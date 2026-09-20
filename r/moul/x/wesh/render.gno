package wesh

import (
	"chain/runtime"
	"encoding/hex"
	"strconv"
	"strings"
	"time"

	"gno.land/p/moul/x/wesh/v0"
)

// Render serves the directory index at "" and one identity card at "<name>".
//
// The index deliberately does not compute a Berty link per row: base58 over a
// 70-byte payload is big-integer work, and it belongs on the page that a human
// actually asked for.
func Render(path string) string {
	path = strings.Trim(path, "/")
	if path == "" {
		return renderIndex()
	}
	return renderIdentity(path)
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# Wesh directory\n\n")
	b.WriteString("Resolvable, self-signed [Wesh protocol](https://berty.tech/docs/protocol/) ")
	b.WriteString("identities, on top of [`p/moul/x/wesh`](/p/moul/x/wesh/v0).\n\n")
	b.WriteString("A Berty identity normally travels out of band as a QR code, cannot be ")
	b.WriteString("looked up, cannot announce a seed rotation, and can never revoke a device. ")
	b.WriteString("This realm addresses those three, and stores no secret of any kind.\n\n")

	if byName.Size() == 0 {
		b.WriteString("_No identity registered yet._\n")
		return b.String()
	}

	b.WriteString("| name | owner | rev | mode | devices |\n")
	b.WriteString("|---|---|---|---|---|\n")
	byName.Iterate("", "", func(key string, value any) bool {
		id := value.(*identity)
		b.WriteString("| [" + id.name + "](/r/moul/x/wesh/v0:" + id.name + ") ")
		b.WriteString("| `" + id.owner.String() + "` ")
		b.WriteString("| " + strconv.Itoa(id.revision) + " ")
		b.WriteString("| " + modeLabel(id) + " ")
		b.WriteString("| " + strconv.Itoa(activeDevices(id)) + " active / " + strconv.Itoa(len(id.devices)) + " entries |\n")
		return false
	})
	n := byName.Size()
	if n == 1 {
		b.WriteString("\n1 identity.\n")
	} else {
		b.WriteString("\n" + strconv.Itoa(n) + " identities.\n")
	}
	return b.String()
}

func renderIdentity(name string) string {
	id := lookup(name)
	if id == nil {
		return "# Not found\n\nNo identity named `" + name + "`. [Back to the directory](/r/moul/x/wesh/v0).\n"
	}

	var b strings.Builder
	b.WriteString("# " + id.name + "\n\n")
	if id.displayName != "" {
		b.WriteString("_" + id.displayName + "_\n\n")
	}
	b.WriteString("| field | value |\n|---|---|\n")
	b.WriteString("| owner | `" + id.owner.String() + "` |\n")
	b.WriteString("| account key | `" + hex.EncodeToString(id.accountPK) + "` |\n")
	b.WriteString("| mode | " + modeLabel(id) + " |\n")
	b.WriteString("| revision | " + strconv.Itoa(id.revision) + " |\n")
	b.WriteString("| registered | block " + strconv.FormatInt(id.history[0].height, 10) + " |\n")

	b.WriteString("\n## Contact\n\n")
	if id.committed {
		b.WriteString("This identity publishes a **commitment**, `")
		b.WriteString(hex.EncodeToString(id.payload))
		b.WriteString("`, not its rendezvous seed.\n\n")
		b.WriteString("The chain attests that this account key claimed that commitment from ")
		b.WriteString("that gno address. The seed itself is shared out of band, and whoever ")
		b.WriteString("receives it can check it here with `H(seed || salt)` before using it. ")
		b.WriteString("The rendezvous point stays off chain.\n")
	} else {
		link, err := contactOf(id).WebLink()
		if err != nil {
			b.WriteString("_Contact is unrenderable: " + err.Error() + "_\n")
		} else {
			b.WriteString("Scan or open this in Berty to send a contact request:\n\n")
			b.WriteString("```\n" + link + "\n```\n\n")
			b.WriteString("| field | value |\n|---|---|\n")
			b.WriteString("| rendezvous seed | `" + hex.EncodeToString(id.payload) + "` |\n")
			now := time.Now().Unix()
			period := wesh.RoundPeriod(now, wesh.DefaultRotationInterval)
			point, _ := contactOf(id).RendezvousPointAt(now, wesh.DefaultRotationInterval)
			b.WriteString("| rendezvous point, period " + strconv.FormatInt(period, 10) + " | `" + hex.EncodeToString(point) + "` |\n")
			b.WriteString("\nThe point is `HMAC-SHA256(accountPK || seed, be64(period))`, derived ")
			b.WriteString("exactly as weshnet derives it, and it rotates every 24h. Anyone can ")
			b.WriteString("recompute it and check the DHT, so this entry is verifiable rather ")
			b.WriteString("than merely asserted.\n")
		}
	}

	b.WriteString("\n## Devices\n\n")
	if len(id.devices) == 0 {
		b.WriteString("No sigchain entry yet. Head is the genesis digest `")
		b.WriteString(hex.EncodeToString(id.head) + "`.\n")
	} else {
		b.WriteString("Every entry below was signed by the account key and verified on chain, ")
		b.WriteString("and chains to the digest of the one before it.\n\n")
		b.WriteString("| seq | op | device | block | digest |\n|---|---|---|---|---|\n")
		for _, e := range id.devices {
			b.WriteString("| " + strconv.Itoa(e.seq) + " ")
			b.WriteString("| " + e.op + " ")
			b.WriteString("| `" + short(hex.EncodeToString(e.devicePK)) + "` ")
			b.WriteString("| " + strconv.FormatInt(e.height, 10) + " ")
			b.WriteString("| `" + short(hex.EncodeToString(e.digest)) + "` |\n")
		}
		b.WriteString("\nHead: `" + hex.EncodeToString(id.head) + "`\n")
	}

	if len(id.history) > 1 {
		b.WriteString("\n## Rotation history\n\n")
		b.WriteString("Weshnet has no way to announce that a seed was reset, so every link ")
		b.WriteString("ever shared dies silently. These are the superseded values, kept so a ")
		b.WriteString("stale link can be recognised as stale.\n\n")
		b.WriteString("| rev | value | block |\n|---|---|---|\n")
		for _, r := range id.history {
			mark := ""
			if r.revision == id.revision {
				mark = " (current)"
			}
			b.WriteString("| " + strconv.Itoa(r.revision) + mark + " ")
			b.WriteString("| `" + short(hex.EncodeToString(r.payload)) + "` ")
			b.WriteString("| " + strconv.FormatInt(r.height, 10) + " |\n")
		}
	}

	b.WriteString("\n[Back to the directory](/r/moul/x/wesh/v0) · chain `" + runtime.ChainID() + "`\n")
	return b.String()
}

func modeLabel(id *identity) string {
	if id.committed {
		return "committed"
	}
	return "published"
}

// activeDevices counts the distinct devices whose latest sigchain entry is an
// add. A device can be added, revoked and added again, so only the last entry
// for each key decides.
func activeDevices(id *identity) int {
	seen := []string{}
	for _, e := range id.devices {
		key := string(e.devicePK)
		known := false
		for _, s := range seen {
			if s == key {
				known = true
				break
			}
		}
		if !known {
			seen = append(seen, key)
		}
	}
	n := 0
	for _, k := range seen {
		if deviceIsActive(id, []byte(k)) {
			n++
		}
	}
	return n
}

// short abbreviates a long hex string for table cells.
func short(s string) string {
	if len(s) <= 16 {
		return s
	}
	return s[:8] + "…" + s[len(s)-8:]
}
