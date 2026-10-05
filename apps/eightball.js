// Magic 8-ball: type a question, shake, read the answer. The question shows
// at once as a shaking ball; the answer comes from the transaction when the
// wallet returns it, otherwise from the realm's history once the chain has it.

import { parseEval } from "../lib/gno.js";
import { Queue } from "../lib/optimistic.js";

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

  let asked = null, base = 0;
  const queue = new Queue({ onExpire: () => { msg("not seen on chain after 3 minutes, rolled back"); draw(); } });

  const draw = () => {
    if (asked === null) return;
    $("[data-n]").textContent = asked + queue.size;
    $("[data-n]").classList.toggle("pending", queue.size > 0);
    $("[data-ball]").classList.toggle("spin", queue.size > 0);
  };

  // answerFor finds a question's answer in the history table Render prints.
  const answerFor = async (question) => {
    const md = await client.render(path, "");
    const row = md.split("\n").find((l) => l.split(" | ")[2] === question);
    return row ? row.split(" | ")[3] : "";
  };

  const refresh = async () => {
    try {
      asked = parseEval(await client.eval(path, "Asked()"));
      if (queue.size) {
        const done = queue.items.slice(0, asked - base);
        queue.take(asked - base);
        base = asked;
        for (const x of done) {
          if (!x.answered) $("[data-a]").textContent = `“${(await answerFor(x.question)) || "answered, see the history below"}”`;
        }
        if (!queue.size) msg("confirmed on chain");
      }
      draw();
    } catch (e) {
      msg(e.message);
    }
  };

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const question = form.elements.q.value.trim();
    $("[data-a]").textContent = "";
    msg("waiting for the wallet…");
    let item = null;
    try {
      const tx = await call("Ask", [question], {
        onSubmit: () => {
          if (!queue.size) base = asked;
          item = queue.add({ question });
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
