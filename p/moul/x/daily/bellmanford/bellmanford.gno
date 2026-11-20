// Package bellmanford finds the cheapest route from one node to every other
// node of a weighted directed graph whose arcs may cost LESS than nothing, as
// a pure, reusable package.
//
// It is the Bellman-Ford algorithm: V-1 passes over the whole arc list, each
// pass relaxing every arc, stopping as soon as a pass changes nothing. That is
// O(V*E) against Dijkstra's O((V+E) log V), and the extra cost buys exactly
// one thing: a negative arc no longer produces a confidently wrong answer. A
// settle-and-never-revisit search reads a rebate, a refund or a subsidy as an
// ordinary cheap hop and misses that it reorders everything decided before it.
//
// It also answers the question a shortest-path routine can only answer when it
// is allowed to look twice: whether a shortest path EXISTS. Go round a cycle
// whose arcs sum to less than zero and the total keeps falling, so there is no
// cheapest route to anything that cycle reaches, only cheaper ones. Such nodes
// report [Unbounded] rather than a number, the cycle itself is handed back by
// [Result.Cycle], and nodes the cycle cannot reach keep their real distances.
// A realm pricing a route across its own fee table wants to be told that,
// loudly, rather than handed the distance after an arbitrary number of turns.
//
// The run is deterministic. Arcs are relaxed in the order they were added,
// every pass, and a relaxation that merely ties the incumbent never replaces
// it, so the predecessor chain Path walks is the same on every node that runs
// the code. A search that broke ties by map iteration order would make a
// Render differ between validators, which is a consensus bug rather than a
// cosmetic one.
//
// Where it differs from [p/moul/x/daily/dijkstra](/p/moul/x/daily/dijkstra/v0),
// which is the right tool whenever every weight is non-negative:
//
//   - Dist has no "unreachable" sentinel value. -1 is a legitimate distance
//     here, so the int returned alongside ok=false carries no meaning at all.
//   - Self-loops are allowed. A negative one is the smallest negative cycle
//     there is, and refusing it would hide a case rather than simplify one.
//   - There is no AddUndirected. A negative arc in both directions is a
//     negative cycle by construction, so the convenience would be a trap.
//
// A live demo of this package is at
// [r/moul/x/daily/bellmanforddemo](/r/moul/x/daily/bellmanforddemo/v0).
package bellmanford

const (
	// MaxNodes bounds the graph so a caller can size gas up front.
	MaxNodes = 512
	// MaxEdges bounds the arcs for the same reason. The work is V*E in the
	// worst case, so these two caps are what make that worst case a number
	// rather than a hope.
	MaxEdges = 4000
	// MaxWeight bounds a single arc's cost, in either direction. The bound on
	// a distance is not a path's length times this: while a negative cycle is
	// still being relaxed, one pass can walk every one of MaxEdges arcs and the
	// run makes up to MaxNodes passes, so a distance can drift as far as
	// MaxNodes*MaxEdges*MaxWeight. driftBound below makes the compiler check
	// that product fits.
	MaxWeight = 1 << 40
)

// driftBound is the furthest a distance can move during a run, cycle included:
// MaxNodes passes, each over at most MaxEdges arcs, each worth at most
// MaxWeight. It is a typed const so that raising any of the three caps past
// what an int64 holds fails to compile instead of wrapping a distance and
// silently reporting no negative cycle.
const driftBound int64 = MaxNodes * MaxEdges * MaxWeight

// State is what a run can say about one node. It exists because "no distance"
// has two different causes here and they call for opposite reactions: nothing
// reaches the node, or too much does.
type State int

const (
	// Unknown means the graph has never heard the name.
	Unknown State = iota
	// Unreached means no route leaves the source for it.
	Unreached
	// Settled means it has a finite cheapest route, which Dist returns.
	Settled
	// Unbounded means a negative cycle reaches it, so every route can be
	// beaten by going round once more and no cheapest route exists.
	Unbounded
)

// String renders a State for a table or an error message.
func (s State) String() string {
	switch s {
	case Unknown:
		return "unknown"
	case Unreached:
		return "unreached"
	case Settled:
		return "settled"
	case Unbounded:
		return "unbounded"
	}
	return "invalid"
}

type arc struct {
	from, to, weight int
}

// Graph is a weighted directed graph over named nodes. The zero value is not
// usable, build one with New.
type Graph struct {
	names []string       // node index -> name, in insertion order
	index map[string]int // name -> node index. Looked up, never ranged over
	arcs  []arc          // every arc, in insertion order: this is the relaxation order
}

// New returns an empty Graph.
func New() *Graph { return &Graph{index: map[string]int{}} }

// AddNode registers a node with no arcs and returns its index. Adding a node
// twice returns the existing index and changes nothing, which is how a caller
// declares an island that nothing reaches.
//
// It panics on an empty name, and past MaxNodes.
func (g *Graph) AddNode(nm string) int {
	if nm == "" {
		panic("bellmanford: empty node name")
	}
	if i, ok := g.index[nm]; ok {
		return i
	}
	if len(g.names) >= MaxNodes {
		panic("bellmanford: too many nodes")
	}
	i := len(g.names)
	g.names = append(g.names, nm)
	g.index[nm] = i
	return i
}

// AddEdge records a one-way arc from -> to costing weight, registering either
// endpoint that is new. The weight may be negative, which is the whole reason
// this package exists. Parallel arcs are kept rather than collapsed: the
// search takes the cheapest, and dropping the others would lose information a
// caller may want to render.
//
// A self-loop is legal. A negative one is a one-arc negative cycle and is
// reported as such; a non-negative one can never improve a distance and is
// simply never relaxed.
//
// It panics on a weight outside [-MaxWeight, MaxWeight], and past MaxEdges.
func (g *Graph) AddEdge(from, to string, weight int) {
	if weight > MaxWeight || weight < -MaxWeight {
		panic("bellmanford: weight out of range")
	}
	if len(g.arcs) >= MaxEdges {
		panic("bellmanford: too many edges")
	}
	f := g.AddNode(from)
	t := g.AddNode(to)
	g.arcs = append(g.arcs, arc{from: f, to: t, weight: weight})
}

// Len returns the number of nodes.
func (g *Graph) Len() int { return len(g.names) }

// Edges returns the number of arcs.
func (g *Graph) Edges() int { return len(g.arcs) }

// Names returns the node names in insertion order. The slice is a copy, so a
// caller cannot reorder the graph's own index by sorting it.
func (g *Graph) Names() []string {
	out := make([]string, len(g.names))
	copy(out, g.names)
	return out
}

// Has reports whether the graph knows a node by that name.
func (g *Graph) Has(nm string) bool {
	_, ok := g.index[nm]
	return ok
}

// Result holds one single-source run. It is a snapshot: mutating the graph
// afterwards does not update it. It keeps its own views of the node names and
// the arc list, capped at their length when From ran, so a node or an arc
// added later is invisible to it rather than an index past its slices.
type Result struct {
	names     []string       // the graph's names as of From, capped
	arcs      []arc          // the graph's arcs as of From, capped
	index     map[string]int // shared with the graph: always bounds-check against names
	src       int
	dist      []int
	prev      []int
	reached   []bool
	unbounded []bool
	cycle     []int // a closed walk, first node repeated last. Empty when there is none
	rounds    int
	relaxs    int
}

// From runs the search outward from source and returns what every node is
// worth. It panics when source is not in the graph, because a typo'd source
// silently reporting "nothing is reachable" is the failure mode this package
// exists to avoid.
//
// It never panics on a negative cycle. A cycle is an answer, not an error, and
// the caller gets to decide what to do about it.
func (g *Graph) From(source string) *Result {
	s, ok := g.index[source]
	if !ok {
		panic("bellmanford: unknown source: " + source)
	}

	n := len(g.names)
	// Both slices are only ever appended to, so a full-slice expression is a
	// snapshot: a later append reallocates or writes past len, never inside it.
	m := len(g.arcs)
	r := &Result{names: g.names[:n:n], arcs: g.arcs[:m:m], index: g.index, src: s}
	r.dist = make([]int, n)
	r.prev = make([]int, n)
	r.reached = make([]bool, n)
	r.unbounded = make([]bool, n)
	for i := 0; i < n; i++ {
		r.prev[i] = -1
	}
	r.reached[s] = true

	// Up to V-1 passes. A shortest path visits each node at most once, so it
	// is at most V-1 arcs long, and one pass extends every known path by at
	// least one arc. More passes than that can only mean a negative cycle.
	stable := false
	for pass := 0; pass < n-1; pass++ {
		r.rounds++
		if !r.relaxAll() {
			stable = true
			break
		}
	}

	if stable {
		// Nothing moved in the last pass, so nothing can move again and no
		// negative cycle is reachable from here. Skip the detection pass
		// rather than pay for it.
		return r
	}
	r.detectCycle()
	return r
}

// relaxAll makes one pass over the arc list and reports whether anything
// improved. Arcs are visited in insertion order, every time: that is what
// makes two runs of the same graph produce the same predecessors.
func (r *Result) relaxAll() bool {
	changed := false
	for _, a := range r.arcs {
		if !r.reached[a.from] {
			continue
		}
		cand := r.dist[a.from] + a.weight
		if !r.reached[a.to] {
			r.reached[a.to] = true
			r.dist[a.to] = cand
			r.prev[a.to] = a.from
			r.relaxs++
			changed = true
			continue
		}
		if cand < r.dist[a.to] {
			// Strictly cheaper, never merely equal: a tie leaves the
			// incumbent predecessor in place, which is what makes Path
			// reproducible rather than dependent on arc order.
			r.dist[a.to] = cand
			r.prev[a.to] = a.from
			r.relaxs++
			changed = true
		}
	}
	return changed
}

// detectCycle runs the one extra pass that proves the answer. Any arc still
// able to improve a distance after V-1 passes is reachable from a negative
// cycle, so its head is a witness: everything the witness reaches is
// unbounded, and walking back from it lands on the cycle itself.
func (r *Result) detectCycle() {
	var witnesses []int
	for _, a := range r.arcs {
		if !r.reached[a.from] {
			continue
		}
		cand := r.dist[a.from] + a.weight
		if !r.reached[a.to] || cand < r.dist[a.to] {
			// Point the witness at the arc that beat it, so the walk back
			// below lands inside the cycle rather than beside it.
			r.reached[a.to] = true
			r.dist[a.to] = cand
			r.prev[a.to] = a.from
			witnesses = append(witnesses, a.to)
		}
	}
	if len(witnesses) == 0 {
		return
	}

	r.markUnbounded(witnesses)
	r.cycle = r.walkBackToCycle(witnesses[0])
}

// markUnbounded floods forward from the witnesses. A node a negative cycle can
// reach has no cheapest route, and that is true however far downstream it
// sits, so the flood follows arcs rather than stopping at the cycle.
func (r *Result) markUnbounded(witnesses []int) {
	queue := make([]int, 0, len(r.names))
	for _, w := range witnesses {
		if !r.unbounded[w] {
			r.unbounded[w] = true
			queue = append(queue, w)
		}
	}
	// An adjacency list built here rather than held on the Graph: this walk
	// is the only thing that needs one, and only when a cycle exists.
	adj := make([][]int, len(r.names))
	for _, a := range r.arcs {
		adj[a.from] = append(adj[a.from], a.to)
	}
	for len(queue) > 0 {
		u := queue[len(queue)-1]
		queue = queue[:len(queue)-1]
		for _, v := range adj[u] {
			if r.unbounded[v] {
				continue
			}
			r.unbounded[v] = true
			queue = append(queue, v)
		}
	}
}

// walkBackToCycle returns the negative cycle a witness sits downstream of, as
// a closed walk with the first node repeated last.
//
// Stepping back V times from a witness cannot leave the cycle: the witness is
// reachable from one, the predecessor chain enters it and never leaves, and V
// steps is more than the cycle is long. From there the chain is the cycle.
func (r *Result) walkBackToCycle(witness int) []int {
	at := witness
	for i := 0; i < len(r.names); i++ {
		if r.prev[at] == -1 {
			// Not reachable, so not a cycle. Defensive: a witness always has
			// a predecessor, by the assignment in detectCycle.
			return nil
		}
		at = r.prev[at]
	}

	var rev []int
	start := at
	for {
		rev = append(rev, at)
		at = r.prev[at]
		if at == start || at == -1 || len(rev) > len(r.names) {
			break
		}
	}
	if at != start {
		return nil
	}

	out := make([]int, 0, len(rev)+1)
	for i := len(rev) - 1; i >= 0; i-- {
		out = append(out, rev[i])
	}
	return append(out, out[0])
}

// at returns the index of a node State has already called Settled.
func (r *Result) at(nm string) int { return r.index[nm] }

// Source returns the node the run started from.
func (r *Result) Source() string { return r.names[r.src] }

// State reports what the run can say about one node. It is the call to make
// before Dist whenever the difference between "nothing reaches it" and "a
// negative cycle reaches it" changes what the caller does.
func (r *Result) State(nm string) State {
	i, known := r.index[nm]
	if !known || i >= len(r.names) {
		// A name the graph learned after From is unknown to this run: the
		// index is shared, but the Result's own slices stop at its snapshot.
		return Unknown
	}
	if r.unbounded[i] {
		return Unbounded
	}
	if !r.reached[i] {
		return Unreached
	}
	return Settled
}

// Dist returns the total weight of the cheapest route to nm, and whether one
// exists at all.
//
// The int returned with ok=false means NOTHING. There is no sentinel because
// there cannot be one: a negative total is a legitimate answer here, so any
// value this could return is also a value a real route could have. Call State
// when the reason matters.
func (r *Result) Dist(nm string) (int, bool) {
	if r.State(nm) != Settled {
		return 0, false
	}
	return r.dist[r.at(nm)], true
}

// Path returns the cheapest route to nm, source first and nm last. It returns
// nil whenever Dist would return ok=false, the unbounded case included: a
// route that can always be beaten is not a shortest path, and handing one back
// would be the lie this package is built to refuse.
func (r *Result) Path(nm string) []string {
	if r.State(nm) != Settled {
		return nil
	}
	var rev []int
	for at := r.at(nm); at != -1; at = r.prev[at] {
		rev = append(rev, at)
	}
	out := make([]string, len(rev))
	for k, at := range rev {
		out[len(rev)-1-k] = r.names[at]
	}
	return out
}

// PathString renders Path joined with sep, or "" when there is no route. It
// exists so a Render does not have to carry its own join loop.
func (r *Result) PathString(nm, sep string) string {
	p := r.Path(nm)
	if p == nil {
		return ""
	}
	return join(p, sep)
}

// Via returns the node immediately before nm on the cheapest route, and false
// for the source and for anything without one.
func (r *Result) Via(nm string) (string, bool) {
	if r.State(nm) != Settled {
		return "", false
	}
	p := r.prev[r.at(nm)]
	if p == -1 {
		return "", false
	}
	return r.names[p], true
}

// Reachable returns how many nodes a route leaves the source for, the source
// included and the unbounded ones counted: they are reached, they just have no
// cheapest route.
func (r *Result) Reachable() int {
	count := 0
	for _, ok := range r.reached {
		if ok {
			count++
		}
	}
	return count
}

// Rounds returns how many passes over the arc list the run made. The bound is
// V-1, and what decides the real figure is the order the arcs were added in,
// so this is the number to watch when gas matters.
//
// A run that settles early makes one more pass to prove nothing moved, and
// that pass is counted here. A run that needs the full V-1 instead pays the
// separate detection pass, which is not.
func (r *Result) Rounds() int { return r.rounds }

// Relaxations returns how many arcs actually improved a distance. It is the
// honest cost figure: the arc count times the round count is what was looked
// at, this is what was paid for.
func (r *Result) Relaxations() int { return r.relaxs }

// HasNegativeCycle reports whether a cycle whose arcs sum to less than zero is
// reachable from the source. A cycle elsewhere in the graph is not this run's
// problem and is not reported.
func (r *Result) HasNegativeCycle() bool { return len(r.cycle) > 0 }

// Cycle returns one negative cycle as a closed walk, first node repeated last,
// or nil when there is none. A graph may hold several; this is the one the
// first witness in arc order sits downstream of.
func (r *Result) Cycle() []string {
	if len(r.cycle) == 0 {
		return nil
	}
	out := make([]string, len(r.cycle))
	for i, at := range r.cycle {
		out[i] = r.names[at]
	}
	return out
}

// CycleWeight returns what one turn of the reported cycle costs, taking the
// cheapest arc for each hop, or 0 when there is no cycle. It is always
// negative when HasNegativeCycle is true, and that is worth asserting in a
// caller's test: it is the one number that proves the detection was real.
func (r *Result) CycleWeight() int {
	if len(r.cycle) < 2 {
		return 0
	}
	total := 0
	for i := 0; i+1 < len(r.cycle); i++ {
		total += r.cheapestArc(r.cycle[i], r.cycle[i+1])
	}
	return total
}

// cheapestArc returns the lowest weight among the arcs from -> to. The walk
// came from the predecessor chain, so at least one such arc always exists.
func (r *Result) cheapestArc(from, to int) int {
	best := 0
	found := false
	for _, a := range r.arcs {
		if a.from != from || a.to != to {
			continue
		}
		if !found || a.weight < best {
			best = a.weight
			found = true
		}
	}
	return best
}

// UnboundedNodes returns, in insertion order, every node a negative cycle
// reaches. It is empty when there is no cycle, and it is the blast radius: the
// nodes whose distance a less careful implementation would have reported.
func (r *Result) UnboundedNodes() []string {
	var out []string
	for i, u := range r.unbounded {
		if u {
			out = append(out, r.names[i])
		}
	}
	return out
}

// join concatenates with a separator. Written out rather than imported so the
// package keeps no dependency at all, not even strings.
func join(in []string, sep string) string {
	out := ""
	for i, s := range in {
		if i > 0 {
			out += sep
		}
		out += s
	}
	return out
}
