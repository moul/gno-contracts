package index

import (
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func ids(ns ...uint64) []store.ID {
	out := make([]store.ID, len(ns))
	for i, n := range ns {
		out[i] = store.ID(n)
	}
	return out
}

func equalIDs(t *testing.T, want, got []store.ID) {
	t.Helper()
	urequire.Equal(t, len(want), len(got))
	for i := range want {
		uassert.Equal(t, want[i].String(), got[i].String())
	}
}

func TestZeroValueIsUsable(t *testing.T) {
	var ix Index
	uassert.Equal(t, 0, ix.Keys())
	uassert.Equal(t, 0, ix.Len())
	uassert.False(t, ix.Has("gno"))
	uassert.Equal(t, 0, ix.Count("gno"))
	uassert.Equal(t, 0, len(ix.Lookup("gno")))
	_, ok := ix.First("gno")
	uassert.False(t, ok)
	uassert.False(t, ix.Remove("gno", 1))
	uassert.Equal(t, 0, ix.RemoveKey("gno"))
	uassert.False(t, ix.Each(func(string, []store.ID) bool { return true }))

	urequire.NoError(t, ix.Add("gno", 1))
	uassert.Equal(t, 1, ix.Keys())
}

// The whole point of sorting the ids: Lookup must depend on the SET of ids, not
// on the order they arrived in, or two realms that indexed the same records in
// a different order render differently.
func TestLookupDoesNotDependOnInsertionOrder(t *testing.T) {
	forward, reverse := New(), New()
	for _, n := range []uint64{3, 1, 2} {
		urequire.NoError(t, forward.Add("gno", store.ID(n)))
	}
	for _, n := range []uint64{2, 1, 3} {
		urequire.NoError(t, reverse.Add("gno", store.ID(n)))
	}
	equalIDs(t, ids(1, 2, 3), forward.Lookup("gno"))
	equalIDs(t, ids(1, 2, 3), reverse.Lookup("gno"))
}

func TestAddIsIdempotentForTheSamePair(t *testing.T) {
	ix := New()
	urequire.NoError(t, ix.Add("gno", 7))
	urequire.NoError(t, ix.Add("gno", 7))
	equalIDs(t, ids(7), ix.Lookup("gno"))
	uassert.Equal(t, 1, ix.Len())
	uassert.Equal(t, 1, ix.Keys())
}

func TestAddRefusals(t *testing.T) {
	for _, tc := range []struct {
		name string
		key  string
		id   store.ID
		want error
	}{
		{"empty key", "", 1, ErrEmptyKey},
		{"zero id", "gno", 0, ErrZeroID},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ix := New()
			err := ix.Add(tc.key, tc.id)
			urequire.ErrorIs(t, err, tc.want)
			uassert.Equal(t, 0, ix.Len())
		})
	}
}

func TestUniqueRefusesASecondID(t *testing.T) {
	ix := Unique()
	uassert.True(t, ix.IsUnique())
	urequire.NoError(t, ix.Add("moul", 1))

	err := ix.Add("moul", 2)
	urequire.ErrorIs(t, err, ErrDuplicateKey)
	equalIDs(t, ids(1), ix.Lookup("moul"))
	uassert.Equal(t, 1, ix.Len())

	// Re-adding the SAME pair is still a no-op, not a duplicate: a realm
	// re-running a write must not be punished for it.
	urequire.NoError(t, ix.Add("moul", 1))
	uassert.Equal(t, 1, ix.Len())
}

// Keys and Len answer different questions and the difference is the fan-out,
// which is what the index actually costs.
func TestKeysAndLenDiffer(t *testing.T) {
	ix := New()
	urequire.NoError(t, ix.Add("gno", 1))
	urequire.NoError(t, ix.Add("gno", 2))
	urequire.NoError(t, ix.Add("go", 3))
	uassert.Equal(t, 2, ix.Keys())
	uassert.Equal(t, 3, ix.Len())
	uassert.Equal(t, 2, ix.Count("gno"))
	uassert.Equal(t, 1, ix.Count("go"))
	uassert.Equal(t, 0, ix.Count("rust"))
}

func TestRemoveDropsTheKeyWithItsLastID(t *testing.T) {
	ix := New()
	urequire.NoError(t, ix.Add("gno", 1))
	urequire.NoError(t, ix.Add("gno", 2))

	uassert.True(t, ix.Remove("gno", 1))
	uassert.True(t, ix.Has("gno"))
	equalIDs(t, ids(2), ix.Lookup("gno"))

	uassert.True(t, ix.Remove("gno", 2))
	uassert.False(t, ix.Has("gno"))
	uassert.Equal(t, 0, ix.Keys())
	uassert.Equal(t, 0, ix.Len())

	uassert.False(t, ix.Remove("gno", 2))
}

func TestRemoveKey(t *testing.T) {
	ix := New()
	urequire.NoError(t, ix.Add("gno", 1))
	urequire.NoError(t, ix.Add("gno", 2))
	urequire.NoError(t, ix.Add("go", 3))

	uassert.Equal(t, 2, ix.RemoveKey("gno"))
	uassert.Equal(t, 1, ix.Keys())
	uassert.Equal(t, 1, ix.Len())
	uassert.Equal(t, 0, ix.RemoveKey("gno"))
}

// A returned slice that is the stored one makes every caller a writer: an
// assignment into it corrupts the index with no write path having been called.
func TestLookupHandsOutACopy(t *testing.T) {
	ix := New()
	urequire.NoError(t, ix.Add("gno", 1))
	urequire.NoError(t, ix.Add("gno", 2))

	got := ix.Lookup("gno")
	got[0] = store.ID(999)
	equalIDs(t, ids(1, 2), ix.Lookup("gno"))
}

func TestEachIsAscendingAndStops(t *testing.T) {
	ix := New()
	for _, k := range []string{"go", "gno", "rust"} {
		urequire.NoError(t, ix.Add(k, 1))
	}

	var seen []string
	uassert.False(t, ix.Each(func(k string, _ []store.ID) bool {
		seen = append(seen, k)
		return false
	}))
	urequire.Equal(t, 3, len(seen))
	uassert.Equal(t, "gno", seen[0])
	uassert.Equal(t, "go", seen[1])
	uassert.Equal(t, "rust", seen[2])

	var first string
	uassert.True(t, ix.Each(func(k string, _ []store.ID) bool {
		first = k
		return true
	}))
	uassert.Equal(t, "gno", first)
}

func TestEachHandsOutACopy(t *testing.T) {
	ix := New()
	urequire.NoError(t, ix.Add("gno", 1))
	ix.Each(func(_ string, got []store.ID) bool {
		got[0] = store.ID(999)
		return true
	})
	equalIDs(t, ids(1), ix.Lookup("gno"))
}

func TestPage(t *testing.T) {
	ix := New()
	for _, k := range []string{"a", "b", "c", "d", "e"} {
		urequire.NoError(t, ix.Add(k, 1))
	}
	for _, tc := range []struct {
		name string
		page int
		size int
		want []string
	}{
		{"first", 1, 2, []string{"a", "b"}},
		{"second", 2, 2, []string{"c", "d"}},
		{"last, short", 3, 2, []string{"e"}},
		{"past the end", 4, 2, nil},
		{"page zero", 0, 2, nil},
		{"size zero", 1, 0, nil},
		{"negative page", -1, 2, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := ix.Page(tc.page, tc.size)
			urequire.Equal(t, len(tc.want), len(got))
			for i := range tc.want {
				uassert.Equal(t, tc.want[i], got[i].Key)
			}
		})
	}
}

// Pages is what a page picker divides by, so it is never 0.
func TestPagesIsNeverZero(t *testing.T) {
	ix := New()
	uassert.Equal(t, 1, ix.Pages(10))
	uassert.Equal(t, 1, ix.Pages(0))
	uassert.Equal(t, 1, ix.Pages(-1))

	for _, k := range []string{"a", "b", "c"} {
		urequire.NoError(t, ix.Add(k, 1))
	}
	uassert.Equal(t, 2, ix.Pages(2))
	uassert.Equal(t, 1, ix.Pages(3))
	uassert.Equal(t, 3, ix.Pages(1))
}

func TestFirst(t *testing.T) {
	ix := New()
	urequire.NoError(t, ix.Add("gno", 9))
	urequire.NoError(t, ix.Add("gno", 4))

	got, ok := ix.First("gno")
	urequire.True(t, ok)
	uassert.Equal(t, "4", got.String())

	_, ok = ix.First("missing")
	uassert.False(t, ok)
}

// Many ids under one key is the case this package exists for, so the binary
// search has to hold at a size where a linear scan would still look fine.
func TestManyIDsUnderOneKey(t *testing.T) {
	ix := New()
	for n := uint64(64); n >= 1; n-- {
		urequire.NoError(t, ix.Add("gno", store.ID(n)))
	}
	uassert.Equal(t, 64, ix.Count("gno"))
	uassert.Equal(t, 1, ix.Keys())

	got := ix.Lookup("gno")
	urequire.Equal(t, 64, len(got))
	for i, id := range got {
		uassert.Equal(t, store.ID(i+1).String(), id.String())
	}
}
