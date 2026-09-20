package toposort

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// order asserts a successful sort and returns the joined result.
func order(t *testing.T, g *Graph) string {
	t.Helper()
	out, err := g.Sort()
	uassert.NoError(t, err)
	return strings.Join(out, ",")
}

func TestLinearChain(t *testing.T) {
	// c depends on b depends on a
	g := FromPairs([][2]string{{"c", "b"}, {"b", "a"}})
	uassert.Equal(t, "a,b,c", order(t, g))
}

func TestDependenciesComeFirst(t *testing.T) {
	g := FromPairs([][2]string{
		{"app", "lib"},
		{"lib", "core"},
		{"app", "core"},
	})
	uassert.Equal(t, "core,lib,app", order(t, g))
}

// Ties are broken lexicographically, so a given graph has exactly one answer —
// the property that keeps an on-chain Render stable.
func TestTiesAreLexicographic(t *testing.T) {
	g := New()
	for _, n := range []string{"delta", "alpha", "charlie", "bravo"} {
		g.Add(n)
	}
	uassert.Equal(t, "alpha,bravo,charlie,delta", order(t, g))
}

func TestResultIsIndependentOfInsertionOrder(t *testing.T) {
	a := FromPairs([][2]string{{"c", "b"}, {"b", "a"}, {"d", "a"}})
	b := FromPairs([][2]string{{"d", "a"}, {"b", "a"}, {"c", "b"}})
	uassert.Equal(t, order(t, a), order(t, b))
}

func TestIsolatedNodes(t *testing.T) {
	g := New()
	g.Add("solo")
	g.DependOn("b", "a")
	uassert.Equal(t, "a,b,solo", order(t, g))
}

func TestEmptyGraph(t *testing.T) {
	g := New()
	out, err := g.Sort()
	uassert.NoError(t, err)
	uassert.Equal(t, 0, len(out))
	uassert.Equal(t, 0, g.Len())
}

func TestCycleIsReported(t *testing.T) {
	g := FromPairs([][2]string{{"a", "b"}, {"b", "c"}, {"c", "a"}})
	out, err := g.Sort()
	uassert.Error(t, err)
	uassert.Equal(t, 0, len(out)) // nothing could start
	uassert.Equal(t, "a,b,c", strings.Join(g.CycleNodes(), ","))
}

// A cycle downstream of a healthy prefix still orders the prefix, and reports
// only the stuck part.
func TestPartialOrderBeforeCycle(t *testing.T) {
	g := FromPairs([][2]string{
		{"b", "a"}, // fine
		{"x", "y"}, // cycle…
		{"y", "x"}, // …here
	})
	out, err := g.Sort()
	uassert.Error(t, err)
	uassert.Equal(t, "a,b", strings.Join(out, ","))
	uassert.Equal(t, "x,y", strings.Join(g.CycleNodes(), ","))
}

func TestCycleNodesEmptyOnDAG(t *testing.T) {
	g := FromPairs([][2]string{{"b", "a"}})
	uassert.Equal(t, 0, len(g.CycleNodes()))
}

// A self-dependency is meaningless and must not deadlock the graph.
func TestSelfDependencyIgnored(t *testing.T) {
	g := New()
	g.DependOn("a", "a")
	uassert.Equal(t, "a", order(t, g))
	uassert.Equal(t, 0, len(g.DependenciesOf("a")))
}

func TestDuplicateEdgesCollapse(t *testing.T) {
	g := New()
	g.DependOn("b", "a")
	g.DependOn("b", "a")
	uassert.Equal(t, 1, len(g.DependenciesOf("b")))
	uassert.Equal(t, "a,b", order(t, g))
}

func TestEmptyNamesIgnored(t *testing.T) {
	g := New()
	g.Add("")
	g.DependOn("", "a")
	g.DependOn("a", "")
	uassert.Equal(t, 0, g.Len())
}

func TestNodesAndDependenciesAreCopies(t *testing.T) {
	g := FromPairs([][2]string{{"b", "a"}})
	ns := g.Nodes()
	ns[0] = "mutated"
	uassert.Equal(t, "a,b", strings.Join(g.Nodes(), ","))

	ds := g.DependenciesOf("b")
	ds[0] = "mutated"
	uassert.Equal(t, "a", strings.Join(g.DependenciesOf("b"), ","))
}

func TestString(t *testing.T) {
	g := FromPairs([][2]string{{"app", "lib"}, {"app", "core"}})
	uassert.Equal(t, "app <- core, lib\ncore\nlib\n", g.String())
}

// A wide diamond: both middles are ready at once and must come out sorted.
func TestDiamond(t *testing.T) {
	g := FromPairs([][2]string{
		{"top", "left"},
		{"top", "right"},
		{"left", "base"},
		{"right", "base"},
	})
	uassert.Equal(t, "base,left,right,top", order(t, g))
}
