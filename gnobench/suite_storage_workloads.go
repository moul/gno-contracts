package main

func perN(n int) int     { return n }
func perHalfN(n int) int { return n / 2 }
func one(n int) int      { return 1 }

// kvBuild and listBuild are the bodies of phaseBuild. They take ks and pm so a
// warm scenario can pass main's own slices in, which makes the baseline
// subtraction exact.
const kvBuild = `	for i := 0; i < n; i++ {
		j := pm[i]
		opSet(ks[j], val(j))
	}
	if opSize() != n {
		panic("build size")
	}`

const listBuild = `	for i := 0; i < n; i++ {
		opPush(val(i))
	}
	if opSize() != n {
		panic("build size")
	}`

var storageWorkloads = []Workload{
	// ============ warm: the whole container in one run ============
	{
		Name: "build", Group: "kv", Mode: "warm", Baseline: "",
		Note: "the empty container: the realm's code and its declaration, nothing stored",
		Body: "\t_ = opSize()\n", Ops: one,
	},
	{
		Name: "insert_seq", Group: "kv", Mode: "warm", Baseline: "build",
		Note: "n inserts in ascending key order, the append-only case",
		Body: `	for i := 0; i < n; i++ {
		opSet(ks[i], val(i))
	}
	if opSize() != n {
		panic("size")
	}
`,
		Ops: perN,
	},
	{
		Name: "insert_rand", Group: "kv", Mode: "warm", Baseline: "build", Prebuilt: true,
		Note: "n inserts in random key order",
		Body: "", Ops: perN,
	},
	{
		Name: "get_hit", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "n point reads, every key present, all of them warm",
		Body: `	h := 0
	for i := 0; i < n; i++ {
		if opGet(ks[pm2[i]]) {
			h++
		}
	}
	if h != n {
		panic("hits")
	}
`,
		Ops: perN,
	},
	{
		Name: "get_miss", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "n point reads, no key present: the negative-lookup path",
		Body: `	for i := 0; i < n; i++ {
		if opGet("z" + ks[i]) {
			panic("miss")
		}
	}
`,
		Ops: perN,
	},
	{
		Name: "update_rand", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "n overwrites of existing keys: no new entries, only new values",
		Body: `	for i := 0; i < n; i++ {
		j := pm2[i]
		opSet(ks[j], val(j))
	}
	if opSize() != n {
		panic("size")
	}
`,
		Ops: perN,
	},
	{
		Name: "iterate_all", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "one full scan of every entry",
		Body: `	if opIter() != n {
		panic("iter")
	}
`,
		Ops: perN,
	},
	{
		Name: "range_scan", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "n/16 range scans of 16 consecutive keys each",
		Body: `	c := 0
	for i := 0; i+16 < n; i += 16 {
		c += opRange(ks[i], ks[i+16])
	}
	if c == 0 {
		panic("range")
	}
`,
		Ops: perN,
	},
	{
		Name: "offset_page", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "paginating the whole container in pages of 10 by offset",
		Body: `	c := 0
	for off := 0; off < n; off += 10 {
		c += opOffset(off, 10)
	}
	if c != n {
		panic("page")
	}
`,
		Ops: perN,
	},
	{
		Name: "remove_half", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "n/2 random deletes: the fragmentation case",
		Body: `	for i := 0; i < n/2; i++ {
		if !opDel(ks[pm2[i]]) {
			panic("del")
		}
	}
	if opSize() != n-n/2 {
		panic("size")
	}
`,
		Ops: perHalfN,
	},
	{
		Name: "remove_all", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "every key deleted: what the container gives back when emptied",
		Body: `	for i := 0; i < n; i++ {
		if !opDel(ks[i]) {
			panic("del")
		}
	}
	if opSize() != 0 {
		panic("size")
	}
`,
		Ops: perN,
	},
	{
		Name: "churn", Group: "kv", Mode: "warm", Baseline: "insert_rand", Prebuilt: true,
		Note: "n delete-and-insert pairs at constant size: steady-state turnover",
		Body: `	for i := 0; i < n; i++ {
		j := pm2[i]
		if !opDel(ks[j]) {
			panic("del")
		}
		opSet("c"+ks[j], val(j))
	}
	if opSize() != n {
		panic("size")
	}
`,
		Ops: perN,
	},

	// ============ cold: the container was committed one transaction ago ============
	{
		Name: "cold_base", Group: "kv", Mode: "cold", Baseline: "", Prebuilt: true,
		Note: "the container exists and this transaction has not touched it",
		Body: "", Ops: one,
	},
	{
		Name: "cold_get_all", Group: "kv", Mode: "cold", Baseline: "cold_base", Prebuilt: true,
		Note: "n point reads starting from a cold store: the first touch of each object deserialises it",
		Body: `	h := 0
	for i := 0; i < n; i++ {
		if opGet(ks[pm2[i]]) {
			h++
		}
	}
	if h != n {
		panic("hits")
	}
`,
		Ops: perN,
	},
	{
		Name: "cold_iterate", Group: "kv", Mode: "cold", Baseline: "cold_base", Prebuilt: true,
		Note: "one full scan from cold: every object in the container is deserialised",
		Body: `	if opIter() != n {
		panic("iter")
	}
`,
		Ops: perN,
	},
	{
		Name: "cold_update_all", Group: "kv", Mode: "cold", Baseline: "cold_base", Prebuilt: true,
		Note: "n overwrites from cold: read every object, write every object",
		Body: `	for i := 0; i < n; i++ {
		j := pm2[i]
		opSet(ks[j], val(j))
	}
`,
		Ops: perN,
	},

	// ============ one transaction, one operation: what a realm actually does ============
	{
		Name: "tx_base", Group: "kv", Mode: "cold", Light: true, Baseline: "", Prebuilt: true,
		Note: "a transaction that never touches the container, so nothing is loaded",
		Body: "", Ops: one,
	},
	{
		Name: "tx_read", Group: "kv", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE read, from cold. This is what a Render() of a single item costs",
		Body: `	if !opGet(k) {
		panic("read")
	}
`,
		Ops: one,
	},
	{
		Name: "tx_write", Group: "kv", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE overwrite of an existing key, from cold. This is what a Call() that edits one record costs",
		Body: "\topSet(k, v)\n", Ops: one,
	},
	{
		Name: "tx_insert", Group: "kv", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE new key, from cold",
		Body: "\topSet(\"zz\"+k, v)\n", Ops: one,
	},
	{
		Name: "tx_delete", Group: "kv", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE delete, from cold",
		Body: `	if !opDel(k) {
		panic("del")
	}
`,
		Ops: one,
	},
	{
		Name: "tx_page10", Group: "kv", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE page of 10 by offset, from cold: the paginated Render()",
		Body: `	if opOffset(n/2, 10) != 10 {
		panic("page")
	}
`,
		Ops: func(n int) int { return 10 },
	},

	// ============ positional, warm ============
	{
		Name: "build", Group: "list", Mode: "warm", Baseline: "",
		Note: "the empty list", Body: "\t_ = opSize()\n", Ops: one,
	},
	{
		Name: "append_n", Group: "list", Mode: "warm", Baseline: "build", Prebuilt: true,
		Note: "n appends", Body: "", Ops: perN,
	},
	{
		Name: "read_seq", Group: "list", Mode: "warm", Baseline: "append_n", Prebuilt: true,
		Note: "n index reads in order",
		Body: `	for i := 0; i < n; i++ {
		if !opAt(i) {
			panic("at")
		}
	}
`,
		Ops: perN,
	},
	{
		Name: "read_rand", Group: "list", Mode: "warm", Baseline: "append_n", Prebuilt: true,
		Note: "n index reads in random order",
		Body: `	for i := 0; i < n; i++ {
		if !opAt(pm2[i]) {
			panic("at")
		}
	}
`,
		Ops: perN,
	},
	{
		Name: "set_rand", Group: "list", Mode: "warm", Baseline: "append_n", Prebuilt: true,
		Note: "n in-place updates at random indices",
		Body: `	for i := 0; i < n; i++ {
		opSetAt(pm2[i], val(i))
	}
`,
		Ops: perN,
	},
	{
		Name: "iterate_all", Group: "list", Mode: "warm", Baseline: "append_n", Prebuilt: true,
		Note: "one full scan",
		Body: `	if opIter() != n {
		panic("iter")
	}
`,
		Ops: perN,
	},
	{
		Name: "delete_rand", Group: "list", Mode: "warm", Baseline: "append_n", Prebuilt: true,
		Note: "n/2 deletes at random indices, leaving holes",
		Body: `	for i := 0; i < n/2; i++ {
		opDelAt(pm2[i])
	}
`,
		Ops: perHalfN,
	},
	{
		Name: "delete_oldest", Group: "list", Mode: "warm", Baseline: "append_n", Prebuilt: true,
		Note: "n/2 deletes at the lowest indices",
		Body: `	for i := 0; i < n/2; i++ {
		opDelAt(i)
	}
`,
		Ops: perHalfN,
	},
	{
		Name: "compact_oldest", Group: "list", Mode: "warm", Baseline: "delete_oldest", Prebuilt: true,
		Note: "compaction after deleting the oldest half",
		Body: `	for i := 0; i < n/2; i++ {
		opDelAt(i)
	}
	_ = opCompact()
`,
		Ops: perHalfN,
	},
	{
		Name: "delete_newest", Group: "list", Mode: "warm", Baseline: "append_n", Prebuilt: true,
		Note: "n/2 deletes at the highest indices",
		Body: `	for i := n - 1; i >= n/2; i-- {
		opDelAt(i)
	}
`,
		Ops: perHalfN,
	},
	{
		Name: "compact_newest", Group: "list", Mode: "warm", Baseline: "delete_newest", Prebuilt: true,
		Note: "compaction after deleting the newest half: the leaves",
		Body: `	for i := n - 1; i >= n/2; i-- {
		opDelAt(i)
	}
	_ = opCompact()
`,
		Ops: perHalfN,
	},
	{
		Name: "compact", Group: "list", Mode: "warm", Baseline: "delete_rand", Prebuilt: true,
		Note: "reclaiming the holes that random deletion left",
		Body: `	for i := 0; i < n/2; i++ {
		opDelAt(pm2[i])
	}
	_ = opCompact()
`,
		Ops: perHalfN,
	},

	// ============ positional, one transaction ============
	{
		Name: "tx_base", Group: "list", Mode: "cold", Light: true, Baseline: "", Prebuilt: true,
		Note: "a transaction that never touches the list",
		Body: "", Ops: one,
	},
	{
		Name: "tx_at", Group: "list", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE index read, from cold",
		Body: `	if !opAt(n / 2) {
		panic("at")
	}
`,
		Ops: one,
	},
	{
		Name: "tx_push", Group: "list", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE append, from cold. This is what posting one message costs",
		Body: "\topPush(v)\n", Ops: one,
	},
	{
		Name: "tx_set_at", Group: "list", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE in-place update, from cold",
		Body: "\topSetAt(n/2, v)\n", Ops: one,
	},
	{
		Name: "tx_del_at", Group: "list", Mode: "cold", Light: true, Baseline: "tx_base", Prebuilt: true,
		Note: "ONE delete, from cold",
		Body: "\topDelAt(n / 2)\n", Ops: one,
	},
}

func init() {
	register(&Suite{
		Name:  "storage",
		Title: "Where a realm puts its data",
		Blurb: "Key/value containers and positional containers available to a gno realm, " +
			"measured warm (built and read in one run) and cold (built one transaction earlier, " +
			"then read against a committed store), on gas, realm storage bytes and wall time.",
		Structures: storageStructures,
		Workloads:  storageWorkloads,
		Facets: []Facet{
			{Key: "origin", Label: "Where it comes from", Values: []string{"builtin", "p/nt", "p/moul"}},
			{Key: "order", Label: "Iteration order", Values: []string{"key", "insertion", "index", "id", "none"}},
			{Key: "keys", Label: "Key type", Values: []string{"string", "comparable"}},
			{Key: "shape", Label: "Persisted shape", Values: []string{"single-object", "per-entry"}},
			{Key: "op", Label: "Supports", Values: []string{"range", "index", "delete", "compact", "stable-index", "multi-index", "clone", "pushfront"}},
		},
	})
}
