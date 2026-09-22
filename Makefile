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

.DEFAULT_GOAL := help
.PHONY: help lint test fmt guards toolcheck guard-examples guard-render \
	guard-readmes guard-private verify deps bump-deps manifest readme readmes gen check \
	sync graph publish upload upload-sim status report preview site clean

help: ## show this help
	@awk 'BEGIN{FS=":.*?## "} /^##@/{printf "\n%s\n",substr($$0,5)} /^[a-z][a-z-]*:.*?## /{printf "  %-14s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

##@ The gate: green before every commit, and what CI runs

lint: ## gno lint every contract
	$(GNOCONTRACTS) gno lint $(ARGS) $(PKG)

test: guards ## run the guards, then gno test every contract
	$(GNOCONTRACTS) gno test $(ARGS) $(PKG)

fmt: ## gno fmt every contract in place
	$(GNOCONTRACTS) gno fmt $(ARGS) $(PKG)

guards: toolcheck guard-examples guard-render guard-readmes guard-private ## every guard CI enforces

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

verify: ## fail if gnomod.lock is stale or a pinned version no longer reproduces
	$(GNOPM) verify

##@ Dependencies

deps: ## vendor the external gno.land deps that are missing (reads the real GNOROOT/examples)
	$(GNOCONTRACTS) vendor

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

gen: manifest readme readmes ## manifest + README table + package READMEs

check: ## fail if contracts.json or the README table is stale
	$(GNOCONTRACTS) check

##@ The chain

publish: ## dependency-ordered publish plan; NET=<net> CHECK=1 to query the chain
	$(GNOCONTRACTS) publish $(if $(NET),-net $(NET),) $(if $(CHECK),-check,)

upload: ## write the gnokey script for what a network is missing; NET= KEY= PKG=, then YES=1 to run it
	@$(GNOCONTRACTS) upload $(if $(NET),-net $(NET),) $(if $(KEY),-key $(KEY),) $(if $(YES),-yes,) $(PKG)

upload-sim: ## the same broadcast through gnopublish, whose gas comes from a real simulation
	cd tools/gnopublish && GOTOOLCHAIN=auto go run . $(ARGS)

status: ## refresh on-chain upload status for every network; needs gnokey
	$(GNOCONTRACTS) status $(if $(NET),-net $(NET),)

sync: ## report drift vs the gnolang/gno monorepo (needs GNOROOT)
	$(GNOCONTRACTS) sync

##@ Pull requests and previews

# `@`-prefixed: this recipe's stdout IS the comment body CI posts, so an echoed
# command line would land at the top of every pull request comment (it did).
report: ## render the sticky PR comment body from the diff; BASE=<ref>
	@$(GNOCONTRACTS) pr $(if $(BASE),-base $(BASE),)

preview: ## render what ARGS selects into _preview/, e.g. ARGS="./r/moul/home"
	$(GNOCONTRACTS) preview -out _preview $(ARGS)

site: ## render EVERY package into _site/, what the main workflow publishes
	$(GNOCONTRACTS) preview -all -out _site

clean: ## remove the GNOROOT view, the gnopm assembly, the previews and the caches
	rm -rf bin .gnoroot-view .gnopm .cache _preview _site
