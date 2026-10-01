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

// The single-operation wiring shapes exist because the storage suite's filetest
// harness never touches the key/value store. This asserts the new shapes
// actually do: a cold read of a container must grow its KV traffic with the
// container, which is precisely what the filetest path fails to do (there, KV
// reads stay at 7 to 8 from n=100 to n=10,000).
//
// It reads the committed result file rather than measuring, so it stays cheap
// and still fails if a change makes the harness stop reaching the store.
func TestWiringOpShapesActuallyReachTheStore(t *testing.T) {
	files, err := LoadAll(".", "wiring")
	if err != nil || len(files) == 0 {
		t.Skip("no wiring results committed for any machine")
	}
	type key struct {
		structure string
		n         int
	}
	got := map[key]Row{}
	for _, f := range files {
		for _, r := range f.Rows {
			if r.Workload == shapeOp1Read {
				got[key{r.Structure, r.N}] = r
			}
		}
	}
	if len(got) == 0 {
		t.Skip("no op_read rows committed yet")
	}
	for k, r := range got {
		if r.DKVGets <= 0 {
			t.Errorf("%s at n=%d: op_read reached the store %d times; the shape is "+
				"measuring nothing, which is the filetest harness's failure mode",
				k.structure, k.n, r.DKVGets)
		}
		if r.DKVGetBytes <= 0 {
			t.Errorf("%s at n=%d: op_read read %d bytes from the store",
				k.structure, k.n, r.DKVGetBytes)
		}
	}
	// And the whole point: the traffic must depend on how much is stored.
	small, okS := got[key{"builtin map[string]string", 100}]
	big, okB := got[key{"builtin map[string]string", 2000}]
	if okS && okB && big.DKVGetBytes <= small.DKVGetBytes*4 {
		t.Errorf("a map's cold read moved %d bytes at n=100 and %d at n=2000; "+
			"a single-object container must read all of itself, so the second "+
			"should be roughly twenty times the first",
			small.DKVGetBytes, big.DKVGetBytes)
	}
}
