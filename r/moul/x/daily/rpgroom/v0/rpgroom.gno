// Package rpgroom is a tiny single-room on-chain RPG. There is exactly one
// monster in the room at a time. Spawn a hero, take a swing, and see what
// happens: land the killing blow and the room's monster gets replaced by a
// tougher one while your hero gains XP, gold, and (eventually) a level; get
// hit hard enough and your hero falls until it's revived. A room-wide
// leaderboard tracks who has climbed the highest.
package rpgroom

import (
	"sort"
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/markdown/sanitize/v0"
)

// Hero is one player's on-chain character in the room.
type Hero struct {
	Name   string
	Level  int
	XP     int
	HP     int
	MaxHP  int
	Attack int
	Kills  int
	Gold   int
	Alive  bool
}

// Monster is the room's current resident.
type Monster struct {
	Name   string
	Level  int
	HP     int
	MaxHP  int
	Attack int
}

var (
	heroes     avl.Tree // address string -> *Hero
	monster    *Monster
	roomLevel  int
	totalKills int
)

var monsterNames = []string{
	"Slime", "Giant Rat", "Goblin", "Skeleton", "Cave Bat",
	"Orc Grunt", "Wraith", "Stone Troll", "Dread Wolf", "Young Dragon",
}

func init() {
	roomLevel = 1
	monster = spawnMonster(roomLevel)
}

func spawnMonster(level int) *Monster {
	name := monsterNames[(level-1)%len(monsterNames)]
	hp := 20 + level*15
	return &Monster{
		Name:   name,
		Level:  level,
		HP:     hp,
		MaxHP:  hp,
		Attack: 3 + level*2,
	}
}

// Spawn creates the caller's hero in the room. Each address gets exactly one
// hero; call Revive (not Spawn again) if it dies.
func Spawn(cur realm, name string) {
	if !cur.Previous().IsUserCall() {
		panic("only a direct EOA call can spawn a hero")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		panic("name required")
	}
	if len(name) > 24 {
		panic("name too long (max 24 chars)")
	}
	addr := cur.Previous().Address().String()
	if heroes.Has(addr) {
		panic("you already have a hero in this room")
	}
	heroes.Set(addr, &Hero{
		Name:   name,
		Level:  1,
		HP:     30,
		MaxHP:  30,
		Attack: 5,
		Alive:  true,
	})
	chain.Emit("HeroSpawned", "addr", addr, "name", name)
}

// Attack swings the caller's hero at the room's current monster. Killing it
// grants XP and gold and replaces it with a tougher one; otherwise the
// monster strikes back.
func Attack(cur realm) {
	if !cur.Previous().IsUserCall() {
		panic("only a direct EOA call can attack")
	}
	addr := cur.Previous().Address().String()
	v := heroes.Get(addr)
	if v == nil {
		panic("no hero found; call Spawn first")
	}
	hero := v.(*Hero)
	if !hero.Alive {
		panic("your hero is dead; call Revive first")
	}

	dmg := hero.Attack
	if runtime.ChainHeight()%7 == 0 {
		dmg *= 2 // occasional critical hit, tied to block height parity
	}
	monster.HP -= dmg
	chain.Emit("HeroAttacked", "addr", addr, "damage", strconv.Itoa(dmg), "monsterHP", strconv.Itoa(monster.HP))

	if monster.HP <= 0 {
		reward := monster.Level * 10
		gained := monster.Level * 20
		hero.Gold += reward
		hero.XP += gained
		hero.Kills++
		levelUp(hero)
		chain.Emit("MonsterSlain", "addr", addr, "monster", monster.Name, "level", strconv.Itoa(monster.Level))

		totalKills++
		roomLevel++
		monster = spawnMonster(roomLevel)
		return
	}

	hero.HP -= monster.Attack
	if hero.HP <= 0 {
		hero.HP = 0
		hero.Alive = false
		chain.Emit("HeroDied", "addr", addr, "monster", monster.Name)
	}
}

// Rest heals the caller's hero for a quarter of its max HP.
func Rest(cur realm) {
	if !cur.Previous().IsUserCall() {
		panic("only a direct EOA call can rest")
	}
	addr := cur.Previous().Address().String()
	v := heroes.Get(addr)
	if v == nil {
		panic("no hero found; call Spawn first")
	}
	hero := v.(*Hero)
	if !hero.Alive {
		panic("your hero is dead; call Revive first")
	}
	if hero.HP >= hero.MaxHP {
		panic("already at full health")
	}
	heal := hero.MaxHP / 4
	if heal < 1 {
		heal = 1
	}
	hero.HP += heal
	if hero.HP > hero.MaxHP {
		hero.HP = hero.MaxHP
	}
	chain.Emit("HeroRested", "addr", addr, "hp", strconv.Itoa(hero.HP))
}

// Revive brings a fallen hero back at half max HP.
func Revive(cur realm) {
	if !cur.Previous().IsUserCall() {
		panic("only a direct EOA call can revive")
	}
	addr := cur.Previous().Address().String()
	v := heroes.Get(addr)
	if v == nil {
		panic("no hero found; call Spawn first")
	}
	hero := v.(*Hero)
	if hero.Alive {
		panic("your hero is not dead")
	}
	hero.Alive = true
	hero.HP = hero.MaxHP / 2
	if hero.HP < 1 {
		hero.HP = 1
	}
	chain.Emit("HeroRevived", "addr", addr, "hp", strconv.Itoa(hero.HP))
}

// levelUp applies every level-up a hero's current XP qualifies for. The
// threshold to reach level N+1 from level N is N*50 XP.
func levelUp(h *Hero) {
	for h.XP >= h.Level*50 {
		h.XP -= h.Level * 50
		h.Level++
		h.MaxHP += 10
		h.HP = h.MaxHP
		h.Attack += 3
	}
}

// byRank orders heroes for the leaderboard: highest level first, then XP,
// then kills, as a tiebreaker.
type byRank []*Hero

func (r byRank) Len() int      { return len(r) }
func (r byRank) Swap(i, j int) { r[i], r[j] = r[j], r[i] }
func (r byRank) Less(i, j int) bool {
	if r[i].Level != r[j].Level {
		return r[i].Level > r[j].Level
	}
	if r[i].XP != r[j].XP {
		return r[i].XP > r[j].XP
	}
	return r[i].Kills > r[j].Kills
}

func collectHeroes() []*Hero {
	var out []*Hero
	heroes.Iterate("", "", func(key string, value any) bool {
		out = append(out, value.(*Hero))
		return false
	})
	return out
}

func hpBar(hp, maxHP int) string {
	if maxHP <= 0 {
		maxHP = 1
	}
	filled := hp * 10 / maxHP
	if filled < 0 {
		filled = 0
	}
	if filled > 10 {
		filled = 10
	}
	bar := strings.Repeat("#", filled) + strings.Repeat("-", 10-filled)
	return "`" + bar + "` " + strconv.Itoa(hp) + "/" + strconv.Itoa(maxHP) + " HP"
}

// Render shows the room overview and leaderboard at path "", or a single
// hero's detail page when path is a bech32 address.
func Render(path string) string {
	path = strings.TrimSpace(path)
	if path != "" {
		return renderHero(path)
	}
	return renderRoom()
}

func renderRoom() string {
	var b strings.Builder
	b.WriteString("# RPG Room\n\n")
	b.WriteString("A single dungeon room with one monster in it at a time. ")
	b.WriteString("Call `Spawn(\"name\")` to enter, `Attack()` to fight the resident monster, ")
	b.WriteString("`Rest()` to heal up, and `Revive()` if you fall.\n\n")

	b.WriteString("## Current monster\n\n")
	b.WriteString("**" + sanitize.InlineText(monster.Name) + "** — level " + strconv.Itoa(monster.Level) + "\n\n")
	b.WriteString(hpBar(monster.HP, monster.MaxHP) + "\n\n")
	b.WriteString("- Attack: " + strconv.Itoa(monster.Attack) + "\n")
	b.WriteString("- Monsters cleared so far: " + strconv.Itoa(totalKills) + "\n\n")

	b.WriteString("## Leaderboard\n\n")
	all := collectHeroes()
	if len(all) == 0 {
		b.WriteString("_No heroes yet. Be the first: `Spawn(\"name\")`._\n")
		return b.String()
	}
	sort.Sort(byRank(all))
	b.WriteString("| # | Hero | Lvl | HP | Kills | Gold | Status |\n")
	b.WriteString("|---|---|---|---|---|---|---|\n")
	limit := len(all)
	if limit > 20 {
		limit = 20
	}
	for i := 0; i < limit; i++ {
		h := all[i]
		status := "alive"
		if !h.Alive {
			status = "fallen"
		}
		b.WriteString("| " + strconv.Itoa(i+1) + " | " + sanitize.InlineText(h.Name) + " | " +
			strconv.Itoa(h.Level) + " | " + strconv.Itoa(h.HP) + "/" + strconv.Itoa(h.MaxHP) + " | " +
			strconv.Itoa(h.Kills) + " | " + strconv.Itoa(h.Gold) + " | " + status + " |\n")
	}
	return b.String()
}

func renderHero(addr string) string {
	v := heroes.Get(addr)
	if v == nil {
		return "> [!WARNING]\n> No hero found for `" + sanitize.InlineText(addr) + "`.\n"
	}
	h := v.(*Hero)
	var b strings.Builder
	b.WriteString("# " + sanitize.InlineText(h.Name) + "\n\n")
	b.WriteString(hpBar(h.HP, h.MaxHP) + "\n\n")
	b.WriteString("- Level: " + strconv.Itoa(h.Level) + "\n")
	b.WriteString("- XP: " + strconv.Itoa(h.XP) + " (next level at " + strconv.Itoa(h.Level*50) + ")\n")
	b.WriteString("- Attack: " + strconv.Itoa(h.Attack) + "\n")
	b.WriteString("- Kills: " + strconv.Itoa(h.Kills) + "\n")
	b.WriteString("- Gold: " + strconv.Itoa(h.Gold) + "\n")
	if !h.Alive {
		b.WriteString("- Status: fallen — call `Revive()` to return\n")
	}
	return b.String()
}
