# web: the dapps dashboard

A static page that talks to the realms in this repo straight from the browser.
Published at <https://moul.github.io/gno-contracts/>.

- **Reads** go to the chain's JSON-RPC (`vm/qrender`, `vm/qeval`, `vm/qfuncs`,
  `vm/qfile`). Every public gno RPC sends `access-control-allow-origin: *`, so no
  server or proxy sits in between.
- **Writes** go through [Adena](https://adena.app). The page never sets gas: the
  wallet simulates the call and shows the fee before signing.
- **No build step, no dependency.** Plain ES modules; what is in this folder is what
  is served.

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
| Source | the deployed files, as the chain has them |

The list of realms comes from `contracts.json` on `main`, filtered to what is
uploaded on the selected network.

## Adding a demo

1. A line in [`apps/index.js`](./apps/index.js): `{ path, title, blurb }`. It shows on
   the front page and opens in the generic view.
2. When it deserves its own UI, write `apps/<name>.js` exporting
   `mount(el, { client, net, path, call })`, return a cleanup function, and add
   `module: "<name>"` to its line. [`apps/counter.js`](./apps/counter.js) is the
   worked example: it polls `Value()` and turns `Inc` / `Dec` into buttons.

## Deploy

`.github/workflows/web.yml` publishes this folder to the `gh-pages` branch on every
push to `main` that touches `web/`. The branch holds only the latest copy.
