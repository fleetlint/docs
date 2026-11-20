---
title: "Writing rules"
weight: 90
description: "The rule format, from a first rule in .fleetlint.yaml to catalog libraries: testing a rule, expressions, foreach, outcome rules, messages, fix actions, capabilities, artifacts, stacks, command rules and the engine level."
---

# Writing rules

A rule is YAML: an id, a severity and a check written in [CEL](https://cel.dev/). This page starts with one rule in a repository and ends with what only a catalog's library can hold. The [CEL reference](cel-reference.md) lists every variable and function an expression can use; `fleetlint schema catalog` prints the JSON Schema of the catalog format.

## Where rules live

| Place | Holds | More |
|---|---|---|
| `.fleetlint.yaml`, under `rules:` | the repository's own rules, as a list; `- use: <id>` selects a library rule | [configuration](configuration.md#rules) |
| a catalog file | rules for many repositories, in the [catalog format](#catalog-format), plus `overrides:` and `exceptions:` for the rules it includes | [organisations](organisations.md) |
| a library, the `rules/` directory of a catalog | one rule per file at `rules/<family>/<name>.yaml`, the path spelling the id; capabilities and their implementations | [capabilities](#capabilities-one-requirement-one-implementation-per-stack) |
| presets, `fleetlint:<name>` | selections from the library of [fleetlint/catalog](https://github.com/fleetlint/catalog), built into the binary | [rule catalog](rule-catalog.md) |

The library of fleetlint/catalog is where its rules are read, changed or added; the [rule pages](rules/_index.md) are generated from it. Your own catalog can ship a `rules/` directory too, as an OCI artifact or a git tree pinned to a full commit SHA; [organisations](organisations.md#publishing-and-pinning) covers how catalogs are published and pinned.

## A first rule

In `.fleetlint.yaml`:

```yaml
version: 1
rules:
  - id: acme/runbook
    title: The service has a runbook
    kind: expr
    severity: error
    expr: file("docs/RUNBOOK.md")
    message: "docs/RUNBOOK.md is missing"
    requirement: docs/RUNBOOK.md says how to run, stop and debug the service.
    fix: { human: "Write docs/RUNBOOK.md." }
```

- `id` is `family/name` in lowercase letters, digits and dashes. Overrides, exceptions and reports key on it, so keep it stable.
- `kind: expr` passes when `expr` is true; `file()` is true when the path exists.
- `severity` is `error`, `warning` or `info` and is required. By default `fleetlint check` fails on `error`.
- `message` is what a finding says. `requirement` and `fix.human` are what `fleetlint explain` and the reports print.

A repository's own rule may be terse: with only `id`, `kind`, `severity`, `expr` and `message`, the id serves as the title, the message as the requirement, and `fix.human` is "See the rule's message.". A catalog rule needs `title`, `requirement` and `fix.human`.

The rule runs with the repository's other rules: the catalogs `extends` and the sources file name, or `fleetlint:recommended` when neither names one. `fleetlint check` lists its finding among theirs.

## Testing a rule

To see a rule on its own, test it in a throwaway repository whose configuration extends one catalog file that holds the rule. The same file can later be published as a catalog.

```sh
mkdir rule-test && cd rule-test && git init -q
cat > .fleetlint.yaml <<'EOF'
version: 1
extends: [./acme.yaml]
EOF
```

`acme.yaml`:

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata: {name: acme, version: 0.1.0, engine: 7}
rules:
  - id: acme/runbook
    title: The service has a runbook
    kind: expr
    severity: error
    expr: file("docs/RUNBOOK.md")
    message: "docs/RUNBOOK.md is missing"
    requirement: docs/RUNBOOK.md says how to run, stop and debug the service.
    fix: { human: "Write docs/RUNBOOK.md." }
```

Without the file the rule fails, and `check` exits 1:

```text
$ fleetlint check
rule-test  stacks: none  forge: unknown  visibility: unknown  tier: 3 (default)  release: no
0 passed   0 warnings   1 errors   0 excepted   0 not applicable

FAIL  acme/runbook  docs/RUNBOOK.md is missing
                    fix: Write docs/RUNBOOK.md.

catalogs in the order they applied (a later one adjusts an earlier one within its policy):
#  catalog          label  name                   pinned by               builds on  contributes
1  ./acme.yaml      acme   acme@0.1.0             file in the repository  -          1 rule
2  .fleetlint.yaml  repo   .fleetlint.yaml@local  file in the repository  -          nothing

fleetlint v0.11.1, catalog v0.8.0
```

With it, the rule passes and `check` exits 0; `-v` lists passing rules too. The file need not be committed.

```text
$ mkdir docs && echo '# Runbook' > docs/RUNBOOK.md
$ fleetlint check -v
rule-test  stacks: none  forge: unknown  visibility: unknown  tier: 3 (default)  release: no
1 passed   0 warnings   0 errors   0 excepted   0 not applicable

ok  acme/runbook
…
```

`fleetlint explain` prints the rule as the run loaded it:

```text
$ fleetlint explain acme/runbook
acme/runbook: The service has a runbook
severity: error   kind: expr   tiers: all   stacks: any   source: acme@0.1.0   label: acme

Requirement
  docs/RUNBOOK.md says how to run, stop and debug the service.

Check
  file("docs/RUNBOOK.md")

Fix
  Write docs/RUNBOOK.md.
```

| Command | Shows |
|---|---|
| `fleetlint check -v` | passing and not-applicable rules too, with the satisfier that passed an outcome rule (`satisfied by goreleaser`) or why a rule does not apply (`n/a: tier 3 not in [1]`) |
| `fleetlint check -f json` | every result with its findings, for a script that asserts on them |
| `fleetlint explain <id>` | the rule as loaded: severity, kind, tiers, source, label, requirement, check, fix |
| `fleetlint facts` | the facts `repo`, `release` and `taskrunner` are built from, and where each came from |
| `fleetlint hierarchy` | the catalogs in the order they applied |
| `fleetlint catalog digest acme.yaml` | the digest to publish the file with, `sha256-<hex>` |

A local catalog file brings neither a `rules/` library nor `templates/`, so capability implementations and fix templates cannot be tested this way. Push them and pin the commit (`git+https://…//catalog.yaml@<commit>`), or push an OCI artifact; a registry on `localhost` is spoken to over plain http.

### When the configuration does not load

A rule that does not load stops the run before any rule is checked, with exit 2 and one message:

| Message | Cause |
|---|---|
| `[3:15] mapping was used where sequence is expected` | `rules:` written as a map. It is a list of `- id:` entries; adjustments to included rules go under `overrides:`, which is a map. |
| `rule <id>: severity is required (error, warning or info)` | every rule and every partial states its severity |
| `rule <id>: unknown kind ""` | `kind` is missing |
| `rule <id>: title and requirement are required` | a catalog rule without them, or a repository's terse rule without `message` |
| `mapping value is not allowed in this context` | an expression with `: ` or `{` that YAML reads as a map; quote it |
| `locate: … undeclared reference to 'docs'` | `locate: docs/RUNBOOK.md` is CEL; a fixed path needs inner quotes: `'"docs/RUNBOOK.md"'` |
| `expr: … undeclared reference to 'fiel' (did you mean 'file'?)` | a typo in an expression; every expression is type-checked when the configuration loads |
| `expr: … result must be bool, got string` | `expr`, `when` and satisfiers must yield a bool |
| `catalog ./acme.yaml builds on catalog v0.7.0; this run uses the built-in catalog (v0.8.0)` | `metadata.catalog` names another version than the run uses: pin it in `.fleetlint.yaml` or the sources file, or update the catalog |
| `include "org" must be a preset, an https URL or a git reference` | a remote catalog includes others by pinned reference; sources-file names work in `extends` only |
| `… set a severity floor of warning; off is below every floor` | a rule with a floor cannot be disabled |
| `rule <id>: a capability belongs in a catalog's rules/ library` | `kind: capability` in a rules list |
| ``rules: a `use: <id>` entry selects a library rule and takes no other keys`` | adjust a selected rule under `overrides:` |
| `catalog <name> <version> needs engine level 9 and this fleetlint has 7` | the catalog is newer than the binary: upgrade fleetlint |

A git catalog pinned to a tag loads, but its `rules/` and `templates/` do not: the run warns on stderr that they are ignored and to pin a full commit SHA.

[Troubleshooting](troubleshooting.md) has the repository and policy errors, with what to change.

## Catalog format

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata:
  name: acme-standards
  version: 1.2.0
  engine: 7                           # the engine level the catalog is written for
  label: org                          # who owns it; reports attribute by it (default: the sources-file name, else the name)
  catalog: { version: v0.8.0 }        # the fleetlint catalog includes and `use:` come from; a remote catalog that uses either must state it
  includes: [fleetlint:minimal]       # optional; loaded first
rules:
  - use: release/*                    # select library rules: an id, or a family with /*
  - id: acme/changelog                # family/name; lowercase letters, digits, dashes
    title: Changes are collected in a changelog
    kind: expr                        # expr | outcome | command | go; a capability only as a library file
    severity: warning                 # error | warning | info
    tiers: [1, 2]                     # omit = every tier
    # stacks: [go]                    # omit = any stack
    scope: root                       # root | each (default) | members: where in a monorepo it runs
    when: release.exists              # applicability; false = not applicable, not a failure
    expr: file("CHANGELOG.md") && text("CHANGELOG.md").contains(params.heading)
    message: "CHANGELOG.md has no Unreleased section"
    locate: '"CHANGELOG.md"'          # the file a finding points at
    requirement: CHANGELOG.md has an Unreleased section that collects the changes since the last release.
    rationale: Users see what changed without reading the commits.
    fix:
      human: Add an Unreleased section to CHANGELOG.md.
      agent: Create CHANGELOG.md from the template if it is missing; otherwise add the Unreleased heading above the first version. Change nothing else.
      actions:                        # optional mechanical steps for `fleetlint fix`
        - template: CHANGELOG.md
          to: CHANGELOG.md
    params: { heading: "## [Unreleased]" }   # read by the expressions as params.heading
    refs:                             # where the practice comes from, strongest source first
      - {url: "https://keepachangelog.com/en/1.1.0/", kind: standard}
      - "https://fleetlint.org/baseline/#releases"
```

Next to `rules:`, a catalog may have `overrides:`, `exceptions:` and `exception_policy:`; [organisations](organisations.md) describes them.

## Expressions

### Variables and functions

The common ones:

| Name | Is |
|---|---|
| `file(path)` | true when the exact path exists, file or directory |
| `exists(glob)` | true when any file matches; `**` crosses directories |
| `text(path)`, `lines(path)` | the contents, `""` or `[]` when the file is absent |
| `yaml(path)`, `json(path)`, `toml(path)` | the parsed document, `null` when the file is absent |
| `grep(glob, regex)` | every matching line as `{path, line, text, match}` |
| `workflows()`, `steps(path)` | the CI files, and every step of one as `{job, name, uses, run, with}` |
| `repo`, `release`, `taskrunner` | the facts: `repo.tier`, `repo.stacks`, `release.exists`, `taskrunner.targets`, … |
| `params`, `item`, `artifact` | the rule's parameters, the element of a `foreach`, the artifact an implementation checks |

The [CEL reference](cel-reference.md) has the full list, generated from the code. What holds for all of them:

- Reading a missing key is an evaluation error, which is reported as a rule error, never as a pass. Test with `has(doc.field)` first.
- A rule that cannot read its input errors. `text()`, `lines()`, `scan()` and `yaml()`/`toml()`/`json()` fail for a file that exists but cannot be read (too large, not a regular file, a symlink out of the repository); `commits()` fails when `git log` does.
- `exists()`, `glob()` and stack detection see the tracked files plus the untracked ones git does not ignore, so a gitignored local file cannot make a rule pass on one machine and fail in CI. Vendored and build directories stay out.
- Every expression is type-checked when the configuration loads, for every rule, whether it applies to the repository or not: a typo is a configuration error (exit 2) naming the rule and the field (`when`, `expr`, `foreach`, `locate`, a satisfier or partial).
- An evaluation stops at a cost limit, so a comprehension over every file cannot run for hours.
- YAML reads `: `, a leading `{`, `[` or `"`, and ` #` itself. Quote such an expression in single quotes.

```yaml
expr: '"check" in makefile("Makefile").targets'
expr: 'yaml(".pre-commit-config.yaml").repos.exists(r, r.repo.contains("gitleaks"))'
expr: '!tracked().exists(f, f.matches("\\.env$"))'
expr: 'glob(".github/workflows/*.yml").all(w, has(yaml(w).permissions))'
```

### When a rule applies

| Field | Effect |
|---|---|
| `when` | a CEL condition; false makes the rule not applicable (`n/a: when: …`), never a failure. A `when` that cannot be evaluated is a rule error. |
| `tiers` | the tiers the rule runs at; omitted, every tier |
| `stacks` | runs only where one of the stacks is detected; each must be a stack the catalog defines |
| `scope` | where in a monorepo: `each` (the default) the root and every scope, `root` the root only, `members` the workspace members only |

### params

`params` are values the expressions read as `params.<key>`. A later catalog or the repository changes them with `overrides: {<id>: {params: …}}` without restating the rule; the rule's own catalog changes the rule itself. A locked rule refuses new params.

### foreach

`foreach` turns one rule into a check per element of a list. The list expression runs first, then `expr` once per element, with the element bound to `item`. Every element for which `expr` is false is its own finding:

- A string element that names a file becomes the finding's path. Any other string is appended to the message.
- A map element gives the finding its `path` and `line`, and its `name`, `subject` or `text` (the first one set) is appended to the message.
- The message is the rule's `message`, else its title.

Three rules, added to `acme.yaml` from the walkthrough:

```yaml
  - id: acme/no-todo-in-docs
    title: The documentation has no TODO left
    kind: expr
    severity: warning
    foreach: grep("**/*.md", "\\bTODO\\b")    # every matching line, as {path, line, text, match}
    expr: "false"                             # so each one is a finding
    message: "TODO left in the documentation"
    requirement: No Markdown file contains a TODO.
    fix: { human: "Write the missing text or remove the TODO." }
  - id: acme/job-timeouts
    title: Every CI job has a timeout
    kind: expr
    severity: warning
    foreach: 'workflows().map(w, jobs(w).map(j, {"path": w, "name": j.name, "timeout": j.timeout_minutes})).flatten()'
    expr: item.timeout > 0
    message: "job without a timeout"
    requirement: Every CI job sets a timeout.
    fix: { human: "Set timeout-minutes on the job (timeout on GitLab)." }
  - id: acme/targets
    title: The task runner has the shared targets
    kind: expr
    severity: warning
    params: { required: [lint, test, check] }
    foreach: params.required
    expr: item in taskrunner.targets
    message: "task runner target missing"
    requirement: The task runner has the targets in params.required.
    fix: { human: "Add the missing targets." }
```

In a repository with a TODO in its README, a workflow job without `timeout-minutes` and a Makefile with only `lint`:

```text
warn  acme/job-timeouts     Every CI job has a timeout (1)
                            .github/workflows/check.yml: job without a timeout (test)
                            fix: Set timeout-minutes on the job (timeout on GitLab).
warn  acme/no-todo-in-docs  The documentation has no TODO left (1)
                            README.md:5: TODO left in the documentation (TODO: write the install section)
                            fix: Write the missing text or remove the TODO.
warn  acme/targets          The task runner has the shared targets (2)
                            task runner target missing (test)
                            task runner target missing (check)
                            fix: Add the missing targets.
```

## Outcome rules: satisfiers, partials and accept

An outcome rule asks whether a result is achieved and lists the ways it can be:

- Each satisfier is a named CEL predicate, with an optional `when` guard. The first that holds passes the rule and is reported as the evidence (`satisfied by goreleaser`).
- When none holds, the first partial that holds is the finding, with its own severity and message.
- Otherwise the rule fails with its own severity and message.

```yaml
- id: acme/sbom
  title: Releases ship an SBOM
  kind: outcome
  severity: error
  when: release.exists
  satisfiers:
    - name: goreleaser
      when: file(".goreleaser.yaml")                 # optional guard
      expr: has(yaml(".goreleaser.yaml").sboms)
    - name: syft-in-release
      expr: tagged_workflows().exists(w, steps(w).exists(s, s.run.matches("\\bsyft\\b")))
  partials:                                          # graded results when nothing satisfies
    - name: syft-outside-release
      severity: warning
      expr: workflows().exists(w, steps(w).exists(s, s.run.matches("\\bsyft\\b")))
      message: "an SBOM producer exists but no release workflow runs it"
  message: "no release step generates an SBOM"
  requirement: Every release publishes an SBOM of what it ships.
  fix: { human: "Generate an SBOM in the release workflow (syft, or sboms in GoReleaser)." }
```

A repository that extends the catalog adds its own way with `accept:` under `overrides:`; it is tried after the rule's satisfiers. It can add ways to pass, never remove the requirement:

```yaml
overrides:
  acme/sbom:
    accept:
      - name: own-script
        expr: tagged_workflows().exists(w, steps(w).exists(s, s.run.contains("scripts/sbom.sh")))
```

```text
$ fleetlint check -v
…
ok  acme/sbom  satisfied by own-script
```

`accept` works on outcome rules, and on a capability, where it reaches the outcome implementations. A locked rule refuses it. `tagged_workflows()` are the release pipelines, the CI files a tag push starts; `ci_kind(path)` tells GitHub, Gitea, Forgejo and GitLab apart where a concept exists in one of them only, such as Actions `permissions:`.

## Messages and locations

A finding carries the rule's `message` (a partial's own message, a command rule's printed one). `foreach` adds the item, and an implementation keyed by artifact puts the artifact's name in front (`ghcr.io/x/worker: the image is not signed`).

### Where a finding points

A rule whose finding is about one file says so with `locate:`, a CEL expression yielding that file's scope-relative path:

- `'"README.md"'` for a fixed name (the outer quotes are YAML's, the inner ones CEL's);
- `taskrunner.file != "" ? taskrunner.file : "Makefile"` for one that depends on the repository;
- `artifact.workflows[0]` in an implementation keyed by artifact.

The result becomes the `anchor` of every finding that names no path: the table and the agent output name that file in front of the finding, and SARIF uses it as the location instead of the scope's configuration file. The anchor is where a report points, nothing more: the finding's own path, and with it the baseline fingerprint, exceptions and fixes, stay as observed. A result outside the repository (`../x`, an absolute path) or an expression that fails anchors nothing, and the result's evidence says why. A rule with `foreach` locates each item that names a file itself; `locate` anchors the rest. An implementation inherits `locate` from its capability unless it sets its own.

### Sources

A `refs` entry is a URL, or `{url, kind, section}` when the rule says what kind of source it rests on. `section` names the chapter, requirement or check id. The kinds, strongest first:

| Kind | Source |
|---|---|
| `spec` | a language or format specification, or an official tool (`gofmt`, `go vet`, the npm documentation of a package.json field) |
| `guidance` | official guidance: Go Code Review Comments, PEP 8, the Rust API Guidelines, a forge's documentation of its own feature |
| `style-guide` | a public style guide with clear status |
| `standard` | a standard for process or supply chain: NIST SSDF, SLSA, OpenSSF Scorecard, OWASP ASVS, Keep a Changelog, Conventional Commits, Semantic Versioning |
| `check` | a linter's check, with `section` its id |
| `convention` | a convention of the catalog with no outside source, which says so |

A slogan or a blog post is not a source. The rule pages list the sources, `fleetlint explain` prints them, and the check JSON and `fleet.json` carry them as objects.

## Fix actions and templates

`fix.human` is one line for a person, `fix.agent` the precise instruction for a coding agent. `fix.actions` are the mechanical steps `fleetlint fix` performs:

| Action | Does |
|---|---|
| `{template: <name>, to: <path>}` | writes a template when the file does not exist; never overwrites |
| `{untrack: "*", gitignore: [<pattern>, …]}` | `git rm --cached` the rule's findings, and appends the missing patterns to `.gitignore` |
| `{set: {file, key, value}}` | adds one string to an existing JSON or TOML file |
| `{append: {file, template, unless}}` | adds a template's text to the end of an existing TOML or YAML file |
| `{merge: {file, template}}` | adds to an existing JSON file the keys of a JSON template it lacks |

```yaml
actions:
  - template: "{stack}/pre-commit-config.yaml"   # {stack} = the detected stack
    to: .pre-commit-config.yaml
  - untrack: "*"
    gitignore: ["*.log"]
  - set: {file: package.json, key: license, value: "{license}"}
  - append: {file: pyproject.toml, template: python/ruff.toml, unless: '(?m)^\[tool\.ruff\]'}
  - merge: {file: tsconfig.json, template: node/tsconfig-strict.json}
```

- `set` never changes a key that is already there. JSON takes a top-level key; TOML takes `table.key` in a table written with a `[table]` header. The edit is kept only if the file afterwards parses to exactly the old content plus the key; files it cannot edit that way (JSON with comments, inline tables) are left to a person.
- `{license}` is the SPDX identifier of the repository's LICENSE file when its text is one recognised license; without it the action does nothing. GNU licenses yield no identifier, because the text does not say whether `-only` or `-or-later` applies.
- `append` skips a file that already matches the `unless` regular expression. The result must still parse, otherwise nothing is written and the run reports it. This is how `[tool.ruff]` lands in a pyproject.toml or `[lints]` in a Cargo.toml.
- `merge` works recursively and keeps every value the file has, its member order, number formatting and indentation. A file that is not strict JSON (tsconfig.json with comments) is reported, not rewritten.
- `set`, `append` and `merge` never create the file.

Template names with placeholders:

- `{taskrunner}` is the runner file of the repository's task runner (`Makefile`, `justfile` or `Taskfile.yml`), written with the container switch when `repo.container` is not `none`.
- `{stack}/devcontainer.json` exists for every stack and is written only when `repo.container` is `devcontainer`. `{stack}/check.yml` and the hooks call the repository's runner and follow the container setting.
- `{stack}/pre-commit-config.yaml`, `{stack}/check.yml` and `{stack}/release.yml` are assembled from fragments: the shared part (hygiene, secret scan, commit messages, shell, the pre-push check), then the hooks or toolchain of the root stack, of any second stack in the same directory, and of each nested project.

### Where templates come from

A template name such as `editorconfig` or `go/pre-commit-config.yaml` is the path below `templates/`. The first of these that has the file wins:

1. The catalogs of the run that ship templates, the last one applied first (see [composition](composition.md) for the order).
2. The run's catalog source: the catalog built into the binary, or the version a `catalog:` pin names.

Only two kinds of catalog ship templates: an `oci://` catalog (its files under `templates/`) and a `git+` catalog pinned to a full commit SHA (the `templates/` directory next to the catalog file). A `git+` catalog pinned to a tag, an `https://` catalog, a local catalog file or directory and `.fleetlint.yaml` bring none; a `templates/` directory next to them is not read.

A catalog replaces a template by its file name, as a whole: a template cannot be extended with extra lines. The assembled templates are put together from fragments under `templates/pre-commit/`, `templates/check/` and `templates/release/` (for example `check/head.yml`, `check/go.yml`, `check/tail.yml`), and each fragment can be replaced on its own. The dry run of `fleetlint fix` names the catalog a change's template came from when it is not the catalog source: `(template from catalog oci://...)`.

A repository cannot provide or replace a template itself: `.fleetlint.yaml` has no key for templates, `overrides:` cannot change a rule's `fix.actions`, and a repository cannot redefine a catalog rule. For one repository, run `fleetlint fix` once and edit the file it wrote: `fix` never overwrites a file, and the rule checks what the file achieves, not that it matches the template. For many repositories, publish a catalog that includes the standard preset and ships `templates/<name>`, and extend it from each repository; changing the template then means a new commit or artifact and moving the pin.

## Capabilities: one requirement, one implementation per stack

Capabilities, their implementations, artifacts and stacks exist only in a library: the `rules/`, `artifacts/` and `stacks/` directories of fleetlint/catalog (or a fork of it), and the `rules/` directory a catalog ships as an OCI artifact or a git tree pinned to a full commit SHA. A rules list, in a catalog file or in `.fleetlint.yaml`, cannot define them.

Many requirements are the same for every stack and differ only in the tools: "a linter is configured", "dependencies are scanned", "the toolchain is pinned". A capability states the requirement once; each stack implements it with its own tools.

```yaml
# rules/lint/configured.yaml: the capability
id: lint/configured
title: A linter is configured
kind: capability
severity: warning
tiers: [1, 2]
requirement: Every stack in the repository has its linter configured in the repository.
rationale: …
fix: { human: Configure the stack's linter (see the stack profiles)., agent: … }
refs: ["https://fleetlint.org/stacks/"]
```

```yaml
# rules/lint/configured/go.yaml: its implementation for Go
id: lint/configured/go
kind: outcome
satisfiers:
  - name: golangci-lint-v2
    expr: file(".golangci.yml") && text(".golangci.yml").matches("(?m)^version:\\s*[\"']?2")
message: "no Go linter configuration"
requirement: A golangci-lint v2 configuration is committed.
fix: { human: Add .golangci.yml (version 2)., actions: [{template: golangci.yml, to: .golangci.yml}] }
```

- An implementation lives at `rules/<family>/<name>/<stack>.yaml`. The last path segment is a stack id from the catalog's `stacks/`, and the implementation runs only where that stack is detected. It takes no `stacks:`; the path decides.
- It states its `kind`, usually `expr` or `outcome` (`go` and `command` load too, with the limits of those kinds), and inherits every field it does not set from the capability: title, severity, tiers, scope, requirement, rationale, message, locate, fix. References add up.
- The capability's `when` gates every implementation; an implementation's own `when` is its own condition on top.
- `any.yaml` is the stack-neutral implementation. It checks the detected stacks that have no implementation of their own, and its satisfiers count for every stack's outcome implementation (osv-scanner scans every lockfile, so it satisfies the Go implementation of `deps/vulnerability-scan` too). It also runs where no stack is detected, so every repository is checked by something. Where that means nothing, the `any.yaml` says so with its own `when`: `deps/vulnerability-scan/any` has `when: repo.stacks.size() > 0`, since without a stack there is no dependency manifest.
- Every implementation that runs in a scope must pass: a Go and Node repository needs both linters. A requirement that one stack's tooling meets for the whole repository (one changelog generator, whatever the stack) is not a capability but a plain rule at the root with the union of the satisfiers. One that differs per published artifact is a capability keyed by artifact (below).
- A stack without an implementation is not silently skipped: the capability reports as not applicable with `no implementation for <stack>`.
- `use: lint/configured` selects the capability and all its implementations. An override, an exception or a policy written for the capability reaches every implementation; `lint/configured/go` adjusts one. Through the capability, `when` replaces the gate and leaves each implementation's own condition alone, and `accept:` reaches the outcome implementations.
- A catalog that ships `rules/` can add or replace an implementation without copying the capability: `rules/deps/unused-check/ruby.yaml` in your catalog inherits from the fleetlint capability. It applies where the catalog selects it, with `use: deps/unused-check` (the capability with every implementation, the catalog's own included) or `use: deps/unused-check/ruby`. The stack must be one the catalog version of the run defines.

The [capability matrix](rules/capabilities.md) shows which stack implements what.

## Capabilities keyed by artifact

What a release must do (sign, attest, describe) is per published artifact, not per stack: a Go repository can publish an image and a Homebrew formula, and what counts as signed differs for an npm package (its provenance), a crate (nothing yet) and an image (a signature on the digest). A capability with `by: artifact` has one implementation per artifact kind the catalog defines, and every artifact the release publishes is checked by the implementation for its kind:

```yaml
# rules/release/signing.yaml
id: release/signing
kind: capability
by: artifact
when: release.exists || repo.artifacts.size() > 0
…
```

```yaml
# rules/release/signing/image.yaml
id: release/signing/image
kind: outcome
satisfiers:
  - name: cosign-by-digest
    expr: artifact.workflows.exists(w, steps(w).exists(s, s.run.matches("\\bcosign sign\\b[^\\n]*@sha256:")))
partials:
  - {name: cosign-by-tag, severity: warning, expr: artifact.workflows.exists(w, steps(w).exists(s, s.run.matches("\\bcosign sign\\b"))), message: "the image is signed by tag, not by digest"}
requirement: The workflow that pushes the image signs it by digest.
```

- The last path segment is an artifact id from the catalog's `artifacts/`. The implementation runs once per published artifact of that kind, with `artifact` bound to it: `{kind, name, workflows}`, where the name tells it from the other artifacts of the kind and `workflows` are the CI files that publish it. It is reported as not applicable when none is published.
- Its own `when` is asked per artifact (`release/trusted-publishing/npm` applies to a package published from GitHub, not to the same package published from Gitea). `by` is inherited and cannot be set on an implementation. An implementation written as a Go or command rule cannot read `artifact` and runs once. `repo.artifacts` lists the published kinds, each once.
- Every published artifact must pass: a repository that publishes binaries and an npm package must sign both, and two images are checked one by one. Each finding carries the name of the one that fails in its `artifact` field, which reports show in front of the message (`ghcr.io/x/worker: the image is not signed`); the evidence names the ones that pass (`ghcr.io/x/api: satisfied by cosign-by-digest`). A partial's severity applies only when every failing artifact matched a partial; of several, the highest applies.
- Where the check means nothing for a kind, the implementation says so with `when: "false"` and a requirement that explains it (an SBOM for an npm package, a signature on a crate); the report shows it as not applicable with that text.
- There is no `any.yaml` for such a capability. A published kind without an implementation is reported as a gap (`no implementation for <kind>`); a repository that publishes nothing detectable gets a not-applicable note on the capability (`no published artifact detected`), never a silent pass.

## Artifacts

An artifact kind is data in the catalog: `artifacts/<id>.yaml` says how fleetlint recognises that a release publishes it.

```yaml
id: image
title: Container image
refs: ["https://fleetlint.org/rules/capabilities/#artifacts"]
summary: "docker/build-push-action with push: true, docker push, ko, Jib, crane, or GoReleaser dockers:"
detect: >
  workflows().filter(w, triggers(w).exists(t, t in ["push", "release", "workflow_dispatch", "schedule"]) && steps(w).exists(s,
    (s.uses.startsWith("docker/build-push-action") && "push" in s.with && string(s.with.push) == "true")
    || s.run.matches("\\b(docker|podman|buildah) push\\b")))
instances: >
  steps(item).map(s, findall(s.run, "\\b(?:docker|podman|buildah) push\\s+([^\\s:@]+)")).flatten()
```

- `detect` is a CEL expression that returns the CI files publishing the artifact; an empty list means it is not published. It is evaluated once per repository, at the root, after the other facts, with every CEL function available. A publish step counts in any workflow not run from a pull request, whatever its `if:`, since a step that is there publishes eventually; dry runs and builds without an upload are left out.
- `instances` says what tells one artifact of the kind from another. It is evaluated once per CI file `detect` returned, with `item` bound to that file, and yields names: an image reference without its tag or digest, a chart path, a registry reference. Each name is one published artifact, with every file that names it. A file that yields no name publishes one artifact named after the file; a kind without `instances` is one unnamed artifact.
- Two images pushed from one workflow are two artifacts, each checked by the release implementations. Whether the signing step covers both is not knowable from the workflow, so both pass when the workflow signs.
- `summary` is what the [capability matrix](rules/capabilities.md#artifacts) shows for the kind.

The result is the fact `artifacts`: kind, name and workflows per published artifact; `fleetlint facts` lists them. A repository pins `facts: {artifacts: [image]}` when a publish step hides in a reusable workflow of another repository, names the artifact and its workflows with `{kind: image, name: ghcr.io/x/api, workflows: [.github/workflows/release.yml]}` so the implementations can read them, and writes `artifacts: []` to say nothing is published. A new kind is a change to fleetlint/catalog (or a fork of it): its definition, then implementations of the release capabilities for it.

## Stacks

A stack is data in the catalog: `stacks/<id>.yaml` says how it is detected and what `fleetlint fix` needs to give it an environment.

```yaml
id: kotlin
title: Kotlin / JVM
refs: ["https://fleetlint.org/stacks/#kotlin-jvm--android"]
detect:                                  # any one marker makes the stack present
  - {glob: build.gradle.kts, contains: "kotlin", unless_stack: flutter}
  - {glob: build.gradle, contains: "kotlin", unless_stack: flutter}
devcontainer: {feature: "ghcr.io/devcontainers/features/java:1", options: {installGradle: true}}
run_image: "mcr.microsoft.com/devcontainers/java:21"     # where targets run with container: docker|podman
lockfile_maintenance: true                               # Renovate refreshes the lockfile
```

A marker is a `file` at the directory's root or a `glob` matching a project file at most two directories down (outside examples, fixtures, dependencies and build output). `contains` and `lacks` are regular expressions the file's text must or must not match, `with` lists paths that must exist as well, and `unless_stack` drops the marker when that stack was detected by its own markers. A new stack is a change to fleetlint/catalog (or a fork of it): its definition, then implementations of the capabilities it should meet. Other catalogs use the stacks of the catalog version they build on and cannot add their own. `stacks:` in `.fleetlint.yaml` and on rules must name a defined stack.

## Command rules

For logic an expression cannot express, a rule may run a tracked executable. Only the repository's own `.fleetlint.yaml` and catalog files in the repository may declare one; a catalog fetched over https, git or OCI that does is refused.

```yaml
version: 1
rules:
  - id: repo/fixtures-match-schema
    kind: command
    severity: error
    run: ./scripts/check-fixtures
    message: "fixtures are out of date"
    fix: { human: "Run make fixtures." }
```

- Command rules execute repository code, so they run only with `--deep`, like `quality/check-passes`; without it they report as not applicable (`n/a: needs --deep`).
- Checked before anything runs: `run` is a relative path starting with `./` to a git-tracked, executable, regular file that is not world-writable, with no arguments. Command rules need a git repository whose tracked files can be listed.
- The program receives `{rule, facts, scope, root, params}` as JSON on stdin, runs in the scope directory with an environment without credentials (below), and has 60 seconds. On timeout the whole process group is killed.
- It prints findings as JSON lines `{"message": "...", "path": "...", "line": 1}` on stdout, at most 1 MiB.

| Exit code | Findings printed | Result |
|---|---|---|
| 0 | none | pass |
| 0 or 1 | some | fail, with those findings |
| 1 | none | rule error (most often a crash) |
| any other | | rule error |

The environment of a command rule (and of `make check` under `--deep`) keeps `PATH`, `HOME`, `USER`, `LOGNAME`, `SHELL`, `LANG`, `LC_ALL`, `TMPDIR`, `TERM`, `CI`, `JAVA_HOME`, `VIRTUAL_ENV`, their Windows counterparts, and variables starting with `GO`, `CARGO_`, `RUSTUP_`, `XDG_`, `UV_`, `PYTHON`, `GRADLE_`, `NVM_` or `LC_`. A name containing `TOKEN`, `SECRET`, `PASSWORD`, `PASSWD`, `AUTH`, `CREDENTIAL`, `_KEY` or `PRIVATE` is dropped even under a kept prefix. Command rules add `FLEETLINT=1`; `--deep` adds `CI=true` and `NO_COLOR=1`.

## Go rules

`kind: go` names a rule fleetlint implements in code. The presets have one: `quality/check-passes`, which runs the repository's check and so has to be code. A catalog cannot add one: a `kind: go` rule with an id fleetlint does not implement is a rule error (`no Go implementation registered for <id>`). Everything else is an expression, an outcome rule or a command rule.

## Contributing to fleetlint

Rules for fleetlint/catalog go further than a catalog of your own: every preset rule has `rationale` and `fix.agent`, and each changed rule gets a passing and a failing fixture in fleetlint's `internal/engine/`. Two lists only shrink: the rules without `locate` (`internal/catalog/testdata/rules_without_locate.txt`) and the rules without a typed source. A new `kind: go` rule implements `rules.Checker` in `internal/rules/builtin` and is registered in `builtin.go`; a rule that only needs to read something no function offers gets a new function instead. The steps are in [CONTRIBUTING.md](https://github.com/fleetlint/fleetlint/blob/main/CONTRIBUTING.md).

## Engine level

A catalog states the engine level it was written for:

```yaml
metadata: {name: acme-baseline, version: 1.0.0, engine: 7}
```

The level counts the changes to what rules can rely on (facts, functions, fix actions) that an older catalog or an older fleetlint would not survive. A binary runs a range of levels; fleetlint 0.10 runs 1 to 7. A catalog outside that range is refused when it is loaded, with one message that says whether to upgrade fleetlint or choose another catalog version, instead of its rules failing one by one. A catalog that states no level is loaded as it is. The level is read before the rest of the document, so a catalog that uses a key this fleetlint does not know is refused with that message, not with a parse error.

| Level | fleetlint | Added or changed |
|---|---|---|
| 1 | | the first catalog format |
| 2 | | `use:` entries that select from the library |
| 3 | | capabilities with per-stack implementations, stacks as catalog data, CI functions that read GitLab CI and Forgejo Actions. Catalogs written for an earlier level ship no `stacks/`; fleetlint detects their stacks as it always did. |
| 4 | 0.5.0 | `combine:` on capabilities |
| 5 | 0.6.0 | artifacts as catalog data, capabilities keyed by artifact (`by: artifact`), `repo.artifacts`, `artifact_workflows()` and `metadata.label`. Catalogs written for an earlier level ship no `artifacts/`; their release capabilities stay keyed by stack. |
| 6 | 0.7.0 | `refs` entries as `{url, kind, section}` |
| 7 | 0.8.0 | published artifacts as named instances (`instances:`, `artifact` in implementations, `facts.artifacts` entries with a name, `find` and `findall`) and `locate:` on rules. `combine:` left the format: `combine: any` let one passing implementation carry the others, and a catalog written for an earlier level still runs with it. `artifact_workflows(kind)`, which read every workflow of the kind even inside an implementation meant to check one artifact, is refused in a catalog written for level 7. |

The presets carry no `metadata.version`: they take the version of the catalog release they ship in (its tag, or the commit for an untagged build), so a report names `fleetlint-recommended@v0.8.0`. Every other catalog states its version.
