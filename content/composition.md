---
title: "How rules combine"
weight: 75
description: "The one pass that turns presets, catalogs, selections, overrides and the repository's own configuration into the effective rule set; what happens when two of them touch the same rule; and what makes the result the same on every machine."
---

# How rules combine

A repository's effective rule set comes from several places: the presets, an organisation catalog, a team catalog, the repository's own `.fleetlint.yaml`. This page is the complete account of how they are put together, and of the three guarantees the design makes: the result is **reproducible** (the same on every machine and every run), **attributed** (every rule and every change says who made it) and **tightening-only** (a later catalog can adjust, never undo policy). Every statement here is held by a test in fleetlint (`internal/config/hierarchy_test.go`, `composition_test.go`, `policy_test.go`, `overrides_test.go`).

## Vocabulary

| Term | Meaning |
|---|---|
| **rule** | One check with an id (`repo/readme-present`). The id is the rule's identity everywhere: reports, exceptions, overrides, explain pages. |
| **capability** | A rule that states one requirement and is checked by an implementation per stack (`lint/configured`, implemented by `lint/configured/go`, `lint/configured/python`, ...). See [capabilities](writing-rules.md#capabilities-one-requirement-one-implementation-per-stack). |
| **library** | The catalog repository's `rules/<family>/<name>.yaml` files, one rule per file, the path spelling the id; a capability's implementations at `rules/<family>/<name>/<stack>.yaml`. Every catalog version ships one; a catalog may ship its own `rules/` next to it. |
| **catalog version** | One release of [fleetlint/catalog](https://github.com/fleetlint/catalog): presets, library and fix templates together. The binary embeds one; `catalog: {version: …}` chooses another. **A run uses exactly one.** |
| **catalog** | A YAML document with `metadata` (name, version, engine, `label`, `catalog`), `includes`, a `rules` list, `overrides` and `exceptions`. Presets, organisation and team catalogs, and the repository's own file are all catalogs. |
| **preset** | A catalog that is part of the catalog version (`fleetlint:minimal`, `recommended`, `strict`, `oss`, `slop`). Presets define no rules: they *select* from the library or *override* another preset. |
| **select** (`- use: …`) | An entry in a catalog's `rules` list that takes a rule, or a family of rules, from the library as it is. |
| **define** (inline) | An entry in a catalog's `rules` list with an `id` and the rule's full text. |
| **override** | An entry in a catalog's `overrides` map that adjusts a rule the catalog took in from elsewhere. |
| **label** | The name a catalog is attributed by in reports and named by for `--require`: what it declares in `metadata.label` (`org`, `team/mobile`, `security-team`, anything), else the sources-file name it is loaded under, else its own name. Presets are `preset`, the repository's own file is `repo`. A label identifies; it does not order. |
| **order** | The position of a catalog in the run, from 1. A later catalog adjusts an earlier one within the earlier one's policy. `fleetlint hierarchy` prints it. |
| **policy** | The three constraints a catalog can put on a rule for everything after it: `locked`, `min_severity`, `exceptions: false`. |

## What makes a run reproducible

Three facts fix the result, and nothing else influences it:

1. **The catalog version.** Set in `.fleetlint.yaml` (`catalog:`), in the organisation's sources file, or neither (the built-in one). Both may speak if they agree; they may not disagree. Every organisation or team catalog states the version it builds on in `metadata.catalog`; a run on another version fails with both versions named, instead of resolving `use: lint/*` to whatever the reader's binary happens to ship. A remote catalog that includes presets or selects from the library *must* state it.
2. **The catalogs, by content.** Presets by version; remote catalogs by digest, commit or signature; the sources file pinned the same way.
3. **The order**, which is the include graph, then the sources file's baseline, then the repository's `extends` as written. Nothing is reordered: whoever lists a catalog first binds the ones after it.

So two machines with the same `.fleetlint.yaml`, the same sources file and any fleetlint binary that can run the catalog version produce the same effective rule set, or the same error.

## The pass

The effective rule set is computed once, at load time:

1. **Collect what to extend**: the sources file's `extends` (the baseline every repository gets), then the repository's `extends`, each alias resolved; a repository that names nothing gets `fleetlint:recommended`.
2. **Load each entry with its `includes`** (depth-first, listed order). A catalog is loaded once however many paths lead to it; a cycle is an error, and so are two versions of one catalog name (the sources file pins v3.2, a team catalog includes v3.1). Each catalog gets its label: `preset` for presets, what it declares, else its sources-file name, else its name. Each is checked against the run's catalog version.
3. **Keep that order.** An include always comes before the catalog that includes it, so a team catalog that includes the organisation's can never apply before it, whatever the repository writes.
4. **Apply each catalog**: its `rules` list in list order — inline definitions and `use:` selections, the latter expanded from the catalog's own `rules/` first and the run's library second — then its `overrides` (patterns before exact ids), then its `exceptions`.
5. **The repository's own file last**, labelled `repo`, with the same grammar: `rules` (definitions and selections), `overrides`, `exceptions`. Then scopes and nested files, which may only override and except.

`fleetlint hierarchy` prints the result, and every report carries it under `catalogs`:

```text
sources.yaml:   catalog: {version: v0.1.0}   extends: [fleetlint:recommended, org]
.fleetlint.yaml: extends: [team/platform]

#  catalog                                  label     name                      pinned by        builds on  contributes
1  fleetlint:minimal                        preset    fleetlint-minimal@v0.1.0  sha256-…         -          8 rules
2  fleetlint:recommended                    preset    fleetlint-recommended@…   sha256-…         #1         71 rules
3  org = git+https://…/org.yaml@v3.2.0      org       acme@3.2.0                sha256-…         #2         3 rules, 2 overrides
4  team/platform = git+https://…@v3.2.0     platform  acme-platform@3.2.0       sha256-…         #3         1 rule
5  .fleetlint.yaml                          repo      .fleetlint.yaml@local     file in the repository  -   1 override, 2 exceptions
```

A catalog file of the repository listed in `extends` takes its place in the written order like any other; it is labelled by what it declares, else its name. It cannot satisfy `--require` by name, and the sources file's baseline always comes before it.

## When an id is met again

A rule's identity is its id. These are all the things that can happen when an id already loaded is met again, and the only things:

| Situation | Result |
|---|---|
| Two inline definitions in one catalog | error |
| An inline definition and a `use:` of the same id, in one catalog | the inline definition; this is how one rule of `lint/*` is replaced while the rest is kept |
| A `use:` of a rule that is already loaded (from an include or an earlier catalog) | kept exactly as first loaded — same label, same selector, same overrides; nothing is redefined or recorded |
| Two catalogs select the same library rule | loaded once, from the first |
| An inline definition, in a catalog, of an id already loaded | **replaces** the rule wholesale: title, kind, expression, severity, params, all from the new text. Refused if the earlier definition is locked; refused if the new severity is below the earlier floor, which is otherwise inherited. A lower severity is recorded as *weakened*, under the label of the catalog that did it, and appears in every report |
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

**Run two in parallel: a new id.** Give yours an id in your own family (`acme/go-lint`) and leave the built-in one in place, or disable it with a reason:

```yaml
rules:
  - id: acme/go-lint
    …
overrides:
  lint/strict/go: {enabled: false, reason: "replaced by acme/go-lint, which also checks the forbidden imports"}
```

Ids never merge. Two rules that check similar things are two findings, two explain pages, two exceptions; the report says why the original is off.

## Capabilities and their implementations

A capability and its implementations are selected, adjusted and bound together. `use: lint/configured` selects the capability with every implementation; an override, an exception or a policy written for the capability id reaches all of them, and one written for `lint/configured/go` reaches that stack only. Disabling a capability is recorded once, not once per stack. Through the capability, `when` replaces the shared gate and leaves each implementation's own condition alone, and `accept:` reaches the outcome implementations. Every implementation that runs must pass (see [capabilities](writing-rules.md#capabilities-one-requirement-one-implementation-per-stack)); a repository cannot change that.

An organisation catalog that ships `rules/` can add or replace an implementation without copying the capability: `rules/deps/unused-check/ruby.yaml` in that catalog inherits title, severity, requirement and fix from the fleetlint capability. Its implementations and its `stacks:` lists use the stacks of the catalog version the run uses; a catalog cannot define a stack of its own (see [stacks and per-stack rules](organisations.md#stacks-and-per-stack-rules)).

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

- `label` — who brought the rule in: `preset`, `repo`, or the label of the catalog (`org`, `team/mobile`, `security-team`).
- `source` — where its text lives: the defining catalog (`acme-baseline@1.0.0`), or `library <version>` for a selected rule.
- `selected_by` — for a selected rule, the catalog whose `use:` took it in.
- Every disable, lowered severity and exception carries the label and the file or catalog that did it, and its reason. A fleet report can therefore answer "which team lowered what, and why" from the data alone.
- `catalogs` in the JSON (and `fleetlint hierarchy`) lists every catalog of the run in order, with its reference, label, name and version, the sha256 of its file or the digest of its OCI artifact, what it builds on and what it contributed, so a definition can be followed to the exact content afterwards.

## The repository's part

The repository's `.fleetlint.yaml` is the last catalog of the run and uses the catalog grammar:

- `rules:` defines rules of its own (ids in its own family; `command` rules are allowed only here) or selects library rules the extended presets did not (`- use: slop/commented-out-code`). A terse definition is fine: the id serves as title, the message as requirement.
- `overrides:` adjusts catalog rules — severity (lowering needs a reason), `raise`, `params`, `accept`, `enabled: false` with a reason — within policy. It may not set policy or applicability.
- `exceptions:` per rule, optionally per path (`match`), always with a reason, optionally with an `until` date.
- `catalog:` and `sources:` choose the catalog version and the organisation's names and baseline.

It may not redefine a catalog rule. Scopes and nested files have `overrides` and `exceptions` only.

## Checklist for catalog authors

- Declare `engine`, `label` and `catalog` in `metadata`. Without `catalog`, a remote catalog cannot build on presets or the library, by design. A catalog that must come after another includes it.
- Select with `use:`; define inline only what is yours. A family glob (`lint/*`) follows the library as it grows — within the pinned catalog version, so growth is a visible version change, never a surprise.
- Adjust with `overrides`; overwrite only when the check itself must differ.
- New checks get ids in your own family. Never reuse a built-in id for a different check.
- Write what must hold as policy (`locked`, `min_severity`, `exceptions: false`), not as a severity override.
- Put the catalog version and the baseline `extends` in the sources file, so repositories carry one line (`sources:`) and cannot run another version or leave the baseline out.
- Read the report's policy notes: every disable, lowered severity and exception is listed with its label and reason. If something you meant to hold does not appear as refused when a team tries to bend it, it was not policy.
