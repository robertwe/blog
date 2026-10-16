---
layout: post
title: 'Testing an OpenTofu module without an AWS account: tofu test and mock_provider'
date: 2026-11-06 22:00:00.00 +01:00
tag: ["DevOps", "OpenTofu", "Terraform", "IaC", "Testing", "AWS"]
category: DevOps
---

In July I published a [DNS Firewall module]({% post_url 2026-07-22-route53-resolver-dns-firewall-blocklist-opentofu %})
and admitted that "tested" meant "applied it once and looked". That is how most infrastructure modules are tested, and it
is why module refactors are scary. OpenTofu has had `tofu test` since 1.6 and provider mocking since 1.8, which
together let you assert what a module does - how many rules it creates, that the action is `BLOCK`, that the wildcard
gets added - without credentials, without a VPC, in a few seconds, in CI. Here is that module with real tests.
<!--more-->

## The shape of a test

Tests live in `tests/*.tftest.hcl` next to the module. Each file has `run` blocks, each `run` does a plan or an apply
of the module with some variables and then checks `assert` conditions:

```hcl
# tests/blocklist.tftest.hcl

run "adds_wildcard_for_every_domain" {
  command = plan

  variables {
    vpc_id          = "vpc-0123456789abcdef0"
    blocked_domains = ["evil-domain.com", "definitely-not-crypto-mining.io"]
  }

  assert {
    condition     = length(aws_route53_resolver_firewall_domain_list.blocklist.domains) == 4
    error_message = "expected 2 domains + 2 wildcards, got ${length(aws_route53_resolver_firewall_domain_list.blocklist.domains)}"
  }

  assert {
    condition     = contains(aws_route53_resolver_firewall_domain_list.blocklist.domains, "*.evil-domain.com")
    error_message = "wildcard entry for evil-domain.com is missing"
  }
}
```

`command = plan` is the fast path. The module is planned, not applied, so anything that is known at plan time - which
is most of what you would want to assert about your own logic - can be checked. Run it with `tofu test` from the
module directory.

Even this much, with no mocking at all, already needs valid AWS credentials, because the provider is configured and
some resources make API calls during plan. Which brings us to the point of this post.

## mock_provider: no credentials, no API

Add a `mock_provider` block to the test file and the real AWS provider is never initialised:

```hcl
mock_provider "aws" {}

run "adds_wildcard_for_every_domain" {
  command = plan
  # ... same as above
}
```

Every resource and data source of the mocked provider now returns made-up values for computed attributes: random
strings for IDs and ARNs, and whatever you set in the configuration for the rest. No network, no `AWS_PROFILE`, runs
on a laptop on a plane and in a GitHub Actions job with no secrets.

The made-up values are fine until a resource depends on a *specific* shape of a computed value. The rule group
association needs the rule group's `id`, and a random string works for that. But if your module has a
`regex()` on an ARN, random garbage will not match. For those cases you tell the mock what to return:

```hcl
mock_provider "aws" {
  mock_resource "aws_route53_resolver_firewall_rule_group" {
    defaults = {
      id  = "rslvr-frg-0123456789abcdef0"
      arn = "arn:aws:route53resolver:eu-central-1:123456789012:firewall-rule-group/rslvr-frg-0123456789abcdef0"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}
```

`mock_resource` and `mock_data` set defaults per type. If you need a specific *instance* to return something, there
is `override_resource` with a `target`, usable both inside `mock_provider` and at the top level of a `run` block.

## command = apply, still without an account

With a mock provider you can also run `command = apply`. Nothing is created anywhere, the "apply" runs against the
mock, but now attributes that are only known after apply are populated, so you can assert on outputs:

```hcl
run "exposes_rule_group_id" {
  command = apply

  variables {
    vpc_id          = "vpc-0123456789abcdef0"
    blocked_domains = ["evil-domain.com"]
  }

  assert {
    condition     = startswith(output.rule_group_id, "rslvr-frg-")
    error_message = "rule_group_id output should be the firewall rule group id"
  }
}
```

This is the part that made the whole thing click for me. Apply-mode tests against a mock are what unit tests are for
application code: fast, deterministic, no external state, and they catch the "I renamed the resource and forgot the
output" class of bug immediately.

## Testing that invalid input is rejected

The module has a validation block saying domains must not start with `*.` (the module adds wildcards itself). Test
that the validation fires with `expect_failures`:

```hcl
run "rejects_explicit_wildcards" {
  command = plan

  variables {
    vpc_id          = "vpc-0123456789abcdef0"
    blocked_domains = ["*.evil-domain.com"]
  }

  expect_failures = [
    var.blocked_domains,
  ]
}
```

The run passes only if that variable's validation fails. If someone deletes the validation block, this test goes red.

## Fixtures: a run block that sets things up

Sometimes a module needs an input that another module produces, a VPC for example. A `run` block can execute a
different module and later runs can use its outputs:

```hcl
run "setup" {
  module {
    source = "./tests/fixtures/vpc"
  }
}

run "attaches_to_the_vpc" {
  command = plan

  variables {
    vpc_id          = run.setup.vpc_id
    blocked_domains = ["evil-domain.com"]
  }

  assert {
    condition     = aws_route53_resolver_firewall_rule_group_association.vpc.vpc_id == run.setup.vpc_id
    error_message = "association should target the fixture VPC"
  }
}
```

With a mock provider the fixture is also mocked, so it is still free. Against a real provider this is how you would do
an integration test: real VPC up, module applied, assertions, everything destroyed at the end of the file - `tofu test`
destroys what apply-mode runs created, in reverse order, even when an assertion fails.

## In CI

```yaml
- uses: opentofu/setup-opentofu@v1
- run: tofu init -backend=false
- run: tofu test
  working-directory: modules/dns-firewall
```

No AWS credentials in that job. The real-provider integration tests, if you have them, go in a separate workflow
that runs on a schedule or on merge to main, with OIDC credentials, against a sandbox account.

## What I would and would not test

Worth testing: your own logic - the `for` expressions, the `locals`, the conditionals, the validations, the outputs.
That is where the bugs are and that is what mocks cover perfectly.

Not worth testing with mocks: whether AWS accepts the configuration. A mock will happily "create" a rule with
`action = "EXPLODE"`. For that you need the real provider, and one scheduled integration run is enough. The two layers
together, mocked unit tests on every PR and a real apply nightly, is the first setup in years that made me stop
being nervous about touching a shared module.
