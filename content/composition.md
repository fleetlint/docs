---
title: "How rules combine"
weight: 75
description: "The one pass that turns presets, catalogs, selections, overrides and the repository's own configuration into the effective rule set, and what happens when two of them touch the same rule."
---

# How rules combine

A repository's effective rule set comes from several places: the presets, an organisation catalog, a team catalog, the repository's own `.fleetlint.yaml`. This page is the complete account of how they are put together. Every statement here is held by a test in fleetlint (`internal/config/composition_test.go`, `policy_test.go`, `overrides_test.go`); if the tool ever behaves differently, the test is wrong or the tool is.

## Vocabulary

| Term | Meaning |
|---|---|
| **rule** | One check with an id (`lint/go-config`). The id is the rule's identity everywhere: reports, exceptions, overrides, explain pages. |
| **library** | The catalog repository's `rules/<family>/<name>.yaml` files, one rule per file, the path spelling the id. The built-in library ships in the binary; a catalog may ship its own `rules/` next to it. |
| **catalog** | A YAML document with `includes`, a `rules` list and `overrides`. Presets, organisation and team catalogs are all catalogs. |
| **preset** | A catalog shipped with fleetlint (`fleetlint:minimal`, `recommended`, `strict`, `oss`, `slop`). Presets define no rules: they *select* from the library or *override* another preset. |
| **select** (`- use: …`) | An entry in a catalog's `rules` list that takes a rule, or a family of rules, from the library as it is. |
| **define** (inline) | An entry in a catalog's `rules` list with an `id` and the rule's full text. |
| **override** | An entry in a catalog's `overrides` map that adjusts a rule the catalog took in from elsewhere. |
| **layer** | Who owns a catalog: `preset`, `org`, `team`, `repo`. Every rule and every change carries the layer that made it. |
| **policy** | The three constraints a catalog can put on a rule for everything loaded after it: `locked`, `min_severity`, `exceptions: false`. |

## The pass

The effective rule set is computed once, at load time, in this order. Nothing later can change what an earlier step did except through the moves listed under *Touching a rule that exists*, and every move is recorded.

1. **`extends`, in written order.** With a `sources` file the order is fixed instead, whatever the repository writes: presets, then `org`, then `team/*`, then catalogs the repository names directly.
2. **For each catalog, its `includes` first**, depth-first and in the listed order, then the catalog itself. A catalog is loaded once however many paths lead to it; a cycle is an error.
3. **Within a catalog, the `rules` list in list order.** A `use:` entry expands to the rules it selects, in id order, taken from the catalog's own `rules/` directory first and the library of the catalog source second. An inline entry defines a rule. Then the catalog's `overrides`, patterns before exact ids.
4. **Last, the repository**: its `rules` block, then exceptions, then the baseline. Scopes and nested `.fleetlint.yaml` files follow the same rules as the repository's own block and may only adjust, never define.

```text
extends: [fleetlint:recommended, org, team/platform]

fleetlint:recommended
  └ includes fleetlint:minimal      → 7 rules          layer preset
  └ use: repo/*, ci/*, lint/*, …    → +76 rules        layer preset
org
  └ includes fleetlint:recommended  (already loaded: nothing happens)
  └ use: slop/*                      → +23 rules        layer org
  └ rules: acme/owner-file           → +1 rule          layer org
  └ overrides: "release/*": {locked: true}, ci/actions-pinned: {severity: error}
team/platform
  └ rules: lint/go-config (inline)   → replaces the preset's definition   layer team
  └ overrides: docs/adr-directory: {enabled: false, reason: "wiki"}
.fleetlint.yaml
  └ rules: quality/coverage-threshold: {params: {min: 90}}
  └ exceptions: - {rule: ci/job-timeouts, match: ".github/workflows/legacy.yml", reason: …, until: 2027-01-01}
```

## Touching a rule that exists

A rule's identity is its id. These are all the things that can happen when an id that is already loaded is met again, and the only things:

| Situation | Result |
|---|---|
| Two inline definitions in one catalog | error |
| An inline definition and a `use:` that selects the same id, in one catalog | the inline definition; the selection is dropped. This is how one rule of `lint/*` is replaced while the rest is kept. |
| A `use:` selects a rule that is already loaded, from an include or an earlier `extends` entry | the rule stays exactly as first loaded: same layer, same source, same overrides. Nothing is redefined and nothing is recorded. |
| Two catalogs select the same library rule | loaded once, from the first |
| An inline definition of an id that is already loaded | **replaces** the rule wholesale: title, kind, expression, severity, params, everything comes from the new text. Refused if the earlier definition is locked. Refused if the new severity is below the earlier floor; otherwise the floor is inherited. A lower severity across layers is recorded as *weakened* and appears in every report with the layer that did it. |
| An `overrides` entry for a rule the same catalog defines inline (exact key) | error: change the definition. A pattern skips the catalog's own inline rules for the same reason. |
| A repository `rules` entry for an id no catalog defines | an inline definition, layer `repo`, like any other |
| A repository `rules` entry with a `kind` for an id a catalog defines | error: the repository adjusts catalog rules, it does not redefine them (that keeps policy readable from the catalogs alone) |

## Three ways to change a rule you did not write

**Extend it without restating it: `overrides`.** An override adjusts a rule the catalog took in from an include, from an earlier `extends` entry, or from its own `use:` selections:

```yaml
overrides:
  ci/actions-pinned:        {severity: error}                 # or raise: 1
  deps/vulnerability-scan:  {accept: [{name: our-scanner, expr: 'text(taskrunner.file).contains("acme-scan")'}]}
  taskrunner/targets:       {params: {required: [lint, test, check]}}
  public/license:           {when: "true"}                    # applicability
  docs/architecture:        {tiers: [1, 2]}
  docs/adr-directory:       {enabled: false, reason: "decisions live in the wiki"}
  "release/*":              {locked: true}                    # a pattern: the whole family
  "*":                      {raise: 1}                        # everything taken in, one step stricter
```

What an override can do: severity (`severity:` or `raise: N`, capped at error), `params` (merged key by key), `accept` (adds satisfiers to an outcome rule, the usual way to recognise your own tool), `when` and `tiers`, `enabled: false` with a reason, and the policy keys. What it cannot do: change an expression, a satisfier, a message. For that, overwrite.

**Overwrite it: define the id inline in a later catalog.** The new text is the rule. The earlier definition contributes nothing but its lock (which forbids the overwrite) and its floor (which the new severity must respect and which stays). Use this when the *check* has to differ, not just its parameters.

**Run two in parallel: a new id.** Give your rule an id in your own family (`acme/go-config`) and leave the built-in one in place, or disable it with a reason:

```yaml
rules:
  - id: acme/go-config
    …
overrides:
  lint/go-config: {enabled: false, reason: "replaced by acme/go-config, which also checks the forbidden imports"}
```

Ids never merge. Two rules that check similar things are two findings, two explain pages, two exceptions; that is the price of clarity, and the report says why the original is off.

## Policy: what a lock, a floor and `exceptions: false` hold

A catalog that acts as a baseline sets policy on a rule, and policy binds everything loaded after it, including redefinitions:

| Policy | A lower layer cannot … | … and can still |
|---|---|---|
| `locked: true` | disable it, lower its severity, change its `when`, `tiers`, `params` or `accept`, redefine it inline, unlock it | raise its severity; declare a reasoned exception (visible in every report) |
| `min_severity: <level>` | set a severity below the level, by override or by redefinition; lower the floor | lower it to the floor with a reason; disable it with a reason |
| `exceptions: false` | declare an exception for it, in the repository, a scope or a nested file; allow exceptions again | everything a lock allows |

Policy only ever tightens: a later catalog can lock a rule that was open, raise a floor, forbid exceptions; it cannot undo any of the three. Violations are configuration errors at load time (exit 2) naming the catalog that set the constraint, never a weaker check at run time.

Why `params` and `accept` are frozen by a lock: both can only widen what satisfies the rule. An `accept` adds a way to pass, a `params` change can lower a threshold. A lock that left them open would not be one. The locking catalog sets the params and accepts the tools it recognises; a repository that needs more asks for a change there, or declares an exception, which is on record.

An **override does not survive a redefinition**: it adjusts a definition, and a later inline definition starts from its own text. What must survive is written as policy: `min_severity` for a severity, `locked` for everything.

## The repository's part

The repository's `.fleetlint.yaml` may:

- adjust catalog rules in `rules:` — severity (lowering needs a reason), `params`, `accept`, `enabled: false` with a reason — within the policy above;
- define new rules inline, with a `kind`, for ids no catalog has;
- declare exceptions: per rule, optionally per path (`match`), always with a reason, optionally with an `until` date; expired exceptions stop applying and are listed;
- pin a catalog version (`catalog: {version: …}`) and name a `sources` file.

It may not redefine a catalog rule, write policy keys, or change what a locked rule demands. Everything it does is attributed to the layer `repo` in reports, so a fleet view can answer "which repositories lowered what".

## Checklist for catalog authors

- Select with `use:`; define inline only what is yours. A family glob (`lint/*`) follows the library as it grows; an explicit list does not.
- Adjust with `overrides`; overwrite only when the check itself must differ.
- New checks get ids in your own family. Never reuse a built-in id for a different check.
- Write what must hold as policy (`locked`, `min_severity`, `exceptions: false`), not as a severity override, and lock the few rules where no local judgement is acceptable.
- State the engine level (`engine: 2`), include the smallest preset that fits (`minimal` plus families, rather than all of `recommended`, when you mean to pick), and version the catalog.
- Read the report's *policy notes*: every disable, lowered severity and exception is listed with its layer and reason. If something you meant to hold does not appear as refused when a team tries to bend it, it was not policy.
