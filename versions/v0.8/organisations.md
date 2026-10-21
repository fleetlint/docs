---
title: "Organisations"
weight: 70
description: "Your own catalog on top of the presets: overrides, locks and floors, layers for teams, and enforcement."
---

# Organisations

A company has more than one level of policy: what security or platform require of every repository, what a business unit or a team adds, and what a repository decides for itself. fleetlint models that with catalogs that build on each other, applied in the order they are listed, and labelled by whoever owns them.

## Your own catalog

A catalog is a YAML file in the same format as the presets. It says who owns it (`label`) and which catalog version it builds on (`catalog`), builds on the presets and on other catalogs with `includes`, adds rules of its own, selects single built-in rules with `use:`, adjusts the included ones with `overrides:`, and may grant `exceptions:` to every repository that extends it:

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata:
  name: acme-baseline
  version: 1.0.0
  engine: 4
  label: org                        # who owns it: any name (org, team/mobile, security-team); reports attribute by it
  catalog: { version: v0.1.0 }      # the fleetlint catalog this builds on; every repository runs that version
  includes: ["fleetlint:minimal"]
rules:
  - use: release/*                  # built-in rules, picked one family at a time
  - use: slop/focused-tests         # or one by one, without taking all of recommended
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
exceptions:
  - { rule: repo/no-tracked-junk, match: "fixtures/*.log", reason: "parser fixtures across the fleet" }
```

- `label` is a free name: `org`, `team/mobile`, `security-team`, whatever identifies the owner. Reports attribute the catalog's rules, locks, lowered severities and exceptions to it, and `--require <label>` names it. It does not order anything. A catalog that says nothing is labelled by the sources-file name it is loaded under, else by its own name.
- Catalogs apply in the order they are listed: the sources file's `extends` first, then the repository's, and an include always before the catalog that includes it. Policy only tightens, so a catalog binds every catalog after it. A team catalog that must come after the organisation's includes it; an organisation that must come first everywhere puts its catalogs in the sources file's `extends`. [How rules combine](composition.md) is the full account; `fleetlint hierarchy` prints the order of a run.
- `catalog` names the fleetlint catalog version the presets it includes and the library it selects from come from. A remote catalog that includes presets or uses the library must state it, and the run fails if the repository runs another version: the catalog means the same rules everywhere or it fails loudly. The sources file sets that version for every repository (below).
- `exceptions` are the same as a repository's, granted fleet-wide and attributed to the catalog in every report; a catalog loaded before may forbid them for a rule (`exceptions: false`).

A repository references it from a local path, an https URL with a digest, or a git repository at a tag or commit:

```yaml
extends:
  - git+https://git.example.com/platform/standards.git//catalog.yaml@<commit>
```

A catalog loaded over https or git can add and tighten rules, use the built-in fix templates and every function in [the CEL reference](cel-reference.md). It cannot declare rules that execute commands; only a repository's own configuration and catalogs on a local path can. How rules are written is in [writing rules](writing-rules.md).

## Stacks and per-stack rules

Your catalog uses the stacks of the fleetlint catalog it builds on (`stacks/` at the version in `metadata.catalog`): detection, `repo.stacks` and the dev environment `fleetlint fix` writes come from there, so it never redefines Go or Node. On top of them it can:

- scope its own rules to a stack with `stacks: [go]`; a stack id the base does not define fails the load;
- select a capability with all its implementations (`use: lint/configured`) or adjust one stack (`overrides: {lint/configured/go: ...}`);
- add or replace an implementation of a base capability. A catalog shipped with a `rules/` directory (a git tree or an `oci://` artifact) puts it at `rules/<family>/<name>/<stack>.yaml`; the file states only its check and inherits title, severity, requirement and fix from the base capability:

```yaml
# rules/deps/unused-check/ruby.yaml in your catalog
id: deps/unused-check/ruby
kind: outcome
satisfiers:
  - name: our-tool
    expr: workflows().exists(w, steps(w).exists(s, s.run.contains("bin/unused-gems")))
```

What it cannot do is define a stack. A stack fleetlint does not ship (Terraform, an in-house language) needs its definition in `stacks/` of the catalog version the run uses: a fork of fleetlint/catalog, pinned with `catalog: {repo: ..., version: ...}`. [Capabilities](writing-rules.md#capabilities-one-requirement-one-implementation-per-stack) and [stacks](writing-rules.md#stacks) explain the formats.

## What applies when

The complete account of how presets, catalogs, selections, overrides and the repository combine, and what happens when two of them touch the same rule, is its own page: [how rules combine](composition.md). The short version: `extends` in order, includes before the catalog, a catalog's `rules` list in order and then its `overrides`, the repository last; an id met again is either kept (selections), replaced (an inline definition, within the earlier policy) or adjusted (an override); policy only tightens.

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
  public/license:         {when: "true"}          # run whatever the detected visibility
  docs/architecture:      {tiers: [1, 2]}
  "release/*":            {locked: true}           # a pattern: the whole family
  "*":                    {raise: 1}               # every included rule one step stricter
```

- A key is a rule id or a pattern over ids: `"*"` is every included rule, `"release/*"` a family. Patterns apply first, exact ids refine them. `raise: 1` lifts whatever matches one severity step (info → warning → error, capped at error); this is how `fleetlint:strict` is written: `"*": {raise: 1}` plus `exceptions: false` on the security rules.
- `severity`, `params`, `accept` and `enabled` work as in a repository's `overrides:` block, including the need for a `reason` when a rule is disabled or its severity lowered. Such changes appear in every report with the catalog's layer.
- `when` and `tiers` replace the rule's applicability: `when: "true"` makes a conditional rule unconditional (this is how `fleetlint:oss` switches the `public/*` family on), `tiers` widens or narrows the tiers it applies to. A locked rule refuses both.
- `locked`, `min_severity` and `exceptions` set the policy for everything loaded afterwards, and only ever tighten it: a rule an earlier catalog locked cannot be unlocked, disabled or lowered, a floor cannot be lowered, and exceptions that were forbidden cannot be allowed again.
- The rule keeps the catalog it came from as its source, and follows that catalog's later improvements; `explain` and the reports name the catalog that set the policy.
- An override for a rule that no earlier catalog defines is an error, as is one for a rule the same catalog defines.

## Organization catalogs: locks, floors, `--require`

A catalog that serves as an organization baseline can constrain what lower layers (team catalogs, the repository, its scopes and nested files) may do with a rule:

```yaml
rules:
  - id: security/no-tracked-secrets
    severity: error
    locked: true          # cannot be disabled, lowered, rescoped, reshaped (params, accept) or redefined by anything loaded after it
    exceptions: false     # no per-finding exceptions either; reserved for the few absolute rules
  - id: ci/actions-pinned
    severity: error
    min_severity: warning # may be lowered to warning (with a reason), never to info; may be disabled with a reason
```

Violations are configuration errors at load time (exit 2), not weaker checks at run time, and they name the catalog that set the constraint. Raising the severity of a locked rule and reasoned exceptions on it remain possible, `params` and `accept` do not (both only widen what satisfies the rule; the locking catalog sets them); the report shows every one.

Locks only hold for catalogs that are actually loaded. A repository could drop the baseline from `extends`, so enforcement belongs where the check runs: the organization's CI template and fleet runner pass `--require acme-baseline` (a catalog name, a ref, or `ref#sha256-<digest>` to pin the exact version). A repository whose effective configuration lacks that catalog fails with exit 2 before any rule runs, and in fleet mode becomes an error row. The flag is persistent, so `fix`, `explain` and `baseline` refuse under a weaker configuration too.

## Names: the sources file

Repositories should not carry URLs and pins for every catalog. An organization publishes one **sources file** that names its catalogs:

```yaml
# sources.yaml
version: 1
catalog: { version: v0.1.0 }         # the fleetlint catalog version every repository runs with (or {oci: ghcr.io/fleetlint/catalog:v0.1.0})
extends: [fleetlint:recommended, org, compliance/pci] # the baseline every repository gets, in this order, before its own extends
catalogs:
  org: git+https://git.example.com/platform/standards.git//org/catalog.yaml@v3.2.0#sha256-<hex>
  compliance/pci: oci://ghcr.io/acme/compliance-catalog:2
  bu/payments: git+https://git.example.com/payments/standards.git//catalog.yaml@v1.4.0#sha256-<hex>
  team/platform: git+https://git.example.com/platform/standards.git//teams/platform/catalog.yaml@v3.2.0#sha256-<hex>
  team/mobile: https://standards.example.com/teams/mobile.yaml#sha256-<hex>
```

and a repository refers to it, adding only what is its own:

```yaml
version: 1
sources: git+https://git.example.com/platform/standards.git//sources.yaml@<commit>
extends: [team/platform]
```

- Names are lowercase words joined by `/` (`org`, `team/mobile`, `compliance/pci`, `bu/payments`): any hierarchy the organisation has. Targets are presets, https catalogs with a digest, git or `oci://` catalogs. A sources file given as a local path may also name local paths, resolved relative to itself; a remote one may not. A catalog loaded under a name takes that name as its label unless it declares one.
- `catalog` is the one version of the fleetlint catalog for every repository; a repository may repeat it, not change it. `extends` is the baseline: the repository's own `extends` adds to it and cannot leave anything out. Together they answer "is the baseline present and complete" without a `--require` flag; `--require` stays for the runner that wants to insist.
- The sources file itself is a local path, an https URL with a digest or a git reference, pinned the same way as a catalog. Rotating a catalog version is then one change to the sources file and one pin update per repository.
- The order is what is written: the sources file's `extends`, then the repository's `extends`, then its own file, with every include before the catalog that includes it. A team catalog that includes `org` can never come before it. Nothing is sorted by name or label.
- Every rule carries the label of the catalog that brought it in (`preset`, `repo`, `org`, `team/mobile`, ...), the catalog that defined its text (`source`, the library for selected rules) and the catalog that selected it (`selected_by`): `explain` prints them, JSON has them on the rule, SARIF in the rule properties. The JSON `catalogs` list, `fleetlint hierarchy` and the fleet report's Catalogs section have every catalog of the run in order with its label, name, version and pin.
- Locks and severity floors hold across catalogs: a later catalog cannot redefine a locked rule or set a severity below an earlier `min_severity`, and the floor still binds the repository after a team redefines the rule. Every lowering, by whichever catalog, is recorded: it appears under `weakened` in JSON and under "Lowered severities" in the fleet report with the label.
- `--require org` and `--require compliance/pci` match the names from the sources file or a catalog's label or name, and count only catalogs fetched by digest, commit or signature: a local file of the same name does not satisfy them.

## Catalogs from a registry: `oci://`, signatures, private templates

An organization that runs a container registry can publish its catalog as an OCI artifact and sign it, so repositories pin a *signer* instead of a digest and a new catalog version needs no change in any repository:

```sh
oras push ghcr.io/acme/fleetlint-catalog:3.2.0 catalog.yaml templates/SECURITY.md templates/pre-commit/head.yaml
cosign sign --new-bundle-format ghcr.io/acme/fleetlint-catalog@sha256:<digest>   # keyless, from the publishing workflow
```

```yaml
# sources.yaml
version: 1
signers:
  - issuer: https://token.actions.githubusercontent.com
    subject_regex: '^https://github\.com/acme/standards/\.github/workflows/publish\.yml@refs/tags/v'
catalogs:
  org: oci://ghcr.io/acme/fleetlint-catalog:3
  team/platform: oci://ghcr.io/acme/fleetlint-catalog@sha256:<digest>
  team/mobile:
    ref: oci://ghcr.io/acme/mobile-catalog:2
    signers:
      - issuer: https://token.actions.githubusercontent.com
        subject_regex: '^https://github\.com/acme/mobile-standards/\.github/workflows/publish\.yml@refs/tags/v'
    min_version: 2.4.0
```

- An `oci://<registry>/<repository>:<tag>` reference is accepted only when signers are listed for it, in the sources file's `signers` or on the entry itself; a `@sha256:<digest>` reference needs none. When signers are listed, the signature is verified for every `oci://` catalog, digest or not.
- A `catalogs:` entry is the reference, or `{ref, signers, min_version}`. `signers` on an entry verify that catalog alone and replace the top-level `signers` for it, so a team that publishes from its own repository is trusted for its own catalog and for nothing else; an entry without `signers` keeps the top-level ones, which also verify the `catalog:` pin. `min_version` is a floor on the loaded catalog's `metadata.version` (a semantic version, with or without a leading `v`): a catalog below it fails the run, naming the alias, the loaded version and the floor. A tag such as `:3` follows the publisher, so the floor is how every repository notices the tag being moved back to an older release. `signers` are allowed only on an `oci://` reference; on any other the sources file is refused. With `min_version`, a catalog whose `metadata.version` is not a semantic version fails the run, since the floor cannot be checked.
- A signer is an OIDC `issuer` plus the certificate `subject`, exact or as `subject_regex`. For GitHub Actions the subject is the workflow reference (`https://github.com/<owner>/<repo>/.github/workflows/<file>@refs/tags/<tag>`); for a person signing with `cosign sign` it is their e-mail with `issuer: https://accounts.google.com` or another identity provider. Verification uses the sigstore public-good instance: the certificate chain, the transparency-log entry or a signed timestamp, and the certificate's signed certificate timestamp. The bundle must be attached to the artifact in the sigstore bundle format (`cosign sign --new-bundle-format`, cosign 2.5 or later); the older `.sig` tag layout is not read.
- Every layer of the artifact with an `org.opencontainers.image.title` annotation is a file, which is what `oras push <ref> <files...>` produces. Files named `*.yaml` at the root are catalogs, loaded in name order. Files under `templates/` are **fix templates that travel with the catalog**: `fleetlint fix` takes them before the preset's templates, so the organization's `SECURITY.md`, hook fragments or workflow head replace the public ones without a fork of fleetlint. The same trust applies: a template is written only from a catalog that was pinned or whose signature was verified.
- The registry is read with the credentials docker or oras already stored (`docker login`, `oras login`, credential helpers). Registries on exactly `localhost`, `127.0.0.1` or `::1`, on any port, are spoken to over plain http, as in tests; `localhost.example.com` is not. Signature lookup reads at most 32 referrers of an artifact and 8 bundle layers per referrer, and fetching the sigstore trust root stops after two minutes.
- A sources file itself cannot come from a registry: it is the trust anchor, so it stays a local path, an https URL with a digest or a git reference.
- **Without a registry**, a `git+` catalog ships templates the same way: a `templates/` directory next to the catalog file travels with it when the reference is pinned to a full commit SHA (a tag reference's digest covers the catalog file only, so templates are not taken from it). `git+https://git.example.com/platform/standards.git//org/catalog.yaml@<commit>` with `org/templates/SECURITY.md` in that repository makes `fleetlint fix` write the organization's security policy.

## The fleet view

`fleetlint fleet` checks every repository and writes one report: compliance per repository and per team, the repository by rule matrix, and policy notes listing every disabled rule, lowered severity and exception with the layer that made it. See [fleet mode](fleet.md).
