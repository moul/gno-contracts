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

GNO          ?= gno
GNOCONTRACTS ?= go -C tools tool gnocontracts
GNOPM        ?= go -C tools tool gnopm

# Ephemeral stdlib-only view of the toolchain (empty examples/ → vendor wins).
VIEW := $(CURDIR)/.gnoroot-view

# Every buildable package directory under the contract trees: one gnomod.toml
# each, EXCLUDING archived packages marked `ignore = true` (the gno toolchain
# skips ignored modules for `lint` but NOT for an explicitly-targeted `test`, so
# we must filter them out here or CI would try to build them).
# Dot-directories are skipped: they are scratch (see TOOLCHECK_DIR), never
# contracts, and a canary left behind by an interrupted run must not become a
# package that lint/test tries to build.
PKG_DIRS := $(shell for d in $$(find p/moul r/moul -name gnomod.toml -not -path '*/.*' -exec dirname {} \; 2>/dev/null); do grep -qE '^[[:space:]]*ignore[[:space:]]*=[[:space:]]*true' "$$d/gnomod.toml" || echo "$$d"; done | sort)

# Versions that no longer live in the working tree, materialized under .gnopm/
# by `gnopm sync`. They are linted and tested too: they are deployed on
# chain, packages in the tree still import them, and "does this still build on
# current gno master" is exactly the drift signal this repo exists to produce.
# Dropping them from CI when their directory went away would have quietly
# reduced coverage as a side effect of a directory move.
#
# Recursively expanded (`=`, not `:=`) on purpose: .gnopm/ is built by the
# .gnopm/.stamp prerequisite, which runs AFTER the Makefile is parsed. A `:=`
# here would evaluate to nothing on a fresh clone and silently skip them.
OLD_PKG_DIRS = $(shell for d in $$(find .gnopm -name gnomod.toml -exec dirname {} \; 2>/dev/null); do grep -qE '^[[:space:]]*ignore[[:space:]]*=[[:space:]]*true' "$$d/gnomod.toml" || echo "$$d"; done | sort)

.DEFAULT_GOAL := help
.PHONY: help deps bump-deps test guard-examples guard-render lint fmt gen manifest readme readmes check sync publish status report graph view clean upload verify

help: ## show this help
	@awk 'BEGIN{FS=":.*?## "} /^[a-zA-Z_-]+:.*?## /{printf "  %-10s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

view: ## (re)build the stdlib-only GNOROOT view used by lint/test
	@test -n "$(GNOROOT)" || { echo "GNOROOT must point at a gnolang/gno checkout"; exit 1; }
	@rm -rf "$(VIEW)" && mkdir -p "$(VIEW)/examples"
	@for e in $(abspath $(GNOROOT))/*; do \
		b=$$(basename "$$e"); \
		[ "$$b" = examples ] || ln -sfn "$$e" "$(VIEW)/$$b"; \
	done

# ---------------------------------------------------------------- gnopm ----
#
# A package's version lives in its gnomod.toml `module` line, not in its
# directory name. gnomod.lock records, per module path, where that version's
# source actually is; versions that no longer have a directory are rebuilt
# from git history into .gnopm/.
#
# gnopm is the interface, not these targets: `gnopm status`, `gnopm sync`,
# `gnopm bump <pkg>`. They are here only for the two things Make genuinely
# needs, a prerequisite and a CI gate.
#
# gnomod.lock is SOURCE, not a generated artifact: unlike contracts.json it is
# committed by the author of the change, because a change that bumps a version
# has to carry the pin that keeps the old version resolvable, or CI cannot
# build the packages that still import it. It only changes when a package is
# added, removed or bumped, never on an ordinary source edit.

verify: ## fail if gnomod.lock is stale or a pinned version no longer reproduces
	$(GNOPM) verify

# Everything gno-invoking depends on this: `gnopm sync` regenerates the lock if
# the tree moved and materializes any version that is pinned but missing. It is
# idempotent and silent when there is nothing to do, so the dependency is free.
.gnopm/.stamp: gnomod.lock
	$(GNOPM) sync

deps: ## vendor MISSING external gno.land deps into vendor/ (reads real GNOROOT/examples)
	$(GNOCONTRACTS) vendor

# `deps` only fetches what's absent, so vendor/ stays pinned — and silently
# drifts from the monorepo. This re-copies every dep from the current
# GNOROOT/examples: the deliberate "bump gno" step. Review the diff, then
# `make lint test` against a matching gno build before committing.
bump-deps: ## re-vendor ALL external deps from GNOROOT/examples (bump the pinned snapshot)
	$(GNOCONTRACTS) vendor -refresh

test: toolcheck guard-examples guard-render view .gnopm/.stamp ## gno test every contract (deps resolved from committed vendor/)
	@set -e; for d in $(PKG_DIRS) $(OLD_PKG_DIRS); do echo "== test $$d =="; GNOROOT="$(VIEW)" $(GNO) test ./$$d; done

# Prove the gno toolchain actually VALIDATES example tests. gno silently skips
# Example funcs on toolchains that lack the feature, turning every ExampleRender
# into a no-op that passes (false green). Run a package whose example output is
# deliberately wrong and require `gno test` to FAIL on it; if it passes, the
# toolchain is blind to examples — abort.
#
# The canary MUST live inside this workspace, hence TOOLCHECK_DIR under p/moul
# rather than a mktemp -d. The skip is workspace-dependent: a toolchain that
# skips every example in this repo still VALIDATES a byte-identical package
# placed in /tmp (verified against gno master.3130 — skips in-tree, validates
# out-of-tree). A canary in /tmp therefore goes green on exactly the broken
# toolchain this target exists to catch.
TOOLCHECK_DIR := p/moul/.toolcheck

toolcheck: view .gnopm/.stamp ## verify the gno toolchain validates example tests
	@rm -rf "$(TOOLCHECK_DIR)"; mkdir -p "$(TOOLCHECK_DIR)"; \
	trap 'rm -rf "$(TOOLCHECK_DIR)"' EXIT; \
	printf 'module = "gno.land/p/moul/toolcheck/v1"\ngno = "0.9"\n' > "$(TOOLCHECK_DIR)/gnomod.toml"; \
	printf 'package toolcheck\n\nfunc H() string { return "hi" }\n' > "$(TOOLCHECK_DIR)/x.gno"; \
	printf 'package toolcheck\n\nfunc ExampleH() {\n\tprint(H())\n\t// Output:\n\t// WRONG-ON-PURPOSE\n}\n' > "$(TOOLCHECK_DIR)/x_test.gno"; \
	if GNOROOT="$(VIEW)" $(GNO) test ./$(TOOLCHECK_DIR) >/dev/null 2>&1; then \
	  echo "ERROR: this gno does NOT validate example tests — they would be false-green."; \
	  echo "       Build gno from gnolang/gno master (go build -o gno ./gnovm/cmd/gno)."; \
	  exit 1; \
	fi; \
	echo "toolcheck: gno validates example tests (workspace-resolved)"

# Every gno Example* test must pin an `// Output:` block, else gno skips it
# silently (a test that asserts nothing).
guard-examples: ## fail if any Example* test lacks an // Output: block
	@python3 tools/guard_examples.py

# A realm's Render is its whole public surface, and a Render whose output varies
# is a consensus bug — so every realm must have a test that actually calls it.
guard-render: ## fail if a realm declares Render but no test calls it
	@python3 tools/guard_render.py

lint: view .gnopm/.stamp ## gno lint every contract (deps resolved from committed vendor/)
	@set -e; for d in $(PKG_DIRS) $(OLD_PKG_DIRS); do echo "== lint $$d =="; GNOROOT="$(VIEW)" $(GNO) lint ./$$d; done

# Like lint/test, fmt resolves against the stdlib-only view. Without it the gno
# binary falls back to its built-in GNOROOT, which on a machine that does not
# have that exact checkout fails with `unable to load .../gnovm/stdlibs` for
# every package. The old `|| true` swallowed that, so `make fmt` reformatted
# nothing and said so to nobody.
# Only PKG_DIRS: a materialized old version is a read-only copy of history,
# and reformatting it would make `gnopm verify` fail against its recorded hash.
fmt: view .gnopm/.stamp ## gno fmt every contract in place
	@set -e; for d in $(PKG_DIRS); do GNOROOT="$(VIEW)" $(GNO) fmt -w ./$$d; done

manifest: ## refresh contracts.json from the contract trees
	$(GNOCONTRACTS) manifest

readme: ## regenerate the README contracts table
	$(GNOCONTRACTS) readme

readmes: ## ensure every package has a README (repo link + disclaimer)
	$(GNOCONTRACTS) readmes

gen: manifest readme readmes ## manifest + README table + per-package READMEs

check: ## fail if contracts.json / README table are stale (CI guard)
	$(GNOCONTRACTS) check

sync: ## report drift vs the gnolang/gno monorepo (needs GNOROOT)
	$(GNOCONTRACTS) sync

publish: ## dependency-ordered publish plan; NET=<net> CHECK=1 to query chain
	$(GNOCONTRACTS) publish $(if $(NET),-net $(NET),) $(if $(CHECK),-check,)

upload: ## broadcast packages to a network via gnopublish, e.g. ARGS="-net mainnet -key mykey -dry-run ./..." (on-chain hits cached in .cache/)
	cd tools/gnopublish && GOTOOLCHAIN=auto go run . $(ARGS)

status: ## refresh on-chain upload status (all networks) + README; needs gnokey
	$(GNOCONTRACTS) status $(if $(NET),-net $(NET),)

report: ## analyze the PR diff (BASE=origin/main) into a Markdown report
	$(GNOCONTRACTS) report $(if $(BASE),-base $(BASE),)

graph: ## generate per-package + global dependency graphs into _assets/ (needs graphviz for svg/png)
	$(GNOCONTRACTS) graph

clean: ## remove build artifacts, the GNOROOT view, the gnopm assembly and the gnopublish on-chain cache
	rm -rf bin "$(VIEW)" .cache .gnopm
