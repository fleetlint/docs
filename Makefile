# Task-runner contract. `make check` is the definition of green.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DEFAULT_GOAL := check-fast

# Hugo, Node, Python, Go and gitleaks are pinned in mise.toml (`mise install`).
# The site documents this release of fleetlint; `make gen` needs that version on the PATH.
# renovate: datasource=github-releases depName=fleetlint/fleetlint
FLEETLINT_VERSION ?= v0.6.1   # the release the generated pages come from
# renovate: datasource=npm depName=pagefind
PAGEFIND_VERSION  ?= 1.5.2
SITE_URL          ?= https://fleetlint.org
# content/ is next, the docs of the coming release; versions/vX.Y/ holds each released minor.
# `make cut` releases next as the minor of FLEETLINT_VERSION: v0.5.0 -> versions/v0.5/.
DOCS_VERSION      := $(shell echo '$(strip $(FLEETLINT_VERSION))' | cut -d. -f1,2)

.PHONY: help tools gen fmt lint test cover audit build search serve check-fast check demo search-index versions cut

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*##' '{printf "  %-12s %s\n", $$1, $$2}'

tools: ## install fleetlint; everything else comes from mise.toml
	go install github.com/fleetlint/fleetlint/cmd/fleetlint@$(FLEETLINT_VERSION)

gen: ## regenerate next's rule pages and CEL reference from the catalog built into fleetlint
	fleetlint docs --out content --index-file _index.md

fmt: ## nothing to format: Markdown is written by hand, the generated pages by fleetlint
	@true

lint: ## the generated pages and the version config are current, and every version builds without warnings
	fleetlint docs --out content --index-file _index.md --check
	python3 scripts/versions.py check
	rm -rf public
	hugo --quiet --panicOnWarning --environment development --destination public

test: lint ## every link and anchor in the built site resolves, in every version
	python3 scripts/check-links.py public

cover: test ## the link check covers every page; there is no code to measure

audit: ## secrets
	gitleaks git --no-banner --redact .

build: ## the deployed site, minified, into public/: the released versions, without next
	rm -rf public
	hugo --quiet --minify --destination public

search: build search-index ## build the site and add the search index (Pagefind) to public/

search-index: ## index whatever is in public/ (the demo report has no data-pagefind-body and stays out)
	npx --yes pagefind@$(PAGEFIND_VERSION) --site public

versions: ## regenerate config/_default/hugo.toml from the directories in versions/
	python3 scripts/versions.py config

cut: lint ## release next as $(DOCS_VERSION): copy content/ to versions/$(DOCS_VERSION)/ and make it the latest
	python3 scripts/versions.py cut $(DOCS_VERSION)

demo: ## the fleet report over the fleetlint repositories, into public/demo/report/ (needs network; the deploy workflow runs it)
	fleetlint fleet --repos demo/fleet.yaml --out public/demo/report --update

serve: ## preview at http://localhost:1313, with next at /next/
	hugo server

check-fast: lint ## before every commit

check: lint test cover audit build ## definition of green
	fleetlint check --fail-on error
