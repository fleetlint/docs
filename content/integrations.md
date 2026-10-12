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
    version: v0.2.0
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
  - remote: https://raw.githubusercontent.com/fleetlint/fleetlint/main/ci/gitlab/fleetlint.yml
variables:
  FLEETLINT_VERSION: v0.2.0
```

The job installs the release, reports the findings in the merge request's Code Quality widget and fails at `FLEETLINT_FAIL_ON` (default `error`). Pin the include to a tag once one carries the file.

## Make

```make
check: lint test cover audit build
	fleetlint check --fail-on error
```

The templates `fleetlint fix` writes already do all three: a local hook, this line in the Makefile's `check` target, and an install step in the check workflow. `quality/policy-enforced` reports a repository where nothing runs fleetlint.

## Pull-request comments

`fleetlint check --format markdown` renders a comment-ready table with a collapsed block of agent instructions. Post it with `gh pr comment --body-file` or Gitea's API from a workflow step.

## Coding agents

`fleetlint check --format agent` emits an ordered task list, one rule per section, each with the requirement, the findings and a precise instruction. Hand it to the agent as the task. `fleetlint explain <rule>` gives the agent the full context for one rule when it asks.

## Editors

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/fleetlint/fleetlint/main/internal/config/schema.json
version: 1
```

The first line gives completion and validation in editors with the YAML language server. `fleetlint schema` prints the same schema.
