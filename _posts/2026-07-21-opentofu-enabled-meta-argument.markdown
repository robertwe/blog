---
layout: post
title: 'OpenTofu''s enabled meta-argument - conditional resources without the count hack'
date: 2026-07-21 21:00:00.00 +02:00
tag: ["DevOps", "OpenTofu", "Terraform", "IaC"]
category: DevOps
---

In my [previous post]({% post_url 2026-07-21-transition-to-opentofu %}) I wrote about migrating from Terraform to OpenTofu
and I mentioned that OpenTofu is not just a passive fork anymore. Today I want to show you a concrete example of that:
a small feature that removes one of the oldest and ugliest hacks in the Terraform world - conditional resource creation
via `count`. The feature is called `enabled`, it lives in the `lifecycle` block, it shipped in OpenTofu 1.11,
and Terraform simply does not have it.
<!--more-->

## The problem - the count = condition ? 1 : 0 hack

Everyone who has written any serious amount of HCL knows this pattern. You want to create a resource only in some
environments - let's say a bastion host that should exist in dev but not in prod. For years the only way was:

```hcl
variable "create_bastion" {
  type    = bool
  default = false
}

resource "aws_instance" "bastion" {
  count         = var.create_bastion ? 1 : 0
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"
}
```

It works, but look at what it does to the rest of your code. The resource is now a *list* with zero or one element,
so every single reference has to deal with indices:

```hcl
output "bastion_ip" {
  value = var.create_bastion ? aws_instance.bastion[0].public_ip : null
}

resource "aws_route53_record" "bastion" {
  count   = var.create_bastion ? 1 : 0
  name    = "bastion"
  type    = "A"
  ttl     = 300
  records = [aws_instance.bastion[0].public_ip]
  zone_id = var.zone_id
}
```

The `[0]` everywhere, the `one()` calls, the `try()` wrappers, the condition repeated in every dependent resource...
And my favourite part: when you retrofit this pattern onto an already existing resource, the address in the state
changes from `aws_instance.bastion` to `aws_instance.bastion[0]`, so without a `moved` block (or a manual `state mv`)
the plan wants to destroy and recreate your instance. All of that just to express "create this thing or don't".

## The OpenTofu way - lifecycle enabled

Since OpenTofu 1.11 you can write this instead:

```hcl
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  lifecycle {
    enabled = var.create_bastion
  }
}
```

That's it. No list, no indices, no address change. The resource keeps its normal singular address
(`aws_instance.bastion`, not `aws_instance.bastion[0]`), and when it's disabled it simply evaluates to `null`:

```hcl
output "bastion_ip" {
  value = aws_instance.bastion != null ? aws_instance.bastion.public_ip : null
}
```

When you flip `enabled` to `false` on an existing resource, OpenTofu destroys the infrastructure object -
exactly the same as it would with the `count` trick, but declared in a place that actually says what it means.

## Driving it from an environment variable

This is where it gets practical for CI/CD. Since `enabled` takes a regular variable, you can toggle resources
per environment without touching any code, using the standard `TF_VAR_` mechanism:

```sh
# dev pipeline
TF_VAR_create_bastion=true tofu apply

# prod pipeline
TF_VAR_create_bastion=false tofu apply
```

One codebase, one variable, and the dev environment gets its bastion while prod stays clean. No `-target`,
no separate tfvars files if you don't want them, and most importantly - no `[0]` spreading through the module.

## It works on modules too

For me this is actually the bigger deal. The `count` hack on a whole module is even more painful than on
a single resource, because then *every* output reference becomes `module.thing[0].output`. With OpenTofu:

```hcl
module "monitoring" {
  source = "./modules/monitoring"

  lifecycle {
    enabled = var.enable_monitoring
  }
}
```

The whole monitoring stack becomes optional with three lines, and `module.monitoring` stays a singular reference.

## Things to keep in mind

  - `enabled` is mutually exclusive with `count` and `for_each` - it is for the "zero or one" case,
    not for scaling. If you need N copies, `count`/`for_each` are still the right tools,
  - a disabled resource evaluates to `null`, so guard your references with `!= null` checks or `try()` -
    a direct attribute access on a disabled resource is an error,
  - when you *migrate* an existing `count = x ? 1 : 0` resource to `enabled`, the state address changes
    from `foo[0]` back to `foo`, so add a `moved` block for the transition:

```hcl
moved {
  from = aws_instance.bastion[0]
  to   = aws_instance.bastion
}
```

  - and the obvious one: this is OpenTofu 1.11+ only. Terraform does not support it (the corresponding
    feature request has been open on the HashiCorp side for years), so once you start using `enabled`,
    your code is no longer portable back to Terraform. For me that ship has sailed anyway.

## Verdict

It's a small feature, but it removes a hack we have all been copy-pasting for a decade and it makes the
intent readable: "this resource exists only when this flag says so". This is exactly the kind of
quality-of-life improvement I hoped to see when the community took over the project. If you are still
maintaining a pile of `count = var.enabled ? 1 : 0` - this alone might be worth the upgrade to 1.11.

Full details in the [official docs](https://opentofu.org/docs/language/meta-arguments/enabled/).

--
cheers
