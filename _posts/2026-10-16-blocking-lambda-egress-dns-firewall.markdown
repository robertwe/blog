---
layout: post
title: 'Blocking egress from Lambda: the sequel to the EKS post'
date: 2026-10-16 13:30:00.00 +02:00
tag: ["DevOps", "AWS", "Lambda", "Security", "Networking", "OpenTofu"]
category: DevOps
---

After the [EKS egress post]({% post_url 2026-07-22-blocking-egress-fqdns-on-eks %}) the first question I got was
"and what about Lambda?". Fair. A lot of the Python glue I write runs as Lambda functions, those functions call
third-party APIs, and the supply-chain argument is identical: a compromised dependency in a function has the same
unrestricted internet access as one in a pod. The answer is mostly the same tool, Route 53 Resolver DNS Firewall,
with one big catch that changes the economics.
<!--more-->

## The catch: a Lambda outside a VPC is invisible to you

By default a Lambda function does not run in your VPC. It runs in an AWS-managed network with direct internet
access, uses an AWS-managed resolver, and none of your VPC controls - security groups, NACLs, DNS Firewall, Network
Firewall - apply to it. There is nothing to attach a rule to. For egress control, a function has to be in a VPC. Period.

Putting it there is one block:

```hcl
resource "aws_lambda_function" "worker" {
  function_name = "worker"
  role          = aws_iam_role.worker.arn
  runtime       = "python3.12"
  handler       = "app.handler"
  filename      = data.archive_file.worker.output_path

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.worker.id]
  }
}
```

The function now gets elastic network interfaces in your private subnets, resolves DNS through the VPC resolver
(the `.2` address), and goes through your route tables. Which means two things.

## Thing one: you now pay for a NAT

A function in a private subnet has no internet route unless the subnet has a NAT Gateway. If the function needs to
reach the internet at all, you need one, and a NAT Gateway bills per hour and per gigabyte processed, per availability
zone. For a function that previously cost a few cents a month, the NAT is now the dominant line item, in the tens of
dollars a month before any traffic. That is the real price of egress control on Lambda, and it is why many teams do
not do it.

Three ways to keep it reasonable:

- **One NAT, not one per AZ**, for non-critical functions. You lose AZ-independence for egress, you save two thirds.
- **No internet at all** if the function only talks to AWS. S3 and DynamoDB gateway endpoints are free; interface
  endpoints for other services cost per hour too, but a handful is still cheaper than a NAT with traffic, and a function
  with no route to the internet is the strongest egress control there is.
- **Share the VPC and NAT** that your EKS cluster already has. If you did the previous post, the DNS Firewall rule
  group is already associated with that VPC, and a function dropped into its private subnets is covered on day one.

## Thing two: DNS Firewall now applies

This is the good part. Because the function uses the VPC resolver, a DNS Firewall rule group associated with the VPC
filters its DNS queries exactly like it filters a pod's. The [module from the previous post]({% post_url 2026-07-22-route53-resolver-dns-firewall-blocklist-opentofu %})
needs no change:

```hcl
module "dns_firewall" {
  source = "./modules/dns-firewall"

  vpc_id = var.vpc_id
  blocked_domains = [
    "evil-domain.com",
    "definitely-not-crypto-mining.io",
  ]
  enable_query_logging = true
}
```

Or, if you prefer an allowlist for a function whose destinations are known - which for a Lambda is usually the case,
it calls two APIs and that is it - flip it around: a rule that `ALLOW`s your known domains with a low priority number,
then a rule that `BLOCK`s `*` after it. The previous post has both patterns.

## Seeing what a function is trying to reach

Resolver query logging, pointed at a CloudWatch log group, is how you find out what to allow before you turn the
block on. Each log line has the query name, the source IP and the firewall action:

```
fields @timestamp, srcaddr, query_name, firewall_rule_action
| filter firewall_rule_action = "BLOCK"
| stats count() by query_name, srcaddr
| sort count desc
```

`srcaddr` is the private IP of the function's ENI. To map it back to a function, `aws ec2 describe-network-interfaces`
with that IP returns an interface whose description starts with `AWS Lambda VPC ENI` and names the function. Not
elegant, but you only do it while building the allowlist.

Run with `firewall_rule_action = "ALERT"` for a week first - the rule logs instead of blocking - then switch the rule to
`BLOCK`. A function that silently fails because its licence-check domain got blocked is a bad Monday.

## What DNS Firewall does not catch, again

Same limitation as for EKS: it filters DNS resolution, not packets. Code that connects to a hardcoded IP, or that
resolves through its own DNS-over-HTTPS client, never asks the VPC resolver. For most third-party Python packages that
is a theoretical problem - they use `requests`, `requests` uses the system resolver - but for a function processing
untrusted input, it is a real one. The next step up is AWS Network Firewall with domain-based stateful rules, which
inspects the SNI in the TLS handshake and so works on the connection itself. It is also an order of magnitude more
expensive than DNS Firewall, so for Lambda I would only reach for it when the VPC already has one.

## The checklist I use now

1. Does the function need the internet at all? If not: VPC, private subnets, gateway endpoints, no NAT. Done, and
   it is free.
2. If yes: VPC with existing NAT where possible, DNS Firewall rule group associated, query logging on.
3. One week in `ALERT`, read the logs, write the allowlist.
4. Switch to `BLOCK`, add a CloudWatch alarm on the count of blocked queries so a new dependency phoning home shows
   up as a page instead of a surprise.

Compared to the EKS version this is less work, because there is no cluster DNS layer in between, and more expensive,
because of the NAT. Whether that trade is worth it depends entirely on what the function processes. For the one that
parses attachments from a public inbox, yes. For the one that rotates a tag on a snapshot once a night, I leave it
outside the VPC and sleep fine.
