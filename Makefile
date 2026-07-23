# moul/gno-contracts — see `make help`.
#
# Requires GNOROOT to point at a gnolang/gno checkout (provides the gno binary's
# stdlibs). External gno.land deps are vendored (see `make deps`); local
# gno.land/{p,r}/moul/* packages resolve via gnowork.toml.

GNO  ?= gno
GO   ?= go

# Every package directory (one gnomod.toml each) under the contract trees.
PKG_DIRS := $(shell find p/moul r/moul -name gnomod.toml -exec dirname {} \; 2>/dev/null | sort)

.DEFAULT_GOAL := help
.PHONY: help deps test lint fmt gen manifest readme check sync publish tools clean

help: ## show this help
	@awk 'BEGIN{FS=":.*?## "} /^[a-zA-Z_-]+:.*?## /{printf "  %-10s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

deps: ## vendor external gno.land dependencies into vendor/ (needs GNOROOT)
	$(GO) run ./tools vendor

test: ## gno test every contract
	@set -e; for d in $(PKG_DIRS); do echo "== test $$d =="; $(GNO) test ./$$d; done

lint: ## gno lint every contract
	@set -e; for d in $(PKG_DIRS); do echo "== lint $$d =="; $(GNO) lint ./$$d; done

fmt: ## gno fmt every contract in place
	@set -e; for d in $(PKG_DIRS); do $(GNO) fmt -w ./$$d || true; done

manifest: ## refresh contracts.json from the contract trees
	$(GO) run ./tools manifest

readme: ## regenerate the README contracts table
	$(GO) run ./tools readme

gen: manifest readme ## manifest + readme

check: ## fail if contracts.json / README table are stale (CI guard)
	$(GO) run ./tools check

sync: ## report drift vs the gnolang/gno monorepo (needs GNOROOT)
	$(GO) run ./tools sync

publish: ## dependency-ordered publish plan; NET=<net> CHECK=1 to query chain
	$(GO) run ./tools publish $(if $(NET),-net $(NET),) $(if $(CHECK),-check,)

tools: ## build the maintenance CLI into bin/
	$(GO) build -o bin/gno-contracts ./tools

clean: ## remove build artifacts
	rm -rf bin
