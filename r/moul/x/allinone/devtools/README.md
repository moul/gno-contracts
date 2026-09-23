# `gno.land/r/moul/x/allinone/devtools`

The worked example of wiring moul's developer packages into one realm: what a
new realm should copy.

Eight packages, each earning its place in the output:

| package | what it contributes |
|---|---|
| [`r/moul/config`](../../../config) | the notice block, the pause guard, which explorer to link |
| [`p/moul/mygnoscan`](../../../../p/moul/mygnoscan) | the explorer routes |
| [`p/moul/debug`](../../../../p/moul/debug) | the `?debug=1` panel |
| [`p/moul/realmpath`](../../../../p/moul/realmpath) | reading the render path |
| [`p/moul/kit/ui`](../../../../p/moul/kit/ui) | escaping caller input, and the tables |
| [`p/moul/md`](../../../../p/moul/md) | the markdown |
| [`p/moul/txlink`](../../../../p/moul/txlink) | the call links |
| [`p/moul/fifo`](../../../../p/moul/fifo) | the bounded note list |

## The three lines worth copying

```go
func Render(path string) string {
	return config.TopBlockFor(realmPath) + body + config.BottomBlockFor(realmPath)
}

func Add(cur realm, body string) {
	config.AssertWritableFor(realmPath)  // honours the pause switch
	notes.Append(ui.Inline(body))        // escapes what a caller typed
}
```

The first gives the realm a place for a warning and a pause banner without
shipping any banner code, and returns `""` while nothing is set, so a page that
concatenates it unconditionally is unchanged by default.

The second is two separate guards and both have to be there: the pause one so
an incident can stop writes from outside this realm and without a redeploy, and
the escaping one because a string a caller typed is the oldest way to break a
page.

## Two views

`Render("")` is the root and is free of anything that moves, so an example test
can pin it. Everything live (the height, the chain id, the links built from
them) is under `:chain`, which is also what keeps the pinned output stable.

State is disposable: the note list is bounded by `fifo` at 10 entries and this
realm is `private = true`, so a redeploy wipes it on purpose.
