# `gno.land/r/moul/x/daily/hmacdemo/v0`

**Demo of the [`p/moul/x/daily/hmac`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/hmac)
library.** Stateless: `Render` computes every tag on the page while the page is being served.

Three things the page shows, in order:

1. **RFC 4231, checked live.** Five of the standard HMAC-SHA-256 vectors, each computed by the
   library and compared against the RFC's published tag, with a `matches` column. A row saying
   `no` means the chain is serving something that is not HMAC. The page is a measurement of
   the library rather than a quotation of it.
2. **Two different keys, one tag.** A 131-byte key and its 32-byte SHA-256 produce the same
   tag, because HMAC folds any key longer than the 64-byte block into its own digest first.
   Rendered side by side so the equality is visible rather than asserted.
3. **Why not `sha256(key + message)`.** The naive prefix MAC beside the real one, both 32
   bytes, both changing with either input, one of them forgeable by length extension.

`Render("/<text>")` tags that text under the key `moul`, which is printed on the page on
purpose: a realm cannot hold a secret, so nothing here is authenticated and the demo says so.
The echoed text goes through `md.InlineCode`, and a test pins that a payload carrying a
backtick and an image cannot break out of its code span.

No cryptography of its own.
