// Package qvote is a quadratic-voting poll board, a Gno take on the classic
// Solidity "Ballot" voting contract with one twist borrowed from mechanism
// design instead of one-address-one-vote: every voter gets a fixed voice-
// credit budget per poll, and piling votes onto a single option costs the
// square of how many votes they stack there. Buying your 1st vote on an
// option costs 1 credit, the 2nd costs 3 more (4 total), the 3rd costs 5
// more (9 total) -- so spreading conviction across options is cheap, but
// dominating one option gets expensive fast. Votes can also be pulled back
// for a matching credit refund.
package qvote

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// InitialCredits is the fixed voice-credit budget every address gets to
// spend on each poll (shared across all of that poll's options).
const InitialCredits int64 = 100

const (
	minOptions = 2
	maxOptions = 8
)

type poll struct {
	ID            string
	Creator       address
	Question      string
	Options       []string
	Tally         []int64
	CreatedHeight int64
	Closed        bool
}

// voterState is one address's standing inside one poll: how many credits
// they've spent so far and how many votes that bought them on each option.
type voterState struct {
	CreditsUsed int64
	Votes       []int64
}

var (
	polls  avl.Tree // poll ID -> *poll
	voters avl.Tree // "<pollID>:<addr>" -> *voterState
	nextID int
)

func voterKey(pollID string, addr address) string {
	return pollID + ":" + addr.String()
}

func getPoll(pollID string) *poll {
	p, ok := polls.Get(pollID).(*poll)
	if !ok {
		panic("no such poll: " + pollID)
	}
	return p
}

func getOrCreateVoter(pollID string, addr address, numOptions int) *voterState {
	key := voterKey(pollID, addr)
	if v, ok := voters.Get(key).(*voterState); ok {
		return v
	}
	vs := &voterState{Votes: make([]int64, numOptions)}
	voters.Set(key, vs)
	return vs
}

// square is the quadratic-voting cost curve: N votes on one option cost
// N*N credits in total.
func square(n int64) int64 {
	return n * n
}

// CreatePoll opens a new poll with the given question and comma-separated
// options (at least 2, at most 8), returning its ID.
func CreatePoll(cur realm, question string, optionsCSV string) string {
	creator := cur.Previous().Address()

	question = strings.TrimSpace(question)
	if question == "" {
		panic("question must not be empty")
	}

	var options []string
	for _, raw := range strings.Split(optionsCSV, ",") {
		opt := strings.TrimSpace(raw)
		if opt == "" {
			continue
		}
		options = append(options, opt)
	}
	if len(options) < minOptions {
		panic("need at least " + strconv.Itoa(minOptions) + " non-empty options")
	}
	if len(options) > maxOptions {
		panic("at most " + strconv.Itoa(maxOptions) + " options are allowed")
	}

	nextID++
	id := strconv.Itoa(nextID)
	p := &poll{
		ID:            id,
		Creator:       creator,
		Question:      question,
		Options:       options,
		Tally:         make([]int64, len(options)),
		CreatedHeight: runtime.ChainHeight(),
	}
	polls.Set(id, p)

	chain.Emit("PollCreated", "id", id, "creator", creator.String(), "question", question)

	return "poll #" + id + " created with " + strconv.Itoa(len(options)) + " options"
}

// Vote adjusts the caller's votes on one option of a poll by delta (positive
// to buy more, negative to sell some back for a credit refund). The credit
// cost of holding N votes on an option is N*N, taken from the caller's fixed
// per-poll budget of InitialCredits.
func Vote(cur realm, pollID string, optionIdx int, delta int64) string {
	caller := cur.Previous().Address()

	p := getPoll(pollID)
	if p.Closed {
		panic("poll #" + pollID + " is closed")
	}
	if optionIdx < 0 || optionIdx >= len(p.Options) {
		panic("invalid option index")
	}
	if delta == 0 {
		panic("delta must be non-zero")
	}

	vs := getOrCreateVoter(pollID, caller, len(p.Options))
	current := vs.Votes[optionIdx]
	updated := current + delta
	if updated < 0 {
		panic("cannot remove more votes than you hold on this option")
	}

	cost := square(updated) - square(current)
	newCreditsUsed := vs.CreditsUsed + cost
	if newCreditsUsed > InitialCredits {
		panic("exceeds your voice-credit budget of " + strconv.FormatInt(InitialCredits, 10) +
			" for this poll (would need " + strconv.FormatInt(newCreditsUsed, 10) + ")")
	}

	vs.Votes[optionIdx] = updated
	vs.CreditsUsed = newCreditsUsed
	p.Tally[optionIdx] += delta

	chain.Emit("VoteCast",
		"pollID", pollID,
		"voter", caller.String(),
		"option", p.Options[optionIdx],
		"votes", strconv.FormatInt(updated, 10),
	)

	verb := "bought"
	n := delta
	if delta < 0 {
		verb = "sold back"
		n = -delta
	}
	return "you " + verb + " " + strconv.FormatInt(n, 10) + " vote(s) on \"" + p.Options[optionIdx] +
		"\" -- now holding " + strconv.FormatInt(updated, 10) + " (credits used: " +
		strconv.FormatInt(vs.CreditsUsed, 10) + "/" + strconv.FormatInt(InitialCredits, 10) + ")"
}

// ClosePoll ends voting on a poll. Only its creator may close it.
func ClosePoll(cur realm, pollID string) string {
	caller := cur.Previous().Address()

	p := getPoll(pollID)
	if caller != p.Creator {
		panic("only the poll creator can close it")
	}
	if p.Closed {
		panic("poll #" + pollID + " is already closed")
	}
	p.Closed = true

	chain.Emit("PollClosed", "id", pollID)

	return "poll #" + pollID + " closed"
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

func leadingOption(p *poll) (string, int64) {
	best := -1
	var bestVotes int64 = -1
	for i, v := range p.Tally {
		if v > bestVotes {
			bestVotes = v
			best = i
		}
	}
	if best < 0 {
		return "", 0
	}
	return p.Options[best], bestVotes
}

func renderHome() string {
	var b strings.Builder
	b.WriteString("# Quadratic Voting\n\n")
	b.WriteString("Create a poll, then spend voice credits on the options you care about -- " +
		"the Nth vote you stack on one option costs N^2 credits out of a fixed budget of " +
		strconv.FormatInt(InitialCredits, 10) + " per poll, so spreading support across " +
		"options is cheap but dominating one gets steep fast.\n\n")

	b.WriteString("## Polls\n\n")
	count := 0
	polls.Iterate("", "", func(key string, value interface{}) bool {
		count++
		p := value.(*poll)
		status := "open"
		if p.Closed {
			status = "closed"
		}
		lead, votes := leadingOption(p)
		line := "- #" + p.ID + " (" + status + "): " + escapeInline(p.Question)
		if lead != "" {
			line += " -- leading: \"" + escapeInline(lead) + "\" (" + strconv.FormatInt(votes, 10) + ")"
		}
		b.WriteString(line + "\n")
		return false
	})
	if count == 0 {
		b.WriteString("_no polls yet -- call `CreatePoll(question, \"opt1,opt2,...\")` to start one._\n")
	}

	b.WriteString("\n## How to use\n\n")
	b.WriteString("1. `CreatePoll(\"Best pizza topping?\", \"pineapple,mushroom,pepperoni\")` -- returns a poll ID.\n")
	b.WriteString("2. `Vote(pollID, optionIdx, delta)` -- e.g. `Vote(\"1\", 0, 3)` buys 3 votes on option 0 " +
		"(costs 9 credits); a negative delta sells votes back for a refund.\n")
	b.WriteString("3. `ClosePoll(pollID)` -- the creator ends voting.\n\n")
	b.WriteString("View a poll at this realm's path plus its ID (e.g. `.../qvote:1`), " +
		"or one voter's standing in it with `.../qvote:1/g1youraddress...`.\n")

	return b.String()
}

func renderPoll(id string) string {
	p, ok := polls.Get(id).(*poll)
	if !ok {
		return "# Poll #" + escapeInline(id) + "\n\nNo such poll.\n"
	}

	var b strings.Builder
	b.WriteString("# Poll #" + p.ID + ": " + escapeInline(p.Question) + "\n\n")
	status := "open"
	if p.Closed {
		status = "closed"
	}
	b.WriteString("- Status: " + status + "\n")
	b.WriteString("- Creator: `" + p.Creator.String() + "`\n\n")

	b.WriteString("## Results\n\n")
	var total int64
	for _, v := range p.Tally {
		total += v
	}
	for i, opt := range p.Options {
		b.WriteString(strconv.Itoa(i) + ". " + escapeInline(opt) + " -- " +
			strconv.FormatInt(p.Tally[i], 10) + " vote(s)\n")
	}
	b.WriteString("\nTotal votes cast: " + strconv.FormatInt(total, 10) + "\n")

	return b.String()
}

func renderVoter(pollID, rawAddr string) string {
	safeAddr := escapeInline(strings.TrimSpace(rawAddr))
	p, ok := polls.Get(pollID).(*poll)
	if !ok {
		return "# Poll #" + escapeInline(pollID) + "\n\nNo such poll.\n"
	}

	var b strings.Builder
	b.WriteString("# " + safeAddr + " in poll #" + p.ID + "\n\n")

	state, ok := voters.Get(voterKey(pollID, address(strings.TrimSpace(rawAddr)))).(*voterState)
	if !ok {
		b.WriteString("No votes cast yet.\n")
		return b.String()
	}

	b.WriteString("- Credits used: " + strconv.FormatInt(state.CreditsUsed, 10) + "/" +
		strconv.FormatInt(InitialCredits, 10) + "\n\n")
	for i, opt := range p.Options {
		if state.Votes[i] == 0 {
			continue
		}
		b.WriteString("- " + escapeInline(opt) + ": " + strconv.FormatInt(state.Votes[i], 10) + " vote(s)\n")
	}

	return b.String()
}

// Render shows the poll board at "", one poll's results at "<pollID>", or
// one voter's standing in a poll at "<pollID>/<addr>".
func Render(path string) string {
	path = strings.TrimPrefix(strings.TrimSpace(path), "/")
	if path == "" {
		return renderHome()
	}
	if idx := strings.IndexByte(path, '/'); idx >= 0 {
		return renderVoter(path[:idx], path[idx+1:])
	}
	return renderPoll(path)
}
