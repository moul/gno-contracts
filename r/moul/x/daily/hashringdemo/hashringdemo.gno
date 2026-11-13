// Package hashringdemo is a small gnoweb demo of the consistent hashing ring
// provided by the [p/moul/x/daily/hashring](/p/moul/x/daily/hashring/v0)
// library: where keys land, and how few of them move when the membership
// changes.
//
// It contains no placement logic of its own. Stateless, so Render is
// deterministic, which is what lets the migration table below be a measurement
// rather than an illustration.
package hashringdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/vendor/nt/ufmt/v2"
	"gno.land/p/moul/x/daily/hashring/v0"
)

// Fixed inputs, never chain state: a demo whose output moves with the block
// height cannot be pinned by an example test.
var (
	nodes = []string{"alpha", "beta", "gamma", "delta"}

	// leaving is the node the migration table takes out. Which one it is
	// matters to the numbers and to nothing else.
	leaving = "gamma"

	// keys is the workload. 2,000 is enough that the shares are stable to the
	// percent and small enough that rendering the page stays cheap.
	keys = buildKeys(2000)

	ring = build(nodes)
)

func buildKeys(n int) []string {
	out := make([]string, 0, n)
	for i := 0; i < n; i++ {
		out = append(out, "key-"+strconv.Itoa(i))
	}
	return out
}

func build(members []string) *hashring.Ring {
	r := hashring.New(hashring.DefaultReplicas)
	for _, n := range members {
		r.Add(n)
	}
	return r
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/")  -> the ring, the shares, and the migration cost
//	Render("/<key>")          -> place that key and show its preference list
func Render(path string) string {
	if arg := strings.TrimPrefix(path, "/"); arg != "" {
		return header() + renderKey(arg)
	}

	var b strings.Builder
	b.WriteString(header())

	b.WriteString(md.H2("The ring"))
	b.WriteString("\n`" + strconv.Itoa(len(nodes)) + "` nodes, `" +
		strconv.Itoa(ring.Replicas()) + "` virtual points each, `" +
		strconv.Itoa(ring.Len()) + "` points on the circle. ")
	b.WriteString("An even split of `" + strconv.Itoa(len(keys)) + "` keys would be `" +
		strconv.Itoa(len(keys)/len(nodes)) + "` apiece.\n\n")

	counts := placeAll(ring)
	t := ui.NewTable("node", "points", "keys", "share")
	for _, n := range nodes {
		t.Row(
			md.InlineCode(n),
			strconv.Itoa(ring.Replicas()),
			strconv.Itoa(counts[n]),
			pct(counts[n], len(keys)),
		)
	}
	b.WriteString(t.String())
	b.WriteString("\nWith one point per node instead of `" + strconv.Itoa(ring.Replicas()) +
		"`, this same workload puts 95% of the keys on " + md.InlineCode("delta") +
		" and 5 of them on " + md.InlineCode("alpha") + ". Four random cuts of a " +
		"circle are nothing like an even split; interleaving `" +
		strconv.Itoa(ring.Replicas()) + "` arcs per node is what fixes it.\n\n")

	b.WriteString(md.H2("Where a few keys land"))
	b.WriteString("\nThe owner, then the next two nodes clockwise, which is the " +
		"preference list a replicated store would write the copies to.\n\n")
	t = ui.NewTable("key", "position", "owner", "replicas")
	for _, k := range []string{"key-0", "key-1", "key-2", "key-7", "key-42"} {
		pref := ring.GetN(k, 3)
		t.Row(
			md.InlineCode(k),
			md.InlineCode(hex(hashring.Hash(k))),
			md.InlineCode(pref[0]),
			code(pref[1:]),
		)
	}
	b.WriteString(t.String())

	b.WriteString("\n")
	b.WriteString(md.H2("What it costs to lose a node"))
	b.WriteString("\nTaking " + md.InlineCode(leaving) + " out and placing the same `" +
		strconv.Itoa(len(keys)) + "` keys again.\n\n")
	b.WriteString(migrationTable())
	b.WriteString("\nThat is the whole argument. The ring moves the keys that have " +
		"to move and not one more, because their owner is a position on a circle " +
		"and the circle did not change. A modulo shard moves almost everything, " +
		"because the modulus moved under every key at once: nothing was wrong " +
		"with where `key-1` lived, only with how many nodes there are.\n\n")

	b.WriteString(md.H2("On chain"))
	b.WriteString("\nThe ring is a value, not realm state. This page builds one " +
		"per call and throws it away, and a realm that wanted to keep one would " +
		"store the membership, a handful of strings, and rebuild. Persisting `" +
		strconv.Itoa(ring.Len()) + "` sorted points to avoid a few hundred hashes " +
		"is the wrong trade when storage is the thing you are charged for.\n\n")

	b.WriteString("> Place your own key: append it to the path, for instance " +
		"[`/hello`](/r/moul/x/daily/hashringdemo/v0:/hello).\n")
	return b.String()
}

func header() string {
	return md.H1("Consistent hashing") +
		"\nKeys on a circle instead of `hash(key) % n`, demoing the " +
		"[`p/moul/x/daily/hashring`](/p/moul/x/daily/hashring/v0) library.\n\n"
}

// renderKey places the visitor's key.
//
// The argument reaches the page only inside a code span, through
// md.InlineCode: a cell escaper backslashes a backtick and a backslash does
// not close a backtick inside a span, so only a fence wider than anything in
// the argument does, which is what md.InlineCode picks. Every table cell below
// holds a derived value: a hash, or a node name from this realm's own fixed
// membership.
func renderKey(arg string) string {
	var b strings.Builder
	b.WriteString(md.H2(md.InlineCode(arg)))

	h := hashring.Hash(arg)
	pref := ring.GetN(arg, len(nodes))

	b.WriteString("\n")
	t := ui.NewTable("position", "owner", "then")
	t.Row(md.InlineCode(hex(h)), md.InlineCode(pref[0]), code(pref[1:]))
	b.WriteString(t.String())

	b.WriteString("\nThe position is SHA-256 of the key, first eight bytes. The " +
		"owner is the first virtual point at or clockwise of it, and the rest of " +
		"the row is the walk onwards, skipping points that belong to a node " +
		"already named.\n\n")

	without := build(remove(nodes, pref[0]))
	b.WriteString("Without " + md.InlineCode(pref[0]) + " this key would belong to " +
		md.InlineCode(without.Get(arg)) + ", and every key that did not live on " +
		md.InlineCode(pref[0]) + " would stay exactly where it is.\n\n")

	b.WriteString("> [Back to the ring](/r/moul/x/daily/hashringdemo/v0).\n")
	return b.String()
}

// migrationTable measures both strategies over the same keys: the ring, and
// the modulo shard the ring exists to replace.
func migrationTable() string {
	before := placements(ring)
	after := placements(build(remove(nodes, leaving)))

	ringMoved, strandedOnly := 0, 0
	for i := range keys {
		if before[i] != after[i] {
			ringMoved++
		}
		if before[i] == leaving {
			strandedOnly++
		}
	}

	modMoved := 0
	for _, k := range keys {
		h := hashring.Hash(k)
		was := nodes[int(h%uint64(len(nodes)))]
		shrunk := remove(nodes, leaving)
		now := shrunk[int(h%uint64(len(shrunk)))]
		if was != now {
			modMoved++
		}
	}

	t := ui.NewTable("strategy", "keys moved", "share", "unavoidable")
	t.Row(
		"consistent hashing",
		strconv.Itoa(ringMoved),
		pct(ringMoved, len(keys)),
		strconv.Itoa(strandedOnly),
	)
	t.Row(
		md.InlineCode("hash(key) % n"),
		strconv.Itoa(modMoved),
		pct(modMoved, len(keys)),
		strconv.Itoa(strandedOnly),
	)
	return t.String()
}

// placements maps every key, in key order.
func placements(r *hashring.Ring) []string {
	out := make([]string, 0, len(keys))
	for _, k := range keys {
		out = append(out, r.Get(k))
	}
	return out
}

// placeAll counts the keys each node owns.
func placeAll(r *hashring.Ring) map[string]int {
	counts := map[string]int{}
	for _, k := range keys {
		counts[r.Get(k)]++
	}
	return counts
}

// remove returns members without node, as a fresh slice: shortening one in
// place would hand back a view onto this realm's own package-level membership.
func remove(members []string, node string) []string {
	out := make([]string, 0, len(members))
	for _, m := range members {
		if m != node {
			out = append(out, m)
		}
	}
	return out
}

// code renders a node list as code spans. The nodes are this realm's own
// constants, never the caller's.
func code(names []string) string {
	parts := make([]string, 0, len(names))
	for _, n := range names {
		parts = append(parts, md.InlineCode(n))
	}
	return strings.Join(parts, ", ")
}

// pct renders n/total to one decimal place. Integer arithmetic throughout:
// this is a share of a count, and a float here would be a rounding question
// nobody asked.
func pct(n, total int) string {
	if total == 0 {
		return "0.0%"
	}
	tenths := n * 1000 / total
	return strconv.Itoa(tenths/10) + "." + strconv.Itoa(tenths%10) + "%"
}

// hex renders a ring position at constant width. ufmt/v2 rather than v0,
// which has no width flags and prints %X unhandled.
func hex(h uint64) string {
	return ufmt.Sprintf("%016x", h)
}
