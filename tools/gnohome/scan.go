package main

import (
	"net/url"
	"strconv"
	"strings"
)

// This file mirrors r/moul/home/scan.gno, which builds its links with
// p/moul/mygnoscan. It exists so `gnohome preview` shows the footer the chain
// would show instead of a literal ":scan.links:".
//
// Mirroring rather than importing is forced: p/moul/mygnoscan is gno, and its
// Scanner reads chain state (runtime.ChainHeight, and the base URL out of
// r/moul/config). Only the three URL shapes below are reproduced, and they are
// the whole of what the layout can reference.
//
// ⚠️ The base URL is the DEFAULT, not what r/moul/config currently says. A
// preview therefore shows the right links for an unconfigured chain and may
// differ from production if the explorer is ever repointed. That is the same
// class of approximation as env.height and is noted in preview's output.

// defaultScanBase mirrors p/moul/mygnoscan's DefaultBase.
const defaultScanBase = "https://mygnoscan.moul.p2p.team"

// networkFor mirrors p/moul/mygnoscan's NetworkFor.
func networkFor(chainID string) string {
	switch chainID {
	case "gnoland-1":
		return "mainnet"
	case "pearl-1":
		return "pearl"
	case "sapphire-1":
		return "sapphire"
	case "staging":
		return "staging"
	default:
		return ""
	}
}

// scanURL mirrors Scanner.URL: the network is the only query parameter any of
// the three shapes below carries, and it is dropped when empty.
func scanURL(chainID, path string) string {
	if path == "" {
		path = "/"
	} else if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	out := defaultScanBase + path
	if n := networkFor(chainID); n != "" {
		v := url.Values{}
		v.Set("network", n)
		out += "?" + v.Encode()
	}
	return out
}

// trimDomain mirrors p/moul/mygnoscan's TrimDomain, minus its safePath check:
// the only path this ever sees is realmPath, a constant.
func trimDomain(pkgPath string) string {
	return strings.Trim(strings.TrimPrefix(pkgPath, "gno.land/"), "/")
}

// escapeSegment mirrors p/moul/mygnoscan's escapeSegment, which is
// encodeURIComponent and NOT url.PathEscape: the two differ on "$", "&", "+",
// "," and ":", none of which occur in a bech32 address, but the explorer
// round-trips the segment with decodeURIComponent so the mirror follows the
// original rather than the nearest stdlib call.
func escapeSegment(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9',
			c == '-', c == '_', c == '.', c == '~':
			b.WriteByte(c)
		default:
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&0x0f])
		}
	}
	return b.String()
}

func scanRealm(chainID, pkgPath string) string {
	p := trimDomain(pkgPath)
	if p == "" {
		return scanURL(chainID, "/")
	}
	return scanURL(chainID, "/realm/"+p)
}

func scanAddress(chainID, addr string) string {
	if addr == "" {
		return scanURL(chainID, "/accounts")
	}
	return scanURL(chainID, "/address/"+escapeSegment(addr))
}

func scanBlock(chainID string, height int64) string {
	if height <= 0 {
		return scanURL(chainID, "/blocks")
	}
	return scanURL(chainID, "/block/"+strconv.FormatInt(height, 10))
}

func mdLink(text, target string) string { return "[" + text + "](" + target + ")" }

// addScanPlaceholders registers the five :scan*: placeholders, mirroring
// registerScanCallbacks in r/moul/home/scan.gno.
func addScanPlaceholders(add func(placeholder, value string), e env) {
	realm := mdLink("this realm", scanRealm(e.chainID, e.realm))
	me := mdLink("my account", scanAddress(e.chainID, e.owner))
	block := mdLink("this block", scanBlock(e.chainID, e.height))

	add(":scan:", defaultScanBase)
	add(":scan.realm:", mdLink("mygnoscan", scanRealm(e.chainID, e.realm)))
	add(":scan.me:", me)
	add(":scan.block:", block)
	add(":scan.links:", strings.Join([]string{realm, me, block}, " · "))
}
