---
layout: post
title: 'From Terraform to OpenTofu - why and how we made the switch'
date: 2026-07-21 09:00:00.00 +02:00
tag: ["DevOps", "Terraform", "OpenTofu", "IaC"]
category: DevOps
---

I have been a Terraform user since the early days - I mentioned on this blog years ago that I was an early adopter, and that has not changed.
Infrastructure as Code is simply how I work. But over the last couple of years something important happened in that ecosystem,
and recently I went through a full migration from Terraform to [OpenTofu](https://opentofu.org/) in a few production environments.
In this post I want to share why we did it, how it went, and what surprised me along the way.
<!--more-->

## A bit of history - why OpenTofu even exists

In August 2023 HashiCorp changed the license of Terraform (and their other tools) from the open source MPL 2.0
to the Business Source License (BSL). BSL is a source-available license, not an open source one - it restricts
who can use the software and for what, especially if you build products that compete with HashiCorp's offering.

For most end users nothing changed overnight. But the community reaction was strong, and for a good reason:
a huge ecosystem of modules, providers and tooling was built over the years on the assumption that Terraform is
and will stay open source. In response, a group of companies and individuals created a fork of the last MPL-licensed
Terraform (1.5.x) called OpenTofu, which was quickly adopted by the Linux Foundation. That gives it neutral,
community-driven governance - no single vendor can pull the same license move again.

Since then OpenTofu has been shipping releases at a solid pace, and it is not just a passive fork anymore.
It has features that Terraform does not have, like native state encryption - something people were asking
HashiCorp for literally for years.

## Why we decided to migrate

I will not name the companies I have been working with, but the motivation was pretty similar everywhere:

  - **License risk** - legal departments do not like "source available" licenses with vague boundaries.
    Even if you are 99% sure your use case is fine, that 1% is an unnecessary risk. Open source under
    the Linux Foundation umbrella is a much easier conversation,
  - **State encryption** - with OpenTofu 1.7+ you can encrypt the state file itself. Terraform state
    contains secrets in plain text (yes, still, in 2026) and until now the only protection was encryption
    at rest on the backend side. Client-side state encryption is a real security improvement,
  - **Cost** - some teams were evaluating Terraform Cloud/HCP pricing and did not like where it was going.
    OpenTofu keeps the classic open workflow: your state backend, your CI, your rules,
  - **No vendor lock-in on the tool itself** - the whole point of IaC is control and repeatability.
    Having the core tool governed by a foundation instead of a single vendor fits that philosophy.

## The migration itself - honestly, it is boring (and that is great)

This was the biggest surprise. I expected a painful multi-week project. In reality, for a codebase
that was on Terraform 1.5.x, the migration is almost a non-event, because OpenTofu started as a
drop-in replacement.

The whole process looks like this:

**1. Install OpenTofu**

```sh
# macOS
brew install opentofu

# or via the installer script
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method deb
```

**2. Take a state backup first**

I do not care how confident you are - back up your state before touching anything:

```sh
terraform state pull > backup-$(date +%F).tfstate
```

**3. Re-initialize with tofu**

```sh
tofu init
```

That is it for the core switch. `tofu init` downloads providers from the OpenTofu registry
(`registry.opentofu.org`), which mirrors the providers you already use. The state format is compatible,
so `tofu plan` right after the init should show **no changes**. If it does not - stop and investigate,
do not apply.

**4. Verify with a plan on every workspace/environment**

```sh
tofu plan -detailed-exitcode
```

We ran this across all environments before letting anyone apply anything. Exit code `0` everywhere means
you are done with the risky part.

**5. Update your CI/CD pipelines**

This was actually most of the work - not because it is hard, but because pipelines are everywhere.
Mostly it boils down to replacing the binary and the setup step, e.g. in GitHub Actions:

```yaml
- uses: opentofu/setup-opentofu@v1
  with:
    tofu_version: 1.10.0

- run: tofu init -input=false
- run: tofu plan -input=false
```

Tools around the ecosystem (Atlantis, Terragrunt, pre-commit hooks, tflint, checkov, infracost) all
support OpenTofu these days, usually via a single configuration switch.

**6. Pin the version**

Same discipline as with Terraform - pin it:

```hcl
terraform {
  required_version = ">= 1.10.0"
}
```

Yes, the block is still called `terraform` - OpenTofu kept it for compatibility, and I think that was
the right call.

## The nice bonus - state encryption

This alone justified the migration for one security-conscious team. Example configuration with an AWS KMS key:

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "main" {
      kms_key_id = "arn:aws:kms:eu-west-1:111111111111:key/xxxx"
      key_spec   = "AES_256"
    }

    method "aes_gcm" "main" {
      keys = key_provider.aws_kms.main
    }

    state {
      method = method.aes_gcm.main
    }
  }
}
```

From that moment your state file is encrypted client-side before it ever reaches the backend.
Anyone who ever had to explain to a security auditor why there are database passwords in plain text
in an S3 bucket will appreciate this.

## Gotchas we hit

Nothing dramatic, but worth mentioning:

  - **Do the migration from Terraform <= 1.5.x if you can.** If your code already uses features from
    newer Terraform versions (post-fork), check the OpenTofu migration guide - the projects have started
    to diverge and a few features have different implementations,
  - **Provider versions** - the OpenTofu registry mirrors providers, but re-check your lock file
    (`.terraform.lock.hcl`) after init. We regenerated it cleanly with `tofu providers lock`,
  - **Muscle memory** - the amount of times I typed `terraform plan` in the first two weeks... a shell
    alias helps: `alias terraform=tofu`,
  - **Documentation drift** - internal runbooks and READMEs mention `terraform` everywhere. A boring
    find-and-replace task, but if you skip it, new team members will happily install Terraform again.

## Verdict

The migration was one of those rare infrastructure changes where the risk/benefit ratio is clearly positive:
a day or two of work (mostly CI plumbing and verification), and in return you get an actually open source tool,
community governance, state encryption and no license anxiety. After several months in production across
multiple environments I have not hit a single issue that I could attribute to OpenTofu itself.

If you are still on Terraform 1.5.x and wondering whether to move - in my opinion the answer is yes,
and the best moment is now, while the drop-in compatibility window is still wide open.

--
cheers
