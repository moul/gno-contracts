package toolbox

import "gno.land/p/nt/bptree/v0"

// Catalog is the directory itself: tools keyed by slug, ordered by it.
//
// The zero value is an empty, usable catalog. A Catalog is a HANDLE: copying
// one shares the directory, and a write through either copy is seen through
// both, the way copying a map does. A copy of a zero value that was never
// written is a separate empty catalog.
//
// # Why a tree and not a sorted slice
//
// A sorted slice is cheaper to READ at the size a directory actually reaches:
// at n = 100 one cold operation costs 92,571 gas against a fanout-128 tree's
// 230,754 (`gnobench`, gno master 1fc4c140e, 2026-09-29). It is still the
// wrong structure, for two reasons that outlive the gas.
//
// A slice is ONE persisted object, so every write rewrites all of it: O(n) per
// transaction and O(n^2) over n of them. That costs nothing for a hub whose
// catalog is compiled in and never written after deploy, and it is the whole
// bill for one that accepts registration, which is the other half of what this
// package is for. Removing is worse than writing: shortening a slice in place
// keeps the peak allocation charged and refunds no deposit at all.
//
// And the ordering comes free. A slug-keyed tree iterates in slug order, which
// is the order every listing here wants, rather than a hand-rolled binary
// search that has to be kept correct.
type Catalog struct {
	s *state
}

// state is everything a Catalog holds, behind one pointer so that a copy of
// the handle cannot split the tree from the counter that describes it.
//
// Embedding [bptree.BPTree] by value was the first shape here and it is wrong
// for exactly that reason: the tree's root is a pointer and its size is an int,
// so `b := a; b.Set(x)` would thread the new node onto the tree both of them
// see while incrementing only b's size. a.Len() would say 1 while a.Get(x)
// found the entry. One pointer, or two readers of the same directory disagree
// about how big it is.
type state struct {
	tools *bptree.BPTree
}

// Fanout is the B+ tree fanout this package uses.
//
// 32 rather than 128 because a tool can be unregistered, and wide nodes lose
// most on removal: a removal shifts every later value in its leaf and rewrites
// each one. Same choice, and the same reason, as
// [gno.land/p/moul/kit/index](/p/moul/kit/index/v0).
const Fanout = 32

// New returns an empty catalog. It is the zero value, spelled out for a caller
// who prefers a constructor.
func New() *Catalog { return &Catalog{} }

// init materialises the state. Called by every mutating method, so the zero
// value works without a constructor. The tree is created with the state, so a
// non-nil state always has one.
func (c *Catalog) init() {
	if c.s == nil {
		c.s = &state{tools: bptree.NewBPTreeN(Fanout)}
	}
}

// Set inserts t, replacing any tool already under its slug.
//
// Replacing rather than refusing is what makes a hub's init idempotent: a
// compiled-in catalog is rebuilt from source on every redeploy, and a second
// Set of the same slug is a corrected description rather than a collision.
func (c *Catalog) Set(t Tool) error {
	if err := t.Validate(); err != nil {
		return err
	}
	c.init()
	c.s.tools.Set(t.Slug, copyTool(t))
	return nil
}

// Remove deletes the tool under slug. It returns [ErrUnknownSlug] when there
// is none, so a realm removing an entry it believes in learns that it is gone.
func (c *Catalog) Remove(slug string) error {
	if c.s == nil {
		return ErrUnknownSlug
	}
	if _, removed := c.s.tools.Remove(slug); !removed {
		return ErrUnknownSlug
	}
	return nil
}

// Get returns the tool under slug.
func (c *Catalog) Get(slug string) (Tool, bool) {
	if c.s == nil {
		return Tool{}, false
	}
	v := c.s.tools.Get(slug)
	if v == nil {
		return Tool{}, false
	}
	return copyTool(v.(Tool)), true
}

// Has reports whether slug is in the catalog.
func (c *Catalog) Has(slug string) bool {
	return c.s != nil && c.s.tools.Has(slug)
}

// Len is how many tools the catalog holds.
func (c *Catalog) Len() int {
	if c.s == nil {
		return 0
	}
	return c.s.tools.Size()
}

// List returns every tool, in slug order.
func (c *Catalog) List() []Tool {
	if c.s == nil {
		return nil
	}
	out := make([]Tool, 0, c.s.tools.Size())
	c.s.tools.Iterate("", "", func(_ string, v any) bool {
		out = append(out, copyTool(v.(Tool)))
		return false
	})
	return out
}

// ByTag returns every tool carrying tag, in slug order. An empty tag matches
// nothing rather than everything: it is almost always an unset field.
func (c *Catalog) ByTag(tag string) []Tool {
	if tag == "" || c.s == nil {
		return nil
	}
	var out []Tool
	c.s.tools.Iterate("", "", func(_ string, v any) bool {
		if t := v.(Tool); t.HasTag(tag) {
			out = append(out, copyTool(t))
		}
		return false
	})
	return out
}

// Tags returns every tag used by any tool, each once, in first-seen order
// within slug order. Deterministic, which iterating a map would not be.
func (c *Catalog) Tags() []string {
	if c.s == nil {
		return nil
	}
	var out []string
	c.s.tools.Iterate("", "", func(_ string, v any) bool {
		for _, tag := range v.(Tool).Tags {
			if !contains(out, tag) {
				out = append(out, tag)
			}
		}
		return false
	})
	return out
}

// copyTool deep-copies the one field that is not a scalar.
//
// A Tool is a value, so handing one out already copies Slug, Path, Title and
// Desc. Tags is a slice: the struct copy duplicates the header and shares the
// backing array, so `c.List()[0].Tags[0] = "x"` would reach into the catalog
// and change what every later read returns. Copied on the way in as well as on
// the way out, or the caller of Set keeps a handle on stored state.
func copyTool(t Tool) Tool {
	if t.Tags == nil {
		return t
	}
	tags := make([]string, len(t.Tags))
	copy(tags, t.Tags)
	t.Tags = tags
	return t
}

func contains(haystack []string, needle string) bool {
	for _, s := range haystack {
		if s == needle {
			return true
		}
	}
	return false
}
