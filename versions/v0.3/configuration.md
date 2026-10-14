---
title: "Configuration"
weight: 60
description: "The .fleetlint.yaml reference: catalogs, facts, scopes, rule overrides, exceptions, baseline."
---

# Configuration

`.fleetlint.yaml` at the repository root (`fleetlint.yaml` is also accepted). Everything is optional, and the whole policy of a repository is in this one file. `fleetlint schema` prints its JSON Schema (`fleetlint schema catalog` and `fleetlint schema sources` those of catalog and sources files); [integrations](integrations.md#editors) shows how to get completion in an editor.

```yaml
version: 1
catalog: { version: v0.2.0 }        # the catalog version this repository runs with; one per run
sources: git+https://git.example.com/org/standards.git//sources.yaml@<commit>   # the organisation's names, baseline and pin
extends:
  - fleetlint:slop                  # in addition to what the sources file extends
  - team/platform                   # a name from the sources file
overrides:                          # adjust rules the catalogs brought in
  hooks/pre-push-check: { enabled: false, reason: "CI runs the full check" }
  taskrunner/targets: { params: { required: [fmt, lint, test, check] } }
  deps/vulnerability-scan:
    accept:
      - { name: our-scanner, expr: 'text(taskrunner.file).contains("acme-scan")' }
rules:                              # the repository's own rules, or library rules it selects
  - use: slop/commented-out-code
  - id: acme/owner-file
    kind: expr
    severity: error
    expr: file("OWNERS")
    message: "OWNERS is missing"
facts:
  tier: 1
  visibility: public
  container: podman
scopes:
  - path: .                         # the repository root
    stacks: [go]
    taskrunner: just
  - path: web
    stacks: [node]
exceptions:
  - rule: ci/actions-pinned
    match: ".github/workflows/android.yml"
    reason: "flutter-action has no stable SHA"
    until: 2027-03-31
```

The file has the same grammar as a catalog: `rules` defines or selects, `overrides` adjusts, `exceptions` excepts. The repository is the last catalog of the run, at the repository layer; what that allows and forbids is one page: [how rules combine](composition.md).

## extends

The catalogs to apply, in order; a later one overrides an earlier one rule by rule. Without the key, `fleetlint:recommended` is used.

| Reference | Meaning |
|---|---|
| `fleetlint:minimal`, `fleetlint:recommended`, `fleetlint:strict`, `fleetlint:oss`, `fleetlint:slop` | a preset of the catalog built into the binary (or of the pinned version, see below) |
| a path | a catalog file, or a directory of them, inside the repository; an absolute path, `..` or a symlink out of it is refused |
| `https://…#sha256-<digest>` | a catalog over https; the digest is required |
| `git+<url>//<path>@<tag or commit>` | a file in a git repository; a tag additionally needs `#sha256-<digest>`, a full commit SHA does not |
| `oci://<registry>/<repository>:<tag>` or `@sha256:<digest>` | a catalog artifact in a container registry, signed with cosign; a tag needs `signers` in a sources file, see [organisations](organisations.md#catalogs-from-a-registry-oci-signatures-private-templates) |
| `org`, `team/<name>` | a name from a `sources` file, see [organisations](organisations.md) |

The presets build on each other: `minimal` holds the rules no repository should fail; `recommended` (the default) adds the task-runner contract, hooks, lint configuration, CI and release checks; `strict` is `recommended` with every warning an error, every informational rule a warning, and no exceptions on the security rules; `oss` is `recommended` with the `public/*` family switched on whatever the detected visibility, for repositories that are about to be published or live on a forge without a visibility API; `slop` is an add-on with the heuristic `slop/*` rules (see [slop](slop.md)).

Catalogs referenced by https or git are fetched on every run. Presets need no network.

## catalog

Every binary carries one version of the catalog; `fleetlint version` names it, and `fleetlint catalog version` shows the version a repository runs with and each catalog it loads. A run uses exactly one version — for the presets, the rule library, and the fix templates — and every catalog in the run must build on that version:

```yaml
version: 1
catalog:
  version: v0.2.0          # a tag or a full commit SHA of the catalog repository
  # repo: git@github.com:acme/fleetlint-catalog.git   # a fork; default is the fleetlint project's
extends: [fleetlint:recommended]
```

- Without `catalog:` the built-in version runs. A sources file may set the pin for every repository that uses it; a repository may repeat it, not change it (a different pin is an error).
- An organisation or team catalog states in its `metadata.catalog` which version it builds on. If that is not the run's version, the run fails with both versions named; this is what makes the catalog mean the same rules in every repository.
- The version is fetched once with git, using the credentials git already has, and kept in the user's cache directory (`FLEETLINT_CACHE_DIR` overrides the location, for CI). Later runs, hooks included, read the cache and need no network.
- A commit SHA cannot move. A tag can; the report shows the commit a tag resolved to when it was fetched.
- A catalog states the engine level it was written for (`metadata.engine`). A version this binary cannot run is refused with one message that says whether to upgrade fleetlint or choose another catalog version, instead of rules failing one by one.

## facts

fleetlint detects these on every run; `fleetlint facts` prints them with where each came from. Pin one only when detection is wrong or when you are stating an intention.

| Fact | Values | Detected from |
|---|---|---|
| `tier` | `1` production or public, `2` a tool you rely on, `3` an experiment | inferred: public or has a release pipeline: 1; CI or tags: 2; otherwise 3 (`default`). `fleetlint facts` and every report say which fact decided |
| `visibility` | `public`, `private` | not detected by `check`; `init` asks the forge once and writes it |
| `forge` | `github`, `gitea`, `gitlab` | the `origin` remote |
| `container` | `none`, `devcontainer`, `docker`, `podman` | `devcontainer` when a devcontainer.json exists, else `none` |

`facts:` holds what applies to the whole repository. Stacks and the task runner are set per directory, under [`scopes`](#scopes).

`container` is a choice as much as a fact. Set it to say where the task runner's targets run: on the machine, in the dev container, or in an image run with docker or podman. `fix` then writes the runner file, hooks and check workflow for that combination. [The baseline](baseline.md#task-runner-contract) describes both.

## scopes

Parts of the repository that are checked as projects of their own, each with its own stacks. Workspace members (go.work, pnpm, package.json workspaces, Cargo, melos, Gradle) and top-level directories with their own manifest are found without configuration. Listing other paths under `scopes:` replaces that list; `scopes: []` turns it off.

Each entry may pin what detection finds in its directory; nothing inherits it, so a member states its own stack:

| Key | Values | Detected from |
|---|---|---|
| `path` | a directory relative to the root; `.` is the root itself | |
| `stacks` | `go`, `python`, `rust`, `node`, `kotlin`, `flutter`, `java`, `dotnet`, `cpp`, `ruby`, `php`, `hugo` | manifests in the directory |
| `taskrunner` | `make`, `just`, `task`, `npm-scripts`, `gradle` | the first of Makefile, justfile, Taskfile, Gradle, package.json scripts |

`path: .` pins the root and adds no scope: listed alone, members are still discovered. Set `taskrunner` when a directory has more than one runner, or to say which one `fix` should write.

Before 0.3, `facts.stacks` and `facts.taskrunner` applied to every scope and a scope wrote `facts: {stacks: [...]}`. Both are still read in 0.3 with a deprecation warning: `facts.stacks` and `facts.taskrunner` pin the root only, and a scope's `facts.stacks` is read as its `stacks`.

### Nested configuration

A workspace member may carry its own `.fleetlint.yaml`:

```yaml
version: 1
facts: { tier: 2 }
overrides:
  lint/go-config: { enabled: false, reason: "uses the root .golangci.yml" }
  taskrunner/targets: { severity: warning, reason: "a prototype" }
exceptions:
  - rule: repo/no-tracked-junk
    match: "testdata/*.log"
    reason: "parser fixtures"
```

It applies to that scope only and may override facts, adjust rules (disable with a reason, change severity, set params, add accepts) and add exceptions. It cannot extend catalogs or define rules; those belong in the root file, so there is one place where policy is resolved. Nested exceptions are reported alongside the root's and appear in the fleet policy notes.

## overrides

Adjustments to rules the catalogs brought in, keyed by rule id or by a pattern over ids (`"*"`, `"release/*"`; patterns apply first):

| Key | Effect |
|---|---|
| `enabled: false` | turns the rule off; needs a `reason`. Refused for a rule a catalog locked or gave a severity floor |
| `severity` | `error`, `warning` or `info`; lowering it needs a `reason` and stays above a catalog's floor |
| `raise` | lift the severity that many steps instead, capped at error |
| `params` | the rule's parameters, as its page in the [rule reference](rules/_index.md) lists them |
| `accept` | for outcome rules: further ways of meeting the requirement, each a `name` and an `expr` |

Disabled rules and lowered severities are listed in every report with their reason. The policy keys (`locked`, `min_severity`, `exceptions`) and the applicability keys (`when`, `tiers`) belong to catalogs; the repository adjusts, it does not set policy. A rule a catalog locked cannot be disabled, lowered or reshaped (`params`, `accept`) here; see [how rules combine](composition.md).

## rules

The repository's own rules, a list in the catalog format described in [writing rules](writing-rules.md): full definitions with an `id`, or `use:` entries that select rules from the library. A terse definition is enough: the id serves as title, the message as requirement.

```yaml
rules:
  - use: slop/commented-out-code       # a library rule the extended presets did not select
  - id: repo/arch-doc
    kind: expr
    severity: warning
    expr: file("docs/ARCHITECTURE.md")
    message: "architecture doc missing"
    fix: { human: "write docs/ARCHITECTURE.md" }
```

An id is `family/name` in lowercase letters, digits and dashes. A rule a catalog already defines cannot be redefined here; adjust it under `overrides`. The repository's own rules may not set `locked`, `min_severity` or `exceptions`: no layer comes after the repository for them to bind. Rules defined in the repository may be `command` rules, which catalogs may not carry.

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

`sources:` names the organisation's sources file. It maps `org` and `team/<name>` to catalog references, so repositories carry no URLs and pins; it may also set the catalog pin and the baseline `extends` every repository gets, and the `signers` whose signatures make registry catalogs trustworthy. See [organisations](organisations.md).
