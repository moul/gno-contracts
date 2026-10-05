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
- **No build step, no dependency.** Plain ES modules; what is in this folder is what
  is served. [`lib/amino.js`](./lib/amino.js), the encoder simulation needs, is copied
  from [moul/gno4](https://github.com/moul/gno4/blob/main/web/amino.js), where it is
  tested byte for byte against gnokey.

## Run it locally

```bash
make web            # http://127.0.0.1:8080
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

## Adding a demo

1. A line in [`apps/index.js`](./apps/index.js): `{ path, title, blurb }`. It shows on
   the front page and opens in the generic view.
2. When it deserves its own UI, write `apps/<name>.js` exporting
   `mount(el, { client, net, path, call, wallet })`, return a cleanup function, and add
   `module: "<name>"` to its line. [`apps/counter.js`](./apps/counter.js) is the
   worked example: it polls `Value()` and turns `Inc` / `Dec` into buttons.

## Deploy

`.github/workflows/web.yml` publishes this folder to the `gh-pages` branch on every
push to `main` that touches `web/`. The branch holds only the latest copy.
