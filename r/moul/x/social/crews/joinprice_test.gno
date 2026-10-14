package crews

import (
	"strconv"
	"strings"
	"testing"

	"chain"

	"gno.land/p/moul/x/social/crew/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// The price a crew page shows a joiner, and the floor Join's envelope guard
// enforces, must both be exactly the least amount that mints a whole share.
//
// Join mints amount * totalShares / treasury, rounded down, so that amount is
// treasury / totalShares rounded UP. Rounded down instead, it is one ugnot
// short whenever the treasury is not an exact multiple of the share count,
// which is the ordinary state after any Fund: the page quotes a price, the
// guard accepts it, and the join reverts on "buys no whole share".
//
// The table is over that rule, not over one input: awkward remainders where
// floor and ceiling differ, exact multiples where they must not, and a crew
// everybody left, where the opening price applies.
func TestTheShownPriceBuysAShareAndOneLessIsRefusedByTheGuard(cur realm, t *testing.T) {
	cases := []struct {
		name   string
		create int64 // what the founder pays in, at the opening price
		fund   int64 // then funded with this, which mints nothing
		leave  bool  // then the founder ragequits, leaving an empty crew
		want   int64 // the least amount that mints one share
	}{
		{"treasury 3001 over 2 shares", 2000, 1001, false, 1501},
		{"treasury 3001 over 3 shares", 3000, 1, false, 1001},
		{"ten GNOT and seven ugnot over 10000 shares", tenGNOT, 7, false, 1001},
		{"ten GNOT and 999 ugnot over 10000 shares", tenGNOT, 999, false, 1001},
		{"exact multiple at the opening price", tenGNOT, 0, false, 1000},
		{"exact multiple after doubling", tenGNOT, tenGNOT, false, 2000},
		{"a single share", 1000, 0, false, 1000},
		{"everybody left", 1000, 0, true, crew.InitialPricePerShare},
	}
	for _, tc := range cases {
		reset()
		id := create(cur, alice, tc.create, "crew")
		if tc.fund > 0 {
			fund(cur, carol, tc.fund, id)
		}
		if tc.leave {
			testing.SetRealm(testing.NewUserRealm(alice))
			Ragequit(cross(cur), id)
		}

		// The oracle, independent of the code under test: the least a with
		// a * shares >= treasury, or the opening price when nobody holds one.
		_, _, _, shares, treasury := Get(id)
		oracle := crew.InitialPricePerShare
		if shares > 0 && treasury > 0 {
			oracle = treasury / shares
			if treasury%shares != 0 {
				oracle++
			}
		}
		urequire.Equal(t, tc.want, oracle, tc.name+": the table agrees with the rule")

		page := Render("crew/" + strconv.FormatInt(id, 10))
		uassert.Equal(t, tc.want, shownPrice(t, page),
			tc.name+": the page quotes what buys a share: "+page)

		// One ugnot under it is refused by the envelope guard, which names the
		// real price, rather than by Join after the guard let it through.
		testing.IssueCoins(realmAddr, chain.Coins{{denom, tc.want - 1}})
		testing.SetOriginSend(chain.Coins{{denom, tc.want - 1}})
		testing.SetRealm(testing.NewUserRealm(bob))
		uassert.AbortsContains(t, cur, "costs at least "+strconv.FormatInt(tc.want, 10)+denom,
			func() { Join(cross(cur), id) }, tc.name+": the guard refuses one ugnot short")

		// Exactly the quoted price buys exactly one share.
		got := join(cur, bob, tc.want, id)
		uassert.Equal(t, int64(1), got, tc.name+": the quoted price mints one share")
	}
}

// shownPrice reads the price cell of a crew page's summary table, the first
// row after the header that starts with "| members", in ugnot. It is keyed on
// the row's position, not the column's title, so it reads the same cell
// whatever that column is called.
func shownPrice(t *testing.T, page string) int64 {
	lines := strings.Split(page, "\n")
	for i, l := range lines {
		if !strings.HasPrefix(l, "| members") {
			continue
		}
		urequire.True(t, i+2 < len(lines), "the summary table has a row: "+page)
		cells := strings.Split(lines[i+2], "|")
		urequire.Equal(t, 6, len(cells), "four cells: "+lines[i+2])
		return parseGNOT(t, strings.TrimSpace(cells[4]))
	}
	t.Fatalf("no summary table on the crew page: %s", page)
	return 0
}

// parseGNOT turns num.GNOTf's "1.0015 GNOT" back into ugnot.
func parseGNOT(t *testing.T, s string) int64 {
	urequire.True(t, strings.HasSuffix(s, " GNOT"), "a GNOT amount: "+s)
	s = strings.TrimSuffix(s, " GNOT")
	whole, frac := s, ""
	if i := strings.Index(s, "."); i >= 0 {
		whole, frac = s[:i], s[i+1:]
	}
	urequire.True(t, len(frac) <= 6, "at most six decimals: "+s)
	frac += strings.Repeat("0", 6-len(frac))
	w, err := strconv.ParseInt(whole, 10, 64)
	urequire.NoError(t, err, s)
	f, err := strconv.ParseInt(frac, 10, 64)
	urequire.NoError(t, err, s)
	return w*1000000 + f
}
