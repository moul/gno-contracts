package main

// The storage suite: where a realm puts its data, and what that costs.
//
// Names are import paths on purpose. "avl" reads like a language feature;
// "p/nt/avl/v0" reads like what it is, a package with a version and an author,
// that a realm chooses and could choose differently.

const noRange = "no ordered range scan"

var storageStructures = []Structure{
	// ---------------- builtins ----------------
	{
		Name:  "builtin map[string]any",
		Group: "kv",
		Note:  "a native gno map in a realm var: one persisted object for the whole container",
		Tags:  []string{"origin:builtin", "order:insertion", "keys:comparable", "shape:single-object", "op:delete"},
		Decl:  `var t = map[string]any{}`,
		Ops: `func opSet(k string, v any) { t[k] = v }
func opGet(k string) bool   { _, ok := t[k]; return ok }
func opDel(k string) bool   { _, ok := t[k]; delete(t, k); return ok }
func opSize() int           { return len(t) }
func opIter() int {
	c := 0
	for _, v := range t {
		_ = v
		c++
	}
	return c
}
func opRange(a, b string) int { panic("unsupported") }
func opOffset(off, count int) int {
	c, i := 0, 0
	for _, v := range t {
		_ = v
		if i >= off && c < count {
			c++
		}
		i++
	}
	return c
}`,
		Skip: map[string]string{"range_scan": noRange},
	},
	{
		Name:   "builtin map[string]string",
		Group:  "kv",
		Note:   "the same map with the any box removed",
		Tags:   []string{"origin:builtin", "order:insertion", "keys:comparable", "shape:single-object", "op:delete"},
		Values: []string{"str"},
		Decl:   `var t = map[string]string{}`,
		Ops: `func opSet(k string, v any) { t[k] = v.(string) }
func opGet(k string) bool   { _, ok := t[k]; return ok }
func opDel(k string) bool   { _, ok := t[k]; delete(t, k); return ok }
func opSize() int           { return len(t) }
func opIter() int {
	c := 0
	for _, v := range t {
		_ = v
		c++
	}
	return c
}
func opRange(a, b string) int { panic("unsupported") }
func opOffset(off, count int) int {
	c, i := 0, 0
	for _, v := range t {
		_ = v
		if i >= off && c < count {
			c++
		}
		i++
	}
	return c
}`,
		Skip: map[string]string{"range_scan": noRange},
	},
	{
		Name:  "builtin []struct, sorted",
		Group: "kv",
		Note:  "sorted slice, binary search, memmove on insert",
		Tags:  []string{"origin:builtin", "order:key", "keys:string", "shape:single-object", "op:range", "op:index", "op:delete"},
		Decl: `type kv struct {
	K string
	V any
}

var t []kv`,
		Ops: sortedSliceOps("nil"),
	},
	{
		Name:  "builtin []struct, linear scan",
		Group: "kv",
		Note:  "append to a slice, find by walking it",
		Tags:  []string{"origin:builtin", "order:insertion", "keys:string", "shape:single-object", "op:index", "op:delete"},
		Decl: `type kv struct {
	K string
	V any
}

var t []kv`,
		Ops: `func find(k string) int {
	for i := 0; i < len(t); i++ {
		if t[i].K == k {
			return i
		}
	}
	return -1
}
func opSet(k string, v any) {
	if i := find(k); i >= 0 {
		t[i].V = v
		return
	}
	t = append(t, kv{k, v})
}
func opGet(k string) bool { return find(k) >= 0 }
func opDel(k string) bool {
	i := find(k)
	if i < 0 {
		return false
	}
	t = append(t[:i], t[i+1:]...)
	return true
}
func opSize() int { return len(t) }
func opIter() int {
	c := 0
	for i := 0; i < len(t); i++ {
		if t[i].K != "" && t[i].V != nil {
			c++
		}
	}
	return c
}
func opRange(a, b string) int { panic("unsupported") }
func opOffset(off, count int) int {
	c := 0
	for i := off; i < off+count && i < len(t); i++ {
		if t[i].K != "" {
			c++
		}
	}
	return c
}`,
		Skip: map[string]string{"range_scan": noRange},
	},

	// ---------------- p/nt ----------------
	{
		Name:    "p/nt/avl/v0",
		Group:   "kv",
		Note:    "the ecosystem default: a leaf-oriented AVL tree, 2n-1 node objects",
		Tags:    []string{"origin:p/nt", "order:key", "keys:string", "shape:per-entry", "op:range", "op:index", "op:delete"},
		Imports: []string{`"gno.land/p/nt/avl/v0"`},
		Decl:    `var t = avl.NewTree()`,
		Ops:     treeOps(true),
	},
	{
		Name:    "p/nt/bptree/v0 fanout=4",
		Group:   "kv",
		Tags:    []string{"origin:p/nt", "order:key", "keys:string", "shape:per-entry", "op:range", "op:index", "op:delete"},
		Imports: []string{`"gno.land/p/nt/bptree/v0"`},
		Decl:    `var t = bptree.NewBPTreeN(4)`,
		Ops:     treeOps(true),
	},
	{
		Name:    "p/nt/bptree/v0 fanout=8",
		Group:   "kv",
		Tags:    []string{"origin:p/nt", "order:key", "keys:string", "shape:per-entry", "op:range", "op:index", "op:delete"},
		Imports: []string{`"gno.land/p/nt/bptree/v0"`},
		Decl:    `var t = bptree.NewBPTreeN(8)`,
		Ops:     treeOps(true),
	},
	{
		Name:    "p/nt/bptree/v0 fanout=32",
		Group:   "kv",
		Note:    "the package default",
		Tags:    []string{"origin:p/nt", "order:key", "keys:string", "shape:per-entry", "op:range", "op:index", "op:delete"},
		Imports: []string{`"gno.land/p/nt/bptree/v0"`},
		Decl:    `var t = bptree.NewBPTree32()`,
		Ops:     treeOps(true),
	},
	{
		Name:    "p/nt/bptree/v0 fanout=128",
		Group:   "kv",
		Tags:    []string{"origin:p/nt", "order:key", "keys:string", "shape:per-entry", "op:range", "op:index", "op:delete"},
		Imports: []string{`"gno.land/p/nt/bptree/v0"`},
		Decl:    `var t = bptree.NewBPTreeN(128)`,
		Ops:     treeOps(true),
	},
	{
		Name:    "256x p/nt/avl/v0, hash-sharded",
		Group:   "kv",
		Note:    "256 AVL trees, key routed by FNV-1a: no global order",
		Tags:    []string{"origin:p/nt", "order:none", "keys:string", "shape:per-entry", "op:delete"},
		Imports: []string{`"gno.land/p/nt/avl/v0"`},
		Decl: `const shards = 256

var t = func() []*avl.Tree {
	s := make([]*avl.Tree, shards)
	for i := range s {
		s[i] = avl.NewTree()
	}
	return s
}()`,
		Ops: `func bucket(k string) *avl.Tree {
	h := uint32(2166136261)
	for i := 0; i < len(k); i++ {
		h ^= uint32(k[i])
		h *= 16777619
	}
	return t[int(h%shards)]
}
func opSet(k string, v any) { bucket(k).Set(k, v) }
func opGet(k string) bool   { return bucket(k).Get(k) != nil }
func opDel(k string) bool   { _, ok := bucket(k).Remove(k); return ok }
func opSize() int {
	c := 0
	for i := 0; i < shards; i++ {
		c += t[i].Size()
	}
	return c
}
func opIter() int {
	c := 0
	for i := 0; i < shards; i++ {
		t[i].Iterate("", "", func(k string, v any) bool { c++; return false })
	}
	return c
}
func opRange(a, b string) int     { panic("unsupported") }
func opOffset(off, count int) int { panic("unsupported") }`,
		Skip: map[string]string{"range_scan": noRange, "offset_page": "no global order across shards", "tx_page10": "no global order across shards"},
	},

	// ---------------- p/moul ----------------
	{
		Name:    "p/moul/cow/v0",
		Group:   "kv",
		Note:    "copy-on-write AVL with structural sharing and Clone",
		Tags:    []string{"origin:p/moul", "order:key", "keys:string", "shape:per-entry", "op:range", "op:index", "op:delete", "op:clone"},
		Imports: []string{`"gno.land/p/moul/cow/v0"`},
		Decl:    `var t = cow.NewTree()`,
		Ops:     treeOps(false),
	},
	{
		Name:    "p/moul/x/daily/orderedmap/v0",
		Group:   "kv",
		Note:    "a map plus a key slice: insertion order, positional access",
		Tags:    []string{"origin:p/moul", "order:insertion", "keys:string", "shape:single-object", "op:index", "op:delete"},
		Imports: []string{`"gno.land/p/moul/x/daily/orderedmap/v0"`},
		Values:  []string{"str"},
		Decl:    `var t = orderedmap.New()`,
		Ops: `func opSet(k string, v any) { t.Set(k, v.(string)) }
func opGet(k string) bool   { _, ok := t.Get(k); return ok }
func opDel(k string) bool   { return t.Delete(k) }
func opSize() int           { return t.Len() }
func opIter() int {
	c := 0
	t.Iterate(func(k, v string) bool { c++; return false })
	return c
}
func opRange(a, b string) int { panic("unsupported") }
func opOffset(off, count int) int {
	c := 0
	for i := off; i < off+count && i < t.Len(); i++ {
		if _, _, ok := t.At(i); ok {
			c++
		}
	}
	return c
}`,
		Skip: map[string]string{"range_scan": noRange},
	},
	{
		Name:    "p/moul/x/daily/flatmap/v0",
		Group:   "kv",
		Note:    "two parallel sorted slices: key order and range without a tree",
		Tags:    []string{"origin:p/moul", "order:key", "keys:string", "shape:single-object", "op:range", "op:index", "op:delete"},
		Imports: []string{`"gno.land/p/moul/x/daily/flatmap/v0"`},
		Values:  []string{"str"},
		Decl:    `var t = flatmap.New()`,
		Ops: `func opSet(k string, v any) { t.Set(k, v.(string)) }
func opGet(k string) bool   { _, ok := t.Get(k); return ok }
func opDel(k string) bool   { return t.Delete(k) }
func opSize() int           { return t.Len() }
func opIter() int {
	c := 0
	t.Iterate(func(k, v string) bool { c++; return false })
	return c
}
func opRange(a, b string) int {
	c := 0
	t.Range(a, b, func(k, v string) bool { c++; return false })
	return c
}
func opOffset(off, count int) int {
	c := 0
	for i := off; i < off+count && i < t.Len(); i++ {
		if _, _, ok := t.At(i); ok {
			c++
		}
	}
	return c
}`,
	},
	{
		Name:    "p/moul/collection/v0",
		Group:   "kv",
		Note:    "a multi-index record store, measured with one extra unique index",
		Tags:    []string{"origin:p/moul", "order:id", "keys:string", "shape:per-entry", "op:index", "op:delete", "op:multi-index"},
		Imports: []string{`"gno.land/p/moul/collection/v0"`, `"gno.land/p/nt/seqid/v0"`},
		Decl: `type crec struct {
	K string
	V any
}

var t = func() *collection.Collection {
	c := collection.New()
	c.AddIndex("k", func(o any) string { return o.(*crec).K }, collection.UniqueIndex)
	return c
}()`,
		Ops: `func idOf(e *collection.Entry) uint64 {
	id, err := seqid.FromString(e.ID)
	if err != nil {
		panic("collection: Entry.ID does not decode as a seqid")
	}
	return uint64(id)
}
func opSet(k string, v any) {
	if e := t.GetFirst("k", k); e != nil {
		if !t.Update(idOf(e), &crec{k, v}) {
			panic("update")
		}
		return
	}
	if t.Set(&crec{k, v}) == 0 {
		panic("set")
	}
}
func opGet(k string) bool { return t.GetFirst("k", k) != nil }
func opDel(k string) bool {
	e := t.GetFirst("k", k)
	if e == nil {
		return false
	}
	return t.Delete(idOf(e))
}
func opSize() int { return t.GetIndex(collection.IDIndex).Size() }
func opIter() int {
	c := 0
	t.GetIndex(collection.IDIndex).Iterate("", "", func(k string, v any) bool { c++; return false })
	return c
}
func opRange(a, b string) int { panic("unsupported") }
func opOffset(off, count int) int {
	c := 0
	t.GetIndex(collection.IDIndex).IterateByOffset(off, count, func(k string, v any) bool { c++; return false })
	return c
}`,
		Skip: map[string]string{"range_scan": "the index tree keys are not the caller's keys"},
	},

	// ---------------- positional ----------------
	{
		Name:  "builtin []any",
		Group: "list",
		Note:  "a plain slice in a realm var",
		Tags:  []string{"origin:builtin", "order:index", "shape:single-object", "op:index"},
		Decl:  `var l []any`,
		Ops: `func opPush(v any)         { l = append(l, v) }
func opAt(i int) bool      { return l[i] != nil }
func opSetAt(i int, v any) { l[i] = v }
func opDelAt(i int)        { l[i] = nil }
func opSize() int          { return len(l) }
func opIter() int {
	c := 0
	for i := 0; i < len(l); i++ {
		if l[i] != nil {
			c++
		}
	}
	return c
}
func opCompact() int { return 0 }`,
		Skip: sliceNoCompact,
	},
	{
		Name:   "builtin []string",
		Group:  "list",
		Note:   "the same slice with the any box removed",
		Tags:   []string{"origin:builtin", "order:index", "shape:single-object", "op:index"},
		Values: []string{"str"},
		Decl:   `var l []string`,
		Ops: `func opPush(v any)         { l = append(l, v.(string)) }
func opAt(i int) bool      { return l[i] != "" }
func opSetAt(i int, v any) { l[i] = v.(string) }
func opDelAt(i int)        { l[i] = "" }
func opSize() int          { return len(l) }
func opIter() int {
	c := 0
	for i := 0; i < len(l); i++ {
		if l[i] != "" {
			c++
		}
	}
	return c
}
func opCompact() int { return 0 }`,
		Skip: sliceNoCompact,
	},
	{
		Name:    "p/moul/ulist/v1",
		Group:   "list",
		Note:    "append-only tree with stable indices and index-preserving compaction",
		Tags:    []string{"origin:p/moul", "order:index", "shape:per-entry", "op:index", "op:delete", "op:compact", "op:stable-index"},
		Imports: []string{`"gno.land/p/moul/ulist/v1"`},
		Decl:    `var l = ulist.New()`,
		Ops: `func opPush(v any)         { l.Append(v) }
func opAt(i int) bool      { return l.Get(i) != nil }
func opSetAt(i int, v any) { l.MustSet(i, v) }
func opDelAt(i int)        { l.MustDelete(i) }
func opSize() int          { return l.Size() }
func opIter() int {
	c := 0
	l.Iterator(0, l.TotalSize()-1, func(i int, v any) bool { c++; return false })
	return c
}
func opCompact() int { return l.Compact() }`,
	},
	{
		Name:    "p/moul/deque/v0",
		Group:   "list",
		Note:    "a doubly linked list: one node object per element",
		Tags:    []string{"origin:p/moul", "order:index", "shape:per-entry", "op:pushfront"},
		Imports: []string{`"gno.land/p/moul/deque/v0"`},
		Decl:    `var l = deque.New()`,
		Ops: `func opPush(v any)         { l.PushBack(v) }
func opAt(i int) bool      { return l.Get(i) != nil }
func opSetAt(i int, v any) {}
func opDelAt(i int)        {}
func opSize() int          { return l.Size() }
func opIter() int {
	c := 0
	l.Enumerate(func(i int, v any) bool { c++; return false })
	return c
}
func opCompact() int { return 0 }`,
		Skip: map[string]string{
			"set_rand": "no positional Set", "delete_rand": "no positional Delete",
			"delete_oldest": "no positional Delete", "delete_newest": "no positional Delete",
			"compact": "no compaction", "compact_oldest": "no compaction", "compact_newest": "no compaction",
			"tx_set_at": "no positional Set", "tx_del_at": "no positional Delete",
		},
	},
	{
		Name:    "p/moul/kit/store/v0",
		Group:   "list",
		Note:    "id-keyed store over a tree: ids survive deletion, indices are not positions",
		Tags:    []string{"origin:p/moul", "order:id", "shape:per-entry", "op:delete", "op:stable-index"},
		Imports: []string{`"gno.land/p/moul/kit/store/v0"`},
		Decl:    `var l = store.New()`,
		Ops: `func opPush(v any)         { l.Add(v) }
func opAt(i int) bool      { _, ok := l.Get(store.ID(i + 1)); return ok }
func opSetAt(i int, v any) { l.Set(store.ID(i+1), v) }
func opDelAt(i int)        { l.Remove(store.ID(i + 1)) }
func opSize() int          { return l.Len() }
func opIter() int {
	c := 0
	l.Each(func(id store.ID, v any) { c++ })
	return c
}
func opCompact() int { return 0 }`,
		Skip: map[string]string{
			"compact":        "nothing to compact, ids are not positions",
			"compact_oldest": "nothing to compact, ids are not positions",
			"compact_newest": "nothing to compact, ids are not positions",
		},
	},
}

var sliceNoCompact = map[string]string{
	"compact":        "no compaction, a slice never reclaims a slot",
	"compact_oldest": "no compaction, a slice never reclaims a slot",
	"compact_newest": "no compaction, a slice never reclaims a slot",
}

// treeOps is the op set for anything with the avl/bptree shape. getTwo is true
// where Get returns a single any (p/nt), false where it returns (any, bool)
// (p/moul/cow).
func treeOps(singleGet bool) string {
	get := `func opGet(k string) bool   { _, ok := t.Get(k); return ok }`
	if singleGet {
		get = `func opGet(k string) bool   { return t.Get(k) != nil }`
	}
	return `func opSet(k string, v any) { t.Set(k, v) }
` + get + `
func opDel(k string) bool   { _, ok := t.Remove(k); return ok }
func opSize() int           { return t.Size() }
func opIter() int {
	c := 0
	t.Iterate("", "", func(k string, v any) bool { c++; return false })
	return c
}
func opRange(a, b string) int {
	c := 0
	t.Iterate(a, b, func(k string, v any) bool { c++; return false })
	return c
}
func opOffset(off, count int) int {
	c := 0
	t.IterateByOffset(off, count, func(k string, v any) bool { c++; return false })
	return c
}`
}

// sortedSliceOps is shared by the any-valued and string-valued sorted slices.
func sortedSliceOps(empty string) string {
	cmp := `t[i].V != nil`
	set := `t[i].V = v`
	lit := `kv{k, v}`
	if empty == `""` {
		cmp = `t[i].V != ""`
		set = `t[i].V = v.(string)`
		lit = `kv{k, v.(string)}`
	}
	return `func lower(k string) int {
	lo, hi := 0, len(t)
	for lo < hi {
		mid := (lo + hi) / 2
		if t[mid].K < k {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}
func opSet(k string, v any) {
	i := lower(k)
	if i < len(t) && t[i].K == k {
		` + set + `
		return
	}
	t = append(t, kv{})
	copy(t[i+1:], t[i:])
	t[i] = ` + lit + `
}
func opGet(k string) bool {
	i := lower(k)
	return i < len(t) && t[i].K == k
}
func opDel(k string) bool {
	i := lower(k)
	if i >= len(t) || t[i].K != k {
		return false
	}
	t = append(t[:i], t[i+1:]...)
	return true
}
func opSize() int { return len(t) }
func opIter() int {
	c := 0
	for i := 0; i < len(t); i++ {
		if t[i].K != "" && ` + cmp + ` {
			c++
		}
	}
	return c
}
func opRange(a, b string) int {
	c := 0
	for i := lower(a); i < len(t) && t[i].K < b; i++ {
		if t[i].K != "" {
			c++
		}
	}
	return c
}
func opOffset(off, count int) int {
	c := 0
	for i := off; i < off+count && i < len(t); i++ {
		if t[i].K != "" {
			c++
		}
	}
	return c
}`
}
