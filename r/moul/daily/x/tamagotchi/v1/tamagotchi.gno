// Package tamagotchi is an on-chain virtual pet. Hatch one, then keep it
// alive by Feeding, Playing and letting it Sleep — hunger, happiness and
// energy all decay with block height, and neglect too long kills the pet.
// Hatching again after a death starts a fresh pet but keeps your lifetime
// stats, so the leaderboard rewards long-term care, not just luck.
package tamagotchi

import (
	"sort"
	"strconv"

	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// pet is the persisted record for one owner's tamagotchi.
type pet struct {
	owner      address
	name       string
	born       int64
	lastUpdate int64
	hunger     int // 0 (full) .. 100 (starving)
	happiness  int // 0 (miserable) .. 100 (joyful)
	energy     int // 0 (exhausted) .. 100 (energetic)
	alive      bool
	deaths     int
	feeds      int
	plays      int
}

var pets avl.Tree // owner address string -> *pet

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func get(owner address) (*pet, bool) {
	v, ok := pets.Get(owner.String())
	if !ok {
		return nil, false
	}
	return v.(*pet), true
}

// tick applies stat decay for blocks elapsed since the pet's last update and
// kills it if any stat has bottomed/topped out. Mutates and persists.
func (p *pet) tick(height int64) {
	if !p.alive {
		return
	}
	elapsed := int(height - p.lastUpdate)
	if elapsed <= 0 {
		return
	}
	p.hunger = clamp(p.hunger+elapsed, 0, 100)
	p.happiness = clamp(p.happiness-elapsed/2, 0, 100)
	p.energy = clamp(p.energy-elapsed/3, 0, 100)
	p.lastUpdate = height
	if p.hunger >= 100 || p.happiness <= 0 || p.energy <= 0 {
		p.alive = false
		p.deaths++
	}
}

// project computes display stats as of height without mutating the pet, so
// Render can show a live-looking view without writing state on a query.
func project(p *pet, height int64) (hunger, happiness, energy int, alive bool) {
	if !p.alive {
		return p.hunger, p.happiness, p.energy, false
	}
	elapsed := int(height - p.lastUpdate)
	if elapsed < 0 {
		elapsed = 0
	}
	hunger = clamp(p.hunger+elapsed, 0, 100)
	happiness = clamp(p.happiness-elapsed/2, 0, 100)
	energy = clamp(p.energy-elapsed/3, 0, 100)
	alive = hunger < 100 && happiness > 0 && energy > 0
	return
}

func ageStageName(born, height int64) string {
	switch age := height - born; {
	case age < 10:
		return "🥚 Egg"
	case age < 50:
		return "🐣 Baby"
	case age < 200:
		return "🐤 Teen"
	default:
		return "🐓 Adult"
	}
}

// requireLivingPet ticks and fetches the caller's pet, panicking with a
// friendly message if there is none or it has died.
func requireLivingPet(owner address, height int64) *pet {
	p, ok := get(owner)
	if !ok {
		panic("you don't have a pet yet — call Hatch(name) first")
	}
	p.tick(height)
	if !p.alive {
		panic(p.name + " has died of neglect. Call Hatch(name) to start over.")
	}
	return p
}

// hatch is the non-crossing core of Hatch, kept separate so unit tests can
// exercise its panics directly without going through a realm-crossing call.
func hatch(owner address, name string, height int64) string {
	if name == "" {
		panic("name cannot be empty")
	}

	deaths, feeds, plays := 0, 0, 0
	if existing, ok := get(owner); ok {
		if existing.alive {
			existing.tick(height)
		}
		if existing.alive {
			panic("you already have a living pet: " + existing.name)
		}
		deaths, feeds, plays = existing.deaths, existing.feeds, existing.plays
	}

	pets.Set(owner.String(), &pet{
		owner:      owner,
		name:       name,
		born:       height,
		lastUpdate: height,
		hunger:     20,
		happiness:  80,
		energy:     80,
		alive:      true,
		deaths:     deaths,
		feeds:      feeds,
		plays:      plays,
	})
	return "🥚 " + name + " has hatched!"
}

// Hatch creates a new pet for the caller. Lifetime feeds/plays/deaths carry
// over from any previous pet so the leaderboard tracks long-term care.
func Hatch(cur realm, name string) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	return hatch(cur.Previous().Address(), name, runtime.ChainHeight())
}

// feed is the non-crossing core of Feed.
func feed(owner address, height int64) string {
	p := requireLivingPet(owner, height)
	p.hunger = clamp(p.hunger-30, 0, 100)
	p.energy = clamp(p.energy+5, 0, 100)
	p.feeds++
	return p.name + " munches happily. Hunger: " + strconv.Itoa(p.hunger) + "/100"
}

// Feed reduces hunger and gives a small energy boost.
func Feed(cur realm) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	return feed(cur.Previous().Address(), runtime.ChainHeight())
}

// play is the non-crossing core of Play.
func play(owner address, height int64) string {
	p := requireLivingPet(owner, height)
	if p.energy < 10 {
		return p.name + " is too tired to play — try Sleep() first."
	}
	p.happiness = clamp(p.happiness+20, 0, 100)
	p.energy = clamp(p.energy-10, 0, 100)
	p.hunger = clamp(p.hunger+5, 0, 100)
	p.plays++
	return p.name + " had a blast! Happiness: " + strconv.Itoa(p.happiness) + "/100"
}

// Play boosts happiness at the cost of energy and a bit of hunger. Refuses
// to run a tired pet into the ground — rest first.
func Play(cur realm) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	return play(cur.Previous().Address(), runtime.ChainHeight())
}

// sleep is the non-crossing core of Sleep.
func sleep(owner address, height int64) string {
	p := requireLivingPet(owner, height)
	p.energy = clamp(p.energy+40, 0, 100)
	p.hunger = clamp(p.hunger+5, 0, 100)
	return p.name + " takes a nap. Energy: " + strconv.Itoa(p.energy) + "/100"
}

// Sleep restores energy at the cost of a little hunger.
func Sleep(cur realm) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	return sleep(cur.Previous().Address(), runtime.ChainHeight())
}

// byAliveThenOwner ranks living pets before dead ones, then orders each
// group by owner address so the leaderboard is fully deterministic.
type byAliveThenOwner []*pet

func (r byAliveThenOwner) Len() int      { return len(r) }
func (r byAliveThenOwner) Swap(i, j int) { r[i], r[j] = r[j], r[i] }
func (r byAliveThenOwner) Less(i, j int) bool {
	if r[i].alive != r[j].alive {
		return r[i].alive
	}
	return r[i].owner.String() < r[j].owner.String()
}

func bar(v int) string {
	filled := v / 10
	out := ""
	for i := 0; i < 10; i++ {
		if i < filled {
			out += "█"
		} else {
			out += "░"
		}
	}
	return out
}

func shortAddr(a address) string {
	s := a.String()
	if len(s) > 12 {
		return s[:8] + "…" + s[len(s)-4:]
	}
	return s
}

func renderCard(p *pet, height int64) string {
	hunger, happiness, energy, alive := project(p, height)
	out := "## " + p.name + " — owned by `" + shortAddr(p.owner) + "`\n\n"
	if !alive {
		out += "💀 **Deceased.** Owner can `Hatch(name)` a new pet.\n\n"
		return out
	}
	out += ageStageName(p.born, height) + " · age **" + strconv.Itoa(int(height-p.born)) + "** blocks\n\n"
	out += "- Hunger:    " + bar(100-hunger) + " (" + strconv.Itoa(hunger) + "/100 — lower is better)\n"
	out += "- Happiness: " + bar(happiness) + " (" + strconv.Itoa(happiness) + "/100)\n"
	out += "- Energy:    " + bar(energy) + " (" + strconv.Itoa(energy) + "/100)\n\n"
	return out
}

// Render shows either every pet ever hatched (path == "") or a single pet's
// detail card when path is a bech32 owner address.
func Render(path string) string {
	height := runtime.ChainHeight()

	out := "# 🐣 Tamagotchi\n\n"
	out += "A tiny on-chain pet. `Hatch(\"name\")` to start, then keep it alive with " +
		"`Feed()`, `Play()` and `Sleep()` — stats decay every block, so neglect kills it.\n\n"

	if path != "" {
		owner := address(path)
		p, ok := get(owner)
		if !ok {
			return out + "_No pet found for `" + path + "`._\n"
		}
		return out + renderCard(p, height)
	}

	var rows []*pet
	pets.Iterate("", "", func(_ string, v any) bool {
		rows = append(rows, v.(*pet))
		return false
	})
	if len(rows) == 0 {
		out += "_No pets hatched yet. Be the first!_\n"
		return out
	}
	sort.Stable(byAliveThenOwner(rows))

	out += "| Pet | Owner | Status | Feeds | Plays | Deaths |\n"
	out += "| :--- | :--- | :--- | ---: | ---: | ---: |\n"
	for _, p := range rows {
		_, _, _, alive := project(p, height)
		status := "🐤 alive"
		if !alive {
			status = "💀 dead"
		}
		out += "| " + p.name + " | `" + shortAddr(p.owner) + "` | " + status +
			" | " + strconv.Itoa(p.feeds) + " | " + strconv.Itoa(p.plays) +
			" | " + strconv.Itoa(p.deaths) + " |\n"
	}
	out += "\n_View a single pet at `?<owner-address>`._\n"
	return out
}
