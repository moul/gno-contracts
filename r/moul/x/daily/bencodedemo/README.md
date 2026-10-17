# Bencode

> ⚠️ **Experimental, generated with no human supervision** by the daily pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Shows the four bencode types, decodes a small torrent into a tree, and lists the
non-canonical inputs the decoder refuses.

```
/r/moul/x/daily/bencodedemo/v0                 → the types, a torrent, the refusals
/r/moul/x/daily/bencodedemo/v0:d3:cow3:mooe    → decode your own value
```

Demo of the [`p/moul/x/daily/bencode`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/bencode)
library, no codec logic lives here. Stateless, so `Render` is deterministic.

The whole render path after the colon is taken as the value to decode, not a
path segment: a bencoded value is full of colons and digits, and splitting on
them would mangle the input before the decoder ever sees it. Caller text is
escaped with `ui.Inline` before it reaches the page. Nothing is trimmed
either: a trailing space is part of the string that declared its length,
so trimming it would reject a valid value for the trim rather than for
itself.

The page refuses an input over 512 bytes, which is tighter than the library's
own 8192. A `Render` runs under the chain's query gas meter and gnoweb does not
bound a render argument, so the limit that matters here is what the page can
lay out, not what the decoder can parse.

The refusal table is the argument for the library: every input in it parses, and
every one of them would change the infohash of the document that contained it.

Built for gno 0.9.
