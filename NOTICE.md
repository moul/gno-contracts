# Notices

Third-party names, marks and prior art referenced by contracts in this
repository. Nothing on this page claims an affiliation; the point of the page is
to record that there is none.

## Plan 9 (`p/moul/x/plan9/*`, `r/moul/x/plan9/*`)

**Plan 9 from Bell Labs** was designed and built by the Computing Science
Research Center at Bell Labs. The name, the marks and the legacy are theirs.
Since March 2021 the copyright is held by the
[Plan 9 Foundation](https://p9f.org), which re-released editions 1 to 4 under
the MIT license.

**The `x/plan9` packages in this repository are not affiliated with, endorsed
by, or sponsored by Bell Labs, Nokia or the Plan 9 Foundation**, and no Plan 9
source code was copied into them. Every line is original gno, written against
the published papers and the 9P2000 specification: `ninep` implements 9P's
semantics and not its wire format, `memfs` answers to `ramfs`, `ns` to
`bind(2)`, `rc` to the shell of the same name, `dev` to the device tree. The
names are borrowed so that anyone who knows Plan 9 can read the code without a
glossary, and for no other reason.

They are an homage, and an experiment. Plan 9 is one of the most coherent and
unusual systems anyone has built, and these packages ask one question: what does
its spirit look like on a chain, where resources are already named by
hierarchical path and `Render(path)` is already a read on a sub-path? If
anything here reads as a claim on that work, it is not one. Read the originals
instead:

- [Plan 9 from Bell Labs](https://9p.io/sys/doc/9.html), Pike, Presotto, Dorward, Flandrena, Thompson, Trickey, Winterbottom
- [The Use of Name Spaces in Plan 9](https://9p.io/sys/doc/names.html)
- [Lexical File Names in Plan 9, or Getting Dot-Dot Right](https://9p.io/sys/doc/lexnames.html)
- [The Plan 9 Foundation](https://p9f.org), which holds the copyright and ships the source

---

For the repository overview and catalog see the [README](./README.md); for what
this code is and is not fit for, [DISCLAIMER](./DISCLAIMER.md).
