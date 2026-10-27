// Small grants: see every request and file a new one.
//
// Two things, and deliberately only two. Reading the desk is for everybody, so
// it needs no wallet and no connection. Filing is the flow this page exists
// for, so it is checked all the way through BEFORE anything is signed: the
// cap, the address, the two text limits, the pause rule, and then the chain
// itself through a simulation. A signature prompt the chain would reject never
// gets opened.
//
// The controller side (accepting, paying a part, refusing) is NOT here. Those
// calls move money and belong to people who already run a signing setup; this
// page shows what they decided and why, and stops there.
//
// # Where the data comes from
//
// The realm exposes no getter for the list, so this reads its public Render
// and lifts the rows out of the markdown, the same way apps/hangman.js does.
// It reads BY COLUMN NAME and BY ROW LABEL, never by position, and anything it
// does not recognise is shown as the realm wrote it rather than dropped. That
// is on purpose: the realm's decision verbs are still being written, so the
// page has to survive a column it has never seen. When the realm grows a
// machine-readable getter, parseIndex and parseRequest are the two functions
// to replace, and nothing else changes.
//
// # Before it is published
//
// `gno.land/r/moul/smallgrants/v0` is not on any chain yet. That is not an error
// screen: it is the state this page spends its first week in, so it renders as
// a deliberate "not published yet" with what it is waiting for, and the ask
// form still validates and still prints the command, it just cannot send.

import { parseEval, NETWORKS } from "../lib/gno.js";
import { command, gasFor } from "../lib/cmd.js";

// The cap, compiled in as a fallback. MaxGrant is a constant in the realm, so
// the page reads the real one with vm/qeval the moment the realm is live and
// only falls back to this before then. 100 GNOT.
export const MAX_GRANT = 100_000_000;

export const UGNOT_PER_GNOT = 1_000_000;

// What the realm bounds, in bytes, because gno's len() counts bytes.
export const MAX_TITLE_BYTES = 80;
export const MAX_REASON_BYTES = 1000;

export const ADDR = /^g1[02-9ac-hj-np-z]{38}$/;

// What vm/qrender answers for a path no chain has. Anything else that goes
// wrong is a chain or network problem and says so instead.
const NOT_PUBLISHED = /package not found|unknown import path|invalid package path/i;

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const bytes = (s) => new TextEncoder().encode(s).length;

// Bidi and zero-width characters, which the realm strips before deciding
// whether a title or a reason says anything. Mirrored here so the page refuses
// the same input the chain would, at the same point.
const INVISIBLE = /[​-‏‪-‮⁦-⁩﻿]/g;
const saysSomething = (s) => s.replace(INVISIBLE, "").trim() !== "";

// ---------------------------------------------------------------- amounts

// gnot renders ugnot the way the realm does: trailing zeros trimmed, unit
// appended. gnot(100_000_000) is "100 GNOT".
export function gnot(ugnot) {
  if (ugnot === null || ugnot === undefined) return "";
  const neg = ugnot < 0 ? "-" : "";
  const n = Math.abs(ugnot);
  const frac = String(n % UGNOT_PER_GNOT).padStart(6, "0").replace(/0+$/, "");
  return `${neg}${Math.floor(n / UGNOT_PER_GNOT)}${frac ? "." + frac : ""} GNOT`;
}

// toUgnot parses what a visitor typed into the amount field, in GNOT. It
// returns null for anything that is not a plain decimal with at most six
// places, including an empty field: "0.0000001" is not a representable
// amount, and rounding it silently is how a form sends something else than
// what it showed.
export function toUgnot(text) {
  const s = String(text).trim().replace(/,/g, "");
  if (!/^\d+(\.\d{1,6})?$/.test(s)) return null;
  const [whole, frac = ""] = s.split(".");
  return Number(whole) * UGNOT_PER_GNOT + Number(frac.padEnd(6, "0"));
}

// fromMarkdown reads an amount out of a rendered cell, which the realm writes
// with num.GNOTf ("100 GNOT") and sometimes wraps in bold or backticks. A raw
// ugnot figure is accepted too, so a realm that changes its mind still parses.
export function fromMarkdown(cell) {
  const s = plain(cell);
  let m = s.match(/(-?[\d,]+(?:\.\d+)?)\s*GNOT\b/i);
  if (m) {
    const v = toUgnot(m[1]);
    return v === null ? null : v;
  }
  m = s.match(/(-?\d+)\s*ugnot\b/i);
  return m ? Number(m[1]) : null;
}

// ---------------------------------------------------------------- markdown

// plain turns one rendered markdown cell back into text: the realm escaped it
// on the way out (ui.Cell, ui.Inline), so the backslashes come off, the
// backticks and the emphasis markers come off, and a link keeps its title.
//
// One left-to-right pass, not two: unescaping first and then dropping markers
// eats the asterisk in "1 \* 2", which is a character the filer typed, and
// dropping markers first leaves the backslashes behind.
export function plain(cell) {
  return String(cell ?? "")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~])|[`*_]/g, (_, escaped) => escaped ?? "")
    .trim();
}

// section returns the body under `## <heading>`, up to the next heading of the
// same level or above. Matching is case-insensitive and ignores anything after
// the words, so "## Open requests" and "## Open requests (3)" are the same
// section.
export function section(md, heading) {
  const lines = String(md).split("\n");
  const want = heading.toLowerCase();
  let out = null;
  for (const line of lines) {
    const h = line.match(/^(#{1,6})\s+(.*)$/);
    if (h) {
      const starts = h[2].toLowerCase().startsWith(want);
      if (out !== null && !starts) break;
      if (starts) out = [];
      continue;
    }
    if (out !== null) out.push(line);
  }
  return out === null ? null : out.join("\n");
}

const cells = (line) => line.replace(/^\s*\|/, "").replace(/\|\s*$/, "").split(/(?<!\\)\|/).map((c) => c.trim());

// table reads the first GFM table in a block as objects keyed by the header
// cell, lowercased. Reading by name is what lets the realm reorder, rename or
// add a column without breaking this page.
export function table(block) {
  const lines = String(block ?? "").split("\n");
  const start = lines.findIndex((l, i) => /^\s*\|/.test(l) && /^\s*\|[\s:|-]+\|?\s*$/.test(lines[i + 1] || ""));
  if (start < 0) return [];
  const keys = cells(lines[start]).map((k) => plain(k).toLowerCase());
  const rows = [];
  for (let i = start + 2; i < lines.length && /^\s*\|/.test(lines[i]); i++) {
    const vals = cells(lines[i]);
    const row = { _cells: vals };
    keys.forEach((k, j) => (row[k] = vals[j] ?? ""));
    rows.push(row);
  }
  return rows;
}

// labels reads a two-column key/value table (the realm's ui.NewTable("", ""))
// into a map keyed by the lowercased label, keeping the order so an unknown
// label can still be shown where the realm put it.
export function labels(block) {
  const lines = String(block ?? "").split("\n");
  const out = [];
  for (const line of lines) {
    if (!/^\s*\|/.test(line)) continue;
    const c = cells(line);
    if (c.length < 2 || /^[\s:|-]*$/.test(c[0] + c[1])) continue;
    const key = plain(c[0]).toLowerCase();
    if (!key) continue;
    out.push({ key, label: plain(c[0]), value: c[1] });
  }
  return out;
}

const pick = (rows, ...keys) => rows.find((r) => keys.includes(r.key))?.value ?? "";

// ---------------------------------------------------------------- the list

// STATES maps whatever word the realm uses for a status onto the five this
// page knows how to draw. An unknown word keeps itself, and draws neutrally.
const STATES = {
  pending: "pending", open: "pending",
  paid: "paid", sent: "paid", accepted: "paid",
  rejected: "refused", refused: "refused", denied: "refused",
  withdrawn: "withdrawn",
};

// normalizeStatus folds the realm's outcome wording into one of the five the
// page draws. The realm does not write a bare "paid": it writes the payout in
// the same breath, "paid in full" or "paid 40 GNOT of 100 GNOT" (render.gno
// result()), so anything that starts with "paid" is the paid state. A word the
// page has never seen keeps itself and draws neutrally.
export const normalizeStatus = (s) => {
  const w = plain(s).toLowerCase();
  if (w.startsWith("paid")) return "paid";
  return STATES[w] || w;
};

// parseIndex lifts the desk out of the realm's index page: the summary rows,
// the open requests and the decided ones. Every field is optional, because the
// page has to render whatever the realm actually returned.
export function parseIndex(md) {
  // The summary is the labelled table in the preamble, before the first `##`.
  const sum = labels(String(md).split(/^##\s/m)[0]);
  const byId = new Map();
  const add = (row, decided) => {
    const id = Number(plain(row["#"] || row.id || "").replace(/^#/, ""));
    if (!Number.isInteger(id) || id <= 0) return;
    const asked = fromMarkdown(row.amount ?? row.asked ?? "");
    const outcome = plain(row.outcome ?? row.status ?? "");
    // The decided table names the outcome in words and carries no Paid column:
    // "paid 40 GNOT of 100 GNOT", or "paid in full". Lift the amount out of the
    // words so a part-paid row reads right from the index alone, before its own
    // page has been opened. A realm that later adds a Paid column still wins.
    let paid = row.paid !== undefined ? fromMarkdown(row.paid) : null;
    if (paid === null && /paid/i.test(outcome)) {
      const m = outcome.match(/paid\s+(.+?)\s+of\s+/i);
      paid = m ? fromMarkdown(m[1]) : /paid in full/i.test(outcome) ? asked : null;
    }
    byId.set(id, {
      id,
      title: plain(row.title ?? ""),
      to: plain(row.to ?? row.pays ?? ""),
      asked,
      paid,
      yes: plain(row.yes ?? ""),
      status: decided ? normalizeStatus(outcome) || "decided" : "pending",
      outcomeRaw: outcome,
    });
  };
  for (const r of table(section(md, "Open requests"))) add(r, false);
  for (const r of table(section(md, "Recently decided"))) add(r, true);

  return {
    requests: [...byId.values()].sort((a, b) => b.id - a.id),
    paused: /\bpaused\b/i.test(pick(sum, "requests", "state")),
    balance: fromMarkdown(pick(sum, "balance")),
    cap: fromMarkdown(pick(sum, "cap per request", "cap")),
    paidOut: fromMarkdown(pick(sum, "paid out")),
    decision: plain(pick(sum, "decision")),
    fundTo: (plain(pick(sum, "fund it")).match(/g1[0-9a-z]{38}/) || [""])[0],
  };
}

// parseRequest lifts one request's own page: the labelled rows, the reason the
// filer wrote, and the controllers' decisions. `extra` keeps every label this
// page has no opinion about, so a field the realm adds tomorrow still reaches
// the reader.
export function parseRequest(md) {
  // Labels come from the body only: the Decisions table below has its own
  // headers (Controller | Decision | Height | Reason), which would otherwise
  // land in `extra` as if they were fields.
  const body = String(md).split(/^##\s+Decisions/m)[0] || String(md);
  const rows = labels(body);
  const known = new Set(["status", "amount", "asked", "paid", "pays", "to", "filed by", "by",
    "filed at height", "decided at height", "reason", "decision", "outcome"]);
  const quote = (body.match(/^>\s?(.*(?:\n>.*)*)/m) || [, ""])[1].replace(/\n>\s?/g, "\n").trim();
  const asked = fromMarkdown(pick(rows, "amount", "asked"));
  const statusRaw = pick(rows, "status");
  // The realm folds the payout into the status word ("paid 40 GNOT of 100
  // GNOT") rather than a Paid row, so the amount comes out of there unless the
  // realm later grows a Paid column.
  const paidRow = pick(rows, "paid");
  let paid = paidRow ? fromMarkdown(paidRow) : null;
  if (paid === null && /paid/i.test(plain(statusRaw))) {
    const m = plain(statusRaw).match(/paid\s+(.+?)\s+of\s+/i);
    paid = m ? fromMarkdown(m[1]) : /paid in full/i.test(plain(statusRaw)) ? asked : null;
  }

  // Each row is one controller's decision: pay in full, pay a part, or refuse,
  // with the reason they wrote. An empty reason is rendered by the realm as the
  // italic "no reason given" (render.gno decisions()), which is "none", not a
  // reason that happens to read that way.
  const decisions = table(section(md, "Decisions")).map((d) => ({
    controller: (plain(d.controller ?? d.voter ?? "").match(/g1[0-9a-z]{38}/) || [plain(d.controller ?? d.voter ?? "")])[0],
    decision: plain(d.decision ?? d.vote ?? ""),
    height: plain(d.height ?? ""),
    reason: noReason(d.reason) ? "" : plain(d.reason ?? ""),
  }));

  return {
    title: plain((md.match(/^##\s+(.*)$/m) || [, ""])[1]),
    status: normalizeStatus(statusRaw),
    asked,
    paid,
    to: (plain(pick(rows, "pays", "to")).match(/g1[0-9a-z]{38}/) || [plain(pick(rows, "pays", "to"))])[0],
    by: (plain(pick(rows, "filed by", "by")).match(/g1[0-9a-z]{38}/) || [plain(pick(rows, "filed by", "by"))])[0],
    filedAt: plain(pick(rows, "filed at height")),
    decidedAt: plain(pick(rows, "decided at height")),
    reason: plain(quote),
    // The one sentence the list reads next to the outcome: the first reason a
    // controller actually wrote. Decided with every reason blank is "", which
    // outcomeOf reads as "there is none"; a page that has not been read at all
    // leaves this undefined upstream, which reads as "not known yet".
    decisionReason: decisions.map((d) => d.reason).find(Boolean) ?? "",
    decisions,
    extra: rows.filter((r) => !known.has(r.key)),
  };
}

// noReason is the realm's rendering of a decision with no reason: the italic
// "no reason given" cell. Matched on the raw cell, before plain() strips the
// markers, so a reason a controller literally typed is never mistaken for it.
const noReason = (cell) => /^\*\s*no reason given\s*\*$/.test(String(cell ?? "").trim());

// outcomeOf is the sentence a decided request reads as. It is the part of this
// page that had to be got right.
//
// A refusal with no reason is a decision somebody took, not a field somebody
// forgot, so it says so in full and is not greyed out like missing data. The
// matching trap is the opposite one: the index does not carry reasons, so
// before the request's own page has been read the page knows NOTHING about a
// reason, and must not claim none was given. `decisionReason` undefined is
// "not read yet" and stays silent; the empty string is "read, and there is
// none" and says so.
export function outcomeOf(r) {
  const known = r.decisionReason !== undefined;
  const reason = String(r.decisionReason ?? "").trim();
  const said = reason ? ` “${reason}”` : known ? " No reason was given, and the realm does not ask for one." : "";
  switch (r.status) {
    case "pending":
      return { label: "Waiting for a decision", tone: "open", detail: r.yes ? `${r.yes} yes so far` : "" };
    case "paid": {
      const part = r.paid !== null && r.paid !== undefined && r.asked !== null && r.paid < r.asked;
      return {
        label: part ? "Paid in part" : "Paid in full",
        tone: "paid",
        detail: part ? `${gnot(r.paid)} of the ${gnot(r.asked)} asked.${said}` : `${gnot(r.paid ?? r.asked)}.${said}`,
      };
    }
    case "refused":
      return { label: "Refused", tone: "refused", detail: said.trim() };
    case "withdrawn":
      return { label: "Withdrawn by whoever filed it", tone: "open", detail: "Nothing was paid." };
    default:
      return { label: r.outcomeRaw || r.status || "unknown", tone: "open", detail: said.trim() };
  }
}

// ---------------------------------------------------------------- the ask

// askArgs is the four arguments `Request` takes, in order, as the strings a
// transaction and a gnokey command both carry.
export const askArgs = ({ to, ugnot, title, reason }) => [to, String(ugnot), title, reason];

// validate applies every rule the realm applies, before anything is signed.
// Each problem names the field, so the form can point at it, and the order is
// the order a reader scans the form in.
//
// It is deliberately a pure function with no chain in it: the three facts it
// needs from the chain (the cap, the realm's own address, whether filing is
// paused for this caller) are passed in, and default to the safe reading when
// the chain has not answered.
export function validate({ to, amount, title, reason }, { cap = MAX_GRANT, realmAddress = "", paused = false, mayFile = true } = {}) {
  const problems = [];
  const t = String(title ?? "").trim();
  const r = String(reason ?? "").trim();
  const dst = String(to ?? "").trim();
  const ugnot = toUgnot(amount);

  if (!dst) problems.push({ field: "to", message: "Who gets paid? Give the payee's address." });
  else if (!ADDR.test(dst)) problems.push({ field: "to", message: `${dst} is not a gno address: they start with g1 and are 40 characters.` });
  else if (realmAddress && dst === realmAddress) problems.push({ field: "to", message: "That is the realm's own address. It cannot pay itself." });

  if (String(amount ?? "").trim() === "") problems.push({ field: "amount", message: "How much? In GNOT." });
  else if (ugnot === null) problems.push({ field: "amount", message: `“${amount}” is not an amount in GNOT. Up to six decimals, no unit.` });
  else if (ugnot <= 0) problems.push({ field: "amount", message: "Ask for more than nothing." });
  else if (ugnot > cap) problems.push({ field: "amount", message: `${gnot(ugnot)} is over the cap. This desk pays at most ${gnot(cap)} per request, and no call can raise it.` });

  if (!saysSomething(t)) problems.push({ field: "title", message: "Give it a title: one line, what the money is for." });
  else if (bytes(t) > MAX_TITLE_BYTES) problems.push({ field: "title", message: `The title is ${bytes(t)} bytes, and ${MAX_TITLE_BYTES} is the most the realm stores.` });

  if (!saysSomething(r)) problems.push({ field: "reason", message: "Say what it is for. This is what the controllers read." });
  else if (bytes(r) > MAX_REASON_BYTES) problems.push({ field: "reason", message: `The reason is ${bytes(r)} bytes, and ${MAX_REASON_BYTES} is the most the realm stores.` });

  if (paused && !mayFile) problems.push({ field: "", message: "The desk is paused: only the addresses on its allowlist may file right now. Everything already filed keeps running." });

  return { ok: problems.length === 0, problems, ugnot, args: ugnot === null ? null : askArgs({ to: dst, ugnot, title: t, reason: r }) };
}

// ---------------------------------------------------------------- the page

const REPO = "https://github.com/moul/gno-contracts/tree/main/r/moul/smallgrants";

// What a simulation was run against. A green check is only ever shown next to
// the arguments it was measured for: a check that survives an edit is worse
// than no check at all.
const fingerprint = (args) => args.join("\u0000");

export function mount(el, ctx) {
  const { client, net, path, call, wallet } = ctx;
  const cfg = NETWORKS[net];

  // What the page knows. Everything starts at the safe reading: unpublished
  // until the chain says otherwise, capped at the compiled-in constant until
  // the chain gives its own.
  const state = {
    phase: "loading", // loading | live | unpublished | unreachable
    error: "",
    cap: MAX_GRANT,
    capFromChain: false,
    realmAddress: "",
    paused: false,
    balance: null,
    paidOut: null,
    decision: "",
    requests: [],
    open: new Set(), // request ids whose detail is expanded
    detail: new Map(), // id -> parsed detail; only successes, and forever
    loading: new Set(), // id -> its page is in flight
    failed: new Map(), // id -> why its page could not be read, until it is retried
    checked: null, // the last simulation: { for, gasUsed, gasWanted, gasFee, error, skipped }
    mayFile: true, // whether THIS visitor may file; only ever false while paused
    probed: false, // the two on-chain constants have been asked for
  };

  el.innerHTML = `
    <div class="sg">
      <div data-state></div>
      <div data-list></div>
      <section class="sg-ask">
        <h3>Ask for a grant</h3>
        <p class="muted">Anyone may file, for anyone. The account that needs the coins is
          often the one that cannot pay the gas to ask for them, so the payee does not have
          to be you. Filing moves no money.</p>
        <label>Who gets paid<input name="to" placeholder="g1…" autocomplete="off" spellcheck="false"></label>
        <label>How much, in GNOT<input name="amount" placeholder="25" inputmode="decimal" autocomplete="off"></label>
        <label>Title <span class="muted" data-count-title></span><input name="title" placeholder="a line of what it is for" autocomplete="off"></label>
        <label>What it is for <span class="muted" data-count-reason></span><textarea name="reason" rows="4" placeholder="what the controllers will read before deciding"></textarea></label>
        <div data-problems></div>
        <div data-review></div>
        <div class="row">
          <button data-check type="button">Check it against the chain</button>
          <button data-send type="button" class="primary">Sign and send</button>
        </div>
        <p class="muted" data-sent></p>
        <details data-gnokey open>
          <summary>Send it with gnokey instead</summary>
          <p class="muted">A browser cannot run gnokey, so this is the same call as a command to
            paste. It stays correct as you edit the form above.</p>
          <pre data-cmd></pre>
          <div class="row">
            <input name="key" placeholder="your gnokey key name" autocomplete="off" spellcheck="false">
            <button data-copy type="button">Copy</button>
          </div>
        </details>
      </section>
    </div>`;

  const $ = (s) => el.querySelector(s);
  const val = (name) => ($(`[name="${name}"]`)?.value ?? "").toString();
  const form = () => ({ to: val("to"), amount: val("amount"), title: val("title"), reason: val("reason") });

  // -------------------------------------------------- draw

  const drawState = () => {
    const node = $("[data-state]");
    if (state.phase === "loading") {
      node.innerHTML = `<p class="muted">reading ${esc(path)} on ${esc(net)}…</p>`;
      return;
    }
    if (state.phase === "unreachable") {
      node.innerHTML = `<div class="sg-banner bad"><strong>Cannot reach ${esc(net)}.</strong>
        <p>${esc(state.error)}</p>
        <p class="muted">This is the network, not the realm. Try again, or pick another network in the header.</p></div>`;
      return;
    }
    if (state.phase === "unpublished") {
      node.innerHTML = `<div class="sg-banner waiting">
        <strong>Not published yet.</strong>
        <p>There is no <code>${esc(path)}</code> on <b>${esc(net)}</b>, so there is nothing to list.
          That is the expected state today, not a failure: the realm is written and reviewed,
          and it is waiting to be deployed.</p>
        <p>Everything below is live the moment it is. Until then the form still checks what you
          type against the realm's rules, and still prints the command that will file it.</p>
        <p class="muted">Waiting on: the realm deployed to ${esc(net)} ·
          <a href="${REPO}" target="_blank" rel="noopener">read the realm ↗</a></p>
      </div>`;
      return;
    }
    const pill = (k, v) => (v === null || v === "" ? "" : `<div><span class="muted">${esc(k)}</span><b>${esc(v)}</b></div>`);
    node.innerHTML = `
      <div class="sg-banner ${state.paused ? "waiting" : "ok"}">
        <strong>${state.paused ? "Paused: new requests from the allowlist only" : "Open: anyone may file"}</strong>
        <div class="sg-stats">
          ${pill("balance", state.balance === null ? null : gnot(state.balance))}
          ${pill("cap per request", gnot(state.cap))}
          ${pill("paid out", state.paidOut === null ? null : gnot(state.paidOut))}
          ${pill("decision", state.decision)}
        </div>
      </div>`;
  };

  const drawList = () => {
    const node = $("[data-list]");
    if (state.phase === "unreachable") return void (node.innerHTML = "");
    if (state.phase === "unpublished") {
      node.innerHTML = `<h3>Requests</h3>
        <p class="sg-none">None. The desk has not opened, so nobody has asked for anything.
          The first request will show here.</p>`;
      return;
    }
    if (state.phase === "loading") return void (node.innerHTML = "");
    if (!state.requests.length) {
      node.innerHTML = `<h3>Requests</h3><p class="sg-none">Nothing has been filed yet.</p>`;
      return;
    }
    node.innerHTML = `<h3>Requests <span class="muted">${state.requests.length}</span></h3>
      <ul class="sg-rows">${state.requests.map(rowHTML).join("")}</ul>`;
    node.querySelectorAll?.("[data-id]").forEach((b) => b.addEventListener("click", () => toggle(Number(b.dataset.id))));
  };

  const rowHTML = (r) => {
    const o = outcomeOf(r);
    return `<li class="sg-row ${o.tone}">
      <button data-id="${r.id}" class="sg-head" aria-expanded="${state.open.has(r.id)}">
        <span class="sg-id">#${r.id}</span>
        <span class="sg-title">${esc(r.title || "(no title)")}</span>
        <span class="sg-amount">${esc(r.asked === null ? "" : gnot(r.asked))}</span>
        <span class="sg-state">${esc(o.label)}</span>
      </button>
      ${o.detail ? `<p class="sg-outcome">${esc(o.detail)}</p>` : ""}
      ${state.open.has(r.id) ? `<div class="sg-detail">${detailHTML(r)}</div>` : ""}
    </li>`;
  };

  const detailHTML = (r) => {
    if (state.failed.has(r.id)) return `<p class="err">could not read request #${r.id}: ${esc(state.failed.get(r.id))}</p>`;
    const d = state.detail.get(r.id);
    if (!d) return `<p class="muted">reading request #${r.id}…</p>`;
    const row = (k, v) => (v ? `<div><span class="muted">${esc(k)}</span><code>${esc(v)}</code></div>` : "");
    return `
      <div class="sg-kv">
        ${row("pays", d.to)}${row("filed by", d.by)}
        ${row("filed at height", d.filedAt)}${row("decided at height", d.decidedAt)}
        ${d.extra.map((x) => row(x.label, plain(x.value))).join("")}
      </div>
      ${d.reason ? `<blockquote>${esc(d.reason)}</blockquote>` : ""}
      ${d.decisions.length ? `<table class="sg-ballots"><tr><th>controller</th><th>decision</th><th>reason</th></tr>
        ${d.decisions.map((b) => `<tr><td><code>${esc(b.controller)}</code></td><td>${esc(b.decision)}</td><td>${esc(b.reason || "—")}</td></tr>`).join("")}</table>` : ""}
      <p class="muted"><a href="${esc(cfg?.web || "https://gno.land")}${esc(path.replace(/^gno\.land/, ""))}:request/${r.id}" target="_blank" rel="noopener">on gnoweb ↗</a></p>`;
  };

  // drawAsk is the whole submit flow: it runs on every keystroke, so what the
  // page says you are about to send is never behind what you typed. A
  // simulation is thrown away the moment the form changes, because a green
  // check against different arguments is worse than no check at all.
  const drawAsk = () => {
    const f = form();
    const v = validate(f, { cap: state.cap, realmAddress: state.realmAddress, paused: state.paused, mayFile: state.mayFile !== false });
    const touched = Object.values(f).some((x) => x.trim() !== "");
    const id = wallet.current?.();

    $("[data-count-title]").textContent = `${bytes(f.title.trim())}/${MAX_TITLE_BYTES} bytes`;
    $("[data-count-reason]").textContent = `${bytes(f.reason.trim())}/${MAX_REASON_BYTES} bytes`;

    $("[data-problems]").innerHTML = touched && v.problems.length
      ? `<ul class="sg-problems">${v.problems.map((p) => `<li>${esc(p.message)}</li>`).join("")}</ul>`
      : "";

    $("[data-review]").innerHTML = v.ok ? reviewHTML(v, f) : "";

    const sim = state.checked;
    const blocked = !v.ok || state.phase !== "live" || !id || (sim && sim.for === fingerprint(v.args) && sim.error);
    const send = $("[data-send]");
    send.disabled = Boolean(blocked);
    send.title = !touched ? "fill the form first"
      : !v.ok ? "fix what is listed above first"
        : state.phase !== "live" ? `nothing to call: ${path} is not on ${net} yet`
          : !id ? "connect an address in the header first"
            : sim?.error ? "the chain would refuse this call" : "";
    $("[data-check]").disabled = !v.ok || state.phase !== "live" || !id;

    $("[data-cmd]").textContent = v.ok && cfg
      ? command({
        net, cfg, pkgPath: path, func: "Request", args: v.args, send: "",
        key: val("key").trim(), gasHint: 'press "Check it against the chain"',
        ...(sim && sim.for === fingerprint(v.args) && sim.gasWanted ? sim : {}),
      })
      : "# fill the form above and the exact command appears here";
  };

  const reviewHTML = (v, f) => {
    const sim = state.checked;
    const fresh = sim && sim.for === fingerprint(v.args);
    return `<div class="sg-review">
      <strong>What you are about to send</strong>
      <ul>
        <li>a call to <code>Request</code> on <code>${esc(path)}</code>, on <b>${esc(net)}</b></li>
        <li>asking for <b>${esc(gnot(v.ugnot))}</b>, to be paid to <code>${esc(f.to.trim())}</code></li>
        <li>titled “${esc(f.title.trim())}”, with your reason stored on chain and public forever</li>
      </ul>
      <p><b>It sends no coins.</b> Filing only records the ask; the money moves later, if and when the
        controllers decide to pay it. What you pay today is the gas for this one call.</p>
      ${fresh && sim.error
        ? `<p class="sg-refuse"><b>The chain would refuse this.</b> ${esc(sim.error)}</p>`
        : fresh && sim.gasWanted
          ? `<p class="sg-accept"><b>The chain accepts this call.</b> Simulated on ${esc(net)}:
             ${sim.gasUsed.toLocaleString()} gas used, so the command below asks for
             ${sim.gasWanted.toLocaleString()} and a fee of ${esc(gnot(sim.gasFee))}.
             ${sim.data ? `It would return <code>${esc(sim.data)}</code>, the new request's number.` : ""}</p>`
          : fresh && sim.skipped
            ? `<p class="muted">${esc(sim.skipped)}</p>`
            : `<p class="muted">Not checked against the chain yet. Adena shows you the fee before you sign either way.</p>`}
    </div>`;
  };

  const draw = () => { drawState(); drawList(); drawAsk(); };

  // -------------------------------------------------- chain

  const read = async () => {
    try {
      const md = await client.render(path, "");
      const idx = parseIndex(md);
      state.phase = "live";
      state.requests = idx.requests;
      state.paused = idx.paused;
      state.balance = idx.balance;
      state.paidOut = idx.paidOut;
      state.decision = idx.decision;
      // The index cap and the "Fund it" address are a FALLBACK, used only until
      // vm/qeval answers. MaxGrant and Address() are constants the realm holds,
      // and reading them directly is the authority; scraping a markdown cell is
      // not. So neither is latched here: once capFromChain is set by readCap the
      // index never overwrites it, and the same for a qeval address.
      if (idx.cap !== null && !state.capFromChain) state.cap = idx.cap;
      if (idx.fundTo && !state.realmAddress) state.realmAddress = idx.fundTo;
      applyDetails();
      // A decided request's reason lives on its own page, and the list is
      // supposed to carry it. The realm bounds the decided table (RecentDecided),
      // so this is a handful of reads once, never per refresh: a decision is
      // final, so its page is cached the first time it is read.
      for (const r of state.requests) if (r.status !== "pending") loadDetail(r.id);
      await readPauseRule();
      // Asked once the realm answers at all, so an unpublished path costs no
      // failing queries, and a realm that goes live while the page is open
      // still gets its authoritative cap. Both are constants on chain, so
      // asking once is asking enough, and the answer overrides the index above.
      if (!state.probed) {
        state.probed = true;
        readCap();
        readAddress();
      }
    } catch (e) {
      state.error = e.message || String(e);
      state.phase = NOT_PUBLISHED.test(state.error) ? "unpublished" : "unreachable";
    }
    draw();
  };

  // Whether THIS visitor may file right now. Only matters while the desk is
  // paused, and only answerable for a connected address.
  const readPauseRule = async () => {
    const id = wallet.current?.();
    if (!state.paused || !id) { state.mayFile = true; return; }
    try {
      state.mayFile = parseEval(await client.eval(path, `IsAllowed(${JSON.stringify(id.address)})`)) === true;
    } catch {
      state.mayFile = true; // unknown is not a reason to block a signature
    }
  };

  // The cap the realm itself holds. MaxGrant is a constant, which vm/qeval
  // reads, so this is the authority whenever it answers; the index table is
  // the fallback and the compiled-in value the fallback's fallback.
  const readCap = async () => {
    try {
      const v = parseEval(await client.eval(path, "MaxGrant"));
      if (Number.isFinite(v) && v > 0) { state.cap = v; state.capFromChain = true; draw(); }
    } catch { /* the index table already gave a cap, or the realm is not there */ }
  };

  // The realm's own address, so the form can refuse a request that pays it.
  // vm/qeval answers an address as `("g1…" .uverse.address)`, which parseEval
  // hands back with its quotes still on, so this reads the value out directly.
  const readAddress = async () => {
    try {
      const m = String(await client.eval(path, "Address()")).match(/g1[02-9ac-hj-np-z]{38}/);
      if (m) { state.realmAddress = m[0]; draw(); }
    } catch { /* same */ }
  };

  // loadDetail reads one request's own page. A decided request never changes,
  // so a success is cached for the life of the page; a failure is not, so the
  // next refresh tries again instead of leaving a permanent gap.
  const loadDetail = async (id) => {
    if (state.detail.has(id) || state.loading.has(id)) return;
    state.loading.add(id);
    state.failed.delete(id);
    drawList();
    try {
      state.detail.set(id, parseRequest(await client.render(path, `request/${id}`)));
      applyDetails();
    } catch (e) {
      state.failed.set(id, e.message);
    }
    state.loading.delete(id);
    drawList();
  };

  // applyDetails copies onto each row what only its own page carries: the
  // reason behind the decision, and the amount actually paid when the index
  // does not name it. Until a row has been through this its decisionReason is
  // undefined, which outcomeOf reads as "not known" rather than "none given".
  const applyDetails = () => {
    for (const r of state.requests) {
      const d = state.detail.get(r.id);
      if (!d) continue;
      r.decisionReason = d.decisionReason;
      if (r.paid === null && d.paid !== null) r.paid = d.paid;
    }
  };

  const toggle = async (id) => {
    if (state.open.has(id)) { state.open.delete(id); return drawList(); }
    state.open.add(id);
    drawList();
    await loadDetail(id);
  };

  // -------------------------------------------------- actions

  // check simulates the call as the connected address. A panic here is the
  // thing this page exists to catch: it is every rule the realm has, including
  // the ones this page cannot know, answered before anyone signs.
  const check = async () => {
    const v = validate(form(), { cap: state.cap, realmAddress: state.realmAddress, paused: state.paused, mayFile: state.mayFile !== false });
    if (!v.ok) return;
    const id = wallet.current?.();
    if (!id) return;
    state.checked = { for: fingerprint(v.args), skipped: "simulating…" };
    drawAsk();
    try {
      const sim = await client.simulate(id.address, path, "Request", v.args);
      state.checked = sim.error
        ? { for: fingerprint(v.args), error: sim.error }
        : { for: fingerprint(v.args), gasUsed: sim.gasUsed, data: sim.data, ...gasFor(sim.gasUsed) };
    } catch (e) {
      // A simulation that cannot run is not a refusal, and must not read as
      // one: an account that never sent a transaction has no public key on
      // chain, so there is nothing to check against yet.
      state.checked = { for: fingerprint(v.args), skipped: `Could not check it: ${e.message}. That is about your account, not about this request, so signing is still allowed.` };
    }
    drawAsk();
  };

  const send = async () => {
    const v = validate(form(), { cap: state.cap, realmAddress: state.realmAddress, paused: state.paused, mayFile: state.mayFile !== false });
    // The same two conditions the button's disabled state carries, checked
    // again here: "the chain would reject this" is an invariant of the page,
    // not a property of one attribute on one element.
    if (!v.ok || state.phase !== "live") return;
    if (state.checked?.for === fingerprint(v.args) && state.checked.error) return;
    $("[data-sent]").textContent = "waiting for the wallet…";
    try {
      const tx = await call("Request", v.args, {});
      $("[data-sent]").textContent = `${wallet.describe(tx)}${wallet.result?.(tx) ? ` · request ${wallet.result(tx)}` : ""}`;
      read();
    } catch (e) {
      $("[data-sent]").textContent = e.message;
    }
  };

  // -------------------------------------------------- wiring

  for (const name of ["to", "amount", "title", "reason"]) {
    $(`[name="${name}"]`)?.addEventListener("input", () => { state.checked = null; drawAsk(); });
  }
  $(`[name="key"]`)?.addEventListener("input", drawAsk);
  $("[data-check]")?.addEventListener("click", check);
  $("[data-send]")?.addEventListener("click", send);
  $("[data-copy]")?.addEventListener("click", async () => {
    await navigator.clipboard.writeText($("[data-cmd]").textContent.replace(/^# .*\n/, ""));
    $("[data-copy]").textContent = "Copied";
  });

  draw();
  read();
  const timer = setInterval(read, 10000);
  return () => clearInterval(timer);
}
