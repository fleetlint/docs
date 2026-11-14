---
title: "Fleet mode"
weight: 80
description: "Check many repositories and get one report: compliance, the rule matrix, teams, and every disabled rule, lowered severity and exception."
---

# Fleet mode

`fleetlint fleet` checks many repositories and writes one report.

```sh
fleetlint fleet ~/src/api ~/src/web                 # local paths
fleetlint fleet --repos fleet.yaml --out reports    # a fleet file
fleetlint fleet --repos fleet.yaml --update --deep --deep-clones  # pull clones, run make check in each, clones included
fleetlint fleet --from github:acme                  # every repository of an owner
fleetlint fleet --from gitlab:gitlab.com/acme/platform  # a GitLab group with its subgroups
fleetlint fleet --discover ~/src                    # every repository below a directory
fleetlint fleet --discover ~/src --fix              # what fix --apply would change in each
```

## Fleet file

```yaml
# fleet.yaml
version: 1
cache: ~/.cache/fleetlint/repos      # where url entries are cloned; optional
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

Each entry has exactly one of `path` or `url`:

- A `url` is `https://`, `ssh://` or `git@` (or an absolute local path); one with credentials in it (`https://user:token@…`) is refused, since it would end up in every report. URL entries are cloned with git's own credentials, keeping the last 50 commits, and reused; `--update` pulls before checking.
- Clones go to `--cache`, else the fleet file's `cache:`, else the user cache directory (`~/.cache/fleetlint/repos` on Linux). A clone lives at `<cache>/<host>/<owner>/<repo>-<hash>`, the hash taken from the URL so two URLs never share a directory; clones from before 0.8 at the old flat path are not reused and can be deleted.
- An entry's name is its `name:`, else the last part of its URL or path. Characters other than letters, digits, `.`, `_` and `-` become `-` (`team/api` is `team-api`), and the report's files carry the name. A name may appear once across all fleet files.

An entry may carry `team:`, `group:`, `tier:` (1, 2 or 3) and `visibility:` (`public` or `private`). `defaults:` and `groups:` set `team`, `tier` and `visibility` for many repositories at once, including the ones `--discover` and `--from` add:

- An entry's own value wins over its group's, a group's over its parent group's (`apps/ios` over `apps`), and the parents' over the defaults.
- `include:` takes the repositories of other fleet files. Each is settled with its own file's defaults and groups first, and this file's defaults fill what that left open; the included file's groups are known here unless this file defines them.
- What a repository pins in its own `.fleetlint.yaml` wins over all of them: the fleet file fills gaps and does not overrule a repository.
- An entry whose `path` is a repository `--discover` also finds adjusts that repository (and takes its group) instead of adding it twice.

A repository's team is the entry's own `team:`, else the owner its own files name (Backstage `catalog-info.yaml`, else the CODEOWNERS default owner, see [configuration](configuration.md#facts)), else its group's or the defaults' `team`. `fleet.json` names the source per repository in `team_from`: `fleet file`, `catalog-info.yaml`, `.github/CODEOWNERS`, ….

A tier from the fleet file is named `fleet file` in the report and `fleet` in `fleet.csv` (`tier_source`) and `fleet.json` (`facts.sources.tier`). Those repositories leave *Facts to pin*.

Each repository is checked with its own `.fleetlint.yaml` (or the defaults), so the fleet view reflects what each repository actually enforces.

## Discovering repositories in a directory

```sh
fleetlint fleet --discover ~/src
fleetlint fleet --discover ~/src --exclude 'vendor-clones/**' --exclude '*/third_party/*'
```

`--discover` walks the directory up to four levels down and takes every git repository it finds; it does not descend into a repository, so submodules and nested clones stay out.

- A repository is named after its directory, or after its path when two directories share a name (`suite-docs`, `other-docs`).
- Its group is the directories it sits under, joined by `/`: `~/src/cairn/cairn-core` is in group `cairn`, `~/src/incyde/tooling/vuln-ui` in `incyde/tooling`, which rolls up into `incyde`.
- The directory itself counts as a repository only when there is none below it.
- Directories that look like a project (a manifest such as `go.mod` or `package.json`, or source files) but are in no repository of their own are listed under *Not under version control*: fleetlint cannot check them.
- `--exclude` takes globs relative to the directory.

## Discovering repositories on a forge

```sh
fleetlint fleet --from github:acme                      # an organisation or a user
fleetlint fleet --from gitea:git.example.com/platform   # a Gitea or Forgejo instance
fleetlint fleet --repos fleet.yaml --from github:acme   # in addition to a fleet file
```

`--from` asks the forge's API for the owner's repositories and adds each as a `url` entry with the visibility the forge reports. Archived repositories and forks are skipped. A GitLab source (`gitlab:<host>/<group>`, the group may name subgroups) lists the group's projects with those of its subgroups, named by their path below the group (`tools/api` becomes `tools-api`), or a user's projects when no group has the name; `internal` projects count as private. Without a token only public repositories are listed. A clone URL the forge returns must be `https://`, `ssh://` or `git@` on the forge's own host (for GitHub Enterprise also the host of `GITHUB_API_URL`); any other URL, a local path among them, fails the run naming the repository.

## Forges and tokens

Fleet mode talks to a forge's API for three things: listing a `--from` source, asking whether a repository is public when neither the fleet file nor the repository says, and opening pull requests with `--fix --apply --pr`. The pull request is the only write; everything else only reads.

The forge of a repository comes from its `origin` remote:

| Remote host | Forge |
|---|---|
| `github.com`, or a host with `github` in its name | `github` |
| a host with `gitlab` in its name | `gitlab` |
| any other host (Forgejo, Codeberg, Gitea) | `gitea` |
| no remote | `unknown` |

`facts: {forge: …}` in the repository's `.fleetlint.yaml` pins it, for example for GitLab on a host without `gitlab` in its name.

| Forge | Token | Contacted |
|---|---|---|
| GitHub | `GITHUB_TOKEN`, else `GH_TOKEN` | github.com always; GitHub Enterprise Server through `GITHUB_API_URL` or `--forge github:<host>` |
| Gitea, Forgejo | `GITEA_TOKEN`; in that host's own Actions run also `GITHUB_TOKEN` | only a host named in `GITEA_HOST`, in a `--from` source or with `--forge` |
| GitLab | `GITLAB_TOKEN` | gitlab.com always; another host only when named in `GITLAB_HOST`, in a `--from` source or with `--forge` |

- A token goes to its own forge only. `GITEA_HOST` and `GITLAB_HOST` take several hosts, comma-separated. In CI, the instance running the job counts as named (Gitea and Forgejo Actions, GitLab CI).
- A host nobody named is not contacted; its repositories' visibility stays unknown, with a note at the end of the run that says how to name it. A forge that does not show a repository without a token leaves its visibility unknown too, with one note per forge.
- `--forge` and `--token` (or `FLEETLINT_FORGE` and `FLEETLINT_TOKEN`) name one more forge and its token. That token then goes to that forge and the `--from` hosts only, for the listing, the clones and the pull requests. A fleet that spans several forges uses the per-forge variables instead.
- Clones of `--from` repositories send the source's token as an `Authorization` header scoped to the forge's host (the way `actions/checkout` does), so private repositories clone over https without further git setup. Repositories from a fleet file use git's own credentials.
- The hosts of the `--from` sources count as named for the pull requests too.
- With the GitHub CLI logged in, `GITHUB_TOKEN=$(gh auth token) fleetlint fleet ...` is enough.

## Fixing across the fleet

```sh
fleetlint fleet --discover ~/src --fix                                       # plan only
fleetlint fleet --discover ~/src --fix --apply --rule hooks/config-present   # one rule, everywhere
fleetlint fleet --discover ~/src --fix --apply                               # every mechanical fix
fleetlint fleet --from github:acme --fix --apply --pr                        # a pull request per repository
```

- `--fix` plans what `fleetlint fix` would change in every local repository and lists it per repository. The dry run writes no `history/` entry.
- `--apply` writes the changes, and the report then shows the state after them. Existing files are never overwritten, nothing is committed, and cloned `url` entries are left alone: review and commit in each repository.
- `--rule` limits both to one rule (repeatable), which suits working down the top levers.
- A repository with uncommitted changes to tracked files is left unfixed and the report notes it, unless `--allow-dirty` is given. Untracked files do not count, a repository without git is never dirty, and one whose state git cannot report is left alone too. `fleetlint fix --apply` on its own refuses such a tree the same way.
- With `--pr` no working tree is written: each repository's fixes become a pull request from `fleetlint/fixes`, as `fleetlint fix --apply --pr` makes it, for clones too (pushed with the token they were cloned with). The report notes each pull request, or why there is none. See [forges and tokens](#forges-and-tokens) for the tokens.

## Running

- `--jobs N` (default 4) checks that many repositories at once. A crash while checking one is reported as that repository's error, and the others are still checked.
- `--deep` runs the repositories' command rules and `make check`, with an environment without credentials (tokens, cloud keys, CI secrets). Cloned repositories (`url` entries, `--from`) are checked without that code even then, since it would execute code from repositories you may not control; `--deep-clones` runs it there too, and the report notes which repositories were skipped.
- `--require <catalog>` holds every repository to a catalog, as in [organisations](organisations.md#enforcing-the-baseline); a repository without it becomes an error row.
- `--keep-history N` keeps the latest N runs in `history/`.

## Exit codes

| Code | When |
|---|---|
| 0 | the report was written, whatever it contains, repositories that could not be checked included |
| 1 | with `--fail`: a repository has an error-severity finding or a rule error, or could not be checked. For a scheduled job. |
| 2 | the fleet file, the flags or a `--from` source are invalid: an unknown key, `--apply` without `--fix`, an owner the forge does not know |
| 3 | anything else, such as an output directory that cannot be written |

## Output directory

The directory is a complete static site: pointing GitHub or Gitea Pages at it publishes the report. The [demo](demo.md) at fleetlint.org/demo/report/ is exactly that: the deploy workflow of the docs repository runs `fleetlint fleet` over `demo/fleet.yaml` on every build and nightly.

| File | Contents |
|---|---|
| `fleet.html` | one page with the sections below. One inline script sorts the tables and filters the matrix; without it the page reads the same, and it works from a file share. |
| `index.html` | the same page as `fleet.html`, so the directory can be served as a site |
| `fleet.md` | the same sections as Markdown, for a wiki or an issue |
| `fleet.json` | machine-readable: every result, all facts, git state, team and group summaries (below) |
| `fleet.csv` | one row per repository (team, group, visibility, tier and its source, compliance, counts, fixable findings, rule errors, branch, commit, uncommitted changes, last commit, stale), for a spreadsheet or existing reporting |
| `actions/<name>.md` | the ordered task list for that repository, ready to hand to a coding agent; it starts with `fleetlint fix --apply` when part of the work is mechanical |
| `actions/<name>.html` | the same list for a browser |
| `sarif/<name>.sarif` | one SARIF file per checked repository, the same output as `fleetlint check --format sarif`, with one run per scope keyed `fleetlint/<name>/` and `fleetlint/<name>/<scope>/`, for uploading to code scanning per repository |
| `history/<timestamp>.json` | a compact copy of `fleet.json` per run (none for a `--fix` dry run). The next run into the same directory compares with the latest one, also across format versions. Keep the directory in git or a bucket to see drift over time. |

`fleet.json` carries `version: 7`:

- Each rule definition is stored once under `definitions`; a result names its rule by id in `rule`, and in `definition` when the repository adjusted it. Field names are snake_case.
- Each repository has its `team_from`, the catalog version it pinned in `catalog`, and its `catalogs` in the order they applied, with label, name, version and the digest or artifact that pins each.
- A rule's `refs` are objects with `url`, `kind` and `section`.
- A published artifact in `facts.artifacts` has a `kind`, a `name` where the catalog names instances, and its `workflows`.
- A finding has its `anchor` and `artifact` where it has them.
- A repository's `notes` say what the run left out for it. Its `disabled`, `weakened` and `exceptions` carry the `label` and `where` of the catalog or file that made each.

Compliance is the share of applicable rules that pass or are excepted. A rule that could not be evaluated (a file fleetlint cannot parse, say) is left out of it and reported as a rule error instead. A repository that could not be checked (missing path, clone failure, invalid config) is listed with its error and never counted as compliant.

## Sections

| Section | What it answers |
|---|---|
| Since the last run | compared with the latest earlier run in `history/`: rules failing at error severity before and after, and per repository the rules that newly fail and the ones that were fixed. Absent on the first run |
| Top levers | which rules hold back most repositories: ranked by the repositories they fail at error severity, then by all failures, with how many `fix --apply` repairs and how much of the errors and of all failures fixing the first ones closes |
| Repositories | most urgent first (could not be checked, then errors, rule errors, warnings, lowest compliance); tier (marked when inferred or default), visibility, compliance, fixable findings, rule errors, the branch and commit that were checked with the number of uncommitted changes, untracked files included (rules read the working tree), and the last commit, marked stale after a year; a Notes column when the run left something out for a repository (code not executed in a clone, fixes not applied to a dirty checkout) or its configuration lists fewer stacks or artifacts than detection finds |
| Groups, Teams | totals per group and per team |
| Rule errors | every rule that could not be evaluated, with the error |
| Rules | per rule, how many repositories pass, fail, can be fixed mechanically, errored, are excepted, do not apply, or do not select it. Rules that apply nowhere are named in one line instead |
| Matrix | rules down, repositories across. `*` marks a failure `fix --apply` repairs; `-` is not applicable, `·` not selected by the repository's configuration |
| Facts to pin | repositories whose tier was inferred or defaulted, or whose visibility is unknown, with the `facts:` line to add. Both decide which rules apply and how severe they are |
| Not under version control | project directories `--discover` found outside any repository |
| Disabled rules | every disabled rule per repository, with the label and file (`Where`) of the catalog or configuration that disabled it, and the reason |
| Lowered severities | every lowered severity, with the same columns |
| Exceptions | every exception per repository, with its team, reason, approver and deadline. Expired ones are marked, and those due within 30 days show the days left |
| Catalogs | every catalog a repository applied, with its label, origin, pin and the repositories using it; the same list `fleetlint hierarchy` prints in one repository |

## Teams and groups

When entries carry `team:` (or `group:`, or come from `--discover`), the report adds a table per team (per group): repositories, how many could not be checked, mean compliance of the checked ones, and the totals of errors, warnings, excepted findings, disabled rules, lowered severities and exceptions that have expired or will within 30 days. A nested group counts for every level above it (`incyde/tooling` and `incyde`). Repositories without a team are grouped as `(none)`. With the Label column of *Disabled rules* and *Lowered severities*, this answers which team weakened what.

## Onboarding many repositories

In each repository, `fleetlint init --pr` writes the configuration, commits it on the branch `fleetlint/onboarding` as you, and opens a pull request with the Markdown report as its description through the forge's API when its token is set, else with `gh`, `tea` or `glab`, as `fix --apply --pr` does. When it cannot open the pull request, it says which part is missing: the branch is pushed and only the pull request is missing (no token and no forge CLI, or it failed), or the push failed, with the command to push it.
