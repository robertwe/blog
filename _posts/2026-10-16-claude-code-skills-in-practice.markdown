---
layout: post
title: 'Claude Code skills - teach the agent your workflow once, in a Markdown file'
date: 2026-10-16 09:00:00.00 +02:00
tag: ["AI", "Claude Code", "Automation", "DevOps"]
category: AI
---

Every time I opened Claude Code I was typing the same paragraph: "new post goes to `_posts`, file name starts with the date,
front matter looks like this, build to a temp dir, don't touch `docs/`". Then I discovered that this paragraph has a
proper home. It is called a skill, it is one Markdown file, and the agent loads it on its own when the task matches.
This post is the five minute version: what a skill is, where it lives, and two examples worth copying.
<!--more-->

## What a skill is

A skill is a directory with a `SKILL.md` inside. The file has a small YAML front matter and then plain instructions:

```markdown
---
name: post
description: Create a new blog post for this Jekyll blog. Use when asked to write, draft or scaffold a post.
---

Create a new post in `_posts/`.

1. File name: `YYYY-MM-DD-<slug>.markdown`, today's date, slug from the title.
2. Front matter exactly like the existing posts: `layout: post`, quoted `title`,
   `date` with `+02:00`, `tag` as a list, single `category`.
3. First paragraph is the excerpt, then `<!--more-->`, then the body.
4. Build with `bundle exec jekyll build -d /tmp/site` and report errors. Never write to `docs/`.

Title and topic: $ARGUMENTS
```

Two things matter here. The `description` is the trigger - Claude reads it to decide whether the skill applies, so write
it as "what it does + when to use it", like a search query you would type yourself. `$ARGUMENTS` is whatever you type
after the slash command, so `/post Route 53 DNS Firewall with OpenTofu` lands in the last line.

## Where it lives

| Location | Scope |
|---|---|
| `~/.claude/skills/<name>/SKILL.md` | you, every project |
| `.claude/skills/<name>/SKILL.md` | this repository, committed, shared with the team |

The project variant is the interesting one for teams. The runbook for "how we cut a release" or "how we review a
module" stops being tribal knowledge in someone's head and becomes a file in the repo that both humans and the agent
read.

## How it gets used

Two ways. You type `/post ...` and it runs. Or you just say "write a post about X" and Claude picks the skill because
the description matches. Until that moment only the name and description sit in the context, the body is loaded on
demand. That is why you can have dozens of skills without paying for them on every request.

If a skill is dangerous enough that you never want it auto-selected - deploy, anything touching production - add
`disable-model-invocation: true` to the front matter. Then only the explicit slash command triggers it.

## Supporting files

A skill directory can hold more than `SKILL.md`: a `scripts/` folder with a shell or Python helper, a `references/`
folder with a long checklist or an API cheat sheet. Reference them from `SKILL.md` by relative path and they are read
only when needed. Rule of thumb that worked for me: keep `SKILL.md` short enough to read in one screen, move anything
longer into a reference file.

## A second one for the infrastructure repo

An OpenTofu review checklist, project-scoped, so every reviewer and the agent use the same list:

```markdown
---
name: tofu-review
description: Review OpenTofu/Terraform changes. Use when asked to review .tf files, a module or a plan output.
---

Review the changed `.tf` files against this list and report findings as file:line bullets, worst first:

- resources without `lifecycle { prevent_destroy }` where data would be lost (RDS, S3, EBS, KMS),
- `count = cond ? 1 : 0` on a resource that already exists in state - needs a `moved` block,
- provider versions not pinned with `~>`,
- IAM policies with `"Action": "*"` or `"Resource": "*"`,
- security groups open to `0.0.0.0/0` on anything but 80/443,
- hardcoded account IDs, regions or ARNs that should be data sources or variables.

Do not run `tofu plan` or `tofu apply`. `tofu fmt -check` and `tofu validate` are fine.
```

Nothing clever. It is the same list I would go through by hand, except now I do not forget point four at 17:55 on a
Friday.

## Skill, CLAUDE.md or subagent?

- `CLAUDE.md` is loaded always. Put there what applies to every single request: coding conventions, "never run apply",
  commit message rules. Keep it short, you pay for it every time.
- A skill is loaded when relevant. Put there a workflow, a checklist, a procedure.
- A subagent is a separate context with its own tools. Reach for it when the task is big enough to pollute your main
  conversation, like reading forty files to answer one question.

Most of what I used to stuff into `CLAUDE.md` turned out to be skills.

## Three mistakes to skip

1. Vague description. "Helpful blog utilities" gives the model nothing to match on. "Create a new blog post for this
   Jekyll blog. Use when asked to write, draft or scaffold a post." does.
2. Skill that does too much. One skill that wrote, built, committed and deployed. Split it: `/post` writes and builds,
   deploy is a separate skill with `disable-model-invocation: true`.
3. No test. After writing a skill, ask for the task without naming the skill. If Claude does not pick it up, the
   description is wrong, not the model.

That is the whole thing. One directory, one Markdown file, a good description.
