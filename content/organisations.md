---
title: "Organisations"
weight: 70
description: "Your own catalog on top of the presets: writing it, publishing and pinning it, naming it in a sources file, enforcing it, and the fleet view."
---

# Organisations

A company has more than one level of policy: what security or platform require of every repository, what a business unit or a team adds, and what a repository decides for itself. fleetlint models that with catalogs that build on each other, applied in the order they are listed, and labelled by whoever owns them.

This page follows the order an administrator sets things up in: write the catalog, publish and pin it, name it in a sources file, enforce it in CI, then look at the whole fleet.

## The setup in one example

A standards repository at `https://git.example.com/platform/standards.git`:

```text
sources.yaml                           what every repository runs
org/catalog.yaml                       the organisation's catalog
org/rules/deps/unused-check/ruby.yaml  an implementation the presets lack
org/templates/SECURITY.md              replaces the preset's security policy template
```

`org/catalog.yaml`:

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata:
  name: acme-baseline
  version: 1.0.0
  engine: 7
  label: org                          # who owns it; reports attribute by it
  catalog: { version: v0.8.0 }        # the fleetlint catalog it builds on
  includes: ["fleetlint:recommended"]
rules:
  - use: deps/unused-check            # with the Ruby implementation from rules/
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
  ci/actions-pinned:   { severity: error, min_severity: warning }
exception_policy:
  max_days: 90
  require_approver: true
```

`org/rules/deps/unused-check/ruby.yaml` states only its check; the rest comes from the capability in fleetlint's library:

```yaml
id: deps/unused-check/ruby
kind: outcome
satisfiers:
  - name: our-tool
    expr: workflows().exists(w, steps(w).exists(s, s.run.contains("bin/unused-gems")))
```

`sources.yaml` pins the catalog by the commit that last changed `org/`. A commit cannot name itself, so the pin moves in a commit of its own:

<!-- example: unchecked -->
```yaml
# sources.yaml
version: 1
catalog: { version: v0.8.0 }          # the fleetlint catalog every repository runs
extends: [org]                        # the baseline every repository gets
catalogs:
  org: git+https://git.example.com/platform/standards.git//org/catalog.yaml@<commit>
```

Each repository names the sources file, pinned the same way:

<!-- example: unchecked -->
```yaml
version: 1
sources: git+https://git.example.com/platform/standards.git//sources.yaml@<commit>
```

The organisation's CI template runs the check and insists on the baseline. fleetlint fetches the standards repository with git's own credentials, so the runner needs read access to it (a deploy key, a credential helper):

```yaml
# .github/workflows/fleetlint.yml; GitHub, Gitea and Forgejo Actions
name: fleetlint
on: [push, pull_request]
permissions: { contents: read }
jobs:
  fleetlint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { persist-credentials: false }
      - run: curl --proto '=https' --tlsv1.2 -fsSL https://fleetlint.org/install.sh | sh -s -- v0.11.1
      - run: ~/.local/bin/fleetlint check --require org
```

Every repository now runs `fleetlint:recommended`, the organisation's rule and its Ruby implementation, and `fleetlint fix` writes the organisation's `SECURITY.md`. Nothing loaded after `org` can unlock, lower or except `repo/no-tracked-env`, take `ci/actions-pinned` below warning, or write an exception without an approver and a date at most 90 days ahead. A repository that drops the sources file fails in CI.

## Your own catalog

A catalog is a YAML file in the [format of the presets](writing-rules.md#catalog-format). In the example:

- `label` says who owns it: `org`, `team/mobile`, `security-team`, any name. Reports attribute the catalog's rules, locks, lowered severities and exceptions to it. It does not order anything, and `--require` does not match it. A catalog without one is labelled by the sources-file name it is loaded under, else by its own name.
- `catalog` names the fleetlint catalog version that its presets and its `use:` selections come from. A remote catalog that includes presets or uses the library must state it, and a run on another version fails. The sources file sets that version for every repository.
- `includes` loads other catalogs first. A remote catalog includes presets and pinned references (https, git, `oci://`) only; a sources-file name such as `org` works in `extends`, not here.
- `rules` adds rules of its own ([writing rules](writing-rules.md)) and selects library rules with `use:`, one family or one rule at a time, without taking all of a preset:

```yaml
rules:
  - use: release/*
  - use: slop/focused-tests
```

- `overrides` adjust the included rules and set policy on them (below).
- `exceptions` are the same as a repository's, granted to every repository that extends the catalog, and bound by its own `exception_policy`. `fleet.json` records the catalog that granted one in the exception's `label` and `where`.

```yaml
exceptions:
  - { rule: repo/no-tracked-junk, match: "fixtures/*.log", reason: "parser fixtures across the fleet" }
```

Catalogs apply in the order they are listed: the sources file's `extends` first, then the repository's, and an include always before the catalog that includes it. Policy only tightens, so a catalog binds every catalog after it. A team catalog that must come after the organisation's includes it by its pinned reference; an organisation that must come first everywhere puts its catalogs in the sources file's `extends`. [How rules combine](composition.md) has the full account, and `fleetlint hierarchy` prints the order of a run.

A catalog loaded over https, git or OCI can add and tighten rules, use the built-in fix templates and every function in [the CEL reference](cel-reference.md). It cannot declare rules that execute commands; only a repository's own configuration and catalog files in the repository can.

### Overrides in a catalog

A catalog that builds on another does not restate a rule to change it. Next to `rules:` it lists `overrides:` for the rules its `includes` brought in:

```yaml
apiVersion: fleetlint.org/v1
kind: Catalog
metadata:
  name: acme-baseline
  version: 1.1.0
  engine: 7
  catalog: { version: v0.8.0 }
  includes: ["fleetlint:recommended"]
overrides:
  repo/no-tracked-env:     { locked: true, exceptions: false }
  ci/actions-pinned:       { severity: error, min_severity: warning }
  taskrunner/targets:      { params: { required: [lint, test, check] } }
  deps/vulnerability-scan: { accept: [{ name: acme-scan, expr: 'taskrunner.file != "" && text(taskrunner.file).contains("acme-scan")' }] }
  docs/adr-directory:      { enabled: false, reason: "decisions are kept in the wiki" }
  public/license:          { when: "true" }        # whatever the detected visibility
  docs/architecture:       { tiers: [1, 2] }
  "release/*":             { locked: true }        # a pattern: the whole family
  "*":                     { raise: 1 }            # every included rule one step stricter
```

- A key is a rule id or a pattern over ids: `"*"` is every included rule, `"release/*"` a family. Patterns apply first, exact ids refine them. `raise: 1` lifts whatever matches one severity step (info → warning → error, capped at error). `fleetlint:strict` is written this way: `"*": {raise: 1}` plus `exceptions: false` on the security rules.
- `severity`, `params`, `accept` and `enabled` work as in a repository's `overrides:` block, including the need for a `reason` when a rule is disabled or its severity lowered. Such changes appear in every report with the catalog's label.
- `when` and `tiers` replace the rule's applicability: `when: "true"` makes a conditional rule unconditional (this is how `fleetlint:oss` switches the `public/*` family on), `tiers` widens or narrows the tiers it applies to. A locked rule refuses both.
- The rule keeps the catalog it came from as its source and follows that catalog's later improvements; `explain` and the reports name the catalog that set the policy.
- An override for a rule that no earlier catalog defines is an error, as is one for a rule the same catalog defines: the catalog changes its own rules directly.

### Locks and floors

Three overrides constrain everything loaded after the catalog: later catalogs, the repository, its scopes and nested files. A catalog sets the same fields on a rule it defines itself.

```yaml
overrides:
  repo/no-tracked-env: { locked: true, exceptions: false }     # an absolute rule
  ci/actions-pinned:   { severity: error, min_severity: warning }
```

| Policy | What is loaded later cannot | It can still |
|---|---|---|
| `locked: true` | disable the rule, lower its severity, change `when`, `tiers`, `params` or `accept`, or redefine it | raise the severity; add a reasoned exception unless exceptions are forbidden |
| `min_severity: <severity>` | disable the rule, or set its severity below the floor | lower it to the floor, with a reason; change `when`, `tiers`, `params`, `accept` |
| `exceptions: false` | add an exception for the rule, or disable it | change its severity (lowering needs a reason), `when`, `tiers`, `params`, `accept` |

`exceptions: false` forbids disabling because disabling is the widest exception; reserve it for the few absolute rules. Under `fleetlint:strict` the security rules can therefore be neither excepted nor disabled. Policy only tightens: a rule an earlier catalog locked cannot be unlocked, a floor cannot be lowered, and exceptions that were forbidden cannot be allowed again.

A violation is a configuration error when the configuration loads (exit 2), never a weaker check at run time, and it names the catalog that set the policy:

```text
fleetlint: .fleetlint.yaml: rules.repo/no-tracked-env: rule is locked by acme-baseline@1.0.0 and cannot be disabled
fleetlint: .fleetlint.yaml: rules.ci/actions-pinned: acme-baseline@1.0.0 set a severity floor of warning; off is below every floor
fleetlint: .fleetlint.yaml: exceptions: rule repo/no-tracked-env forbids exceptions (set by acme-baseline@1.0.0)
```

Locks hold only for catalogs that are loaded; [enforcing the baseline](#enforcing-the-baseline) makes sure they are.

### Stacks and per-stack rules

Your catalog uses the stacks of the fleetlint catalog it builds on (`stacks/` at the version in `metadata.catalog`): detection, `repo.stacks` and the dev environment `fleetlint fix` writes come from there, so it never redefines Go or Node. On top of them it can:

- scope its own rules to a stack with `stacks: [go]`; a stack id the base does not define fails the load;
- select a capability with all its implementations (`use: lint/configured`) or adjust one stack (`overrides: {lint/configured/go: ...}`);
- add or replace an implementation of a base capability, as `org/rules/deps/unused-check/ruby.yaml` does in the example. The catalog must ship its `rules/` directory (an `oci://` artifact or a git tree pinned to a full commit SHA), and the implementation applies where the catalog selects it with `use:`, the capability or the implementation's own id.

What it cannot do is define a stack. A stack fleetlint does not ship (Terraform, an in-house language) needs its definition in `stacks/` of the catalog version the run uses: a fork of fleetlint/catalog, pinned with `catalog: {repo: ..., version: ...}`. [Capabilities](writing-rules.md#capabilities-one-requirement-one-implementation-per-stack) and [stacks](writing-rules.md#stacks) explain the formats.

## Publishing and pinning

A repository or a sources file references a catalog in one of these forms; `fleetlint catalog digest catalog.yaml` prints the digest of a file.

| Reference | Pinned by | Ships `rules/` and `templates/` |
|---|---|---|
| `./standards/catalog.yaml`, or a directory of `*.yaml`, inside the repository | the repository's own history | no |
| `https://standards.example.com/catalog.yaml#sha256-<hex>` | the digest | no |
| `git+https://git.example.com/platform/standards.git//org/catalog.yaml@v1.0.0#sha256-<hex>` | a tag and the digest of the catalog file | no, and the run warns when they exist |
| `git+https://git.example.com/platform/standards.git//org/catalog.yaml@<commit>` | a full commit SHA | yes, the directories next to the catalog file |
| `oci://ghcr.io/acme/fleetlint-catalog@sha256:<digest>`, or a tag with signers | the artifact digest, or a verified signature | yes |

- An https catalog is fetched over https only, follows redirects only within the same host, times out after 20 seconds and refuses bodies over 2 MiB. The digest, not the transport, is what makes the content trusted.
- A git catalog is `git+<url>//<path>@<revision>`, with an https or ssh URL. It is fetched with the credentials git already has (credential helper, ssh agent), so private repositories work. The revision is a tag or a full commit SHA, never a branch. A tag can be moved, so it must carry `#sha256-<hex>`, and a moved tag fails the digest check. That digest covers the catalog file only, which is why a tag pin ships neither `rules/` nor `templates/`; the run says so on stderr: `rules/ and templates/ ignored: a git catalog pinned to a tag ships only its catalog file; pin a full commit SHA to ship them`.
- A git fetch times out after two minutes. Files over 2 MiB are refused, and so is a catalog directory with its `templates/` and `rules/` over 16 MiB or 512 files.
- Catalogs are fetched on every run, hooks included. A catalog that cannot be fetched is a configuration error (exit 2). Only the `catalog:` version pin is kept in a cache.
- Catalogs fetched over https, git or OCI are untrusted: they cannot declare command rules, and include only presets and other pinned references. A catalog file in the repository is trusted like the repository's own configuration.

### Catalogs from a registry: `oci://`, signatures, private templates

An organisation that runs a container registry can publish its catalog as an OCI artifact and sign it, so repositories pin a *signer* instead of a digest and a new catalog version needs no change in any repository:

```sh
oras push ghcr.io/acme/fleetlint-catalog:3.2.0 catalog.yaml templates/SECURITY.md templates/pre-commit/head.yaml
cosign sign --new-bundle-format ghcr.io/acme/fleetlint-catalog@sha256:<digest>   # keyless, from the publishing workflow
```

<!-- example: unchecked -->
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
- A `catalogs:` entry is the reference, or `{ref, signers, min_version}`. `signers` on an entry verify that catalog alone and replace the top-level `signers` for it, so a team that publishes from its own repository is trusted for its own catalog and for nothing else. An entry without `signers` keeps the top-level ones, which also verify the `catalog:` pin. `signers` are allowed only on an `oci://` reference; on any other the sources file is refused.
- `min_version` is a floor on the loaded catalog's `metadata.version` (a semantic version, with or without a leading `v`): a catalog below it fails the run, naming the alias, the loaded version and the floor. A tag such as `:3` follows the publisher, so the floor is how every repository notices the tag being moved back to an older release. With `min_version`, a catalog whose `metadata.version` is not a semantic version fails the run, since the floor cannot be checked.
- A signer is an OIDC `issuer` plus the certificate `subject`, exact or as `subject_regex`. For GitHub Actions the subject is the workflow reference (`https://github.com/<owner>/<repo>/.github/workflows/<file>@refs/tags/<tag>`); for a person signing with `cosign sign` it is their e-mail with `issuer: https://accounts.google.com` or another identity provider. Verification uses the sigstore public-good instance: the certificate chain, the transparency-log entry or a signed timestamp, and the certificate's signed certificate timestamp. The bundle must be attached to the artifact in the sigstore bundle format (`cosign sign --new-bundle-format`, cosign 2.5 or later); the older `.sig` tag layout is not read.
- Every layer of the artifact with an `org.opencontainers.image.title` annotation is a file, which is what `oras push <ref> <files...>` produces. Files named `*.yaml` at the root are catalogs, loaded in name order. Files under `rules/` are the catalog's library. Files under `templates/` are **fix templates that travel with the catalog**: `fleetlint fix` takes them before the preset's templates (the lookup order is in [writing rules](writing-rules.md#where-templates-come-from)), so the organisation's `SECURITY.md`, hook fragments or workflow head replace the public ones without a fork of fleetlint. A template is written only from a catalog that was pinned or whose signature was verified, and the fix plan names the catalog each such change comes from (`(template from catalog oci://...)`), since a template can become a hook or a workflow.
- The registry is read with the credentials docker or oras already stored (`docker login`, `oras login`, credential helpers). Registries on exactly `localhost`, `127.0.0.1` or `::1`, on any port, are spoken to over plain http, as in tests; `localhost.example.com` is not. Signature lookup reads at most 32 referrers of an artifact and 8 bundle layers per referrer, and fetching the sigstore trust root stops after two minutes.
- A sources file cannot come from a registry: it is the trust anchor, so it stays a local path, an https URL with a digest or a git reference.
- **Without a registry**, a git tree pinned to a full commit SHA ships `rules/` and `templates/` the same way, from the directories next to the catalog file. That is the example at the top: `org/templates/SECURITY.md` makes `fleetlint fix` write the organisation's security policy.

## Names: the sources file

Repositories should not carry URLs and pins for every catalog. An organisation publishes one **sources file** that names its catalogs:

<!-- example: unchecked -->
```yaml
# sources.yaml
version: 1
catalog: { version: v0.8.0 }         # the fleetlint catalog version every repository runs (or {oci: ghcr.io/fleetlint/catalog:v0.8.0})
extends: [fleetlint:recommended, org, compliance/pci] # the baseline every repository gets, in this order, before its own extends
catalogs:
  org: git+https://git.example.com/platform/standards.git//org/catalog.yaml@<commit>
  compliance/pci: oci://ghcr.io/acme/compliance-catalog@sha256:<digest>
  bu/payments: git+https://git.example.com/payments/standards.git//catalog.yaml@v1.4.0#sha256-<hex>
  team/platform: git+https://git.example.com/platform/standards.git//teams/platform/catalog.yaml@<commit>
  team/mobile: https://standards.example.com/teams/mobile.yaml#sha256-<hex>
```

A repository names it with `sources:` and adds only what is its own, such as `extends: [team/platform]`.

- Names are lowercase words joined by `/` (`org`, `team/mobile`, `compliance/pci`, `bu/payments`): any hierarchy the organisation has. Targets are presets, https catalogs with a digest, git or `oci://` catalogs. A sources file given as a local path may also name local paths, resolved relative to itself; a remote one may not. A catalog loaded under a name takes that name as its label unless it declares one.
- `catalog` is the one version of the fleetlint catalog for every repository; a repository may repeat it, not change it.
- `extends` is the baseline: the repository's own `extends` adds to it and cannot leave anything out. Only the catalogs that are extended are fetched.
- The sources file itself is a local path, an https URL with a digest or a git reference, pinned the same way as a catalog. Rotating a catalog version is then one change to the sources file and one pin update per repository.
- The order is what is written: the sources file's `extends`, then the repository's `extends`, then its own file, with every include before the catalog that includes it. A team catalog that includes the organisation's can never come before it. Nothing is sorted by name or label.
- Every rule carries the label of the catalog that brought it in (`preset`, `repo`, `org`, `team/mobile`, ...), the catalog that defined its text (`source`, the library for selected rules) and the catalog that selected it (`selected_by`). `explain` prints them, JSON has them on the rule, SARIF in the rule properties. The JSON `catalogs` list, `fleetlint hierarchy` and the fleet report's Catalogs section have every catalog of the run in order with its label, name, version and pin.
- Locks and severity floors hold across catalogs: a later catalog cannot redefine a locked rule or set a severity below an earlier `min_severity`, and the floor still binds the repository after a team redefines the rule. Every lowering, by whichever catalog, is recorded: under `weakened` in JSON, and under *Lowered severities* in the fleet report with the label.

## Enforcing the baseline

The sources file's `extends` reaches every repository that names the file, but a repository can drop `sources:` or a catalog from `extends`. Enforcement belongs where the check runs: the organisation's CI template and its fleet runs pass `--require`, as in the example.

- `--require org` names a catalog by its sources-file name or its `metadata.name`, by its reference, or as `ref#sha256-<digest>` for the exact content; the label does not count. A name counts only for a catalog fetched by digest, commit or signature: a file in the repository that calls itself `org` does not satisfy it.
- A repository whose configuration lacks a required catalog fails with exit 2 before any rule runs: `required catalog org is not part of the effective configuration (add it to extends)`. In fleet mode it becomes an error row.
- The flag is global, so `fix`, `explain` and `baseline` refuse under a weaker configuration too.
- fleetlint's GitHub Action and GitLab component have no input for it; a CI template that requires a catalog runs the binary, as the example does.

### Exception policy

What an exception must say is set once, for every repository that extends the catalog:

```yaml
exception_policy:
  require_until: true      # every exception has an expiry date
  max_days: 90             # until is at most 90 days after the run (implies require_until)
  require_approver: true   # every exception names approved_by
```

- The policy binds the exceptions of the catalog that sets it and of everything loaded after it: later catalogs, the repository's `.fleetlint.yaml`, its scopes and nested files.
- Policies of several catalogs add up, so a team catalog can tighten the organisation's (a smaller `max_days`) but never loosen it.
- An exception that breaks the policy is a configuration error (exit 2) that names the exception's rule and the catalogs whose policy it breaks: `exceptions: rule repo/readme-present: approved_by is required (exception policy of …)`.
- `max_days` is counted from the day of the run, so an exception written for 90 days stays valid until it expires. An expired exception is no error; its findings simply count again.
- The policy checks what an exception says, not who wrote it: `approved_by` is a name fleetlint records without verifying, and the approval itself is the review of the change to `.fleetlint.yaml`.

## The fleet view

`fleetlint fleet` checks every repository and writes one report: compliance per repository and per team, the repository-by-rule matrix, and three tables of what the fleet weakened. *Disabled rules* and *Lowered severities* name the label and the file of the catalog or configuration that made each change; *Exceptions* lists each with its team, reason, approver and deadline. Run it with `--require org` so a repository without the baseline shows up as an error. See [fleet mode](fleet.md).
