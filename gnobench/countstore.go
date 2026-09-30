package main

import (
	"github.com/gnolang/gno/tm2/pkg/store"
	"github.com/gnolang/gno/tm2/pkg/store/cache"
	"github.com/gnolang/gno/tm2/pkg/store/types"
)

// countStore wraps the commit store and records what actually reaches it.
//
// The realm storage diff says how the realm's net state changed. That is what
// the chain charges a deposit on, and it is NOT what the node writes: a commit
// flushes every key the transaction touched, so ten transactions each touching
// one path write ten sets of nodes where one transaction touching ten paths
// writes one. This counts the difference.
type countStore struct {
	store.CommitStore
	Sets, Dels, Gets int64
	SetBytes         int64
	GetBytes         int64
	KeyBytes         int64
}

func (c *countStore) Set(gctx *types.GasContext, key, value []byte) {
	c.Sets++
	c.KeyBytes += int64(len(key))
	c.SetBytes += int64(len(value))
	c.CommitStore.Set(gctx, key, value)
}

func (c *countStore) Delete(gctx *types.GasContext, key []byte) {
	c.Dels++
	c.KeyBytes += int64(len(key))
	c.CommitStore.Delete(gctx, key)
}

func (c *countStore) Get(gctx *types.GasContext, key []byte) []byte {
	v := c.CommitStore.Get(gctx, key)
	c.Gets++
	c.GetBytes += int64(len(v))
	return v
}

// CacheWrap must hand back a cache whose Write() lands on THIS counter. The
// obvious delegation to the inner store's CacheWrap bypasses the counter
// entirely: the cache then writes straight through to the store underneath and
// every counter reads zero, which is exactly what it did the first time.
func (c *countStore) CacheWrap() types.Store { return cache.New(c) }

func (c *countStore) Reset() {
	c.Sets, c.Dels, c.Gets = 0, 0, 0
	c.SetBytes, c.GetBytes, c.KeyBytes = 0, 0, 0
}
