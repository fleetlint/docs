---
title: "Integrations"
weight: 110
description: "Git hooks, CI, pull-request comments, coding agents and editors."
---

# Integrations

## prek / pre-commit

```yaml
repos:
  - repo: https://github.com/fleetlint/fleetlint
    rev: v0.10.2
    hooks:
      - id: fleetlint
```

The hook builds fleetlint at `rev` with the Go toolchain prek manages, runs `fleetlint check --fail-on error` on every commit (well under a second on a typical repository), and blocks commits with error-severity findings. Warnings are reported in CI instead, where they don't interrupt work. `prek autoupdate` (or `pre-commit autoupdate`) moves `rev` to the latest release; a `rev` older than the fleetlint that wrote your `.fleetlint.yaml` may not read it.

The hook that `fleetlint fix` writes runs the installed binary instead, with no Go build:

```yaml
repos:
  - repo: local
    hooks:
      - id: fleetlint
        name: fleetlint (repository setup)
        entry: fleetlint check --fail-on error --color=false
        language: system
        pass_filenames: false
        always_run: true
```

Either hook fetches remote catalogs like any run, and fails with exit 2 when one cannot be fetched; see [troubleshooting](troubleshooting.md#a-catalog-cannot-be-fetched).

## GitHub Actions and Gitea Actions

```yaml
- uses: fleetlint/action@v0.1.0   # or its commit SHA
  with:
    version: v0.10.2              # the fleetlint release to run
    fail-on: warning
    sarif-file: fleetlint.sarif
- uses: github/codeql-action/upload-sarif@v4   # GitHub only; shows findings in the Security tab
  if: always()
  with:
    sarif_file: fleetlint.sarif
```

[fleetlint/action](https://github.com/fleetlint/action) installs the release binary (checked against `checksums.txt`, and against its cosign signature when `cosign` is on PATH), annotates every finding on its file and line, writes the report into the job summary and fails the step at `fail-on`. No Go toolchain needed. Without `version` it installs the fleetlint release the action version was cut with: v0.1.0 installs fleetlint v0.9.0, whose onboarding pull request lists the stacks as a comment instead of under `scopes:`. Set `version` to the release you run locally (see [Versions](#versions)).

Gitea and Forgejo run it by its full URL, `uses: https://github.com/fleetlint/action@v0.1.0` (Forgejo resolves a short `uses:` against its own actions instance), on a runner with `bash`, `curl` and `tar`. The report goes into the job summary, which Forgejo shows from v17 with runner v13.2; annotations are off by default there (`annotations: auto`), since neither forge shows them, and there is no code scanning to upload SARIF to. Tested on Forgejo 17 with runner 13.2; Gitea runs the same steps but is not tested.

Every run checks. With `pr: true`, a run of the default branch also proposes changes on the repository it runs in, with the run's token:

- without a `.fleetlint.yaml`, the onboarding pull request (`fleetlint init --pr`); that run is not gated, since nothing is adopted yet;
- else the fixes pull request (`fleetlint fix --apply --pr`), updated on every run; the run is gated as usual.

Pull request runs and other branches only check, so one workflow serves both. The job needs `contents: write` and `pull-requests: write`, and on GitHub the setting *Allow GitHub Actions to create and approve pull requests*. A pull request opened with `GITHUB_TOKEN` starts no workflows; a GitHub App token (`actions/create-github-app-token`) or a fine-grained token passed as `token:` does. Gitea and Forgejo run the same step, with the instance and its API taken from the job; the commit is the instance's Actions user's (`forgejo-actions`, `gitea-actions`), and on Forgejo the job's own token can push and open the pull request.

### Action inputs

| Input | Default | Meaning |
|---|---|---|
| `version` | the release the action version was cut with (v0.1.0: `v0.9.0`) | the fleetlint release to install, such as `v0.10.2`, or `latest`; `pr` needs v0.9.0 or newer |
| `fail-on` | `error` | the lowest severity that fails the step: `error`, `warning`, `info` or `never` |
| `path` | `.` | the repository root to check, relative to the workspace |
| `annotations` | `auto` | annotate every finding on the run and, on pull requests, on the changed files: `true`, `false`, or `auto` (on GitHub only) |
| `summary` | `true` | write the report into the job summary |
| `sarif-file` | none | also write SARIF to this path, for `github/codeql-action/upload-sarif` |
| `verify` | `auto` | how the download is verified: `auto` (the cosign signature when `cosign` is on PATH, else the checksum), `cosign` or `checksum` |
| `pr` | `false` | on runs of the default branch, also open or update the onboarding or fixes pull request |
| `token` | the run's `github.token` | the token for `pr` |

The output `version` is the fleetlint version that ran.

## GitLab CI

The [fleetlint component](https://github.com/fleetlint/gitlab-components) for the GitLab CI/CD catalog:

```yaml
include:
  - component: gitlab.com/fleetlint/components/fleetlint@0.1.0
    inputs:
      version: v0.10.2
      fail-on: warning
      pr: true
```

- Without `version`, a component version installs the fleetlint release it was cut with (0.1.0: fleetlint v0.9.0), with that release's install script, and requires the cosign signature of its checksums.
- Every run reports the findings in the merge request's Code Quality widget, keeps `fleetlint.json` as an artifact and fails at `fail-on`.
- With `pr: true`, a pipeline of the default branch also opens or updates a merge request, as the action does: the onboarding configuration when the project has none (not gated), else the mechanical fixes. Other branches and merge request pipelines only check; a pipeline schedule keeps the fixes current between pushes.
- The job token cannot push or open merge requests, so `pr: true` needs `FLEETLINT_TOKEN`: a project access token with the `api` and `write_repository` scopes and the Developer role, as a masked CI/CD variable.

### Component inputs

| Input | Default | Meaning |
|---|---|---|
| `version` | the release the component version was cut with (0.1.0: `v0.9.0`) | the fleetlint release to install, as `vX.Y.Z`; `pr` needs v0.9.0 or newer |
| `fail-on` | `error` | the lowest severity that fails the job: `error`, `warning`, `info` or `never`; a project being onboarded is not gated |
| `pr` | `false` | on pipelines of the default branch, open or update the onboarding or fixes merge request |
| `path` | `.` | the directory to check, relative to the project |
| `verify` | `cosign` | `cosign` requires the signature of the release's checksums; `checksum` checks the checksum only |
| `stage` | `test` | the stage the job runs in |
| `job-name` | `fleetlint` | the name of the job |
| `image` | `alpine:3.22` | the Alpine image the job runs in, such as one from the dependency proxy |

A component can only be included from the instance it is published on. On a self-managed instance include the template by URL, which takes the same inputs:

```yaml
include:
  - remote: https://raw.githubusercontent.com/fleetlint/gitlab-components/0.1.0/templates/fleetlint.yml
    inputs:
      version: v0.10.2
```

The older job, `include: remote: https://raw.githubusercontent.com/fleetlint/fleetlint/<tag>/ci/gitlab/fleetlint.yml`, is the component without inputs and without `pr` (variables `FLEETLINT_FAIL_ON`, `FLEETLINT_VERIFY`); up to 0.8.1 it fails on every run (the Code Quality step). Use the component.

## Versions

The packages (Homebrew, Scoop, Nix, the Linux packages, the image, `install.sh`) have fleetlint's version: they ship the binary of that release. The action and the GitLab component have their own versions, independent of fleetlint's: each version pins one fleetlint release as its `version` default, Renovate bumps the default, and a release of the integration follows. Pin the integration, and set `version` to run another fleetlint release.

| Integration | Installs by default | `pr` needs |
|---|---|---|
| action v0.1.0 | fleetlint v0.9.0 | fleetlint 0.9.0 |
| GitLab component 0.1.0 | fleetlint v0.9.0 | fleetlint 0.9.0 |

## What the CI rules read

The `ci/*` and `release/*` rules read the CI configuration of every system fleetlint knows: GitHub, Gitea and Forgejo Actions workflows (`.github/workflows`, `.gitea/workflows`, `.forgejo/workflows`) and `.gitlab-ci.yml` with the local files it includes. A rule about something only one system has applies to that system only, for example `permissions:` (GitHub and Gitea) or `persist-credentials` on `actions/checkout` (Actions); each rule's page in the [rule reference](rules/_index.md) says which it reads. `fleetlint fix` writes a GitHub Actions check workflow; on GitLab, add a job that runs the task runner's `check`.

## Make

```make
check: lint test cover audit build
	fleetlint check --fail-on error
```

The templates `fleetlint fix` writes run fleetlint in three places: a local hook, the task runner's `check` target (this line in a Makefile, the same in a justfile or Taskfile) and an install step in the check workflow. `quality/policy-enforced` reports a repository where nothing runs fleetlint.

## Machine-readable output

`fleetlint check --format json` writes the whole run. Field names are snake_case.

| Key | Contents |
|---|---|
| `version` | the shape of the document, `5`; a change of shape gets a new number |
| `tool` | fleetlint's name and version, and the catalog version |
| `repo` | the repository's name |
| `facts` | the repository's facts with where each came from (`sources`); a published artifact in `artifacts` has a `kind`, a `name` where the catalog names instances, and its `workflows` |
| `scopes` | each scope's path and facts |
| `summary` | counts per status; `errors` counts error-severity failures, `rule_errors` the rules that could not run |
| `results` | each rule with its `status`, `severity`, findings and evidence. The rule carries `label`, `source` and `selected_by`, its satisfiers from `accept:` under `rule.accept`, and `refs` as objects with `url`, `kind` and `section` |
| `disabled`, `weakened` | the disabled rules and lowered severities, each with its reason, the file and the label of the catalog that did it |
| `catalogs` | the catalogs in the order they applied: reference, label, name, version, digest or artifact, what each builds on and contributed |

`fleetlint hierarchy --format json` writes the `catalogs` list on its own.

### SARIF

`fleetlint check --format sarif` writes SARIF 2.1.0 the way GitHub code scanning and the common viewers read it:

- Every result has a location. A finding about a file names the file and line; a finding about a missing file points at where the rule expects it (the rule's `locate`); a finding about nothing in particular is anchored to the scope's `.fleetlint.yaml`, else its `README.md`, so code scanning does not drop it.
- Each rule carries `helpUri` to its page on this site, its family as a tag, and the rule's sources under `refs`.
- Rules of the `release`, `ci`, `deps`, `containers`, `hooks` and `repo` families carry the `security` tag and a `security-severity`: 8.0 for an error, 5.0 for a warning, 2.0 for a note.
- Results have a stable `partialFingerprints` entry (`fleetlint/v1`), so alerts keep their identity across runs.
- Excepted and baselined findings are results with a `suppressions` entry that carries the reason, and for an exception its expiry (`properties.until`).
- A rule that could not run is a `toolExecutionNotifications` entry under `invocations`, with `executionSuccessful: false`.
- The log holds one run per scope: `automationDetails.id` is `fleetlint/<repository>/` for the root and `fleetlint/<repository>/<scope>/` for each scope. Code scanning takes an id up to its last `/` as the category, so every scope gets its own alert set. After upgrading from 0.7, the first upload moves a repository's alerts to these categories once.
- A finding about a named artifact shows the name in front of the message and is its own alert.
- A failing rule that `fleetlint fix --apply` can repair carries the change as `fixes` on its first result: one replacement per file it creates, appends to or edits, with offsets in UTF-16 code units (`columnKind`). A fix that untracks a file is not a text edit and is left out.
- The output validates against the OASIS schema in fleetlint's tests.

## Pull-request comments

`fleetlint check --format markdown` renders a comment-ready table with a collapsed block of agent instructions. After the action has installed fleetlint, a step posts it on the pull request (the job needs `pull-requests: write`):

```yaml
- if: always() && github.event_name == 'pull_request'
  run: |
    fleetlint check --format markdown --fail-on never > fleetlint.md
    gh pr comment "$PR" --body-file fleetlint.md
  env:
    GH_TOKEN: ${{ github.token }}
    PR: ${{ github.event.pull_request.number }}
```

On Gitea and Forgejo, post the same file through the API's issue comments endpoint.

## Coding agents

`fleetlint check --format agent` emits an ordered task list, one rule per section, each with the requirement, the findings and a precise instruction. Hand it to the agent as the task. `fleetlint explain <rule>` gives the agent the full context for one rule when it asks.

## Editors

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/fleetlint/fleetlint/v0.10.2/internal/config/schema.json
version: 1
```

The first line gives completion and validation in editors with the YAML language server. Use the tag of the fleetlint you run:

| File | Schema |
|---|---|
| `.fleetlint.yaml` | `https://raw.githubusercontent.com/fleetlint/fleetlint/v0.10.2/internal/config/schema.json` |
| a catalog | `https://raw.githubusercontent.com/fleetlint/fleetlint/v0.10.2/internal/catalog/catalog.schema.json` |
| a sources file | `https://raw.githubusercontent.com/fleetlint/fleetlint/v0.10.2/internal/catalog/sources.schema.json` |

`fleetlint schema` prints the first; `fleetlint schema catalog` and `fleetlint schema sources` print the others.
