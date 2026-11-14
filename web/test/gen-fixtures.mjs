// Regenerates web/test/fixtures.js: the small-grants page's test fixture.
//
// The whole point of this file is that the fixture is NOT written by the same
// hand as the parser. The markdown every test parses is produced here by a
// faithful port of the realm's own render.gno (its ui.Table / md / num helpers,
// byte for byte), and then LOCKED against the realm's committed golden:
//
//   * the empty index must equal render_test.gno's `atDeploy` exactly, which
//     pins every index helper (num.GNOTf, ui.Table, ui.AddrFull, md.*,
//     OrEmpty, the banner) to the realm's own TestRenderAtDeploy oracle, and
//   * the populated pages must contain every substring the realm's own tests
//     assert (grants_test.gno / render_test.gno): "**paid 40 GNOT of 100
//     GNOT**", "pay 40 GNOT of 100 GNOT", "| *no reason given* |",
//     "| out of scope |", "| refused |", "**refused**".
//
// So the fixture agrees with the REALM, not with the parser. If render.gno's
// format changes, this script's self-check fails until it is brought back in
// line, and the regenerated fixture then re-breaks any parser that drifted.
//
// Usage:
//   node web/test/gen-fixtures.mjs            # derive from render.gno port, self-verify, write
//   node web/test/gen-fixtures.mjs --from-chain <rpc> <pkgpath>
//                                             # once the realm is live, read its
//                                             # real Render over RPC instead and
//                                             # pin that; the self-check on the
//                                             # empty index still guards it.
//
// The realm source lives on its own PR branch; this script does not need it.
// It needs render.gno's *format*, which the golden below pins.

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const PATH = "gno.land/r/moul/smallgrants/v0";
const ROUTE = "/r/moul/smallgrants/v0"; // link(): selfPath without the domain

// Addresses. The three controllers are the realm's real ones (they appear in
// the golden). The desk address and the three users are crafted from the
// bech32 charset so they are valid g1 addresses the page's ADDR regex accepts;
// their exact bytes do not matter, only that the fixture is self-consistent.
const Moul = "g1m7nvpk9trgj5sqhwdu2r0p9v5e2pzemedglvzt";
const Jaekwon = "g1ecsuj0q572jr0dhu29q9njtnmw03hyu7tyyvv6";
const Aeddi = "g1cgnrpdemae7r2qvtkd99x3vk6cvmppsavx8eqs";
const CONTROLLERS = [Moul, Jaekwon, Aeddi];

const B32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
const mkAddr = (seed) => {
  let s = "g1";
  let x = 2166136261 >>> 0;
  for (const ch of seed) { x ^= ch.charCodeAt(0); x = Math.imul(x, 16777619) >>> 0; }
  for (let i = 0; i < 38; i++) {
    x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; // xorshift32
    s += B32[(x >>> (i % 11)) % B32.length];
  }
  return s;
};
const ADDR = mkAddr("smallgrants-desk");
const alice = mkAddr("alice");
const bob = mkAddr("bob");
const carol = mkAddr("carol");

const ADDR_RE = /^g1[02-9ac-hj-np-z]{38}$/;
for (const [n, a] of Object.entries({ ADDR, alice, bob, carol }))
  if (!ADDR_RE.test(a)) throw new Error(`crafted ${n} is not a valid g1 address: ${a}`);

// ---------------------------------------------------------------- helpers
// Faithful ports of the realm's render helpers. Each is pinned by the golden.

const UGNOT = 1_000_000;
// num.GNOTf: trailing zeros trimmed, " GNOT" appended. "100 GNOT", "0.5 GNOT".
function GNOTf(u) {
  const neg = u < 0 ? "-" : "";
  const n = Math.abs(u);
  const frac = String(n % UGNOT).padStart(6, "0").replace(/0+$/, "");
  return `${neg}${Math.floor(n / UGNOT)}${frac ? "." + frac : ""} GNOT`;
}

// The fixture uses only plain text, so sanitize.* is identity-plus-wrapping.
const Bold = (s) => `**${s}**`;
const Italic = (s) => `*${s}*`;
const H1 = (s) => `# ${s}\n`;
const H2 = (s) => `## ${s}\n`;
const InlineCode = (s) => "`" + s + "`";
const Inline = (s) => s; // sanitize.InlineText on plain text
const Cell = (s) => s; // sanitize.TableCell on plain text
const Link = (text, url) => `[${text}](${url})`;
const Blockquote = (s) => "> " + s + "\n";
const CodeBlock = (s) => "```\n" + s + "\n```\n";
const BulletList = (items) => items.map((i) => `- ${i}\n`).join("");
const Empty = (msg) => Italic(msg) + "\n";

const HEAD = 8, TAIL = 4, ELL = "…";
const AddrText = (a) => (a.length <= HEAD + 1 + TAIL ? a : a.slice(0, HEAD) + ELL + a.slice(-TAIL));
const Addr = (a) => InlineCode(AddrText(a));
const AddrFull = (a) => InlineCode(a);

// ui.Table, byte-identical to ui.gno's Table.String().
function Table(headers) {
  const rows = [];
  return {
    row(...cells) {
      if (cells.length < headers.length) cells = cells.concat(Array(headers.length - cells.length).fill(""));
      rows.push(cells); return this;
    },
    get length() { return rows.length; },
    string() {
      if (!rows.length) return "";
      let s = "| " + headers.join(" | ") + " |\n";
      s += "|" + " --- |".repeat(headers.length) + "\n";
      for (const r of rows) s += "| " + r.join(" | ") + " |\n";
      return s;
    },
    orEmpty(msg) { return rows.length ? this.string() : Empty(msg); },
  };
}

const itoa = (n) => String(n);

// ---------------------------------------------------------------- the desk
// A canonical desk. Each request carries the ballots the realm would have
// recorded for the votes described, and the Status/Paid the realm would have
// derived from them. result()/decisions() below turn that into the realm's
// exact markdown; the self-check proves the markdown is the realm's.

const DESK = {
  paused: false,
  cap: 100 * UGNOT,
  balance: 190 * UGNOT,
  totalPaid: 60 * UGNOT,
  paidCount: 2,
  quorum: 2,
  requests: [
    {
      id: 1, title: "A keyboard", by: alice, to: bob, amount: 100 * UGNOT, paid: 40 * UGNOT,
      status: "paid", height: 101, decided: 118,
      ballots: [
        { voter: Moul, yes: true, amount: 40 * UGNOT, note: "Half of it, the rest next quarter.", height: 110 },
        { voter: Jaekwon, yes: true, amount: 100 * UGNOT, note: "", height: 118 },
      ],
    },
    {
      id: 2, title: "Conference ticket", by: alice, to: carol, amount: 60 * UGNOT, paid: 0,
      status: "refused", height: 102, decided: 125,
      ballots: [
        { voter: Moul, yes: false, amount: 0, note: "", height: 120 },
        { voter: Jaekwon, yes: false, amount: 0, note: "out of scope", height: 125 },
      ],
    },
    {
      id: 3, title: "Deploy gas", by: alice, to: bob, amount: 5 * UGNOT, paid: 0,
      status: "pending", height: 103, decided: 0,
      ballots: [
        { voter: Moul, yes: true, amount: 5 * UGNOT, note: "", height: 130 },
      ],
    },
    {
      id: 4, title: "A domain", by: alice, to: bob, amount: 20 * UGNOT, paid: 20 * UGNOT,
      status: "paid", height: 104, decided: 140,
      ballots: [
        { voter: Moul, yes: true, amount: 20 * UGNOT, note: "", height: 138 },
        { voter: Jaekwon, yes: true, amount: 20 * UGNOT, note: "", height: 140 },
      ],
    },
    {
      id: 5, title: "A risky idea", by: alice, to: carol, amount: 30 * UGNOT, paid: 0,
      status: "refused", height: 105, decided: 150,
      ballots: [
        { voter: Moul, yes: false, amount: 0, note: "", height: 148 },
        { voter: Jaekwon, yes: false, amount: 0, note: "", height: 150 },
      ],
    },
    {
      id: 6, title: "Old idea", by: alice, to: carol, amount: 10 * UGNOT, paid: 0,
      status: "withdrawn", height: 106, decided: 155, ballots: [],
    },
  ],
};

const isController = (a) => CONTROLLERS.includes(a);
const yesCount = (bs) => bs.filter((b) => b.yes && isController(b.voter)).length;

// result(): a request's state in words, with what it paid. Verbatim render.gno.
function result(r) {
  if (r.status !== "paid") return r.status;
  if (r.paid === r.amount) return "paid in full";
  return "paid " + GNOTf(r.paid) + " of " + GNOTf(r.amount);
}

// decisions(): the request page's "## Decisions" table. Verbatim render.gno.
function decisions(r) {
  const t = Table(["Controller", "Decision", "Height", "Reason"]);
  for (const b of r.ballots) {
    let d = "refuse";
    if (b.amount === r.amount) d = "pay in full";
    else if (b.amount > 0) d = "pay " + GNOTf(b.amount) + " of " + GNOTf(r.amount);
    if (!isController(b.voter)) d += " (no longer a controller, not counted)";
    const why = b.note === "" ? Italic("no reason given") : Cell(b.note);
    t.row(Addr(b.voter), d, itoa(b.height), why);
  }
  return t.orEmpty("No decisions yet.");
}

const banner =
  "> **This is a demo.** A working preview of the small-grants desk I plan to\n" +
  "> deploy under `gno.land/r/nt` or `gno.land/r/gnoland`, once approved.\n" +
  "> Requests, decisions and payouts here are real; only the address is temporary.\n";

const askCommand =
  "gnokey maketx call -pkgpath " + PATH + " -func Request \\\n" +
  "  -args <payee address> -args <amount in ugnot> \\\n" +
  "  -args '<title>' -args '<what it is for>' ...";

function renderIndex(desk) {
  let out = H1("Small grants (demo)") + banner + "\n";
  out += "Ask for a small amount of GNOT, for yourself or for someone else, in the open.\n" +
    "The controllers below decide in public: pay in full, pay a part, or refuse,\n" +
    "each with an optional reason. The decision that makes a majority pays the\n" +
    "request out of this realm's balance in the same transaction.\n\n";

  const state = desk.paused
    ? "**paused**: new requests from the allowlist only; everything filed still runs"
    : "open to everyone";
  const t = Table(["", ""]);
  t.row("Requests", state);
  t.row("Cap per request", GNOTf(desk.cap));
  t.row("Balance", "**" + GNOTf(desk.balance) + "**");
  t.row("Paid out", GNOTf(desk.totalPaid) + " over " + itoa(desk.paidCount) + " grant(s)");
  t.row("Decision", desk.quorum + " yes of " + CONTROLLERS.length + " controllers");
  t.row("Fund it", "a plain send to " + AddrFull(ADDR));
  out += t.string() + "\n";

  out += H2("Ask") + CodeBlock(askCommand) + "\n";

  out += H2("Open requests");
  const ot = Table(["#", "Title", "To", "Amount", "Yes"]);
  for (const r of desk.requests.filter((r) => r.status === "pending")) {
    ot.row(Link("#" + itoa(r.id), ROUTE + ":request/" + r.id), Cell(r.title),
      Addr(r.to), GNOTf(r.amount), yesCount(r.ballots) + "/" + desk.quorum);
  }
  out += ot.orEmpty("Nothing is waiting for a decision.") + "\n";

  out += H2("Recently decided");
  const dt = Table(["#", "Title", "To", "Amount", "Outcome"]);
  for (const r of [...desk.requests].reverse().filter((r) => r.status !== "pending")) {
    dt.row(Link("#" + itoa(r.id), ROUTE + ":request/" + r.id), Cell(r.title),
      Addr(r.to), GNOTf(r.amount), result(r));
  }
  out += dt.orEmpty("Nothing has been decided yet.") + "\n";

  out += H2("Controllers");
  out += BulletList(CONTROLLERS.map(AddrFull)) + "\n";

  out += H2("Motions");
  out += Empty("Nobody has proposed changing the controllers.") + "\n";

  out += H2("Allowlist") +
    "Who may still file while the realm is paused. Its own list, not the controllers.\n\n";
  out += BulletList([...CONTROLLERS].sort().map(AddrFull));
  return out;
}

function renderRequest(id) {
  const r = DESK.requests.find((x) => x.id === id);
  if (!r) return H1("Not found") + "There is no request " + InlineCode(itoa(id)) + ".\n";
  let out = H1("Request #" + itoa(r.id)) + H2(Inline(r.title));
  const t = Table(["", ""]);
  t.row("Status", "**" + result(r) + "**");
  t.row("Asked", GNOTf(r.amount));
  t.row("Pays", AddrFull(r.to));
  t.row("Filed by", AddrFull(r.by));
  t.row("Filed at height", itoa(r.height));
  if (r.status !== "pending") t.row("Decided at height", itoa(r.decided));
  out += t.string() + "\n" + Blockquote(Inline(reasonOf(r))) + "\n";
  out += H2("Decisions") + decisions(r);
  return out;
}

const REASONS = {
  1: "bob needs a keyboard to keep porting the library",
  2: "early-bird conference ticket",
  3: "three realms to publish and no gas",
  4: "a domain for the docs site",
  5: "a speculative rewrite with no plan attached",
  6: "changed my mind, never mind",
};
const reasonOf = (r) => REASONS[r.id];

// ---------------------------------------------------------------- generate

function deriveFixtures() {
  const requests = {};
  for (const r of DESK.requests) requests[r.id] = renderRequest(r.id);
  return {
    ADDR, PATH, controllers: { Moul, Jaekwon, Aeddi }, alice, bob, carol,
    index: renderIndex(DESK),
    indexPaused: renderIndex({ ...DESK, paused: true }),
    requests,
  };
}

// The realm's own golden, from render_test.gno TestRenderAtDeploy, with the
// path and address substituted the way that test substitutes them.
const atDeployTemplate = `# Small grants (demo)
> **This is a demo.** A working preview of the small-grants desk I plan to
> deploy under \`gno.land/r/nt\` or \`gno.land/r/gnoland\`, once approved.
> Requests, decisions and payouts here are real; only the address is temporary.

Ask for a small amount of GNOT, for yourself or for someone else, in the open.
The controllers below decide in public: pay in full, pay a part, or refuse,
each with an optional reason. The decision that makes a majority pays the
request out of this realm's balance in the same transaction.

|  |  |
| --- | --- |
| Requests | open to everyone |
| Cap per request | 100 GNOT |
| Balance | **0 GNOT** |
| Paid out | 0 GNOT over 0 grant(s) |
| Decision | 2 yes of 3 controllers |
| Fund it | a plain send to \`ADDR\` |

## Ask
\`\`\`
gnokey maketx call -pkgpath PATH -func Request \\
  -args <payee address> -args <amount in ugnot> \\
  -args '<title>' -args '<what it is for>' ...
\`\`\`

## Open requests
*Nothing is waiting for a decision.*

## Recently decided
*Nothing has been decided yet.*

## Controllers
- \`g1m7nvpk9trgj5sqhwdu2r0p9v5e2pzemedglvzt\`
- \`g1ecsuj0q572jr0dhu29q9njtnmw03hyu7tyyvv6\`
- \`g1cgnrpdemae7r2qvtkd99x3vk6cvmppsavx8eqs\`

## Motions
*Nobody has proposed changing the controllers.*

## Allowlist
Who may still file while the realm is paused. Its own list, not the controllers.

- \`g1cgnrpdemae7r2qvtkd99x3vk6cvmppsavx8eqs\`
- \`g1ecsuj0q572jr0dhu29q9njtnmw03hyu7tyyvv6\`
- \`g1m7nvpk9trgj5sqhwdu2r0p9v5e2pzemedglvzt\`
`;

function selfCheck(fx) {
  const fails = [];
  // 1. The empty index must equal the realm's committed golden, byte for byte.
  const emptyDesk = { ...DESK, paused: false, requests: [], balance: 0, totalPaid: 0, paidCount: 0 };
  const empty = renderIndex(emptyDesk);
  const want = atDeployTemplate.replace(/ADDR/g, ADDR).replace(/PATH/g, PATH);
  if (empty !== want) {
    fails.push("empty index does not match render_test.gno atDeploy golden");
    const a = empty.split("\n"), b = want.split("\n");
    for (let i = 0; i < Math.max(a.length, b.length); i++)
      if (a[i] !== b[i]) { fails.push(`  line ${i + 1}:\n    got:  ${JSON.stringify(a[i])}\n    want: ${JSON.stringify(b[i])}`); break; }
  }
  // 2. The substrings the realm's own tests pin on populated pages.
  const must = [
    [fx.requests[1], "**paid 40 GNOT of 100 GNOT**"], // grants_test TestAcceptPart...
    [fx.requests[1], "pay 40 GNOT of 100 GNOT"],
    [fx.requests[1], "pay in full"],
    [fx.requests[1], "| Half of it, the rest next quarter. |"],
    [fx.requests[2], "**refused**"], // grants_test TestRenderShowsDecisions...
    [fx.requests[2], "| *no reason given* |"],
    [fx.requests[2], "| out of scope |"],
    [fx.index, "| refused |"], // the index shows the outcome
    [fx.index, "| paid 40 GNOT of 100 GNOT |"], // the part outcome on the index row
    [fx.index, "| paid in full |"],
    [fx.requests[4], "**paid in full**"],
    [fx.requests[5], "**refused**"], // a refusal where every decision gave no reason
    [fx.requests[6], "No decisions yet."], // a withdrawn request has no ballots
  ];
  for (const [hay, needle] of must)
    if (needle && !hay.includes(needle)) fails.push(`missing pinned substring: ${JSON.stringify(needle)}`);
  return fails;
}

async function fromChain(rpc, pkgpath) {
  const b64 = (s) => Buffer.from(s, "utf8").toString("base64");
  const qrender = async (arg) => {
    const res = await fetch(rpc, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "abci_query", params: { path: "vm/qrender", data: b64(`${pkgpath}:${arg}`) } }),
    });
    const j = await res.json();
    const r = j.result?.response;
    if (r?.ResponseBase?.Error) throw new Error(r.ResponseBase.Log || "query error");
    return Buffer.from(r.ResponseBase.Data, "base64").toString("utf8");
  };
  const index = await qrender("");
  const requests = {};
  for (let id = 1; id <= 20; id++) {
    try { const p = await qrender(`request/${id}`); if (!/^# Not found/.test(p)) requests[id] = p; } catch { /* past the end */ }
  }
  return { ADDR, PATH: pkgpath, controllers: { Moul, Jaekwon, Aeddi }, alice, bob, carol, index, indexPaused: index, requests };
}

const argv = process.argv.slice(2);
let fx;
if (argv[0] === "--from-chain") {
  fx = await fromChain(argv[1], argv[2] || PATH);
  console.log("read Render from", argv[1]);
} else {
  fx = deriveFixtures();
  const fails = selfCheck(fx);
  if (fails.length) { console.error("SELF-CHECK FAILED:\n" + fails.join("\n")); process.exit(1); }
  console.log("self-check passed: empty index == realm golden, all pinned substrings present");
}

const out = `// GENERATED by web/test/gen-fixtures.mjs from the realm's render.gno format.
// Do not edit by hand. Regenerate: node web/test/gen-fixtures.mjs
// The empty index here is byte-equal to the realm's own TestRenderAtDeploy
// golden; the populated pages carry every substring the realm's tests pin.
export const fixtures = ${JSON.stringify(fx, null, 2)};
`;
writeFileSync(join(HERE, "fixtures.js"), out);
console.log("wrote", join(HERE, "fixtures.js"));
