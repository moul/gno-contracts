// Package passport is an on-chain identity and lifecycle registry for
// autonomous (AI) agents.
//
// The premise: a long-lived agent identity is *weak* evidence. The code,
// model, prompt, owner, operating keys and runtime behind an identity can
// all change silently. A blockchain cannot preserve an agent's cognition;
// it can only preserve the *history* of what an identity claimed to be and
// who controlled it, in an order nobody can rewrite.
//
// So this realm does not try to prove an agent is trustworthy. It records
// registration, ownership transfers, operator changes and — crucially —
// runtime changes, and it surfaces them so a reader can judge how much the
// identity has drifted since it was created.
package passport

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Status is the lifecycle state of an agent identity.
type Status string

const (
	StatusActive    Status = "active"
	StatusSuspended Status = "suspended"
	StatusRetired   Status = "retired"
)

// Endpoint advertises where the agent can be reached or discovered
// (e.g. an MCP server, an A2A endpoint, a DID document, an ENS name).
type Endpoint struct {
	Kind string // "mcp", "a2a", "did", "url", ...
	URI  string
}

// Event is one entry in an agent's append-only lifecycle log.
type Event struct {
	Height int64
	Actor  address
	Kind   string // "register", "transfer", "add-operator", "set-runtime", ...
	Detail string
}

// Agent is a persistent, importable identity object. Other realms can
// import this package and ask questions like IsActive / IsOperator
// directly, instead of parsing NFT metadata scattered across contracts.
type Agent struct {
	ID        string
	Owner     address
	Operators []address
	Runtime   string // free-form runtime descriptor, e.g. "claude-opus-4-8@<commit>"
	Endpoints []Endpoint
	Caps      []string // declared capability slugs
	Status    Status
	CreatedAt int64
	UpdatedAt int64
	History   []Event
}

var agents = avl.NewTree() // id -> *Agent

// Register creates a new agent identity owned by the caller. The id must
// be a non-empty, previously unused slug.
func Register(cur realm, id, runtimeDesc string) {
	assert(id != "", "empty agent id")
	assert(!agents.Has(id), "agent id already registered: "+id)

	caller := cur.Previous().Address()
	h := runtime.ChainHeight()
	a := &Agent{
		ID:        id,
		Owner:     caller,
		Runtime:   runtimeDesc,
		Status:    StatusActive,
		CreatedAt: h,
		UpdatedAt: h,
	}
	a.log(h, caller, "register", "runtime="+runtimeDesc)
	agents.Set(id, a)
	chain.Emit("AgentRegistered", "id", id, "owner", caller.String())
}

// Transfer hands ownership of an agent to a new address. Only the current
// owner may call it. Ownership changes are the single most important thing
// to keep visible: the operator behind an identity may become someone else.
func Transfer(cur realm, id string, newOwner address) {
	a, caller := mustOwn(cur, id)
	old := a.Owner
	a.Owner = newOwner
	a.touch(caller, "transfer", old.String()+" -> "+newOwner.String())
	chain.Emit("AgentTransferred", "id", id, "from", old.String(), "to", newOwner.String())
}

// AddOperator authorizes an additional address to act as this agent.
func AddOperator(cur realm, id string, op address) {
	a, caller := mustOwn(cur, id)
	for _, e := range a.Operators {
		assert(e != op, "already an operator")
	}
	a.Operators = append(a.Operators, op)
	a.touch(caller, "add-operator", op.String())
	chain.Emit("AgentOperatorAdded", "id", id, "operator", op.String())
}

// SetRuntime records a change of the agent's runtime/model. This is logged
// loudly: a runtime change means the thing acting under this identity is
// (partly) a different thing than before.
func SetRuntime(cur realm, id, runtimeDesc string) {
	a, caller := mustOwn(cur, id)
	old := a.Runtime
	a.Runtime = runtimeDesc
	a.touch(caller, "set-runtime", old+" -> "+runtimeDesc)
	chain.Emit("AgentRuntimeChanged", "id", id, "runtime", runtimeDesc)
}

// AddEndpoint advertises a discovery/interaction endpoint.
func AddEndpoint(cur realm, id, kind, uri string) {
	a, caller := mustOwn(cur, id)
	a.Endpoints = append(a.Endpoints, Endpoint{Kind: kind, URI: uri})
	a.touch(caller, "add-endpoint", kind+":"+uri)
}

// DeclareCapability records a capability the agent claims to offer. Note:
// this is a *claim*, not proof. Validation belongs to other realms
// (see the receipt and gnomem demos).
func DeclareCapability(cur realm, id, capab string) {
	a, caller := mustOwn(cur, id)
	a.Caps = append(a.Caps, capab)
	a.touch(caller, "declare-capability", capab)
}

// Suspend and Retire move the lifecycle forward. Retire is terminal.
func Suspend(cur realm, id string) { setStatus(cur, id, StatusSuspended) }
func Retire(cur realm, id string)  { setStatus(cur, id, StatusRetired) }

// Reactivate returns a suspended agent to active. A retired agent cannot
// be reactivated.
func Reactivate(cur realm, id string) {
	a, caller := mustOwn(cur, id)
	assert(a.Status != StatusRetired, "retired agents cannot be reactivated")
	a.Status = StatusActive
	a.touch(caller, "reactivate", "")
}

// ---- read-only API other realms and readers can rely on ----

// Get returns a copy of the agent record; panics if unknown.
func Get(id string) Agent {
	return *mustGet(id)
}

// Exists reports whether an id is registered.
func Exists(id string) bool { return agents.Has(id) }

// IsActive reports whether the agent exists and is in the active state.
func IsActive(id string) bool {
	if !agents.Has(id) {
		return false
	}
	return agents.Get(id).(*Agent).Status == StatusActive
}

// IsOperator reports whether addr is the owner or a listed operator of an
// active agent — the check other realms should gate agent actions on.
func IsOperator(id string, addr address) bool {
	if !agents.Has(id) {
		return false
	}
	a := agents.Get(id).(*Agent)
	if a.Status != StatusActive {
		return false
	}
	if a.Owner == addr {
		return true
	}
	for _, op := range a.Operators {
		if op == addr {
			return true
		}
	}
	return false
}

// Count returns the number of registered agents.
func Count() int { return agents.Size() }

// ---- internal helpers ----

func setStatus(cur realm, id string, s Status) {
	a, caller := mustOwn(cur, id)
	assert(a.Status != StatusRetired, "agent is retired")
	a.Status = s
	a.touch(caller, "status", string(s))
	chain.Emit("AgentStatusChanged", "id", id, "status", string(s))
}

func mustGet(id string) *Agent {
	assert(agents.Has(id), "unknown agent: "+id)
	return agents.Get(id).(*Agent)
}

func mustOwn(cur realm, id string) (*Agent, address) {
	a := mustGet(id)
	caller := cur.Previous().Address()
	assert(caller == a.Owner, "caller is not the owner of "+id)
	return a, caller
}

func (a *Agent) log(h int64, actor address, kind, detail string) {
	a.History = append(a.History, Event{Height: h, Actor: actor, Kind: kind, Detail: detail})
}

func (a *Agent) touch(actor address, kind, detail string) {
	h := runtime.ChainHeight()
	a.UpdatedAt = h
	a.log(h, actor, kind, detail)
}

func assert(cond bool, msg string) {
	if !cond {
		panic(msg)
	}
}

// Render shows the registry, or a single agent's profile + lifecycle log
// at r/moul/agents/passport/v0:<id>. The profile deliberately foregrounds
// drift: how many owner and runtime changes have happened since creation.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	return renderAgent(path)
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString("# Agent Passport\n\n")
	sb.WriteString(ufmt.Sprintf("On-chain identity & lifecycle registry — %d agent(s).\n\n", agents.Size()))
	if agents.Size() == 0 {
		sb.WriteString("_No agents registered yet._\n")
		return sb.String()
	}
	sb.WriteString("| Agent | Owner | Runtime | Status |\n")
	sb.WriteString("|---|---|---|---|\n")
	agents.Iterate("", "", func(key string, v any) bool {
		a := v.(*Agent)
		sb.WriteString(ufmt.Sprintf("| [%s](/r/moul/agents/passport/v0:%s) | %s | %s | %s |\n",
			a.ID, a.ID, short(a.Owner), a.Runtime, string(a.Status)))
		return false
	})
	return sb.String()
}

func renderAgent(id string) string {
	a := mustGet(id)
	var sb strings.Builder
	sb.WriteString(ufmt.Sprintf("# Agent: %s\n\n", a.ID))
	sb.WriteString(ufmt.Sprintf("- **Status:** %s\n", string(a.Status)))
	sb.WriteString(ufmt.Sprintf("- **Owner:** %s\n", a.Owner.String()))
	sb.WriteString(ufmt.Sprintf("- **Runtime:** %s\n", a.Runtime))
	sb.WriteString(ufmt.Sprintf("- **Created at height:** %d\n", a.CreatedAt))
	sb.WriteString(ufmt.Sprintf("- **Last updated at height:** %d\n\n", a.UpdatedAt))

	owners, runtimes := 0, 0
	for _, e := range a.History {
		switch e.Kind {
		case "transfer":
			owners++
		case "set-runtime":
			runtimes++
		}
	}
	sb.WriteString("## Drift\n\n")
	sb.WriteString(ufmt.Sprintf("What the chain actually proves about this identity — how much it has changed:\n\n"))
	sb.WriteString(ufmt.Sprintf("- Ownership changes since creation: **%d**\n", owners))
	sb.WriteString(ufmt.Sprintf("- Runtime changes since creation: **%d**\n\n", runtimes))

	if len(a.Operators) > 0 {
		sb.WriteString("## Operators\n\n")
		for _, op := range a.Operators {
			sb.WriteString("- " + op.String() + "\n")
		}
		sb.WriteString("\n")
	}
	if len(a.Endpoints) > 0 {
		sb.WriteString("## Endpoints\n\n")
		for _, e := range a.Endpoints {
			sb.WriteString(ufmt.Sprintf("- `%s`: %s\n", e.Kind, e.URI))
		}
		sb.WriteString("\n")
	}
	if len(a.Caps) > 0 {
		sb.WriteString("## Declared capabilities\n\n")
		sb.WriteString("> These are self-declared claims, not proofs.\n\n")
		for _, c := range a.Caps {
			sb.WriteString("- " + c + "\n")
		}
		sb.WriteString("\n")
	}

	sb.WriteString("## Lifecycle log (append-only)\n\n")
	sb.WriteString("| Height | Actor | Event | Detail |\n")
	sb.WriteString("|---|---|---|---|\n")
	for _, e := range a.History {
		sb.WriteString(ufmt.Sprintf("| %d | %s | %s | %s |\n", e.Height, short(e.Actor), e.Kind, e.Detail))
	}
	return sb.String()
}

func short(a address) string {
	s := a.String()
	if len(s) <= 12 {
		return s
	}
	return s[:8] + "…" + s[len(s)-4:]
}
