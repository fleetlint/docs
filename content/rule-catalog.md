---
title: "Rule catalog"
weight: 50
description: "Every rule in the presets, by family."
---

# Rule catalog

The rules the `fleetlint:*` presets ship, grouped by family, with a one-line summary of what each checks. The [rule reference](rules/_index.md) has a page per rule, generated from the catalog, with the exact requirement, parameters and fix. The practices behind the rules are in [the baseline](baseline.md) and, per stack, in [the stack profiles](stacks.md).

## Reading the tables

**Preset** names the smallest preset that selects the rule:

- `minimal`: the floor for any repository. Nothing secret, accidental or oversized is tracked, no conflict markers are committed, a public repository has a license, and hooks exist. The two hook rules apply at tiers 1 and 2, not to experiments.
- `recommended`, the default: `minimal` plus the families below.
- `strict`: `recommended` with every severity raised one step. The security rules take no exceptions and cannot be disabled.
- `oss`: `recommended` with its `public/*` rules run whatever the detected visibility.
- `slop`: an add-on with the heuristic `slop/*` rules and the two agent-trace rules for public repositories.

**Severity** is the default. A repository may raise it freely and lower it with a reason.

**Tiers**: `all`, or the tiers the rule applies to. [What runs at each tier](rules/_index.md#what-runs-at-each-tier) lists them per tier.

**Kind** says how the rule decides:

- `expr`: a CEL predicate. A repository can except a finding, but cannot add ways to pass.
- `outcome`: an outcome rule. It names a result and lists the known ways of reaching it, its *satisfiers*; the first that holds passes the rule and is reported as the evidence. A repository adds its own way with `accept:` ([writing rules](writing-rules.md#outcome-rules-satisfiers-without-go)).
- `capability`: one requirement that each stack meets with its own tools. `lint/configured` is implemented by `lint/configured/go`, `lint/configured/python` and so on, each an `expr` or `outcome` rule with its own page. Every implementation that runs must pass. Selecting, overriding or excepting the capability reaches every implementation, and `accept:` reaches its outcome implementations; an implementation id adjusts one stack. The [capability matrix](rules/capabilities.md) shows which stack implements which ([writing rules](writing-rules.md#capabilities-one-requirement-one-implementation-per-stack)).
- `capability by artifact`: a capability implemented per kind of published artifact instead of per stack. Each image, package or set of release files is checked on its own ([artifacts](rules/capabilities.md#artifacts)).
- `go`: written in Go inside fleetlint. Only `quality/check-passes`, which runs the repository's code.

## repo: repository hygiene

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `repo/no-tracked-junk` | error | all | minimal | expr | no OS, editor or backup files, bytecode or dependency directories tracked (`.DS_Store`, `*.log`, `__pycache__/`, `node_modules/`, ...) |
| `repo/no-tracked-env` | error | all | minimal | expr | no `.env*` with values tracked (`.env.example` allowed) |
| `repo/no-large-files` | warning | all | minimal | expr | no tracked file over `params.max_kb` (default 2048) unless git-lfs takes its pattern |
| `repo/gitignore-present` | warning | all | minimal | expr | a `.gitignore` at the root |
| `repo/editorconfig` | warning | all | recommended | expr | an `.editorconfig` exists |
| `repo/gitattributes` | warning | all | recommended | expr | `.gitattributes` contains `text=auto` |
| `repo/readme-present` | warning | all | recommended | expr | a README of at least 10 lines with a heading on installing, running or using the project |
| `repo/lockfile-committed` | error | 1, 2 | recommended | capability | the lockfile of each stack's dependency manager is tracked |
| `repo/toolchain-pinned` | warning | 1, 2 | recommended | capability | each stack pins its compiler or runtime with a version (the stack's version file, `.tool-versions`/`mise.toml` naming the tool, or `devbox.json` naming its package with a version); a JDK pin for Java and Kotlin |
| `repo/dev-environment` | warning | 1, 2 | recommended | outcome | the tools are reproducible: in a container mode the container; on the machine a Nix flake, devenv or devbox with its lock file (or `shell.nix`), `mise.toml` / `.tool-versions`, or a `tools` target with pinned versions |
| `repo/codeowners` | info | 1 | recommended | expr | a `CODEOWNERS` file at the root or in `.github/`, `docs/` or `.gitea/` |

## taskrunner: the task-runner contract

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `taskrunner/targets` | error | 1, 2 | recommended | expr | `fmt lint test cover audit check check-fast` exist and are not placeholders (Makefile, justfile, Taskfile or package.json scripts; not checked with Gradle, whose `check` is the convention) |
| `taskrunner/container` | warning | 1, 2 | recommended | outcome | when `facts.container` is not `none`: a target called outside the container runs inside it (devcontainer CLI, docker, podman, or an `accept:`ed way); Makefile, justfile, Taskfile |
| `taskrunner/check-composition` | warning | all | recommended | expr | `check` reaches `lint` and `test` (up to three levels deep) and neither `bench` nor `release`; Makefile, justfile, Taskfile |

## format, lint, types: static analysis per stack

The per-stack tools and settings are in [the stack profiles](stacks.md).

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `format/configured` | warning | 1, 2 | recommended | capability | a formatter is configured or runs (gofumpt, ruff format, rustfmt, Prettier or Biome, Spotless, `dart format`, `dotnet format`, clang-format, RuboCop, PHP CS Fixer, ...); not applicable to Hugo |
| `lint/configured` | warning | 1, 2 | recommended | capability | a linter is configured (golangci-lint v2, ruff, clippy `[lints]`, ESLint/Biome/oxlint, detekt 2, Checkstyle/Error Prone/SpotBugs/PMD, .NET analyzers, clang-tidy, RuboCop, PHPStan/Psalm, a Dart lint set; for Hugo `hugo --panicOnWarning`) |
| `lint/strict` | warning | 1, 2 | recommended | capability | the linter's required checks are on, one finding per missing check (golangci-lint `errcheck govet staticcheck errorlint gosec gocognit funlen`; ruff `E F I B UP SIM BLE S C90 T20`; clippy `unwrap_used expect_used panic todo dbg_macro`; five detekt rules; .NET Nullable, warnings as errors, analysis level; clang-tidy `WarningsAsErrors`; Java analyzers that fail the build; RuboCop `NewCops: enable`) |
| `types/strict` | warning | 1, 2 | recommended | capability | the type checker runs in strict mode (tsconfig strict flags; mypy or pyright strict; PHPStan max or Psalm level 1; the Dart analyzer's three strict modes); not applicable where the compiler is the type checker |
| `lint/shell` | info | all | recommended | expr | when shell scripts are tracked, shellcheck runs as a hook, in the task runner or in CI |

## quality: behaviour, not configuration

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `quality/check-passes` | error | 1, 2 | recommended | go | with `--deep`: the task runner's `check` exits 0 within the budget |
| `quality/policy-enforced` | warning | 1, 2 | recommended | expr | `fleetlint check` runs as a hook, in the task runner or in CI |
| `quality/coverage-threshold` | warning | 1, 2 | recommended | capability | tests fail below a coverage floor (the stack's coverage tool with a minimum, diff-cover `--fail-under`, a codecov `target`) |
| `quality/duplication-gate` | info | 1 | recommended | capability | a duplication detector runs: golangci-lint `dupl`, pylint `duplicate-code`, PMD CPD, or for every stack jscpd, Simian, duplo or Sonar |
| `quality/mutation-gate` | info | 1 | recommended | capability | a mutation testing tool runs on the core: gremlins, mutmut, cargo-mutants, StrykerJS, Pitest, mutation_test, Stryker.NET, Mull, mutant, Infection |

## docs and changelog: the documents that must exist

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `docs/architecture` | warning | 1 | recommended | expr | `docs/ARCHITECTURE.md`, `ARCHITECTURE.md` or an Architecture section in the README |
| `docs/adr-directory` | info | 1 | recommended | expr | at least one Markdown record in `docs/adr/` (or `docs/decisions/`, `doc/adr/`, `adr/`, ...) |
| `changelog/present` | warning | 1, 2 | recommended | expr | `CHANGELOG.md` with at least one `## ` section |
| `changelog/generator-configured` | info | 1 | recommended | outcome | a changelog generator is configured: git-cliff, GoReleaser, release-please, cocogitto, semantic-release, commitizen, changesets or towncrier |

## hooks: prek, pre-commit or lefthook

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `hooks/config-present` | error | 1, 2 | minimal | expr | `.pre-commit-config.yaml` or a lefthook configuration |
| `hooks/secret-scan` | error | 1, 2 | minimal | outcome | a pre-commit hook runs a secret scanner (gitleaks, trufflehog, ggshield, detect-secrets, secretlint); `detect-private-key` alone is a partial result |
| `hooks/shared-hygiene` | warning | 1, 2 | recommended | expr | `.pre-commit-config.yaml` runs the shared hygiene hooks (trailing whitespace, end of file, merge conflicts, large files); lefthook is not read |
| `hooks/conventional-commits` | warning | 1, 2 | recommended | outcome | a commit-msg hook checks every message |
| `hooks/pre-push-check` | warning | 1, 2 | recommended | outcome | a pre-push hook runs the task runner's `check` (`check-fast` does not count) |
| `hooks/revs-pinned` | warning | 1, 2 | recommended | expr | every `rev:` in `.pre-commit-config.yaml` is a version tag or a commit SHA, never a branch |

## deps: dependency hygiene

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `deps/locked-install` | warning | 1, 2 | recommended | capability | installs use the lockfile strictly (`npm ci`, `uv sync --locked`, `cargo --locked`, `composer install`, Bundler frozen, ...) and nothing rewrites it outside an update target |
| `deps/vulnerability-scan` | warning | 1, 2 | recommended | capability | the task runner or CI runs a vulnerability scanner (the stack's tool, or osv-scanner, trivy, grype and the like for every stack) |
| `deps/license-check` | info | 1 | recommended | capability | the task runner or CI checks dependency licenses against an allowlist |
| `deps/unused-check` | info | 1 | recommended | capability | unused dependencies are detected (`go mod tidy -diff`, deptry, cargo-machete, knip, composer-unused, dependency_validator, ...) |
| `deps/update-automation` | warning | 1, 2 | recommended | expr | Renovate or Dependabot is configured |
| `deps/update-coverage` | info | 1, 2 | recommended | expr | the update automation covers every detected stack, GitHub Actions and Dockerfiles |
| `deps/update-cooldown` | info | 1, 2 | recommended | expr | updates wait a few days after a release: Renovate `minimumReleaseAge`, Dependabot `cooldown` |
| `deps/install-scripts-disabled` | info | 1, 2 | recommended | expr | Node: install scripts are off or allowlisted (`.npmrc`, `.yarnrc.yml`, pnpm `onlyBuiltDependencies`, bun `trustedDependencies`) |
| `deps/forks-documented` | info | 1, 2 | recommended | capability | a dependency taken from a fork (go.mod `replace`, git sources in Cargo.toml, package.json, Python requirements or the Gemfile, a VCS repository in composer.json) is documented in `FORKS.md`, a Forks section, or a comment on its line |

## containers: repositories with a Dockerfile

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `containers/dockerignore` | warning | all | recommended | expr | a `.dockerignore` exists |
| `containers/non-root-user` | warning | all | recommended | expr | every Dockerfile sets a non-root `USER` or builds on a non-root base (`:nonroot`, Chainguard); one finding per file |
| `containers/base-image-pinned` | info | 1 | recommended | expr | every `FROM` carries `@sha256:`; `scratch`, build arguments and earlier stages exempt |

## ci: the check workflow and its safety

The CI rules read GitHub, Gitea and Forgejo Actions workflows and `.gitlab-ci.yml` with its local includes. A rule about something only one system has applies to that system only; the rule's page says which.

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `ci/check-workflow` | warning | 1, 2 | recommended | outcome | a workflow or pipeline on push or pull/merge request runs the task runner's `check` (`check-fast` does not count) |
| `ci/actions-pinned` | warning | 1 | recommended | expr | every `uses:` is pinned to a commit SHA, `docker://` images by digest; GitLab includes and components to a commit SHA, remote includes by `integrity:` |
| `ci/least-privilege` | warning | 1, 2 | recommended | expr | GitHub Actions only: top-level or per-job `permissions:` present and not `write-all` |
| `ci/no-script-injection` | warning | 1, 2 | recommended | expr | Actions: no `${{ }}` over outsider-controlled event data inside a `run:` or github-script `script:` |
| `ci/no-pipe-to-shell` | warning | 1, 2 | recommended | expr | no download piped into a shell in CI scripts or Dockerfiles |
| `ci/no-pull-request-target` | error | all | recommended | expr | no `pull_request_target` workflow checks out or fetches the PR's code (GitHub, Gitea, Forgejo) |
| `ci/checkout-no-persist-credentials` | info | 1 | recommended | expr | Actions: every `actions/checkout` sets `persist-credentials: false` |
| `ci/workflow-lint` | info | 1 | recommended | outcome | Actions workflows are linted with actionlint or zizmor |
| `ci/sast` | info | 1 | recommended | capability | a SAST tool runs: CodeQL, Semgrep or Opengrep, GitLab SAST, SonarQube; for Ruby also Brakeman, for PHP Psalm's taint analysis |
| `ci/job-timeouts` | info | all | recommended | expr | every job sets a timeout (`timeout-minutes`; GitLab `timeout:`); one finding per job |
| `ci/concurrency-cancel` | info | all | recommended | expr | pull-request pipelines cancel superseded runs (`concurrency` with `cancel-in-progress`; GitLab `interruptible`) |

## release: producing artifacts

The release rules apply once a repository releases: a release mechanism, a tag-triggered pipeline, a published artifact or version tags. Each rule's page says which.

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `release/tag-triggered` | error | 1 | recommended | expr | releases come from a tag-triggered pipeline (Actions `push: tags:`, GitLab `$CI_COMMIT_TAG`) |
| `release/signing` | error | 1 | recommended | capability by artifact | every published artifact is signed: with its ecosystem's signature where there is one (APK signing, PGP for Maven Central, npm provenance, PyPI attestations, NuGet signing), otherwise with cosign or gpg |
| `release/sbom` | warning | 1 | recommended | capability by artifact | an SPDX or CycloneDX SBOM is generated in the release pipeline for each artifact that carries its own dependencies; packages a registry resolves from a manifest (npm, PyPI, crates.io, RubyGems, pub.dev) are not checked |
| `release/provenance` | warning | 1 | recommended | capability by artifact | build provenance is attested: by the registry where it does that (npm, PyPI, RubyGems), otherwise attest-build-provenance, the SLSA generator, `cosign attest`, BuildKit or GitLab artifact metadata |
| `release/checksums` | warning | 1 | recommended | outcome | a checksums file is produced (GoReleaser default, `sha256sum`, `shasum -a 256`); not needed for what a registry addresses by digest |
| `release/trusted-publishing` | warning | 1 | recommended | capability by artifact | publishing to npm, PyPI, crates.io, RubyGems, NuGet or pub.dev uses OIDC trusted publishing, not a registry token from secrets (GitHub and GitLab) |
| `release/semver-tags` | warning | all | recommended | expr | existing tags match `v?MAJOR.MINOR.PATCH[-pre]`; one finding per offending tag |
| `release/signed-tags` | warning | 1 | recommended | expr | the newest `params.recent` (3) version tags carry a PGP, SSH or X.509 signature |
| `release/changelog-in-release` | info | 1 | recommended | outcome | release notes come from git-cliff, GoReleaser, release-please, changesets or the generated CHANGELOG.md, not hand-written |
| `release/hosted-builder` | info | 1 | recommended | expr | jobs of a tag-triggered GitHub workflow run on GitHub-hosted runners |
| `release/reproducible-build` | info | 1 | recommended | capability by artifact | release builds are reproducible: the stack's build settings (`-trimpath`, `--remap-path-prefix`, `outputTimestamp`, `ContinuousIntegrationBuild`) or `SOURCE_DATE_EPOCH` in the release build |
| `release/api-compatibility` | info | 1 | recommended | capability | libraries: the stack's API check runs against the previous release (gorelease or apidiff, griffe, cargo-semver-checks, API Extractor, binary-compatibility-validator, japicmp or revapi, .NET package validation, dart_apitool) |

## public: open-source repositories (`when: repo.public`)

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `public/license` | error | all | minimal | expr | a license file at the root (`LICENSE*`, `LICENCE*`, `COPYING*`, `UNLICENSE`) or a REUSE `LICENSES/` directory |
| `public/security-policy` | warning | 1 | recommended | expr | `SECURITY.md` at the root or in `.github/`, `docs/` or `.gitea/` |
| `public/contributing` | info | 1 | recommended | expr | `CONTRIBUTING.md` at the root or in `.github/`, `docs/` or `.gitea/` |
| `public/code-of-conduct` | info | 1 | recommended | expr | `CODE_OF_CONDUCT.md` at the root or in `.github/`, `docs/` or `.gitea/` |
| `public/manifest-license` | info | 1 | recommended | capability | a published package's manifest declares its license (package.json, pyproject.toml, Cargo.toml, the Maven POM, a gemspec, composer.json, `PackageLicenseExpression`, vcpkg.json, conanfile.py) |
| `public/issue-templates` | info | 1 | recommended | expr | an issue or pull-request template in `.github/` or `.gitea/` |
| `public/no-agent-files` | error | all | slop | expr | no agent instruction files tracked (`CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.aider*`, `.claude/`, `.agent/`, `.cursor/`) |
| `public/no-ai-attribution` | error | all | slop | expr | the last `params.commits` (default 200) commits carry no AI tool's address as author or co-author and no generated-with footer; names are not read |

## slop: traces of careless or generated code

Catalog and rationale: [slop.md](slop.md). `slop/conflict-markers` is in `fleetlint:minimal` and three more are in `fleetlint:recommended`; the others are heuristics in the add-on preset `fleetlint:slop`.

| Rule | Severity | Tiers | Preset | Kind | Checks |
|---|---|---|---|---|---|
| `slop/conflict-markers` | error | all | minimal | expr | no merge conflict markers in source |
| `slop/focused-tests` | error | all | recommended | expr | no `.only`, `fit`, `fdescribe`, `solo: true`, RSpec `focus: true` |
| `slop/scratch-scripts` | warning | all | recommended | expr | no `fix_*`, `debug-*`, `tmp_*` scripts at the root |
| `slop/report-documents` | warning | all | recommended | expr | no `*_SUMMARY.md`, `*REPORT*.md`, `NEXT_STEPS.md` and the like |
| `slop/narration-comments`, `slop/placeholder-comments`, `slop/banner-comments`, `slop/todo-without-issue`, `slop/commented-out-code` | info | all | slop | expr | comment hygiene |
| `slop/emoji-in-code`, `slop/typographic-chars`, `slop/emoji-headings` | info | all | slop | expr | no emoji or typographic characters in code and headings |
| `slop/marketing-words` | info | all | slop | expr | no marketing filler in Markdown documentation |
| `slop/debug-output`, `slop/arbitrary-delays`, `slop/swallowed-errors`, `slop/escape-hatches`, `slop/forced-unwraps`, `slop/vague-errors`, `slop/placeholder-values` | info | all | slop | expr | code smells outside tests |
| `slop/insecure-patterns` | warning | all | slop | expr | no disabled TLS verification, `eval(`, `chmod 777`, wildcard CORS |
| `slop/variant-names`, `slop/variant-files`, `slop/dumping-ground-files` | info | all | slop | expr | no `V2`/`New`/`Old` variants, no `utils` dumping grounds |
| `slop/skipped-tests`, `slop/trivial-asserts` | info | all | slop | expr | test hygiene |
| `slop/vague-commit-messages`, `slop/non-conventional-commits`, `slop/huge-commits` | info | all | slop | expr | history of the last `params.commits` commits |

## Totals

| | Count |
|---|---|
| rules | 106 |
| of which capabilities | 22 |
| of which keyed by artifact | 5 |
| implementations per stack (and `any`) | 170 |
| implementations per artifact kind | 65 |

## Templates are not rules

The rules check outcomes, not the shape of the files `fleetlint fix` writes: a repository with its own hooks, workflows or release pipeline passes when it produces the same results. fleetlint's own tests check the other direction: a repository set up from each stack's templates passes the hook, CI and release rules.
