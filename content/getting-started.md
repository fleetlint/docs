---
title: "Getting started"
weight: 10
description: "Install fleetlint, check a repository, fix what can be fixed."
---

# Getting started

## Install

The quickest way on Linux and macOS is the install script. It needs only `curl`, `tar` and `sh`:

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://fleetlint.org/install.sh | sh
```

It installs the latest release into `~/.local/bin` and says so when that directory is not on `PATH`. A version and a directory can be given: `curl ... | sh -s -- v0.9.0 ~/bin`. The script is served from this site and is the one of the release these pages describe; to read it first, `curl -fsSL https://fleetlint.org/install.sh | less`.

With a package manager:

```sh
brew install fleetlint/tap/fleetlint                    # macOS, Linux
scoop bucket add fleetlint https://github.com/fleetlint/scoop-bucket
scoop install fleetlint/fleetlint                       # Windows
nix profile install github:fleetlint/nur#fleetlint     # Nix
mise use github:fleetlint/fleetlint                     # mise
go install github.com/fleetlint/fleetlint/cmd/fleetlint@latest
```

The container image runs on a checkout mounted at `/repo`:

```sh
docker run --rm -v "$PWD:/repo" ghcr.io/fleetlint/fleetlint check
```

Every [release](https://github.com/fleetlint/fleetlint/releases) carries archives for Linux, macOS and Windows, `.deb`, `.rpm`, `.apk` and Arch packages, `checksums.txt`, a cosign signature bundle for it and one SBOM per archive and package; the release notes show the `cosign verify-blob` command. The install script speaks https only, checks the archive against `checksums.txt`, and verifies more where it can: with `cosign` installed it verifies the signature of `checksums.txt` first; without cosign but with a logged-in `gh` it verifies the archive's build provenance (`gh attestation verify`); with neither it says that only the checksum was checked. `FLEETLINT_VERIFY=cosign` makes the signature required. The image is signed with cosign too.

`fleetlint version` prints the version of the tool and of the catalog built into it; `fleetlint catalog version` shows the catalog version the current repository runs with.

## Check a repository

```sh
cd your-repo
fleetlint
```

With no configuration fleetlint discovers the stacks, the forge, the CI system (GitHub, Gitea or Forgejo Actions, GitLab CI), the task runner, nested projects and whether a dev container is used, and applies the `recommended` preset. Requirements that differ by stack, such as a configured linter or a committed lockfile, are checked by each detected stack's own implementation; the [capability matrix](rules/capabilities.md) shows which stack has which. The report lists each finding with what to do about it; findings marked `*` are the ones `fleetlint fix` can repair. The last line names the fleetlint and catalog versions that produced it.

Exit codes: 0 clean, 1 findings at or above `--fail-on` (default `error`), 2 configuration error, 3 internal error.

```sh
fleetlint facts                       # what was discovered, and where each value came from
fleetlint explain taskrunner/targets  # one rule in full: requirement, rationale, fix
fleetlint hierarchy                   # the catalogs of the run in the order they apply, with their pins
```

## Write the configuration

```sh
fleetlint init
```

writes a `.fleetlint.yaml` that extends the `recommended` preset, with what was discovered as a comment. On GitHub, Gitea or GitLab it asks the forge once whether the repository is public and records the answer, because some rules apply to public repositories only. Nothing else is pinned: facts are detected again on every run.

A repository without a remote and without releases is treated as an experiment (tier 3), which is asked for very little. Say what it is with `fleetlint init --tier 1` (production or public) or `--tier 2` (a tool you rely on).

## Fix what can be fixed

```sh
fleetlint fix             # dry run: what it would create, untrack or edit
fleetlint fix --apply
fleetlint fix --apply --pr  # the same as a pull request against the default branch
```

`--apply` refuses a working tree with uncommitted changes to tracked files (exit 2), so the fixes never mix with work in progress: commit or stash first, or pass `--allow-dirty`. Untracked files, such as the `.fleetlint.yaml` `init` just wrote, do not count.

`--apply --pr` does not touch the working tree. It checks out the default branch as `origin` has it into a temporary worktree, applies the fixes there, commits them on the branch `fleetlint/fixes` as you (with the repository's git hooks off), force-pushes that branch and opens a pull request from it, or updates the one that is open, with the list of changes and the report as its description. A protected default branch and uncommitted work in the checkout are both fine. fleetlint owns `fleetlint/fixes`: the next run rebuilds it from the default branch, so commit your own changes elsewhere. With a token for the forge, its API opens the pull request and finds the default branch, and the push to an https remote authenticates with the same token; without a token, `gh`, `tea` or `glab` opens it (a new one only: an open pull request keeps its description), the default branch comes from `origin/HEAD` and the push uses git's own credentials.

The token is `--token` or `FLEETLINT_TOKEN` (the variable keeps it out of the process list), else the forge's own variable: `GITHUB_TOKEN` (or `GH_TOKEN`), `GITEA_TOKEN` for Gitea, Forgejo and Codeberg, `GITLAB_TOKEN`. The repository's own forge counts as asked for, so Codeberg or a self-hosted instance needs no `GITEA_HOST`. `--forge` (or `FLEETLINT_FORGE`) says which forge it is when the remote's host does not: `gitlab:git.example.com`, `gitea:codeberg.org`, `github:ghe.example.com`, or with a path prefix `gitlab:https://git.example.com/scm`. A `--token` goes to that forge only. In a CI job the job's own server is known: in GitHub Actions `GITHUB_API_URL` and `GITHUB_TOKEN`; in Gitea and Forgejo Actions `GITHUB_SERVER_URL`, `GITHUB_API_URL` and the job's `GITHUB_TOKEN`; in GitLab CI `CI_SERVER_HOST` and `CI_API_V4_URL`, with `GITLAB_TOKEN` or `--token`, since the job token cannot open merge requests.

`fix` creates missing files from templates (editor settings, hook configuration, a task runner file, a check workflow, linter, formatter and type-checker configuration), untracks files that should not be in git, and adds values to existing manifests. It never overwrites a file and never changes a key that is already set. What it writes belongs to your repository: edit it freely; the rules check what the files achieve, not that they match a template.

The rest needs a person or a coding agent:

```sh
fleetlint check --format agent   # an ordered task list with a precise instruction per rule
```

## Existing repositories with many findings

```sh
fleetlint baseline
```

records today's findings so that only new ones fail from now on. See [configuration](configuration.md#baseline).

## Keep it running

`fix` wires fleetlint into what it writes: a git hook, the task runner's `check` target and the check workflow. For an existing setup see [integrations](integrations.md).

## Many repositories

```sh
fleetlint fleet ~/src/*                   # paths
fleetlint fleet --from github:your-org    # or every repository of an owner
```

writes one report for all of them. See [fleet mode](fleet.md).
