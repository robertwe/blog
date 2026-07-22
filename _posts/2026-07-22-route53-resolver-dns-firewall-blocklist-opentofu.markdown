---
layout: post
title: 'Route 53 Resolver DNS Firewall blocklist with OpenTofu - full example'
date: 2026-07-22 23:30:00.00 +02:00
tag: ["DevOps", "AWS", "OpenTofu", "IaC", "Security", "Networking"]
category: DevOps
---

In the [previous post]({% post_url 2026-07-22-blocking-egress-fqdns-on-eks %}) I compared the options for
blocking egress to specific domains from an EKS cluster, and concluded that Route 53 Resolver DNS Firewall
is the cheapest seatbelt you can put on a VPC. Talk is cheap though, so here is the whole thing as working
OpenTofu code: a custom blocklist, the rule group, the VPC association, fail-mode configuration and query
logging so you can actually see what gets blocked. Tested with OpenTofu 1.12.
<!--more-->

## The moving parts

DNS Firewall is four resources stacked on top of each other, and the names are a mouthful:

  1. `aws_route53_resolver_firewall_domain_list` - the list of domains,
  2. `aws_route53_resolver_firewall_rule_group` - a container for rules,
  3. `aws_route53_resolver_firewall_rule` - "for this domain list, do BLOCK/ALERT/ALLOW",
  4. `aws_route53_resolver_firewall_rule_group_association` - attaches the rule group to a VPC.

Everything the VPC resolver (the `.2` address) answers goes through the associated rule groups in priority
order. No routing changes, no agents, applies to every instance and every EKS pod in the VPC immediately.

## Variables

```hcl
variable "vpc_id" {
  type = string
}

variable "blocked_domains" {
  description = "Domains to block, apex only - wildcards are added automatically"
  type        = set(string)
  default = [
    "evil-domain.com",
    "definitely-not-crypto-mining.io",
  ]
}

variable "enable_query_logging" {
  type    = bool
  default = true
}
```

One quirk worth knowing before we start: an entry `evil-domain.com` matches *only* the apex, not
`www.evil-domain.com`. To block a domain and everything under it you need two entries - the apex and the
`*.` wildcard. Nobody wants to maintain that by hand, so a local doubles the list for us:

```hcl
locals {
  # each domain becomes itself + wildcard: evil.com, *.evil.com
  blocked_fqdns = flatten([for d in var.blocked_domains : [d, "*.${d}"]])
}
```

## The blocklist itself

```hcl
terraform {
  required_version = ">= 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

resource "aws_route53_resolver_firewall_domain_list" "blocklist" {
  name    = "egress-blocklist"
  domains = local.blocked_fqdns
}

resource "aws_route53_resolver_firewall_rule_group" "egress" {
  name = "egress-filtering"
}

resource "aws_route53_resolver_firewall_rule" "block" {
  name                    = "block-denied-domains"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.egress.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.blocklist.id
  priority                = 100

  action         = "BLOCK"
  block_response = "NXDOMAIN"
}

resource "aws_route53_resolver_firewall_rule_group_association" "vpc" {
  name                   = "egress-filtering"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.egress.id
  vpc_id                 = var.vpc_id
  priority               = 101
}
```

Notes on the non-obvious bits:

  - `block_response` can be `NXDOMAIN` ("no such domain"), `NODATA` ("domain exists, no such record")
    or `OVERRIDE`. I use NXDOMAIN - it makes clients fail fast instead of retrying other record types,
  - rule `priority` orders rules *within* the group, association `priority` orders rule groups *per VPC* -
    and the association one must be between 100 and 9900 (exclusive). First custom group → 101,
  - `action = "ALERT"` instead of `BLOCK` is the dry-run mode: nothing is blocked, but matches show up
    in the query logs. Roll out with ALERT first, flip to BLOCK when the logs look sane.

## The override variant - sinkholing

Instead of NXDOMAIN you can answer the query with a record you control. Useful if you want to point
blocked domains at an internal page ("this domain is blocked, contact #security") - or a honeypot:

```hcl
resource "aws_route53_resolver_firewall_rule" "sinkhole" {
  name                    = "sinkhole-denied-domains"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.egress.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.blocklist.id
  priority                = 100

  action                  = "BLOCK"
  block_response          = "OVERRIDE"
  block_override_dns_type = "CNAME"
  block_override_domain   = "blocked.internal.example.com"
  block_override_ttl      = 60
}
```

(Use this *or* the plain block rule, not both - one rule per domain list and priority.)

## Fail mode

What happens when DNS Firewall itself has a bad day? By default the resolver **fails open** - if the
firewall can't evaluate a query, the query is answered anyway. For a blocklist that's usually what you
want (availability over filtering), but if your compliance people insist on fail-closed:

```hcl
resource "aws_route53_resolver_firewall_config" "this" {
  resource_id        = var.vpc_id
  firewall_fail_open = "DISABLED" # DISABLED = fail closed
}
```

## Seeing what gets blocked - query logging

A blocklist without logs is a blocklist you'll never be able to debug. Resolver query logging captures
every query in the VPC including the firewall action that was applied. This is also where the previous
post's [OpenTofu enabled meta-argument]({% post_url 2026-07-21-opentofu-enabled-meta-argument %}) earns
its keep - the whole logging stack becomes optional without a single `count` or `[0]`:

```hcl
resource "aws_cloudwatch_log_group" "dns_queries" {
  name              = "/aws/route53-resolver/queries"
  retention_in_days = 30

  lifecycle {
    enabled = var.enable_query_logging
  }
}

resource "aws_route53_resolver_query_log_config" "this" {
  name            = "vpc-dns-queries"
  destination_arn = aws_cloudwatch_log_group.dns_queries.arn

  lifecycle {
    enabled = var.enable_query_logging
  }
}

resource "aws_route53_resolver_query_log_config_association" "vpc" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.this.id
  resource_id                  = var.vpc_id

  lifecycle {
    enabled = var.enable_query_logging
  }
}
```

A blocked query lands in CloudWatch looking like this - `firewall_rule_action` is the field to filter on:

```json
{
  "query_name": "evil-domain.com.",
  "query_type": "A",
  "rcode": "NXDOMAIN",
  "firewall_rule_action": "BLOCK",
  "firewall_rule_group_id": "rslvr-frg-0123456789abcdef",
  "firewall_domain_list_id": "rslvr-fdl-0123456789abcdef"
}
```

## Does it work?

From any instance or pod in the VPC:

```sh
$ dig +short amazon.com
205.251.242.103
54.239.28.85

$ dig evil-domain.com

;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 47017
;; QUESTION SECTION:
;evil-domain.com.               IN      A
```

NXDOMAIN, no packets ever left the VPC. And the same for `www.evil-domain.com`, thanks to the wildcard
entry the local generated.

## Don't forget the side door

As I wrote in the previous post - DNS Firewall only filters queries that go through the VPC resolver.
A pod pointing at `8.8.8.8` walks right past it. Close that hole at the security group / NACL level by
blocking outbound port 53 to anything that isn't the VPC resolver, and the DNS path is sealed. (Direct
connections to hardcoded IPs remain out of scope - that's Network Firewall territory and Network Firewall
pricing.)

Also worth knowing: AWS ships managed domain lists (malware, botnet C2, DGA domains - names like
`AWSManagedDomainsMalwareDomainList`) that you can reference in a rule the same way as your own list.
A custom blocklist for policy plus the managed malware list for hygiene is a solid default combo.

## Verdict

Around sixty lines of HCL, no infrastructure changes, a few dollars a month - and every workload in the
VPC stops resolving domains you've denylisted, with logs to prove it. As seatbelts go, hard to beat.

Full resource reference in the
[provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_firewall_rule_group).

--
cheers
