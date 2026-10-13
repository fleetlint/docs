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
- uses: fleetlint/action@main   # no release yet: pin a commit SHA
  with:
    version: v0.3.0
    fail-on: warning
    sarif-file: fleetlint.sarif
- uses: github/codeql-action/upload-sarif@v4   # GitHub only; shows findings in the Security tab
  if: always()
  with:
    sarif_file: fleetlint.sarif
```

[fleetlint/action](https://github.com/fleetlint/action) installs the release binary (checked against `checksums.txt`, and against its cosign signature when `cosign` is on PATH), annotates every finding on its file and line, writes the report into the job summary and fails the step at `fail-on`. No Go toolchain needed. Gitea and Forgejo run it as `uses: https://github.com/fleetlint/action@<commit SHA>`; skip the SARIF upload there. The action has no release yet, so pin `uses:` to a commit SHA.

## GitLab CI

```yaml
include:
  - remote: https://raw.githubusercontent.com/fleetlint/fleetlint/v0.3.0/ci/gitlab/fleetlint.yml
```

The job installs the release of the tag it is included from, with that tag's install script, and requires the cosign signature of its checksums. It reports the findings in the merge request's Code Quality widget and fails at `FLEETLINT_FAIL_ON` (default `error`).

## What the CI rules read

The `ci/*` and `release/*` rules read the CI configuration of every system fleetlint knows: GitHub, Gitea and Forgejo Actions workflows (`.github/workflows`, `.gitea/workflows`, `.forgejo/workflows`) and `.gitlab-ci.yml` with the local files it includes. A rule about something only one system has applies to that system only, for example `permissions:` (GitHub and Gitea) or `persist-credentials` on `actions/checkout` (Actions); each rule's page in the [rule reference](rules/_index.md) says which it reads. `fleetlint fix` writes a GitHub Actions check workflow; on GitLab, add a job that runs the task runner's `check`.

## Make

```make
check: lint test cover audit build
	fleetlint check --fail-on error
```

The templates `fleetlint fix` writes already do all three: a local hook, this line in the Makefile's `check` target, and an install step in the check workflow. `quality/policy-enforced` reports a repository where nothing runs fleetlint.

## Machine-readable output

`fleetlint check --format json` writes the whole run: `results` (each rule with its `status`, findings and evidence), `summary`, `facts`, `scopes`, the `catalogs` loaded with their layers, and what was `disabled` or `weakened`. Field names are snake_case and the document carries `version: 2`; a change of shape gets a new version. `summary.errors` counts error-severity failures, `summary.rule_errors` the rules that could not run. A rule's satisfiers from `accept:` are in `results[].rule.accept`. `--format sarif` writes SARIF for code-scanning tools.

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
