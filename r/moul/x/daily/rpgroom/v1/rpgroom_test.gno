package rpgroom

import (
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	heroes = avl.Tree{}
	roomLevel = 1
	totalKills = 0
	monster = spawnMonster(roomLevel)
}

func TestSpawnMonster(t *testing.T) {
	m1 := spawnMonster(1)
	m5 := spawnMonster(5)
	if m1.Level != 1 || m5.Level != 5 {
		t.Fatal("spawnMonster should carry the requested level")
	}
	if m5.HP <= m1.HP {
		t.Fatal("a higher-level monster should have more HP")
	}
	if m5.Attack <= m1.Attack {
		t.Fatal("a higher-level monster should hit harder")
	}
}

func TestLevelUp(t *testing.T) {
	h := &Hero{Level: 1, XP: 0, HP: 30, MaxHP: 30, Attack: 5}
	h.XP = 50 // exactly the level-1 threshold
	levelUp(h)
	if h.Level != 2 {
		t.Fatalf("Level = %d, want 2", h.Level)
	}
	if h.XP != 0 {
		t.Fatalf("XP = %d, want 0 (fully consumed)", h.XP)
	}
	if h.MaxHP != 40 || h.HP != 40 {
		t.Fatalf("MaxHP/HP = %d/%d, want 40/40 (healed on level up)", h.MaxHP, h.HP)
	}
	if h.Attack != 8 {
		t.Fatalf("Attack = %d, want 8", h.Attack)
	}
}

func TestLevelUpMultipleLevels(t *testing.T) {
	h := &Hero{Level: 1, XP: 200, HP: 30, MaxHP: 30, Attack: 5}
	levelUp(h)
	// level 1->2 costs 50, 2->3 costs 100: 200 - 50 - 100 = 50 left, still short of 150 for 3->4
	if h.Level != 3 {
		t.Fatalf("Level = %d, want 3", h.Level)
	}
	if h.XP != 50 {
		t.Fatalf("XP = %d, want 50 remaining", h.XP)
	}
}

func TestHPBar(t *testing.T) {
	full := hpBar(10, 10)
	empty := hpBar(0, 10)
	if full == empty {
		t.Fatal("full and empty bars should render differently")
	}
}

// Crossing: Spawn/Attack/Rest/Revive mutate realm state, so the test needs `cur realm`.
func TestFullHeroLifecycle(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	testing.SetRealm(testing.NewUserRealm(alice))
	Spawn(cross(cur), "Alice the Bold")

	v := heroes.Get(alice.String())
	if v == nil {
		t.Fatal("expected a hero for alice")
	}
	hero := v.(*Hero)
	if hero.Level != 1 || !hero.Alive {
		t.Fatalf("fresh hero should be level 1 and alive, got level=%d alive=%v", hero.Level, hero.Alive)
	}

	// Grind the starter monster down; it starts at 35 HP with our hero
	// hitting for 5 (ignoring the rare crit), so a handful of swings should
	// clear it without the hero dying (monster only hits for 5).
	startMonster := monster
	for i := 0; i < 20 && monster == startMonster; i++ {
		if !hero.Alive {
			testing.SetRealm(testing.NewUserRealm(alice))
			Revive(cross(cur))
		}
		testing.SetRealm(testing.NewUserRealm(alice))
		Attack(cross(cur))
	}
	if monster == startMonster {
		t.Fatal("expected the starter monster to be replaced after repeated attacks")
	}
	if hero.Kills < 1 {
		t.Fatalf("Kills = %d, want at least 1", hero.Kills)
	}
	if hero.Gold < 1 {
		t.Fatalf("Gold = %d, want at least 1", hero.Gold)
	}
	if roomLevel < 2 {
		t.Fatalf("roomLevel = %d, want at least 2 after a kill", roomLevel)
	}
}

func TestDoubleSpawnPanics(cur realm, t *testing.T) {
	resetState()
	bob := testutils.TestAddress("bob")
	testing.SetRealm(testing.NewUserRealm(bob))
	Spawn(cross(cur), "Bob")

	testing.SetRealm(testing.NewUserRealm(bob))
	// Spawn panics inside a cross-realm call; a plain defer/recover in this
	// test does not catch a cross-boundary panic, so use revive().
	rec := revive(func() { Spawn(cross(cur), "Bob Again") })
	if rec == nil {
		t.Fatal("expected a second Spawn for the same address to panic")
	}
}

func TestRestRequiresDamage(cur realm, t *testing.T) {
	resetState()
	carol := testutils.TestAddress("carol")
	testing.SetRealm(testing.NewUserRealm(carol))
	Spawn(cross(cur), "Carol")

	testing.SetRealm(testing.NewUserRealm(carol))
	rec := revive(func() { Rest(cross(cur)) })
	if rec == nil {
		t.Fatal("expected Rest at full HP to panic")
	}
}
