package eggling

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	eggs = avl.Tree{}
	nextID = 0
	totalPlanted = 0
	totalHatched = 0
	rarityCounts = [4]int{}
}

func TestHashSeedDeterministicAndSensitive(t *testing.T) {
	a := hashSeed("1", "g1alice", "100")
	b := hashSeed("1", "g1alice", "100")
	if a != b {
		t.Fatal("hashSeed should be deterministic for the same inputs")
	}
	if a == hashSeed("2", "g1alice", "100") {
		t.Fatal("different egg IDs should hash differently")
	}
	if len(a) != 64 {
		t.Fatalf("hashSeed length = %d, want 64 (hex sha256)", len(a))
	}
}

func TestSeedBytesFromKnownDigest(t *testing.T) {
	// sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
	r1, r2 := seedBytes(hashSeed(""))
	if r1 != 0xe3 || r2 != 0xb0 {
		t.Fatalf("seedBytes = (%x, %x), want (e3, b0)", r1, r2)
	}
}

func TestRarityTierBoundaries(t *testing.T) {
	cases := []struct {
		roll uint8
		wait int64
		want int
	}{
		{0, 0, 0},     // score 0 -> common
		{139, 0, 0},   // score 139 -> common
		{140, 0, 1},   // score 140 -> uncommon
		{219, 0, 1},   // score 219 -> uncommon
		{220, 0, 2},   // score 220 -> rare
		{255, 0, 2},   // score 255 -> rare (no wait bonus)
		{255, 200, 3}, // score 355 -> legendary (max wait bonus)
		{0, 200, 0},   // score 100 -> still common, roll matters too
	}
	for _, c := range cases {
		if got := rarityTier(c.roll, c.wait); got != c.want {
			t.Fatalf("rarityTier(%d, %d) = %d, want %d", c.roll, c.wait, got, c.want)
		}
	}
}

func TestRarityTierCapsWaitBonus(t *testing.T) {
	// waitCap is 200; waiting 1000 blocks should score identically to
	// waiting exactly 200.
	if rarityTier(50, 1000) != rarityTier(50, 200) {
		t.Fatal("rarityTier should cap the wait bonus at waitCap")
	}
}

func TestPlantAssignsSequentialIDs(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	e1 := plant(alice, 100)
	e2 := plant(alice, 101)
	if e1.ID != "1" || e2.ID != "2" {
		t.Fatalf("expected sequential IDs 1, 2; got %s, %s", e1.ID, e2.ID)
	}
	if totalPlanted != 2 {
		t.Fatalf("totalPlanted = %d, want 2", totalPlanted)
	}
}

func TestHatchTooEarlyPanics(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	e := plant(alice, 100)

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic hatching before minIncubation blocks pass")
		}
	}()
	hatch(e, 100+minIncubation-1)
}

func TestHatchTwicePanics(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	e := plant(alice, 100)
	hatch(e, 100+minIncubation)

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic hatching an already-hatched egg")
		}
	}()
	hatch(e, 100+minIncubation)
}

func TestHatchSetsSpeciesAndCountsStats(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	e := plant(alice, 100)
	hatch(e, 100+minIncubation)

	if !e.Hatched {
		t.Fatal("expected egg to be hatched")
	}
	if e.Species == "" {
		t.Fatal("expected a species to be assigned")
	}
	if e.Level != 1 {
		t.Fatalf("expected level 1 on hatch, got %d", e.Level)
	}
	if totalHatched != 1 {
		t.Fatalf("totalHatched = %d, want 1", totalHatched)
	}
	if rarityCounts[e.RarityTier] != 1 {
		t.Fatalf("expected rarityCounts[%d] = 1, got %d", e.RarityTier, rarityCounts[e.RarityTier])
	}
}

func TestTrainBeforeHatchPanics(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	e := plant(alice, 100)

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic training an unhatched egg")
		}
	}()
	train(e)
}

func TestTrainAccumulatesXPAndLevelsUp(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	e := plant(alice, 100)
	hatch(e, 100+minIncubation)

	for i := 0; i < 5; i++ {
		train(e)
	}
	if e.XP != 50 {
		t.Fatalf("XP = %d, want 50", e.XP)
	}
	if e.Level != 2 {
		t.Fatalf("Level = %d, want 2", e.Level)
	}
}

func TestRenameRequiresHatchedAndNonEmpty(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	e := plant(alice, 100)

	func() {
		defer func() {
			if r := recover(); r == nil {
				t.Fatal("expected panic renaming an unhatched egg")
			}
		}()
		rename(e, "Sparky")
	}()

	hatch(e, 100+minIncubation)
	rename(e, "Sparky")
	if e.Name != "Sparky" {
		t.Fatalf("Name = %q, want Sparky", e.Name)
	}

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic renaming with an empty name")
		}
	}()
	rename(e, "   ")
}

func TestRenderShowsEmptyThenEggThenOwner(t *testing.T) {
	resetState()
	if !strings.Contains(Render(""), "None planted yet") {
		t.Fatal("expected empty-state placeholder")
	}

	alice := testutils.TestAddress("alice")
	e := plant(alice, 100)
	hatch(e, 100+minIncubation)

	home := Render("")
	if !strings.Contains(home, "#"+e.ID) {
		t.Fatal("expected egg row in home listing")
	}

	detail := Render(e.ID)
	if !strings.Contains(detail, "Rarity") {
		t.Fatal("expected detail card to show rarity")
	}

	owned := Render(alice.String())
	if !strings.Contains(owned, e.Name) {
		t.Fatal("expected owner view to list the creature by name")
	}
}

// TestFullLifecycleViaCrossingCalls smoke-tests the exported, realm-crossing
// entry points end to end (as an on-chain caller would invoke them).
func TestFullLifecycleViaCrossingCalls(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	msg := PlantEgg(cross(cur))
	if !strings.Contains(msg, "planted egg #1") {
		t.Fatalf("expected plant confirmation, got %q", msg)
	}

	testing.SkipHeights(minIncubation)

	hatchMsg := Hatch(cross(cur), "1")
	if !strings.Contains(hatchMsg, "hatched into a") {
		t.Fatalf("expected hatch confirmation, got %q", hatchMsg)
	}

	trainMsg := Train(cross(cur), "1")
	if !strings.Contains(trainMsg, "gained 10 XP") {
		t.Fatalf("expected train confirmation, got %q", trainMsg)
	}

	renameMsg := Rename(cross(cur), "1", "Buddy")
	if !strings.Contains(renameMsg, "renamed to Buddy") {
		t.Fatalf("expected rename confirmation, got %q", renameMsg)
	}

	e, ok := get("1")
	if !ok || e.Name != "Buddy" || e.XP != 10 {
		t.Fatalf("unexpected final state: %+v", e)
	}
}

// TestOnlyOwnerCanHatch checks that another address can't hatch someone
// else's egg.
func TestOnlyOwnerCanHatch(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	PlantEgg(cross(cur))
	testing.SkipHeights(minIncubation)

	testing.SetRealm(testing.NewUserRealm(bob))
	rec := revive(func() { Hatch(cross(cur), "1") })
	if rec == nil {
		t.Fatal("expected panic hatching someone else's egg")
	}
}
