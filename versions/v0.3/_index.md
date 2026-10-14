---
title: "fleetlint"
description: "Policy for a fleet of repositories."
---

# fleetlint

Policy for a fleet of repositories. fleetlint checks how a repository is set up (hooks, task runner, lint configuration, CI, release pipeline) against a catalog of rules, reports how far it is from compliant, and tells you or your coding agent exactly how to close each gap.

It does not lint code. It checks that the things which lint, test, build and release the code are present, wired together and configured the way you decided they should be, in every repository, the same way.

```sh
brew install fleetlint/tap/fleetlint     # or scoop, nix, mise, a container: see Getting started
cd your-repo
fleetlint                 # zero configuration: discovers the setup, applies the recommended preset
fleetlint fix --apply     # writes what can be written; never overwrites a file
```

## Where to go

| If you want to | Read |
|---|---|
| try it on a repository | [Getting started](getting-started.md) |
| know what it checks and why | [The baseline](baseline.md), [stack profiles](stacks.md), [slop catalog](slop.md) |
| look up a rule | [Rule catalog](rule-catalog.md), [rule reference](rules/_index.md) |
| configure a repository | [Configuration](configuration.md) |
| roll it out across a company | [Organisations](organisations.md), [fleet mode](fleet.md) |
| write rules | [Writing rules](writing-rules.md), [CEL reference](cel-reference.md) |
| wire it into hooks, CI and editors | [Integrations](integrations.md) |
| see how it relates to Scorecard, repolinter and alint | [Comparison](comparison.md) |
| see it running | [Demo](demo.md) |

The tool is at [github.com/fleetlint/fleetlint](https://github.com/fleetlint/fleetlint), the rules at [github.com/fleetlint/catalog](https://github.com/fleetlint/catalog). Changes and plans: [project](project.md).
