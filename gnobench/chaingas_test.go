package main

import (
	"testing"

	"github.com/gnolang/gno/tm2/pkg/db/memdb"
	"github.com/gnolang/gno/tm2/pkg/store/dbadapter"
	"github.com/gnolang/gno/tm2/pkg/store/types"
)

// The config must be the chain's, not a transcription of it. These are the
// values gno.land's genesis actually ships; if upstream reprices anything this
// test fails and the report's numbers are wrong until someone looks.
func TestChainGasConfigIsTheChains(t *testing.T) {
	c := chainGasConfig()
	for _, tc := range []struct {
		name string
		got  int64
		want int64
	}{
		{"ReadCostFlat", int64(c.ReadCostFlat), 59_000},
		{"ReadCostPerByte", int64(c.ReadCostPerByte), 17},
		{"WriteCostFlat", int64(c.WriteCostFlat), 24_000},
		{"WriteCostPerByte", int64(c.WriteCostPerByte), 14},
		{"IterNextCostFlat", int64(c.IterNextCostFlat), 1_000},
		{"FixedGetReadDepth100", c.FixedGetReadDepth100, 100},
		{"FixedSetReadDepth100", c.FixedSetReadDepth100, 200},
		{"FixedWriteDepth100", c.FixedWriteDepth100, 540},
	} {
		if tc.got != tc.want {
			t.Errorf("%s = %d, want %d: upstream repriced storage gas, and every "+
				"`store gas` column in the reports moved with it", tc.name, tc.got, tc.want)
		}
	}
}

// chainStoreGas must agree with the formulas in tm2/pkg/store/cache/store.go.
func TestChainStoreGasFormula(t *testing.T) {
	c := chainGasConfig()
	for _, tc := range []struct {
		name                         string
		gets, getB, sets, setB, dels int64
		want                         int64
	}{
		// GET: 1.00 * 59_000 + 17/byte
		{"one empty get", 1, 0, 0, 0, 0, 59_000},
		{"one 1KB get", 1, 1000, 0, 0, 0, 59_000 + 17_000},
		// SET: 2.00 * 59_000 + 5.40 * 24_000 + 14/byte = 247_600 + 14b
		{"one empty set", 0, 0, 1, 0, 0, 247_600},
		{"one 1KB set", 0, 0, 1, 1000, 0, 247_600 + 14_000},
		// DELETE: the same flats, no per-byte
		{"one delete", 0, 0, 0, 0, 1, 247_600},
		{"nothing", 0, 0, 0, 0, 0, 0},
	} {
		if got := chainStoreGas(c, tc.gets, tc.getB, tc.sets, tc.setB, tc.dels); got != tc.want {
			t.Errorf("%s: chainStoreGas = %d, want %d", tc.name, got, tc.want)
		}
	}
}

// The counters feeding chainStoreGas sit below a cache, while the chain charges
// at the cache. This asserts the two surfaces see the same events, which is the
// whole reason the conversion is legitimate:
//
//   - a repeated Set to one key reaches the counter ONCE, carrying the final
//     value, which is what the chain's refund-dedup also charges for;
//   - a repeated Get is absorbed by the cache and never reaches the counter,
//     which is what the chain's "cache hit, no gas" also does.
func TestChainStoreGasMatchesCacheCharging(t *testing.T) {
	mk := func() (*countStore, types.Store) {
		cs := &countStore{CommitStore: commitAdapter{dbadapter.Store{DB: memdb.NewMemDB()}}}
		return cs, cs.CacheWrap()
	}

	t.Run("three sets of one key flush once, with the last value", func(t *testing.T) {
		cs, c := mk()
		c.Set(nil, []byte("k"), []byte("a"))
		c.Set(nil, []byte("k"), []byte("bb"))
		c.Set(nil, []byte("k"), []byte("ccc"))
		c.Write()
		if cs.Sets != 1 {
			t.Fatalf("Sets = %d, want 1: the chain charges once per distinct key", cs.Sets)
		}
		if cs.SetBytes != 3 {
			t.Fatalf("SetBytes = %d, want 3: the charge is for the final value", cs.SetBytes)
		}
	})

	t.Run("a repeated get is a cache hit and costs nothing", func(t *testing.T) {
		cs, c := mk()
		c.Set(nil, []byte("k"), []byte("value"))
		c.Write()
		cs.Reset()
		tx := cs.CacheWrap() // the next transaction's cache
		for i := 0; i < 5; i++ {
			tx.Get(nil, []byte("k"))
		}
		if cs.Gets != 1 {
			t.Fatalf("Gets = %d, want 1: four of the five are cache hits", cs.Gets)
		}
	})
}
