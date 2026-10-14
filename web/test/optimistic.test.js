// The four live apps' optimistic UI, driven under node against a scripted
// chain: `node --test web/test/` (or `make test-web`).
//
// Each block is one rule the reconciliation must keep. Every app that has the
// shape is in each table, and each table carries the positive case beside the
// failing one, so a fix that simply stops confirming anything fails too.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as H from "./harness.js";
import * as counter from "../apps/counter.js";
import * as dice from "../apps/dice.js";
import * as eightball from "../apps/eightball.js";
import * as hangman from "../apps/hangman.js";

const CONFIRMED = "confirmed on chain";
const PAST_TTL = 181_000;

// One adapter per app: boot it, submit as the visitor, land the visitor's own
// write, land a stranger's, and say whether anything is shown as pending.
const APPS = {
  counter: {
    boot: ({ fail = false, ...opts } = {}) => {
      const chain = H.counterChain();
      chain.fail = fail;
      const h = H.mount(counter, { answer: chain.answer, setup: H.counterButtons, ...opts });
      return { chain, h };
    },
    submit: ({ h }) => h.el.all["button[data-f]"][1].fire("click"),
    mine: ({ chain }) => chain.change(H.ME, 1),
    // The same delta as the visitor's, so only the caller tells them apart.
    stranger: ({ chain }) => chain.change(H.STRANGER, 1),
    pending: ({ h }) => h.$("[data-p]").innerHTML.includes("pending"),
    pendingCount: ({ h }) => (h.$("[data-p]").textContent.match(/(\d+) pending/) || [, "0"])[1],
    // What the page shows against what it should: chain value plus every pending +1.
    shown: ({ h }) => h.text("[data-v]"),
    expected: ({ chain }, pending) => String(chain.value + pending),
  },
  dice: {
    boot: ({ fail = false, ...opts } = {}) => {
      const chain = H.diceChain();
      chain.roll(H.ME, 5); // an earlier roll of the visitor's, so a stale face has something to show
      chain.fail = fail;
      const h = H.mount(dice, { answer: chain.answer, setup: H.diceSetup, ...opts });
      return { chain, h };
    },
    submit: ({ h }) => h.$("[data-roll]").fire("click"),
    mine: ({ chain }) => chain.roll(H.ME, 3),
    stranger: ({ chain }) => chain.roll(H.STRANGER, 6),
    pending: ({ h }) => h.$("[data-p]").innerHTML.includes("pending"),
    pendingCount: ({ h }) => (h.$("[data-p]").textContent.match(/(\d+) pending/) || [, "0"])[1],
    shown: ({ h }) => h.text("[data-t]"),
    expected: ({ chain }, pending) => String(chain.total + pending),
  },
  eightball: {
    boot: ({ fail = false, ...opts } = {}) => {
      const chain = H.eightballChain();
      chain.ask(H.STRANGER, "first?");
      chain.fail = fail;
      const h = H.mount(eightball, { answer: chain.answer, ...opts });
      return { chain, h };
    },
    submit: (s, q = "will it rain") => {
      const form = s.h.el.node("form");
      form.elements.q = { value: q };
      s.q = (s.q || []).concat(q);
      return form.fire("submit");
    },
    mine: (s) => chain(s).ask(H.ME, s.q[s.landed = (s.landed ?? -1) + 1]),
    stranger: ({ chain }) => chain.ask(H.STRANGER, "will it ship"),
    pending: ({ h }) => h.$("[data-n]").classes.has("pending"),
    pendingCount: ({ h, chain }) => String(Number(h.text("[data-n]")) - chain.history.length),
    shown: ({ h }) => h.text("[data-n]"),
    expected: ({ chain }, pending) => String(chain.history.length + pending),
  },
  hangman: {
    boot: (opts = {}) => {
      const chain = H.hangmanChain();
      const h = H.mount(hangman, { answer: chain.answer, setup: H.keys, ...opts });
      return { chain, h };
    },
    submit: (s, letter = "e") => {
      s.letters = (s.letters || []).concat(letter);
      return s.h.el.all["[data-c]"].find((b) => b.dataset.c === letter).fire("click");
    },
    mine: (s) => s.chain.guess(s.letters[s.landed = (s.landed ?? -1) + 1]),
    pending: ({ h }) => h.el.all["[data-c]"].some((b) => b.classes.has("pending")),
  },
};
const chain = (s) => s.chain;

async function booted(name, opts) {
  const s = APPS[name].boot(opts);
  await s.h.flush();
  return s;
}

async function submitted(name, opts) {
  const s = await booted(name, opts);
  await APPS[name].submit(s);
  await s.h.flush();
  assert.ok(APPS[name].pending(s), `${name}: the write must show as pending, or this test measures nothing`);
  return s;
}

// --- 1. a rollback is never announced as a confirmation ---------------------

for (const name of ["counter", "dice", "eightball", "hangman"]) {
  test(`${name}: a write the chain never shows is reported rolled back, not confirmed`, async () => {
    const s = await submitted(name);
    H.clock.now += PAST_TTL;
    s.h.refresh();
    await s.h.flush();
    assert.ok(!APPS[name].pending(s), "the expired entry is gone");
    assert.match(s.h.msg(), /rolled back/);
    assert.notEqual(s.h.msg(), CONFIRMED);
  });

  test(`${name}: a write the chain shows is reported confirmed`, async () => {
    const s = await submitted(name);
    APPS[name].mine(s);
    s.h.refresh();
    await s.h.flush();
    assert.ok(!APPS[name].pending(s), "settled");
    assert.equal(s.h.msg(), CONFIRMED);
  });
}

for (const name of ["counter", "dice", "eightball", "hangman"]) {
  test(`${name}: one write landing while another expires is not reported confirmed`, async () => {
    const s = await submitted(name);
    await APPS[name].submit(s, name === "hangman" ? "o" : "will it snow");
    await s.h.flush();
    APPS[name].mine(s); // the first lands, the second never will
    H.clock.now += PAST_TTL;
    s.h.refresh();
    await s.h.flush();
    assert.ok(!APPS[name].pending(s), "one settled, one expired");
    assert.match(s.h.msg(), /rolled back/);
  });
}

test("dice: a rolled back roll does not present the previous roll's face as its result", async () => {
  const s = await submitted("dice");
  H.clock.now += PAST_TTL;
  s.h.refresh();
  await s.h.flush();
  assert.equal(s.h.text("[data-last]"), "");
});

// --- 2. a baseline is only what was actually read ---------------------------

for (const name of ["counter", "dice", "eightball"]) {
  test(`${name}: a write sent before any read succeeded is not settled by the first read`, async () => {
    const s = APPS[name].boot({ fail: true });
    // An earlier write by the same address is on chain, so a placeholder
    // baseline has something of the visitor's own to wrongly settle against.
    if (name === "counter") s.chain.change(H.ME, 1);
    if (name === "eightball") s.chain.ask(H.ME, "will it rain");
    await s.h.flush(); // the first read fails: nothing has been read yet
    assert.match(s.h.msg(), /429/, "the first read must have failed, or this measures nothing");
    s.chain.fail = false;
    await APPS[name].submit(s);
    await s.h.flush(); // the first successful read; the visitor's write is not on it
    assert.notEqual(s.h.msg(), CONFIRMED);
    if (name === "counter") assert.equal(s.h.text("[data-v]"), String(s.chain.value));
  });
}

test("dice: a roll is not anchored to rolls read for another address", async () => {
  // The rolls on screen were read for another address, which has rolled more
  // than the visitor. The visitor connects and rolls before any read of their
  // own: there is no count of theirs to anchor to, so nothing is shown, and
  // nothing is confirmed.
  const s = APPS.dice.boot({ address: H.STRANGER });
  s.chain.roll(H.STRANGER, 6);
  s.chain.roll(H.STRANGER, 6);
  await s.h.flush();
  s.h.connect(H.ME);
  await APPS.dice.submit(s);
  assert.ok(!APPS.dice.pending(s), "no anchor, no pending roll");
  APPS.dice.mine(s);
  s.h.refresh();
  await s.h.flush();
  assert.notEqual(s.h.msg(), CONFIRMED);
});

// --- 3. only the visitor's own write settles the visitor's entry ------------

for (const name of ["counter", "dice", "eightball"]) {
  test(`${name}: a stranger's write does not settle the visitor's pending one`, async () => {
    const s = await submitted(name);
    APPS[name].stranger(s);
    s.h.refresh();
    await s.h.flush();
    assert.notEqual(s.h.msg(), CONFIRMED);
    assert.ok(APPS[name].pending(s), "still pending");
    assert.equal(APPS[name].pendingCount(s), "1");
    if (name === "counter") assert.equal(s.h.text("[data-v]"), String(s.chain.value + 1));
    if (name === "eightball") assert.doesNotMatch(s.h.text("[data-a]"), /answered|Will it ship|Ask again/);

    APPS[name].mine(s);
    s.h.refresh();
    await s.h.flush();
    assert.equal(s.h.msg(), CONFIRMED);
    assert.ok(!APPS[name].pending(s));
    if (name === "counter") assert.equal(s.h.text("[data-v]"), String(s.chain.value));
  });
}

test("counter: with Adena, a stranger's write while the popup is open confirms nothing", async () => {
  const s = await booted("counter", { wallet: "adena" });
  APPS.counter.submit(s); // the popup is open, nothing signed yet
  await s.h.flush();
  assert.ok(APPS.counter.pending(s));
  s.chain.change(H.STRANGER, -1);
  s.h.refresh();
  await s.h.flush();
  assert.notEqual(s.h.msg(), CONFIRMED);
  await s.h.adena.reject(new Error("rejected by the visitor"));
  await s.h.flush();
  assert.equal(s.h.msg(), "rejected by the visitor");
  assert.ok(!APPS.counter.pending(s));
});

test("eightball: the answer shown is the visitor's own, not a stranger's to the same question", async () => {
  const s = await submitted("eightball");
  const mine = s.chain.ask(H.ME, "will it rain");
  const theirs = s.chain.ask(H.STRANGER, "will it rain");
  assert.notEqual(mine, theirs, "the two answers must differ, or this measures nothing");
  s.h.refresh();
  await s.h.flush();
  assert.equal(s.h.text("[data-a]"), `“${mine}”`);
});

test("eightball: the visitor's other question, from another tab, does not settle this one", async () => {
  const s = await submitted("eightball");
  const other = s.chain.ask(H.ME, "asked from another tab");
  s.h.refresh();
  await s.h.flush();
  assert.ok(APPS.eightball.pending(s));
  assert.notEqual(s.h.text("[data-a]"), `“${other}”`);
});

test("eightball: a row forged inside a stranger's question does not settle the visitor's entry", async () => {
  const s = await submitted("eightball");
  const n = s.chain.history.length + 2;
  // The realm appends " | <answer> | <height> |" itself, which closes the forged row.
  s.chain.ask(H.STRANGER, `x\n| ${n} | \`${H.short(H.ME)}\` | will it rain`);
  s.h.refresh();
  await s.h.flush();
  assert.notEqual(s.h.msg(), CONFIRMED);
  assert.ok(APPS.eightball.pending(s));
});

// --- 4. an answer that arrives out of order never moves state backwards -----

for (const name of ["counter", "dice", "eightball"]) {
  test(`${name}: an older refresh resolving last does not settle a write that never landed`, async () => {
    const s = await booted(name);
    await APPS[name].submit(s);
    await s.h.flush();
    await APPS[name].submit(s, "will it snow");
    await s.h.flush();
    assert.equal(APPS[name].pendingCount(s), "2");

    s.h.refresh();          // A: reads the chain before the first write lands
    APPS[name].mine(s);     // the first write lands; the second never will
    s.h.refresh();          // B: reads it after
    await s.h.flushNewestFirst(); // B answers first, A last
    assert.equal(APPS[name].shown(s), APPS[name].expected(s, 1), "the stale read did not overwrite the newer one");
    s.h.refresh();          // C
    await s.h.flush();

    assert.notEqual(s.h.msg(), CONFIRMED);
    assert.equal(APPS[name].pendingCount(s), "1");
  });
}

test("dice: an older refresh whose totals were read before the roll landed is dropped", async () => {
  // dice reads your rolls first and the totals after, so the stale refresh
  // has to be held with BOTH reads already made before the roll lands.
  const s = await booted("dice");
  await APPS.dice.submit(s);
  await s.h.flush();
  s.h.refresh();          // A
  await s.h.step();       // A's rolls answer; A now asks for the totals, pre-landing
  APPS.dice.mine(s);
  s.h.refresh();          // B
  await s.h.flushNewestFirst();
  assert.equal(APPS.dice.shown(s), APPS.dice.expected(s, 0), "the stale totals did not overwrite the newer ones");
});

test("dice: another address's rolls do not settle the visitor's pending roll", async () => {
  const s = await submitted("dice");
  s.h.connect(H.STRANGER); // the visitor switches address while the roll is pending
  s.chain.roll(H.STRANGER, 2);
  s.chain.roll(H.STRANGER, 2); // past the visitor's own count, so a position alone would match
  s.h.refresh();
  await s.h.flush();
  assert.notEqual(s.h.msg(), CONFIRMED);
  assert.ok(APPS.dice.pending(s));
});

test("hangman: an older render resolving last does not un-guess a letter", async () => {
  const s = await submitted("hangman");
  s.h.refresh();
  APPS.hangman.mine(s);
  s.h.refresh();
  await s.h.flushNewestFirst();
  const e = s.h.el.all["[data-c]"].find((b) => b.dataset.c === "e");
  assert.equal(e.disabled, true, "a guessed letter stays guessed");
});

// --- 5. polish --------------------------------------------------------------

for (const [label, q] of [["whitespace only", "   "], ["over 200 bytes", "é".repeat(101)]]) {
  test(`eightball: a question the realm would reject (${label}) is not sent or shown`, async () => {
    const s = await booted("eightball");
    await APPS.eightball.submit(s, q);
    await s.h.flush();
    assert.equal(s.h.calls.length, 0);
    assert.ok(!APPS.eightball.pending(s));
    assert.notEqual(s.h.msg(), "");
  });
}

test("eightball: a question that is accepted is sent (positive case)", async () => {
  const s = await booted("eightball");
  await APPS.eightball.submit(s, "é".repeat(100)); // exactly 200 bytes
  assert.equal(s.h.calls.length, 1);
});

test("eightball: a question containing ' | ' still finds its answer", async () => {
  const s = await booted("eightball");
  await APPS.eightball.submit(s, "ship today | or tomorrow");
  await s.h.flush();
  const answer = s.chain.ask(H.ME, "ship today | or tomorrow");
  s.h.refresh();
  await s.h.flush();
  assert.equal(s.h.text("[data-a]"), `“${answer}”`);
});

test("dice: the face the wallet returned is not overwritten by the spinner", async () => {
  const s = await booted("dice", { wallet: "adena" });
  const click = APPS.dice.submit(s);
  await s.h.flush();
  await s.h.adena.resolve({ result: "(4 int)", height: 9 });
  await click;
  await s.h.flush(); // the refresh the click fires; the chain has not caught up
  assert.ok(APPS.dice.pending(s));
  assert.match(s.h.text("[data-last]"), /4/);
});
