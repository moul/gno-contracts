package lru

import (
	"strconv"
	"strings"

	"chain"
)

// capacity is the fixed maximum number of entries the cache holds.
const capacity = 8

// node is a doubly-linked-list node holding a key/value pair.
// The list is ordered MRU (head) -> LRU (tail).
type node struct {
	key   string
	value string
	prev  *node
	next  *node
}

// cache is a fixed-capacity LRU cache backed by a doubly-linked list and
// an index from key -> node for O(1) lookups.
type cache struct {
	index map[string]*node
	head  *node // most-recently-used
	tail  *node // least-recently-used
	size  int
	hits  int
	miss  int
}

var c = &cache{index: make(map[string]*node)}

// detach removes n from the linked list (does not touch the index).
func (ca *cache) detach(n *node) {
	if n.prev != nil {
		n.prev.next = n.next
	} else {
		ca.head = n.next
	}
	if n.next != nil {
		n.next.prev = n.prev
	} else {
		ca.tail = n.prev
	}
	n.prev = nil
	n.next = nil
}

// pushFront inserts n at the head (MRU position).
func (ca *cache) pushFront(n *node) {
	n.prev = nil
	n.next = ca.head
	if ca.head != nil {
		ca.head.prev = n
	}
	ca.head = n
	if ca.tail == nil {
		ca.tail = n
	}
}

// touch moves an existing node to the MRU position.
func (ca *cache) touch(n *node) {
	ca.detach(n)
	ca.pushFront(n)
}

// evict removes the LRU entry (tail) and returns its key.
func (ca *cache) evict() string {
	n := ca.tail
	if n == nil {
		return ""
	}
	ca.detach(n)
	delete(ca.index, n.key)
	ca.size--
	return n.key
}

// Put inserts or updates key with value and marks it most-recently-used.
// Evicts the least-recently-used entry if capacity is exceeded.
func Put(cur realm, key string, value string) {
	if n, ok := c.index[key]; ok {
		n.value = value
		c.touch(n)
		chain.Emit("Put", "key", key, "op", "update")
		return
	}
	n := &node{key: key, value: value}
	c.index[key] = n
	c.pushFront(n)
	c.size++
	evicted := ""
	if c.size > capacity {
		evicted = c.evict()
	}
	if evicted != "" {
		chain.Emit("Put", "key", key, "op", "insert", "evicted", evicted)
	} else {
		chain.Emit("Put", "key", key, "op", "insert")
	}
}

// Get returns the value for key and marks it most-recently-used.
// It records a hit or a miss. The returned bool reports whether the key
// was present.
func Get(cur realm, key string) (string, bool) {
	if n, ok := c.index[key]; ok {
		c.touch(n)
		c.hits++
		chain.Emit("Get", "key", key, "result", "hit")
		return n.value, true
	}
	c.miss++
	chain.Emit("Get", "key", key, "result", "miss")
	return "", false
}

// Reset clears the cache and stats.
func Reset(cur realm) {
	c = &cache{index: make(map[string]*node)}
	chain.Emit("Reset")
}

// peek returns the value without affecting recency or stats (read helper).
func peek(key string) (string, bool) {
	if n, ok := c.index[key]; ok {
		return n.value, true
	}
	return "", false
}

// Render displays the cache contents in MRU->LRU order with stats.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# LRU Cache\n\n")
	b.WriteString("A fixed-capacity least-recently-used cache.\n\n")

	b.WriteString("## Stats\n\n")
	b.WriteString("- Capacity: " + strconv.Itoa(capacity) + "\n")
	b.WriteString("- Size: " + strconv.Itoa(c.size) + "\n")
	b.WriteString("- Hits: " + strconv.Itoa(c.hits) + "\n")
	b.WriteString("- Misses: " + strconv.Itoa(c.miss) + "\n")
	total := c.hits + c.miss
	if total > 0 {
		// integer-percent hit rate, deterministic
		rate := (c.hits * 100) / total
		b.WriteString("- Hit rate: " + strconv.Itoa(rate) + "%\n")
	} else {
		b.WriteString("- Hit rate: n/a\n")
	}
	b.WriteString("\n")

	b.WriteString("## Entries (MRU → LRU)\n\n")
	if c.head == nil {
		b.WriteString("_empty_\n")
		return b.String()
	}
	b.WriteString("| # | Key | Value |\n")
	b.WriteString("|---|-----|-------|\n")
	i := 1
	for n := c.head; n != nil; n = n.next {
		b.WriteString("| " + strconv.Itoa(i) + " | " + n.key + " | " + n.value + " |\n")
		i++
	}
	return b.String()
}
