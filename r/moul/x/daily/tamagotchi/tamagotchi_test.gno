package tamagotchi

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	pets = avl.Tree{}
}

func TestClamp(t *testing.T) {
	if clamp(150, 0, 100) != 100 {
		t.Fatal("clamp should cap at hi")
	}
	if clamp(-5, 0, 100) != 0 {
		t.Fatal("clamp should floor at lo")
	}
	if clamp(50, 0, 100) != 50 {
		t.Fatal("clamp should pass through in-range values")
	}
}

func TestHatchCreatesLivingPet(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	hatch(alice, "Fluffy", 100)

	p, ok := get(alice)
	if !ok || !p.alive {
		t.Fatal("expected a living pet after hatch")
	}
	if p.name != "Fluffy" {
		t.Fatalf("expected name Fluffy, got %s", p.name)
	}
}

func TestHatchTwiceWhileAlivePanics(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	hatch(alice, "Fluffy", 100)

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic hatching a second living pet")
		}
	}()
	hatch(alice, "Again", 101)
}

func TestHatchAfterDeathKeepsLifetimeStats(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	hatch(alice, "Fluffy", 0)
	feed(alice, 0)

	p, _ := get(alice)
	p.alive = false
	p.deaths = 1

	hatch(alice, "Fluffy2", 10)

	p, _ = get(alice)
	if p.feeds != 1 || p.deaths != 1 {
		t.Fatalf("expected lifetime stats to carry over, got feeds=%d deaths=%d", p.feeds, p.deaths)
	}
	if !p.alive {
		t.Fatal("expected the new pet to be alive")
	}
}

func TestFeedReducesHunger(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	hatch(alice, "Fluffy", 100)

	p, _ := get(alice)
	p.hunger = 60

	feed(alice, 100)
	if p.hunger != 30 {
		t.Fatalf("expected hunger 30 after feed, got %d", p.hunger)
	}
	if p.feeds != 1 {
		t.Fatalf("expected feeds counter to increment, got %d", p.feeds)
	}
}

func TestPlayRefusesWhenTooTired(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	hatch(alice, "Fluffy", 100)

	p, _ := get(alice)
	p.energy = 5

	out := play(alice, 100)
	if !strings.Contains(out, "too tired") {
		t.Fatalf("expected too-tired message, got %q", out)
	}
	if p.plays != 0 {
		t.Fatal("play should not have counted while too tired")
	}
}

func TestNeglectKillsPet(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	hatch(alice, "Fluffy", 0)

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic acting on a neglected/dead pet")
		}
	}()
	// Feed re-ticks against a much later height, starving the pet to death.
	feed(alice, 1000)
}

func TestFeedWithoutPetPanics(t *testing.T) {
	resetState()
	bob := testutils.TestAddress("bob")

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic feeding without a pet")
		}
	}()
	feed(bob, 100)
}

func TestRenderShowsEmptyThenPet(t *testing.T) {
	resetState()
	if !strings.Contains(Render(""), "No pets hatched yet") {
		t.Fatal("expected empty-state placeholder")
	}

	alice := testutils.TestAddress("alice")
	hatch(alice, "Fluffy", 100)

	out := Render("")
	if !strings.Contains(out, "Fluffy") {
		t.Fatal("expected pet name in leaderboard render")
	}

	detail := Render(alice.String())
	if !strings.Contains(detail, "Hunger") {
		t.Fatal("expected detail card to show hunger stat")
	}
}

// TestHatchViaCrossingCall smoke-tests the exported, realm-crossing entry
// point end to end (as an on-chain caller would invoke it).
func TestHatchViaCrossingCall(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	msg := Hatch(cross(cur), "Fluffy")
	if !strings.Contains(msg, "hatched") {
		t.Fatalf("expected hatch confirmation, got %q", msg)
	}
	if _, ok := get(alice); !ok {
		t.Fatal("expected pet to be persisted for caller")
	}
}

// decayOver ticks one pet from full stats across `blocks` blocks, calling tick
// every `every` blocks, and returns what it is left with. It drives tick
// directly rather than through Feed/Play/Sleep, because those also restore
// stats and the question here is only what decay does.
func decayOver(blocks, every int) (hunger, happiness, energy int) {
	p := &pet{alive: true, hunger: 0, happiness: 100, energy: 100, lastUpdate: 0}
	for h := every; h <= blocks; h += every {
		p.tick(int64(h))
	}
	return p.hunger, p.happiness, p.energy
}

// TestDecayDoesNotDependOnCallFrequency is the bug this file exists for.
//
// happiness decays once per 2 blocks and energy once per 3, by integer
// division. Before the carried debt, that division truncated on EVERY call, so
// ticking once per block cost 1/2 = 0 happiness and 1/3 = 0 energy, forever: a
// pet fed in a `while true` loop was immortal while everyone else's died. The
// leaderboard rewarded a bot, which is the opposite of what the realm claims.
//
// Over the same 60 blocks the outcome must now be the same whether the owner
// acts every block or once at the end.
func TestDecayDoesNotDependOnCallFrequency(t *testing.T) {
	const blocks = 60
	wantHunger, wantHappy, wantEnergy := decayOver(blocks, blocks)

	for _, every := range []int{1, 2, 3, 5, 30} {
		h, hap, e := decayOver(blocks, every)
		if h != wantHunger || hap != wantHappy || e != wantEnergy {
			t.Errorf("acting every %d block(s) over %d blocks: hunger=%d happiness=%d energy=%d, "+
				"want %d/%d/%d as when acting once",
				every, blocks, h, hap, e, wantHunger, wantHappy, wantEnergy)
		}
	}
}

// The absolute numbers, so a future change to the rates is a deliberate edit
// and not a silent one: 60 blocks costs 60 hunger, 30 happiness, 20 energy.
func TestDecayRates(t *testing.T) {
	h, hap, e := decayOver(60, 1)
	if h != 60 || hap != 70 || e != 80 {
		t.Errorf("60 blocks of decay = hunger %d, happiness %d, energy %d; want 60, 70, 80", h, hap, e)
	}
}

// project draws the page; tick decides the outcome. If they disagree, the pet a
// reader sees is not the pet the next call will act on.
func TestProjectAgreesWithTick(t *testing.T) {
	for _, every := range []int{1, 2, 3, 7} {
		p := &pet{alive: true, hunger: 0, happiness: 100, energy: 100, lastUpdate: 0}
		for h := every; h <= 42; h += every {
			p.tick(int64(h))
		}
		// One more step, projected rather than applied.
		ph, phap, pe, _ := project(p, int64(42+every))
		p.tick(int64(42 + every))
		if ph != p.hunger || phap != p.happiness || pe != p.energy {
			t.Errorf("every %d: project says %d/%d/%d, tick says %d/%d/%d",
				every, ph, phap, pe, p.hunger, p.happiness, p.energy)
		}
	}
}
