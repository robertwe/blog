---
layout: post
title: 'State surgery without the CLI: import, moved and removed blocks with for_each'
date: 2026-10-16 12:30:00.00 +02:00
tag: ["DevOps", "OpenTofu", "Terraform", "IaC"]
category: DevOps
---

For about eight years, changing what is in the state meant typing `terraform state mv` and `terraform import` by hand,
one resource at a time, in the right order, hoping nobody else ran an apply in between. Those commands still exist, but
you should mostly stop using them. There are three declarative blocks - `import`, `moved`, `removed` - that do the same
thing from code, show up in the plan, go through code review, and since they accept `for_each` they handle fifty
resources as easily as one. This is in both OpenTofu and Terraform (since 1.7 on both sides), so unlike my last two
posts this is not a "Tofu only" trick - it is a "most people still don't use it" trick.
<!--more-->

## import: adopt existing infrastructure, in bulk

Somebody created twelve security groups in the console in 2019 and you are finally bringing them under management.
The old way is twelve `tofu import` commands with twelve copy-pasted IDs. The new way:

```hcl
variable "legacy_sgs" {
  type = map(string)
  default = {
    web      = "sg-0a1b2c3d4e5f60001"
    api      = "sg-0a1b2c3d4e5f60002"
    database = "sg-0a1b2c3d4e5f60003"
    # ... nine more
  }
}

import {
  for_each = var.legacy_sgs
  to       = aws_security_group.legacy[each.key]
  id       = each.value
}

resource "aws_security_group" "legacy" {
  for_each = var.legacy_sgs
  # ... attributes matching what exists
}
```

`tofu plan` now shows twelve "will be imported" lines next to any real changes. The import happens during `apply`,
in the same run, under the same state lock. No separate step, no window where the state and the code disagree.

And you do not have to write the twelve resource bodies by hand either:

```sh
tofu plan -generate-config-out=legacy_sgs.tf
```

OpenTofu reads the real objects and writes a `.tf` file with their current attributes. The generated code is verbose
and you will want to trim it (it writes every attribute, including defaults), but it beats reconstructing a security
group from the console. Note that `-generate-config-out` only works for `import` blocks without `for_each` at the
moment, so for bulk work generate once with a single block, turn it into a `for_each` resource yourself, and then
switch the import block to `for_each`.

Once the apply is done, delete the `import` block. It has done its job and leaving it in produces a warning on every
plan.

## moved: rename and restructure without destroy/create

Every refactor that changes a resource address - renaming, wrapping in a module, going from `count` to `for_each` -
used to mean a destroy and a recreate unless you remembered `state mv`. The `moved` block makes the refactor and the
state change one commit:

```hcl
# was: resource "aws_instance" "bastion" with count = 1
# now: module "bastion" with for_each over environments

moved {
  from = aws_instance.bastion[0]
  to   = module.bastion["prod"].aws_instance.this
}
```

`moved` does not take `for_each`, each move is explicit, but you can list as many as you need and they can chain
(A moved to B in one release, B moved to C in the next, both blocks stay and OpenTofu follows the trail). It is the
block I use most often and the one that has saved the most production instances from an accidental recreate. Keep
`moved` blocks around for a few releases, then clean them up once you are sure every environment has applied them.

## removed: forget a resource without destroying it

The opposite of import. You want OpenTofu to stop managing something but keep the thing itself - handing a bucket over
to another team's state, or a resource you are going to manage with a different tool. Previously: `tofu state rm`,
which is a direct state edit with no plan and no review. Now:

```hcl
removed {
  from = aws_s3_bucket.handed_over

  lifecycle {
    destroy = false
  }
}
```

With `destroy = false` the plan says "will no longer be managed" and the bucket stays. Without it, `removed` behaves
like deleting the resource block, which is to say it destroys. That default surprises people, so I would make a habit
of always writing the lifecycle block, even when destroy is what you want, so the intent is in the diff.

`removed` also does not take `for_each`, but `from` can point at a whole resource including all its instances
(`from = aws_s3_bucket.handed_over` covers every `[key]`), and at a module (`from = module.legacy`), which in practice
covers the bulk cases.

## Putting it together: the three-step refactor

A pattern that comes up constantly - a module that was copy-pasted per environment gets collapsed into one
`for_each` module. The sequence that works, all in code, all in review:

```hcl
# 1. new shape
module "app" {
  for_each = toset(["dev", "staging", "prod"])
  source   = "./modules/app"
  env      = each.key
}

# 2. moves from the old addresses
moved {
  from = module.app_dev
  to   = module.app["dev"]
}
moved {
  from = module.app_staging
  to   = module.app["staging"]
}
moved {
  from = module.app_prod
  to   = module.app["prod"]
}

# 3. adopt the one thing that was never in state
import {
  to = module.app["prod"].aws_cloudwatch_log_group.this
  id = "/aws/app/prod"
}
```

Plan shows three moves and one import and zero destroys. If it shows a destroy, you got an address wrong, and you find
that out before anything happens rather than after.

## What the CLI is still for

`tofu state mv`, `rm`, `import` are not deprecated and they are still the right tool for emergency surgery - a broken
state after an interrupted apply, a one-off fix at 2 a.m. For everything planned, the blocks are strictly better:
they are reviewable, they run under the lock, they are idempotent (applying a `moved` twice is a no-op), and with
`for_each` on `import` they scale. The mental shift is small: state changes are code changes now, and they go
through the same pipeline as everything else.
