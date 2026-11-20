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

It installs the latest release into `~/.local/bin` and says so when that directory is not on `PATH`. A version and a directory can be given: `curl ... | sh -s -- v0.11.1 ~/bin`. The script is served from this site and is the one of the release these pages describe; to read it first, `curl -fsSL https://fleetlint.org/install.sh | less`.

With a package manager:

```sh
brew install fleetlint/tap/fleetlint                    # macOS, Linux
scoop bucket add fleetlint https://github.com/fleetlint/scoop-bucket
scoop install fleetlint/fleetlint                       # Windows
nix profile install github:fleetlint/nur#fleetlint     # Nix
mise use github:fleetlint/fleetlint                     # mise
go install github.com/fleetlint/fleetlint/cmd/fleetlint@latest
```

Every [release](https://github.com/fleetlint/fleetlint/releases) carries archives for Linux, macOS and Windows, `.deb`, `.rpm`, `.apk` and Arch packages, `checksums.txt`, a cosign signature bundle for it and one SBOM per archive and package; the release notes show the `cosign verify-blob` command. The install script speaks https only and checks the archive against `checksums.txt`. It verifies more where it can:

- with `cosign` installed, the signature of `checksums.txt`;
- else, with a logged-in `gh`, the archive's build provenance (`gh attestation verify`);
- else it says that only the checksum was checked.

`curl ... | FLEETLINT_VERIFY=cosign sh` makes the signature required.

The release image `ghcr.io/fleetlint/fleetlint` is signed with cosign and runs on a checkout mounted at `/repo`.

```sh
docker run --rm -v "$PWD:/repo" ghcr.io/fleetlint/fleetlint check
docker run --rm -v "$PWD:/repo" --user "$(id -u):$(id -g)" ghcr.io/fleetlint/fleetlint fix --apply
```

The image runs as uid 65532, so `fix --apply` needs `--user` to write into a checkout you own.

`fleetlint version` prints the version of the tool and of the catalog built into it; `fleetlint catalog version` shows the catalog version the current repository runs with.

## Check a repository

```sh
cd your-repo
fleetlint
```

With no configuration fleetlint discovers the stacks, the forge, the CI system (GitHub, Gitea or Forgejo Actions, GitLab CI), the task runner, nested projects and whether a dev container is used, and applies the `recommended` preset. Requirements that differ by stack, such as a configured linter or a committed lockfile, are checked by each detected stack's own implementation; the [capability matrix](rules/capabilities.md) shows which stack has which. The report lists each finding with what to do about it; findings marked `*` are the ones `fleetlint fix` can repair. The last line names the fleetlint and catalog versions that produced it.

```sh
fleetlint facts                       # what was discovered, and where each value came from
fleetlint explain taskrunner/targets  # one rule in full: requirement, rationale, fix
fleetlint hierarchy                   # the catalogs of the run in the order they apply, with their pins
```

### Exit codes

| Code | Meaning | Typical causes |
|---|---|---|
| 0 | clean | no finding at or above `--fail-on` |
| 1 | findings | a finding at or above `--fail-on` (`error`, `warning`, `info` or `never`; default `error`); a rule that could not run, whatever `--fail-on` says |
| 2 | configuration error | an invalid `.fleetlint.yaml` or catalog, a catalog that could not be fetched, an override or exception that a catalog's policy forbids, an unmet `--require`, `fix --apply` on uncommitted changes |
| 3 | internal error | anything else, such as a failed push or pull request with `--pr` |

[Troubleshooting](troubleshooting.md) has the common configuration errors with their messages. Every command, flag and environment variable is in the [CLI reference](cli-reference.md).

## Write the configuration

```sh
fleetlint init
```

writes a `.fleetlint.yaml` that extends the `recommended` preset and lists what was detected and is checked: the stacks of the root and of each workspace member under `scopes:`, and what the release publishes under `facts.artifacts`, with the workflows that publish it. On GitHub, Gitea or GitLab it asks the forge once whether the repository is public and records the answer, because some rules apply to public repositories only; a private repository needs a token for that, see [pull requests and forges](#pull-requests-and-forges). The lists replace detection, so the file says what fleetlint goes by; `fleetlint check` notes when detection finds a stack or an artifact the file does not list, so you can add it or leave it out knowingly. The task runner, the container and the other facts are detected again on every run.

Without configuration the tier is inferred:

| Tier | For | Inferred when |
|---|---|---|
| 1 | production or public | the repository is public, or has a release pipeline: a GoReleaser config, `cliff.toml` or a workflow run on tags |
| 2 | a tool you rely on | it has CI or tags |
| 3 | an experiment, asked for very little | neither |

Say what it is with `fleetlint init --tier 1` or `--tier 2`. The rule reference lists [what runs at each tier](rules/_index.md#what-runs-at-each-tier).

## Fix what can be fixed

```sh
fleetlint fix             # dry run: what it would create, untrack or edit
fleetlint fix --apply
fleetlint fix --apply --pr  # the same as a pull request against the default branch
```

`--apply` refuses a working tree with uncommitted changes to tracked files (exit 2), so the fixes never mix with work in progress: commit or stash first, or pass `--allow-dirty`. Untracked files, such as the `.fleetlint.yaml` `init` just wrote, do not count. `--apply --pr` leaves the working tree alone; see [pull requests and forges](#pull-requests-and-forges).

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

## Pull requests and forges

`fleetlint fix --apply --pr` and `fleetlint init --pr` propose their changes as a pull request instead of writing into the checkout:

- `fix --apply --pr` checks out the default branch as `origin` has it into a temporary worktree, applies the fixes there and commits them on the branch `fleetlint/fixes` as you, with the repository's git hooks off. It force-pushes that branch and opens a pull request from it, or updates the one that is open, with the list of changes and the report as its description.
- A protected default branch and uncommitted work in the checkout are both fine.
- fleetlint owns `fleetlint/fixes`: the next run rebuilds it from the default branch, so commit your own changes elsewhere.
- With a token for the forge, its API opens the pull request and finds the default branch, and the push to an https remote authenticates with the same token.
- Without a token, `gh`, `tea` or `glab` opens it (a new one only: an open pull request keeps its description), the default branch comes from `origin/HEAD` and the push uses git's own credentials.

| Forge | Token | Host | In CI |
|---|---|---|---|
| GitHub | `GITHUB_TOKEN` or `GH_TOKEN` | github.com; GitHub Enterprise Server: `--forge github:<host>` or `GITHUB_API_URL` | GitHub Actions: the job's `GITHUB_TOKEN` and `GITHUB_API_URL` |
| Gitea, Forgejo, Codeberg | `GITEA_TOKEN` | `--pr` trusts the remote's own host; `init` and [fleet mode](fleet.md#forges-and-tokens) ask only hosts named in `GITEA_HOST` | Gitea and Forgejo Actions: the job's `GITHUB_TOKEN`, `GITHUB_SERVER_URL` and `GITHUB_API_URL` |
| GitLab | `GITLAB_TOKEN` | gitlab.com; another instance as with Gitea, but named in `GITLAB_HOST` | GitLab CI: `CI_SERVER_HOST` and `CI_API_V4_URL`; the job token cannot open merge requests, so `GITLAB_TOKEN` or `--token` |

- `--token` or `FLEETLINT_TOKEN` (the variable keeps it out of the process list) replaces the forge's own variable, and goes to that forge only.
- The forge is detected from the remote's host: github.com or a host with `github` in its name is GitHub, a host with `gitlab` in its name is GitLab, any other host is Gitea (Forgejo, Codeberg). `--forge` or `FLEETLINT_FORGE` says which forge it is when the host does not: `gitlab:git.example.com`, `github:ghe.example.com`, or with a path prefix `gitlab:https://git.example.com/scm`.
