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
fleetlint fleet --discover ~/src --fix              # what fix --apply would change in each
```

## Fleet file

```yaml
version: 1
cache: ~/.cache/fleetlint/repos      # where url entries are cloned (shallow)
include:                             # other fleet files, relative to this one: a team's fleet inside the organisation's
  - teams/platform/fleet.yaml
defaults:                            # for every repository, discovered ones too
  tier: 2
groups:                              # for the repositories of a group; groups nest by path
  experiments: {tier: 3, visibility: private}
  apps: {team: mobile}
  apps/ios: {tier: 1}
repos:
  - path: ../api                       # relative to this file
    team: platform
  - url: https://github.com/example/absorb.git
    name: absorb                       # optional; derived from the URL otherwise
    team: mobile
    group: apps                        # optional; reports summarize per group
```

An entry may also carry `tier:` (1, 2 or 3) and `visibility:` (`public` or `private`). `defaults:` and `groups:` set `team`, `tier` and `visibility` for many repositories at once, including the ones `--discover` and `--from` add: an entry's own value wins over its group's, a group's over its parent group's (`apps/ios` over `apps`), and the parents' over the defaults. `include:` takes the repositories of other fleet files: each is settled with its own file's defaults and groups first, and this file's defaults fill what that left open; the included file's groups are known here unless this file defines them, and a repository name may appear once across all files. What a repository pins in its own `.fleetlint.yaml` wins over all of them, so the fleet file fills gaps and does not overrule a repository. An entry whose `path` is a repository `--discover` also finds adjusts that repository (and takes its group) instead of adding it twice. A tier from the fleet file shows as `fleet file` wherever the tier source is named, and those repositories leave *Facts to pin*.

When neither the fleet file nor the repository says whether it is public, fleet mode asks the forge of the repository's remote, the way `init` does: `GITHUB_TOKEN` (or `GH_TOKEN`) for GitHub, `GITEA_TOKEN` for Gitea. Gitea hosts are asked only when named in `GITEA_HOST` (comma-separated) or as a `--from` source; any other host is not contacted, and its repositories' visibility stays unknown with a note how to name it. A forge that does not show a repository without a token leaves its visibility unknown, with one note per forge at the end of the run. With the GitHub CLI logged in, `GITHUB_TOKEN=$(gh auth token) fleetlint fleet ...` is enough.

Each entry has exactly one of `path` or `url`; a `url` with credentials in it (`https://user:token@…`) is refused, since it would end up in every report. Clones are shallow and reused; `--update` pulls before checking. Each repository is checked with its own `.fleetlint.yaml` (or the defaults), so the fleet view reflects what each repo actually enforces.

## Discovering repositories in a directory

```sh
fleetlint fleet --discover ~/src
fleetlint fleet --discover ~/src --exclude 'vendor-clones/**' --exclude '*/third_party/*'
```

`--discover` walks the directory up to four levels down and takes every git repository it finds; it does not descend into a repository, so submodules and nested clones stay out. A repository is named after its directory, or after its path when two directories share a name (`suite-docs`, `other-docs`), and its group is the directories it sits under, joined by `/` (`~/src/cairn/cairn-core` is in group `cairn`, `~/src/incyde/tooling/vuln-ui` in `incyde/tooling`, which rolls up into `incyde`). The directory itself counts as a repository only when there is none below it. Directories that look like a project (a manifest such as `go.mod` or `package.json`, or source files) but are in no repository of their own are listed under *Not under version control*: fleetlint cannot check them. `--exclude` takes globs relative to the directory.

## Discovering repositories on a forge

```sh
fleetlint fleet --from github:acme                      # an organization or a user
fleetlint fleet --from gitea:git.example.com/platform   # a Gitea or Forgejo instance
fleetlint fleet --repos fleet.yaml --from github:acme   # in addition to a fleet file
```

`--from` asks the forge's REST API for the owner's repositories and adds each as a `url` entry with the visibility the forge reports. Archived repositories and forks are skipped. Without a token only public repositories are listed; `GITHUB_TOKEN` (or `GH_TOKEN`) and `GITEA_TOKEN` are read from the environment and sent to that forge only; a `--from` source names its Gitea host, so it needs no `GITEA_HOST`. `GITHUB_API_URL` selects a GitHub Enterprise Server instance. Clones of discovered repositories send the same token as an `Authorization` header scoped to the forge's host (the way `actions/checkout` does), so private repositories clone over https without further git setup; repositories from a fleet file use git's own credentials. Clones go to `--cache`, or to the user cache directory when none is given. fleetlint only reads: it never writes to the forge.

## Fixing across the fleet

```sh
fleetlint fleet --discover ~/src --fix                                       # plan only
fleetlint fleet --discover ~/src --fix --apply --rule hooks/config-present   # one rule, everywhere
fleetlint fleet --discover ~/src --fix --apply                               # every mechanical fix
```

`--fix` plans what `fleetlint fix` would change in every local repository and lists it per repository; `--apply` writes it, and the report then shows the state after the fixes. `--rule` limits both to one rule (repeatable), which suits working down the top levers. Existing files are never overwritten, nothing is committed, and cloned `url` entries are left alone: review and commit in each repository, or let `fleetlint init --pr` open the pull requests. A repository with uncommitted changes to tracked files is left unfixed and the report notes it, unless `--allow-dirty` is given; untracked files do not count. `fleetlint fix --apply` on its own refuses such a tree the same way.

## Output directory

| File | Contents |
|---|---|
| `fleet.html` | self-contained page with the sections below. One inline script sorts the tables and filters the matrix; without it the page reads the same, and it works from a file share. |
| `fleet.md` | the same sections as Markdown, for a wiki or an issue |
| `fleet.json` | machine-readable: every result, all facts, git state, team and group summaries. Each rule definition is stored once under `definitions`; a result names its rule by id in `rule`, and in `definition` when the repository adjusted it. Field names are snake_case (`version: 3`). |
| `fleet.csv` | one row per repository (team, group, visibility, tier and its source, compliance, counts, fixable findings, rule errors, branch, commit, uncommitted changes, last commit, stale), for a spreadsheet or existing reporting |
| `actions/<repo>.md` | the ordered task list for that repository, ready to hand to a coding agent; it starts with `fleetlint fix --apply` when part of the work is mechanical |
| `sarif/<repository>.sarif` | one SARIF file per checked repository (`/` in the fleet name becomes `--`), the same output as `fleetlint check --format sarif`, with one run per scope keyed `fleetlint/<fleet name>` and `fleetlint/<fleet name>/<scope>`, for uploading to code scanning per repository |
| `history/<timestamp>.json` | a copy of `fleet.json` per run; the next run into the same directory compares with the latest one, also across format versions. Keep the directory in git or a bucket to see drift over time |

`fleet.json` carries `version: 6`: each repository lists its `catalogs` in the order they applied, with label, name, version and the digest or artifact that pins each, a rule's `refs` are objects with `url`, `kind` and `section`, and a published artifact in `facts.artifacts` has a `kind`, a `name` where the catalog names instances, and its `workflows`.

Compliance is the share of applicable rules that pass or are excepted. A rule that could not be evaluated (a file fleetlint cannot parse, say) is left out of it and reported as a rule error instead. A repository that could not be checked (missing path, clone failure, invalid config) is listed with its error and never counted as compliant.

## Sections

| Section | What it answers |
|---|---|
| Since the last run | compared with the latest earlier run in `history/`: rules failing at error severity before and after, and per repository the rules that newly fail and the ones that were fixed. Absent on the first run |
| Top levers | which rules hold back most repositories: ranked by the repositories they fail at error severity, then by all failures, with how many `fix --apply` repairs and how much of the errors and of all failures fixing the first ones closes |
| Repositories | most urgent first (could not be checked, then errors, rule errors, warnings, lowest compliance); tier (marked when inferred or default), visibility, compliance, fixable findings, rule errors, the branch and commit that were checked with the number of uncommitted changes (rules read the working tree), and the last commit, marked stale after a year |
| Groups, Teams | totals per group and per team |
| Rule errors | every rule that could not be evaluated, with the error |
| Rules | per rule, how many repositories pass, fail, can be fixed mechanically, errored, are excepted, do not apply, or do not select it. Rules that apply nowhere are named in one line instead |
| Matrix | rules down, repositories across. `*` marks a failure `fix --apply` repairs; `-` is not applicable, `·` not selected by the repository's configuration |
| Facts to pin | repositories whose tier was inferred or defaulted, or whose visibility is unknown, with the `facts:` line to add. Both decide which rules apply and how severe they are |
| Not under version control | project directories `--discover` found outside any repository |
| Policy notes | disabled rules, lowered severities, exceptions |
| Catalogs | every catalog a repository applied, with its label, origin, pin and the repositories using it; the same list `fleetlint hierarchy` prints in one repository |

## Teams and groups

When entries carry `team:` (or `group:`, or come from `--discover`), the report adds a table per team (per group): repositories, how many could not be checked, mean compliance of the checked ones, and the totals of errors, warnings, excepted findings, disabled rules, lowered severities and exceptions that have expired or will within 30 days. A nested group counts for every level above it (`incyde/tooling` and `incyde`). Repositories without a team are grouped as `(none)`. Together with the label column in the policy notes this answers which team weakened what.

## Policy notes

The report lists every disabled rule, every lowered severity and every exception across the fleet, with the reason each repository gave and the deadline where there is one. Expired exceptions are marked, and those due within 30 days show the days left, each with its team. This is how weakening stays visible: it is allowed, but never silent.

## Exit code

`--fail` makes the command exit 1 when any repository has error-severity findings, a rule error, or could not be checked, for use in a scheduled job. Command rules in the repositories run only when the fleet run is given `--deep`, and `make check` runs with an environment without credentials (tokens, cloud keys, CI secrets). Cloned repositories (`url` entries, `--from`) are checked without their command rules even then, since that would execute code from repositories you may not control; `--deep-clones` runs them there too, and the report notes which repositories were skipped.

## Onboarding many repositories

The output directory is a complete static site: `index.html` duplicates `fleet.html`, and every action list exists as both `.md` (for an agent) and `.html` (for a browser), so pointing GitHub or Gitea Pages at the directory publishes the report. The [demo](demo.md) at fleetlint.org/demo/report/ is exactly that: the deploy workflow of the docs repository runs `fleetlint fleet` over `demo/fleet.yaml` on every build and nightly.

In each repository, `fleetlint init --pr` writes the configuration, commits it on the branch `fleetlint/onboarding` as you, and opens a pull request with the Markdown report as its description using `gh` (GitHub) or `tea` (Gitea). When it cannot open the pull request, it says which part is missing: the branch is pushed and only the pull request is missing (no `gh` or `tea`, or they failed), or the push failed, with the command to push it.
