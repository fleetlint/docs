---
title: "Stack profiles"
weight: 30
description: "The concrete tools and settings for Go, Python, Rust, Node, Kotlin, Flutter, Java, .NET, C/C++, Ruby, PHP and Hugo sites."
---

# Stack profiles

The concrete tools and settings behind [the baseline](baseline.md) for each stack. Settings marked "ratchet" start with a baseline or allowlist for existing code that may only shrink. Tool names and flags reflect the tools as of 2026; verify them against the installed version.

## Go

- **Toolchain:** pin with the `toolchain` directive in `go.mod`. Task runner: Makefile.
- **Format:** `gofumpt` + `goimports` (via golangci-lint formatters).
- **Lint:** `golangci-lint` v2 with `version: "2"` config. Enable at least: `errcheck`, `govet` (all analyzers), `staticcheck`, `errorlint`, `wrapcheck`, `nilerr`, `bodyclose`, `noctx`, `contextcheck`, `gosec`, `revive`, `gocognit` (15), `funlen` (50/80), `forbidigo` (ban `fmt.Print*` and `log.Print*` outside main/output), `depguard` (layer import rules), `exhaustive`, `unparam`, `unused`. Use `new-from-rev` as the ratchet.
- **Errors:** wrap with `fmt.Errorf("op: %w", err)`; inspect with `errors.Is`/`errors.As`; sentinel or typed errors for expected cases. No `panic` in library code. Never `_ =` an error without a comment.
- **Design:** `cmd/<app>` + `internal/`; define small interfaces at the consumer; accept interfaces, return structs. `context.Context` is the first parameter of every IO function; no contexts stored in structs.
- **Tests:** stdlib `testing` + `go-cmp` (testify optional); table-driven tests with `t.Run` and `t.Parallel()`; `httptest` for HTTP; `testcontainers-go` for databases; native fuzzing (`go test -fuzz`) for parsers. Run `go test -race -shuffle=on ./...`.
- **Coverage:** `go test -coverprofile=cover.out -coverpkg=./...`; convert to Cobertura (`gocover-cobertura`) for `diff-cover`.
- **Logging:** `log/slog` with a JSON handler; implement `slog.LogValuer` on secret types to redact them.
- **Audit:** `govulncheck ./...`, `go mod tidy -diff`, `gitleaks`.
- **Licenses:** `go-licenses check ./... --allowed_licenses=<allowlist>`.
- **Slop guards:** `godox` (TODO/FIXME only with an issue reference), `dupl` for duplication, `gremlins` for mutation testing.
- **Benchmarks:** `go test -run=^$ -bench=. -benchmem -count=10` saved to a file; compare with `benchstat` against the stored baseline.
- **API compatibility (libraries):** `gorelease` reports incompatible changes and suggests the next version.

## Python

- **Toolchain:** `uv` for Python version, venv and lockfile (`uv.lock`); `pyproject.toml` only; src layout. Task runner: Makefile (recipes call `uv run ...`).
- **Format + lint:** `ruff format`; `ruff check` with a broad selection: `E,W,F,I,B,UP,SIM,C4,BLE,TRY,EM,S,PL,PT,RET,ARG,PTH,DTZ,T20,ERA,RUF,C90,ANN`. Set `max-complexity = 15` and `PLR0915` (max statements). Ratchet existing violations with `ruff check --add-noqa` run once (it writes targeted `# noqa` codes), then shrink that set phase by phase.
- **Types:** `mypy --strict` or `basedpyright` in strict mode. No `Any` at module boundaries.
- **Errors:** a project exception hierarchy rooted in one base class; `raise ... from err`; no bare `except:` or `except Exception: pass` (BLE/S110 enforce this).
- **Design:** `pydantic` (or `attrs`/dataclasses + explicit validation) at boundaries; `typing.Protocol` for ports; `import-linter` contracts for layers.
- **Tests:** `pytest`, `pytest-randomly`, `pytest-xdist`; `hypothesis` for parsing/logic; `respx` (httpx) or `responses` (requests) for HTTP; `time-machine` for clock; `testcontainers` for DBs. Fixtures in `conftest.py`, builders in `tests/support/`.
- **Coverage:** `pytest --cov --cov-branch --cov-report=xml` + `diff-cover`.
- **Logging:** stdlib `logging` or `structlog`; `pydantic.SecretStr` for secrets.
- **Audit:** `pip-audit` (or `uv` with osv-scanner), `deptry` (unused/missing deps), `gitleaks`.
- **Licenses:** `pip-licenses --allow-only="<allowlist>"`.
- **Slop guards:** ruff `TD` (TODOs need an issue link, TD003), `FIX`, `ERA` (commented-out code) and `T20` (print); `jscpd` for duplication; `mutmut` for mutation testing.
- **Benchmarks:** `pytest-benchmark` with `--benchmark-autosave` and `--benchmark-compare --benchmark-compare-fail=mean:10%`.
- **API compatibility (libraries):** `griffe check <package>` against the last release tag.

## Rust

- **Toolchain:** `rust-toolchain.toml`; MSRV in `Cargo.toml`. Task runner: Makefile wrapping cargo commands.
- **Format:** `rustfmt` with a committed `rustfmt.toml`.
- **Lint:** `cargo clippy --all-targets --all-features -- -D warnings`. Configure in the `[lints]` table of `Cargo.toml`: `unsafe_code = "forbid"` (or `deny` with documented exceptions); clippy groups `all` deny and `pedantic` warn; plus `unwrap_used`, `expect_used`, `panic`, `todo`, `dbg_macro`, `print_stdout`, `print_stderr` set to deny in non-test code. Set `too_many_lines` and `cognitive_complexity` thresholds in `clippy.toml`.
- **Errors:** `thiserror` for library error enums; `anyhow`/`eyre` only in binaries, with `.context(...)`. `unwrap`/`expect` only for proven invariants, with an `// INVARIANT:` comment.
- **Design:** newtypes for IDs/units; enums for state machines; traits as ports; workspace crates to enforce layering (domain crate has no IO deps). Every `unsafe` block has a `// SAFETY:` comment.
- **Tests:** `cargo nextest`; `proptest` for logic/parsers; `insta` for reviewed snapshots; `cargo fuzz` for untrusted input; `mockall` only at adapter boundaries; `miri` for any `unsafe`.
- **Coverage:** `cargo llvm-cov --lcov` + `diff-cover`.
- **Logging:** `tracing` + `tracing-subscriber`; `secrecy::SecretString` for secrets.
- **Audit:** `cargo deny check` (advisories, licenses, bans, duplicates), `cargo machete` (unused deps), `gitleaks`.
- **Licenses:** covered by `cargo deny` (`[licenses]` allowlist in `deny.toml`).
- **Slop guards:** clippy `todo`, `dbg_macro`, `allow_attributes_without_reason` (use `#[expect(lint, reason = "…")]`); `jscpd` for duplication; `cargo-mutants` for mutation testing.
- **Benchmarks:** `criterion` (or `divan`); save with `--save-baseline main`, compare with `--baseline main`.
- **API compatibility (libraries):** `cargo semver-checks`.

## Node.js / TypeScript

- **Toolchain:** pin Node via `.nvmrc`/`.node-version` and the `engines` field; one package manager, pinned with `packageManager` (Corepack); commit the lockfile. TypeScript everywhere, ESM.
- **tsconfig:** `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch`, `verbatimModuleSyntax`. Run `tsc --noEmit` in `lint`.
- **Format + lint:** Prettier + ESLint with `typescript-eslint` `strictTypeChecked` and `stylisticTypeChecked` — or Biome as an all-in-one alternative. Required rules: `no-floating-promises`, `no-misused-promises`, `switch-exhaustiveness-check`, `no-explicit-any`, `no-console`, `max-lines` (400/800), `max-lines-per-function` (50/80), `complexity` (15). Ratchet with ESLint bulk suppressions or a per-file baseline.
- **Errors:** custom `Error` subclasses with `cause`; no `catch {}`; unknown errors narrowed before use; a top-level `unhandledRejection`/`uncaughtException` handler that logs and exits.
- **Design:** `zod` (or valibot) to parse every boundary; branded types for IDs; discriminated unions for state; `dependency-cruiser` (or `eslint-plugin-boundaries`) for layer rules.
- **Tests:** Vitest (or `node:test`); `fast-check` for properties; MSW for HTTP; Testing Library for UI; Playwright for e2e; fake timers for clock.
- **Coverage:** Vitest with `@vitest/coverage-v8` (lcov/cobertura) + `diff-cover`.
- **Logging:** `pino` with `redact` paths for auth headers and tokens.
- **Audit:** `npm audit --omit=dev` (or the pnpm/yarn equivalent) / `osv-scanner`, `knip` (unused files, exports, deps), `gitleaks`.
- **Licenses:** `license-checker-rseidelsohn --production --onlyAllow "<allowlist>"`.
- **Slop guards:** `no-warning-comments` (or `unicorn/expiring-todo-comments`), `@eslint-community/eslint-comments/require-description` for every disable comment, a focused-test ban (Vitest `allowOnly: false`); `jscpd` for duplication; Stryker for mutation testing.
- **Benchmarks and budgets:** `vitest bench`; bundle-size budgets with `size-limit`; Lighthouse CI budgets for web apps.
- **API compatibility (libraries):** `@microsoft/api-extractor` with a committed API report; any diff must be intentional.
- **UI:** `@axe-core/playwright` in e2e tests (no violations allowed); Playwright `toHaveScreenshot` for visual regression; `eslint-plugin-i18next` (or the framework's equivalent) bans hard-coded strings; a script fails on missing or unused translation keys.

## Kotlin (JVM / Android)

- **Toolchain:** Gradle wrapper + version catalog (`libs.versions.toml`); dependency locking; JVM toolchain pinned. Task runner: Gradle tasks (`check` aggregates everything).
- **Format:** `ktlint` (or `ktfmt`) via Spotless.
- **Lint:** `detekt` with `buildUponDefaultConfig` and a baseline file for the ratchet. Enforce: `EmptyCatchBlock`, `SwallowedException`, `TooGenericExceptionCaught`, `LongMethod` (50), `LargeClass`, `CognitiveComplexMethod` (15), `GlobalCoroutineUsage`, `InjectDispatcher`, `ForbiddenMethodCall` (println). Set `allWarningsAsErrors = true`; explicit API mode for libraries. Android: Android Lint with `warningsAsErrors` and a baseline.
- **Errors/coroutines:** sealed result/error hierarchies for expected failures; structured concurrency only (no `GlobalScope`); never swallow `CancellationException` (rethrow it, or use `ensureActive()`); inject dispatchers.
- **Design:** sealed classes for state; value classes for IDs; constructor injection (Hilt/Koin/manual) wired in one place; module boundaries per layer, with `Konsist` architecture tests.
- **Tests:** JUnit 5 (or Kotest); `kotlinx-coroutines-test` (`runTest`, test dispatchers); Turbine for Flows; MockK only at adapter boundaries; Robolectric / Compose UI tests on Android; Testcontainers on JVM.
- **Coverage:** Kover (XML report) + `diff-cover`.
- **Logging:** SLF4J + Logback (JVM) or Timber (Android, debug tree only in debug builds).
- **Secrets (Android):** Android Keystore-backed encryption (e.g. via Tink) with DataStore; never plain SharedPreferences.
- **Audit:** `osv-scanner` against the Gradle lockfiles, Gradle dependency analysis plugin (unused deps), `gitleaks`.
- **Licenses:** `app.cash.licensee` Gradle plugin with an allowlist.
- **Slop guards:** detekt `ForbiddenComment` (TODO/FIXME without an issue reference), `UnusedPrivateMember`, `UnusedParameter`; PMD CPD or `jscpd` for duplication; Pitest (gradle-pitest-plugin) for mutation testing.
- **Benchmarks:** `kotlinx-benchmark` (JMH) on JVM; Jetpack Macrobenchmark for startup and scrolling on Android, plus Baseline Profiles.
- **API compatibility (libraries):** binary-compatibility-validator (`apiDump` / `apiCheck`) with the API file committed.
- **UI (Android):** Compose UI tests with accessibility checks enabled; Roborazzi or Paparazzi screenshot tests; Android Lint `HardcodedText` and missing-translation checks as errors.

## Flutter / Dart

- **Toolchain:** pin the Flutter version (FVM or `.tool-versions`); commit `pubspec.lock`.
- **Format:** `dart format --set-exit-if-changed .`
- **Lint:** `very_good_analysis`; `analyzer.language`: `strict-casts`, `strict-inference` and `strict-raw-types` set to true. Make sure `use_build_context_synchronously`, `unawaited_futures`, `discarded_futures`, `avoid_print`, `cancel_subscriptions` and `close_sinks` are on. Run `flutter analyze --fatal-infos`. Ratchet with per-file `ignore_for_file` lists tracked in the repository.
- **Errors:** sealed failure classes or a Result type; `FlutterError.onError` + `PlatformDispatcher.instance.onError` as the top-level handlers.
- **Design:** one state approach (Riverpod or Bloc); `freezed` + `json_serializable` for models (no unchecked `as` casts on JSON); repositories behind interfaces; no `part`-file mixins sharing state.
- **Tests:** `flutter_test`, `mocktail` (prefer fakes), `fake_async`, `bloc_test` / Riverpod `ProviderContainer`, golden tests for key screens, `integration_test` for e2e.
- **Coverage:** `flutter test --coverage` (lcov) + `diff-cover`.
- **Logging:** the `logging` package with a redacting handler; debug output disabled in release.
- **Secrets:** `flutter_secure_storage`. Self-signed servers get a host-scoped `SecurityContext`, never a global `badCertificateCallback`.
- **Audit:** `osv-scanner` on `pubspec.lock`, `dart pub outdated`, `gitleaks`.
- **Licenses:** `osv-scanner` license scanning on `pubspec.lock` with the allowlist; otherwise a script over `dart pub deps --json`.
- **Slop guards:** `flutter_style_todos`, `avoid_print`, `require_trailing_commas` via very_good_analysis; every `// ignore:` needs a reason on the line above; `jscpd` for duplication; the `mutation_test` package for mutation testing.
- **Benchmarks:** `benchmark_harness` for pure Dart logic; `integration_test` with `traceAction` for frame timings of key screens; app-size budget from `flutter build --analyze-size`.
- **UI:** widget tests with `meetsGuideline(textContrastGuideline)`, `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `iOSTapTargetGuideline`; golden tests in light/dark and large text; `flutter gen-l10n` with `untranslated-messages-file` set, and `check` fails if that file is not empty.

## Java

Detected by `pom.xml`. Gradle builds, Kotlin or Java, are the [Kotlin](#kotlin-jvm--android) profile.

- **Toolchain:** `.java-version` or `.sdkmanrc` (Temurin), the Maven wrapper (`./mvnw`) committed; `maven-enforcer-plugin` pins the Maven version.
- **Format:** Spotless with google-java-format or Palantir; `spotless:check` in the hooks.
- **Lint:** Checkstyle with a committed `config/checkstyle/checkstyle.xml` and `failOnViolation`; Error Prone as a compiler plugin; SpotBugs for bug patterns. Checked by `lint/java-config`; `fleetlint fix --apply` writes the Checkstyle configuration.
- **Errors:** no `catch (Exception e)` without rethrow (Checkstyle `IllegalCatch`, `EmptyCatchBlock`); checked exceptions translated at module boundaries.
- **Tests:** JUnit 5, AssertJ, Testcontainers for integration; Mockito only at boundaries. `surefire` for unit tests, `failsafe` for integration.
- **Coverage:** JaCoCo with `<rule>` minimums in `jacoco-maven-plugin` (`check` goal) plus `diff-cover` on the XML report.
- **Audit:** OWASP `dependency-check-maven` or `osv-scanner` on the dependency tree; `gitleaks`.
- **Licenses:** `license-maven-plugin` (`third-party-report` with an allowlist) or `osv-scanner` license scanning.
- **Slop guards:** Checkstyle `TodoComment` requiring an issue reference, `SuppressWarnings` forbidden without a reason filter; PMD CPD for duplication; Pitest for mutation testing.
- **API compatibility (libraries):** `japicmp-maven-plugin` or Revapi against the previous release.

## .NET

Detected by `global.json`, `Directory.Build.props`, a `.sln`/`.slnx` or a `.csproj`/`.fsproj`.

- **Toolchain:** `global.json` pins the SDK (`rollForward: latestPatch`); `Directory.Packages.props` for central package versions; `dotnet restore --locked-mode` with `packages.lock.json` committed.
- **Format:** `dotnet format --verify-no-changes` in the hooks; style rules in `.editorconfig`.
- **Lint:** `Directory.Build.props` at the root with `<Nullable>enable`, `<TreatWarningsAsErrors>true`, `<AnalysisLevel>latest-all` (or `latest-recommended`) and `<EnforceCodeStyleInBuild>true`, so every project compiles under the same analyzers. Checked by `lint/dotnet-config`; `fleetlint fix --apply` writes the file.
- **Errors:** no `catch (Exception)` without rethrow (CA1031); `Result`-style types or exceptions, not both; `ConfigureAwait` policy decided once.
- **Tests:** xUnit, FluentAssertions or Shouldly, Testcontainers; `dotnet test --collect:"XPlat Code Coverage"`.
- **Coverage:** coverlet with `/p:Threshold` or `diff-cover` on the Cobertura report.
- **Audit:** `dotnet list package --vulnerable --include-transitive` failing on findings; `gitleaks`.
- **Licenses:** `dotnet-project-licenses` or `nuget-license` with an allowlist.
- **Slop guards:** analyzers IDE0005 (unused usings), CA1848/CA2254 (logging), a `TODO` check via `.editorconfig` `dotnet_diagnostic.S1135`; `jscpd` for duplication; Stryker.NET for mutation testing.
- **API compatibility (libraries):** `Microsoft.DotNet.ApiCompat` (`EnablePackageValidation` with a baseline version).

## C/C++

Detected by `CMakeLists.txt`, `meson.build`, a Conan file or `vcpkg.json`.

- **Toolchain:** the compiler and standard pinned in presets (`CMakePresets.json`), dependencies through Conan or vcpkg with a lockfile (`conan.lock`, `vcpkg.json` builtin-baseline).
- **Format:** `clang-format` with a committed `.clang-format`; the hook formats staged files.
- **Lint:** `clang-tidy` with a committed `.clang-tidy` (`WarningsAsErrors: '*'`) over `compile_commands.json`; `-Wall -Wextra -Werror` (`CMAKE_COMPILE_WARNING_AS_ERROR`). Checked by `lint/cpp-config`; `fleetlint fix --apply` writes both files.
- **Errors:** no swallowed exceptions (`bugprone-empty-catch`), `std::expected`/error codes at boundaries, RAII everywhere (`cppcoreguidelines-owning-memory`).
- **Tests:** Catch2 or GoogleTest through CTest; sanitizers (ASan, UBSan) in a dedicated preset run by `check`.
- **Coverage:** `gcovr` or `llvm-cov` with `--fail-under-line`.
- **Audit:** `osv-scanner` on the lockfile; `cppcheck` as a second analyzer; `gitleaks`.
- **Licenses:** Conan's `conan graph info --format=json` or vcpkg's license fields against an allowlist.
- **Slop guards:** `readability-function-cognitive-complexity`, `readability-function-size`; `jscpd` or PMD CPD for duplication; Mull for mutation testing.
- **API compatibility (libraries):** `abi-compliance-checker` or `abidiff` against the previous release.

## Ruby

Detected by `Gemfile` or a `.gemspec`.

- **Toolchain:** `.ruby-version`; Bundler with `Gemfile.lock` committed; `bundle config set frozen true` in CI.
- **Format and lint:** RuboCop with a committed `.rubocop.yml` (`NewCops: enable`, rubocop-performance, rubocop-rspec), or Standard; `.rubocop_todo.yml` as the ratchet. Checked by `lint/ruby-config`; `fleetlint fix --apply` writes `.rubocop.yml`.
- **Errors:** `Lint/SuppressedException` on, `Style/RescueStandardError: explicit`; no `rescue Exception`.
- **Tests:** RSpec or Minitest; `webmock`/`vcr` for HTTP; `simplecov` with `minimum_coverage`.
- **Coverage:** SimpleCov `minimum_coverage` and `diff-cover` on the Cobertura formatter output.
- **Audit:** `bundler-audit check --update`; `brakeman` for Rails; `gitleaks`.
- **Licenses:** `license_finder` with an allowlist.
- **Slop guards:** `Style/CommentAnnotation` with a required colon and an issue reference convention; `flay` or `jscpd` for duplication; `mutant` for mutation testing.
- **API compatibility (libraries):** none standard; semantic versioning enforced by review and a changelog entry per public change.

## PHP

Detected by `composer.json`.

- **Toolchain:** `.php-version` or `composer.json` `config.platform.php`; `composer.lock` committed; `composer install --prefer-dist` in CI.
- **Format:** PHP CS Fixer (`.php-cs-fixer.dist.php`, `@PER-CS`, `declare_strict_types`) or Pint; the hook runs `--dry-run`.
- **Lint:** PHPStan at `level: max` with `phpstan-strict-rules` (`phpstan.neon.dist`) or Psalm; a generated baseline is the ratchet. Checked by `lint/php-config`; `fleetlint fix --apply` writes both configurations.
- **Errors:** `declare(strict_types=1)` everywhere; exceptions typed per module; no empty `catch`.
- **Tests:** PHPUnit or Pest; `--fail-on-warning`, `--fail-on-risky`.
- **Coverage:** PHPUnit coverage (pcov) with `diff-cover` on the Clover/Cobertura report.
- **Audit:** `composer audit` failing on advisories; `gitleaks`.
- **Licenses:** `composer licenses --format=json` against an allowlist.
- **Slop guards:** PHPStan's `disallowedCalls` for `var_dump`/`dd`, `ergebnis/phpstan-rules` for TODO hygiene; `jscpd` or `phpcpd` for duplication; Infection for mutation testing.
- **API compatibility (libraries):** `roave/backward-compatibility-check` against the previous tag.

## Hugo / static sites

A documentation or marketing site is a repository like any other: it has a build that can break, links that can rot and a deployment that should be reproducible. fleetlint recognises a site by `hugo.toml`/`hugo.yaml`/`hugo.json` (also under `config/_default/`), or a legacy `config.toml` naming the `baseURL` next to a `content/` directory.

- **Toolchain:** pin Hugo (`mise.toml`, `.tool-versions`, or the version in the check workflow); the extended build when the site uses SCSS. The dev container uses the `hugo` feature; the `docker`/`podman` modes use `ghcr.io/gohugoio/hugo`.
- **Build (`lint`):** `hugo --quiet --panicOnWarning --destination <tmp>`: a missing layout, a broken `ref`/`relref` or a deprecated setting fails the build instead of printing a warning. Checked by `lint/hugo-strict-build`.
- **Tests:** a link and anchor check over the built site (every `href` resolves, every `#fragment` exists); `markdownlint` on the content. Hugo already fails on a link to a Markdown file that does not exist when `refLinksErrorLevel = "ERROR"`.
- **Hooks:** the build check scoped to content, layouts, assets, static and configuration; `markdownlint --fix`.
- **CI:** `peaceiris/actions-hugo` with a pinned `HUGO_VERSION` (Renovate bumps it), then the task runner's `check`.
- **Release:** none; a site ships by deployment. The release rules stay not-applicable while no tag-triggered workflow exists.
- **Slop guards:** `markdownlint` for structure, the link check for dead references; no generated `public/` or `resources/_gen` tracked (`.gitignore`).

## Shared tools (all stacks)

| Purpose | Tool |
|---|---|
| Git hooks | `prek` (single binary, pre-commit compatible) |
| Shell scripts | `shellcheck` + `shfmt` |
| Editor/line-ending consistency | `.editorconfig` + `.gitattributes` |
| Changed-line coverage gate | `diff-cover` (reads lcov / Cobertura / JaCoCo) |
| Code metrics | `scc` or `tokei` |
| Secret scan | `gitleaks` (working tree + history) |
| Vulnerability scan | `osv-scanner` (any lockfile), plus the ecosystem tool above |
| Task runner | GNU Make (`make check`); Gradle or `npm run` where that's the stack convention |
| Changelog from conventional commits | `git-cliff` |
| Signed tags | `git tag -s` (GPG or SSH signing key) |
