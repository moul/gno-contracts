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

# Every buildable package directory under the contract trees: one gnomod.toml
# each, EXCLUDING archived packages marked `ignore = true` (the gno toolchain
# skips ignored modules for `lint` but NOT for an explicitly-targeted `test`, so
# we must filter them out here or CI would try to build them).
PKG_DIRS := $(shell for d in $$(find p/moul r/moul -name gnomod.toml -exec dirname {} \; 2>/dev/null); do grep -qE '^[[:space:]]*ignore[[:space:]]*=[[:space:]]*true' "$$d/gnomod.toml" || echo "$$d"; done | sort)

.DEFAULT_GOAL := help
.PHONY: help deps bump-deps test lint fmt gen manifest readme readmes check sync publish status report graph view clean upload

help: ## show this help
	@awk 'BEGIN{FS=":.*?## "} /^[a-zA-Z_-]+:.*?## /{printf "  %-10s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

view: ## (re)build the stdlib-only GNOROOT view used by lint/test
	@test -n "$(GNOROOT)" || { echo "GNOROOT must point at a gnolang/gno checkout"; exit 1; }
	@rm -rf "$(VIEW)" && mkdir -p "$(VIEW)/examples"
	@for e in $(abspath $(GNOROOT))/*; do \
		b=$$(basename "$$e"); \
		[ "$$b" = examples ] || ln -sfn "$$e" "$(VIEW)/$$b"; \
	done

deps: ## vendor MISSING external gno.land deps into vendor/ (reads real GNOROOT/examples)
	$(TOOL) vendor

# `deps` only fetches what's absent, so vendor/ stays pinned — and silently
# drifts from the monorepo. This re-copies every dep from the current
# GNOROOT/examples: the deliberate "bump gno" step. Review the diff, then
# `make lint test` against a matching gno build before committing.
bump-deps: ## re-vendor ALL external deps from GNOROOT/examples (bump the pinned snapshot)
	$(TOOL) vendor -refresh

test: toolcheck guard-examples view ## gno test every contract (deps resolved from committed vendor/)
	@set -e; for d in $(PKG_DIRS); do echo "== test $$d =="; GNOROOT="$(VIEW)" $(GNO) test ./$$d; done

# Prove the gno toolchain actually VALIDATES example tests. gno silently skips
# Example funcs on toolchains that lack the feature, turning every ExampleRender
# into a no-op that passes (false green). Run a package whose example output is
# deliberately wrong and require `gno test` to FAIL on it; if it passes, the
# toolchain is blind to examples — abort.
toolcheck: view ## verify the gno toolchain validates example tests
	@tmp=$$(mktemp -d); \
	printf 'module = "gno.land/p/moul/toolcheck/v1"\ngno = "0.9"\n' > $$tmp/gnomod.toml; \
	printf 'package toolcheck\n\nfunc H() string { return "hi" }\n' > $$tmp/x.gno; \
	printf 'package toolcheck\n\nimport "fmt"\n\nfunc ExampleH() {\n\tfmt.Println(H())\n\t// Output:\n\t// WRONG-ON-PURPOSE\n}\n' > $$tmp/x_test.gno; \
	if GNOROOT="$(VIEW)" $(GNO) test $$tmp >/dev/null 2>&1; then \
	  rm -rf $$tmp; \
	  echo "ERROR: this gno does NOT validate example tests — they would be false-green."; \
	  echo "       Build gno from gnolang/gno master (go build -o gno ./gnovm/cmd/gno)."; \
	  exit 1; \
	fi; \
	rm -rf $$tmp; echo "toolcheck: gno validates example tests"

# Every gno Example* test must pin an `// Output:` block, else gno skips it
# silently (a test that asserts nothing).
guard-examples: ## fail if any Example* test lacks an // Output: block
	@python3 tools/guard_examples.py

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

upload: ## broadcast packages to a network via gnopublish, e.g. ARGS="-net portal-loop -key mykey -dry-run ./..."
	cd tools/gnopublish && GOTOOLCHAIN=auto go run . $(ARGS)

status: ## refresh on-chain upload status (all networks) + README; needs gnokey
	$(TOOL) status $(if $(NET),-net $(NET),)

report: ## analyze the PR diff (BASE=origin/main) into a Markdown report
	$(TOOL) report $(if $(BASE),-base $(BASE),)

graph: ## generate per-package + global dependency graphs into _assets/ (needs graphviz for svg/png)
	$(TOOL) graph

clean: ## remove build artifacts and the GNOROOT view
	rm -rf bin "$(VIEW)"
