---
title: "Troubleshooting"
weight: 15
description: "The errors fleetlint stops with, their exact messages, and what to change."
---

# Troubleshooting

The errors on this page are configuration errors: fleetlint stops before any rule runs and exits with 2. Each message names the file, and a YAML error the line and column. The visibility notes under [forges](#visibility-left-undetected) are warnings. The [exit codes](getting-started.md#exit-codes) say what the other codes mean. Errors in a rule's own expressions are listed under [writing rules](writing-rules.md#when-the-configuration-does-not-load).

## The repository's configuration

### `rules` written as a map

```text
fleetlint: .fleetlint.yaml: [3:23] mapping was used where sequence is expected
   1 | version: 1
   2 | rules:
>  3 |   hooks/pre-push-check: { enabled: false, reason: "CI runs the full check" }
                             ^
```

`rules:` is a list of the repository's own rules and `use:` selections. Changes to a rule a catalog brought in go under `overrides:`, keyed by the rule id:

```yaml
version: 1
overrides:
  hooks/pre-push-check: { enabled: false, reason: "CI runs the full check" }
```

### `version` missing

```text
fleetlint: .fleetlint.yaml: version must be 1 (got 0)
```

`version: 1` is the one key every `.fleetlint.yaml` needs, nested files included.

### An unknown key

```text
fleetlint: .fleetlint.yaml: [2:10] unknown field "teir"
   1 | version: 1
>  2 | facts: { teir: 2 }
                ^
```

fleetlint reads the file strictly, so a misspelt key is an error, not ignored. An editor with the YAML language server marks it while you type; see [editors](integrations.md#editors). [Configuration](configuration.md) lists every key.

## Catalogs

### A rule without `severity`, `kind` or texts

```text
fleetlint: catalog policy/acme.yaml: rule acme/owner-file: severity is required (error, warning or info)
fleetlint: catalog policy/acme.yaml: rule acme/owner-file: unknown kind ""
fleetlint: catalog policy/acme.yaml: rule acme/owner-file: title and requirement are required
fleetlint: catalog policy/acme.yaml: rule acme/owner-file: fix.human is required
```

Every rule needs `kind` (`expr` for an expression rule) and `severity`. A rule in a catalog also needs `title`, `requirement` and `fix.human`; only the repository's own rules may be terse. [Writing rules](writing-rules.md) has the full format.

### The catalog builds on another catalog version

```text
fleetlint: catalog policy/acme.yaml builds on catalog v0.7.0; this run uses the built-in catalog (v0.8.0). Pin that version in .fleetlint.yaml (catalog:) or in the sources file so every repository runs the same rules
```

A run uses one catalog version, and every catalog's `metadata.catalog` must name it. Either pin the version the catalog names (`catalog: { version: v0.7.0 }` in `.fleetlint.yaml` or the sources file), or move the catalog to the version the run uses. `metadata.catalog` is a mapping, `catalog: { version: v0.8.0 }`; the plain string `catalog: v0.8.0` fails with `string was used where mapping is expected`.

### The catalog needs a newer fleetlint

```text
fleetlint: catalog policy/acme.yaml: catalog acme 1.0.0 needs engine level 99 and this fleetlint has 7: upgrade fleetlint, or use an older catalog version
```

`metadata.engine` is the engine level the catalog was written for. Upgrade fleetlint everywhere the catalog runs, hooks and CI included.

### `includes` names a sources-file name

```text
fleetlint: catalog https://standards.example.com/teams/platform.yaml#sha256-…: include "org" must be a preset, an https URL or a git reference
```

Names from the sources file (`org`, `team/platform`) resolve in `extends`, not in a catalog's `includes`. Include the pinned reference that the sources file maps the name to, or leave the include out and rely on the order: the sources file's `extends` always applies before the repository's.

### A git catalog pinned to a tag loses its `rules/`

```text
fleetlint: catalog git+https://git.example.com/org/standards.git//catalog.yaml@v1.0.0#sha256-…: use acme/owner-file: no such rule in the library (it has 341 rules)
```

A tag can move, so its digest covers only the catalog file. A git catalog pinned to a tag never brings the `rules/` and `templates/` next to it, and fleetlint warns on stderr when the tree has them. Pin a full commit SHA instead, which needs no digest:

```text
git+https://git.example.com/org/standards.git//catalog.yaml@<40-character commit SHA>
```

A catalog from a registry (`oci://`) brings its `rules/` and `templates/` at a tag too, since the signature covers the whole artifact.

### A catalog cannot be fetched

```text
fleetlint: fetch https://standards.example.com/org.yaml: Get "https://standards.example.com/org.yaml": dial tcp: lookup standards.example.com: no such host
fleetlint: fetch git+https://git.example.com/org/standards.git//catalog.yaml@<commit>: git fetch: exit status 128: fatal: unable to access 'https://git.example.com/org/standards.git/': Could not resolve host: git.example.com
```

Catalogs and sources files referenced by https, git or `oci://` are fetched on every run, hooks included, and one that cannot be fetched stops the run with exit 2. A git hook then blocks the commit while you are offline. Only the catalog version pin (`catalog: { version: … }`) is cached. Check the network and the credentials git uses for that host; to commit offline, prek and pre-commit skip the hook with `SKIP=fleetlint git commit`.

## Policy

### A catalog's policy refuses an override or exception

```text
fleetlint: .fleetlint.yaml: rules.hooks/config-present: rule is locked by acme@1.0.0 and cannot be disabled
fleetlint: .fleetlint.yaml: rules.hooks/config-present: acme@1.0.0 set a severity floor of warning; off is below every floor
fleetlint: .fleetlint.yaml: rules.hooks/config-present: rule forbids exceptions (set by acme@1.0.0) and cannot be disabled
fleetlint: .fleetlint.yaml: exceptions: rule hooks/config-present forbids exceptions (set by acme@1.0.0)
```

An earlier catalog, named in the message, set the policy, and policy only tightens:

| Policy | What remains |
|---|---|
| `locked: true` | a reasoned exception for the findings |
| `min_severity` | a lower severity, not below the floor, with a reason; an exception |
| `exceptions: false` | changing the severity, `params` or `accept`; nothing that turns the rule off or excepts it |

Otherwise fix the finding, or ask the catalog's owners for a change there. [How rules combine](composition.md#policy-what-a-lock-a-floor-and-exceptions-false-hold) has the full table.

### A required catalog is missing

```text
fleetlint: required catalog org is not part of the effective configuration (add it to extends)
```

The runner passed `--require org`. Add the catalog to `extends`, or use the sources file whose baseline includes it.

## Forges

### GitHub Enterprise or GitLab on its own hostname

`fleetlint facts` shows the forge it detected from the remote's host:

```text
forge        gitea (git.example.com)                  detected
```

github.com or a host with `github` in its name is GitHub, a host with `gitlab` in its name is GitLab, any other host is Gitea. A GitLab instance at `git.example.com` is therefore taken for Gitea. Pin the forge in `.fleetlint.yaml`, and name it for the commands that call its API (`init`, `--pr`, fleet mode):

```yaml
version: 1
facts: { forge: gitlab }
```

```sh
export FLEETLINT_FORGE=gitlab:git.example.com     # or --forge; github:<host> for GitHub Enterprise Server
```

### Visibility left undetected

```text
visibility: git.example.com was not asked; left undetected (set GITEA_HOST=git.example.com to let fleetlint ask it, or pin facts.visibility)
visibility: github.com does not show this repository without a token; left undetected (set GITHUB_TOKEN or GITEA_TOKEN, or pin facts.visibility)
```

`init` asks the forge whether the repository is public, and asks only hosts it may contact: github.com, gitlab.com, the host named with `--forge`, and the hosts named in `GITEA_HOST` or `GITLAB_HOST`. A private repository needs a token. Set the variable and run `init --force` again, or pin `facts: { visibility: private }` yourself. [Pull requests and forges](getting-started.md#pull-requests-and-forges) lists the tokens.

## Fixing

### Uncommitted changes

```text
fleetlint: the working tree has uncommitted changes to tracked files; commit or stash them, or pass --allow-dirty
```

`fix --apply` writes only into a clean working tree, so its changes never mix with yours. Commit or stash, pass `--allow-dirty`, or use `fix --apply --pr`, which works on a temporary checkout of the default branch.
