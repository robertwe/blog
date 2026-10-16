---
layout: post
title: 'GitHub Actions beyond the basics: containers, services, your own runners, dynamic matrices and summaries'
date: 2026-10-17 08:00:00.00 +02:00
tag: ["DevOps", "CI/CD", "GitHub Actions", "Containers", "OpenTofu"]
category: DevOps
---

Most workflows I see are a list of `run:` steps on `ubuntu-latest`, and for most repos that is correct. This post is
about the five features you reach for when that stops being enough: running a job inside a container image, starting
a database next to your tests, bringing your own runners, building the job matrix at run time, and getting plan
output into the PR instead of into a log nobody opens. Each one is a few lines of YAML once you know it exists, and
each one took me longer to find than it should have.
<!--more-->
{% raw %}

## 1. Run the job inside a container

`runs-on` picks the machine, `container` picks the image the steps run in. Everything in `steps` executes inside
that container, with the checkout directory mounted:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: docker.io/library/ruby:3.4
      env:
        BUNDLE_PATH: vendor/bundle
    steps:
      - uses: actions/checkout@v4
      - run: bundle install
      - run: bundle exec jekyll build
```

Why bother, when `setup-ruby` exists? Parity. This blog is built with exactly that job, and the image is the same
one `make build` uses on my laptop. Same Debian, same toolchain, same gem versions. When CI breaks, I run the same
container locally and it breaks the same way.

Things to know before you use it:

- Linux only. `container` is ignored on macOS and Windows runners.
- JavaScript actions (`actions/checkout`, `actions/cache`, most of the marketplace) run with a Node binary GitHub
  mounts into the container. It is linked against glibc, so **Alpine images break them**. Use Debian, Ubuntu or any
  glibc distro.
- The container runs as root unless you say otherwise with `options: --user 1001`. Files it writes into the workspace
  are then root-owned, which matters if a later step outside the container needs them.
- Private registries work with `credentials: { username: ..., password: ${{ secrets.X }} }`.

## 2. Services: a database for your tests, no Docker Compose

`services` starts containers before the steps and tears them down after. Classic use: integration tests against a
real Postgres instead of a mock:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_DB: notes_test
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
      redis:
        image: redis:7
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version-file: go.mod }
      - run: go test ./...
        env:
          DATABASE_URL: postgres://postgres:test@localhost:5432/notes_test?sslmode=disable
          REDIS_ADDR: localhost:6379
```

The `options` block is passed to `docker create`, so anything Docker accepts goes there. The health check is the
part people skip and then wonder why the first test fails: GitHub waits for the service to report healthy before
starting your steps, but only if you define a health check.

Networking depends on where your steps run. If the job is **not** in a container, services are reached on
`localhost` through the mapped `ports`. If the job **is** in a container (section 1), all containers share a network
and you reach the service by its label as hostname, `postgres:5432`, no port mapping needed. Mixing those two up is
the most common reason "connection refused" shows up in a services job.

## 3. Your own runners

Hosted runners are the right default: two cores, seven gigabytes, a fresh VM every job, zero maintenance. You go
self-hosted for one of three reasons: you need hardware GitHub does not offer, you need network access to something
private (a VPC-internal registry, a database, an on-prem system), or you are running enough minutes that the bill
hurts.

Registration is a token from the repo or org settings and one command; the runner then appears with labels and you
target it by label:

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, linux, arm64, prod-vpc]
```

Everything that actually matters about self-hosted runners is operational, not YAML:

- **Never use a persistent self-hosted runner for a public repository.** A pull request from a fork runs the fork's
  code on your machine. GitHub's own docs say this in bold. For public repos, hosted runners only.
- **Prefer ephemeral runners** (`--ephemeral` at registration): one job, then the runner deregisters and the VM or
  pod is thrown away. A long-lived runner accumulates state - caches, credentials in `~/.docker`, leftover
  containers - and every job inherits whatever the previous one left behind.
- **Autoscale on Kubernetes** with the official Actions Runner Controller. The current version installs as a Helm
  chart and creates a `gha-runner-scale-set` per repo or org that scales runner pods from zero to a max you set.
  Each pod is ephemeral by design. If you already run EKS, this is a couple of Helm releases, and the runners get
  pod identity, VPC access and your existing logging for free.
- **Runner groups** at the org level control which repos can use which runners, so the runner that can reach prod
  is not available to the sandbox repo.

The middle option many people miss: GitHub's **larger hosted runners**. Still GitHub-managed, still ephemeral, but
you pick the size (up to 64 cores), can get static egress IPs you can allowlist in a firewall, and arm64 is available.
If your reason for self-hosting was "the default runner is too small" or "I need a known IP", this is cheaper in
engineering time than running your own. The 4-core arm64 runner is free for public repos, which is also the one I
would use for cross-compiling Go.

## 4. Build the matrix at run time

A static `matrix:` is fine when the set is fixed. For a monorepo with a dozen OpenTofu environments, you want "plan
only the environments this PR touched", and the list is only known once you look at the diff. Pattern: one job
discovers, outputs JSON, the next job fans out over it.

```yaml
jobs:
  discover:
    runs-on: ubuntu-latest
    outputs:
      envs: ${{ steps.set.outputs.envs }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - id: set
        run: |
          # directories under envs/ that have changes vs the base branch, as a JSON array
          changed=$(git diff --name-only "origin/${{ github.base_ref }}"...HEAD \
            | grep '^envs/' | cut -d/ -f2 | sort -u | jq -R . | jq -sc .)
          echo "envs=${changed:-[]}" >> "$GITHUB_OUTPUT"

  plan:
    needs: discover
    if: needs.discover.outputs.envs != '[]'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      max-parallel: 3
      matrix:
        env: ${{ fromJSON(needs.discover.outputs.envs) }}
    concurrency:
      group: tofu-${{ matrix.env }}
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - run: tofu init -input=false && tofu plan -input=false -no-color -out=tfplan
        working-directory: envs/${{ matrix.env }}
```

Three details that make this work in practice. `fail-fast: false`, because the default cancels every other
environment the moment one plan fails, which is the opposite of what you want to see in a PR. `max-parallel`,
because twelve simultaneous plans against one AWS account is a good way to meet the API rate limiter.
And `concurrency` keyed on the environment, so two PRs touching `prod` do not fight over the same state lock.

`fromJSON` also accepts objects, so a matrix can carry more than one field per entry (`{"env":"prod","region":"eu-central-1"}`)
and you reference them as `matrix.env` and `matrix.region`.

## 5. Put the result where people look

Nobody reads a 400-line plan in a collapsed log. Two built-in channels get the result into the PR page itself.

**The job summary.** Anything you append to the file at `$GITHUB_STEP_SUMMARY` is rendered as Markdown on the run's
summary page, one block per job:

````yaml
      - name: plan summary
        if: always()
        working-directory: envs/${{ matrix.env }}
        run: |
          {
            echo "## tofu plan: ${{ matrix.env }}"
            echo
            echo '<details><summary>show plan</summary>'
            echo
            echo '```'
            tofu show -no-color tfplan
            echo '```'
            echo '</details>'
          } >> "$GITHUB_STEP_SUMMARY"
````

With the matrix from section 4, the summary page becomes one collapsible plan per changed environment, which is the
review artefact a reviewer actually wants. `if: always()` so a failed plan still gets its error text there.

**Annotations.** A line printed in the special `::error`, `::warning` or `::notice` format becomes an annotation,
shown on the run and, when it names a file and line, inline on the PR diff:

```sh
tofu validate -json | jq -r '
  .diagnostics[] |
  "::\(.severity) file=\(.range.filename),line=\(.range.start.line)::\(.summary): \(.detail)"'
```

That turns `tofu validate` output into red and yellow markers on the exact lines of the exact `.tf` files, without
any marketplace action. The same trick works for anything that can emit file and line: `go vet`, `golangci-lint`
(which has a `--out-format github-actions` for exactly this), `shellcheck -f gcc`.

And for long logs, `::group::name` and `::endgroup::` fold a section of the log so the interesting part is not
buried under forty lines of `tofu init` download noise.

## The two lines every job should have anyway

Not advanced, but missing from most workflows I review, so here they are:

```yaml
permissions:
  contents: read        # at the top: least privilege for GITHUB_TOKEN; add per job what the job needs

jobs:
  anything:
    timeout-minutes: 15 # default is 360 - six hours of a stuck job is six hours of billed minutes
```

Everything above is in the official docs, and the docs are good: start at
[Running jobs in a container](https://docs.github.com/en/actions/using-jobs/running-jobs-in-a-container),
[About service containers](https://docs.github.com/en/actions/using-containerized-services/about-service-containers),
[About self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners),
[Running variations of jobs in a workflow](https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs)
and [Workflow commands](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions).
The reason I wrote this anyway is that each of those pages explains one feature, and the value is in how they
combine: a container job, with a service, on an ephemeral runner, fanned out over a computed matrix, reporting into
the summary. That is a complete infrastructure CI in about sixty lines, and none of it needs anything from the
marketplace.
{% endraw %}
