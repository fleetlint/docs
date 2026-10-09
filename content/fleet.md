---
title: "Fleet mode"
weight: 80
description: "Check many repositories and get one report: compliance, the rule matrix, teams and policy notes."
---

# Fleet mode

`fleetlint fleet` checks many repositories and writes one report.

```sh
fleetlint fleet ~/src/api ~/src/web                 # local paths
fleetlint fleet --repos fleet.yaml --out reports    # a fleet file
fleetlint fleet --repos fleet.yaml --update --deep  # pull clones, run make check in each
fleetlint fleet --from github:acme                  # every repository of an owner
fleetlint fleet --discover ~/src                    # every repository below a directory
```

## Fleet file

```yaml
version: 1
cache: ~/.cache/fleetlint/repos      # where url entries are cloned (shallow)
repos:
  - path: ../api                       # relative to this file
    team: platform
  - url: https://github.com/example/absorb.git
    name: absorb                       # optional; derived from the URL otherwise
    team: mobile
    group: apps                        # optional; reports summarize per group
```

An entry may also carry `visibility: public` or `private`: what the forge says about the repository, used when the repository does not say itself (through `facts.visibility` or the `agent.public` git setting).

Each entry has exactly one of `path` or `url`. Clones are shallow and reused; `--update` pulls before checking. Each repository is checked with its own `.fleetlint.yaml` (or the defaults), so the fleet view reflects what each repo actually enforces.

## Discovering repositories in a directory

```sh
fleetlint fleet --discover ~/src
fleetlint fleet --discover ~/src --exclude 'vendor-clones/**' --exclude '*/third_party/*'
```

`--discover` walks the directory up to four levels down and takes every git repository it finds; it does not descend into a repository, so submodules and nested clones stay out. A repository is named after its directory, or after its path when two directories share a name (`suite-docs`, `other-docs`), and its group is the top-level directory it sits under (`~/src/cairn/cairn-core` is in group `cairn`). The directory itself counts as a repository only when there is none below it. Directories that look like a project (a manifest such as `go.mod` or `package.json`, or source files) but are in no repository of their own are listed under *Not under version control*: fleetlint cannot check them. `--exclude` takes globs relative to the directory.

## Discovering repositories on a forge

```sh
fleetlint fleet --from github:acme                      # an organization or a user
fleetlint fleet --from gitea:git.example.com/platform   # a Gitea or Forgejo instance
fleetlint fleet --repos fleet.yaml --from github:acme   # in addition to a fleet file
```

`--from` asks the forge's REST API for the owner's repositories and adds each as a `url` entry with the visibility the forge reports. Archived repositories and forks are skipped. Without a token only public repositories are listed; `GITHUB_TOKEN` (or `GH_TOKEN`) and `GITEA_TOKEN` are read from the environment and sent to that forge only. `GITHUB_API_URL` selects a GitHub Enterprise Server instance. Clones of discovered repositories send the same token as an `Authorization` header scoped to the forge's host (the way `actions/checkout` does), so private repositories clone over https without further git setup; repositories from a fleet file use git's own credentials. Clones go to `--cache`, or to the user cache directory when none is given. fleetlint only reads: it never writes to the forge.

## Output directory

| File | Contents |
|---|---|
| `fleet.html` | self-contained page with the sections below. One inline script sorts the tables and filters the matrix; without it the page reads the same, and it works from a file share. |
| `fleet.md` | the same sections as Markdown, for a wiki or an issue |
| `fleet.json` | machine-readable: every result, all facts, git state, team and group summaries. Each rule definition is stored once under `definitions`; a result names its rule by id in `rule`, and in `definition` when the repository adjusted it (`version: 2`). |
| `fleet.csv` | one row per repository (team, group, visibility, tier and its source, compliance, counts, fixable findings, rule errors, branch, commit, uncommitted changes, last commit, stale), for a spreadsheet or existing reporting |
| `actions/<repo>.md` | the ordered task list for that repository, ready to hand to a coding agent; it starts with `fleetlint fix --apply` when part of the work is mechanical |
| `history/<timestamp>.json` | a copy of `fleet.json` per run; keep the directory in git or a bucket to see drift over time |

Compliance is the share of applicable rules that pass or are excepted. A rule that could not be evaluated (a file fleetlint cannot parse, say) is left out of it and reported as a rule error instead. A repository that could not be checked (missing path, clone failure, invalid config) is listed with its error and never counted as compliant.

## Sections

| Section | What it answers |
|---|---|
| Top levers | which rules hold back most repositories: ranked by the repositories they fail at error severity, then by all failures, with how many `fix --apply` repairs and how much of the errors and of all failures fixing the first ones closes |
| Repositories | most urgent first (could not be checked, then errors, rule errors, warnings, lowest compliance); tier (marked when inferred or default), visibility, compliance, fixable findings, rule errors, the branch and commit that were checked with the number of uncommitted changes (rules read the working tree), and the last commit, marked stale after a year |
| Groups, Teams | totals per group and per team |
| Rule errors | every rule that could not be evaluated, with the error |
| Rules | per rule, how many repositories pass, fail, can be fixed mechanically, errored, are excepted, do not apply, or do not select it. Rules that apply nowhere are named in one line instead |
| Matrix | rules down, repositories across. `*` marks a failure `fix --apply` repairs; `-` is not applicable, `·` not selected by the repository's configuration |
| Facts to pin | repositories whose tier was inferred or defaulted, or whose visibility is unknown, with the `facts:` line to add. Both decide which rules apply and how severe they are |
| Not under version control | project directories `--discover` found outside any repository |
| Policy notes | disabled rules, lowered severities, exceptions |

## Teams and groups

When entries carry `team:` (or `group:`, or come from `--discover`), the report adds a table per team (per group): repositories, how many could not be checked, mean compliance of the checked ones, and the totals of errors, warnings, excepted findings, disabled rules, lowered severities and exceptions that have expired or will within 30 days. Repositories without a team are grouped as `(none)`. Together with the layer column in the policy notes this answers which team weakened what.

## Policy notes

The report lists every disabled rule, every lowered severity and every exception across the fleet, with the reason each repository gave and the deadline where there is one. Expired exceptions are marked, and those due within 30 days show the days left, each with its team. This is how weakening stays visible: it is allowed, but never silent.

## Exit code

`--fail` makes the command exit 1 when any repository has error-severity findings, a rule error, or could not be checked, for use in a scheduled job. Command rules in the repositories run only when the fleet run is given `--deep`.

## Onboarding many repositories

The output directory is a complete static site: `index.html` duplicates `fleet.html`, and every action list exists as both `.md` (for an agent) and `.html` (for a browser), so pointing GitHub or Gitea Pages at the directory publishes the report. `deploy/demo/` holds the fleet file and workflow behind demo.fleetlint.org.

In each repository, `fleetlint init --pr` writes the configuration, commits it on the branch `fleetlint/onboarding` as you, and opens a pull request with the Markdown report as its description using `gh` (GitHub) or `tea` (Gitea). Without either, the branch and commit remain and the command says so.
