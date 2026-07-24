package moodstone

import (
	"chain/runtime"
	"strconv"
	"strings"
)

// Entry holds a single mood log.
type Entry struct {
	Author address
	Mood   string
	Note   string
	Block  int64
}

var entries []Entry

var validMoods = []string{"happy", "sad", "excited", "calm", "anxious", "angry", "neutral"}

func isValid(mood string) bool {
	for _, m := range validMoods {
		if m == mood {
			return true
		}
	}
	return false
}

func emoji(mood string) string {
	switch mood {
	case "happy":
		return "😊"
	case "sad":
		return "😢"
	case "excited":
		return "🎉"
	case "calm":
		return "😌"
	case "anxious":
		return "😰"
	case "angry":
		return "😠"
	case "neutral":
		return "😐"
	}
	return "❓"
}

func shortAddr(addr address) string {
	s := addr.String()
	if len(s) <= 12 {
		return s
	}
	return s[:6] + "…" + s[len(s)-4:]
}

func bar(count, total int) string {
	if total == 0 {
		return strings.Repeat("░", 20)
	}
	filled := (count * 20) / total
	return strings.Repeat("▓", filled) + strings.Repeat("░", 20-filled)
}

// LogMood records the caller's current mood with an optional note.
// mood must be one of: happy sad excited calm anxious angry neutral
func LogMood(_ realm, mood, note string) {
	mood = strings.ToLower(strings.TrimSpace(mood))
	if !isValid(mood) {
		panic("invalid mood; choose from: " + strings.Join(validMoods, ", "))
	}
	entries = append(entries, Entry{
		Author: runtime.OriginCaller(),
		Mood:   mood,
		Note:   strings.TrimSpace(note),
		Block:  runtime.ChainHeight(),
	})
}

// TotalEntries returns the total number of mood logs on record.
func TotalEntries() int {
	return len(entries)
}

// MoodCount returns how many times the given mood has been logged.
func MoodCount(mood string) int {
	mood = strings.ToLower(strings.TrimSpace(mood))
	n := 0
	for _, e := range entries {
		if e.Mood == mood {
			n++
		}
	}
	return n
}

// DominantMood returns the most-logged mood, or "none" if no entries.
func DominantMood() string {
	if len(entries) == 0 {
		return "none"
	}
	counts := make(map[string]int)
	for _, e := range entries {
		counts[e.Mood]++
	}
	best := ""
	bestN := 0
	for _, m := range validMoods {
		if counts[m] > bestN {
			bestN = counts[m]
			best = m
		}
	}
	return best
}

func Render(path string) string {
	out := "# 🪨 Moodstone — On-chain Mood Tracker\n\n"
	out += "> Log how you feel. Watch how the community feels. Immutably, on Gno.\n\n"

	total := len(entries)

	// Community stats table
	out += "## 📊 Community Vibes\n\n"
	if total == 0 {
		out += "*No moods logged yet — be the first!*\n\n"
	} else {
		counts := make(map[string]int)
		for _, e := range entries {
			counts[e.Mood]++
		}
		out += "| Mood | Count | Distribution |\n"
		out += "|------|-------|--------------|\n"
		for _, m := range validMoods {
			c := counts[m]
			pct := 0
			if total > 0 {
				pct = (c * 100) / total
			}
			out += "| " + emoji(m) + " " + m + " | " + strconv.Itoa(c) +
				" | `" + bar(c, total) + "` " + strconv.Itoa(pct) + "% |\n"
		}
		dom := DominantMood()
		out += "\n**Total entries:** " + strconv.Itoa(total) +
			" · **Dominant mood:** " + emoji(dom) + " " + dom + "\n\n"
	}

	// Recent entries (newest first, max 10)
	out += "## 📝 Recent Entries\n\n"
	if total == 0 {
		out += "*Nothing here yet.*\n\n"
	} else {
		start := total - 10
		if start < 0 {
			start = 0
		}
		for i := total - 1; i >= start; i-- {
			e := entries[i]
			line := "- " + emoji(e.Mood) + " **" + e.Mood + "**"
			if e.Note != "" {
				line += ": *" + e.Note + "*"
			}
			line += " — `" + shortAddr(e.Author) + "` at block " +
				strconv.FormatInt(e.Block, 10)
			out += line + "\n"
		}
		out += "\n"
	}

	// How to use
	out += "## 🚀 How to Use\n\n"
	out += "```bash\n"
	out += "gnokey maketx call \\\n"
	out += "  -pkgpath gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/moodstone \\\n"
	out += "  -func LogMood \\\n"
	out += "  -args 'happy' -args 'Just shipped something awesome!'\n"
	out += "```\n\n"
	out += "**Valid moods:** " + strings.Join(validMoods, " · ") + "\n"

	return out
}
