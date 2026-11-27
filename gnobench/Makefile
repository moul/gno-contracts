# gnobench: run `make help`.
#
# One variable matters: GNOROOT, a gnolang/gno checkout. It supplies the gno
# stdlibs. The generated benchmark sources land in ../.gno/scratch/gnobench,
# which is inside this repository's gno workspace (so p/moul/* and the vendored
# p/nt/* resolve) and gitignored (so nothing lands in the tree).

# The default matches what .github/actions/setup-gno clones to, so CI needs no
# override. On a workstation, export GNOROOT or pass it: make bench GNOROOT=~/src/gno
GNOROOT ?= $(HOME)/gno
SUITE   ?= storage
N       ?= 100,1000
VALUE   ?= str,obj
REPEAT  ?= 2

# GNOROOT supplies the stdlibs, but the interpreter and its gas meter are the
# gnolang/gno Go module go.mod pins. install-local builds against GNOROOT's Go
# code instead, through a copy of go.mod kept in the gitignored scratch
# directory, so the committed one never changes. The build records GNOROOT's
# commit, so `call` can warn once GNOROOT has moved on without a rebuild.
LOCALMOD := ../.gno/scratch/gnobench-localmod

.DEFAULT_GOAL := help
.PHONY: help bench bench-quick bench-full report report-check list test install install-local clean

help: ## show this help
	@awk 'BEGIN{FS=":.*?## "} /^##@/{printf "\n%s\n",substr($$0,5)} /^[a-z][a-z-]*:.*?## /{printf "  %-13s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

##@ Measuring

bench: ## measure SUITE at N and merge into this machine's result file
	GNOROOT=$(GNOROOT) go run . run -suite $(SUITE) -n $(N) -value $(VALUE) -repeat $(REPEAT) -v

bench-quick: ## the fast pass: one size, strings only, no repeats
	GNOROOT=$(GNOROOT) go run . run -suite $(SUITE) -n 1000 -value str -repeat 1 -v

bench-full: ## every suite, every size; slow, this is what CI runs on a schedule
	GNOROOT=$(GNOROOT) go run . run -suite storage -n 100,1000 -value str,obj -repeat 2 -v
	GNOROOT=$(GNOROOT) go run . run -suite storage -n 10000 -value str -repeat 1 -v
	GNOROOT=$(GNOROOT) go run . run -suite wiring -n 100,1000 -repeat 2 -v
	GNOROOT=$(GNOROOT) go run . run -suite digest -n 32,256,1024,8192 -repeat 2 -v

##@ Output

report: ## regenerate reports/, the README charts and its results section, measuring nothing
	go run . report

report-check: ## fail if the README's generated region disagrees with results/
	go run . report -check

list: ## what suites, candidates and workloads exist
	go run . list

##@ Housekeeping

test: ## go test
	go test ./...

install: ## build the binary into this directory
	go build -o gnobench .

install-local: ## build the binary against the Go code of GNOROOT, not the gno go.mod pins
	mkdir -p $(LOCALMOD)
	cp go.mod go.sum $(LOCALMOD)/
	go mod edit -modfile=$(LOCALMOD)/go.mod -replace github.com/gnolang/gno=$(abspath $(GNOROOT))
	go build -mod=mod -modfile=$(LOCALMOD)/go.mod \
		-ldflags "-X main.builtGnoCommit=$$(git -C $(GNOROOT) rev-parse HEAD 2>/dev/null)" -o gnobench .

clean: ## remove the built binary and the generated sources
	rm -f gnobench
	rm -rf ../.gno/scratch/gnobench $(LOCALMOD)
