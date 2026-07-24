// Package polls is an on-chain poll / voting realm for gno.land.
//
// Anyone can create a poll with a question and a comma-separated list of
// options. Each caller address may cast exactly one vote per poll. Render
// draws every poll with its options, tallies as ▓░ bar charts, percentages
// and the total vote count.
package polls

import (
	"chain"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// Poll is a single question with its options and per-address vote tracking.
type Poll struct {
	ID       int
	Question string
	Options  []string
	Tallies  []int
	Creator  string    // bech32 address of the poll creator
	voted    *avl.Tree // address string -> struct{}{}, one vote per address
}

var (
	polls  []*Poll // index i holds the poll with ID i
	nextID int
)

// CreatePoll registers a new poll. options is a comma-separated list; blank
// entries are dropped. Returns the new poll's id. Crossing function: an EOA
// invokes it via MsgCall; another realm via polls.CreatePoll(cross, q, opts).
func CreatePoll(cur realm, question string, options string) int {
	creator := unsafe.PreviousRealm().Address().String()

	q := strings.TrimSpace(question)
	if q == "" {
		panic("question must not be empty")
	}

	opts := parseOptions(options)
	if len(opts) < 2 {
		panic("a poll needs at least 2 options")
	}

	id := nextID
	nextID++
	p := &Poll{
		ID:       id,
		Question: q,
		Options:  opts,
		Tallies:  make([]int, len(opts)),
		Creator:  creator,
		voted:    avl.NewTree(),
	}
	polls = append(polls, p)

	chain.Emit("PollCreated",
		"id", strconv.Itoa(id),
		"creator", creator,
		"options", strconv.Itoa(len(opts)),
	)
	return id
}

// Vote casts one vote for optionIndex on poll pollID. Each caller address may
// vote at most once per poll. Crossing function.
func Vote(cur realm, pollID int, optionIndex int) {
	voter := unsafe.PreviousRealm().Address().String()

	p := getPoll(pollID)
	if optionIndex < 0 || optionIndex >= len(p.Options) {
		panic("option index out of range")
	}
	if _, voted := p.voted.Get(voter); voted {
		panic("address already voted on this poll")
	}

	p.voted.Set(voter, struct{}{})
	p.Tallies[optionIndex]++

	chain.Emit("Voted",
		"id", strconv.Itoa(pollID),
		"voter", voter,
		"option", strconv.Itoa(optionIndex),
	)
}

// parseOptions splits a comma-separated option string, trimming whitespace and
// dropping empties. Pure logic — no realm state.
func parseOptions(options string) []string {
	var out []string
	for _, raw := range strings.Split(options, ",") {
		o := strings.TrimSpace(raw)
		if o != "" {
			out = append(out, o)
		}
	}
	return out
}

// getPoll returns the poll with the given id or panics if it does not exist.
func getPoll(id int) *Poll {
	if id < 0 || id >= len(polls) {
		panic("poll not found")
	}
	return polls[id]
}

// PollCount returns the number of polls created so far (read-only helper).
func PollCount() int {
	return len(polls)
}

const barWidth = 20

// bar renders a proportional ▓░ bar of fixed width for count out of total.
func bar(count, total int) string {
	filled := 0
	if total > 0 {
		filled = count * barWidth / total
	}
	if filled > barWidth {
		filled = barWidth
	}
	return strings.Repeat("▓", filled) + strings.Repeat("░", barWidth-filled)
}

// percent returns the integer percentage of count out of total.
func percent(count, total int) int {
	if total == 0 {
		return 0
	}
	return count * 100 / total
}

// total sums a tally slice.
func total(tallies []int) int {
	sum := 0
	for _, t := range tallies {
		sum += t
	}
	return sum
}

// renderPoll writes one poll's Markdown block into b.
func renderPoll(b *strings.Builder, p *Poll) {
	sum := total(p.Tallies)

	b.WriteString("## Poll #")
	b.WriteString(strconv.Itoa(p.ID))
	b.WriteString(": ")
	b.WriteString(p.Question)
	b.WriteString("\n\n")

	for i, opt := range p.Options {
		c := p.Tallies[i]
		b.WriteString("- **")
		b.WriteString(opt)
		b.WriteString("** `")
		b.WriteString(bar(c, sum))
		b.WriteString("` ")
		b.WriteString(strconv.Itoa(percent(c, sum)))
		b.WriteString("% (")
		b.WriteString(strconv.Itoa(c))
		if c == 1 {
			b.WriteString(" vote)")
		} else {
			b.WriteString(" votes)")
		}
		b.WriteString("\n")
	}

	b.WriteString("\n_Total votes: ")
	b.WriteString(strconv.Itoa(sum))
	b.WriteString("_\n\n")
}

// Render produces the Markdown page for gnoweb. It is NOT a crossing function.
//
//   - ""        -> index of all polls
//   - "<id>"    -> a single poll by id
func Render(path string) string {
	var b strings.Builder

	path = strings.TrimSpace(path)
	if path != "" {
		id, err := strconv.Atoi(path)
		if err != nil || id < 0 || id >= len(polls) {
			return "# Polls\n\nPoll not found.\n"
		}
		b.WriteString("# Polls\n\n")
		renderPoll(&b, polls[id])
		b.WriteString("[← all polls](/r/REPLACE_ADDR/polls)\n")
		return b.String()
	}

	b.WriteString("# Polls & Voting\n\n")
	if len(polls) == 0 {
		b.WriteString("_No polls yet. Create one with `CreatePoll(question, \"a,b,c\")`._\n")
		return b.String()
	}

	b.WriteString("Total polls: ")
	b.WriteString(strconv.Itoa(len(polls)))
	b.WriteString("\n\n")
	for _, p := range polls {
		renderPoll(&b, p)
	}
	return b.String()
}
