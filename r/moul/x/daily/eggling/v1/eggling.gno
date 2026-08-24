// Package eggling is an on-chain egg incubator and creature collector.
// Plant an egg, let it incubate for a minimum number of blocks, then Hatch
// it: the longer you waited (and a little luck, seeded from the egg's own
// history) decides the rarity of the creature you get. Train hatched
// creatures to level them up. Unlike a tamagotchi there's nothing to feed
// or lose to neglect — eggling is about patience and the luck of the
// hatch, not survival.
package eggling

import (
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// minIncubation is the minimum number of blocks an egg must sit before it
// can hatch.
const minIncubation int64 = 20

// waitCap is the incubation-time bonus cap (in blocks) used by rarityTier,
// so waiting forever doesn't guarantee a legendary — it just improves odds.
const waitCap int64 = 200

var speciesNames = [...]string{
	"Slime", "Sprout", "Ember", "Pebble", "Breeze", "Glimmer", "Shade", "Coral",
}

var rarityNames = [...]string{"Common", "Uncommon", "Rare", "Legendary"}
var rarityEmoji = [...]string{"⚪", "🟢", "🔵", "🟡"}

// egg is the persisted record for one planted egg, hatched or not.
type egg struct {
	ID         string
	Owner      address
	PlantedAt  int64
	Hatched    bool
	Species    string
	RarityTier int
	Name       string
	XP         int
	Level      int
}

var (
	eggs         avl.Tree // id string -> *egg
	nextID       int
	totalPlanted int
	totalHatched int
	rarityCounts [4]int
)

func get(id string) (*egg, bool) {
	v := eggs.Get(id)
	if v == nil {
		return nil, false
	}
	return v.(*egg), true
}

// hashSeed hashes the given parts (joined with ":") to a deterministic hex
// digest. Used to derive an egg's species and rarity roll from facts
// already fixed at plant time, so nobody — not even the owner — can game
// the outcome after the fact.
func hashSeed(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, ":")))
	return hex.EncodeToString(sum[:])
}

// seedBytes pulls the first two bytes out of a hex digest for use as two
// independent 0-255 rolls (species pick, rarity roll).
func seedBytes(seedHex string) (byte, byte) {
	raw, err := hex.DecodeString(seedHex)
	if err != nil || len(raw) < 2 {
		return 0, 0
	}
	return raw[0], raw[1]
}

// rarityTier turns a 0-255 roll plus the blocks waited into a tier index
// 0..3 (common..legendary). Waiting longer raises the effective score, so
// patience improves your odds, but a bad roll can still land common even
// after a long wait, and a lucky roll can hatch rare almost immediately.
func rarityTier(roll uint8, waitBlocks int64) int {
	bonus := waitBlocks
	if bonus > waitCap {
		bonus = waitCap
	}
	score := int(roll) + int(bonus)/2
	switch {
	case score >= 300:
		return 3
	case score >= 220:
		return 2
	case score >= 140:
		return 1
	default:
		return 0
	}
}

// plant is the non-crossing core of PlantEgg.
func plant(owner address, height int64) *egg {
	nextID++
	id := strconv.Itoa(nextID)
	e := &egg{ID: id, Owner: owner, PlantedAt: height}
	eggs.Set(id, e)
	totalPlanted++
	return e
}

// PlantEgg starts incubating a new egg for the caller. Returns its ID.
func PlantEgg(cur realm) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	e := plant(cur.Previous().Address(), runtime.ChainHeight())
	return "🥚 planted egg #" + e.ID + " — incubate at least " +
		strconv.Itoa(int(minIncubation)) + " blocks, then Hatch(\"" + e.ID + "\")"
}

// hatch is the non-crossing core of Hatch.
func hatch(e *egg, height int64) string {
	if e.Hatched {
		panic("egg #" + e.ID + " already hatched into a " + e.Species)
	}
	wait := height - e.PlantedAt
	if wait < minIncubation {
		panic("egg #" + e.ID + " needs " + strconv.Itoa(int(minIncubation-wait)) + " more blocks to incubate")
	}

	seed := hashSeed(e.ID, e.Owner.String(), strconv.FormatInt(e.PlantedAt, 10))
	rarityRoll, speciesRoll := seedBytes(seed)
	tier := rarityTier(rarityRoll, wait)
	species := speciesNames[int(speciesRoll)%len(speciesNames)]

	e.Hatched = true
	e.Species = species
	e.RarityTier = tier
	e.Name = species
	e.Level = 1
	rarityCounts[tier]++
	totalHatched++

	return rarityEmoji[tier] + " egg #" + e.ID + " hatched into a " + rarityNames[tier] + " " + species + "!"
}

// Hatch hatches an incubated egg the caller owns.
func Hatch(cur realm, id string) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	e, ok := get(id)
	if !ok {
		panic("no such egg #" + id)
	}
	if e.Owner != cur.Previous().Address() {
		panic("only the owner can hatch egg #" + id)
	}
	return hatch(e, runtime.ChainHeight())
}

// train is the non-crossing core of Train.
func train(e *egg) string {
	if !e.Hatched {
		panic("egg #" + e.ID + " hasn't hatched yet")
	}
	e.XP += 10
	newLevel := e.XP/50 + 1
	leveled := newLevel > e.Level
	e.Level = newLevel

	msg := e.Name + " gained 10 XP (" + strconv.Itoa(e.XP) + " total)"
	if leveled {
		msg += " and reached level " + strconv.Itoa(e.Level) + "!"
	}
	return msg
}

// Train gives a hatched creature the caller owns some experience, leveling
// it up every 50 XP.
func Train(cur realm, id string) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	e, ok := get(id)
	if !ok {
		panic("no such egg #" + id)
	}
	if e.Owner != cur.Previous().Address() {
		panic("only the owner can train egg #" + id)
	}
	return train(e)
}

// rename is the non-crossing core of Rename.
func rename(e *egg, name string) string {
	if !e.Hatched {
		panic("egg #" + e.ID + " hasn't hatched yet — nothing to name")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		panic("name cannot be empty")
	}
	old := e.Name
	e.Name = name
	return old + " renamed to " + name
}

// Rename gives a hatched creature the caller owns a custom name.
func Rename(cur realm, id string, name string) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	e, ok := get(id)
	if !ok {
		panic("no such egg #" + id)
	}
	if e.Owner != cur.Previous().Address() {
		panic("only the owner can rename egg #" + id)
	}
	return rename(e, name)
}

// escapeInline neutralizes markdown-active characters in untrusted text
// before it's embedded inline in Render output.
func escapeInline(s string) string {
	r := strings.NewReplacer(
		"\\", "\\\\",
		"`", "\\`",
		"*", "\\*",
		"_", "\\_",
		"[", "\\[",
		"]", "\\]",
		"|", "\\|",
	)
	return r.Replace(s)
}

func shortAddr(a address) string {
	s := a.String()
	if len(s) > 12 {
		return s[:8] + "…" + s[len(s)-4:]
	}
	return s
}

// byIDNumeric orders eggs by their numeric ID, ascending.
type byIDNumeric []*egg

func (r byIDNumeric) Len() int      { return len(r) }
func (r byIDNumeric) Swap(i, j int) { r[i], r[j] = r[j], r[i] }
func (r byIDNumeric) Less(i, j int) bool {
	a, _ := strconv.Atoi(r[i].ID)
	b, _ := strconv.Atoi(r[j].ID)
	return a < b
}

func allEggs() []*egg {
	var rows []*egg
	eggs.Iterate("", "", func(_ string, v any) bool {
		rows = append(rows, v.(*egg))
		return false
	})
	sort.Stable(byIDNumeric(rows))
	return rows
}

func renderHome() string {
	var b strings.Builder
	b.WriteString("# 🥚 Eggling\n\n")
	b.WriteString("An on-chain egg incubator. `PlantEgg()` to start one, wait at least " +
		strconv.Itoa(int(minIncubation)) + " blocks, then `Hatch(id)` — the longer you " +
		"waited (plus a little sealed-in luck) decides the rarity of the creature you get. " +
		"`Train(id)` levels a hatched creature up; `Rename(id, name)` gives it a name.\n\n")

	b.WriteString("- Eggs planted: " + strconv.Itoa(totalPlanted) + "\n")
	b.WriteString("- Creatures hatched: " + strconv.Itoa(totalHatched) + "\n")
	if totalHatched > 0 {
		for tier := 3; tier >= 0; tier-- {
			if rarityCounts[tier] > 0 {
				b.WriteString("  - " + rarityEmoji[tier] + " " + rarityNames[tier] + ": " +
					strconv.Itoa(rarityCounts[tier]) + "\n")
			}
		}
	}

	rows := allEggs()
	b.WriteString("\n## Eggs\n\n")
	if len(rows) == 0 {
		b.WriteString("_None planted yet. Be the first!_\n")
		return b.String()
	}

	b.WriteString("| ID | Owner | Status | Level |\n")
	b.WriteString("| :--- | :--- | :--- | ---: |\n")
	for _, e := range rows {
		status := "🥚 incubating"
		level := "-"
		if e.Hatched {
			status = rarityEmoji[e.RarityTier] + " " + escapeInline(e.Name) + " (" + rarityNames[e.RarityTier] + " " + e.Species + ")"
			level = strconv.Itoa(e.Level)
		}
		b.WriteString("| #" + e.ID + " | `" + shortAddr(e.Owner) + "` | " + status + " | " + level + " |\n")
	}
	b.WriteString("\n_View a single egg at this realm's path plus its ID (e.g. `.../eggling:3`), " +
		"or one owner's eggs plus their address._\n")
	return b.String()
}

func renderEgg(id string, height int64) string {
	e, ok := get(id)
	if !ok {
		return "# Egg #" + escapeInline(id) + "\n\nNo such egg.\n"
	}

	var b strings.Builder
	if !e.Hatched {
		wait := height - e.PlantedAt
		b.WriteString("# 🥚 Egg #" + e.ID + "\n\n")
		b.WriteString("- Owner: `" + e.Owner.String() + "`\n")
		b.WriteString("- Planted at block: " + strconv.FormatInt(e.PlantedAt, 10) + "\n")
		if wait < minIncubation {
			b.WriteString("- Ready to hatch in: " + strconv.FormatInt(minIncubation-wait, 10) + " more blocks\n")
		} else {
			b.WriteString("- Ready to hatch now — call `Hatch(\"" + e.ID + "\")`\n")
		}
		return b.String()
	}

	b.WriteString("# " + rarityEmoji[e.RarityTier] + " " + e.Name + "\n\n")
	b.WriteString("- Owner: `" + e.Owner.String() + "`\n")
	b.WriteString("- Species: " + e.Species + "\n")
	b.WriteString("- Rarity: " + rarityNames[e.RarityTier] + "\n")
	b.WriteString("- Level: " + strconv.Itoa(e.Level) + " (" + strconv.Itoa(e.XP) + " XP)\n")
	return b.String()
}

func renderOwner(rawAddr string) string {
	owner := address(strings.TrimSpace(rawAddr))
	safe := escapeInline(owner.String())

	var b strings.Builder
	b.WriteString("# Eggs owned by " + safe + "\n\n")

	found := false
	for _, e := range allEggs() {
		if e.Owner != owner {
			continue
		}
		found = true
		if e.Hatched {
			b.WriteString("- #" + e.ID + ": " + rarityEmoji[e.RarityTier] + " " + escapeInline(e.Name) +
				" — " + rarityNames[e.RarityTier] + " " + e.Species + ", level " + strconv.Itoa(e.Level) + "\n")
		} else {
			b.WriteString("- #" + e.ID + ": 🥚 incubating\n")
		}
	}
	if !found {
		b.WriteString("_No eggs found for this address._\n")
	}
	return b.String()
}

// Render shows the full egg list at "", a single egg's detail when path is
// a numeric ID, or one owner's eggs when path is a bech32 address.
func Render(path string) string {
	path = strings.TrimPrefix(strings.TrimSpace(path), "/")
	if path == "" {
		return renderHome()
	}
	if _, err := strconv.Atoi(path); err == nil {
		return renderEgg(path, runtime.ChainHeight())
	}
	return renderOwner(path)
}
