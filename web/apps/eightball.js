// Magic 8-ball: type a question, shake, read the answer. The question shows
// at once as a shaking ball; the answer comes from the transaction when the
// wallet returns it, otherwise from the realm's history once the chain has it.
// A question settles on its own row in that history, asked by your address,
// never on Asked(), which every visitor moves.

import { parseEval } from "../lib/gno.js";
import { Queue, ordered } from "../lib/optimistic.js";

// The asker column is ui.AddrOf: the address cut to 8 + "…" + 4, in backticks.
const short = (a) => `${a.slice(0, 8)}…${a.slice(-4)}`;

// shakes lifts the count and the history table out of Render: the last 15
// questions, oldest first, each with its number (`at`), asker, question and
// answer. The realm writes the question into its cell unescaped, so the
// columns are read from both ends (a question may hold " | "), and a table
// whose rows are not exactly the run of numbers the count implies (a question
// holding a newline, or a row forged inside one) is not trusted at all.
const shakes = (md) => {
  const m = md.match(/\*\*Questions asked:\*\* (\d+)/);
  if (!m) throw new Error("unexpected Render layout");
  const asked = Number(m[1]);
  const sep = "|---|---|---|---|---|\n";
  const i = md.indexOf(sep);
  if (i < 0) return { asked, rows: [] };
  const rows = md.slice(i + sep.length).split("\n").filter((l) => l !== "").map((l) => {
    const c = l.split(" | ");
    return c.length < 5 ? null : {
      at: Number(c[0].replace(/^\| /, "")),
      asker: c[1].replace(/^`|`$/g, ""),
      question: c.slice(2, -2).join(" | "),
      answer: c[c.length - 2],
    };
  });
  const ok = rows.length === Math.min(15, asked) && rows.every((r, k) => r && r.at === asked - k);
  return { asked, rows: ok ? rows.reverse() : [] };
};

export function mount(el, { client, path, call, wallet }) {
  el.innerHTML = `
    <form class="app-panel">
      <div style="font-size:4rem" data-ball>🎱</div>
      <div class="row" style="justify-content:center">
        <input name="q" maxlength="200" placeholder="Will it ship today?" required>
        <button>Shake</button>
      </div>
      <div class="answer" data-a></div>
      <p class="muted"><span data-n>…</span> questions asked so far</p>
      <p class="muted" data-msg></p>
    </form>`;
  const $ = (s) => el.querySelector(s);
  const msg = (s) => { $("[data-msg]").textContent = s; };
  const form = el.querySelector("form");

  // A pending question remembers Asked() as last read (`after`) and who asked.
  let asked = null;
  const fresh = ordered();
  const queue = new Queue({ onExpire: () => { msg("not seen on chain after 3 minutes, rolled back"); draw(); } });

  const draw = () => {
    if (asked === null) return;
    $("[data-n]").textContent = asked + queue.size;
    $("[data-n]").classList.toggle("pending", queue.size > 0);
    $("[data-ball]").classList.toggle("spin", queue.size > 0);
  };

  const refresh = async () => {
    const current = fresh();
    try {
      const read = queue.size
        ? shakes(await client.render(path, ""))
        : { asked: parseEval(await client.eval(path, "Asked()")), rows: [] };
      if (!current()) return;
      asked = read.asked;
      if (queue.size) {
        const r = queue.claim(read.rows, (x, row) => row.asker === short(x.addr) && row.question === x.question);
        for (const x of r.claimed) if (!x.answered) $("[data-a]").textContent = `“${x.seen.answer}”`;
        if (r.confirmed) msg("confirmed on chain");
      }
      draw();
    } catch (e) {
      if (current()) msg(e.message);
    }
  };

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const question = form.elements.q.value.trim();
    // The realm panics on both; say so before anything is shown as pending.
    if (!question) return msg("ask something first");
    if (new TextEncoder().encode(question).length > 200) return msg("too long: the realm takes at most 200 bytes");
    $("[data-a]").textContent = "";
    msg("waiting for the wallet…");
    let item = null;
    try {
      const tx = await call("Ask", [question], {
        onSubmit: () => {
          // Nothing read yet, or nobody to attribute it to: show nothing
          // rather than a question no refresh could reconcile.
          const me = wallet.current();
          if (asked === null || !me) return;
          item = queue.add({ question, after: asked, addr: me.address });
          $("[data-a]").innerHTML = '<span class="muted pending">shaking…</span>';
          draw();
        },
      });
      const answer = parseEval(wallet.result(tx));
      if (answer) {
        if (item) item.answered = true;
        $("[data-a]").textContent = `“${answer}”${tx.simulated ? " (dry run)" : ""}`;
      }
      msg(wallet.describe(tx));
      refresh();
    } catch (e) {
      if (item) { queue.remove(item); draw(); }
      $("[data-a]").textContent = "";
      msg(e.message);
    }
  });

  refresh();
  const timer = setInterval(refresh, 5000);
  return () => clearInterval(timer);
}
