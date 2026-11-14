// Package murmur3demo is a small gnoweb demo of the MurmurHash3 x86_32 hash
// provided by the [p/moul/x/daily/murmur3](/p/moul/x/daily/murmur3/v0)
// library: it hashes a few strings, runs the SMHasher self-test on chain, and
// shows a thousand keys spreading evenly over eight shards.
//
// It contains no hashing logic of its own. Stateless, so Render is
// deterministic.
package murmur3demo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/murmur3/v0"
)

var samples = []string{"", "a", "abc", "123456789", "hello world", "hello worle"}

// shards is the bucket count the spread table demonstrates.
const shards = 8

// keys is how many synthetic keys the spread table distributes.
const keys = 1000

// Render renders the demo for gnoweb.
//
//	Render("")       / Render("/") -> the samples, the self-test, the spread
//	Render("/<text>")              -> hash and shard that text
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# MurmurHash3 x86_32\n\n")
	b.WriteString("Austin Appleby's non-cryptographic hash, demoing the ")
	b.WriteString("[`p/moul/x/daily/murmur3`](/p/moul/x/daily/murmur3/v0) library.\n\n")

	if in := parseArg(path); in != "" {
		b.WriteString("## " + md.InlineCode(in) + "\n\n")
		t := ui.NewTable("seed", "hash", "bucket of 8")
		t.Row("0", md.InlineCode(murmur3.SumHex(in)), strconv.Itoa(murmur3.Bucket(in, shards)))
		t.Row("1", md.InlineCode(murmur3.Hex(murmur3.Sum32Seed(in, 1))), "n/a")
		b.WriteString(t.String())
		b.WriteString("\nTwo seeds, two unrelated results: that is how one function ")
		b.WriteString("becomes a family of them.\n")
		return b.String()
	}

	b.WriteString("## Vectors\n\n")
	st := ui.NewTable("input", "seed 0", "seed 1")
	for _, s := range samples {
		label := "_(empty)_"
		if s != "" {
			label = md.InlineCode(s)
		}
		st.Row(label, md.InlineCode(murmur3.SumHex(s)), md.InlineCode(murmur3.Hex(murmur3.Sum32Seed(s, 1))))
	}
	b.WriteString(st.String())
	b.WriteString("\nThe last two inputs differ by one letter and share no digits. ")
	b.WriteString("That avalanche is the finalizer doing its job.\n\n")

	b.WriteString("## Self-test\n\n")
	b.WriteString("SMHasher hashes 256 growing keys under 256 seeds and hashes the ")
	b.WriteString("results. For MurmurHash3 x86_32 the answer is `b0f57ee3`, and this ")
	b.WriteString("realm computes it on chain every time you load the page:\n\n")
	b.WriteString("`" + murmur3.Hex(murmur3.Verification()) + "`\n\n")

	b.WriteString("## Spread\n\n")
	b.WriteString("`key-0` through `key-" + strconv.Itoa(keys-1) + "` over " +
		strconv.Itoa(shards) + " buckets. A hash worth using fills all of them:\n\n")
	counts := make([]int, shards)
	for i := 0; i < keys; i++ {
		counts[murmur3.Bucket("key-"+strconv.Itoa(i), shards)]++
	}
	bt := ui.NewTable("bucket", "keys", "")
	for i, c := range counts {
		bt.Row(strconv.Itoa(i), strconv.Itoa(c), strings.Repeat("#", c/10))
	}
	b.WriteString(bt.String())

	b.WriteString("\nAppend a path to hash your own text: ")
	b.WriteString("[`/gno.land`](/r/moul/x/daily/murmur3demo/v0:gno.land)\n\n")
	b.WriteString("> ⚠️ **Not a cryptographic hash.** MurmurHash3 is invertible and ")
	b.WriteString("collisions are cheap to generate, so anyone who picks the keys can ")
	b.WriteString("pick the bucket. Use it to spread, never to commit or authenticate.\n")
	return b.String()
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
