// Package timecapsule is a public guestbook where every message is sealed
// until a future block height, then permanently unlocked for anyone to read.
package timecapsule

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/markdown/sanitize/v0"
)

type capsule struct {
	id           int64
	author       address
	message      string
	createdAt    int64
	unlockHeight int64
}

var (
	capsules avl.Tree // key: zero-padded id -> *capsule
	nextID   int64
)

const (
	maxDelayBlocks int64 = 1_000_000
	maxMessageLen  int   = 500
)

// Leave seals a new message that stays hidden until `delayBlocks` blocks
// from now, then becomes publicly readable forever. Returns the capsule id.
func Leave(cur realm, message string, delayBlocks int64) int64 {
	if !cur.Previous().IsUserCall() {
		panic("only direct user calls can leave a capsule")
	}

	message = strings.TrimSpace(message)
	if message == "" {
		panic("message must not be empty")
	}
	if len(message) > maxMessageLen {
		panic("message too long")
	}
	if delayBlocks <= 0 || delayBlocks > maxDelayBlocks {
		panic("delayBlocks out of range")
	}

	now := runtime.ChainHeight()
	id := nextID
	nextID++

	c := &capsule{
		id:           id,
		author:       cur.Previous().Address(),
		message:      message,
		createdAt:    now,
		unlockHeight: now + delayBlocks,
	}
	capsules.Set(idKey(id), c)

	chain.Emit("CapsuleSealed",
		"id", strconv.FormatInt(id, 10),
		"unlockHeight", strconv.FormatInt(c.unlockHeight, 10),
	)
	return id
}

func idKey(id int64) string {
	s := strconv.FormatInt(id, 10)
	return strings.Repeat("0", 12-len(s)) + s
}

func Render(path string) string {
	switch {
	case path == "":
		return renderHome()
	case path == "sealed":
		return renderSealed()
	case strings.HasPrefix(path, "capsule/"):
		return renderCapsule(strings.TrimPrefix(path, "capsule/"))
	default:
		return "> [!WARNING]\n> Path not found\n"
	}
}

func renderHome() string {
	now := runtime.ChainHeight()

	revealed := 0
	sealed := 0
	capsules.Iterate("", "", func(_ string, value any) bool {
		if value.(*capsule).unlockHeight <= now {
			revealed++
		} else {
			sealed++
		}
		return false
	})

	var out strings.Builder
	out.WriteString("# ⏳ Time Capsule Guestbook\n\n")
	out.WriteString("Leave a message for the future. It stays sealed until its unlock block height, then anyone can read it — call `Leave(message, delayBlocks)`.\n\n")
	out.WriteString(strconv.Itoa(revealed+sealed) + " capsule(s) total · " +
		strconv.Itoa(revealed) + " unlocked · " + strconv.Itoa(sealed) + " still sealed")
	if sealed > 0 {
		out.WriteString(" (see [sealed](sealed))")
	}
	out.WriteString(".\n\n## Unlocked messages\n\n")

	if revealed == 0 {
		out.WriteString("_None yet. Be the first to leave one that will open later._\n")
		return out.String()
	}

	capsules.Iterate("", "", func(_ string, value any) bool {
		c := value.(*capsule)
		if c.unlockHeight <= now {
			out.WriteString(renderEntry(c))
		}
		return false
	})
	return out.String()
}

func renderSealed() string {
	now := runtime.ChainHeight()

	var out strings.Builder
	out.WriteString("# Sealed Capsules\n\n")

	found := false
	capsules.Iterate("", "", func(_ string, value any) bool {
		c := value.(*capsule)
		if c.unlockHeight > now {
			found = true
			out.WriteString("- capsule [#" + strconv.FormatInt(c.id, 10) + "](capsule/" +
				strconv.FormatInt(c.id, 10) + ") by `" + c.author.String() +
				"` — unlocks at block " + strconv.FormatInt(c.unlockHeight, 10) +
				" (" + strconv.FormatInt(c.unlockHeight-now, 10) + " blocks left)\n")
		}
		return false
	})
	if !found {
		out.WriteString("_No sealed capsules right now._\n")
	}
	return out.String()
}

func renderCapsule(idStr string) string {
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		return "> [!WARNING]\n> Invalid capsule id\n"
	}
	v, ok := capsules.Get(idKey(id))
	if !ok {
		return "> [!WARNING]\n> Capsule not found\n"
	}
	c := v.(*capsule)
	now := runtime.ChainHeight()

	var out strings.Builder
	out.WriteString("# Capsule #" + strconv.FormatInt(c.id, 10) + "\n\n")
	out.WriteString("Sealed by `" + c.author.String() + "` at block " + strconv.FormatInt(c.createdAt, 10) + ".\n\n")

	if c.unlockHeight > now {
		out.WriteString("\U0001f512 Still sealed. Unlocks at block " + strconv.FormatInt(c.unlockHeight, 10) +
			" (" + strconv.FormatInt(c.unlockHeight-now, 10) + " blocks left).\n")
		return out.String()
	}

	out.WriteString("\U0001f513 Unlocked at block " + strconv.FormatInt(c.unlockHeight, 10) + ":\n\n> " +
		sanitize.InlineText(c.message) + "\n")
	return out.String()
}

func renderEntry(c *capsule) string {
	return "- **#" + strconv.FormatInt(c.id, 10) + "** by `" + c.author.String() +
		"` (sealed at block " + strconv.FormatInt(c.createdAt, 10) +
		", opened at block " + strconv.FormatInt(c.unlockHeight, 10) + "):\n  > " +
		sanitize.InlineText(c.message) + "\n\n"
}
