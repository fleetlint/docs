---
title: "Configuration"
weight: 60
description: "The .fleetlint.yaml reference: catalogs, facts, scopes, rule overrides, exceptions, baseline."
---

# Configuration

`.fleetlint.yaml` at the repository root (`fleetlint.yaml` is also accepted). Everything is optional, and the whole policy of a repository is in this one file. `fleetlint schema` prints its JSON Schema (`fleetlint schema catalog` and `fleetlint schema sources` those of catalog and sources files); [integrations](integrations.md#editors) shows how to get completion in an editor.

```yaml
version: 1
catalog: { version: v0.1.0 }        # the catalog version this repository runs with; one per run
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

The file has the same grammar as a catalog: `rules` defines or selects, `overrides` adjusts, `exceptions` excepts. The repository is the last catalog of the run; what that allows and forbids is one page: [how rules combine](composition.md). `fleetlint hierarchy` prints the catalogs of a run in the order they apply.

## extends

The catalogs to apply, in order: a later one adjusts an earlier one within the earlier one's policy (locks, floors, forbidden exceptions only tighten). A catalog's includes apply before it. The sources file's `extends` comes before this list. Without the key, `fleetlint:recommended` is used.

| Reference | Meaning |
|---|---|
| `fleetlint:minimal`, `fleetlint:recommended`, `fleetlint:strict`, `fleetlint:oss`, `fleetlint:slop` | a preset of the catalog built into the binary (or of the pinned version, see below) |
| a path | a catalog file, or a directory of them, inside the repository; an absolute path, `..` or a symlink out of it is refused |
| `https://…#sha256-<digest>` | a catalog over https; the digest is required |
| `git+<url>//<path>@<tag or commit>` | a file in a git repository; a tag additionally needs `#sha256-<digest>`, a full commit SHA does not |
| `oci://<registry>/<repository>:<tag>` or `@sha256:<digest>` | a catalog artifact in a container registry, signed with cosign; a tag needs `signers` in a sources file, see [organisations](organisations.md#catalogs-from-a-registry-oci-signatures-private-templates) |
| `org`, `team/<name>` | a name from a `sources` file, see [organisations](organisations.md) |

The presets build on each other: `minimal` holds the rules no repository should fail (nothing secret, accidental or oversized tracked, no conflict markers, hooks with a secret scan, a license in public repositories); `recommended` (the default) adds the task-runner contract, hooks, formatter, linter and type-checker configuration, dependencies, CI and release checks; `strict` is `recommended` with every warning an error, every informational rule a warning, and no exceptions on the security rules; `oss` is `recommended` with its `public/*` rules switched on whatever the detected visibility, for repositories that are about to be published or live on a forge without a visibility API; `slop` is an add-on with the heuristic `slop/*` rules and, for public repositories, `public/no-agent-files` and `public/no-ai-attribution` (see [slop](slop.md)). The [rule catalog](rule-catalog.md) lists which preset selects each rule.

Catalogs referenced by https or git are fetched on every run. Presets need no network.

## catalog

Every binary carries one version of the catalog; `fleetlint version` names it, and `fleetlint catalog version` shows the version a repository runs with and each catalog it loads. A run uses exactly one version — for the presets, the rule library, and the fix templates — and every catalog in the run must build on that version:

```yaml
version: 1
catalog:
  version: v0.1.0          # a tag or a full commit SHA of the catalog repository
  # repo: git@github.com:acme/fleetlint-catalog.git   # a fork; default is the fleetlint project's
extends: [fleetlint:recommended]
```

- Without `catalog:` the built-in version runs. A sources file may set the pin for every repository that uses it; a repository may repeat it, not change it (a different pin is an error).
- An organisation or team catalog states in its `metadata.catalog` which version it builds on. If that is not the run's version, the run fails with both versions named; this is what makes the catalog mean the same rules in every repository.
- The version is fetched once with git, using the credentials git already has, and kept in the user's cache directory (`FLEETLINT_CACHE_DIR` overrides the location, for CI). Later runs, hooks included, read the cache and need no network.
- A commit SHA cannot move. A tag can; the report shows the commit a tag resolved to when it was fetched.
- The same version also comes from a registry: every catalog tag is published as a signed OCI artifact holding the whole catalog (presets, rules, stacks, templates, renamed ids). Pin it instead of the git tag where git access is awkward or a registry is the trusted source:

  ```yaml
  catalog:
    oci: ghcr.io/fleetlint/catalog:v0.1.0      # or ...:v0.1.0@sha256:<digest> to pin the content
  extends: [fleetlint:recommended]
  ```

  A tag of `ghcr.io/fleetlint/catalog` is verified against the signature of the catalog repository's publish workflow; a mirror or a fork at a tag needs `signers` in the sources file; a `@sha256:` digest needs neither. `oci` names the version on its own (no `version` or `repo` next to it), and `ghcr.io/fleetlint/catalog:v0.1.0` is the same version as the git tag `v0.1.0` for every catalog that builds on it. The artifact is read once per run.
- A catalog states the engine level it was written for (`metadata.engine`). A version this binary cannot run is refused with one message that says whether to upgrade fleetlint or choose another catalog version, instead of rules failing one by one.

## facts

fleetlint detects these on every run; `fleetlint facts` prints them with where each came from. `init` writes the detected artifacts (and, under [`scopes`](#scopes), the stacks), so the file says what is checked; set the others only when detection is wrong or when you are stating an intention.

| Fact | Values | Detected from |
|---|---|---|
| `tier` | `1` production or public, `2` a tool you rely on, `3` an experiment | inferred: public or has a release pipeline: 1; CI or tags: 2; otherwise 3 (`default`). A scope whose tier nobody sets takes the repository's when that is more serious, since workflows and releases live at the root. `fleetlint facts` and every report say which fact decided |
| `visibility` | `public`, `private` | not detected by `check`; `init` asks the forge once and writes it |
| `forge` | `github`, `gitea`, `gitlab` | the `origin` remote |
| `container` | `none`, `devcontainer`, `docker`, `podman` | `devcontainer` when a devcontainer.json exists, else `none` |
| `artifacts` | artifact kinds the catalog defines: `release-files`, `image`, `oci-artifact`, `helm-chart`, `npm`, `pypi`, `crate`, `gem`, `maven`, `nuget`, `pub`, `android-app`, `apple-app`; or `{kind, name, workflows}` naming one published artifact and the CI files that publish it | the workflows that publish each (`gh release create`, a build-push action with `push: true`, `npm publish`, ...), by the catalog's `artifacts/<kind>.yaml`, which names the instances of a kind where it can (an image reference, a chart path); `fleetlint facts` lists them. `init` writes what it detects here; add an entry when a publish step hides in a reusable workflow, with the name and workflows so the release rules can read them; `artifacts: []` says nothing is published. The list replaces detection, and `check` notes an artifact (or a workflow of a named one) detection finds beyond it; a kind without a name covers its instances. The release capabilities are checked once per published artifact, and a finding names the one that fails |

`facts:` holds what applies to the whole repository. Stacks and the task runner are set per directory, under [`scopes`](#scopes).

The owner is detected but not set here: the file that names it is the place to change it. `fleetlint facts` shows it as `owner` with the file it came from. Backstage's `catalog-info.yaml` wins with `spec.owner` (`group:default/payments` and `payments` are both `payments`; another namespace stays, `group:ops/payments` is `ops/payments`). Without it, the CODEOWNERS default owner counts: the first owner of the last rule for every file (`*`, `/*`, `**` or `/**`), without its `@`, from `.github/CODEOWNERS`, `CODEOWNERS`, `docs/CODEOWNERS`, `.gitea/CODEOWNERS` or `.gitlab/CODEOWNERS`, the first that exists; GitLab sections are skipped. Nothing asks the forge. In fleet mode the owner is the repository's team unless its fleet file entry names one ([fleet](fleet.md)).

`container` is a choice as much as a fact. Set it to say where the task runner's targets run: on the machine, in the dev container, or in an image run with docker or podman. `fix` then writes the runner file, hooks and check workflow for that combination. [The baseline](baseline.md#task-runner-contract) describes both.

## scopes

Parts of the repository that are checked as projects of their own, each with its own stacks. Workspace members (go.work, pnpm, package.json workspaces, Cargo, melos, Gradle) and top-level directories with their own manifest are found without configuration. Listing other paths under `scopes:` replaces that list; `scopes: []` turns it off.

Each entry may pin what detection finds in its directory; nothing inherits it, so a member states its own stack. `init` writes the root and every member with the stacks it detected, so the file says which stack rules apply where; `check` notes a stack detection finds beyond a directory's list, so a stack added later is listed or left out knowingly:

| Key | Values | Detected from |
|---|---|---|
| `path` | a directory relative to the root; `.` is the root itself | |
| `stacks` | a stack the catalog defines in `stacks/`: `go`, `python`, `rust`, `node`, `kotlin`, `flutter`, `java`, `dotnet`, `cpp`, `ruby`, `php`, `hugo` in the fleetlint catalog | the stack definitions' markers in the directory, see [stacks](writing-rules.md#stacks) |
| `taskrunner` | `make`, `just`, `task`, `npm-scripts`, `gradle` | the first of Makefile, justfile, Taskfile, Gradle, package.json scripts |

`path: .` pins the root and adds no scope: listed alone, members are still discovered. Set `taskrunner` when a directory has more than one runner, or to say which one `fix` should write. A stack name the catalog does not define is a configuration error.

Before 0.3, `facts.stacks` and `facts.taskrunner` applied to every scope and a scope wrote `facts: {stacks: [...]}`. Both are still read in 0.3 with a deprecation warning: `facts.stacks` and `facts.taskrunner` pin the root only, and a scope's `facts.stacks` is read as its `stacks`.

### Nested configuration

A workspace member may carry its own `.fleetlint.yaml`:

```yaml
version: 1
facts: { tier: 2 }
overrides:
  lint/strict/go: { enabled: false, reason: "generated client, linted where it is generated" }
  taskrunner/targets: { severity: warning, reason: "a prototype" }
exceptions:
  - rule: repo/no-tracked-junk
    match: "testdata/*.log"
    reason: "parser fixtures"
```

It applies to that scope only and may override facts, adjust rules (disable with a reason, change severity, set params, add accepts) and add exceptions. It cannot extend catalogs or define rules; those belong in the root file, so there is one place where policy is resolved. Nested exceptions are reported alongside the root's and appear in the fleet policy notes.

## overrides

Adjustments to rules the catalogs brought in, keyed by rule id or by a pattern over ids (`"*"`, `"release/*"`; patterns apply first). An override on a [capability](writing-rules.md#capabilities-one-requirement-one-implementation-per-stack) reaches every implementation (`lint/configured` for all stacks); `<capability>/<stack>` adjusts one (`lint/configured/go`). Exceptions work the same way. Every implementation that runs must pass; a repository cannot change that.

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

An id is `family/name` in lowercase letters, digits and dashes. A rule a catalog already defines cannot be redefined here; adjust it under `overrides`. The repository's own rules may not set `locked`, `min_severity` or `exceptions`: no catalog comes after the repository for them to bind. Rules defined in the repository may be `command` rules, which catalogs may not carry.

## exceptions

An exception accepts individual findings of a rule that keeps running:

| Key | Meaning |
|---|---|
| `rule` | the rule id |
| `match` | a glob against the finding's path, or `re:<regex>` against its message (a regex that does not compile is a configuration error); without it every finding of the rule |
| `reason` | required |
| `until` | a date; afterwards the findings count again and the report marks the exception as expired |
| `approved_by` | who agreed to the exception, a person or team as your organization names them (`"@acme/security"`); shown in the table, the fleet report and SARIF. fleetlint records it and does not check it: who may approve is enforced by review of `.fleetlint.yaml`, for example with a CODEOWNERS entry for it |

A catalog's `exception_policy` can require `until` and `approved_by` and cap how far `until` may lie ahead; see [organisations](organisations.md#exception-policy).

## Baseline

`fleetlint baseline` writes `.fleetlint-baseline.json` with a fingerprint (rule, scope, path, message, and the artifact's name for a finding about a named artifact) of every current finding. Where a report points (a rule's `locate`) is not part of it. From then on those findings report as *baselined* instead of failing, so `fleetlint check` is green today and fails only on findings that are new. Two findings with the same fingerprint (the same message on the same file) are two entries, so a third copy is new and fails.

The file can only shrink. Re-running `fleetlint baseline` drops entries that no longer match and refuses to add new ones; the report says how many entries are "paid off" after each run. `--reset` starts over and grandfathers everything, which is a deliberate act you should see in a diff. Commit the file; a pull request that grows it is a pull request that weakens the policy.

Since 0.8 a release finding about a named artifact (an image, a chart, an OCI artifact) carries the name and so has a fingerprint of its own: a baseline written by 0.7 no longer covers it, and `--reset` grandfathers the findings again if that is what you want. Every other fingerprint is unchanged.

Baselined findings do not count towards compliance in fleet mode: they are acknowledged debt, listed separately, not success.

A baseline and an exception are different tools: an exception is a reasoned, visible acceptance of a specific finding, optionally with a deadline; a baseline is unexplained legacy that is expected to go away.


`baseline:` in the configuration names another file than `.fleetlint-baseline.json`.

## sources

`sources:` names the organisation's sources file. It maps `org` and `team/<name>` to catalog references, so repositories carry no URLs and pins; it may also set the catalog pin and the baseline `extends` every repository gets, and the `signers` whose signatures make registry catalogs trustworthy. See [organisations](organisations.md).
