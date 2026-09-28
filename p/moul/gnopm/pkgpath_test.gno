package gnopm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestValidPkgPath(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"versioned package", "gno.land/p/moul/md/v1", true},
		{"versioned realm", "gno.land/r/moul/gnopm/registry/v0", true},
		{"unversioned realm", "gno.land/r/sys/users", true},
		{"address namespace", "gno.land/r/" + addrNS + "/scratch/v0", true},

		{"empty", "", false},
		{"too few elements", "gno.land/p/moul", false},
		{"domain without a dot", "gnoland/p/moul/md/v1", false},
		{"unknown kind", "gno.land/x/moul/md/v1", false},
		{"leading slash", "/gno.land/p/moul/md/v1", false},
		{"trailing slash", "gno.land/p/moul/md/v1/", false},
		{"double slash", "gno.land/p//moul/md", false},
		{"parent traversal", "gno.land/p/moul/../md", false},
		{"space", "gno.land/p/moul/m d", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidPkgPath(tc.in), tc.name)
	}
}

func TestSplitPkgPath(t *testing.T) {
	domain, kind, ns, rest, ok := SplitPkgPath("gno.land/r/moul/gnopm/registry/v0")
	uassert.True(t, ok, "splits")
	uassert.Equal(t, "gno.land", domain)
	uassert.Equal(t, "r", kind)
	uassert.Equal(t, "moul", ns)
	uassert.Equal(t, "gnopm/registry/v0", rest)

	_, _, _, _, ok = SplitPkgPath("nonsense")
	uassert.False(t, ok, "rejects a non-path")

	uassert.Equal(t, "moul", Namespace("gno.land/p/moul/md/v1"))
	uassert.Equal(t, "", Namespace("nonsense"))
}

func TestVersion(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"gno.land/p/moul/md/v1", "v1"},
		{"gno.land/p/moul/md/v0", "v0"},
		{"gno.land/p/moul/md/v10", "v10"},
		{"gno.land/r/sys/users", ""},   // unversioned is legal
		{"gno.land/r/moul/home", ""},   // the one path that can never carry one
		{"gno.land/p/moul/md/vx", ""},  // not a number
		{"gno.land/p/moul/md/v", ""},   // no digits
		{"short", ""},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Version(tc.in), tc.in)
	}
}

func TestAddressNamespace(t *testing.T) {
	uassert.True(t, AddressNamespace(addrNS), "a real address")
	uassert.False(t, AddressNamespace("moul"), "a name")
	uassert.False(t, AddressNamespace(""), "empty")
	// b, i, o and 1 are exactly the characters bech32 drops.
	uassert.False(t, AddressNamespace("g1bbbfred47kzduec920z88wfr64ylksmdcedlf5"), "wrong length")
}
