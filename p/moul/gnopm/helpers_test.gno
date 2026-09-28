package gnopm

// Fixtures shared by the tests in this package.
//
// addrNS is moul's mainnet address, used wherever a test needs a real bech32
// address rather than a plausible-looking string: the address-namespace rule
// turns on the bech32 alphabet, so a made-up "g1aaa..." would pass or fail for
// the wrong reason.
const (
	addrNS   = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
	alice    = address("g1ubwjz3jmrjwmpuvrsjzgy5qkxf5wrgphzmd2tk")
	bob      = address("g1e8vw6gh284q7ggzqs66ug0zvyf42tzsf5zdhsk")
	carol    = address("g1v9kxjcm9ta047h6lta047h6lta047h6lz7gmv8")
	sha1Zero = "0000000000000000000000000000000000000000"
	sha1One  = "1111111111111111111111111111111111111111"
)

// resolver builds an r/sys/users stand-in from a name -> address table, so the
// ownership rule is tested without importing a realm.
func resolver(table map[string]address) func(string) (address, bool) {
	return func(name string) (address, bool) {
		a, ok := table[name]
		return a, ok
	}
}
