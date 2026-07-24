package kudos

import (
	"chain"
	"chain/runtime/unsafe"
	"sort"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// counts maps an address (as string) -> number of kudos received.
var counts avl.Tree

// feed holds recent kudos, newest first, capped at feedCap entries.
var feed []kudo

const feedCap = 50

type kudo struct {
	from   address
	to     address
	reason string
}

// Give records a kudos from the caller to `to` with a reason.
// A caller cannot give kudos to themselves.
func Give(cur realm, to address, reason string) {
	from := unsafe.PreviousRealm().Address()
	if !to.IsValid() {
		panic("invalid recipient address")
	}
	if from == to {
		panic("cannot give kudos to yourself")
	}
	reason = strings.TrimSpace(reason)
	if reason == "" {
		panic("reason must not be empty")
	}

	key := to.String()
	n := int64(0)
	if v, ok := counts.Get(key); ok {
		n = v.(int64)
	}
	counts.Set(key, n+1)

	// prepend newest, cap the feed
	feed = append([]kudo{{from: from, to: to, reason: reason}}, feed...)
	if len(feed) > feedCap {
		feed = feed[:feedCap]
	}

	chain.Emit("KudosGiven", "from", from.String(), "to", to.String(), "reason", reason)
}

// entry is a leaderboard row used for deterministic sorting.
type entry struct {
	addr  string
	count int64
}

// byScore sorts by count desc, then address asc for stable ties.
type byScore []entry

func (s byScore) Len() int      { return len(s) }
func (s byScore) Swap(i, j int) { s[i], s[j] = s[j], s[i] }
func (s byScore) Less(i, j int) bool {
	if s[i].count != s[j].count {
		return s[i].count > s[j].count
	}
	return s[i].addr < s[j].addr
}

func leaderboard() []entry {
	out := make([]entry, 0, counts.Size())
	counts.Iterate("", "", func(key string, value any) bool {
		out = append(out, entry{addr: key, count: value.(int64)})
		return false
	})
	sort.Sort(byScore(out))
	return out
}

// Render shows a leaderboard of most-received addresses and a recent feed.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Kudos\n\n")
	b.WriteString("Give props to addresses. `Give(to, reason)` records a kudos.\n\n")

	b.WriteString("## Leaderboard\n\n")
	lb := leaderboard()
	if len(lb) == 0 {
		b.WriteString("_No kudos yet._\n\n")
	} else {
		b.WriteString("| # | Address | Kudos |\n")
		b.WriteString("| --- | --- | --- |\n")
		for i, e := range lb {
			b.WriteString("| " + strconv.Itoa(i+1) + " | " + e.addr + " | " + strconv.FormatInt(e.count, 10) + " |\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("## Recent kudos\n\n")
	if len(feed) == 0 {
		b.WriteString("_Nothing here yet._\n")
	} else {
		for _, k := range feed {
			b.WriteString("- " + k.from.String() + " → " + k.to.String() + ": " + k.reason + "\n")
		}
	}

	return b.String()
}
