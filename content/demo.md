---
title: "Demo"
weight: 130
description: "The fleet report over the fleetlint project's own repositories."
---

# Demo

The demo is fleetlint's fleet report over the project's own repositories: the tool, the catalog and this documentation. It shows what [fleet mode](fleet.md) produces: compliance per repository, the repository by rule matrix, the team summary, the policy notes with every disabled rule, lowered severity and exception, and a task list per repository.

It will be published at [demo.fleetlint.org](https://demo.fleetlint.org) once the repositories are public, and rebuilt nightly. Until then, produce the same report for your own repositories:

```sh
fleetlint fleet --from github:your-org --out report
open report/index.html
```

The report is a directory of static files with no scripts; it can be read from a file share or published as it is.
