---
title: "Rule catalog"
weight: 50
description: "Every rule in the presets, by family."
---

# Rule catalog

The practices behind the rules are described in [the baseline](baseline.md) and, per stack, in [the stack profiles](stacks.md). Each rule has a page of its own in the [rule reference](rules/_index.md), generated from the catalog.

The rules the `fleetlint:*` presets ship, grouped by family. The [rule reference](rules/_index.md) has the exact requirement, parameters and fix of each.

**Presets.** `minimal` is the floor for any repository; `recommended` (the default) includes it and selects the families below; `strict` is `recommended` with every severity raised one step and no exceptions on the security rules; `oss` is `recommended` with the `public/*` rules on whatever the detected visibility; `slop` is an add-on with the heuristic `slop/*` rules and the two agent-trace rules for public repositories. The **Preset** column names the smallest preset that selects a rule.

**Capabilities.** A rule marked *capability* states one requirement that each stack meets with its own tools: `lint/configured` is implemented by `lint/configured/go`, `lint/configured/python` and so on, each with its own page. Selecting, overriding or excepting the capability reaches every implementation; the implementation id adjusts one stack. Every implementation that runs must pass. The release capabilities are keyed by published artifact rather than by stack, so each image, package or set of release files is checked on its own; the changelog generator is one rule at the root that any generator satisfies. The [capability matrix](rules/capabilities.md) shows which stack implements which capability, and [writing rules](writing-rules.md#capabilities-one-requirement-one-implementation-per-stack) how they work.

Severity is the default; repositories may raise it freely and lower it with a reason. Tiers: `all`, or the tiers the rule applies to.

## repo: repository hygiene

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `repo/no-tracked-junk` | error | all | minimal | no OS/editor/build junk in the index (`.DS_Store`, `*.log`, `__pycache__`, ...) |
| `repo/no-tracked-env` | error | all | minimal | no `.env*` with values tracked (`.env.example` allowed) |
| `repo/no-large-files` | warning | all | minimal | no tracked file over `params.max_kb` (default 2048) unless under git-lfs |
| `repo/gitignore-present` | warning | all | minimal | `.gitignore` at the root |
| `repo/editorconfig` | warning | all | recommended | `.editorconfig` with `root = true` |
| `repo/gitattributes` | warning | all | recommended | `.gitattributes` with `* text=auto` |
| `repo/readme-present` | warning | all | recommended | README with an install/quickstart section |
| `repo/lockfile-committed` | error | 1, 2 | recommended | *capability*: the lockfile of each stack's dependency manager is tracked |
| `repo/toolchain-pinned` | warning | 1, 2 | recommended | *capability*: each stack pins its compiler or runtime with a version (the stack's version file, or `.tool-versions`/`mise.toml` naming the tool); a JDK pin for Java and Kotlin |
| `repo/dev-environment` | warning | 1, 2 | recommended | the tools are reproducible: in a container mode the container; on the machine a Nix flake or devenv, `mise.toml` / `.tool-versions`, or a `tools` target with pinned versions (outcome rule) |
| `repo/codeowners` | info | 1 | recommended | `CODEOWNERS` in a recognised location |

## taskrunner: the task-runner contract

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `taskrunner/targets` | error | 1, 2 | recommended | `fmt lint test cover audit check check-fast` exist and are not placeholders, in whichever runner is used (Makefile, justfile, Taskfile, package.json scripts; Gradle by convention) |
| `taskrunner/container` | warning | 1, 2 | recommended | when `facts.container` is not `none`: a target called outside the container runs inside it: devcontainer CLI, docker, podman, or an `accept:`ed way (outcome rule) |
| `taskrunner/check-composition` | warning | all | recommended | `check` depends on `lint` and `test` (and `cover`, `audit` at tier 1) |

## format, lint, types: static analysis per stack

The per-stack tools and settings are in [the stack profiles](stacks.md).

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `format/configured` | warning | 1, 2 | recommended | *capability*: a formatter is configured or runs (gofumpt, ruff format, rustfmt, Prettier or Biome, Spotless, `dart format`, `dotnet format`, clang-format, RuboCop, PHP CS Fixer, ...); not applicable to Hugo |
| `lint/configured` | warning | 1, 2 | recommended | *capability*: a linter is configured (golangci-lint v2, ruff, clippy `[lints]`, ESLint/Biome/oxlint, detekt, Checkstyle/Error Prone/SpotBugs/PMD, .NET analyzers, clang-tidy, RuboCop, PHPStan/Psalm, a Dart lint set; for Hugo `hugo --panicOnWarning`) |
| `lint/strict` | warning | 1, 2 | recommended | *capability*: the linter's required checks are on, one finding per missing check (golangci-lint `errcheck govet staticcheck errorlint gosec gocognit funlen`; ruff `E F I B UP SIM BLE S C90 T20`; clippy `unwrap_used expect_used panic todo dbg_macro`; five detekt rules; .NET Nullable, warnings as errors, analysis level; clang-tidy `WarningsAsErrors`; Java analyzers that fail the build; RuboCop `NewCops: enable`) |
| `types/strict` | warning | 1, 2 | recommended | *capability*: the type checker runs in strict mode (tsconfig strict flags; mypy or pyright strict; PHPStan max or Psalm level 1; the Dart analyzer's three strict modes); not applicable where the compiler is the type checker |
| `lint/shell` | info | all | recommended | when shell scripts are tracked, shellcheck runs as a hook, in the task runner or in CI |

## quality: behaviour, not configuration

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `quality/check-passes` | error | 1, 2 | recommended | with `--deep`: the task runner's `check` exits 0 within the budget |
| `quality/policy-enforced` | warning | 1, 2 | recommended | `fleetlint check` runs as a hook, in the task runner or in CI |
| `quality/coverage-threshold` | warning | 1, 2 | recommended | *capability*: tests fail below a coverage floor (the stack's coverage tool with a minimum, diff-cover `--fail-under`, a codecov `target`) |
| `quality/duplication-gate` | info | 1 | recommended | a duplication detector runs: golangci `dupl`, `jscpd`, PMD CPD, pylint `duplicate-code`, Sonar (outcome rule) |
| `quality/mutation-gate` | info | 1 | recommended | a mutation testing tool runs on the core: gremlins, mutmut, cargo-mutants, Stryker, Pitest, mutation_test (outcome rule) |

## docs and changelog: the documents that must exist

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `docs/architecture` | warning | 1 | recommended | `docs/ARCHITECTURE.md` or an Architecture section in the README |
| `docs/adr-directory` | info | 1 | recommended | `docs/adr/` with at least one record |
| `changelog/present` | warning | 1, 2 | recommended | `CHANGELOG.md` with an Unreleased section |
| `changelog/generator-configured` | info | 1 | recommended | `cliff.toml` or release-please/changesets |

## hooks: prek, pre-commit or lefthook

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `hooks/config-present` | error | 1, 2 | minimal | `.pre-commit-config.yaml` or a lefthook configuration |
| `hooks/secret-scan` | error | 1, 2 | minimal | a pre-commit hook runs a secret scanner (gitleaks, trufflehog, ggshield, detect-secrets, secretlint); `detect-private-key` alone is a partial result |
| `hooks/shared-hygiene` | warning | 1, 2 | recommended | the shared hygiene hooks (trailing whitespace, end of file, merge conflicts, large files) |
| `hooks/conventional-commits` | warning | 1, 2 | recommended | a commit-msg hook checks every message |
| `hooks/pre-push-check` | warning | 1, 2 | recommended | a pre-push hook runs the task runner's `check` (`check-fast` does not count) |
| `hooks/revs-pinned` | warning | 1, 2 | recommended | every `rev:` is a version tag or a commit SHA, never a branch |

## deps: dependency hygiene

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `deps/locked-install` | warning | 1, 2 | recommended | *capability*: installs use the lockfile strictly (`npm ci`, `uv sync --locked`, `cargo --locked`, `composer install`, Bundler frozen, ...) and nothing rewrites it outside an update target |
| `deps/vulnerability-scan` | warning | 1, 2 | recommended | *capability*: the task runner or CI runs a vulnerability scanner (the stack's tool, or osv-scanner, trivy, grype and the like for every stack) |
| `deps/license-check` | info | 1 | recommended | *capability*: the task runner or CI checks dependency licenses against an allowlist |
| `deps/unused-check` | info | 1 | recommended | *capability*: unused dependencies are detected (`go mod tidy -diff`, deptry, cargo-machete, knip, composer-unused, dependency_validator, ...) |
| `deps/update-automation` | warning | 1, 2 | recommended | Renovate or Dependabot is configured |
| `deps/update-coverage` | info | 1, 2 | recommended | the update automation covers every detected stack, GitHub Actions and Dockerfiles |
| `deps/update-cooldown` | info | 1, 2 | recommended | updates wait a few days after a release: Renovate `minimumReleaseAge`, Dependabot `cooldown` |
| `deps/install-scripts-disabled` | info | 1, 2 | recommended | Node: install scripts are off or allowlisted (`.npmrc`, `.yarnrc.yml`, pnpm `onlyBuiltDependencies`, bun `trustedDependencies`) |
| `deps/forks-documented` | info | 1, 2 | recommended | when a fork is used: go.mod `replace`, git sources in Cargo.toml, package.json or Python requirements are documented in `FORKS.md`, a Forks section, or an inline comment |

## containers: repositories with a Dockerfile

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `containers/dockerignore` | warning | all | recommended | a `.dockerignore` exists |
| `containers/non-root-user` | warning | all | recommended | every Dockerfile sets a non-root `USER` or builds on a `:nonroot` base; one finding per file |
| `containers/base-image-pinned` | info | 1 | recommended | every `FROM` carries `@sha256:`; `scratch`, build arguments and earlier stages exempt |

## ci: the check workflow and its safety

The CI rules read GitHub, Gitea and Forgejo Actions workflows and `.gitlab-ci.yml` with its local includes. A rule about something only one system has applies to that system only; the rule's page says which.

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `ci/check-workflow` | warning | 1, 2 | recommended | a workflow or pipeline on push or pull/merge request runs the task runner's `check` (`check-fast` does not count) |
| `ci/actions-pinned` | warning | 1 | recommended | every `uses:` is pinned to a commit SHA, `docker://` images by digest; GitLab includes and components to a commit SHA |
| `ci/least-privilege` | warning | 1, 2 | recommended | GitHub and Gitea: top-level or per-job `permissions:` present and not `write-all` |
| `ci/no-script-injection` | warning | 1, 2 | recommended | Actions: no `${{ }}` over outsider-controlled event data inside a `run:` or github-script `script:` |
| `ci/no-pipe-to-shell` | warning | 1, 2 | recommended | no download piped into a shell in CI scripts or Dockerfiles |
| `ci/no-pull-request-target` | error | all | recommended | public repositories: no `pull_request_target` workflow checks out or fetches the PR's code |
| `ci/checkout-no-persist-credentials` | info | 1 | recommended | Actions: every `actions/checkout` sets `persist-credentials: false` |
| `ci/workflow-lint` | info | 1 | recommended | Actions workflows are linted with actionlint or zizmor |
| `ci/sast` | info | 1 | recommended | a SAST tool runs: CodeQL, Semgrep or Opengrep, GitLab SAST, SonarQube |
| `ci/job-timeouts` | info | all | recommended | every job sets a timeout (`timeout-minutes`; GitLab `timeout:`); one finding per job |
| `ci/concurrency-cancel` | info | all | recommended | pull-request pipelines cancel superseded runs (`concurrency` with `cancel-in-progress`; GitLab `interruptible`) |

## release: producing artifacts (tier 1)

Outcome rules: satisfiers list the known producers; a repository adds its own with `accept:`. Most apply when a release mechanism or a tag-triggered pipeline exists.

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `release/tag-triggered` | error | 1 | recommended | releases come from a tag-triggered pipeline (Actions `push: tags:`, GitLab `$CI_COMMIT_TAG`) |
| `release/signing` | error | 1 | recommended | artifacts are signed in the release pipeline (cosign, GoReleaser `signs:`, sigstore-python, npm provenance, gpg) |
| `release/sbom` | warning | 1 | recommended | an SPDX or CycloneDX SBOM is generated in the release pipeline; not checked for registry-only and git-cliff-only releases |
| `release/provenance` | warning | 1 | recommended | build provenance is attested (attest-build-provenance, SLSA generator, `cosign attest`, npm or PyPI trusted publishing, GitLab artifact metadata) |
| `release/checksums` | warning | 1 | recommended | a checksums file is produced (GoReleaser default, `sha256sum`, `shasum -a 256`) |
| `release/trusted-publishing` | warning | 1 | recommended | publishing to npm, PyPI, crates.io or RubyGems uses OIDC trusted publishing, not a registry token from secrets (GitHub and GitLab) |
| `release/semver-tags` | warning | all | recommended | existing tags match `v?MAJOR.MINOR.PATCH[-pre]`; one finding per offending tag |
| `release/signed-tags` | warning | 1 | recommended | the newest `params.recent` (3) version tags carry a PGP, SSH or X.509 signature |
| `release/changelog-in-release` | info | 1 | recommended | release notes come from git-cliff/GoReleaser changelog, not hand-written |
| `release/hosted-builder` | info | 1 | recommended | jobs of a tag-triggered GitHub workflow run on GitHub-hosted runners |
| `release/reproducible-build` | info | 1 | recommended | *capability*: release builds are reproducible (`-trimpath`, `--remap-path-prefix`, `outputTimestamp`, `ContinuousIntegrationBuild`, or `SOURCE_DATE_EPOCH` for any stack) |
| `release/api-compatibility` | info | 1 | recommended | libraries: the stack's API check runs against the previous release: gorelease/apidiff, griffe, cargo semver-checks, api-extractor, binary-compatibility-validator (outcome rule) |

## public: open-source repositories (`when: repo.public`)

| Rule | Severity | Tiers | Preset | Checks |
|---|---|---|---|---|
| `public/license` | error | all | minimal | `LICENSE` with a recognised SPDX license |
| `public/security-policy` | warning | 1 | recommended | `SECURITY.md` |
| `public/contributing` | info | 1 | recommended | `CONTRIBUTING.md` |
| `public/code-of-conduct` | info | 1 | recommended | `CODE_OF_CONDUCT.md` |
| `public/manifest-license` | info | 1 | recommended | a published package's manifest declares the license (package.json, pyproject.toml, Cargo.toml) |
| `public/issue-templates` | info | 1 | recommended | an issue or pull-request template in `.github/` or `.gitea/` |
| `public/no-agent-files` | error | all | slop | no agent instruction files tracked (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.aider*`, `.claude/`, `.cursor/`) |
| `public/no-ai-attribution` | error | all | slop | the last `params.commits` (default 200) commits carry no AI tool's address as author or co-author and no generated-with footer; names are not read |

## slop: traces of careless or generated code

Catalog and rationale: [slop.md](slop.md). `slop/conflict-markers` is in `fleetlint:minimal`, three more are in `fleetlint:recommended`; the others are heuristics in the add-on preset `fleetlint:slop`, all `info` except `slop/insecure-patterns` (warning). All apply at every tier.

| Rule | Severity | Preset | Checks |
|---|---|---|---|
| `slop/conflict-markers` | error | minimal | no merge conflict markers in source |
| `slop/focused-tests` | error | recommended | no `.only`, `fit`, `fdescribe`, `solo: true` |
| `slop/scratch-scripts` | warning | recommended | no `fix_*`, `debug-*`, `tmp_*` scripts at the root |
| `slop/report-documents` | warning | recommended | no `*_SUMMARY.md`, `*REPORT*.md`, `NEXT_STEPS.md` and the like |
| `slop/narration-comments`, `slop/placeholder-comments`, `slop/banner-comments`, `slop/todo-without-issue`, `slop/commented-out-code` | info | slop | comment hygiene |
| `slop/emoji-in-code`, `slop/typographic-chars`, `slop/emoji-headings` | info | slop | no emoji or typographic characters in code and headings |
| `slop/marketing-words` | info | slop | no marketing filler in Markdown documentation |
| `slop/debug-output`, `slop/arbitrary-delays`, `slop/swallowed-errors`, `slop/escape-hatches`, `slop/forced-unwraps`, `slop/vague-errors`, `slop/placeholder-values` | info | slop | code smells outside tests |
| `slop/insecure-patterns` | warning | slop | no disabled TLS verification, `eval(`, `chmod 777`, wildcard CORS |
| `slop/variant-names`, `slop/variant-files`, `slop/dumping-ground-files` | info | slop | no `V2`/`New`/`Old` variants, no `utils` dumping grounds |
| `slop/skipped-tests`, `slop/trivial-asserts` | info | slop | test hygiene |
| `slop/vague-commit-messages`, `slop/non-conventional-commits`, `slop/huge-commits` | info | slop | history of the last `params.commits` commits |

## Totals

| | Count |
|---|---|
| rules | 106 |
| of which capabilities | 12 |
| implementations of the capabilities (per stack and `any`) | 129 |

## Not rules: the templates

Three entries of earlier drafts (`release/template-shape`, `release/gitea-parity`, `ci/same-shape-both-forges`) asserted that a repository's workflows have the shape of fleetlint's templates. They are not rules: the release and CI rules above check outcomes, so a repository with its own pipeline passes, and a shape rule would fail it for being different. What they stood for is checked on fleetlint's side instead: a test (`internal/engine/templates_test.go`) requires that a repository set up from each stack's templates passes the hook, CI and release rules, and the templates still have to run once on a real GitHub runner ([roadmap](https://github.com/fleetlint/fleetlint/blob/main/docs/ROADMAP.md)).

Not rules, but part of 1.0: organization layer (locked rules, severity floors, `--require`, signed git/OCI catalog sources) and team layer (sources file, layered resolution, per-layer attribution). See ROADMAP.
