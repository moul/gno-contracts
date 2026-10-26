// What the small-grants page has to get right.
//
// Two halves. The pure half checks the rules and the parsers: every reason the
// realm would panic is a reason this page refuses before anything is signed,
// and every shape the realm renders reads back as the right outcome. The
// mounted half checks the three states a visitor actually lands in: not
// published, live, and a chain that cannot be reached.

import { test } from "node:test";
import assert from "node:assert/strict";

import * as app from "../apps/smallgrants.js";
import { command, gasFor, sh } from "../lib/cmd.js";
import { mount, grantsChain, ME, STRANGER } from "./harness.js";

const GNOT = 1_000_000;
const OK = { to: STRANGER, amount: "25", title: "A keyboard", reason: "Mine died." };

// ---------------------------------------------------------------- amounts

test("GNOT in, ugnot out, and nothing in between", () => {
  const cases = [
    ["25", 25 * GNOT], ["0.5", 500_000], ["0.000001", 1], ["100", 100 * GNOT],
    ["1,000", 1000 * GNOT], [" 7 ", 7 * GNOT],
    // Not amounts: a seventh decimal is not representable, and rounding it
    // would send something other than what the form showed.
    ["0.0000001", null], ["", null], ["abc", null], ["-5", null], ["1e6", null], ["5 GNOT", null],
  ];
  for (const [input, want] of cases) assert.equal(app.toUgnot(input), want, `toUgnot(${JSON.stringify(input)})`);
});

test("ugnot renders the way the realm renders it", () => {
  assert.equal(app.gnot(100 * GNOT), "100 GNOT");
  assert.equal(app.gnot(40 * GNOT), "40 GNOT");
  assert.equal(app.gnot(1_234_567), "1.234567 GNOT");
  assert.equal(app.gnot(500_000), "0.5 GNOT");
  assert.equal(app.gnot(0), "0 GNOT");
});

test("an amount reads back out of a rendered cell", () => {
  assert.equal(app.fromMarkdown("**250 GNOT**"), 250 * GNOT);
  assert.equal(app.fromMarkdown("40 GNOT over 2 grant(s)"), 40 * GNOT);
  assert.equal(app.fromMarkdown("`0.5 GNOT`"), 500_000);
  assert.equal(app.fromMarkdown("100000000ugnot"), 100 * GNOT);
  assert.equal(app.fromMarkdown("nothing yet"), null);
});

// ---------------------------------------------------------------- the rules

test("a good request passes", () => {
  const v = app.validate(OK);
  assert.deepEqual(v.problems, []);
  assert.equal(v.ok, true);
  assert.deepEqual(v.args, [STRANGER, String(25 * GNOT), "A keyboard", "Mine died."]);
});

test("every panic the realm would raise is refused first", () => {
  const field = (over, opts) => app.validate({ ...OK, ...over }, opts).problems.map((p) => p.field);

  assert.deepEqual(field({ to: "" }), ["to"]);
  assert.deepEqual(field({ to: "not-an-address" }), ["to"]);
  assert.deepEqual(field({ to: "g1" + "b".repeat(38) }), ["to"], "b is not in the bech32 charset");
  assert.deepEqual(field({ to: ME }, { realmAddress: ME }), ["to"], "the realm cannot pay itself");

  assert.deepEqual(field({ amount: "" }), ["amount"]);
  assert.deepEqual(field({ amount: "0" }), ["amount"]);
  assert.deepEqual(field({ amount: "100.000001" }), ["amount"], "one ugnot over the cap");
  assert.deepEqual(field({ amount: "100" }), [], "exactly the cap is allowed");

  assert.deepEqual(field({ title: "   " }), ["title"]);
  assert.deepEqual(field({ title: "​​" }), ["title"], "invisible characters say nothing");
  assert.deepEqual(field({ title: "x".repeat(81) }), ["title"]);
  assert.deepEqual(field({ title: "é".repeat(41) }), ["title"], "82 bytes, not 41 characters");
  assert.deepEqual(field({ title: "é".repeat(40) }), [], "80 bytes exactly");

  assert.deepEqual(field({ reason: "" }), ["reason"]);
  assert.deepEqual(field({ reason: "x".repeat(1001) }), ["reason"]);
});

test("the cap comes from the chain when the chain gives one", () => {
  assert.equal(app.validate({ ...OK, amount: "150" }).ok, false);
  assert.equal(app.validate({ ...OK, amount: "150" }, { cap: 200 * GNOT }).ok, true);
  assert.match(app.validate({ ...OK, amount: "150" }).problems[0].message, /at most 100 GNOT/);
});

test("paused blocks only an address that may not file", () => {
  assert.equal(app.validate(OK, { paused: true, mayFile: false }).ok, false);
  assert.equal(app.validate(OK, { paused: true, mayFile: true }).ok, true);
  assert.equal(app.validate(OK, { paused: false, mayFile: false }).ok, true);
});

test("several problems are all reported, in form order", () => {
  const v = app.validate({ to: "nope", amount: "999", title: "", reason: "" });
  assert.deepEqual(v.problems.map((p) => p.field), ["to", "amount", "title", "reason"]);
});

// ---------------------------------------------------------------- outcomes

const decided = (over) => app.outcomeOf({ id: 1, status: "paid", asked: 100 * GNOT, paid: 100 * GNOT, decisionReason: "", ...over });

test("paid in full, paid in part, refused, withdrawn", () => {
  assert.equal(decided({ decisionReason: "Fine." }).label, "Paid in full");
  assert.match(decided({ decisionReason: "Fine." }).detail, /100 GNOT\. “Fine\.”/);

  const part = decided({ paid: 40 * GNOT, decisionReason: "Half now." });
  assert.equal(part.label, "Paid in part");
  assert.match(part.detail, /40 GNOT of the 100 GNOT asked/, "the part is named, and so is what was asked");

  assert.equal(decided({ status: "refused" }).label, "Refused");
  assert.equal(decided({ status: "withdrawn" }).label, "Withdrawn by whoever filed it");
  assert.equal(app.outcomeOf({ status: "pending", yes: "1/2" }).label, "Waiting for a decision");
});

// The requirement this page was asked for by name: a refusal with nothing
// written next to it is a decision somebody took, and must not read like a
// field somebody forgot to fill in.
test("a refusal with no reason reads as deliberate", () => {
  const r = decided({ status: "refused" });
  assert.equal(r.label, "Refused");
  assert.equal(r.detail, "No reason was given, and the realm does not ask for one.");
  assert.doesNotMatch(r.detail, /unknown|missing|n\/a|—/i);
});

// The other half of the same requirement. The index carries no reasons, so a
// row the page has not read the page of knows NOTHING about a reason, and must
// not claim there was none: that would be the page inventing a fact.
test("not read yet is not the same as no reason given", () => {
  const notRead = app.outcomeOf({ status: "refused", asked: 1 });
  assert.equal(notRead.detail, "", "silent until the reason has been read");

  const read = app.outcomeOf({ status: "refused", asked: 1, decisionReason: "" });
  assert.match(read.detail, /No reason was given/);

  assert.equal(app.outcomeOf({ status: "paid", asked: 100, paid: 100 }).detail, "0.0001 GNOT.");
  assert.match(app.outcomeOf({ status: "paid", asked: 100, paid: 100, decisionReason: "" }).detail, /No reason was given/);
});

test("an outcome word the page has never seen is shown, not swallowed", () => {
  const o = app.outcomeOf({ status: "escalated", outcomeRaw: "escalated", asked: 1 });
  assert.equal(o.label, "escalated");
});

// ---------------------------------------------------------------- parsing

test("the index parses into the desk", () => {
  const c = grantsChain();
  const idx = app.parseIndex(c.index());
  assert.equal(idx.balance, 250 * GNOT);
  assert.equal(idx.cap, 100 * GNOT);
  assert.equal(idx.paidOut, 40 * GNOT);
  assert.equal(idx.decision, "2 yes of 3 controllers");
  assert.equal(idx.fundTo, c.realm);
  assert.equal(idx.paused, false);
  assert.deepEqual(idx.requests.map((r) => r.id), [4, 3, 2, 1], "newest first");

  const one = idx.requests.find((r) => r.id === 1);
  assert.equal(one.title, "A keyboard");
  assert.equal(one.asked, 100 * GNOT);
  assert.equal(one.paid, 40 * GNOT);
  assert.equal(one.status, "paid");
  assert.equal(idx.requests.find((r) => r.id === 3).status, "pending");
  assert.equal(idx.requests.find((r) => r.id === 2).status, "refused");
});

test("paused is read off the summary, not guessed", () => {
  const c = grantsChain();
  assert.equal(app.parseIndex(c.index()).paused, false);
  c.paused = true;
  assert.equal(app.parseIndex(c.index()).paused, true);
});

test("columns are read by name, so the realm may reorder them", () => {
  const c = grantsChain();
  const shuffled = c.index()
    .replace("| # | Title | To | Amount | Paid | Outcome |", "| Outcome | Amount | Paid | To | Title | # |")
    .replace(/\| (\[#\d+\][^|]*) \| ([^|]*) \| (`[^|]*`) \| ([^|]*) \| ([^|]*) \| ([^|]*) \|/g, "| $6 | $4 | $5 | $3 | $2 | $1 |");
  const idx = app.parseIndex(shuffled);
  const one = idx.requests.find((r) => r.id === 1);
  assert.equal(one.title, "A keyboard");
  assert.equal(one.asked, 100 * GNOT);
  assert.equal(one.status, "paid");
});

test("a request's own page parses, ballots and all", () => {
  const c = grantsChain();
  const d = app.parseRequest(c.page(1));
  assert.equal(d.title, "A keyboard");
  assert.equal(d.status, "paid");
  assert.equal(d.asked, 100 * GNOT);
  assert.equal(d.paid, 40 * GNOT);
  assert.equal(d.to, STRANGER);
  assert.equal(d.by, ME);
  assert.equal(d.reason, "Mine died.");
  assert.equal(d.decisionReason, "Half of it, the rest next quarter.", "a ballot note is the controllers' reason today");
  assert.equal(d.ballots.length, 1);
  assert.deepEqual(d.extra, [], "the ballots table is not mistaken for a field");
});

test("a field the realm adds tomorrow still reaches the reader", () => {
  const md = grantsChain().page(1).replace("| Filed by |", "| Escalated to | `g1whoever` |\n| Filed by |");
  const d = app.parseRequest(md);
  assert.deepEqual(d.extra.map((x) => x.label), ["Escalated to"]);
});

test("markdown the realm escaped comes back as text", () => {
  assert.equal(app.plain("a \\| b"), "a | b");
  assert.equal(app.plain("`g1abc`"), "g1abc");
  assert.equal(app.plain("**paid**"), "paid");
  assert.equal(app.plain("[#7](/r/moul/smallgrants:request/7)"), "#7");
  assert.equal(app.plain("1 \\* 2 \\_ 3"), "1 * 2 _ 3");
});

test("a pipe inside a cell does not open a column", () => {
  const md = "## Open requests\n| # | Title | Amount |\n| --- | --- | --- |\n| [#1](/x) | a \\| b | 5 GNOT |\n";
  const rows = app.table(app.section(md, "Open requests"));
  assert.equal(rows.length, 1);
  assert.equal(app.plain(rows[0].title), "a | b");
  assert.equal(app.fromMarkdown(rows[0].amount), 5 * GNOT);
});

// ---------------------------------------------------------------- the command

test("the gnokey command is the same call, quoted for a shell", () => {
  const v = app.validate({ ...OK, title: "it's a keyboard" });
  const cmd = command({
    net: "mainnet", cfg: { chainId: "gnoland-1", rpc: "https://rpc.gno.land:443" },
    pkgPath: "gno.land/r/moul/smallgrants", func: "Request", args: v.args, send: "",
    key: "mykey", ...gasFor(1_234_567),
  });
  assert.match(cmd, /-pkgpath gno\.land\/r\/moul\/smallgrants/);
  assert.match(cmd, /-func Request/);
  assert.match(cmd, new RegExp(`-args ${STRANGER}`));
  assert.match(cmd, /-args 25000000/);
  assert.match(cmd, /-args 'it'\\''s a keyboard'/, "an apostrophe cannot break out of the quoting");
  assert.match(cmd, /-gas-wanted 1604938 -gas-fee 3210ugnot/, "measured, not guessed");
  assert.match(cmd, /-broadcast -chainid gnoland-1 -remote https:\/\/rpc\.gno\.land:443/);
  assert.doesNotMatch(cmd, /-send /, "filing sends no coins");
  assert.equal(sh("plain"), "plain");
});

test("without a measurement the command says so instead of inventing a number", () => {
  const cmd = command({ net: "mainnet", cfg: { chainId: "gnoland-1", rpc: "x" }, pkgPath: "p", func: "Request", args: [], send: "", key: "" });
  assert.match(cmd, /-gas-wanted <measure it/);
});

// ---------------------------------------------------------------- the page

const boot = (c, opts = {}) => mount(app, { answer: c.answer, ...opts });

test("not published reads as a deliberate state, not an error", async () => {
  const c = grantsChain();
  c.published = false;
  const t = boot(c);
  await t.flush();

  const state = t.text("[data-state]");
  assert.match(state, /Not published yet/);
  assert.match(state, /waiting to be deployed/i);
  assert.match(state, /Waiting on: the realm deployed to test/);
  assert.doesNotMatch(state, /package not found/, "the chain's error text is not what a visitor reads");
  assert.match(t.text("[data-list]"), /The desk has not opened/);

  // The form still works as a preview: it validates, and it still prints the
  // command. What it will not do is send a call to a realm that is not there.
  for (const [k, v] of Object.entries({ to: STRANGER, amount: "25", title: "A keyboard", reason: "Mine died." })) t.$(`[name="${k}"]`).value = v;
  await t.$('[name="reason"]').fire("input");
  assert.deepEqual(t.text("[data-problems]"), "", "the rules still pass");
  assert.match(t.text("[data-review]"), /It sends no coins/);
  assert.equal(t.$("[data-send]").disabled, true);
  assert.match(t.$("[data-send]").title, /is not on test yet/);
  await t.$("[data-send]").fire("click");
  assert.deepEqual(t.calls, [], "nothing is sent to a realm that is not published");
});

test("a chain that cannot be reached is a different thing, and says so", async () => {
  const c = grantsChain();
  c.fail = true;
  const t = boot(c);
  await t.flush();
  assert.match(t.text("[data-state]"), /Cannot reach test/);
  assert.match(t.text("[data-state]"), /This is the network, not the realm/);
  assert.doesNotMatch(t.text("[data-state]"), /Not published/);
});

test("live: the desk, then every request with its outcome", async () => {
  const t = boot(grantsChain());
  await t.flush();

  const state = t.text("[data-state]");
  assert.match(state, /Open: anyone may file/);
  assert.match(state, /250 GNOT/);
  assert.match(state, /100 GNOT/);

  const list = t.text("[data-list]");
  assert.match(list, /Requests 4/);
  assert.match(list, /Paid in part/);
  assert.match(list, /40 GNOT of the 100 GNOT asked/);
  assert.match(list, /Paid in full/);
  assert.match(list, /Refused/);
  assert.match(list, /Waiting for a decision/);
  // The reason a decided request carries on its own page reaches the list,
  // without the reader having to click anything.
  assert.match(list, /Half of it, the rest next quarter/);
  assert.match(list, /No reason was given, and the realm does not ask for one/, "the refusal that gave none");
});

test("one read per decided request, cached, and never per refresh", async () => {
  const c = grantsChain();
  const reads = [];
  const answer = (kind, expr) => { if (kind === "render") reads.push(expr); return c.answer(kind, expr); };
  const t = mount(app, { answer });
  await t.flush();
  assert.deepEqual(reads, ["", "request/4", "request/2", "request/1"], "the index, then the three decided ones");

  reads.length = 0;
  t.refresh();
  await t.flush();
  assert.deepEqual(reads, [""], "a refresh re-reads the index and nothing else");
});

test("a request page that fails is retried, not cached as a gap", async () => {
  const c = grantsChain();
  let broken = true;
  const answer = (kind, expr) => {
    if (kind === "render" && broken && /^request\//.test(expr)) throw new Error("test: HTTP 429");
    return c.answer(kind, expr);
  };
  const t = mount(app, { answer });
  await t.flush();
  assert.doesNotMatch(t.text("[data-list]"), /Half of it/);

  broken = false;
  t.refresh();
  await t.flush();
  assert.match(t.text("[data-list]"), /Half of it, the rest next quarter/);
});

test("paused is shown, and blocks an address that may not file", async () => {
  const c = grantsChain();
  c.paused = true;
  const t = boot(c, { address: STRANGER });
  t.$('[name="to"]').value = STRANGER;
  t.$('[name="amount"]').value = "25";
  t.$('[name="title"]').value = "A keyboard";
  t.$('[name="reason"]').value = "Mine died.";
  await t.flush();
  await t.$('[name="reason"]').fire("input");

  assert.match(t.text("[data-state]"), /Paused: new requests from the allowlist only/);
  assert.match(t.text("[data-problems]"), /only the addresses on its allowlist may file/);
  assert.equal(t.$("[data-send]").disabled, true);
});

test("the review says what is about to be sent, and that it sends no coins", async () => {
  const t = boot(grantsChain());
  await t.flush();
  t.$('[name="to"]').value = STRANGER;
  t.$('[name="amount"]').value = "25";
  t.$('[name="title"]').value = "A keyboard";
  t.$('[name="reason"]').value = "Mine died.";
  await t.$('[name="reason"]').fire("input");

  const review = t.text("[data-review]");
  assert.match(review, /a call to Request on gno\.land\/r\/test/);
  assert.match(review, /asking for 25 GNOT, to be paid to g1jg8mtut/);
  assert.match(review, /It sends no coins\./);
  assert.match(review, /public forever/);
  assert.match(review, /Not checked against the chain yet/);
  assert.equal(t.$("[data-send]").disabled, false);
});

test("a refusal the page could not predict stops the signature", async () => {
  const c = grantsChain();
  c.sim = { error: "grants: paused, new requests are open to the allowlist only" };
  const t = boot(c);
  await t.flush();
  for (const [k, v] of Object.entries({ to: STRANGER, amount: "25", title: "A keyboard", reason: "Mine died." })) t.$(`[name="${k}"]`).value = v;
  await t.$('[name="reason"]').fire("input");
  assert.equal(t.$("[data-send]").disabled, false);

  const checked = t.$("[data-check]").fire("click");
  await t.flush();
  await checked;
  assert.match(t.text("[data-review]"), /The chain would refuse this/);
  assert.match(t.text("[data-review]"), /open to the allowlist only/);
  assert.equal(t.$("[data-send]").disabled, true, "no signature prompt the chain would reject");
});

// On a real network, because the command names the chain id and the RPC the
// visitor would paste; "test" is not one.
test("a measured call shows its gas, and the command carries the same figure", async () => {
  const t = boot(grantsChain(), { net: "staging" });
  await t.flush();
  for (const [k, v] of Object.entries({ to: STRANGER, amount: "25", title: "A keyboard", reason: "Mine died." })) t.$(`[name="${k}"]`).value = v;
  await t.$('[name="reason"]').fire("input");
  const checked = t.$("[data-check]").fire("click");
  await t.flush();
  await checked;

  assert.match(t.text("[data-review]"), /The chain accepts this call/);
  assert.match(t.text("[data-review]"), /1,234,567 gas used/);
  assert.match(t.text("[data-cmd]"), /-gas-wanted 1604938/);
  assert.equal(t.$("[data-send]").disabled, false);
});

test("editing the form throws the check away rather than keeping a stale green", async () => {
  const t = boot(grantsChain(), { net: "staging" });
  await t.flush();
  for (const [k, v] of Object.entries({ to: STRANGER, amount: "25", title: "A keyboard", reason: "Mine died." })) t.$(`[name="${k}"]`).value = v;
  await t.$('[name="reason"]').fire("input");
  const checked = t.$("[data-check]").fire("click");
  await t.flush();
  await checked;
  assert.match(t.text("[data-review]"), /The chain accepts this call/);

  t.$('[name="amount"]').value = "99";
  await t.$('[name="amount"]').fire("input");
  assert.doesNotMatch(t.text("[data-review]"), /The chain accepts this call/);
  assert.match(t.text("[data-review]"), /asking for 99 GNOT/);
  assert.match(t.text("[data-cmd]"), /-args 99000000/);
  assert.match(t.text("[data-cmd]"), /-gas-wanted <measure it/, "a measurement never carries over to different arguments");
});

test("a simulation that cannot run is not read as a refusal", async () => {
  const c = grantsChain();
  c.answer = (kind, expr) => { if (kind === "simulate") throw new Error("invalid pubkey"); return grantsChain().answer(kind, expr); };
  const t = boot(c);
  await t.flush();
  for (const [k, v] of Object.entries({ to: STRANGER, amount: "25", title: "A keyboard", reason: "Mine died." })) t.$(`[name="${k}"]`).value = v;
  await t.$('[name="reason"]').fire("input");
  const checked = t.$("[data-check]").fire("click");
  await t.flush();
  await checked;

  assert.match(t.text("[data-review]"), /Could not check it/);
  assert.match(t.text("[data-review]"), /about your account, not about this request/);
  assert.equal(t.$("[data-send]").disabled, false, "signing stays allowed");
});

test("sending files the request, and nothing is sent while the form is wrong", async () => {
  const t = boot(grantsChain());
  await t.flush();
  await t.$("[data-send]").fire("click");
  assert.deepEqual(t.calls, [], "an empty form sends nothing");

  for (const [k, v] of Object.entries({ to: STRANGER, amount: "25", title: " A keyboard ", reason: " Mine died. " })) t.$(`[name="${k}"]`).value = v;
  await t.$('[name="reason"]').fire("input");
  const sent = t.$("[data-send]").fire("click");
  await t.flush();
  await sent;

  assert.deepEqual(t.calls, [{ func: "Request", args: [STRANGER, "25000000", "A keyboard", "Mine died."] }],
    "trimmed the way the realm trims");
});

test("with no address connected there is nothing to sign with", async () => {
  const t = boot(grantsChain(), { address: null });
  await t.flush();
  for (const [k, v] of Object.entries({ to: STRANGER, amount: "25", title: "A keyboard", reason: "Mine died." })) t.$(`[name="${k}"]`).value = v;
  await t.$('[name="reason"]').fire("input");
  assert.equal(t.$("[data-send]").disabled, true);
  assert.match(t.$("[data-send]").title, /connect an address/);
});

test("the byte counters count bytes", async () => {
  const t = boot(grantsChain());
  await t.flush();
  t.$('[name="title"]').value = "héllo";
  await t.$('[name="title"]').fire("input");
  assert.equal(t.text("[data-count-title]"), "6/80 bytes");
});
