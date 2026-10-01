package zones

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// A real node id, from mainnet's published persistent_peers.
const nodeID = "g15rcv5yqef3kvnmueqvkyw8y05sd40jz9p3n5su"

func TestValidateSlug(t *testing.T) {
	cases := []struct {
		in, err string
	}{
		{"mainnet", ""},
		{"onyx", ""},
		{"moul-staging", ""},
		{"t1", ""},
		{"a", "2 to 32"},
		{strings.Repeat("a", 33), "2 to 32"},
		{"Mainnet", "[a-z0-9-]"},
		{"-onyx", "[a-z0-9-]"},
		{"onyx-", "[a-z0-9-]"},
		{"on_yx", "[a-z0-9-]"},
		{"on/yx", "[a-z0-9-]"},
		{"on|yx", "[a-z0-9-]"},
	}
	for _, c := range cases {
		err := ValidateSlug(c.in)
		if c.err == "" {
			uassert.NoError(t, err, c.in)
		} else {
			uassert.ErrorContains(t, err, c.err, c.in)
		}
	}
}

func TestValidateChainID(t *testing.T) {
	uassert.NoError(t, ValidateChainID("gnoland-1"))
	uassert.NoError(t, ValidateChainID("moulstaging-1"))
	uassert.NoError(t, ValidateChainID("dev"))
	uassert.NoError(t, ValidateChainID("test_5.x"))
	uassert.ErrorContains(t, ValidateChainID(""), "1 to 50")
	uassert.ErrorContains(t, ValidateChainID(strings.Repeat("x", 51)), "1 to 50")
	uassert.ErrorContains(t, ValidateChainID("gno land"), "[A-Za-z0-9._-]")
	uassert.ErrorContains(t, ValidateChainID("a|b"), "[A-Za-z0-9._-]")
}

func TestValidateEndpoint(t *testing.T) {
	cases := []struct {
		kind EndpointKind
		addr string
		err  string
	}{
		{RPC, "https://rpc.gno.land", ""},
		{RPC, "https://rpc.gno.land:443", ""},
		{RPC, "http://127.0.0.1:26657", ""},
		{RPC, "tcp://127.0.0.1:26657", ""},
		{RPC, "wss://rpc.gno.land/websocket", ""},
		{Gnoweb, "https://gno.land", ""},
		{Indexer, "https://indexer.gno.land/graphql/query", ""},
		{Faucet, "https://onyx.testnets.gno.land/faucet", ""},
		{Explorer, "https://gnoscan.io/?chainId=onyx-1", ""},
		{Seed, nodeID + "@seed-1.gno.land:26656", ""},
		{Peer, nodeID + "@10.0.0.1:26656", ""},

		{RPC, "", "is empty"},
		{RPC, "rpc.gno.land", "needs a scheme"},
		{RPC, "ftp://rpc.gno.land", "scheme is"},
		{Gnoweb, "tcp://gno.land", "scheme is"},
		{RPC, "https://", "has no host"},
		{RPC, "https:///path", "has no host"},
		{RPC, "https://user:pass@rpc.gno.land", "credentials"},
		{Gnoweb, "https://gno.land/a b", "contains"},
		{Gnoweb, "https://gno.land/)evil", "contains"},
		{Gnoweb, "https://gno.land/[x]", "contains"},
		{Gnoweb, "https://gno.land/\"x", "contains"},
		{Gnoweb, "https://gno.land/é", "contains"},
		{Gnoweb, "https://gno.land/" + strings.Repeat("a", MaxURLLen), "longer than"},

		{RPC, "https://:26657", "has no host"},
		{RPC, "https://host:not-a-port", "port is 1 to 65535"},
		{RPC, "https://host:99999", "port is 1 to 65535"},
		{RPC, "https://host:", "port is 1 to 65535"},
		{RPC, "https://ho_st", "DNS name"},
		{RPC, "https://[::1]:26657", "contains"},
		{RPC, "https://rpc.gno.land:443/path?x=1", ""},
		{RPC, "https://rpc.gno.land:443/path?x=1#f", "contains"}, // a fragment is never sent: no second listing
		{RPC, "https://rpc.gno.land:+443", "port is 1 to 65535"},
		{Gnoweb, "https://gno.land/%zz", "two hex digits"},
		{Gnoweb, "https://gno.land/%2", "two hex digits"},
		{Gnoweb, "https://gno.land/%2F", ""},
		{Gnoweb, "https://gno.land/?a=1&b=2", ""},
		{Gnoweb, "https://gno.land/?a=1&amp;b=2", "entity"},
		{Gnoweb, "https://0x7f.1", "DNS name"},
		{Gnoweb, "https://a.1", "DNS name"},
		{Gnoweb, "https://foo.123", "DNS name"},
		{Gnoweb, "https://1.2.3.4", ""},
		{Peer, "G15RCV5YQEF3KVNMUEQVKYW8Y05SD40JZ9P3N5SU@seed-1.gno.land:26656", "lowercase g1 address"},
		{Peer, nodeID + "@seed-1.gno.land:+26656", "1 to 65535"},
		{Peer, nodeID + "@" + strings.Repeat("a.", 120) + "example:26656", "longer than"},
		{RPC, "https://rpc.gno.land.", ""},
		{RPC, "http://10.0.0.1:26657", ""},
		{RPC, "http://localhost:26657", ""},
		{RPC, "https://-.example", "DNS name"},
		{RPC, "https://bad-.example", "DNS name"},
		{RPC, "https://-bad.example", "DNS name"},
		{RPC, "https://foo..example", "DNS name"},
		{RPC, "https://.example", "DNS name"},
		{RPC, "https://example..", "DNS name"},
		{RPC, "https://" + strings.Repeat("a", 64) + ".example", "DNS name"},
		{RPC, "https://" + strings.Repeat("a", 63) + ".example", ""},
		{RPC, "http://300.1.1.1", "DNS name"},
		{RPC, "http://1.2.3", "DNS name"},
		{RPC, "http://01.2.3.4", "DNS name"},
		{Peer, nodeID + "@bad-.example:26656", "DNS name"},

		{Peer, "seed-1.gno.land:26656", "<node id>@"},
		{Peer, "nope@seed-1.gno.land:26656", "g1 address"},
		{Peer, nodeID + "@seed-1.gno.land", "needs a port"},
		{Peer, nodeID + "@:26656", "needs a port"},
		{Peer, nodeID + "@seed-1.gno.land:0", "1 to 65535"},
		{Peer, nodeID + "@seed-1.gno.land:65536", "1 to 65535"},
		{Peer, nodeID + "@seed-1.gno.land:080", "1 to 65535"},
		{Peer, nodeID + "@seed-1.gno.land:port", "1 to 65535"},
		{Seed, nodeID + "@seed_1.gno.land:26656", "DNS name"},
		{Seed, nodeID + "@[::1]:26656", "DNS name"},

		{RPC, "HTTPS://rpc.gno.land", ""},
		{Gnoweb, "Https://gno.land", ""},
		{" rpc ", "not a url", "unknown endpoint kind"},
		{"RPC", "https://rpc.gno.land", "unknown endpoint kind"},
		{"", "https://gno.land", "needs a kind"},
		{"grpc", "https://gno.land", "unknown endpoint kind"},
	}
	for _, c := range cases {
		err := ValidateEndpoint(c.kind, c.addr)
		label := string(c.kind) + " " + c.addr
		if c.err == "" {
			uassert.NoError(t, err, label)
		} else {
			uassert.ErrorContains(t, err, c.err, label)
		}
	}
}

func TestValidateInfo(t *testing.T) {
	ok := Info{ChainID: "onyx-1", Title: "Onyx", Kind: Testnet, RPCURL: "https://rpc.onyx.testnets.gno.land"}
	uassert.NoError(t, ValidateInfo(ok))
	// A loopback main RPC is a local zone's, and only a local zone's: it names a
	// different machine for every reader.
	tcp := ok
	tcp.RPCURL = "tcp://127.0.0.1:26657"
	uassert.ErrorContains(t, ValidateInfo(tcp), "loopback or private")
	tcp.Kind = Local
	uassert.NoError(t, ValidateInfo(tcp))
	for _, h := range []string{"http://localhost:26657", "http://10.0.0.1:26657", "http://192.168.1.2", "http://172.20.0.1",
		"http://169.254.169.254", "http://100.64.0.1", "http://0.0.0.0:26657", "http://api.localhost"} {
		in := ok
		in.RPCURL = h
		uassert.ErrorContains(t, ValidateInfo(in), "loopback or private", h)
	}
	pub := ok
	pub.RPCURL = "http://172.32.0.1"
	uassert.NoError(t, ValidateInfo(pub))

	bad := func(mut func(*Info), want string) {
		in := ok
		mut(&in)
		uassert.ErrorContains(t, ValidateInfo(in), want)
	}
	bad(func(in *Info) { in.ChainID = "" }, "chain id")
	bad(func(in *Info) { in.Title = "" }, "title is 1 to 64")
	bad(func(in *Info) { in.Title = strings.Repeat("x", MaxTitleLen+1) }, "title is 1 to 64")
	bad(func(in *Info) { in.Title = "two\nlines" }, "control character")
	bad(func(in *Info) { in.Title = "\u200b" }, "invisible or bidi")
	bad(func(in *Info) { in.Title = "\u2060" }, "invisible or bidi")
	bad(func(in *Info) { in.Title = "\u3164" }, "invisible or bidi")
	bad(func(in *Info) { in.Title = "\u061cOnyx" }, "invisible or bidi")
	bad(func(in *Info) { in.Title = "Onyx\ufe0f" }, "invisible or bidi")
	bad(func(in *Info) { in.Title = "Onyx\U000e0041" }, "invisible or bidi")
	bad(func(in *Info) { in.Title = "\u2800" }, "invisible or bidi")
	bad(func(in *Info) { in.Title = "\u2705 official mainnet" }, "status glyph")
	bad(func(in *Info) { in.Title = "Z\u0301\u0301\u0301" }, "combining marks")
	bad(func(in *Info) { in.Title = "\u0301" }, "nothing visible")
	bad(func(in *Info) { in.Title = "bad\xffbyte" }, "not valid UTF-8")
	bad(func(in *Info) { in.Title = "alpha\u2028beta" }, "control character")
	bad(func(in *Info) { in.Title = "alpha\u2029beta" }, "control character")
	bad(func(in *Info) { in.Title = "alpha\u0085beta" }, "control character")
	bad(func(in *Info) { in.Description = "x\u009by" }, "control character")
	bad(func(in *Info) { in.Title = "Onyx\u202e" }, "invisible or bidi")
	bad(func(in *Info) { in.Description = "fine\u200dtext" }, "invisible or bidi")
	bad(func(in *Info) { in.Description = strings.Repeat("x", MaxDescriptionLen+1) }, "description is at most")
	bad(func(in *Info) { in.Kind = "" }, "needs a kind")
	bad(func(in *Info) { in.Kind = "betanet" }, "unknown kind")
	bad(func(in *Info) { in.RPCURL = "" }, "rpc url is empty")
	// The main RPC is what gnokey -remote gets, which dials http, https, tcp.
	bad(func(in *Info) { in.RPCURL = "wss://rpc.onyx.testnets.gno.land/websocket" }, "rpc url scheme")
	bad(func(in *Info) { in.RPCURL = "ws://rpc.onyx.testnets.gno.land/websocket" }, "rpc url scheme")
	bad(func(in *Info) { in.RPCURL = "https://rpc.example/path" }, "no path")
	bad(func(in *Info) { in.RPCURL = "https://rpc.example?x=1" }, "no path")
	bad(func(in *Info) { in.RPCURL = "https://rpc.example:443#f" }, "contains")
	bad(func(in *Info) { in.RPCURL = "https://rpc.example/" }, "no path")
	bad(func(in *Info) { in.Kind = " testnet " }, "unknown kind")
	port := ok
	port.RPCURL = "https://rpc.onyx.testnets.gno.land:443"
	uassert.NoError(t, ValidateInfo(port))
	bad(func(in *Info) { in.GnowebURL = "gno.land" }, "gnoweb url needs a scheme")
	bad(func(in *Info) { in.GenesisURL = "tcp://x" }, "genesis url scheme")

	// Runes, not bytes: a 64-character title of multi-byte runes is fine.
	in := ok
	in.Title = strings.Repeat("é", MaxTitleLen)
	uassert.NoError(t, ValidateInfo(in))
}

func TestCanonical(t *testing.T) {
	uassert.Equal(t, "https://rpc.gno.land/API?Q=1", Canonical(RPC, "HTTPS://RPC.Gno.Land/API?Q=1"))
	uassert.Equal(t, "https://rpc.gno.land", Canonical(RPC, "https://RPC.gno.land"))
	// One endpoint, one key: every spelling below is the same server.
	for _, same := range []string{"https://rpc.gno.land", "https://rpc.gno.land/", "https://rpc.gno.land.",
		"https://rpc.gno.land:443", "https://rpc.gno.land?", "HTTPS://RPC.gno.land.:443/"} {
		uassert.Equal(t, "https://rpc.gno.land", Canonical(RPC, same), same)
	}
	uassert.Equal(t, "http://h.example", Canonical(Gnoweb, "http://h.example:80"))
	uassert.Equal(t, "http://h.example:443", Canonical(Gnoweb, "http://h.example:443")) // not http's default
	uassert.Equal(t, "https://h.example/api", Canonical(Indexer, "https://h.example:443/api"))
	uassert.Equal(t, nodeID+"@seed-1.gno.land:26656", Canonical(Peer, nodeID+"@SEED-1.gno.land:26656"))
}

func TestParse(t *testing.T) {
	for _, s := range []string{"", "approved", "pending", "rejected", "retired"} {
		_, err := ParseStatus(s)
		uassert.NoError(t, err, s)
	}
	_, err := ParseStatus("official")
	uassert.ErrorContains(t, err, "unknown status")

	_, err = ParseKind("betanet")
	uassert.ErrorContains(t, err, "unknown kind")
	k, err := ParseKind(" testnet ")
	uassert.NoError(t, err)
	uassert.Equal(t, string(Testnet), string(k))

	_, err = ParseEndpointKind("grpc")
	uassert.ErrorContains(t, err, "unknown endpoint kind")
	_, err = ParseVerification("trusted")
	uassert.ErrorContains(t, err, "unknown verification")

	// Every listed value parses back to itself.
	for _, v := range EndpointKinds() {
		got, err := ParseEndpointKind(string(v))
		uassert.NoError(t, err)
		uassert.Equal(t, string(v), string(got))
	}
	for _, v := range Kinds() {
		got, _ := ParseKind(string(v))
		uassert.Equal(t, string(v), string(got))
	}
	for _, v := range Statuses() {
		got, _ := ParseStatus(string(v))
		uassert.Equal(t, string(v), string(got))
	}
	for _, v := range Verifications() {
		got, _ := ParseVerification(string(v))
		uassert.Equal(t, string(v), string(got))
	}
}
