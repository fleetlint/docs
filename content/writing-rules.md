---
title: "Writing rules"
weight: 90
description: "The rule format: predicates, outcome rules, fix actions, command rules and the engine level."
---

# Writing rules

## Where rules live

- **Presets** ship in the binary and are referenced as `fleetlint:<name>`. Their source is the catalog repository, [fleetlint/catalog](https://github.com/fleetlint/catalog) (`presets/*.yaml`), of which every binary embeds one version (`fleetlint --version` and every report name it); a repository uses another version with `catalog: {version: …}` (see below).
- **Your catalog** is a YAML file with the same format, hosted anywhere over https and referenced with its digest: `https://…/catalog.yaml#sha256-<hex>`. Get the digest with `fleetlint catalog digest catalog.yaml`. Fetches are https only, follow redirects only within the same host, time out after 20 seconds and refuse bodies over 2 MiB; the digest, not the transport, is what makes the content trusted. Every rule and partial must state its `severity`.
- **A catalog in a git repository** is referenced as `git+<url>//<path>@<revision>`, for example `git+https://git.example.com/platform/standards.git//teams/mobile/catalog.yaml@v3.2.0#sha256-<hex>`. The URL is https or ssh and is fetched with the credentials git already has (credential helper, ssh agent), so private repositories work. The revision is a tag or a full commit SHA, never a branch. A commit SHA needs no digest; a tag can be moved, so it must carry `#sha256-<hex>` and a moved tag fails the digest check. Files over 2 MiB are refused and the fetch times out after two minutes. Like https catalogs, git catalogs are untrusted: they cannot declare `command` rules, and may include only presets, https catalogs and other git catalogs.
- **Inline rules** go under `rules:` in `.fleetlint.yaml` with a `kind`.

## Catalog format

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata:
  name: my-standards
  version: 1.2.0
  includes: [fleetlint:recommended]   # optional; loaded first
rules:
  - id: family/name            # namespaced, stable; documentation and overrides key on it
    title: One line
    kind: expr                 # expr | go | command
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

`append` adds a template's text to the end of an existing TOML or YAML file, unless the file already matches the `unless` regular expression; the result must still parse, otherwise nothing is written and the run reports it. This is how `[tool.ruff]` lands in a pyproject.toml or `[lints]` in a Cargo.toml without rewriting what the project wrote. `merge` adds to an existing JSON file the keys of a JSON template it lacks, recursively, keeping every value the file has and its indentation; a file that is not strict JSON (tsconfig.json with comments) is reported, not rewritten. Neither creates the file.

`{taskrunner}` is the runner file for the repository's task runner (`Makefile`, `justfile` or `Taskfile.yml`), written with the container switch when `repo.container` is not `none`. `{stack}/devcontainer.json` is generated for all stacks, and only when `repo.container` is `devcontainer`; `{stack}/check.yml` and the hooks call the repository's runner and follow the container setting. A `{stack}/pre-commit-config.yaml` or `{stack}/check.yml` template is assembled: the shared part (hygiene, secret scan, commit messages, shell, the pre-push check), then the hooks or toolchain of the root stack, of any second stack in the same directory, and of each nested project. Like every template it is only written when the file does not exist; an existing file is never merged into.

Every rule needs `title`, `requirement` and `fix.human`; presets additionally require `rationale` and `fix.agent` (enforced by tests).

## CEL predicates

Variables: `repo` (`name`, `stacks`, `forge`, `visibility`, `public`, `tier`, `layout`, `ci`, `hooks`, `has_git`, `scope`), `release` (`exists`, `mechanisms`, `tag_patterns`, `latest_tag`), `taskrunner` (`kind`, `targets`), `params`.

Accessors:

| Function | Returns |
|---|---|
| `exists(glob)` | any file matches (`**` supported) |
| `file(path)` | exact path exists (`has` is reserved by CEL) |
| `glob(pattern)` | matching paths, sorted |
| `tracked()` | git-tracked paths in the scope |
| `text(path)` / `lines(path)` | contents, `""`/`[]` when absent |
| `yaml(path)` / `toml(path)` / `json(path)` | parsed document, `null` when absent; a parse error is a rule error |
| `makefile(path)` | `{targets: [...], deps: {target: [...]}}` |
| `scan(path, regex)` | 1-based line numbers that match |
| `matchesAny(list, regex)` | any element matches |

Use `has(doc.field)` to test for a key before reading it; reading a missing key is an evaluation error, which the engine reports as a rule error rather than a pass.

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

Accessors that make this practical: `workflows()`, `tagged_workflows()` (release pipelines: workflows triggered by `on.push.tags`), and `steps(path)`, which flattens every job's steps into `{job, name, uses, run, with}` with empty values for absent fields, so expressions never fail on a missing key. The same pattern suits signing, changelog generation and coverage gates: define the outcome, list the known producers, grade by whether the producer sits in the right place.

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

Command rules execute repository code, so they run only with `--deep`, like `quality/check-passes`; without it they report as not applicable with that reason. The other constraints, all enforced before anything runs: only the repository's own config may declare one (remote catalogs are rejected); `run` is a relative path to a git-tracked, executable, regular file that is not world-writable, with no arguments. The program receives `{rule, facts, scope, root, params}` as JSON on stdin, runs with a scrubbed environment (`PATH`, `HOME`, `LANG`, `LC_ALL`, `TMPDIR`, `TERM`, `FLEETLINT=1`) in the scope directory, and has 60 seconds. It prints findings as JSON lines `{"message": "...", "path": "...", "line": 1}` on stdout, at most 1 MiB; exit 0 or 1 means it ran, anything else is a rule error, never a pass.
## Go rules

Rules are data. The one exception in the presets is `quality/check-passes`, which runs the repository's check and so has to be code. A new rule of that kind implements `rules.Checker` in `internal/rules/builtin`, is registered in `builtin.go`, declared in the catalog with `kind: go`, and gets a passing and a failing fixture test. If a rule only needs to read something the accessors do not offer yet, add the accessor instead. Return one `Finding` per concrete problem with `Path` and `Line` where known; set `Outcome.Evidence` to explain a pass.


## Engine level

A catalog states the engine level it was written for:

```yaml
metadata: {name: acme-baseline, version: 1.0.0, engine: 1}
```

The level counts the changes to what rules can rely on (facts, functions, fix actions) that an older catalog or an older fleetlint would not survive. A binary runs a range of levels. A catalog outside that range is refused when it is loaded, with one message that says whether to upgrade fleetlint or choose another catalog version, instead of its rules failing one by one. A catalog that states no level is loaded as it is.
