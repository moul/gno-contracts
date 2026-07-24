// Package reactions is an emoji reaction board.
//
// Each topic collects emoji reactions. A caller may register at most one
// reaction per topic; the emoji they picked increments a per-topic per-emoji
// tally. Render lists every topic with its emoji tallies and total count.
package reactions

import (
	"sort"
	"strconv"
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// topic holds the tallies and the set of callers who already reacted.
type topic struct {
	name    string
	tallies *avl.Tree // emoji (string) -> count (int)
	voters  *avl.Tree // caller address (string) -> struct{}
	total   int
}

// topics maps topic name -> *topic, kept in an avl.Tree for deterministic order.
var topics = avl.NewTree()

func getOrPanic(name string) *topic {
	v, ok := topics.Get(name)
	if !ok {
		panic("topic does not exist: " + name)
	}
	return v.(*topic)
}

func newTopic(name string) *topic {
	t := &topic{
		name:    name,
		tallies: avl.NewTree(),
		voters:  avl.NewTree(),
	}
	topics.Set(name, t)
	return t
}

// CreateTopic registers a new empty topic. It is optional: React auto-creates
// a topic if it does not exist yet. Panics if the topic already exists or the
// name is empty.
func CreateTopic(cur realm, name string) {
	name = strings.TrimSpace(name)
	if name == "" {
		panic("topic name must not be empty")
	}
	if topics.Has(name) {
		panic("topic already exists: " + name)
	}
	newTopic(name)
	chain.Emit("TopicCreated", "topic", name)
}

// React adds the caller's reaction (an emoji) to a topic. Each caller may react
// at most once per topic. The topic is created on demand if missing. Panics on
// empty input or when the caller has already reacted to this topic.
func React(cur realm, name, emoji string) {
	name = strings.TrimSpace(name)
	emoji = strings.TrimSpace(emoji)
	if name == "" {
		panic("topic name must not be empty")
	}
	if emoji == "" {
		panic("emoji must not be empty")
	}

	caller := unsafe.PreviousRealm().Address().String()

	var t *topic
	if v, ok := topics.Get(name); ok {
		t = v.(*topic)
	} else {
		t = newTopic(name)
	}

	if t.voters.Has(caller) {
		panic("caller already reacted to this topic: " + name)
	}
	t.voters.Set(caller, struct{}{})

	count := 0
	if v, ok := t.tallies.Get(emoji); ok {
		count = v.(int)
	}
	t.tallies.Set(emoji, count+1)
	t.total++

	chain.Emit("Reacted", "topic", name, "emoji", emoji)
}

// TopicCount returns the number of topics on the board.
func TopicCount() int {
	return topics.Size()
}

// emojiTally is used to sort a topic's tallies deterministically.
type emojiTally struct {
	emoji string
	count int
}

// byCountDesc sorts tallies by count descending, then emoji ascending.
type byCountDesc []emojiTally

func (s byCountDesc) Len() int      { return len(s) }
func (s byCountDesc) Swap(i, j int) { s[i], s[j] = s[j], s[i] }
func (s byCountDesc) Less(i, j int) bool {
	if s[i].count != s[j].count {
		return s[i].count > s[j].count
	}
	return s[i].emoji < s[j].emoji
}

func (t *topic) sortedTallies() []emojiTally {
	out := make([]emojiTally, 0, t.tallies.Size())
	t.tallies.Iterate("", "", func(key string, value interface{}) bool {
		out = append(out, emojiTally{emoji: key, count: value.(int)})
		return false
	})
	sort.Stable(byCountDesc(out))
	return out
}

// tallyRow renders a topic's tallies as e.g. "👍 3  ❤️ 5  🎉 1".
func (t *topic) tallyRow() string {
	if t.tallies.Size() == 0 {
		return "_no reactions yet_"
	}
	rows := t.sortedTallies()
	parts := make([]string, 0, len(rows))
	for _, r := range rows {
		parts = append(parts, r.emoji+" "+strconv.Itoa(r.count))
	}
	return strings.Join(parts, "  ")
}

// Render returns a Markdown view of the board. If path is a non-empty topic
// name, only that topic is shown; otherwise all topics are listed.
func Render(path string) string {
	path = strings.TrimSpace(strings.Trim(path, "/"))

	if path != "" {
		v, ok := topics.Get(path)
		if !ok {
			return "# Reaction Board\n\nTopic not found: `" + path + "`\n"
		}
		t := v.(*topic)
		var sb strings.Builder
		sb.WriteString("# Reaction Board — " + t.name + "\n\n")
		sb.WriteString(t.tallyRow() + "\n\n")
		sb.WriteString("**Total reactions:** " + strconv.Itoa(t.total) + "\n")
		return sb.String()
	}

	var sb strings.Builder
	sb.WriteString("# Reaction Board\n\n")
	if topics.Size() == 0 {
		sb.WriteString("_No topics yet. Call `React(cur, topic, emoji)` to start._\n")
		return sb.String()
	}

	grand := 0
	topics.Iterate("", "", func(key string, value interface{}) bool {
		t := value.(*topic)
		grand += t.total
		sb.WriteString("## " + t.name + "\n\n")
		sb.WriteString(t.tallyRow() + "\n\n")
		sb.WriteString("Total: " + strconv.Itoa(t.total) + "\n\n")
		return false
	})

	sb.WriteString("---\n\n")
	sb.WriteString("**Topics:** " + strconv.Itoa(topics.Size()) +
		" · **Reactions:** " + strconv.Itoa(grand) + "\n")
	return sb.String()
}
