---
title: "Configuration"
weight: 60
description: "The .fleetlint.yaml reference: catalogs, facts, scopes, rule overrides, exceptions, baseline."
---

# Configuration

`.fleetlint.yaml` at the repository root (`fleetlint.yaml` is also accepted). Everything is optional, and the whole policy of a repository is in this one file. `fleetlint schema` prints its JSON Schema; [integrations](integrations.md#editors) shows how to get completion in an editor.

```yaml
version: 1
catalog: { version: v0.2.0 }        # another catalog version than the built-in one
extends:
  - fleetlint:recommended           # a built-in preset
  - fleetlint:slop                  # the add-on with slop heuristics
  - https://example.com/catalog.yaml#sha256-<digest>
  - git+https://git.example.com/org/standards.git//catalog.yaml@<commit>
facts:
  tier: 1
  visibility: public
  taskrunner: just
  container: podman
scopes:
  - path: web
    facts: { stacks: [node] }
rules:
  hooks/pre-push-check: { enabled: false, reason: "CI runs the full check" }
  taskrunner/targets: { params: { required: [fmt, lint, test, check] } }
  deps/vulnerability-scan:
    accept:
      - { name: our-scanner, expr: 'text(taskrunner.file).contains("acme-scan")' }
exceptions:
  - rule: ci/actions-pinned
    match: ".github/workflows/android.yml"
    reason: "flutter-action has no stable SHA"
    until: 2027-03-31
```

## extends

The catalogs to apply, in order; a later one overrides an earlier one rule by rule. Without the key, `fleetlint:recommended` is used.

| Reference | Meaning |
|---|---|
| `fleetlint:minimal`, `fleetlint:recommended`, `fleetlint:strict`, `fleetlint:oss`, `fleetlint:slop` | a preset of the catalog built into the binary (or of the pinned version, see below) |
| a path | a catalog file, or a directory of them, in the repository or next to it |
| `https://…#sha256-<digest>` | a catalog over https; the digest is required |
| `git+<url>//<path>@<tag or commit>` | a file in a git repository; a tag additionally needs `#sha256-<digest>`, a full commit SHA does not |
| `oci://<registry>/<repository>:<tag>` or `@sha256:<digest>` | a catalog artifact in a container registry, signed with cosign; a tag needs `signers` in a sources file, see [organisations](organisations.md#catalogs-from-a-registry-oci-signatures-private-templates) |
| `org`, `team/<name>` | a name from a `sources` file, see [organisations](organisations.md) |

The presets build on each other: `minimal` holds the rules no repository should fail; `recommended` (the default) adds the task-runner contract, hooks, lint configuration, CI and release checks; `strict` is `recommended` with every warning an error, every informational rule a warning, and no exceptions on the security rules; `oss` is `recommended` with the `public/*` family switched on whatever the detected visibility, for repositories that are about to be published or live on a forge without a visibility API; `slop` is an add-on with the heuristic `slop/*` rules (see [slop](slop.md)).

Catalogs referenced by https or git are fetched on every run. Presets need no network.

## catalog

Every binary carries one version of the catalog; `fleetlint --version` names it. A repository can use another:

```yaml
version: 1
catalog:
  version: v0.2.0          # a tag or a full commit SHA of the catalog repository
  # repo: git@github.com:acme/fleetlint-catalog.git   # a fork; default is the fleetlint project's
extends: [fleetlint:recommended]
```

- `fleetlint:<preset>` and the fix templates then come from that version, for this repository only. Every report says `catalog v0.2.0 (<commit>), pinned in .fleetlint.yaml`.
- The version is fetched once with git, using the credentials git already has, and kept in the user's cache directory (`FLEETLINT_CACHE_DIR` overrides the location, for CI). Later runs, hooks included, read the cache and need no network.
- A commit SHA cannot move. A tag can; the report shows the commit a tag resolved to when it was fetched.
- A catalog states the engine level it was written for (`metadata.engine`). A version this binary cannot run is refused with one message that says whether to upgrade fleetlint or choose another catalog version, instead of rules failing one by one.


## facts

fleetlint detects these on every run; `fleetlint facts` prints them with where each came from. Pin one only when detection is wrong or when you are stating an intention.

| Fact | Values | Detected from |
|---|---|---|
| `tier` | `1` production or public, `2` a tool you rely on, `3` an experiment | public or has a release pipeline: 1; otherwise 3 |
| `visibility` | `public`, `private` | not detected by `check`; `init` asks the forge once and writes it |
| `stacks` | `go`, `python`, `rust`, `node`, `kotlin`, `flutter` | manifests at the root |
| `forge` | `github`, `gitea`, `gitlab` | the `origin` remote |
| `taskrunner` | `make`, `just`, `task`, `npm-scripts`, `gradle` | the first of Makefile, justfile, Taskfile, Gradle, package.json scripts |
| `container` | `none`, `devcontainer`, `docker`, `podman` | `devcontainer` when a devcontainer.json exists, else `none` |

`taskrunner` and `container` are choices as much as facts. Set `taskrunner` when a repository has more than one runner, or to say which one `fix` should write. Set `container` to say where the task runner's targets run: on the machine, in the dev container, or in an image run with docker or podman. `fix` then writes the runner file, hooks and check workflow for that combination. [The baseline](baseline.md#task-runner-contract) describes both.

## scopes

Parts of the repository that are checked as projects of their own, each with its own stacks. Workspace members (go.work, pnpm, package.json workspaces, Cargo, melos, Gradle) and top-level directories with their own manifest are found without configuration. `scopes:` replaces that list; `scopes: []` turns it off.

### Nested configuration

A workspace member may carry its own `.fleetlint.yaml`:

```yaml
version: 1
facts: { tier: 2 }
rules:
  lint/go-config: { enabled: false, reason: "uses the root .golangci.yml" }
  taskrunner/targets: { severity: warning }
exceptions:
  - rule: repo/no-tracked-junk
    match: "testdata/*.log"
    reason: "parser fixtures"
```

It applies to that scope only and may override facts, configure rules (disable with a reason, change severity, set params) and add exceptions. It cannot extend catalogs or define new rules; those belong in the root file, so there is one place where policy is resolved. Nested exceptions are reported alongside the root's and appear in the fleet policy notes.

## rules

Per rule, any of:

| Key | Effect |
|---|---|
| `enabled: false` | turns the rule off; needs a `reason` |
| `severity` | `error`, `warning` or `info`; lowering it needs a `reason` |
| `params` | the rule's parameters, as its page in the [rule reference](rules/_index.md) lists them |
| `accept` | for outcome rules: further ways of meeting the requirement, each a `name` and an `expr` |

Disabled rules and lowered severities are listed in every report. A rule that an organisation's catalog locked cannot be disabled or lowered; see [organisations](organisations.md).

A key that names no existing rule defines one, in the format described in [writing rules](writing-rules.md):

```yaml
rules:
  repo/arch-doc:
    kind: expr
    expr: file("docs/ARCHITECTURE.md")
    message: "architecture doc missing"
    fix: { human: "write docs/ARCHITECTURE.md" }
```

## exceptions

An exception accepts individual findings of a rule that keeps running:

| Key | Meaning |
|---|---|
| `rule` | the rule id |
| `match` | a glob against the finding's path, or `re:<regex>` against its message; without it every finding of the rule |
| `reason` | required |
| `until` | a date; afterwards the findings count again and the report marks the exception as expired |

## Baseline

`fleetlint baseline` writes `.fleetlint-baseline.json` with a fingerprint (rule, scope, path, message) of every current finding. From then on those findings report as *baselined* instead of failing, so `fleetlint check` is green today and fails only on findings that are new.

The file can only shrink. Re-running `fleetlint baseline` drops entries that no longer match and refuses to add new ones; the report says how many entries are "paid off" after each run. `--reset` starts over and grandfathers everything, which is a deliberate act you should see in a diff. Commit the file; a pull request that grows it is a pull request that weakens the policy.

Baselined findings do not count towards compliance in fleet mode: they are acknowledged debt, listed separately, not success.

A baseline and an exception are different tools: an exception is a reasoned, visible acceptance of a specific finding, optionally with a deadline; a baseline is unexplained legacy that is expected to go away.


`baseline:` in the configuration names another file than `.fleetlint-baseline.json`.

## sources

`sources:` names a file that maps `org` and `team/<name>` to catalog references, so repositories do not carry URLs and pins. See [organisations](organisations.md).
