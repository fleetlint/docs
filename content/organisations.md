---
title: "Organisations"
weight: 70
description: "Your own catalog on top of the presets: overrides, locks and floors, layers for teams, and enforcement."
---

# Organisations

A company has more than one layer of policy: what security or platform require of every repository, what a team adds, and what a repository decides for itself. fleetlint models that with catalogs.

## Your own catalog

A catalog is a YAML file in the same format as the presets. It builds on them with `includes`, adds rules of its own, and adjusts the included ones with `overrides:`:

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata:
  name: acme-baseline
  version: 1.0.0
  engine: 1
  includes: ["fleetlint:recommended"]
rules:
  - id: acme/owner-file
    title: Every repository names its owning team
    kind: expr
    severity: error
    expr: file("OWNERS")
    message: "OWNERS is missing"
    requirement: An OWNERS file names the team responsible for the repository.
    fix: { human: "Add OWNERS with the team's handle." }
overrides:
  repo/no-tracked-env: { locked: true, exceptions: false }
```

A repository references it from a local path, an https URL with a digest, or a git repository at a tag or commit:

```yaml
extends:
  - git+https://git.example.com/platform/standards.git//catalog.yaml@<commit>
```

A catalog loaded over https or git can add and tighten rules, use the built-in fix templates and every function in [the CEL reference](cel-reference.md). It cannot declare rules that execute commands; only a repository's own configuration and catalogs on a local path can. How rules are written is in [writing rules](writing-rules.md).

## Overrides in a catalog

A catalog that builds on another does not restate a rule to change it. Next to `rules:` it lists `overrides:` for rules its `includes` brought in:

```yaml
metadata: {name: acme-baseline, version: 1.0.0, includes: ["fleetlint:recommended"]}
rules: []
overrides:
  repo/no-tracked-env:    {locked: true, exceptions: false}
  ci/actions-pinned:      {severity: error, min_severity: warning}
  taskrunner/targets:     {params: {required: [lint, test, check]}}
  deps/vulnerability-scan: {accept: [{name: our-scanner, expr: 'text(taskrunner.file).contains("acme-scan")'}]}
  docs/adr-directory:     {enabled: false, reason: "decisions are kept in the wiki"}
```

- `severity`, `params`, `accept` and `enabled` work as in a repository's `rules:` block, including the need for a `reason` when a rule is disabled or its severity lowered. Such changes appear in every report with the catalog's layer.
- `locked`, `min_severity` and `exceptions` set the policy for everything loaded afterwards, and only ever tighten it: a rule an earlier catalog locked cannot be unlocked, disabled or lowered, a floor cannot be lowered, and exceptions that were forbidden cannot be allowed again.
- The rule keeps the catalog it came from as its source, and follows that catalog's later improvements; `explain` and the reports name the catalog that set the policy.
- An override for a rule that no earlier catalog defines is an error, as is one for a rule the same catalog defines.

## Organization catalogs: locks, floors, `--require`

A catalog that serves as an organization baseline can constrain what lower layers (team catalogs, the repository, its scopes and nested files) may do with a rule:

```yaml
rules:
  - id: security/no-tracked-secrets
    severity: error
    locked: true          # cannot be disabled, lowered or redefined by anything loaded after it
    exceptions: false     # no per-finding exceptions either; reserved for the few absolute rules
  - id: ci/actions-pinned
    severity: error
    min_severity: warning # may be lowered to warning (with a reason), never to info; may be disabled with a reason
```

Violations are configuration errors at load time (exit 2), not weaker checks at run time, and they name the catalog that set the constraint. Raising severity, adding `params` and `accept`, and reasoned exceptions on locked rules remain possible; the report shows every one.

Locks only hold for catalogs that are actually loaded. A repository could drop the baseline from `extends`, so enforcement belongs where the check runs: the organization's CI template and fleet runner pass `--require acme-baseline` (a catalog name, a ref, or `ref#sha256-<digest>` to pin the exact version). A repository whose effective configuration lacks that catalog fails with exit 2 before any rule runs, and in fleet mode becomes an error row. The flag is persistent, so `fix`, `explain` and `baseline` refuse under a weaker configuration too.

## Layers: organization, teams, repository

Repositories should not carry URLs and pins for every catalog. An organization publishes one **sources file** that names its catalogs:

```yaml
# sources.yaml
version: 1
catalogs:
  org: git+https://git.example.com/platform/standards.git//org/catalog.yaml@v3.2.0#sha256-<hex>
  team/platform: git+https://git.example.com/platform/standards.git//teams/platform/catalog.yaml@v3.2.0#sha256-<hex>
  team/mobile: https://standards.example.com/teams/mobile.yaml#sha256-<hex>
```

and a repository refers to it:

```yaml
version: 1
sources: git+https://git.example.com/platform/standards.git//sources.yaml@<commit>
extends: [fleetlint:recommended, org, team/platform]
```

- Names are `org` or `team/<name>`; nothing else is accepted. Targets are presets, https catalogs with a digest or git catalogs. A sources file given as a local path may also name local paths, resolved relative to itself; a remote one may not.
- The sources file itself is a local path, an https URL with a digest or a git reference, pinned the same way as a catalog. Rotating a catalog version is then one change to the sources file and one pin update per repository.
- With `sources`, resolution order is fixed however `extends` is written: presets, then `org`, then `team/*`, then catalogs the repository references directly, then its own `rules:`. Without `sources`, the written order applies as before.
- Every rule carries the layer that defined it (`preset`, `org`, `team`, `repo`): `explain` prints it, JSON has `rule.layer`, SARIF has it in the rule properties, and the JSON `catalogs` list has each catalog's layer and name.
- Locks and severity floors hold across catalogs: a team catalog cannot redefine a locked organization rule or set a severity below the organization's `min_severity`, and the floor still binds the repository after a team redefines the rule. A later layer lowering an earlier layer's severity is allowed above the floor and is recorded: it appears under `weakened` in JSON and under "Lowered severities" in the fleet report with its layer, next to what repositories lowered themselves.
- `--require org` and `--require team/platform` match the names from the sources file.


## The fleet view

`fleetlint fleet` checks every repository and writes one report: compliance per repository and per team, the repository by rule matrix, and policy notes listing every disabled rule, lowered severity and exception with the layer that made it. See [fleet mode](fleet.md).
