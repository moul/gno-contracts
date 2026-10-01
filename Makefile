# moul/gno-contracts: run `make help`.
#
# Every recipe here is one line. The logic lives in the Go tools, where it can
# be read, tested and given a flag: `go -C tools tool gnocontracts help` and
# `go -C tools tool gnopm -h` are the real interface, and the reasoning behind
# each step is a doc comment next to the code that does it.
#
# One variable matters: GNOROOT, a gnolang/gno checkout. It supplies the gno
# stdlibs and nothing else. Every external gno.land/* dependency is vendored
# under vendor/ and resolves from there, because the tools point the toolchain
# at a stdlib-only image of GNOROOT whose examples/ is empty.
#
# Two conventions: ARGS= passes flags straight through to the tool, PKG=
# narrows a target to the packages whose path contains it.

GNOCONTRACTS ?= go -C tools tool gnocontracts
GNOPM        ?= go -C tools tool gnopm
GNOHOME      ?= go -C tools tool gnohome
# Where `make home-push PRINT=1` writes the unsigned document. Without PRINT the
# tool picks its own path, keyed by chain id so two chains cannot collide.
HOME_TX      ?= /tmp/home.tx.json

.DEFAULT_GOAL := help
.PHONY: help lint test fmt guards toolcheck guard-examples guard-render bench bench-report \
	guard-readmes guard-private guard-untrusted-render guard-tables guard-tables-update audit-patterns audit-patterns-update review-advice \
	verify deps deps-chain bump-deps manifest readme readmes gen check \
	sync graph publish status home-push home-packages report preview site clean

help: ## show this help
	@awk 'BEGIN{FS=":.*?## "} /^##@/{printf "\n%s\n",substr($$0,5)} /^[a-z][a-z-]*:.*?## /{printf "  %-14s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

##@ The gate: green before every commit, and what CI runs

lint: ## gno lint every contract
	$(GNOCONTRACTS) gno lint $(ARGS) $(PKG)

test: guards ## run the guards, then gno test every contract
	$(GNOCONTRACTS) gno test $(ARGS) $(PKG)

fmt: ## gno fmt every contract in place
	$(GNOCONTRACTS) gno fmt $(ARGS) $(PKG)

guards: toolcheck guard-examples guard-render guard-readmes guard-private guard-untrusted-render guard-tables ## every guard CI enforces

toolcheck: ## fail if this gno skips example tests, which would make them false-green
	@$(GNOCONTRACTS) gno toolcheck

guard-examples: ## fail if an Example* test pins no // Output: block
	@$(GNOCONTRACTS) guard-examples

guard-render: ## fail if a realm declares Render and no test calls it
	@$(GNOCONTRACTS) guard-render

guard-readmes: ## fail if a package ships a README that documents nothing; LIST=1 lists the undocumented
	@$(GNOCONTRACTS) guard-readmes $(if $(LIST),-list,)

guard-private: ## fail if a realm declares neither private = true nor why it is public
	@$(GNOCONTRACTS) guard-private

guard-untrusted-render: ## fail if a realm renders a caller's string without escaping it
	@$(GNOCONTRACTS) guard-untrusted-render

review-advice: ## should this diff get a Copilot code review? REVIEW or SKIP, with why; BASE=<ref>
	@$(GNOCONTRACTS) review-advice $(if $(BASE),-base $(BASE),) $(ARGS)

audit-patterns: ## run the upstream audit-pattern rules over every contract; fails on a hit the baseline does not record
	@$(GNOCONTRACTS) audit-patterns $(ARGS)

audit-patterns-update: ## re-record the audit-pattern baseline from what the tree contains now
	@$(GNOCONTRACTS) audit-patterns -update

guard-tables: ## fail if a package builds a markdown table by hand instead of using p/moul/kit/ui
	@$(GNOCONTRACTS) guard-tables

guard-tables-update: ## re-record which packages still build tables by hand
	@$(GNOCONTRACTS) guard-tables -update

verify: ## fail if gnomod.lock is stale or a pinned version no longer reproduces
	$(GNOPM) verify

##@ Benchmarks

bench: ## measure what a construct costs; see gnobench/README.md
	$(MAKE) -C gnobench bench

bench-report: ## regenerate gnobench/reports/ from the committed results
	$(MAKE) -C gnobench report

##@ Dependencies

deps: ## vendor the external gno.land deps that are missing (reads the real GNOROOT/examples)
	$(GNOCONTRACTS) vendor

deps-chain: ## vendor the missing deps, falling back to mainnet for what lives only on a chain
	$(GNOCONTRACTS) vendor -from-chain https://rpc.gno.land

bump-deps: ## re-vendor EVERY external dep from GNOROOT/examples: the deliberate "bump gno" step
	$(GNOCONTRACTS) vendor -refresh

##@ Generated on main, never in a pull request

manifest: ## refresh contracts.json from the contract trees
	$(GNOCONTRACTS) manifest

readme: ## regenerate the contracts table in README.md
	$(GNOCONTRACTS) readme

readmes: ## refresh the generated footer of every package README
	$(GNOCONTRACTS) readmes

graph: ## write per-package and global dependency graphs into _assets/ (svg/png need graphviz)
	$(GNOCONTRACTS) graph

home-packages: ## regenerate r/moul/home's packages slot from contracts.json
	@$(GNOHOME) packages > r/moul/home/content/packages.md

gen: manifest readme readmes home-packages ## manifest + README table + package READMEs + the home packages slot

check: ## fail if contracts.json or the README table is stale
	$(GNOCONTRACTS) check

##@ The chain

publish: ## publish what the chain is missing, in dependency order; PRINT=1 plans without acting, KEY= names the gnokey key, PKG= filters
	$(GNOPM) publish $(if $(PRINT),-print,) $(if $(KEY),-key $(KEY),) $(PKG)

status: ## refresh on-chain upload status for every network; needs gnokey
	$(GNOCONTRACTS) status $(if $(NET),-net $(NET),)

home-push: ## push r/moul/home to match content/: sets what differs, deletes what is gone, one signature; PRINT=1 writes the document instead of signing
	$(GNOHOME) tx -prune $(if $(PRINT),-batch $(HOME_TX),-run)

sync: ## report drift vs the gnolang/gno monorepo (needs GNOROOT)
	$(GNOCONTRACTS) sync

##@ Pull requests and previews

# `@`-prefixed: this recipe's stdout IS the comment body CI posts, so an echoed
# command line would land at the top of every pull request comment (it did).
report: ## render the sticky PR comment body from the diff; BASE=<ref>
	@mkdir -p .cache
	@$(GNOPM) tool ci > .cache/gnopm-ci.md 2>/dev/null || true
	@$(GNOCONTRACTS) pr $(if $(BASE),-base $(BASE),) -gnopm-report .cache/gnopm-ci.md

preview: ## render what ARGS selects into _preview/, e.g. ARGS="./r/moul/home"
	$(GNOCONTRACTS) preview -out _preview $(ARGS)

site: ## render EVERY package into _site/, what the main workflow publishes
	$(GNOCONTRACTS) preview -all -out _site

clean: ## remove the GNOROOT view, the gnopm assembly, the previews and the caches
	rm -rf bin .gnoroot-view .gnopm .cache _preview _site
