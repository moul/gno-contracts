package memory

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// findPairIndices returns two grid indices holding the same face, plus a third
// index whose face differs from that pair — using the current board layout.
func findPairIndices() (int, int, int) {
	// Map first-seen index per face.
	first := map[int]int{}
	var pa, pb int = -1, -1
	for i := 0; i < gridSize; i++ {
		f := board.tiles[i].face
		if j, ok := first[f]; ok {
			pa, pb = j, i
			break
		}
		first[f] = i
	}
	// Find an index outside the matched pair with a different face.
	other := -1
	for i := 0; i < gridSize; i++ {
		if i != pa && i != pb && board.tiles[i].face != board.tiles[pa].face {
			other = i
			break
		}
	}
	return pa, pb, other
}

func TestFlipMatchAndMiss(cur realm, t *testing.T) {
	addr := testutils.TestAddress("player")
	testing.SetRealm(testing.NewUserRealm(addr))

	NewGame(cross(cur))

	pa, pb, other := findPairIndices()
	uassert.True(t, pa >= 0 && pb >= 0 && other >= 0, "expected valid indices")

	// Flip a matching pair -> both matched, pairs increments.
	Flip(cross(cur), pa)
	Flip(cross(cur), pb)
	uassert.True(t, board.tiles[pa].matched, "first tile should be matched")
	uassert.True(t, board.tiles[pb].matched, "second tile should be matched")
	uassert.Equal(t, 1, board.pairs)
	uassert.Equal(t, 1, board.moves)

	// Flip a mismatched pair (pa is matched; pick two unmatched non-equal).
	// Reuse `other` and find a partner with a different face, both unmatched.
	partner := -1
	for i := 0; i < gridSize; i++ {
		if i != other && !board.tiles[i].matched && board.tiles[i].face != board.tiles[other].face {
			partner = i
			break
		}
	}
	uassert.True(t, partner >= 0, "expected a mismatched partner")

	Flip(cross(cur), other)
	Flip(cross(cur), partner)
	uassert.Equal(t, 2, board.moves)
	uassert.Equal(t, 1, board.pairs) // no new match
	// Both still showing (not matched) until next flip clears them.
	uassert.False(t, board.tiles[other].matched, "mismatched tile not matched")
	uassert.Equal(t, 2, len(board.flipped))

	// Next flip clears the two mismatched tiles first.
	// Find any still-unmatched, not-currently-flipped index.
	next := -1
	for i := 0; i < gridSize; i++ {
		if i == other || i == partner {
			continue
		}
		if !board.tiles[i].matched {
			next = i
			break
		}
	}
	uassert.True(t, next >= 0, "expected an unflipped unmatched tile")
	Flip(cross(cur), next)
	uassert.Equal(t, 1, len(board.flipped), "previous mismatch cleared, one showing")
}

func TestDeterministicShuffleAndRender(cur realm, t *testing.T) {
	// Same seed -> identical layout.
	a := shuffle(42)
	b := shuffle(42)
	for i := 0; i < gridSize; i++ {
		uassert.Equal(t, a[i].face, b[i].face)
	}

	// Different seed -> at least one differing cell (extremely likely).
	c := shuffle(43)
	diff := false
	for i := 0; i < gridSize; i++ {
		if a[i].face != c[i].face {
			diff = true
			break
		}
	}
	uassert.True(t, diff, "different seeds should differ")

	// Each face appears exactly twice.
	counts := map[int]int{}
	for i := 0; i < gridSize; i++ {
		counts[a[i].face]++
	}
	for f := 0; f < numPairs; f++ {
		uassert.Equal(t, 2, counts[f])
	}

	// Render on a fresh game shows hidden tiles and zero progress.
	addr := testutils.TestAddress("viewer")
	testing.SetRealm(testing.NewUserRealm(addr))
	NewGame(cross(cur))
	out := Render("")
	uassert.True(t, len(out) > 0, "render non-empty")
	uassert.True(t, containsSub(out, "Memory Match"), "has title")
	uassert.True(t, containsSub(out, "❓"), "shows hidden tiles")
	uassert.True(t, containsSub(out, "0 / 8"), "zero pairs matched")
}

func containsSub(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
