// Package commitrevealdemo is a small gnoweb demo of the commit-reveal scheme
// provided by the [p/moul/x/daily/commitreveal](/p/moul/x/daily/commitreveal/v1)
// library: the two phases, and what the salt is for.
//
// It contains no crypto of its own. Stateless, so Render is deterministic —
// which is precisely what the library is for.
package commitrevealdemo

import (
	"strings"

	"gno.land/p/moul/x/daily/commitreveal/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Commit–Reveal\n\n")
	b.WriteString("Bind to a choice without disclosing it, demoing the ")
	b.WriteString("[`p/moul/x/daily/commitreveal`](/p/moul/x/daily/commitreveal/v1) library.\n\n")

	b.WriteString("## The problem\n\n")
	b.WriteString("A transaction is public before it executes. In a sealed-bid auction or ")
	b.WriteString("a simultaneous-move game, whoever moves last reads everyone else's ")
	b.WriteString("move and wins for free.\n\n")

	aliceSalt := "alice-secret-salt-1"
	bobSalt := "bob-secret-salt-0001"
	aliceCommit := commitreveal.MustCommit("rock", aliceSalt)
	bobCommit := commitreveal.MustCommit("paper", bobSalt)

	b.WriteString("## Phase 1 — commit\n\n")
	b.WriteString("Each player publishes only `H(value ‖ salt)`. Nothing about the move ")
	b.WriteString("leaks, but neither can change it later.\n\n")
	b.WriteString("| player | commitment |\n|---|---|\n")
	b.WriteString("| alice | `" + short(aliceCommit) + "` |\n")
	b.WriteString("| bob | `" + short(bobCommit) + "` |\n")

	b.WriteString("\n## Phase 2 — reveal\n\n")
	b.WriteString("Now the values and salts are published and checked against the ")
	b.WriteString("commitments recorded earlier:\n\n")
	b.WriteString("| check | result |\n|---|---|\n")
	row(&b, "alice opens with `rock`", commitreveal.Open(aliceCommit, "rock", aliceSalt))
	row(&b, "bob opens with `paper`", commitreveal.Open(bobCommit, "paper", bobSalt))
	row(&b, "bob tries `scissors` instead", commitreveal.Open(bobCommit, "scissors", bobSalt))
	row(&b, "bob claims alice's commitment", commitreveal.Open(aliceCommit, "rock", bobSalt))

	b.WriteString("\nBob cannot switch his move after seeing Alice's, and cannot pass off ")
	b.WriteString("her commitment as his own.\n\n")

	b.WriteString("## Why the salt is mandatory\n\n")
	b.WriteString("Rock-paper-scissors has three possible moves. Without a salt there are ")
	b.WriteString("exactly three possible hashes, and hashing all three breaks the scheme ")
	b.WriteString("outright. The library refuses a salt shorter than `")
	b.WriteString(itoa(commitreveal.MinSaltLen) + "` bytes rather than leaving that as advice:\n\n")
	_, err := commitreveal.Commit("rock", "tooshort")
	b.WriteString("- `Commit(\"rock\", \"tooshort\")` → `")
	if err != nil {
		b.WriteString(err.Error())
	}
	b.WriteString("`\n\n")
	b.WriteString("The salt also keeps two players who pick the *same* move from ")
	b.WriteString("publishing the same commitment:\n\n")
	one := commitreveal.MustCommit("rock", "salt-one-0123456789")
	two := commitreveal.MustCommit("rock", "salt-two-0123456789")
	b.WriteString("| same move, different salt | commitment |\n|---|---|\n")
	b.WriteString("| player 1 | `" + short(one) + "` |\n")
	b.WriteString("| player 2 | `" + short(two) + "` |\n")

	b.WriteString("\n## Two details that are easy to get wrong\n\n")
	b.WriteString("- **Length-prefixed hashing.** With plain concatenation `(\"ab\",\"cd…\")` ")
	b.WriteString("and `(\"abc\",\"d…\")` hash identically, so one commitment could be opened ")
	b.WriteString("two different ways.\n")
	b.WriteString("- **Constant-time comparison.** A short-circuiting check leaks, through ")
	b.WriteString("timing, how many leading bytes of a guess were right — enough to rebuild ")
	b.WriteString("a commitment byte by byte.\n")
	return b.String()
}

func row(b *strings.Builder, label string, err error) {
	b.WriteString("| " + label + " | ")
	if err == nil {
		b.WriteString("✅ accepted")
	} else {
		b.WriteString("❌ `" + err.Error() + "`")
	}
	b.WriteString(" |\n")
}

func short(c string) string { return c[:16] + "…" }

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	s := ""
	for i > 0 {
		s = string(rune('0'+i%10)) + s
		i /= 10
	}
	return s
}
