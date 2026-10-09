package toolbox

// Catalog is the directory itself: tools kept sorted by slug.
//
// The zero value is an empty, usable catalog.
//
// # Why a sorted slice and not a tree
//
// A directory of tools is tens of entries, not thousands, and it is read far
// more often than it is written. At n = 100 a sorted slice costs 92,571 gas
// for one cold operation against `avl`'s 164,812 (gnobench, gno master
// 1fc4c140e, 2026-09-29), and the whole container is one persisted object
// rather than one per node. The crossover where a tree wins a read is around
// n = 750; a toolbox that reaches it has a different problem.
//
// Sorted, rather than insertion-ordered, because the order has to be the same
// on every call. A Render that reshuffles between two identical queries is a
// bug, and slug order is the one ordering that does not depend on when an
// entry was written.
type Catalog struct {
	tools []Tool
}

// Set inserts t, replacing any tool already under its slug.
//
// Replacing rather than refusing is what makes a hub's init idempotent: the
// catalog is rebuilt from source on every redeploy, and a second Set of the
// same slug is a corrected description rather than a collision.
func (c *Catalog) Set(t Tool) error {
	if err := t.Validate(); err != nil {
		return err
	}
	i, found := c.search(t.Slug)
	if found {
		c.tools[i] = t
		return nil
	}
	// A fresh slice of the exact size, not append-and-shift. A slice is one
	// persisted object sized by its backing array, so append's spare capacity
	// is deposit charged for entries that do not exist. Same O(n) copy either
	// way, and this one leaves nothing over.
	longer := make([]Tool, len(c.tools)+1)
	copy(longer, c.tools[:i])
	longer[i] = t
	copy(longer[i+1:], c.tools[i:])
	c.tools = longer
	return nil
}

// Remove deletes the tool under slug. It returns [ErrUnknownSlug] when there
// is none, so a realm removing an entry it believes in learns that it is gone.
func (c *Catalog) Remove(slug string) error {
	i, found := c.search(slug)
	if !found {
		return ErrUnknownSlug
	}
	// Not append(s[:i], s[i+1:]...): that shortens the slice header and leaves
	// the backing array at its peak, so the deposit for the removed entry is
	// never refunded. A fresh exact-size slice drops the old array.
	shorter := make([]Tool, len(c.tools)-1)
	copy(shorter, c.tools[:i])
	copy(shorter[i:], c.tools[i+1:])
	c.tools = shorter
	return nil
}

// Get returns the tool under slug.
func (c *Catalog) Get(slug string) (Tool, bool) {
	i, found := c.search(slug)
	if !found {
		return Tool{}, false
	}
	return c.tools[i], true
}

// Has reports whether slug is in the catalog.
func (c *Catalog) Has(slug string) bool {
	_, found := c.search(slug)
	return found
}

// Len is how many tools the catalog holds.
func (c *Catalog) Len() int { return len(c.tools) }

// List returns every tool, sorted by slug.
//
// The slice is a copy: a caller appending to it, or rewriting an element,
// cannot reach the catalog's own storage.
func (c *Catalog) List() []Tool {
	out := make([]Tool, len(c.tools))
	copy(out, c.tools)
	return out
}

// ByTag returns every tool carrying tag, in slug order. An empty tag matches
// nothing rather than everything: it is almost always an unset field.
func (c *Catalog) ByTag(tag string) []Tool {
	if tag == "" {
		return nil
	}
	var out []Tool
	for _, t := range c.tools {
		if t.HasTag(tag) {
			out = append(out, t)
		}
	}
	return out
}

// Tags returns every tag used by any tool, each once, in first-seen order
// within slug order. Deterministic, which iterating a map would not be.
func (c *Catalog) Tags() []string {
	var out []string
	for _, t := range c.tools {
		for _, tag := range t.Tags {
			if !contains(out, tag) {
				out = append(out, tag)
			}
		}
	}
	return out
}

// search returns the index slug belongs at, and whether it is already there.
func (c *Catalog) search(slug string) (int, bool) {
	lo, hi := 0, len(c.tools)
	for lo < hi {
		mid := int(uint(lo+hi) >> 1)
		if c.tools[mid].Slug < slug {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < len(c.tools) && c.tools[lo].Slug == slug {
		return lo, true
	}
	return lo, false
}

func contains(haystack []string, needle string) bool {
	for _, s := range haystack {
		if s == needle {
			return true
		}
	}
	return false
}
