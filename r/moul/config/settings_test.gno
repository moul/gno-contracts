package config

import (
	"strconv"
	"testing"

	"chain/runtime"

	"gno.land/p/moul/authz/v0"
	"gno.land/p/moul/mygnoscan/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/uassert/v0"
)

// resetSettings puts the realm back to a just-deployed state. Realm globals
// live for the whole test binary and gno runs every Example AFTER every Test,
// so without this the pinned ExampleRender output would depend on which tests
// ran before it and in what order.
func resetSettings() {
	settings = avl.NewTree()
	proxies = avl.NewTree()
	settingsRev = 0
	Authorizer = authz.NewWithAuthority(authz.NewMemberAuthority(originAddr))
}

func TestValidKey(t *testing.T) {
	tests := []struct {
		key  string
		want bool
	}{
		{"mygnoscan.url", true},
		{"a", true},
		{"a-b_c.d0", true},
		{"", false},
		{"Upper", false},
		{"has space", false},
		{"tab\there", false},
		{"colon:here", false},
		// A bare slash is not a name; it is only legal inside a scope.
		{"slash/here", false},
		// Scoped keys.
		{"pause" + ScopeSep + "r/moul/home", true},
		{"block.top" + ScopeSep + "p/moul/kit/ui", true},
		{"pause" + ScopeSep, false},           // scope separator with no scope
		{ScopeSep + "r/moul/home", false},     // scope with no name
		{"pause" + ScopeSep + "r//moul", false},
		{"pause" + ScopeSep + "r/moul/", false},
		{"pause" + ScopeSep + "R/Moul/Home", false},
		{"pause" + ScopeSep + "a" + ScopeSep + "b", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, validKey(tt.key), "validKey("+tt.key+")")
	}

	// 64 bytes is the last legal length, 65 the first illegal one.
	long := ""
	for i := 0; i < maxNameLen; i++ {
		long += "a"
	}
	uassert.True(t, validKey(long), "a name of exactly maxNameLen is legal")
	uassert.False(t, validKey(long+"a"), "one byte over maxNameLen is not")
}

func TestSetGetUnset(cur realm, t *testing.T) {
	resetSettings()

	uassert.Equal(t, "", Get("mygnoscan.url"))
	uassert.False(t, Has("mygnoscan.url"))
	uassert.Equal(t, "fallback", GetOr("mygnoscan.url", "fallback"))
	uassert.Equal(t, 0, SettingsRevision())

	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyMygnoscanURL, "https://scan.example.com")

	uassert.Equal(t, "https://scan.example.com", Get(KeyMygnoscanURL))
	uassert.True(t, Has(KeyMygnoscanURL))
	uassert.Equal(t, "https://scan.example.com", GetOr(KeyMygnoscanURL, "fallback"))
	uassert.Equal(t, 1, SettingsRevision())
	uassert.Equal(t, 1, Size())

	// Overwriting is an ordinary write and bumps the revision again.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyMygnoscanURL, "https://scan2.example.com")
	uassert.Equal(t, "https://scan2.example.com", Get(KeyMygnoscanURL))
	uassert.Equal(t, 2, SettingsRevision())
	uassert.Equal(t, 1, Size())

	testing.SetRealm(testing.NewUserRealm(originAddr))
	Unset(cross(cur), KeyMygnoscanURL)
	uassert.Equal(t, "", Get(KeyMygnoscanURL))
	uassert.False(t, Has(KeyMygnoscanURL))
	uassert.Equal(t, 0, Size())
	uassert.Equal(t, 3, SettingsRevision())
}

// TestEmptyValueIsSet pins the one case GetOr cannot see: a key set to "" is
// set, and every reader falls back anyway. That is deliberate (a reader's
// default beats an empty string) but it means Unset and Set("") are not the
// same operation, and only Has tells them apart.
func TestEmptyValueIsSet(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), "some.key", "")

	uassert.True(t, Has("some.key"))
	uassert.Equal(t, "", Get("some.key"))
	uassert.Equal(t, "fallback", GetOr("some.key", "fallback"))
}

func TestSetRequiresAuthority(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(nonManagerAddr))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		Set(cross(cur), "some.key", "value")
	})
	uassert.Equal(t, 0, Size(), "a rejected write leaves nothing behind")
	uassert.Equal(t, 0, SettingsRevision(), "and does not move the revision")

	// A manager added by the origin can write, which is the whole point of
	// routing through the Authorizer instead of a hardcoded address.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.NoError(t, AddManager(cross(cur), manager1Addr))

	testing.SetRealm(testing.NewUserRealm(manager1Addr))
	Set(cross(cur), "some.key", "value")
	uassert.Equal(t, "value", Get("some.key"))

	// And loses it again when removed.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.NoError(t, RemoveManager(cross(cur), manager1Addr))

	testing.SetRealm(testing.NewUserRealm(manager1Addr))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		Set(cross(cur), "other.key", "value")
	})
}

func TestUnsetRequiresAuthority(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), "some.key", "value")

	testing.SetRealm(testing.NewUserRealm(nonManagerAddr))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		Unset(cross(cur), "some.key")
	})
	uassert.Equal(t, "value", Get("some.key"), "a rejected unset leaves the value")
}

func TestUnsetMissingKeyAborts(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.AbortsWithMessage(t, cur, "no such setting: never.set", func() {
		Unset(cross(cur), "never.set")
	})
}

func TestInvalidInputAborts(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.AbortsContains(t, cur, "invalid key", func() {
		Set(cross(cur), "Bad Key", "value")
	})

	long := ""
	for i := 0; i < maxValueLen+1; i++ {
		long += "x"
	}
	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.AbortsContains(t, cur, "value too long", func() {
		Set(cross(cur), "some.key", long)
	})

	uassert.Equal(t, 0, Size(), "neither rejection wrote anything")
}

// TestKeyValidatedBeforeAuthority pins the check order: an unauthorised caller
// passing a malformed key is told the key is wrong, not that they are. Nothing
// secret leaks either way, and validating first means a manager's typo gets
// the useful message rather than a misleading "unauthorized".
func TestKeyValidatedBeforeAuthority(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(nonManagerAddr))
	uassert.AbortsContains(t, cur, "invalid key", func() {
		Set(cross(cur), "Bad Key", "value")
	})
}

func TestKeysAndManifest(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), "zzz.last", "z")
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), "aaa.first", "a")

	keys := Keys()
	uassert.Equal(t, 2, len(keys))
	uassert.Equal(t, "aaa.first", keys[0], "Keys is sorted, not insertion-ordered")
	uassert.Equal(t, "zzz.last", keys[1])

	// rev is the realm-wide counter at the time of that key's last write, so
	// zzz.last carries 1 and aaa.first carries 2 despite sorting first. The
	// height column is read back from the chain rather than hardcoded: gno's
	// test harness has no absolute height setter, so tests inherit whatever
	// height ran before them and a literal here would break on the next test
	// added above this one.
	h := strconv.FormatInt(runtime.ChainHeight(), 10)
	uassert.Equal(t,
		"aaa.first\t2\t"+h+"\ta\nzzz.last\t1\t"+h+"\tz\n",
		Manifest())
}

func TestScannerFollowsSettings(cur realm, t *testing.T) {
	resetSettings()

	// Unset, every reader is on the package default.
	uassert.Equal(t, mygnoscan.DefaultBase, MygnoscanURL())
	uassert.Equal(t,
		mygnoscan.DefaultBase+"/realm/r/moul/home",
		MygnoscanFor("gno.land/r/moul/home"))

	// One transaction moves every realm that reads this one.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyMygnoscanURL, "https://scan.example.com")

	uassert.Equal(t, "https://scan.example.com", MygnoscanURL())
	uassert.Equal(t,
		"https://scan.example.com/realm/r/moul/home",
		MygnoscanFor("gno.land/r/moul/home"))

	// The network override is independent of the base, for an instance that
	// names the chain differently. The test harness runs as chain-id "dev",
	// which maps to no network at all, so this is the only way to see one.
	uassert.Equal(t, "", Scanner().Network())
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyMygnoscanNetwork, "gnoland1")
	uassert.Equal(t, "gnoland1", Scanner().Network())
	uassert.Equal(t,
		"https://scan.example.com/realm/r/moul/home?network=gnoland1",
		MygnoscanFor("gno.land/r/moul/home"))
}

func TestMygnoscanFooter(cur realm, t *testing.T) {
	resetSettings()
	uassert.Equal(t,
		mygnoscan.DefaultBase+"/realm/r/moul/config",
		mygnoscan.Default().Realm("gno.land/r/moul/config"),
		"the footer and a direct build agree while nothing is configured")
	uassert.True(t, len(MygnoscanFooterFor("gno.land/r/moul/config")) > 0)
	uassert.Equal(t, "", MygnoscanFooterFor(""))
}

// ExampleRender pins the page as it looks right after deployment. It resets
// first: examples run after every Test in the binary and would otherwise
// render whatever state they left.
func ExampleRender() {
	resetSettings()
	print(Render(""))
	// Output:
	// # gno.land/r/moul/config
	//
	// moul's settings, read by his other realms. rev 0 · 0 setting(s)
	//
	// ## Settings
	//
	// _none set; every reader is on its built-in default_
	//
	// ## Pause
	//
	// _running; no global pause_
	//
	// ## Authority
	//
	// `member_authority[g1daexjemfde047h6lta047h6lta047h6ld2pug6]`
	//
	// ---
	//
	// [explorer](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1) · [source](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1?tab=source) · [calls](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1?tab=calls) · [deps](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1?tab=deps)
}

// ExampleRender_populated pins the settings table and the global pause banner,
// which together are the view a manager actually looks at during an incident.
func ExampleRender_populated() {
	resetSettings()
	settings.Set(KeyMygnoscanURL, &setting{value: "https://scan.example.com", rev: 1, updated: 42})
	settings.Set(KeyPause, &setting{value: "readonly: migrating storage", rev: 2, updated: 43})
	settings.Set(KeyFor(KeyBlockTop, "gno.land/r/moul/gns"), &setting{value: "> v2 shipped", rev: 3, updated: 44})
	settingsRev = 3
	print(Render(""))
	// Output:
	// # gno.land/r/moul/config
	//
	// moul's settings, read by his other realms. rev 3 · 3 setting(s)
	//
	// ## Settings
	//
	// | key | value | rev | height |
	// | --- | --- | ---: | ---: |
	// | `block.top@r/moul/gns` | `> v2 shipped` | 3 | 44 |
	// | `mygnoscan.url` | `https://scan.example.com` | 1 | 42 |
	// | `pause` | `readonly: migrating storage` | 2 | 43 |
	//
	// ## Pause
	//
	// > **Read-only.** This realm is still readable, but not accepting changes. migrating storage
	//
	// ## Authority
	//
	// `member_authority[g1daexjemfde047h6lta047h6lta047h6ld2pug6]`
	//
	// ---
	//
	// [explorer](https://scan.example.com/realm/r/moul/config/v1) · [source](https://scan.example.com/realm/r/moul/config/v1?tab=source) · [calls](https://scan.example.com/realm/r/moul/config/v1?tab=calls) · [deps](https://scan.example.com/realm/r/moul/config/v1?tab=deps)
}
