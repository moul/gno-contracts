# web: the dapps dashboard

A static page that talks to the realms in this repo straight from the browser.
Published at <https://moul.github.io/gno-contracts/>.

- **Reads** go to the chain's JSON-RPC (`vm/qrender`, `vm/qeval`, `vm/qfuncs`,
  `vm/qfile`). Every public gno RPC sends `access-control-allow-origin: *`, so no
  server or proxy sits in between.
- **Writes** depend on who you are, set once in the header's **Connect** modal, which
  always shows the address the page acts for:
  - **Adena** ([adena.app](https://adena.app), suggested when it is missing). The page
    never sets gas: the wallet simulates the call and shows the fee before signing.
  - **An address typed by hand.** Every write opens a modal with the
    `gnokey maketx call` to paste, prefilled with that address's key name. The page
    runs the call through `.app/simulate` (no signature needed for a call) and fills
    in the measured gas plus 30% and a fee at twice the chain's floor. It never
    prints a gas figure it did not measure.
- **🧪 Dry run**, the header toggle: every write is simulated as the connected
  address instead of sent, and the result lands in a dashed yellow box: what the call
  would return or the panic it would hit, the gas and fee, the storage it would lock,
  and the events it would emit. Nothing is signed.
- **The gnokey command itself** is [`lib/cmd.js`](./lib/cmd.js): pure, no DOM and no
  storage, so it is unit-tested and any app can print it inline instead of in the modal.
- **No build step, no dependency.** Plain ES modules; what is in this folder is what
  is served. [`lib/amino.js`](./lib/amino.js), the encoder simulation needs, is copied
  from [moul/gno4](https://github.com/moul/gno4/blob/main/web/amino.js), where it is
  tested byte for byte against gnokey.

## Run it locally

```bash
make web            # http://127.0.0.1:8080
make test-web       # the live apps under node, against a scripted chain (test/)
```

The `local` network targets a `gnodev` on `127.0.0.1:26657`.

## Every realm gets the generic view

`#/r/<path>[:<args>]` shows a realm three ways:

| tab | what |
|---|---|
| Render | the markdown `Render()` returns, links rewired to stay in the dashboard |
| Functions | every exported function: a read one becomes a `qeval` form, a crossing one (`cur realm` first) a wallet transaction |
| Source | every deployed file on one page, code first, then tests, then the rest |

The list of realms comes from `contracts.json` on `main`, filtered to what is
uploaded on the selected network.

## Custom apps

A realm with its own page carries a **⚡ live app** badge, on its card and in the
list, and sorts first. Today:

| realm | page | what it adds |
|---|---|---|
| `x/daily/counter/v0` | [`counter.js`](./apps/counter.js) | live value, Inc / Dec buttons |
| `x/daily/dice/v0` | [`dice.js`](./apps/dice.js) | the distribution as bars, Roll, your own rolls |
| `x/daily/hangman/v0` | [`hangman.js`](./apps/hangman.js) | gallows and word lifted from `Render`, an A to Z keyboard of `Guess` calls |
| `x/daily/eightball/v1` | [`eightball.js`](./apps/eightball.js) | a question box, the answer the transaction returned |
| `smallgrants` | [`smallgrants.js`](./apps/smallgrants.js) | every grant request with its outcome, and a checked form to file one |

## The small-grants page

Two things only: **see the list**, and **ask for a grant**. Deciding a request pays money
and is not on this page; it shows what the controllers decided and why, and stops there.

- **The list** reads the realm's public `Render` and lifts the rows out of the markdown,
  by column name and row label, never by position. A decided request's own page is read
  once and cached, because a decision is final: that is what puts the reason next to the
  outcome in the list instead of behind a click. **A refusal with no reason reads as a
  decision somebody took**, in body text, not greyed out; and before a reason has been read
  at all the page says nothing about one, rather than claiming there was none.
- **Asking is checked before anything is signed**, in three layers: the realm's own rules
  re-stated in the page (the 100 GNOT cap, the bech32 address, the two byte limits, the
  pause rule, the invisible characters that do not count as text); a review that says in
  words what is about to be sent and that **it sends no coins**; and a simulation against
  the chain, whose panic disables the signature. A measurement is thrown away the moment
  the form changes, because a green check against different arguments is worse than none.
- **gnokey support is the command, because a browser cannot run gnokey.** The exact
  `gnokey maketx call` sits under the form and stays correct as you type; once the call has
  been simulated it carries the measured gas, and until then it says so instead of guessing.
- **Not published yet is a first-class state**, not an error screen: it is what
  `r/moul/smallgrants/v0` shows today, and the form still validates and still prints the
  command while it waits.

When the realm grows a machine-readable getter for the list, `parseIndex` and `parseRequest`
are the two functions to replace, and nothing else in the page changes.

## Optimistic UI

A live app shows a write the moment it leaves, before the chain has it: the counter
moves, the die spins, the letter is marked, the 8-ball shakes, all styled as pending
with an "N pending" chip. "Leaves" is the wallet popup opening, or the visitor
clicking "I sent it" in the gnokey modal; a dry run never counts. Each refresh tells
[`lib/optimistic.js`](./lib/optimistic.js)'s queue what the chain now shows, and only
the visitor's own change settles the visitor's entry: a row of the realm's history with
their address on it (counter, 8-ball), their own `RollsOf` (dice). A realm-wide count
like `Total()` moves for everyone, so it never settles anything. Hangman's guesses carry
no address, so a letter settles on the letter. A rejected popup rolls the change back at
once. A change the chain never shows rolls back after 3 minutes, and says so. Nothing is
shown as pending before the page has read the realm once, or without a connected
address to attribute it to.

## Adding a demo

1. A line in [`apps/index.js`](./apps/index.js): `{ path, title, blurb }`. It shows on
   the front page and opens in the generic view.
2. When it deserves its own UI, write `apps/<name>.js` exporting
   `mount(el, { client, net, path, call, wallet })`, where
   `call(func, args, { send, onSubmit })` sends `send` (e.g. `"1000000ugnot"`) with the
   call and fires `onSubmit` as the transaction leaves. Return a cleanup function, and add
   `module: "<name>"` to its line. [`apps/counter.js`](./apps/counter.js) is the
   worked example: it polls `Value()` and turns `Inc` / `Dec` into buttons.

## Deploy

`.github/workflows/web.yml` publishes this folder to the `gh-pages` branch on every
push to `main` that touches `web/`. The branch holds only the latest copy.
