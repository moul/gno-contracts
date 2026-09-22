package config

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/moul/mygnoscan/v0"
	"gno.land/p/nt/avl/v0"
)

// The keys this realm answers for by name. A key is just a string and any key
// can be set, but one the rest of the repo reads gets a constant here so the
// reader and the writer cannot drift apart on a typo.
const (
	// KeyMygnoscanURL is the explorer instance every realm of moul's links to.
	KeyMygnoscanURL = "mygnoscan.url"
	// KeyMygnoscanNetwork overrides the ?network= id, for an instance that
	// names the chain something other than what mygnoscan.NetworkFor expects.
	// Unset is the normal case: the chain-id decides.
	KeyMygnoscanNetwork = "mygnoscan.network"
)

const (
	maxKeyLen = 64
	// maxValueLen bounds one write. Storage is paid for and never refunded, so
	// this realm holds settings, not content: a URL, a flag, a short list.
	maxValueLen = 1024
)

type setting struct {
	value   string
	rev     int
	updated int64
}

var (
	settings    = avl.NewTree() // key -> *setting
	settingsRev int
)

// validKey reports whether key is legal: 1..maxKeyLen bytes of [a-z0-9._-].
// The dot is the namespace separator ("mygnoscan.url"), lowercase only so a
// setting has exactly one name, and no whitespace so a key round-trips through
// Manifest's tab-separated lines unambiguously.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > maxKeyLen {
		return false
	}
	for i := 0; i < len(key); i++ {
		c := key[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case c == '-', c == '_', c == '.':
		default:
			return false
		}
	}
	return true
}

// Set creates or replaces a setting. Only an address the Authorizer accepts
// may call it.
//
// It panics rather than returning an error, which is the opposite of the
// manager functions in config.gno, and deliberately so: a returned error from
// a realm call leaves the transaction SUCCESSFUL. A rejected config write that
// reports success is the one outcome worth ruling out here, because the caller
// then walks away believing the new value is live and every realm reading this
// key keeps serving the old one. The manager functions predate that reasoning
// and are frozen on chain at v0; new surface does not inherit the mistake.
func Set(cur realm, key, value string) {
	assertWritableKey(key)
	if len(value) > maxValueLen {
		panic("value too long: max " + strconv.Itoa(maxValueLen) + " bytes, got " + strconv.Itoa(len(value)))
	}
	assertAuthorized(cur, "config.Set:"+key)

	settingsRev++
	settings.Set(key, &setting{
		value:   value,
		rev:     settingsRev,
		updated: runtime.ChainHeight(),
	})
	chain.Emit("ConfigSet", "key", key, "value", value, "rev", strconv.Itoa(settingsRev))
}

// Unset removes a setting, so readers fall back to their built-in default.
// Removing a key that is not set is an error, not a no-op: it almost always
// means the key was misspelled here or in the realm that reads it.
func Unset(cur realm, key string) {
	assertWritableKey(key)
	assertAuthorized(cur, "config.Unset:"+key)

	if _, removed := settings.Remove(key); !removed {
		panic("no such setting: " + key)
	}
	settingsRev++
	chain.Emit("ConfigUnset", "key", key, "rev", strconv.Itoa(settingsRev))
}

func assertWritableKey(key string) {
	if !validKey(key) {
		panic("invalid key: want 1-" + strconv.Itoa(maxKeyLen) +
			" bytes of [a-z0-9._-], got " + strconv.Quote(key))
	}
}

// assertAuthorized runs the write through the Authorizer, so whoever holds
// authority today decides: the member list at first, a DAO or a contract after
// a TransferManagement. The action closure is what authz authorizes; the write
// itself happens after, because a nil error is the only thing that reaches it.
func assertAuthorized(cur realm, title string) {
	allowed := false
	err := Authorizer.DoByPrevious(0, cur, title, func() error {
		allowed = true
		return nil
	})
	if err != nil {
		panic("unauthorized: " + err.Error())
	}
	if !allowed {
		panic("unauthorized")
	}
}

// Get returns a setting's value, or "" when it is not set. Reads are open: a
// realm importing this one calls Get on every render and pays nothing beyond
// the cross-realm call.
func Get(key string) string {
	v := settings.Get(key)
	if v == nil {
		return ""
	}
	return v.(*setting).value
}

// GetOr returns a setting's value, or fallback when it is unset or empty.
// This is the shape every consumer wants: a realm should still render on a
// chain where this one was never deployed with that key.
func GetOr(key, fallback string) string {
	if v := Get(key); v != "" {
		return v
	}
	return fallback
}

// Has reports whether key is set, including to the empty string, which GetOr
// cannot distinguish from unset.
func Has(key string) bool { return settings.Has(key) }

// Keys returns every set key, in sorted order.
func Keys() []string {
	out := []string{}
	settings.Iterate("", "", func(key string, _ any) bool {
		out = append(out, key)
		return false
	})
	return out
}

// Size returns how many settings are set.
func Size() int { return settings.Size() }

// SettingsRevision counts every settings write this realm has accepted. A
// client that caches config polls this one int to learn that nothing moved.
func SettingsRevision() int { return settingsRev }

// Manifest returns one tab-separated line per setting:
//
//	<key>\t<rev>\t<height>\t<value>
//
// It is the whole config in one vm/qeval read, for a tool that wants to diff
// the chain against a local file without a call per key. The value is last
// because it is the only field that can contain a tab.
func Manifest() string {
	var b strings.Builder
	settings.Iterate("", "", func(key string, value any) bool {
		s := value.(*setting)
		b.WriteString(key)
		b.WriteString("\t")
		b.WriteString(strconv.Itoa(s.rev))
		b.WriteString("\t")
		b.WriteString(strconv.FormatInt(s.updated, 10))
		b.WriteString("\t")
		b.WriteString(s.value)
		b.WriteString("\n")
		return false
	})
	return b.String()
}

// MygnoscanURL returns the explorer base moul's realms should link to, falling
// back to the package default when nothing is set here.
func MygnoscanURL() string { return GetOr(KeyMygnoscanURL, mygnoscan.DefaultBase) }

// Scanner returns a link builder pointed at the configured explorer, on
// whichever network answers for the running chain (or at the KeyMygnoscanNetwork
// override, when one is set).
//
// This is the function other realms are meant to call:
//
//	config.Scanner().Realm("gno.land/r/moul/home")
//	config.Scanner().Address(someAddr)
//
// Changing where every one of them points is then one transaction against this
// realm, not a redeploy of each.
func Scanner() mygnoscan.Scanner {
	s := mygnoscan.New(MygnoscanURL())
	if net := Get(KeyMygnoscanNetwork); net != "" {
		s = s.WithNetwork(net)
	}
	return s
}

// MygnoscanFor is the one-liner: the explorer page for a realm path.
//
// It takes the path explicitly and there is no zero-argument version on
// purpose. mygnoscan can name the calling realm by stack-walking, but the
// stack seen from in here has this realm on it, so a "current realm" helper
// exported from a shared config realm would confidently return
// gno.land/r/moul/config for every caller. Pass your own path.
func MygnoscanFor(pkgPath string) string { return Scanner().Realm(pkgPath) }

// MygnoscanFooter is MygnoscanFor's render-ready form: the markdown line a
// realm appends under its output.
func MygnoscanFooter(pkgPath string) string { return Scanner().RealmFooter(pkgPath) }

// Render shows the whole configuration: the settings, who may change them, and
// where this realm itself can be inspected.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# gno.land/r/moul/config\n\n")
	b.WriteString("moul's settings, read by his other realms. ")
	b.WriteString("rev ")
	b.WriteString(strconv.Itoa(settingsRev))
	b.WriteString(" · ")
	b.WriteString(strconv.Itoa(settings.Size()))
	b.WriteString(" setting(s)\n\n")

	b.WriteString("## Settings\n\n")
	if settings.Size() == 0 {
		b.WriteString("_none set; every reader is on its built-in default_\n")
	} else {
		b.WriteString("| key | value | rev | height |\n")
		b.WriteString("| --- | --- | ---: | ---: |\n")
		settings.Iterate("", "", func(key string, value any) bool {
			s := value.(*setting)
			b.WriteString("| `")
			b.WriteString(key)
			b.WriteString("` | ")
			b.WriteString(renderValue(s.value))
			b.WriteString(" | ")
			b.WriteString(strconv.Itoa(s.rev))
			b.WriteString(" | ")
			b.WriteString(strconv.FormatInt(s.updated, 10))
			b.WriteString(" |\n")
			return false
		})
	}

	b.WriteString("\n## Authority\n\n")
	b.WriteString("`")
	b.WriteString(Authorizer.String())
	b.WriteString("`\n")

	b.WriteString("\n---\n\n")
	b.WriteString(MygnoscanFooter("gno.land/r/moul/config"))
	b.WriteString("\n")

	return b.String()
}

// renderValue puts a value in a code span and neutralises the two characters
// that would otherwise break out of the table cell it sits in. Only a manager
// can write a value, so this is about a stray pipe in a URL and not about an
// attacker, but a config page that silently loses a column is its own bug.
func renderValue(v string) string {
	if v == "" {
		return "_(empty)_"
	}
	v = strings.ReplaceAll(v, "|", "\\|")
	v = strings.ReplaceAll(v, "`", "'")
	v = strings.ReplaceAll(v, "\n", " ")
	return "`" + v + "`"
}
