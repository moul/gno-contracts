package idle

import (
	"sort"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
)

// Render shows every mine, or one mine's card at /r/.../idle:<address>.
//
// The numbers move on their own: the same URL renders differently a minute
// later because the mine kept digging, and nothing wrote to the chain in
// between. That is the whole point of the accrual pair, and it is why every
// figure here comes from the read-only view rather than from stored state.
func Render(path string) string {
	at := now()
	if addr := strings.TrimSpace(path); addr != "" {
		return card(address(addr), at)
	}
	return board(at)
}

// byLifetimeThenOwner ranks by lifetime ore, then by address so the order is
// identical on every node.
type byLifetimeThenOwner []*mine

func (r byLifetimeThenOwner) Len() int      { return len(r) }
func (r byLifetimeThenOwner) Swap(i, j int) { r[i], r[j] = r[j], r[i] }
func (r byLifetimeThenOwner) Less(i, j int) bool {
	if r[i].prestige != r[j].prestige {
		return r[i].prestige > r[j].prestige
	}
	if r[i].lifetime != r[j].lifetime {
		return r[i].lifetime > r[j].lifetime
	}
	return r[i].owner.String() < r[j].owner.String()
}

func board(at int64) string {
	var b strings.Builder
	b.WriteString("# The Mine\n\n")
	b.WriteString("Ore accrues while you are away. The mine holds " +
		strconv.FormatInt(CapPeriods, 10) + " periods of production and then spills, so the only thing that costs you anything is not showing up.\n\n")

	all := []*mine{}
	mines.Iterate("", "", func(_ string, v any) bool {
		all = append(all, v.(*mine))
		return false
	})
	sort.Sort(byLifetimeThenOwner(all))

	t := ui.NewTable("#", "Miner", "Lv", "Prestige", "In the mine", "Banked", "Lifetime")
	for i, m := range all {
		pending := m.view(at)
		full := ""
		if r := m.fullAt(at); r > at {
			full = " (" + span(r-at) + " to spill)"
		} else {
			full = " (**full**)"
		}
		t.Row(
			ui.Podium(i)+strconv.Itoa(i+1),
			ui.Addr(m.owner),
			strconv.FormatInt(m.level, 10),
			strconv.FormatInt(m.prestige, 10),
			strconv.FormatInt(pending, 10)+full,
			strconv.FormatInt(m.banked, 10),
			strconv.FormatInt(m.lifetime, 10),
		)
	}
	b.WriteString(t.OrEmpty("Nobody is digging yet."))
	b.WriteString("\n")
	b.WriteString(ui.Join(" | ",
		ui.Action("Open a mine", "Start"),
		ui.Action("Claim", "Claim"),
		ui.Action("Upgrade", "Upgrade"),
		ui.Action("Prestige", "Prestige"),
	))
	b.WriteString("\n")
	return b.String()
}

func card(owner address, at int64) string {
	m, ok := get(owner)
	if !ok {
		return "# The Mine\n\n" + ui.Empty("No mine at "+ui.Addr(owner)+".")
	}

	pending := m.view(at)
	r := rate(m.level, m.prestige)
	var b strings.Builder

	b.WriteString("# " + ui.Addr(m.owner) + "'s mine\n\n")
	b.WriteString("Level **" + strconv.FormatInt(m.level, 10) + "**")
	if m.prestige > 0 {
		b.WriteString(", prestige **" + strconv.FormatInt(m.prestige, 10) + "**")
	}
	b.WriteString(", digging **" + strconv.FormatInt(r.Amount, 10) + "** ore every " +
		span(Period) + ".\n\n")

	t := ui.NewTable("", "")
	t.Row("In the mine", strconv.FormatInt(pending, 10)+" / "+strconv.FormatInt(r.Cap, 10))
	if full := m.fullAt(at); full > at {
		t.Row("Spills in", span(full-at))
	} else {
		t.Row("Spills in", "**already full, every period is being wasted**")
	}
	t.Row("Banked", strconv.FormatInt(m.banked, 10))
	t.Row("Lifetime ore", strconv.FormatInt(m.lifetime, 10))
	t.Row("Claims", strconv.FormatInt(m.claims, 10))
	t.Row("Digging for", span(at-m.started))
	if m.level < MaxLevel {
		cost := upgradeCost(m.level)
		short := cost - m.banked
		next := strconv.FormatInt(cost, 10) + " ore"
		if short > 0 {
			next += " (" + strconv.FormatInt(short, 10) + " short)"
		} else {
			next += " (**affordable now**)"
		}
		t.Row("Next level", next)
	}
	if m.prestige < MaxPrestige {
		if m.level >= PrestigeAt {
			t.Row("Prestige", "**available**, and it burns "+
				strconv.FormatInt(m.banked+pending, 10)+" ore")
		} else {
			t.Row("Prestige", "at level "+strconv.FormatInt(PrestigeAt, 10)+
				", "+strconv.FormatInt(PrestigeAt-m.level, 10)+" to go")
		}
	}
	b.WriteString(t.String())
	b.WriteString("\n")
	b.WriteString(ui.Join(" | ",
		ui.Action("Claim", "Claim"),
		ui.Action("Upgrade", "Upgrade"),
		ui.Action("Prestige", "Prestige"),
	))
	b.WriteString("\n")
	return b.String()
}

// span renders a number of seconds the way a player reads it. It rounds down
// and stops at two units, because "2h 3m 11s to spill" is noise when the
// question is whether to claim now or after lunch.
func span(secs int64) string {
	if secs <= 0 {
		return "0s"
	}
	units := []struct {
		size int64
		name string
	}{
		{86400, "d"},
		{3600, "h"},
		{60, "m"},
		{1, "s"},
	}
	parts := []string{}
	for i, u := range units {
		if secs < u.size {
			continue
		}
		n := secs / u.size
		secs -= n * u.size
		parts = append(parts, strconv.FormatInt(n, 10)+u.name)
		if len(parts) == 2 || i == len(units)-1 {
			break
		}
	}
	return strings.Join(parts, " ")
}
