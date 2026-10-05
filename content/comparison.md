---
title: "Comparison"
weight: 120
description: "fleetlint next to OpenSSF Scorecard, repolinter and alint: what each is for."
---

# Comparison

Several tools look at a repository instead of at its code. They answer different questions, and more than one of them can be right for the same repository. This page describes them as of October 2026; check each project for its current state.

| | Question it answers | Scope | Rules come from | Tells you how to fix |
|---|---|---|---|---|
| **fleetlint** | Is this repository set up the way we decided, and how far is each of our repositories from that? | one repository or a fleet, from the working tree | a catalog you can extend, override and lock per organisation and team | yes: a fix text and an agent instruction per rule, and mechanical fixes for part of it |
| **OpenSSF Scorecard** | How does this open-source project score on supply-chain security practices? | one repository, mostly through the forge's API | a fixed set of checks maintained by the OpenSSF | remediation text per check |
| **repolinter** | Does this repository contain the files and content our open-source programme requires? | one repository, from the working tree | a ruleset you write | optional automatic fixes for some rules |
| **alint** | Do the files in this repository have the shape we require? | one repository, from the working tree | a configuration with many built-in rule kinds, extendable | an instruction per finding |

## OpenSSF Scorecard

[Scorecard](https://github.com/ossf/scorecard) runs a set of security checks against a repository and gives each a score from 0 to 10: branch protection, pinned dependencies, token permissions, dangerous workflow patterns, signed releases, known vulnerabilities, whether the project is maintained, and others. Many checks use data only the forge has, such as branch protection settings and review history.

Use it when the question is the security posture of an open-source project, yours or a dependency's, measured the same way for everyone. Its checks and scoring are the same for all projects by design.

fleetlint overlaps where a check can be read from the files (pinned actions, workflow permissions, a security policy, signed releases with an SBOM) and differs in purpose: its rules are your policy, with tiers, exceptions with reasons, and a report across your repositories. It reads the working tree and does not look at branch protection or review history. The two fit together: Scorecard for the outside view of public projects, fleetlint for the setup you want in every repository including private ones.

## repolinter

[repolinter](https://github.com/todogroup/repolinter), from the TODO Group, checks a repository against a ruleset: that a license, a readme and contributing guidelines exist, that files contain or do not contain certain text, and similar. It was written for open-source programme offices. Check its repository for its maintenance status before adopting it.

fleetlint covers that ground with its `repo/*` and `public/*` rules and goes further into how the repository works: the task runner, hooks, linter configuration, CI and the release pipeline. Its rules can also say "any of these tools is fine" (outcome rules), which a file-presence check cannot.

## alint

[alint](https://alint.org) lints the shape of a repository's files with a large set of built-in rule kinds, facts evaluated once per run, shared configurations pinned by hash, a baseline for existing findings, nested configurations for monorepos and instructions for coding agents.

fleetlint adopted several of those ideas and is built around others: rules as expressions over discovered facts instead of many rule kinds, outcome rules that accept several tools, exceptions with reasons and deadlines, tiers and public-only rules, layers for organisations and teams with locks and floors, and the fleet report. If the need is precise rules about file shape in one repository, alint is the more direct tool. If the need is one policy across many repositories with room for each to differ visibly, that is what fleetlint is for.

## What fleetlint is not

- Not a code linter. It checks that a linter is configured strictly, not what the linter finds.
- Not a security scanner. It checks that scanners run, not what they report.
- Not a service. It is a binary that reads a working tree; reports are files you keep where you already keep things.
