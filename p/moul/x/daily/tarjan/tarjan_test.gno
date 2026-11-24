package tarjan

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// join renders a component list as "a,b|c" so a table can state the expected
// answer on one line, order included.
func join(comps [][]string) string {
	parts := make([]string, 0, len(comps))
	for _, c := range comps {
		parts = append(parts, strings.Join(c, ","))
	}
	return strings.Join(parts, "|")
}

func TestComponents(t *testing.T) {
	tests := []struct {
		name  string
		edges [][2]string
		want  string
	}{
		{
			name:  "empty graph",
			edges: nil,
			want:  "",
		},
		{
			name:  "single edge is two singletons, sink first",
			edges: [][2]string{{"a", "b"}},
			want:  "b|a",
		},
		{
			name:  "two mutually dependent nodes collapse",
			edges: [][2]string{{"a", "b"}, {"b", "a"}},
			want:  "a,b",
		},
		{
			name:  "three node cycle collapses whole",
			edges: [][2]string{{"a", "b"}, {"b", "c"}, {"c", "a"}},
			want:  "a,b,c",
		},
		{
			name:  "self loop is its own component",
			edges: [][2]string{{"a", "a"}},
			want:  "a",
		},
		{
			name:  "chain comes out in reverse topological order",
			edges: [][2]string{{"a", "b"}, {"b", "c"}, {"c", "d"}},
			want:  "d|c|b|a",
		},
		{
			// Tarjan's own 1972 example, relabelled: two cycles joined by
			// one edge, so the condensation has two nodes.
			name:  "two cycles joined one way",
			edges: [][2]string{{"a", "b"}, {"b", "a"}, {"b", "c"}, {"c", "d"}, {"d", "c"}},
			want:  "c,d|a,b",
		},
		{
			name:  "diamond has no cycle at all",
			edges: [][2]string{{"top", "left"}, {"top", "right"}, {"left", "bot"}, {"right", "bot"}},
			want:  "bot|left|right|top",
		},
		{
			name: "cycle with a tail hanging off it",
			edges: [][2]string{
				{"app", "core"}, {"core", "util"}, {"util", "core"}, {"core", "leaf"},
			},
			want: "leaf|core,util|app",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := FromPairs(tt.edges)
			uassert.Equal(t, tt.want, join(g.Components()))
		})
	}
}

// TestComponentsIsOrderIndependent is the determinism claim: the same edge set
// fed in a different order must produce byte-identical output, because a realm
// whose Render reshuffled between identical calls would be a consensus bug.
func TestComponentsIsOrderIndependent(t *testing.T) {
	forward := FromPairs([][2]string{
		{"a", "b"}, {"b", "a"}, {"b", "c"}, {"c", "d"}, {"d", "c"}, {"d", "e"},
	})
	backward := FromPairs([][2]string{
		{"d", "e"}, {"d", "c"}, {"c", "d"}, {"b", "c"}, {"b", "a"}, {"a", "b"},
	})
	uassert.Equal(t, join(forward.Components()), join(backward.Components()))
	uassert.Equal(t, "e|c,d|a,b", join(forward.Components()))
}

func TestComponentOf(t *testing.T) {
	g := FromPairs([][2]string{{"a", "b"}, {"b", "a"}, {"b", "c"}})

	uassert.Equal(t, "a,b", strings.Join(g.ComponentOf("a"), ","))
	uassert.Equal(t, "a,b", strings.Join(g.ComponentOf("b"), ","))
	uassert.Equal(t, "c", strings.Join(g.ComponentOf("c"), ","))
	uassert.Equal(t, 0, len(g.ComponentOf("nope")))
}

func TestCyclic(t *testing.T) {
	tests := []struct {
		name  string
		edges [][2]string
		want  bool
	}{
		{"empty", nil, false},
		{"single node", [][2]string{{"a", "a"}}, true},
		{"dag", [][2]string{{"a", "b"}, {"b", "c"}}, false},
		{"diamond", [][2]string{{"t", "l"}, {"t", "r"}, {"l", "b"}, {"r", "b"}}, false},
		{"mutual", [][2]string{{"a", "b"}, {"b", "a"}}, true},
		{"far away cycle", [][2]string{{"a", "b"}, {"b", "c"}, {"c", "d"}, {"d", "c"}}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			uassert.Equal(t, tt.want, FromPairs(tt.edges).Cyclic())
		})
	}
}

// TestSelfLoopIsCyclicButSizeOne is the edge case the component size alone gets
// wrong: a one-node component with an edge to itself is a cycle, and that is
// why Cyclic cannot just ask whether any component holds more than one node.
func TestSelfLoopIsCyclicButSizeOne(t *testing.T) {
	g := FromPairs([][2]string{{"a", "a"}})
	uassert.Equal(t, 1, len(g.Components()))
	uassert.Equal(t, 1, len(g.Components()[0]))
	uassert.True(t, g.Cyclic())
}

func TestAddAndEdge(t *testing.T) {
	g := New()
	g.Add("lonely")
	g.Edge("a", "b")
	g.Edge("b", "a")
	g.Edge("a", "b") // duplicate, must collapse

	uassert.Equal(t, "a,b,lonely", strings.Join(g.Nodes(), ","))
	// Two components that cannot reach each other are incomparable, so the
	// tie is broken by the walk order, which starts at the smallest name.
	uassert.Equal(t, "a,b|lonely", join(g.Components()))

	// Empty names are rejected rather than creating a "" node.
	g.Add("")
	g.Edge("", "a")
	g.Edge("a", "")
	uassert.Equal(t, "a,b,lonely", strings.Join(g.Nodes(), ","))
}

// TestNodesIsACopy pins that a caller cannot mutate the graph through the
// slice it was handed.
func TestNodesIsACopy(t *testing.T) {
	g := FromPairs([][2]string{{"a", "b"}})
	ns := g.Nodes()
	ns[0] = "clobbered"
	uassert.Equal(t, "a,b", strings.Join(g.Nodes(), ","))
}

func TestSuccessors(t *testing.T) {
	g := FromPairs([][2]string{{"a", "c"}, {"a", "b"}, {"b", "c"}})

	uassert.Equal(t, "b,c", strings.Join(g.Successors("a"), ","))
	uassert.Equal(t, "c", strings.Join(g.Successors("b"), ","))
	uassert.Equal(t, 0, len(g.Successors("c")))
	uassert.Equal(t, 0, len(g.Successors("nope")))
}

func TestString(t *testing.T) {
	g := FromPairs([][2]string{{"a", "b"}, {"b", "a"}, {"b", "c"}})
	uassert.Equal(t, "a -> b\nb -> a, c\nc\n", g.String())

	uassert.Equal(t, "", New().String())
}

// TestDeepChainDoesNotRecurse walks a 2000 node chain. Tarjan is usually
// written recursively and a graph this deep would need a 2000 frame call
// stack; this implementation keeps its own stack, so the only thing being
// asserted is that it returns at all.
func TestDeepChainDoesNotRecurse(t *testing.T) {
	const n = 2000
	g := New()
	prev := "n0"
	g.Add(prev)
	for i := 1; i < n; i++ {
		cur := "n" + itoa(i)
		g.Edge(prev, cur)
		prev = cur
	}

	comps := g.Components()
	uassert.Equal(t, n, len(comps))
	uassert.False(t, g.Cyclic())
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	var b []byte
	for i > 0 {
		b = append([]byte{byte('0' + i%10)}, b...)
		i /= 10
	}
	return string(b)
}
