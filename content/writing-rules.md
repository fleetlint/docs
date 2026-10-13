---
title: "Writing rules"
weight: 90
description: "The rule format: predicates, outcome rules, capabilities and their per-stack implementations, stacks, fix actions, command rules and the engine level."
---

# Writing rules

## Where rules live

- **The library** is the catalog repository's `rules/` directory, [fleetlint/catalog](https://github.com/fleetlint/catalog): one rule per file at `rules/<family>/<name>.yaml`, the path spelling the id (`rules/repo/readme-present.yaml` is `repo/readme-present`). A capability's implementations sit next to it at `rules/<family>/<name>/<stack>.yaml` (`rules/lint/configured/go.yaml` is `lint/configured/go`), see [capabilities](#capabilities-one-requirement-one-implementation-per-stack). The stacks themselves are data in `stacks/<id>.yaml`, see [stacks](#stacks). This is where a rule is read, changed or added; the rule pages on this site are generated from it.
- **Presets** ship in the binary and are referenced as `fleetlint:<name>`. A preset defines no rules: it selects them from the library with `- use: <id>` or `- use: <family>/*` in its `rules:` list (`minimal`, `recommended`, `slop`), or adjusts an included preset with `overrides:` (`strict`, `oss`). Every binary embeds one version of the catalog (`fleetlint version` and every report name it); a repository uses another version with `catalog: {version: …}` (see below).
- **Your catalog** is a YAML file with the same format, hosted anywhere over https and referenced with its digest: `https://…/catalog.yaml#sha256-<hex>`. Get the digest with `fleetlint catalog digest catalog.yaml`. Fetches are https only, follow redirects only within the same host, time out after 20 seconds and refuse bodies over 2 MiB; the digest, not the transport, is what makes the content trusted. Every rule and partial must state its `severity`.
- **A catalog in a git repository** is referenced as `git+<url>//<path>@<revision>`, for example `git+https://git.example.com/platform/standards.git//teams/mobile/catalog.yaml@v3.2.0#sha256-<hex>`. The URL is https or ssh and is fetched with the credentials git already has (credential helper, ssh agent), so private repositories work. The revision is a tag or a full commit SHA, never a branch. A commit SHA needs no digest; a tag can be moved, so it must carry `#sha256-<hex>` and a moved tag fails the digest check. Files over 2 MiB are refused and the fetch times out after two minutes. Like https catalogs, git catalogs are untrusted: they cannot declare `command` rules, and may include only presets, https catalogs and other git catalogs.
- **The repository's own rules** go under `rules:` in `.fleetlint.yaml`, as a list in the same format as a catalog's (`id`, `kind`, `severity`, …, or `- use: <id>` to select a library rule); adjustments to catalog rules go under `overrides:`. See [configuration](configuration.md#rules).

## Catalog format

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata:
  name: my-standards
  version: 1.2.0
  engine: 3                           # the engine level the catalog is written for
  layer: org                          # org or team; where it resolves in a run (omit for a repository's local catalog)
  catalog: { version: v0.2.0 }        # the fleetlint catalog the includes and `use:` selections come from; required for a remote catalog
  includes: [fleetlint:recommended]   # optional; loaded first
rules:
  - id: family/name            # lowercase letters, digits, dashes; stable: documentation and overrides key on it
    title: One line
    kind: expr                 # expr | outcome | capability | go | command
    severity: warning          # error | warning | info
    tiers: [1, 2]              # omit = all
    stacks: [go]               # omit = any
    scope: root                # root | each (default) | members — where in a monorepo it runs
    when: repo.tier <= 2       # applicability; false = not applicable, not a failure
    expr: file("docs/ARCHITECTURE.md")
    message: "architecture doc missing"
    requirement: What must be true, in one or two sentences.
    rationale: Why it matters.
    fix:
      human: What a person does.
      agent: What a coding agent does, precisely, and nothing else.
      actions:                 # optional mechanical steps for `fleetlint fix`
        - template: "{stack}/pre-commit-config.yaml"   # from the catalog's templates; {stack} = detected stack
          to: .pre-commit-config.yaml                   # never overwrites
        - untrack: "*"                                  # git rm --cached the rule's findings
          gitignore: ["*.log"]                          # append missing patterns
        - set: {file: package.json, key: license, value: "{license}"}   # add a value to an existing JSON or TOML file
        - append: {file: pyproject.toml, template: python/ruff.toml, unless: '(?m)^\[tool\.ruff\]'}   # add a block to an existing TOML or YAML file
        - merge: {file: tsconfig.json, template: node/tsconfig-strict.json}   # add the keys an existing JSON file lacks
    params: { key: value }     # available to the expression as params.key
    refs: ["docs/baseline.md#documentation"]
```

`set` adds one string to a file that exists and never changes a key that is already there. JSON takes a top-level key, TOML takes `table.key` in a table written with a `[table]` header. The edit is kept only if the file afterwards parses to exactly the old content plus the key; files it cannot edit that way (JSON with comments, inline tables) are left to a person. `{license}` is the SPDX identifier of the repository's LICENSE file when its text is one recognised license; without it the action does nothing. GNU licenses yield no identifier, because the text does not say whether `-only` or `-or-later` applies.

`append` adds a template's text to the end of an existing TOML or YAML file, unless the file already matches the `unless` regular expression; the result must still parse, otherwise nothing is written and the run reports it. This is how `[tool.ruff]` lands in a pyproject.toml or `[lints]` in a Cargo.toml without rewriting what the project wrote. `merge` adds to an existing JSON file the keys of a JSON template it lacks, recursively, keeping every value the file has, its member order, its number formatting and its indentation; a file that is not strict JSON (tsconfig.json with comments) is reported, not rewritten. Neither creates the file.

`{taskrunner}` is the runner file for the repository's task runner (`Makefile`, `justfile` or `Taskfile.yml`), written with the container switch when `repo.container` is not `none`. `{stack}/devcontainer.json` is generated for all stacks, and only when `repo.container` is `devcontainer`; `{stack}/check.yml` and the hooks call the repository's runner and follow the container setting. A `{stack}/pre-commit-config.yaml` or `{stack}/check.yml` template is assembled: the shared part (hygiene, secret scan, commit messages, shell, the pre-push check), then the hooks or toolchain of the root stack, of any second stack in the same directory, and of each nested project. Like every template it is only written when the file does not exist; an existing file is never merged into.

Every rule needs `title`, `requirement` and `fix.human`; presets additionally require `rationale` and `fix.agent` (enforced by tests). `fleetlint schema catalog` prints the JSON Schema of this format.

## CEL predicates

Variables: `repo` (`name`, `stacks`, `forge`, `visibility`, `public`, `tier`, `layout`, `ci`, `hooks`, `has_git`, `scope`), `release` (`exists`, `mechanisms`, `tag_patterns`, `latest_tag`), `taskrunner` (`kind`, `targets`), `params`.

Accessors:

| Function | Returns |
|---|---|
| `exists(glob)` | any file matches (`**` supported); see below for which files count |
| `file(path)` | exact path exists (`has` is reserved by CEL) |
| `glob(pattern)` | matching paths, sorted |
| `tracked()` | git-tracked paths in the scope |
| `text(path)` / `lines(path)` | contents, `""`/`[]` when absent |
| `yaml(path)` / `toml(path)` / `json(path)` | parsed document, `null` when absent; a parse error is a rule error |
| `makefile(path)` | `{targets: [...], deps: {target: [...]}}` |
| `scan(path, regex)` | 1-based line numbers that match |
| `matchesAny(list, regex)` | any element matches |

Use `has(doc.field)` to test for a key before reading it; reading a missing key is an evaluation error, which the engine reports as a rule error rather than a pass.

A rule that cannot read its input errors, it never passes: `text()`, `lines()`, `scan()` and `yaml()`/`toml()`/`json()` fail for a file that exists but cannot be read (too large, not a regular file, a symlink out of the repository), and `commits()` fails when `git log` does.

`exists()`, `glob()` and stack detection see the tracked files plus the untracked ones git does not ignore, so a gitignored local file cannot make a rule pass on one machine and fail in CI. Vendored and build directories stay out.

Every expression is type-checked when the configuration loads, for every rule, whether it applies to the repository or not: a typo is a configuration error (exit 2) naming the rule and the field (`when`, `expr`, `foreach`, a satisfier or partial). An evaluation stops at a cost limit, so a comprehension over every file cannot run for hours.

Examples:

```yaml
expr: '"check" in makefile("Makefile").targets'
expr: 'yaml(".pre-commit-config.yaml").repos.exists(r, r.repo.contains("gitleaks"))'
expr: '!tracked().exists(f, f.matches("\\.env$"))'
expr: 'glob(".github/workflows/*.yml").all(w, has(yaml(w).permissions))'
```

## Outcome rules: satisfiers without Go

An outcome rule asks whether a result is achieved and lists the ways it can be. Each satisfier is a CEL predicate with a name; the first that holds makes the rule pass and is reported as the evidence (`satisfied by goreleaser`). Catalog authors add satisfiers in YAML; repositories add their own with `accept:` and can never remove the requirement.

```yaml
- id: release/sbom
  kind: outcome
  severity: error
  when: release.exists
  satisfiers:
    - name: goreleaser
      when: file(".goreleaser.yaml")                 # optional guard
      expr: has(yaml(".goreleaser.yaml").sboms)
    - name: workflow-command
      expr: tagged_workflows().exists(w, steps(w).exists(s, s.run.matches("\\bsyft\\b")))
  partials:                                          # graded results when nothing satisfies
    - name: sbom-outside-release
      severity: warning
      expr: workflows().exists(w, steps(w).exists(s, s.run.matches("\\bsyft\\b")))
      message: "an SBOM producer exists but no release workflow invokes it"
  message: "no release step generates an SBOM"
  requirement: …
  fix: { human: …, agent: … }
```

In a repository:

```yaml
rules:
  release/sbom:
    accept:
      - name: own-script
        expr: tagged_workflows().exists(w, steps(w).exists(s, s.run.contains("scripts/sbom.sh")))
```

Accessors that make this practical: `workflows()` (Actions workflows of GitHub, Gitea and Forgejo, and `.gitlab-ci.yml` with the local files it includes), `tagged_workflows()` (release pipelines: started by a tag push, `on.push.tags` or a GitLab rule on `$CI_COMMIT_TAG`), and `steps(path)`, which flattens every job's steps into `{job, name, uses, run, with}` with empty values for absent fields, so expressions never fail on a missing key; a GitLab job is one step whose `run` is its scripts. `ci_kind(path)` tells the systems apart where a concept exists only in one, such as Actions `permissions:`. The same pattern suits signing, changelog generation and coverage gates: define the outcome, list the known producers, grade by whether the producer sits in the right place.

## Capabilities: one requirement, one implementation per stack

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

- An implementation lives at `rules/<family>/<name>/<stack>.yaml`; the last path segment is a stack id from the catalog's `stacks/`, and it runs only where that stack is detected. It states its `kind` (`expr` or `outcome`) and inherits every field it does not set from the capability: title, severity, tiers, scope, requirement, rationale, message, fix. References add up. It takes no `stacks:`, the path decides.
- The capability's `when` gates every implementation; an implementation's own `when` is its own condition on top.
- `any.yaml` is the stack-neutral implementation: it checks the detected stacks that have no implementation of their own, and its satisfiers count for every stack's outcome implementation (osv-scanner scans every lockfile, so it satisfies the Go implementation of `deps/vulnerability-scan` too).
- A stack without an implementation is not silently skipped: the capability reports as not applicable with `no implementation for <stack>`.
- `use: lint/configured` selects the capability and all its implementations. An override, an exception or a policy written for the capability reaches every implementation; `lint/configured/go` adjusts one. Through the capability, `when` replaces the gate and leaves each implementation's own condition alone, and `accept:` reaches the outcome implementations.
- A catalog that ships `rules/` can add or replace an implementation without copying the capability: `rules/deps/unused-check/ruby.yaml` in your catalog inherits from the fleetlint capability. The stack must be one the catalog version of the run defines in `stacks/`; a new stack comes with that catalog (fleetlint/catalog, or a fork pinned with `catalog: {repo: …}`).

The [capability matrix](rules/capabilities.md) shows which stack implements what.

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

A marker is a `file` at the directory's root or a `glob` matching a project file at most two directories down (outside examples, fixtures, dependencies and build output). `contains` and `lacks` are regular expressions the file's text must or must not match, `with` lists paths that must exist as well, and `unless_stack` drops the marker when that stack was detected by its own markers. A new stack is a catalog change: its definition, then implementations of the capabilities it should meet. `stacks:` in `.fleetlint.yaml` and on rules must name a defined stack. Catalogs older than engine level 3 ship no `stacks/`; fleetlint detects their stacks as it always did.

## Command rules

For logic the catalog cannot express, a repository's own `.fleetlint.yaml` may run a tracked executable:

```yaml
rules:
  repo/fixtures-match-schema:
    kind: command
    run: ./scripts/check-fixtures
    message: "fixtures are out of date"
    fix: { human: "make fixtures" }
```

Command rules execute repository code, so they run only with `--deep`, like `quality/check-passes`; without it they report as not applicable with that reason. The other constraints, all enforced before anything runs: only the repository's own config may declare one (remote catalogs are rejected); `run` is a relative path to a git-tracked, executable, regular file that is not world-writable, with no arguments. The program receives `{rule, facts, scope, root, params}` as JSON on stdin, runs in the scope directory with an environment without credentials (below), and has 60 seconds. It prints findings as JSON lines `{"message": "...", "path": "...", "line": 1}` on stdout, at most 1 MiB; exit 0 means it ran, exit 1 means it ran and printed findings; exit 1 without a finding (most often a crash) or any other code is a rule error, never a pass. Command rules need a git repository whose tracked files can be listed.

The environment of a command rule (and of `make check` under `--deep`) keeps `PATH`, `HOME`, `USER`, `LOGNAME`, `SHELL`, `LANG`, `LC_ALL`, `TMPDIR`, `TERM`, `CI`, `JAVA_HOME`, `VIRTUAL_ENV`, their Windows counterparts, and variables starting with `GO`, `CARGO_`, `RUSTUP_`, `XDG_`, `UV_`, `PYTHON`, `GRADLE_`, `NVM_` or `LC_`. A name containing `TOKEN`, `SECRET`, `PASSWORD`, `PASSWD`, `AUTH`, `CREDENTIAL`, `_KEY` or `PRIVATE` is dropped even under a kept prefix. Command rules add `FLEETLINT=1`; `--deep` adds `CI=true` and `NO_COLOR=1`. On timeout the whole process group is killed.
## Go rules

Rules are data. The one exception in the presets is `quality/check-passes`, which runs the repository's check and so has to be code. A new rule of that kind implements `rules.Checker` in `internal/rules/builtin`, is registered in `builtin.go`, declared in the catalog with `kind: go`, and gets a passing and a failing fixture test. If a rule only needs to read something the accessors do not offer yet, add the accessor instead. Return one `Finding` per concrete problem with `Path` and `Line` where known; set `Outcome.Evidence` to explain a pass.


## Engine level

A catalog states the engine level it was written for:

```yaml
metadata: {name: acme-baseline, version: 1.0.0, engine: 3}
```

The level counts the changes to what rules can rely on (facts, functions, fix actions) that an older catalog or an older fleetlint would not survive. A binary runs a range of levels. A catalog outside that range is refused when it is loaded, with one message that says whether to upgrade fleetlint or choose another catalog version, instead of its rules failing one by one. A catalog that states no level is loaded as it is. The level is read before the rest of the document, so a catalog that uses a key this fleetlint does not know (level 2 introduced `use:`) is refused with that message, not with a parse error.

Levels so far: 1, the first catalog format; 2, `use:` entries that select from the library; 3, capabilities with per-stack implementations, stacks as catalog data, and CI accessors that read GitLab CI and Forgejo Actions.

The presets carry no `metadata.version`: they take the version of the catalog release they ship in (its tag, or the commit for an untagged build), so a report names `fleetlint-recommended@v0.1.0`. Every other catalog states its version.
