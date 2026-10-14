// The featured dapps, in the order the dashboard shows them.
//
// Two kinds, so a demo can start as one line and grow:
//   { path }              the generic view: Render, functions, source
//   { path, module }      a custom page, `apps/<module>.js`, exporting
//                         `mount(el, ctx)`; ctx is { client, net, path, call, wallet }
//
// Adding one: a line here. Promoting one: write the module, add `module`.

export const FEATURED = [
  { path: "gno.land/r/moul/x/daily/counter/v0", module: "counter", title: "Counter Club", blurb: "A shared counter, live: read it every few seconds, Inc and Dec from your wallet." },
  { path: "gno.land/r/moul/x/daily/dice/v0", module: "dice", title: "Dice", blurb: "Roll a die from your wallet and watch the distribution move." },
  { path: "gno.land/r/moul/x/daily/hangman/v0", module: "hangman", title: "Hangman", blurb: "One shared word a day. Click a letter, everyone sees it." },
  { path: "gno.land/r/moul/x/daily/eightball/v1", module: "eightball", title: "Magic 8-ball", blurb: "Ask a yes/no question, the block height answers." },
  { path: "gno.land/r/moul/home", title: "Home", blurb: "moul's home realm, rendered from the chain." },
  { path: "gno.land/r/moul/blog", title: "Blog", blurb: "The on-chain blog." },
  { path: "gno.land/r/moul/present/v0", title: "Present", blurb: "Slides as a realm." },
  { path: "gno.land/r/moul/gallery/v0", title: "Gallery" },
  { path: "gno.land/r/moul/x/daily/life/v0", title: "Game of Life" },
  { path: "gno.land/r/moul/x/daily/guestbook/v1", title: "Guestbook" },
  { path: "gno.land/r/moul/x/daily/connect4/v1", title: "Connect 4" },
  { path: "gno.land/r/moul/x/daily/leaderboard/v1", title: "Leaderboard" },
  { path: "gno.land/r/moul/x/amm/v0", title: "AMM" },
  { path: "gno.land/r/moul/demo/microposts/v0", title: "Microposts" },
];
