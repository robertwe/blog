---
layout: post
title: 'Blocking egress to specific domains from an EKS cluster - what are the options?'
date: 2026-07-22 21:00:00.00 +02:00
tag: ["DevOps", "AWS", "EKS", "Kubernetes", "Security", "Networking"]
category: DevOps
---

A seemingly simple requirement: "pods in our EKS cluster must not be able to talk to `evil-domain.com`"
(or the reverse - "must only be able to talk to an allowlist of domains"). Simple to say, surprisingly
annoying to implement, because classic AWS network controls - security groups, NACLs - speak IP, not DNS.
A domain can resolve to hundreds of rotating IPs behind a CDN, so blocking by IP is a losing game.
Here is a rundown of the options that actually work with FQDNs, and what each one really gives you.
<!--more-->

## Why security groups and NACLs are out

Just to get it off the table: security groups and network ACLs only accept CIDRs (or other SGs / prefix
lists). There is no field to type `*.evil-domain.com` into. You could resolve the domain periodically and
sync the IPs into a prefix list with a Lambda, and people do build that - but for anything behind
CloudFront/Cloudflare/Akamai the IP set changes constantly and is shared with thousands of other sites,
so you either block too much or too little. Don't build that. Use one of the tools below that was
actually designed for the job.

## Option 1 - Route 53 Resolver DNS Firewall

The cheapest and simplest entry point. DNS Firewall sits in front of the VPC resolver (the `.2` resolver
that every VPC gets), and lets you attach rule groups to a VPC with domain lists:

  - **BLOCK** - the query for `evil-domain.com` returns NXDOMAIN, NODATA, or an OVERRIDE record you define
    (nice trick: override to a sinkhole/honeypot IP and alert on whoever hits it),
  - **ALERT** - resolve normally but log the query,
  - **ALLOW** - used to build allowlist setups: allow `*.mycompany.com`, `*.amazonaws.com`, block `*`.

Setup is pure Terraform/OpenTofu, no infrastructure changes, no re-routing, works instantly for the
whole VPC - which means the whole EKS cluster, since pods (with the default VPC CNI + CoreDNS setup)
ultimately forward queries to the VPC resolver.

The catch is fundamental though: **it only filters DNS resolution, not traffic**. If a pod already knows
the IP, or ships its own DNS-over-HTTPS client, or just uses `8.8.8.8` directly, DNS Firewall never sees
the query and the connection goes through. It's a seatbelt against accidental/lazy egress, not against
a determined adversary. Pair it with a NACL/SG rule blocking outbound `53` to anything except the VPC
resolver and you close the "just use another resolver" hole - but the "connect straight to the IP" hole
stays open by design.

Pricing is per rule group association + per million queries, typically pocket change compared to the
next option.

## Option 2 - AWS Network Firewall

The heavyweight. AWS Network Firewall is a managed stateful firewall you insert into the *packet path* -
traffic from your private subnets gets routed through firewall endpoints (usually placed in dedicated
firewall subnets between your NAT gateway and the internet gateway, or in an inspection VPC in a hub-and-spoke
setup with Transit Gateway).

Because it sees actual packets, it can block domains regardless of how they were resolved:

  - for **HTTPS** it matches the **SNI** in the TLS ClientHello (`tls.sni` in Suricata rule terms),
  - for **HTTP** it matches the **Host header**,
  - rules can be written as simple "domain list" rule groups (`.evil-domain.com` denylist or an allowlist)
    or as full Suricata-compatible IPS rules if you need more,

So even a pod that hardcodes the IP still gets caught, because the TLS handshake announces the hostname.
The remaining bypass is a client that uses encrypted ClientHello (ECH) or no SNI at all - rarer, and you
can just drop no-SNI traffic in a strict setup.

The price you pay, literally: ~$0.395/h per firewall endpoint plus data processing per GB, and you want
an endpoint per AZ. That's roughly $300/month per AZ before traffic costs, plus the routing surgery on
your VPC (firewall subnets, route table changes for IGW/NAT paths). For a compliance-driven environment
this is the "proper" answer; for "I just want to block one domain" it's a lot of machinery.

One EKS-specific note: Network Firewall sees traffic *after* SNAT through the NAT gateway (or with the
node's IP), so rules are per-VPC/subnet, not per-pod. You can't say "only the payments namespace can
reach api.stripe.com" with it - that granularity lives one layer down, in the cluster itself.

## Option 3 - FQDN-aware network policies in the cluster

Standard Kubernetes `NetworkPolicy` (including what the AWS VPC CNI enforces natively on EKS) is also
IP/label-based - no FQDN field, same problem as security groups. But CNIs with extended policy engines
do support DNS-based egress rules:

  - **Cilium** - a word about it first, because this is not just another CNI plugin. Cilium is an
    eBPF-based networking stack for Kubernetes (a CNCF *graduated* project, same status as Kubernetes
    itself, and the default data plane in GKE and in EKS-Anywhere). Instead of iptables chains it loads
    eBPF programs directly into the kernel, which is what makes things like identity-aware L7 policies,
    kube-proxy replacement and the Hubble observability layer possible - and it's exactly this
    architecture that enables the DNS-aware policies below. On EKS you can run it on top of the VPC CNI
    (chaining mode) or as a full replacement for it.

    For our problem the interesting piece is `CiliumNetworkPolicy` with `toFQDNs`. Cilium's agent snoops DNS responses (you add a
    `rules.dns` section so it proxies/observes DNS), builds an IP↔name mapping per pod, and enforces
    egress against the *names*:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-stripe-only
  namespace: payments
spec:
  endpointSelector: {}
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*"
    - toFQDNs:
        - matchName: "api.stripe.com"
```

  - **Calico Enterprise / Calico Cloud** - `GlobalNetworkPolicy` with domain names in egress rules
    (note: this is the paid tier; open-source Calico doesn't do FQDN policies).

This is the only option that gives you **per-namespace / per-pod granularity** - "this workload may talk
to exactly these three domains" - which neither DNS Firewall nor Network Firewall can express. It's also
free (with Cilium) and doesn't touch VPC routing.

The trade-offs: you're changing (or configuring around) the cluster CNI, which on an existing EKS cluster
running the VPC CNI is not a small decision - Cilium can run in chaining mode or replace the VPC CNI
entirely, both need testing. And enforcement is DNS-snooping based: like DNS Firewall, a pod that never
does a DNS lookup the agent can see (hardcoded IP) is enforced only by whatever IP/CIDR rules remain -
the default-deny that `toFQDNs` policies imply is what saves you there.

## Option 4 - an egress proxy

The old-school answer that still works: run Squid/Envoy (or use a managed egress-proxy service) in the
VPC, allow outbound traffic *only* from the proxy (SG on the NAT path / no default route for pod subnets),
and point workloads at it via `HTTP_PROXY`/`HTTPS_PROXY`. The proxy filters by hostname from the CONNECT
request, logs everything, and can even do TLS inspection if you go down the MITM-CA rabbit hole.

It gives you great logs and hostname-level control without touching the CNI or paying for Network
Firewall - but it's explicit-proxy based, so every workload must cooperate (env vars, or an istio-style
transparent redirect), and non-HTTP protocols need extra care. In Kubernetes-land, a service mesh
(Istio/Cilium's Envoy) with an egress gateway is the modern spelling of the same idea.

## So which one?

  - **"Stop developers/pods from accidentally reaching known-bad or unsanctioned domains, cheaply"** →
    Route 53 DNS Firewall + block outbound 53 to non-VPC resolvers. An afternoon of work.
  - **"Compliance says all egress must be inspected and enforced on the wire"** →
    AWS Network Firewall with a domain allowlist on SNI/Host. Budget for it.
  - **"Different workloads need different egress allowlists"** →
    Cilium `toFQDNs` policies (or Calico Enterprise). Only option with pod-level granularity.
  - **"We want full visibility of every egress request"** →
    egress proxy / egress gateway.

They also compose: DNS Firewall as the cheap VPC-wide baseline plus Cilium policies for the sensitive
namespaces is a very reasonable combination - defence in depth without the Network Firewall bill. And
whatever you pick, remember the golden rule of egress filtering: **denylists rot, allowlists work**.
If you can enumerate what your workloads legitimately talk to, flip the model to default-deny and
allow only that.

--
cheers
