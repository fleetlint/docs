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
    rev: v0.1.0
    hooks:
      - id: fleetlint
```

The hook builds fleetlint with the Go toolchain prek manages, runs `fleetlint check --fail-on error` on every commit (well under a second on a typical repository), and blocks commits with error-severity findings. Warnings are reported in CI instead, where they don't interrupt work.

## GitHub Actions and Gitea Actions

```yaml
- uses: fleetlint/action@v0.1.0   # or its commit SHA
  with:
    fail-on: warning
    sarif-file: fleetlint.sarif
- uses: github/codeql-action/upload-sarif@v4   # GitHub only; shows findings in the Security tab
  if: always()
  with:
    sarif_file: fleetlint.sarif
```

[fleetlint/action](https://github.com/fleetlint/action) installs the release binary (checked against `checksums.txt`, and against its cosign signature when `cosign` is on PATH), annotates every finding on its file and line, writes the report into the job summary and fails the step at `fail-on`. No Go toolchain needed. Each version of the action installs one pinned fleetlint release by default (v0.1.0: fleetlint v0.9.0); `version:` runs another (see [Versions](#versions)).

Gitea and Forgejo run it by its full URL, `uses: https://github.com/fleetlint/action@v0.1.0` (Forgejo resolves a short `uses:` against its own actions instance), on a runner with `bash`, `curl` and `tar`. The report goes into the job summary, which Forgejo shows from v17 with runner v13.2; annotations are off by default there (`annotations: auto`), since neither forge shows them, and there is no code scanning to upload SARIF to. Tested on Forgejo 17 with runner 13.2; Gitea runs the same steps but is not tested.

Every run checks. With `pr: true`, a run of the default branch also proposes changes on the repository it runs in, with the run's own token: the onboarding pull request (`fleetlint init --pr`) when the repository has no `.fleetlint.yaml`, and that run is not gated, since nothing is adopted yet; else the fixes pull request (`fleetlint fix --apply --pr`), updated on every run, and the run is gated as usual. Pull request runs and other branches only check, so one workflow serves both. The job needs `contents: write` and `pull-requests: write`, and on GitHub the setting *Allow GitHub Actions to create and approve pull requests*. A pull request opened with `GITHUB_TOKEN` starts no workflows; a GitHub App token (`actions/create-github-app-token`) or a fine-grained token passed as `token:` does. Gitea and Forgejo run the same step, with the instance and its API taken from the job; the commit is the instance's Actions user's (`forgejo-actions`, `gitea-actions`), and on Forgejo the job's own token can push and open the pull request.

## GitLab CI

The [fleetlint component](https://github.com/fleetlint/gitlab-components) for the GitLab CI/CD catalog:

```yaml
include:
  - component: gitlab.com/fleetlint/components/fleetlint@0.1.0
    inputs:
      fail-on: warning
      pr: true
```

A component version installs one pinned fleetlint release by default (0.1.0: fleetlint v0.9.0), with that release's install script, and requires the cosign signature of its checksums (`verify: checksum` checks the checksum only). Every run reports the findings in the merge request's Code Quality widget, keeps `fleetlint.json` as an artifact and fails at `fail-on` (default `error`). With `pr: true`, a pipeline of the default branch also opens or updates a merge request, as the action does: the onboarding configuration when the project has none (not gated), else the mechanical fixes. Other branches and merge request pipelines only check; a pipeline schedule keeps the fixes current between pushes. The job token cannot push or open merge requests, so `pr: true` needs `FLEETLINT_TOKEN`, a project access token with the `api` and `write_repository` scopes and the Developer role, as a masked CI/CD variable. The component also takes `stage`, `job-name`, `path`, `version` and `image` (an Alpine image, such as one from the dependency proxy).

A component can only be included from the instance it is published on. On a self-managed instance include the template by URL, which takes the same inputs:

```yaml
include:
  - remote: https://raw.githubusercontent.com/fleetlint/gitlab-components/0.1.0/templates/fleetlint.yml
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

The templates `fleetlint fix` writes already do all three: a local hook, this line in the Makefile's `check` target, and an install step in the check workflow. `quality/policy-enforced` reports a repository where nothing runs fleetlint.

## Machine-readable output

`fleetlint check --format json` writes the whole run: `results` (each rule with its `status`, findings and evidence), `summary`, `facts` (with the published `artifacts`), `scopes`, the `catalogs` in the order they applied (reference, label, name, version, digest or artifact, what each builds on and contributed), and what was `disabled` or `weakened`. Field names are snake_case and the document carries `version: 5` (a published artifact in `facts.artifacts` has a `kind`, a `name` where the catalog names instances, and its `workflows`; a rule's `refs` are objects with `url`, `kind` and `section`); a change of shape gets a new version. `fleetlint hierarchy --format json` writes the `catalogs` list on its own. `summary.errors` counts error-severity failures, `summary.rule_errors` the rules that could not run. A rule's satisfiers from `accept:` are in `results[].rule.accept`. `--format sarif` writes SARIF for code-scanning tools.

### SARIF

`fleetlint check --format sarif` writes SARIF 2.1.0 the way GitHub code scanning and the common viewers read it. Every result has a location: a finding about a file names the file and line, a finding about a missing file points at where the rule expects it (the rule's `locate`), and a finding about nothing in particular is anchored to the scope's `.fleetlint.yaml`, else its `README.md`, so code scanning does not drop it. Each rule carries `helpUri` to its page on this site, its family as a tag, and for the `release`, `ci`, `deps`, `containers`, `hooks` and `repo` families the `security` tag with a `security-severity` (8.0 for an error, 5.0 for a warning, 2.0 for a note), plus the rule's sources under `refs`. Results have a stable `partialFingerprints` entry (`fleetlint/v1`) so alerts keep their identity across runs. Excepted and baselined findings are results with a `suppressions` entry that carries the reason, and for an exception its expiry (`properties.until`), not silently dropped. A rule that could not run is a `toolExecutionNotifications` entry under `invocations`, with `executionSuccessful: false`. The log holds one run per scope: `automationDetails.id` is `fleetlint/<repository>/` for the root and `fleetlint/<repository>/<scope>/` for each scope. Code scanning takes an id up to its last `/` as the category, so the trailing slash gives every scope its own alert set; after upgrading from 0.7, the first upload moves a repository's alerts to these categories once. A finding about a named artifact shows the name in front of the message and is its own alert. A failing rule that `fleetlint fix --apply` can repair carries the change as `fixes` on its first result: one replacement per file it creates, appends to or edits, with offsets in UTF-16 code units (`columnKind`); a fix that untracks a file is not a text edit and is left out. The output validates against the OASIS schema in the tests.

## Pull-request comments

`fleetlint check --format markdown` renders a comment-ready table with a collapsed block of agent instructions. Post it with `gh pr comment --body-file` or Gitea's API from a workflow step.

## Coding agents

`fleetlint check --format agent` emits an ordered task list, one rule per section, each with the requirement, the findings and a precise instruction. Hand it to the agent as the task. `fleetlint explain <rule>` gives the agent the full context for one rule when it asks.

## Editors

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/fleetlint/fleetlint/main/internal/config/schema.json
version: 1
```

The first line gives completion and validation in editors with the YAML language server. `fleetlint schema` prints the same schema; `fleetlint schema catalog` and `fleetlint schema sources` print those of catalog files and sources files.
