// A harness that mounts one live app (web/apps/*.js) under node, against a
// scripted chain, with the clock, the poll timer and the RPC answers all in
// the test's hands. No browser, no network: the apps only ever touch the page
// through data-attribute selectors, which a map of stub nodes can answer.

export const ME = "g1manfred47kzduec920z88wfr64ylksmdcedlf5";
export const STRANGER = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5";
export const short = (a) => `${a.slice(0, 8)}…${a.slice(-4)}`;

// The clock the queue reads. Tests move it forward to make an entry expire.
export const clock = { now: 1_000_000 };
Date.now = () => clock.now;

const tick = () => new Promise((r) => setImmediate(r));

function node() {
  const n = {
    _text: "", _html: "", classes: new Set(), disabled: false, dataset: {}, style: {},
    children: [], listeners: {}, elements: {},
    get textContent() { return this._text; },
    set textContent(v) { this._text = String(v); this._html = String(v); },
    get innerHTML() { return this._html; },
    set innerHTML(v) { this._html = String(v); this._text = String(v).replace(/<[^>]*>/g, ""); },
    classList: {
      toggle: (c, on) => (on ? n.classes.add(c) : n.classes.delete(c)),
      contains: (c) => n.classes.has(c),
    },
    addEventListener(ev, fn) { (this.listeners[ev] ||= []).push(fn); },
    querySelector(s) { return (this._sub ||= {})[s] ||= node(); },
    querySelectorAll(s) { return (this._all ||= {})[s] || []; },
    fire(ev, arg = { preventDefault() {} }) { return Promise.all((this.listeners[ev] || []).map((f) => f(arg))); },
  };
  return n;
}

function makeEl() {
  const nodes = {};
  const all = {};
  return {
    set innerHTML(_) {},
    querySelector: (s) => (nodes[s] ||= node()),
    querySelectorAll: (s) => all[s] || [],
    all,
    node: (s) => (nodes[s] ||= node()),
  };
}

// mount boots one app. answer(kind, expr) is the chain: it is called when a
// request is MADE, so every answer is a snapshot of the chain at that moment,
// and it is only delivered when the test flushes. That is what lets a test
// hold an old read in flight while the chain moves on.
export function mount(app, { answer, address = ME, wallet: mode = "gnokey", setup = () => {}, net = "test" }) {
  const el = makeEl();
  setup(el);

  const pending = [];
  const req = (kind, expr) => new Promise((resolve, reject) => {
    let out;
    try { out = answer(kind, expr); } catch (e) { out = e; }
    pending.push(() => (out instanceof Error ? reject(out) : resolve(out)));
  });
  const client = {
    eval: (_, expr) => req("eval", expr),
    render: (_, args) => req("render", args),
    // An app that checks a call before asking anyone to sign it needs this;
    // the chain answers it like any other read, so the test holds it too.
    simulate: (caller, _pkg, func, args) => req("simulate", `${caller} ${func}(${args.join("|")})`),
  };

  const calls = [];
  const adena = [];
  let id = address ? { address, mode } : null;
  const wallet = {
    current: () => id,
    describe: (tx) => (tx.manual ? "sent with gnokey, waiting for the chain" : `included at height ${tx.height}`),
    result: (tx) => tx?.result || "",
  };
  const call = async (func, args = [], opts = {}) => {
    calls.push({ func, args });
    opts.onSubmit?.();
    if (mode === "gnokey") return { manual: true };
    return new Promise((resolve, reject) => adena.push({ resolve, reject }));
  };

  let poll = null;
  const realSetInterval = globalThis.setInterval;
  globalThis.setInterval = (fn) => { poll = fn; return 0; };
  try {
    app.mount(el, { client, net, path: "gno.land/r/test", call, wallet });
  } finally {
    globalThis.setInterval = realSetInterval;
  }

  return {
    el, calls,
    connect: (address) => { id = address ? { address, mode } : null; },
    $: (s) => el.node(s),
    text: (s) => el.node(s).textContent,
    msg: () => el.node("[data-msg]").textContent,
    refresh: () => poll(),
    // flush delivers every answer in the order the requests were made, until
    // nothing is in flight.
    async flush() { await tick(); while (pending.length) { pending.shift()(); await tick(); } await tick(); },
    // step delivers the single oldest answer still in flight.
    async step() { await tick(); pending.shift()(); await tick(); },
    // flushNewestFirst delivers the most recent request first, repeatedly, so
    // a refresh that started later finishes before one that started earlier.
    async flushNewestFirst() { await tick(); while (pending.length) { pending.pop()(); await tick(); } await tick(); },
    // adena settles the oldest wallet popup still open.
    adena: {
      resolve: async (tx) => { adena.shift().resolve(tx); await tick(); },
      reject: async (err) => { adena.shift().reject(err); await tick(); },
    },
  };
}

// --- chains, each answering the way its realm in r/moul/x/daily does ---

export function counterChain() {
  const c = { value: 2, total: 10, history: [], fail: false, height: 100 };
  c.change = (caller, delta) => {
    c.value += delta;
    c.total++;
    c.history.push({ caller, delta, value: c.value, height: c.height++ });
    if (c.history.length > 20) c.history.shift();
  };
  c.answer = (kind, expr) => {
    if (c.fail) throw new Error("test: HTTP 429");
    if (kind === "eval") {
      if (expr === "Value()") return `(${c.value} int)`;
      if (expr === "Total()") return `(${c.total} int)`;
      throw new Error(`unexpected eval ${expr}`);
    }
    let md = "# Counter Club\n\nA shared counter anyone can Inc, Dec, or Reset. The last 20 changes are logged below.\n\n";
    md += `## Current value\n\n# ${c.value}\n\n**Total changes:** ${c.total}\n\n## Recent history\n\n`;
    if (!c.history.length) return md + "_No changes yet._\n";
    md += "| # | Caller | Delta | New value | Height |\n|---|--------|-------|-----------|--------|\n";
    const n = c.history.length;
    for (let i = n - 1; i >= 0; i--) {
      const h = c.history[i];
      md += `| ${n - i} | ${h.caller} | ${h.delta >= 0 ? "+" : ""}${h.delta} | ${h.value} | ${h.height} |\n`;
    }
    return md;
  };
  return c;
}

export function diceChain() {
  const c = { rolls: {}, total: 0, count: [0, 0, 0, 0, 0, 0], fail: false };
  c.roll = (addr, face) => {
    (c.rolls[addr] ||= []).push(face);
    c.total++;
    c.count[face - 1]++;
  };
  c.answer = (kind, expr) => {
    if (c.fail) throw new Error("test: HTTP 429");
    if (expr === "Total()") return `(${c.total} int)`;
    if (expr === "Distribution()") return `([6]int{${c.count.map((n) => `(${n} int)`).join(",")}} [6]int)`;
    const m = expr.match(/^RollsOf\("(g1\w+)"\)$/);
    if (m) { const r = c.rolls[m[1]]; return r ? `(slice[${r.map((v) => `(${v} int)`).join(",")}] []int)` : "(nil []int)"; }
    throw new Error(`unexpected ${kind} ${expr}`);
  };
  return c;
}

export const ANSWERS = ["It is certain.", "Ask again later.", "My reply is no.", "Outlook good.", "Very doubtful."];

export function eightballChain() {
  const c = { history: [], fail: false, height: 500 };
  c.ask = (asker, question) => {
    const answer = ANSWERS[c.history.length % ANSWERS.length];
    c.history.push({ asker, question: question.trim(), answer, height: c.height++ });
    return answer;
  };
  c.answer = (kind, expr) => {
    if (c.fail) throw new Error("test: HTTP 429");
    if (kind === "eval") {
      if (expr === "Asked()") return `(${c.history.length} int)`;
      throw new Error(`unexpected eval ${expr}`);
    }
    let md = "# 🎱 Magic 8-Ball\n\nAsk a yes/no question.\n\n";
    md += `**Questions asked:** ${c.history.length}\n\n`;
    if (!c.history.length) return md + "_No questions yet. Call `Ask(\"will it rain tomorrow?\")`._\n";
    md += `Last shake: 🎱 _${c.history[c.history.length - 1].answer}_\n\n| # | asker | question | answer | height |\n|---|---|---|---|---|\n`;
    const start = c.history.length - 1;
    const end = Math.max(0, start - 14);
    for (let i = start; i >= end; i--) {
      const e = c.history[i];
      md += `| ${i + 1} | \`${short(e.asker)}\` | ${e.question} | ${e.answer} | ${e.height} |\n`;
    }
    return md;
  };
  return c;
}

export function hangmanChain() {
  const c = { word: "gnoland", guessed: new Set(), fail: false };
  c.guess = (letter) => c.guessed.add(letter);
  c.answer = (kind) => {
    if (c.fail) throw new Error("test: HTTP 429");
    if (kind !== "render") throw new Error("hangman has no getter");
    const letters = [...c.guessed].sort().join(" ") || "_(none yet)_";
    const masked = [...c.word].map((ch) => (c.guessed.has(ch) ? ch : "_")).join(" ");
    return "# 🪢 Hangman\n\nDay: `1` · Block: `10`\n\n```\n  +---+\n=========\n```\n\n" +
      `## Word\n\n\`${masked}\`\n\nWrong: **0 / 6**  ·  Lives left: **6**\n\nGuessed letters: ${letters}\n\n` +
      "## Status\n\nGame in progress. Call `Guess(\"a\")` with a letter.\n\n";
  };
  return c;
}

// grantsChain answers the way r/moul/smallgrants renders: a labelled summary
// in the preamble, an open table, a decided table, and a page per request. It
// can also answer like a chain that has never heard of the realm, which is the
// state the page spends its first week in.
export function grantsChain() {
  const c = {
    published: true, paused: false, balance: 250_000_000, cap: 100_000_000, paidOut: 40_000_000,
    realm: "g1grantsdeskxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    requests: [
      { id: 1, title: "A keyboard", to: STRANGER, asked: 100_000_000, paid: 40_000_000, status: "paid", by: ME, reason: "Mine died.", note: "Half of it, the rest next quarter." },
      { id: 2, title: "Conference ticket", to: ME, asked: 60_000_000, status: "rejected", by: ME, reason: "GnoCon, early bird.", note: "" },
      { id: 3, title: "Deploy gas", to: ME, asked: 5_000_000, status: "pending", by: ME, reason: "Three realms to publish.", yes: 1 },
      { id: 4, title: "Paid whole", to: STRANGER, asked: 20_000_000, paid: 20_000_000, status: "paid", by: ME, reason: "A domain.", note: "Fine." },
    ],
    sim: { gasUsed: 1_234_567, data: "(5 int)" },
  };
  const gnot = (u) => `${(u / 1e6).toFixed(6).replace(/\.?0+$/, "")} GNOT`;
  const notFound = () => { throw new Error("package not found: gno.land/r/moul/smallgrants"); };

  c.answer = (kind, expr) => {
    if (!c.published) notFound();
    if (c.fail) throw new Error("test: HTTP 429");
    if (kind === "eval") {
      if (expr === "MaxGrant") return `(${c.cap} int64)`;
      if (expr === "Address()") return `("${c.realm}" .uverse.address)`;
      if (expr.startsWith("IsAllowed(")) return `(${expr.includes(ME) ? "true" : "false"} bool)`;
      throw new Error(`unexpected eval ${expr}`);
    }
    if (kind === "simulate") return c.sim.error ? { error: c.sim.error } : { gasUsed: c.sim.gasUsed, data: c.sim.data, events: [], deposits: [] };
    const m = String(expr).match(/^request\/(\d+)$/);
    return m ? c.page(Number(m[1])) : c.index();
  };

  c.index = () => {
    let md = "# Small grants\n\nAsk for a small amount of GNOT, in the open.\n\n";
    md += "|  |  |\n| --- | --- |\n";
    md += `| Requests | ${c.paused ? "**paused**: new requests from the allowlist only" : "open to everyone"} |\n`;
    md += `| Cap per request | ${gnot(c.cap)} |\n| Balance | **${gnot(c.balance)}** |\n`;
    md += `| Paid out | ${gnot(c.paidOut)} over 2 grant(s) |\n| Decision | 2 yes of 3 controllers |\n`;
    md += `| Fund it | a plain send to \`${c.realm}\` |\n\n`;
    md += "## Ask\n\n```\ngnokey maketx call -pkgpath gno.land/r/moul/smallgrants -func Request ...\n```\n\n";

    const open = c.requests.filter((r) => r.status === "pending");
    md += "## Open requests\n";
    md += open.length
      ? "| # | Title | To | Amount | Yes |\n| --- | --- | --- | --- | --- |\n" +
        open.map((r) => `| [#${r.id}](/r/moul/smallgrants:request/${r.id}) | ${r.title} | \`${short(r.to)}\` | ${gnot(r.asked)} | ${r.yes || 0}/2 |\n`).join("")
      : "_Nothing is waiting for a decision._\n";
    md += "\n";

    const done = c.requests.filter((r) => r.status !== "pending").reverse();
    md += "## Recently decided\n";
    md += done.length
      ? "| # | Title | To | Amount | Paid | Outcome |\n| --- | --- | --- | --- | --- | --- |\n" +
        done.map((r) => `| [#${r.id}](/r/moul/smallgrants:request/${r.id}) | ${r.title} | \`${short(r.to)}\` | ${gnot(r.asked)} | ${r.paid ? gnot(r.paid) : ""} | ${r.status} |\n`).join("")
      : "_Nothing has been decided yet._\n";
    return md + "\n## Controllers\n\n- `" + ME + "`\n";
  };

  c.page = (id) => {
    const r = c.requests.find((x) => x.id === id);
    if (!r) return `# Not found\n\nThere is no request \`${id}\`.\n`;
    let md = `# Request #${r.id}\n## ${r.title}\n\n|  |  |\n| --- | --- |\n`;
    md += `| Status | **${r.status}** |\n| Amount | ${gnot(r.asked)} |\n`;
    if (r.paid) md += `| Paid | ${gnot(r.paid)} |\n`;
    md += `| Pays | \`${r.to}\` |\n| Filed by | \`${r.by}\` |\n| Filed at height | 100 |\n`;
    if (r.status !== "pending") md += "| Decided at height | 120 |\n";
    md += `\n> ${r.reason}\n\n## Ballots\n| Controller | Vote | Height | Note |\n| --- | --- | --- | --- |\n`;
    if (r.status !== "pending") md += `| \`${short(ME)}\` | ${r.status === "paid" ? "yes" : "no"} | 120 | ${r.note || ""} |\n`;
    return md;
  };
  return c;
}

// Per-app wiring: how to boot it, how a visitor submits, how the write lands.
export function diceSetup(el) {
  el.node("[data-bars]").children = Array.from({ length: 6 }, () => node());
}

export function keys(el) {
  el.all["[data-c]"] = [..."abcdefghijklmnopqrstuvwxyz"].map((c) => {
    const b = node();
    b.dataset.c = c;
    return b;
  });
}

export function counterButtons(el) {
  const mk = (f, d) => { const b = node(); b.dataset.f = f; b.dataset.d = d; return b; };
  el.all["button[data-f]"] = [mk("Dec", "-1"), mk("Inc", "1")];
}
