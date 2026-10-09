package usernames

import (
	"strings"
	"testing"
	"unicode/utf8"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/sys/users"
)

const (
	moulAddr  = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")
	plainAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

// controllerPath is the realm r/sys/users whitelists in its own init when the
// chain id is "dev", which is what `gno test` runs as. Registering a fixture
// means borrowing that identity: this package is not a controller and
// AddControllerAtGenesis cannot be reached from here, since its `_ realm`
// first parameter is the non-crossing threaded form and an external realm
// refuses a cur-call to one.
const controllerPath = "gno.land/r/sys/users/init"

// seed registers the fixtures every test in this file reads.
//
// The SetRealm is immediately followed by a crossing call, which is the only
// shape that works: in a helper that does not itself cross, the switch is
// silently dropped and the caller stays whoever it was.
func seed(cur realm, t *testing.T) {
	t.Helper()
	if users.IsNameTaken("moul") {
		return
	}
	testing.SetRealm(testing.NewCodeRealm(controllerPath))
	urequire.NoError(t, users.RegisterUser(cross(cur), "moul", moulAddr))
}

func TestResolveByName(cur realm, t *testing.T) {
	seed(cur, t)

	name, addr, found := Resolve("moul")
	uassert.True(t, found)
	uassert.Equal(t, "moul", name)
	uassert.Equal(t, moulAddr.String(), addr)
}

func TestResolveByAddress(cur realm, t *testing.T) {
	seed(cur, t)

	name, addr, found := Resolve(moulAddr.String())
	uassert.True(t, found)
	uassert.Equal(t, "moul", name)
	uassert.Equal(t, moulAddr.String(), addr)
}

func TestResolveMisses(cur realm, t *testing.T) {
	seed(cur, t)

	cases := []struct {
		name  string
		input string
	}{
		{"empty", ""},
		{"unknown name", "nobodyholdsthis"},
		{"valid address with no name", plainAddr.String()},
		{"not an address and not a name", "g1notanaddress"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, _, found := Resolve(tc.input)
			uassert.False(t, found)
		})
	}
}

// TestResolveAnyTrap is the defect this tool exists not to repeat: for an
// input that parses as an address, r/sys/users.ResolveAny reports true
// whatever the lookup produced, so the pointer it returns can be nil. Pinned
// against the vendored copy so a later upstream fix is visible here.
func TestResolveAnyTrap(cur realm, t *testing.T) {
	seed(cur, t)

	data, ok := users.ResolveAny(plainAddr.String())
	uassert.True(t, ok)
	uassert.True(t, data == nil)

	_, _, found := Resolve(plainAddr.String())
	uassert.False(t, found)
}

func TestAccessors(cur realm, t *testing.T) {
	seed(cur, t)

	uassert.Equal(t, moulAddr.String(), AddressOf("moul"))
	uassert.Equal(t, "moul", NameOf(moulAddr.String()))
	uassert.Equal(t, "@moul", Display("moul"))
	uassert.Equal(t, "@moul", Display(moulAddr.String()))

	uassert.Equal(t, "", AddressOf("nobodyholdsthis"))
	uassert.Equal(t, "", NameOf("nobodyholdsthis"))
	uassert.Equal(t, "nobodyholdsthis", Display("nobodyholdsthis"))
}

func TestCanonicalAndTaken(cur realm, t *testing.T) {
	seed(cur, t)

	uassert.Equal(t, users.Canonicalize("moul"), Canonical("moul"))
	uassert.True(t, Taken("moul"))
	uassert.False(t, Taken("nobodyholdsthis"))
	uassert.False(t, Taken(""))

	uassert.Equal(t, "moul", CanonicalOwner("moul"))
	uassert.Equal(t, "", CanonicalOwner("nobodyholdsthis"))
	uassert.Equal(t, "", CanonicalOwner(""))
}

// TestCurrentNameOnAlias: r/sys/users keeps an old name resolving after a
// rename and nothing in the resolve result says it is old. CurrentName is the
// only call that does.
func TestCurrentNameOnAlias(cur realm, t *testing.T) {
	seed(cur, t)

	const old = "aliasfixture"
	const now = "renamedfixture"

	if !users.IsNameTaken(old) {
		testing.SetRealm(testing.NewCodeRealm(controllerPath))
		urequire.NoError(t, users.RegisterUser(cross(cur), old, plainAddr))
	}

	data := users.ResolveAddress(plainAddr)
	urequire.True(t, data != nil)
	if data.Name() == old {
		testing.SetRealm(testing.NewCodeRealm(controllerPath))
		urequire.NoError(t, data.UpdateName(0, cur, now))
	}

	uassert.Equal(t, now, CurrentName(old))
	uassert.Equal(t, "", CurrentName(now))
	uassert.Equal(t, "", CurrentName(plainAddr.String()))
	uassert.Equal(t, "", CurrentName("nobodyholdsthis"))
	uassert.Equal(t, "", CurrentName(""))

	// The old name still resolves, to the current one.
	name, _, found := Resolve(old)
	uassert.True(t, found)
	uassert.Equal(t, now, name)
}

func TestSafeArg(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"username", "moul", true},
		{"address", "g1manfred47kzduec920z88wfr64ylksmdcedlf5", true},
		{"dashes and dots", "a-b.c_d", true},
		{"empty", "", false},
		{"quote", "a'b", false},
		{"backtick", "a`b", false},
		{"fence", "```", false},
		{"dollar", "$(id)", false},
		{"too long", strings.Repeat("a", maxInput+1), false},
		{"exactly max", strings.Repeat("a", maxInput), true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, safeArg(tc.in))
		})
	}
}

func TestTrim(t *testing.T) {
	uassert.Equal(t, "moul", trim("moul"))
	long := strings.Repeat("a", maxInput+10)
	uassert.Equal(t, strings.Repeat("a", maxInput)+"…", trim(long))
}

// TestTrimCutsOnARuneBoundary: a byte cut at maxInput lands inside the
// multi-byte character here and leaves half of it, which no escaper
// downstream can do anything sensible with.
func TestTrimCutsOnARuneBoundary(t *testing.T) {
	in := strings.Repeat("a", maxInput-1) + "é" + "tail"
	got := trim(in)
	uassert.Equal(t, strings.Repeat("a", maxInput-1)+"é"+"…", got)
	uassert.True(t, utf8.ValidString(got))

	// And the cap counts characters, not bytes, so an all-multibyte input
	// keeps maxInput of them rather than half as many.
	accents := strings.Repeat("é", maxInput+5)
	uassert.Equal(t, strings.Repeat("é", maxInput)+"…", trim(accents))
}

// TestDisplayOnEmpty pins the one input Display has nothing to say about.
func TestDisplayOnEmpty(t *testing.T) {
	uassert.Equal(t, "", Display(""))
}
