---
layout: post
title: 'Podman on macOS instead of Docker Desktop - what actually changes'
date: 2026-11-27 22:00:00.00 +01:00
tag: ["DevOps", "Containers", "Podman", "macOS"]
category: DevOps
---

My [About page](/about/) has said "Podman / OrbStack" instead of "Docker" for a while now, and I keep getting asked
whether that is a political statement or a practical one. Practical. Docker Desktop's licence terms made it a
procurement question in a lot of companies, and once you have to justify a tool you start asking what you actually
use it for. For me the answer was: run a container, build an image, occasionally a compose file. Podman does all of
that. This post is the list of what is different on a Mac, because the differences are real, just smaller than the
internet makes them sound.
<!--more-->

## There is still a VM, you just see it

Containers are a Linux thing. On a Mac both Docker Desktop and Podman run them inside a Linux virtual machine. Docker
hides that VM completely. Podman does not:

```sh
brew install podman
podman machine init --cpus 4 --memory 8192 --disk-size 60
podman machine start
```

That creates a Fedora CoreOS VM (using Apple's Virtualization framework on Apple silicon), and from then on the
`podman` command on your Mac talks to the Podman service inside it over a socket. `podman machine stop` when you want
your battery back. The upside of seeing the VM: you decide how big it is, you can `podman machine ssh` into it when
something is weird, and you can have more than one (`podman machine init work`, `podman machine init play`).

## The `docker` command, and the tools that hardcode it

Muscle memory and third-party tools both type `docker`. Two layers fix that.

For your shell, `podman` accepts the same subcommands and flags for the everyday stuff - `run`, `build`, `ps`,
`exec`, `logs`, `pull`, `push`, `images`, `rm`, `rmi`. An alias is enough:

```sh
alias docker=podman
```

For tools that talk to the Docker *socket* rather than the CLI - Testcontainers, some IDE plugins, anything using
the Docker SDK - Podman ships a helper that puts a compatible socket at the standard path:

```sh
sudo podman-mac-helper install
podman machine stop && podman machine start
ls -la /var/run/docker.sock   # -> symlink into your Podman machine's socket
```

After that, software that looks for `/var/run/docker.sock` finds a Docker-API-compatible endpoint and mostly does not
notice. "Mostly" because the API compatibility is good but not total; Testcontainers works, a few niche tools that
rely on Docker-only API fields do not. Setting `DOCKER_HOST` to the socket path, which `podman machine start` prints,
is the alternative when the helper is not an option.

## Compose

`podman compose` exists and is a thin wrapper: it looks for `docker-compose` or `podman-compose` on your PATH and
runs that against the Podman socket. So the realistic setup is:

```sh
brew install docker-compose    # the Compose v2 binary, no Docker Desktop needed
podman compose up -d
```

Compose files I use day to day work unchanged. The things that have bitten people are `network_mode: host` (not
meaningful on a Mac with either tool), and anything mounting the Docker socket into a container, which needs the
Podman socket path instead.

## Rootless by default, and what that means on a Mac

Podman's headline feature is rootless containers. On the Mac this is slightly confusing: the VM is yours, so what does
rootless even mean? It means the Podman *service inside the VM* runs as an unprivileged user, so a container breakout
lands in a user account inside a VM, not in root inside a VM. Practically, two consequences:

- binding ports below 1024 works anyway, because the VM is configured to allow it,
- a handful of images that insist on doing privileged things at start (some older database images, anything that
  wants to `mount`) fail. For those, `podman machine set --rootful` switches the machine to rootful mode, and you are
  back to Docker-equivalent behaviour.

I run rootless and have flipped exactly one machine to rootful, for one project. The default is right.

## Volumes and file sharing

Bind-mounting a directory from the Mac into a container goes Mac → VM → container, and the Mac → VM hop is the
historically slow part, on both tools. Podman uses virtiofs for it now, which is fine for source code and config, and
painful for the same thing it is painful for everywhere: `node_modules` with sixty thousand files, or a database
data directory. The fix is the same as on Docker: keep heavy data in a named volume (`podman volume create`), which
lives on the VM's disk, and bind-mount only what you edit.

## Images and registries

Pulls from Docker Hub need the full name or a configured search list. `podman pull nginx` asks which registry you
mean; `podman pull docker.io/library/nginx` does not. Add `docker.io` to `unqualified-search-registries` in
`~/.config/containers/registries.conf` and short names work again. Not a Mac thing, but it is the first thing
everyone hits.

Builds are done by Buildah under the hood, and `podman build -f Dockerfile .` reads a Dockerfile unchanged. Multi-arch
builds for pushing an `arm64` image to be run on `amd64` EC2 are `podman build --platform linux/amd64`, with the
usual emulation slowness.

## Where OrbStack comes in

OrbStack is the other name on my About page. It is a commercial macOS app (free for personal use) that provides a
Docker-compatible engine and lightweight Linux machines, with a focus on being fast and quiet. It is what I reach for
when I want zero friction: a project with a `docker-compose.yml` someone else maintains, where I do not want to find
out about any difference at all. Podman is what I reach for when the environment matters - when I am going to deploy
to Kubernetes anyway and want the same tool that produces pods (`podman generate kube`, `podman play kube`), or on a
machine where I want everything open source. Having both installed is not a conflict, they do not share a socket
unless you tell them to.

## Would I switch back

No, but not out of principle. The day-to-day commands are the same, the VM being visible is a feature once you get
used to it, and the socket helper covers the tools that care. The friction that is left - the short-name registry
prompt, the occasional image that wants rootful - is a one-time fix each. If your workflow is "compose up, write code,
compose down", the honest summary is that you will stop noticing within a week.
