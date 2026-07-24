# moul/gno-contracts — see `make help`.
#
# Requires GNOROOT to point at a gnolang/gno checkout (provides the gno binary's
# stdlibs). External gno.land deps are VENDORED (see `make deps`) and are the
# single source of truth; local gno.land/{p,r}/moul/* packages resolve via
# gnowork.toml.
#
# Dependency resolution: `lint`/`test`/`check` run against a stdlib-only view of
# GNOROOT (an ephemeral tree that symlinks the toolchain but has an EMPTY
# examples/), so gno.land/* deps resolve from committed vendor/ — NOT from
# whatever the GNOROOT checkout happens to have in examples/. This makes builds
# reproducible and independent of monorepo drift. Only `deps` (vendoring) reads
# the real GNOROOT/examples, to source dependency code.
#
# The maintenance CLI is a `go tool` (declared in go.mod), invoked as
# `go tool gnocontracts <cmd>` — no binary is ever built into the tree.

GNO  ?= gno
TOOL ?= go tool gnocontracts

# Ephemeral stdlib-only view of the toolchain (empty examples/ → vendor wins).
VIEW := $(CURDIR)/.gnoroot-view


.DEFAULT_GOAL := help
.PHONY: help deps test lint fmt gen manifest readme readmes check sync publish status report graph view clean

help: ## show this help
	@awk 'BEGIN{FS=":.*?## "} /^[a-zA-Z_-]+:.*?## /{printf "  %-10s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

view: ## (re)build the stdlib-only GNOROOT view used by lint/test
	@test -n "$(GNOROOT)" || { echo "GNOROOT must point at a gnolang/gno checkout"; exit 1; }
	@rm -rf "$(VIEW)" && mkdir -p "$(VIEW)/examples"
	@for e in $(abspath $(GNOROOT))/*; do \
		b=$$(basename "$$e"); \
		[ "$$b" = examples ] || ln -sfn "$$e" "$(VIEW)/$$b"; \
	done

deps: ## vendor external gno.land dependencies into vendor/ (reads real GNOROOT/examples)
	$(TOOL) vendor

test: view ## gno test every contract (deps resolved from committed vendor/)
	@set -e; for d in $(PKG_DIRS); do echo "== test $$d =="; GNOROOT="$(VIEW)" $(GNO) test ./$$d; done

lint: view ## gno lint every contract (deps resolved from committed vendor/)
	@set -e; for d in $(PKG_DIRS); do echo "== lint $$d =="; GNOROOT="$(VIEW)" $(GNO) lint ./$$d; done

fmt: ## gno fmt every contract in place
	@set -e; for d in $(PKG_DIRS); do $(GNO) fmt -w ./$$d || true; done

manifest: ## refresh contracts.json from the contract trees
	$(TOOL) manifest

readme: ## regenerate the README contracts table
	$(TOOL) readme

readmes: ## ensure every package has a README (repo link + disclaimer)
	$(TOOL) readmes

gen: manifest readme readmes ## manifest + README table + per-package READMEs

check: ## fail if contracts.json / README table are stale (CI guard)
	$(TOOL) check

sync: ## report drift vs the gnolang/gno monorepo (needs GNOROOT)
	$(TOOL) sync

publish: ## dependency-ordered publish plan; NET=<net> CHECK=1 to query chain
	$(TOOL) publish $(if $(NET),-net $(NET),) $(if $(CHECK),-check,)

status: ## refresh on-chain upload status (all networks) + README; needs gnokey
	$(TOOL) status $(if $(NET),-net $(NET),)

report: ## analyze the PR diff (BASE=origin/main) into a Markdown report
	$(TOOL) report $(if $(BASE),-base $(BASE),)

graph: ## generate per-package + global dependency graphs into _assets/ (needs graphviz for svg/png)
	$(TOOL) graph

clean: ## remove build artifacts and the GNOROOT view
	rm -rf bin "$(VIEW)"
