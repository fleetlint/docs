---
title: "How rules combine"
weight: 75
description: "The one pass that turns presets, catalogs, selections, overrides and the repository's own configuration into the effective rule set; what happens when two of them touch the same rule; and what makes the result the same on every machine."
---

# How rules combine

A repository's effective rule set comes from several places: the presets, an organisation catalog, a team catalog, the repository's own `.fleetlint.yaml`. This page is the complete account of how they are put together, and of the three guarantees the design makes: the result is **reproducible** (the same on every machine and every run), **attributed** (every rule and every change says who made it) and **tightening-only** (a lower layer can adjust, never undo policy). Every statement here is held by a test in fleetlint (`internal/config/hierarchy_test.go`, `composition_test.go`, `policy_test.go`, `overrides_test.go`).

## Vocabulary

| Term | Meaning |
|---|---|
| **rule** | One check with an id (`lint/go-config`). The id is the rule's identity everywhere: reports, exceptions, overrides, explain pages. |
| **library** | The catalog repository's `rules/<family>/<name>.yaml` files, one rule per file, the path spelling the id. Every catalog version ships one; a catalog may ship its own `rules/` next to it. |
| **catalog version** | One release of [fleetlint/catalog](https://github.com/fleetlint/catalog): presets, library and fix templates together. The binary embeds one; `catalog: {version: …}` chooses another. **A run uses exactly one.** |
| **catalog** | A YAML document with `metadata` (name, version, engine, `layer`, `catalog`), `includes`, a `rules` list, `overrides` and `exceptions`. Presets, organisation and team catalogs, and the repository's own file are all catalogs. |
| **preset** | A catalog that is part of the catalog version (`fleetlint:minimal`, `recommended`, `strict`, `oss`, `slop`). Presets define no rules: they *select* from the library or *override* another preset. |
| **select** (`- use: …`) | An entry in a catalog's `rules` list that takes a rule, or a family of rules, from the library as it is. |
| **define** (inline) | An entry in a catalog's `rules` list with an `id` and the rule's full text. |
| **override** | An entry in a catalog's `overrides` map that adjusts a rule the catalog took in from elsewhere. |
| **layer** | Who owns a catalog: `preset`, `org`, `team`, `repo`. A catalog declares `org` or `team` in `metadata.layer`; presets are `preset`; everything else, including the repository's file, is `repo`. |
| **policy** | The three constraints a catalog can put on a rule for everything after it: `locked`, `min_severity`, `exceptions: false`. |

## What makes a run reproducible

Three facts fix the result, and nothing else influences it:

1. **The catalog version.** Set in `.fleetlint.yaml` (`catalog:`), in the organisation's sources file, or neither (the built-in one). Both may speak if they agree; they may not disagree. Every organisation or team catalog states the version it builds on in `metadata.catalog`; a run on another version fails with both versions named, instead of resolving `use: lint/*` to whatever the reader's binary happens to ship. A remote catalog that includes presets or selects from the library *must* state it.
2. **The catalogs, by content.** Presets by version; remote catalogs by digest, commit or signature; the sources file pinned the same way.
3. **The layer order**, which is fixed, not written. `extends` can be in any order and the result is the same.

So two machines with the same `.fleetlint.yaml`, the same sources file and any fleetlint binary that can run the catalog version produce the same effective rule set, or the same error.

## The pass

The effective rule set is computed once, at load time:

1. **Collect what to extend**: the sources file's `extends` (the baseline every repository gets), then the repository's `extends`, each alias resolved; a repository that names nothing gets `fleetlint:recommended`.
2. **Load each entry with its `includes`** (depth-first, listed order). A catalog is loaded once however many paths lead to it; a cycle is an error. Each catalog gets its layer: `preset` for presets, the declared `org` or `team` (which must agree with the sources-file alias it is loaded under), `repo` otherwise. Each is checked against the run's catalog version.
3. **Order by layer**: preset → org → team → repo. Within a layer, the order of step 1.
4. **Apply each catalog**: its `rules` list in list order — inline definitions and `use:` selections, the latter expanded from the catalog's own `rules/` first and the run's library second — then its `overrides` (patterns before exact ids), then its `exceptions`.
5. **The repository last**, as a catalog of layer `repo` with the same grammar: `rules` (definitions and selections), `overrides`, `exceptions`. Then scopes and nested files, which may only override and except.

```text
sources.yaml:   catalog: {version: v0.2.0}   extends: [fleetlint:recommended, org]
.fleetlint.yaml: extends: [team/platform]

fleetlint:recommended   layer preset   includes minimal (7) + use: repo/*, ci/*, lint/*, … (76)
org                     layer org      catalog v0.2.0 ✓   use: slop/*  +  acme/owner-file  +  overrides "release/*": {locked: true}
team/platform           layer team     catalog v0.2.0 ✓   lint/go-config redefined inline (weakened: recorded)
.fleetlint.yaml         layer repo     overrides quality/coverage-threshold: {params: {min: 90}}   exceptions: …
```

## When an id is met again

A rule's identity is its id. These are all the things that can happen when an id already loaded is met again, and the only things:

| Situation | Result |
|---|---|
| Two inline definitions in one catalog | error |
| An inline definition and a `use:` of the same id, in one catalog | the inline definition; this is how one rule of `lint/*` is replaced while the rest is kept |
| A `use:` of a rule that is already loaded (from an include or an earlier catalog) | kept exactly as first loaded — same layer, same selector, same overrides; nothing is redefined or recorded |
| Two catalogs select the same library rule | loaded once, from the first |
| An inline definition, in a catalog, of an id already loaded | **replaces** the rule wholesale: title, kind, expression, severity, params, all from the new text. Refused if the earlier definition is locked; refused if the new severity is below the earlier floor, which is otherwise inherited. A lower severity is recorded as *weakened*, by whichever layer, and appears in every report |
| An inline definition, in the repository's file, of an id a catalog defines | error: the repository adjusts under `overrides`; it does not redefine, so policy stays readable from the catalogs alone |
| An `overrides` key for a rule the same catalog defines inline | an exact key is an error (change the definition); a pattern skips the catalog's own definitions |

## Three ways to change a rule you did not write

**Extend without restating: `overrides`.** An override adjusts a rule the catalog took in from an include, from an earlier catalog, or from its own `use:` selections:

```yaml
overrides:
  ci/actions-pinned:        {severity: error}                 # or raise: 1
  deps/vulnerability-scan:  {accept: [{name: our-scanner, expr: 'text(taskrunner.file).contains("acme-scan")'}]}
  taskrunner/targets:       {params: {required: [lint, test, check]}}
  public/license:           {when: "true"}                    # applicability (catalogs only)
  docs/adr-directory:       {enabled: false, reason: "decisions live in the wiki"}
  "release/*":              {locked: true}                    # a pattern: the whole family
  "*":                      {raise: 1}                        # everything taken in, one step stricter
```

An override can set severity (`severity:` or `raise: N`), `params` (merged key by key), `accept` (adds satisfiers to an outcome rule — the usual way to recognise your own tool), `when` and `tiers`, `enabled: false` with a reason, and policy. It cannot change an expression, a satisfier or a message. For that, overwrite.

**Overwrite: define the id inline in a later catalog.** The new text is the rule. The earlier definition contributes its lock (which forbids the overwrite) and its floor (which the new severity must respect and which stays), nothing else. Use this when the *check* has to differ, not just its parameters. Only catalogs can overwrite; the repository adjusts.

**Run two in parallel: a new id.** Give yours an id in your own family (`acme/go-config`) and leave the built-in one in place, or disable it with a reason:

```yaml
rules:
  - id: acme/go-config
    …
overrides:
  lint/go-config: {enabled: false, reason: "replaced by acme/go-config, which also checks the forbidden imports"}
```

Ids never merge. Two rules that check similar things are two findings, two explain pages, two exceptions; the report says why the original is off.

## Policy: what a lock, a floor and `exceptions: false` hold

Policy binds everything applied after the catalog that set it, redefinitions included, and only ever tightens:

| Policy | A later catalog or the repository cannot … | … and can still |
|---|---|---|
| `locked: true` | disable it, lower its severity, change `when`, `tiers`, `params` or `accept`, redefine it inline, unlock it | raise its severity; declare a reasoned exception (visible in every report) |
| `min_severity: <level>` | set a severity below the level, by override or redefinition; **disable it** (off is below every floor); lower the floor | lower it to the floor with a reason |
| `exceptions: false` | declare an exception for it, in a catalog, the repository, a scope or a nested file; allow exceptions again | everything a lock allows |

Why `params` and `accept` are frozen by a lock: both can only widen what satisfies the rule — an `accept` adds a way to pass, a `params` change can lower a threshold — so a lock that left them open would not be one. The locking catalog sets the params and accepts the tools it recognises; a repository that needs more asks for a change there, or declares an exception, which is on record.

An **override does not survive a redefinition**: it adjusts a definition, and a later inline definition starts from its own text. What must survive is written as policy: `min_severity` for a severity, `locked` for everything.

Violations are configuration errors at load time (exit 2), naming the catalog that set the constraint; never a weaker check at run time.

## Attribution

Every rule in a report carries three things, and every change one:

- `layer` — who brought the rule in: `preset`, `org`, `team`, `repo`.
- `source` — where its text lives: the defining catalog (`acme-baseline@1.0.0`), or `library <version>` for a selected rule.
- `selected_by` — for a selected rule, the catalog whose `use:` took it in.
- Every disable, lowered severity and exception carries the layer and the file or catalog that did it, and its reason. A fleet report can therefore answer "which team lowered what, and why" from the data alone.

## The repository's part

The repository's `.fleetlint.yaml` is the last catalog of the run and uses the catalog grammar:

- `rules:` defines rules of its own (ids in its own family; `command` rules are allowed only here) or selects library rules the extended presets did not (`- use: slop/commented-out-code`). A terse definition is fine: the id serves as title, the message as requirement.
- `overrides:` adjusts catalog rules — severity (lowering needs a reason), `raise`, `params`, `accept`, `enabled: false` with a reason — within policy. It may not set policy or applicability.
- `exceptions:` per rule, optionally per path (`match`), always with a reason, optionally with an `until` date.
- `catalog:` and `sources:` choose the catalog version and the organisation's names and baseline.

It may not redefine a catalog rule. Scopes and nested files have `overrides` and `exceptions` only.

## Checklist for catalog authors

- Declare `engine`, `layer` and `catalog` in `metadata`. Without `catalog`, a remote catalog cannot build on presets or the library, by design.
- Select with `use:`; define inline only what is yours. A family glob (`lint/*`) follows the library as it grows — within the pinned catalog version, so growth is a visible version change, never a surprise.
- Adjust with `overrides`; overwrite only when the check itself must differ.
- New checks get ids in your own family. Never reuse a built-in id for a different check.
- Write what must hold as policy (`locked`, `min_severity`, `exceptions: false`), not as a severity override.
- Put the catalog version and the baseline `extends` in the sources file, so repositories carry one line (`sources:`) and cannot run another version or leave the baseline out.
- Read the report's policy notes: every disable, lowered severity and exception is listed with its layer and reason. If something you meant to hold does not appear as refused when a team tries to bend it, it was not policy.
