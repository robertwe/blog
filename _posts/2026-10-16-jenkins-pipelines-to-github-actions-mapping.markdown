---
layout: post
title: 'From Jenkins pipelines to GitHub Actions - a mapping, not a migration guide'
date: 2026-10-16 15:00:00.00 +02:00
tag: ["DevOps", "CI/CD", "Jenkins", "GitHub Actions", "OpenTofu", "AWS"]
category: DevOps
---

I have written a lot of Jenkins - shared libraries, Job DSL seed jobs, declarative pipelines, the works - and over
the last years most of it has moved to GitHub Actions. Every migration guide I read was either "here is how to export
your jobs" (you cannot, not meaningfully) or a sales pitch. What I actually wanted was a dictionary: I know what this
Jenkins thing does, what is the Actions word for it, and where does the mental model break. So here is that
dictionary, with the one place where Actions is genuinely better and the two places where you will miss Jenkins.
<!--more-->

## The dictionary

| Jenkins | GitHub Actions | Notes |
|---|---|---|
| `Jenkinsfile` | `.github/workflows/*.yml` | one file per workflow, several workflows per repo |
| `pipeline { stages { stage {} } }` | `jobs:` → `steps:` | a job is the unit of parallelism and of the runner |
| `agent { label 'linux' }` | `runs-on: ubuntu-latest` | labels still exist, for self-hosted runners |
| `steps { sh '...' }` | `- run: ...` | multi-line with `run: \|` |
| `when { branch 'main' }` | `if: github.ref == 'refs/heads/main'` | on job or step |
| `parallel { }` | `strategy: matrix:` or multiple jobs | matrix is the idiomatic one |
| `post { always { } }` | `if: always()` on a step | `failure()`, `success()`, `cancelled()` too |
| `parameters { }` | `on: workflow_dispatch: inputs:` | typed: string, choice, boolean |
| `triggers { cron('H 2 * * *') }` | `on: schedule: - cron: '17 2 * * *'` | no `H`, pick an odd minute yourself |
| `environment { }` | `env:` | workflow, job or step scope |
| `credentials('id')` | `${{ secrets.NAME }}` | plus OIDC, see below |
| `lock('deploy-prod')` | `concurrency: group: deploy-prod` | `cancel-in-progress` optional |
| `input message: 'Deploy?'` | `environment:` with required reviewers | approval lives in repo settings |
| `archiveArtifacts` / `stash` | `actions/upload-artifact` / `download-artifact` | artifacts cross jobs; stash was within a build |
| shared library `vars/*.groovy` | composite action or reusable workflow | the big one, next section |
| Job DSL seed job | reusable workflow with `on: workflow_call` | plus a template repo |
| `buildDiscarder(logRotator(...))` | repository settings → retention | not in YAML |
| Jenkins agents | self-hosted runners | or just use hosted ones |

## Shared libraries → composite actions and reusable workflows

This is where the model actually differs, so it is worth more than a table row.

A Jenkins shared library is Groovy code: it can have functions, classes, loops, and a `vars/deploy.groovy` step
that takes a map of arguments and does anything. Actions has no scripting layer in YAML. Instead you get two
composition tools, and you pick by granularity:

**Composite action** = a reusable *step sequence*. Lives in `action.yml`, takes `inputs`, produces `outputs`, runs
inside the calling job on the calling runner. This is the replacement for the typical `vars/tofuPlan.groovy`:

```yaml
# .github/actions/tofu-plan/action.yml
name: tofu plan
inputs:
  working-directory:
    required: true
runs:
  using: composite
  steps:
    - uses: opentofu/setup-opentofu@v1
    - run: tofu init -input=false
      shell: bash
      working-directory: ${{ inputs.working-directory }}
    - run: tofu plan -input=false -out=tfplan
      shell: bash
      working-directory: ${{ inputs.working-directory }}
```

**Reusable workflow** = a reusable *job set*. Triggered with `on: workflow_call`, called from another workflow with
`uses: org/repo/.github/workflows/plan.yml@main`, runs as its own jobs with its own runners. This is the replacement for
the Job DSL seed job that stamped out one pipeline per service: one reusable workflow in a central repo, each service
repo has a five-line workflow that calls it.

The thing you lose is logic. There is no `if (env == 'prod') { ... } else { ... }` in a composite action, only `if:`
expressions on steps. In practice that pushed me to move logic *out* of CI into scripts and Makefiles in the repo,
which is where it should have been in the first place. Jenkins let you hide a lot of real program in a `vars/` folder.

## The place Actions is better: credentials via OIDC

In Jenkins the AWS credentials for deploying were an access key and secret stored in the credentials store, rotated
when someone remembered. Actions can skip the long-lived key entirely. The job requests an OIDC token from GitHub,
and AWS trusts GitHub's identity provider for a specific repository and branch:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-plan
          aws-region: eu-central-1
      - uses: ./.github/actions/tofu-plan
        with:
          working-directory: envs/prod
```

The IAM role's trust policy restricts `token.actions.githubusercontent.com:sub` to `repo:org/repo:ref:refs/heads/main`,
or to an environment. No secret exists anywhere. A leaked workflow log cannot leak a key because there is no key.
This alone was worth the migration for the infrastructure repos.

## A full example, side by side

The pipeline every infrastructure team has - fmt, validate, plan on pull requests:

```groovy
// Jenkinsfile
pipeline {
  agent { label 'linux' }
  options { timeout(time: 20, unit: 'MINUTES') }
  stages {
    stage('fmt')      { steps { sh 'tofu fmt -check -recursive' } }
    stage('validate') { steps { sh 'tofu init -backend=false && tofu validate' } }
    stage('plan') {
      when { changeRequest() }
      steps {
        withCredentials([aws(credentialsId: 'aws-plan')]) {
          sh 'tofu init -input=false && tofu plan -input=false'
        }
      }
    }
  }
}
```

```yaml
# .github/workflows/tofu.yml
name: tofu
on:
  pull_request:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read
  pull-requests: write

concurrency:
  group: tofu-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - run: tofu fmt -check -recursive
      - run: tofu init -backend=false && tofu validate

  plan:
    if: github.event_name == 'pull_request'
    needs: check
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-plan
          aws-region: eu-central-1
      - uses: ./.github/actions/tofu-plan
        with:
          working-directory: envs/prod
```

Roughly the same length. The Actions version has the OIDC role instead of a stored credential, `concurrency` instead
of hoping two PR builds do not race on the same state lock, and `needs:` making the dependency explicit instead of
implied by stage order.

## The two things you will miss

**The Blue Ocean / stage view.** Actions shows jobs as a graph and steps as a log. It does not show *stages within a
job* visually, and a forty-step job is a forty-section log. You adapt by making more, smaller jobs, which also
parallelises better, but the first week feels like flying blind.

**Running the pipeline locally.** A Jenkinsfile could, with effort, be replayed. Actions workflows run on GitHub,
full stop. `act` exists and gets you most of the way for simple workflows, but OIDC, environments and anything
touching `github.*` context behave differently. The practical answer was the same as for the logic question: put the
real work in scripts that run with no CI at all, and keep the YAML to orchestration. If the YAML is boring enough that
you never need to run it locally, you have done it right.

## Pin your actions

Last thing, because it is a security issue and not a style one. `uses: some-org/some-action@v4` follows a moving tag.
If that repository is compromised, your workflow runs the attacker's code with your OIDC token. Pin to a commit SHA
with the version as a comment, and let Dependabot bump it:

```yaml
- uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502 # v4.0.2
```

Jenkins had this problem too, with plugins, it just was less visible. In Actions the supply chain is in the YAML
where you can see it, so there is no excuse.
