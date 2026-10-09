package toolbox

import "gno.land/p/nt/bptree/v0"

// Catalog is the directory itself: tools keyed by slug, ordered by it.
//
// The zero value is an empty, usable catalog. The tree is embedded by value
// rather than held behind a pointer, which is one fewer persisted object and
// is also what makes the zero value work: [bptree.BPTree]'s own zero value is
// an empty tree that takes fanout 32 on its first write, which is the fanout
// wanted here anyway (wide nodes lose most on removal, and a tool can be
// unregistered).
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
	tools bptree.BPTree
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
	c.tools.Set(t.Slug, t)
	return nil
}

// Remove deletes the tool under slug. It returns [ErrUnknownSlug] when there
// is none, so a realm removing an entry it believes in learns that it is gone.
func (c *Catalog) Remove(slug string) error {
	if _, removed := c.tools.Remove(slug); !removed {
		return ErrUnknownSlug
	}
	return nil
}

// Get returns the tool under slug.
func (c *Catalog) Get(slug string) (Tool, bool) {
	v := c.tools.Get(slug)
	if v == nil {
		return Tool{}, false
	}
	return v.(Tool), true
}

// Has reports whether slug is in the catalog.
func (c *Catalog) Has(slug string) bool { return c.tools.Has(slug) }

// Len is how many tools the catalog holds.
func (c *Catalog) Len() int { return c.tools.Size() }

// List returns every tool, in slug order.
func (c *Catalog) List() []Tool {
	out := make([]Tool, 0, c.tools.Size())
	c.tools.Iterate("", "", func(_ string, v any) bool {
		out = append(out, v.(Tool))
		return false
	})
	return out
}

// ByTag returns every tool carrying tag, in slug order. An empty tag matches
// nothing rather than everything: it is almost always an unset field.
func (c *Catalog) ByTag(tag string) []Tool {
	if tag == "" {
		return nil
	}
	var out []Tool
	c.tools.Iterate("", "", func(_ string, v any) bool {
		if t := v.(Tool); t.HasTag(tag) {
			out = append(out, t)
		}
		return false
	})
	return out
}

// Tags returns every tag used by any tool, each once, in first-seen order
// within slug order. Deterministic, which iterating a map would not be.
func (c *Catalog) Tags() []string {
	var out []string
	c.tools.Iterate("", "", func(_ string, v any) bool {
		for _, tag := range v.(Tool).Tags {
			if !contains(out, tag) {
				out = append(out, tag)
			}
		}
		return false
	})
	return out
}

func contains(haystack []string, needle string) bool {
	for _, s := range haystack {
		if s == needle {
			return true
		}
	}
	return false
}
