# Task-runner contract. `make check` is the definition of green.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DEFAULT_GOAL := check-fast

# Hugo, Node, Python, Go and gitleaks are pinned in mise.toml (`mise install`).
# The site documents this release of fleetlint; `make gen` needs that version on the PATH.
# It is a branch until fleetlint has its first tag: set it to the tag then.
FLEETLINT_VERSION ?= b4d31fca4496b673a33679a13d0c77ac45a9a06b   # the commit the generated pages come from; a tag after the next release
# renovate: datasource=npm depName=pagefind
PAGEFIND_VERSION  ?= 1.5.2

.PHONY: help tools gen fmt lint test cover audit build search serve check-fast check demo search-index

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*##' '{printf "  %-12s %s\n", $$1, $$2}'

tools: ## install fleetlint; everything else comes from mise.toml
	go install github.com/fleetlint/fleetlint/cmd/fleetlint@$(FLEETLINT_VERSION)

gen: ## regenerate the rule pages and the CEL reference from the catalog built into fleetlint
	fleetlint docs --out content --index-file _index.md

fmt: ## nothing to format: Markdown is written by hand, the generated pages by fleetlint
	@true

lint: ## the generated pages are current, and the site builds without warnings
	fleetlint docs --out content --index-file _index.md --check
	hugo --quiet --panicOnWarning --destination public

test: lint ## every link and anchor in the built site resolves
	python3 scripts/check-links.py public

cover: test ## the link check covers every page; there is no code to measure

audit: ## secrets
	gitleaks git --no-banner --redact .

build: ## the site, minified, into public/
	hugo --quiet --minify --destination public

search: build search-index ## build the site and add the search index (Pagefind) to public/

search-index: ## index whatever is in public/ (the demo report has no data-pagefind-body and stays out)
	npx --yes pagefind@$(PAGEFIND_VERSION) --site public

demo: ## the fleet report over the fleetlint repositories, into public/demo/report/ (needs network; the site workflow runs it)
	fleetlint fleet --repos demo/fleet.yaml --out public/demo/report --update

serve: ## preview at http://localhost:1313
	hugo server

check-fast: lint ## before every commit

check: lint test cover audit build ## definition of green
	fleetlint check --fail-on error
