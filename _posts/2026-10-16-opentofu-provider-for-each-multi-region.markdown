---
layout: post
title: 'One module block, every region: provider for_each in OpenTofu'
date: 2026-10-16 11:45:00.00 +02:00
tag: ["DevOps", "OpenTofu", "Terraform", "IaC", "AWS"]
category: DevOps
---

Here is a thing I wish somebody had shown me the week OpenTofu 1.9 came out. If you have ever had to deploy the same
stack to five AWS regions, you know the ritual: five `provider "aws"` blocks with five aliases, five copies of the
`module` block differing only in the `providers` map, and a bad feeling every time a sixth region shows up. In OpenTofu
you can put `for_each` on the provider block itself. One provider block, one module block, regions come from a
variable. Terraform still cannot do this.
<!--more-->

## The old way, for contrast

This is what multi-region looked like in every repo I have worked in:

```hcl
provider "aws" {
  alias  = "frankfurt"
  region = "eu-central-1"
}

provider "aws" {
  alias  = "ireland"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

module "dns_firewall_frankfurt" {
  source    = "./modules/dns-firewall"
  providers = { aws = aws.frankfurt }
  vpc_id    = var.vpc_ids["eu-central-1"]
}

module "dns_firewall_ireland" {
  source    = "./modules/dns-firewall"
  providers = { aws = aws.ireland }
  vpc_id    = var.vpc_ids["eu-west-1"]
}

module "dns_firewall_virginia" {
  source    = "./modules/dns-firewall"
  providers = { aws = aws.virginia }
  vpc_id    = var.vpc_ids["us-east-1"]
}
```

Three regions, and already nobody wants to touch it. People reach for templating (`cookiecutter`, a Python script
spitting out `.tf` files, Terragrunt) and now the infrastructure code has a build step. All of that because `provider`
blocks could not be iterated.

## The OpenTofu way

Since OpenTofu 1.9:

```hcl
variable "regions" {
  type    = set(string)
  default = ["eu-central-1", "eu-west-1", "us-east-1"]
}

variable "vpc_ids" {
  type = map(string)
}

provider "aws" {
  alias    = "by_region"
  for_each = var.regions
  region   = each.value
}

module "dns_firewall" {
  source   = "./modules/dns-firewall"
  for_each = var.regions

  providers = {
    aws = aws.by_region[each.key]
  }

  vpc_id = var.vpc_ids[each.key]
}
```

That is the whole trick. `aws.by_region` is now a map of provider instances keyed by region, and `aws.by_region[each.key]`
hands the right one to each module instance. Adding a region is adding a string to a set. The module code inside
`./modules/dns-firewall` did not change at all, it still just says `provider "aws"` and gets whatever it is given.

It works on resources too, not only modules, in case you do not want a module for a three-resource thing:

```hcl
resource "aws_cloudwatch_log_group" "dns_firewall" {
  for_each = var.regions
  provider = aws.by_region[each.key]

  name              = "/aws/route53resolver/dns-firewall"
  retention_in_days = 30
}
```

## Why this was impossible before: early evaluation

The reason Terraform never did this is not laziness, it is the evaluation model. Provider configuration has to be known
before the graph is built, because providers are what the graph talks to. Anything in a provider block had to be a
literal or a variable with no dependencies.

OpenTofu 1.8 introduced what the docs call early evaluation (you will also see "static evaluation"): variables and
locals that can be resolved before the graph exists are allowed in places that used to be literal-only. Provider
`for_each` in 1.9 is built on top of it. The same mechanism gives you two other things advanced users have been asking
for since roughly 2015:

```hcl
# a variable in the backend config
terraform {
  backend "s3" {
    bucket = var.state_bucket
    key    = "dns-firewall/${var.environment}.tfstate"
    region = "eu-central-1"
  }
}

# a variable in a module source
module "dns_firewall" {
  source = "git::https://github.com/example/tofu-modules.git//dns-firewall?ref=${var.modules_ref}"
  # ...
}
```

The rule to remember: the value has to be knowable without talking to any provider. Variables, locals built from
variables, functions on those - fine. Anything that comes out of a `data` source or a `resource` - no, and OpenTofu
tells you so at plan time, not with a cryptic error halfway through apply.

## The gotcha, and the pattern that avoids it

There is one sharp edge, and it is the same one aliased providers always had, just easier to hit now. Say you remove
`us-east-1` from `var.regions`. OpenTofu now wants to destroy `module.dns_firewall["us-east-1"]`, but the provider
instance `aws.by_region["us-east-1"]` is gone from the configuration too, and you cannot destroy a resource without the
provider that created it. Plan fails.

The fix is to decouple the two sets. Providers iterate over every region you could ever have, modules iterate over the
ones you actually want right now:

```hcl
locals {
  # every region this account is ever allowed to touch
  all_regions = ["eu-central-1", "eu-west-1", "eu-north-1", "us-east-1", "us-west-2"]
}

variable "active_regions" {
  type    = set(string)
  default = ["eu-central-1", "eu-west-1"]
}

provider "aws" {
  alias    = "by_region"
  for_each = toset(local.all_regions)
  region   = each.value
}

module "dns_firewall" {
  source   = "./modules/dns-firewall"
  for_each = var.active_regions
  providers = { aws = aws.by_region[each.key] }
  vpc_id   = var.vpc_ids[each.key]
}
```

Now removing a region from `active_regions` produces a clean destroy, because the provider instance for it still
exists. An unused provider instance costs nothing, it is just configuration. Add a `validation` block on
`active_regions` checking `setsubtract(var.active_regions, local.all_regions)` is empty if you want a friendlier error
than the one OpenTofu gives for a missing map key.

## Two small bonuses

Since the module instances are keyed by region, you can do one region at a time without touching the code.
OpenTofu 1.9 also added `-exclude`, the mirror image of `-target`:

```sh
# roll out only Frankfurt first
tofu apply -target='module.dns_firewall["eu-central-1"]'

# everything except Virginia, which is in the middle of an incident
tofu apply -exclude='module.dns_firewall["us-east-1"]'
```

And because the region is `each.key`, your outputs come out as a map for free:

```hcl
output "rule_group_ids" {
  value = { for region, m in module.dns_firewall : region => m.rule_group_id }
}
```

## Should you migrate existing code to this?

If you have the five-copies setup and it works, the honest answer is: only when you touch it next. The addresses change
from `module.dns_firewall_frankfurt` to `module.dns_firewall["eu-central-1"]`, so you need a `moved` block per region
or a state move, which is a chore but a one-time one. For anything new, I do not see a reason to write the old pattern
ever again. Requires OpenTofu 1.9 or newer, and the provider itself does not have to know or care.
