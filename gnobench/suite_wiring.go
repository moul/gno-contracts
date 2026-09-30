package main

// The wiring suite: what it costs to make the same change across many
// transactions instead of one.
//
// Ten thousand writes in one transaction and ten thousand writes across ten
// thousand transactions end at the same state, so the chain charges the same
// storage deposit for both. They are not the same thing for the node. A commit
// flushes every key the transaction touched, so N transactions each walking
// one path rewrite that path N times, and a container held in a single
// persisted object rewrites all of it on every single write.
//
// Nothing in the storage suite can see this: a filetest commits once. This one
// drives the VM directly, one committed transaction at a time, with the
// key/value store wrapped in a counter.
//
// Candidates carry realm source rather than an op set, because each one has to
// expose a crossing function a transaction can call.

type wiringCandidate struct {
	Name string
	Note string
	Tags []string
	Src  string
}

var wiringCandidates = []wiringCandidate{
	{
		Name: "builtin []string",
		Note: "one persisted array: every append rewrites all of it",
		Tags: []string{"origin:builtin", "shape:single-object", "order:index"},
		Src: `package wire

var t []string

func Set(cur realm, k, v string) { t = append(t, v) }
func Size(cur realm) int         { return len(t) }
`,
	},
	{
		Name: "builtin map[string]string",
		Note: "one persisted object: every write rewrites the whole map",
		Tags: []string{"origin:builtin", "shape:single-object", "order:insertion"},
		Src: `package wire

var t = map[string]string{}

func Set(cur realm, k, v string) { t[k] = v }
func Size(cur realm) int         { return len(t) }
`,
	},
	{
		Name: "p/nt/avl/v0",
		Note: "a write touches one root-to-leaf path, not the container",
		Tags: []string{"origin:p/nt", "shape:per-entry", "order:key"},
		Src: `package wire

import "gno.land/p/nt/avl/v0"

var t = avl.NewTree()

func Set(cur realm, k, v string) { t.Set(k, v) }
func Size(cur realm) int         { return t.Size() }
`,
	},
	{
		Name: "p/nt/bptree/v0 fanout=32",
		Note: "one path again, but wider nodes: fewer objects, each bigger",
		Tags: []string{"origin:p/nt", "shape:per-entry", "order:key"},
		Src: `package wire

import "gno.land/p/nt/bptree/v0"

var t = bptree.NewBPTree32()

func Set(cur realm, k, v string) { t.Set(k, v) }
func Size(cur realm) int         { return t.Size() }
`,
	},
	{
		Name: "p/nt/bptree/v0 fanout=128",
		Note: "wider still: the fanout that wins on deposit, measured on writes",
		Tags: []string{"origin:p/nt", "shape:per-entry", "order:key"},
		Src: `package wire

import "gno.land/p/nt/bptree/v0"

var t = bptree.NewBPTreeN(128)

func Set(cur realm, k, v string) { t.Set(k, v) }
func Size(cur realm) int         { return t.Size() }
`,
	},
	{
		Name: "p/moul/ulist/v1",
		Note: "an append-only tree: a write touches a path, not the list",
		Tags: []string{"origin:p/moul", "shape:per-entry", "order:index"},
		Src: `package wire

import "gno.land/p/moul/ulist/v1"

var t = ulist.New()

func Set(cur realm, k, v string) { t.Append(v) }
func Size(cur realm) int         { return t.Size() }
`,
	},
}

// The two shapes every candidate is measured in. Same writes, same final
// state, different number of commits.
const (
	shapeOneTx = "one_tx"
	shapePerTx = "tx_each"
)

func init() {
	register(&Suite{
		Name:  "wiring",
		Title: "What it costs to write one change at a time",
		Blurb: "The same n writes, batched into one transaction and spread across n transactions. " +
			"Both end at the same state, so the chain charges the same storage deposit for both. " +
			"What differs is what the node is asked to write, because every commit flushes every " +
			"key its transaction touched.",
		SizeLabel: "writes",
		OpLabel:   "write",
		HowToRead: `| axis | where it comes from | what it means |
|---|---|---|
| **deposit** | ` + "`Store.RealmStorageDiffs()`" + ` | the realm's net state change, which is what the chain charges at 100 ugnot/byte. **Identical between the two shapes**, by construction |
| **kv bytes** | a counter wrapped around the commit store | what the key/value store was asked to write, summed over every commit. This is what the node's disk absorbs |
| **kv sets** | the same counter | how many individual keys were written |
| **gas** | the VM's meter | comparable between rows, **not** mainnet gas |

The deploy transaction is measured and discarded: counting it would flatter the batched shape,
which pays it once alongside far fewer commits.

Each transaction is built the way the VM keeper builds a ` + "`MsgCall`" + `: its own cache wrap over the
commit store, its own gno transaction store (which starts with an empty object cache), and the
compiler-internal ` + "`.origin`" + ` sentinel in the crossing slot. Then both layers are written, which
is the commit.
`,
		Facets: []Facet{
			{Key: "shape", Label: "Persisted shape", Values: []string{"single-object", "per-entry"}},
			{Key: "origin", Label: "Where it comes from", Values: []string{"builtin", "p/nt", "p/moul"}},
			{Key: "order", Label: "Iteration order", Values: []string{"key", "insertion", "index"}},
		},
	})
}
