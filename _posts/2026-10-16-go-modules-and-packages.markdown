---
layout: post
title: 'Go modules and packages: how to create a module and how to split an app into packages'
date: 2026-10-16 18:30:00.00 +02:00
tag: ["Programming", "GoLang"]
category: GoLang
---

Every Go project starts the same way: one `main.go`, it works, it grows, and at some point you have a 1500-line file
and the question "how do I split this up" - followed by "and what is the difference between a module and a package
again". This post is the answer I give every time. It is short on theory and long on the three commands and one
directory layout you actually need, with links to the official docs for the parts I skip.
<!--more-->

## Two words, two different things

- A **package** is a directory of `.go` files that all start with the same `package` clause. It is the unit of
  compilation and of visibility: identifiers starting with a capital letter are exported from the package, everything
  else is private to it. You import packages.
- A **module** is a directory tree with a `go.mod` file at its root. It is the unit of versioning and distribution:
  it has a path (usually a repository URL), a version (a git tag), and a list of other modules it depends on. You
  `go get` modules.

A module contains one or more packages. Most projects are one module with several packages, and that is the case this
post is about. The import path of a package is the module path plus the directory: in module `github.com/robertwe/notes`,
the code in `internal/store/` is imported as `github.com/robertwe/notes/internal/store`.

Official reference, when you need the full rules: the [Go Modules Reference](https://go.dev/ref/mod).

## Creating a module

```sh
mkdir notes && cd notes
go mod init github.com/robertwe/notes
```

That writes a `go.mod`:

```
module github.com/robertwe/notes

go 1.25
```

The module path should be where the code will live, even if you have not pushed it yet, because it is also the
import path prefix for every package inside and the thing `go get` will fetch later. For something that will never be
published, any path works, but pick the real one anyway, renaming later means touching every import.

Add dependencies by importing them and running:

```sh
go get github.com/aws/aws-sdk-go-v2/service/s3@latest
go mod tidy
```

`go get` adds a `require` line with the resolved version and writes checksums to `go.sum`. `go mod tidy` adds anything
you import but have not required, and removes anything you require but no longer import. Run `tidy` before every
commit; most CI setups fail the build if it would change anything (`go mod tidy -diff` since Go 1.23).

The official walkthrough for this part is the [Create a Go module tutorial](https://go.dev/doc/tutorial/create-module),
and the dependency commands are in [Managing dependencies](https://go.dev/doc/modules/managing-dependencies).

## Splitting an app into packages

Take a small HTTP service: it reads config, talks to a database, serves a JSON API. As one file it is `main.go`. The
layout that the Go team recommends for exactly this case, from their
[Organizing a Go module](https://go.dev/doc/modules/layout) page, is:

```
notes/
├── go.mod
├── go.sum
├── cmd/
│   └── notes-server/
│       └── main.go          # package main: wire things together, start the server
└── internal/
    ├── config/
    │   └── config.go        # package config: load env/flags into a struct
    ├── store/
    │   ├── store.go         # package store: the database layer
    │   └── store_test.go
    └── httpapi/
        ├── server.go        # package httpapi: handlers, routing, middleware
        └── server_test.go
```

Three rules make this work:

**1. `internal/` is enforced by the compiler.** A package under `internal/` can only be imported by code rooted at
the parent of `internal/`. So `github.com/robertwe/notes/internal/store` is importable by anything in the `notes`
module and by nothing outside it. For a service, that is where everything goes. You get to change the API of `store`
whenever you want, because nobody but you can depend on it. The docs put it plainly: keep packages in `internal` as
much as possible.

**2. `cmd/<name>/main.go` is tiny.** `package main` builds the pieces and starts them. Nothing else lives there,
which keeps it testable - you test `httpapi` and `store`, not `main`:

```go
package main

import (
	"log/slog"
	"net/http"
	"os"

	"github.com/robertwe/notes/internal/config"
	"github.com/robertwe/notes/internal/httpapi"
	"github.com/robertwe/notes/internal/store"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}

	st, err := store.Open(cfg.DatabaseURL)
	if err != nil {
		slog.Error("store", "err", err)
		os.Exit(1)
	}
	defer st.Close()

	srv := httpapi.New(st)
	slog.Info("listening", "addr", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, srv); err != nil {
		slog.Error("server", "err", err)
		os.Exit(1)
	}
}
```

If the project later needs a second binary - a migration tool, a CLI - it is `cmd/notes-migrate/main.go`, sharing
`internal/` with the server.

**3. Dependencies point inward, and never in a circle.** `httpapi` imports `store`. `store` imports nothing of ours.
`main` imports both. Go refuses to compile an import cycle, so the compiler keeps you honest; when you hit one, the fix
is almost always to move the shared type into the package that is lower in the stack, or into a small new package
both can import.

## Naming packages

This is where most of the mess comes from, so the short version of the official
[Package names](https://go.dev/blog/package-names) advice:

- Short, lowercase, one word, no underscores: `store`, not `data_store` or `storeUtils`.
- The name is part of every call site, so do not repeat it inside: `store.Open`, not `store.OpenStore`;
  `config.Load`, not `config.LoadConfig`.
- Name the package after what it *provides*, not what it *contains*. `util`, `common`, `helpers`, `models` are
  the names you reach for when you have not decided what the package is for yet. A package called `util` grows
  forever and everything ends up importing it.
- The directory name and the package name should match. They do not have to, but every reader assumes they do.

## When one module is not enough

Most apps never need more than one module. The two cases where you do:

**You want to publish a library out of the service.** `internal/` cannot be imported from outside, so to share
`store` with another project it has to move out of `internal/` - and at that point it usually deserves its own
repository and module with its own version tags, because its users will want to pin it independently of your service.

**You are developing two modules at once** and want the service to use the library from your working copy instead of
a published tag. That is what Go workspaces are for:

```sh
go work init ./notes ./notes-lib
```

A `go.work` file at the parent directory tells the toolchain to resolve `github.com/robertwe/notes-lib` from the local
`./notes-lib` directory. No `replace` directive to forget to remove before committing, and `go.work` itself is
normally not committed. The [workspaces tutorial](https://go.dev/doc/tutorial/workspaces) covers it in ten minutes.

For publishing, the thing that trips people up is major versions: from `v2` on, the major version is part of the module
path (`github.com/robertwe/notes-lib/v2`), both in `go.mod` and in every import. The reasoning and the mechanics are in
[Module version numbering](https://go.dev/doc/modules/version-numbers).

## The handful of commands worth memorising

```sh
go mod init <path>        # new module
go get <pkg>@<version>    # add or update a dependency (@latest, @v1.2.3, @master, @none to drop)
go mod tidy               # fix require/go.sum to match the imports
go mod why <module>       # why is this in my go.mod?
go mod graph              # full dependency graph, pipe into grep
go list -m -u all         # which dependencies have newer versions
go work init ./a ./b      # multi-module local development
```

Everything else - vendoring, private module proxies, `GOPRIVATE`, `GOFLAGS=-mod=mod` - exists and is in the
reference, and you will know when you need it.

## A Claude Code skill for this

I [wrote earlier]({% post_url 2026-10-16-claude-code-skills-in-practice %}) about skills, the Markdown files Claude
Code loads when a task matches. There is no official Go skill in Anthropic's
[public skills repository](https://github.com/anthropics/skills) at the time of writing - it has document, design, API
and MCP skills, nothing language-specific. The [skills documentation](https://code.claude.com/docs/en/skills)
explains the format if you want to roll your own, and for this post's topic the skill is short enough to paste here:

```markdown
---
name: go-layout
description: Create or restructure a Go module into packages. Use when starting a Go project, splitting a large main.go, or asked where code should live.
---

Follow https://go.dev/doc/modules/layout. Concretely:

- One module per repository unless told otherwise; `go mod init` with the real repository path.
- Binaries in `cmd/<name>/main.go`; `main` only wires dependencies and starts things.
- Everything else under `internal/`, one package per concern (`config`, `store`, `httpapi`, ...).
  No `pkg/`, `util`, `common` or `models` packages.
- Package names: short, lowercase, one word, matching the directory; no stuttering (`store.Open`, not `store.OpenStore`).
- Dependencies point inward: `cmd` -> `httpapi` -> `store`. Never introduce an import cycle; if one appears,
  move the shared type down the stack.
- After changes run `go build ./... && go vet ./... && go mod tidy -diff` and fix what they report.
- Do not add a dependency for something the standard library does (`net/http`, `log/slog`, `encoding/json`, `flag`).
```

Project-scoped (`.claude/skills/go-layout/SKILL.md`), it is a checklist the agent and every human on the team read the
same way. It encodes nothing that is not in the official layout page, which is the point: the layout page is the
source of truth, the skill just makes sure it gets applied at 17:55 on a Friday.
