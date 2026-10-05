// Dice: the six faces as a live bar chart from Distribution(), a Roll button,
// and your own last rolls once connected. A roll shows at once as a spinning
// die and a bumped total, until the chain confirms it and the face is known.

import { parseEval } from "../lib/gno.js";
import { Queue } from "../lib/optimistic.js";

const FACES = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"];

export function mount(el, { client, path, call, wallet }) {
  el.innerHTML = `
    <div class="app-panel">
      <div class="bars" data-bars>${FACES.map((f) => `<div style="height:2px"><b>0</b><span>${f}</span></div>`).join("")}</div>
      <p class="muted" style="margin-top:2.2rem"><span data-t>…</span> rolls in total <span data-p></span></p>
      <div class="answer" data-last></div>
      <button data-roll>🎲 Roll</button>
      <p class="muted" data-mine></p>
      <p class="muted" data-msg></p>
    </div>`;
  const $ = (s) => el.querySelector(s);
  const msg = (s) => { $("[data-msg]").textContent = s; };

  let total = null, base = 0, mine = [];
  const queue = new Queue({ onExpire: () => { msg("not seen on chain after 3 minutes, rolled back"); draw(); } });

  const draw = () => {
    if (total === null) return;
    $("[data-t]").textContent = total + queue.size;
    $("[data-t]").classList.toggle("pending", queue.size > 0);
    $("[data-p]").innerHTML = queue.size ? `<span class="pending-chip">${queue.size} pending</span>` : "";
    if (queue.size) $("[data-last]").innerHTML = '<span class="spin">🎲</span> <span class="muted">rolling…</span>';
  };

  const refresh = async () => {
    try {
      const [dist, t] = await Promise.all([client.eval(path, "Distribution()"), client.eval(path, "Total()")]);
      const counts = [...dist.matchAll(/\((\d+) int\)/g)].map((m) => Number(m[1]));
      const max = Math.max(1, ...counts);
      [...$("[data-bars]").children].forEach((bar, i) => {
        bar.style.height = `${Math.max(2, (counts[i] / max) * 100)}%`;
        bar.querySelector("b").textContent = counts[i] ?? 0;
      });
      total = parseEval(t);
      const me = wallet.current();
      if (me) {
        mine = [...(await client.eval(path, `RollsOf(${JSON.stringify(me.address)})`)).matchAll(/\((\d) int\)/g)].map((m) => Number(m[1]));
        $("[data-mine]").textContent = mine.length ? `your rolls: ${mine.slice(-20).map((v) => FACES[v - 1]).join(" ")}` : "you have not rolled yet";
      }
      if (queue.size) {
        queue.take(total - base);
        base = total;
        if (!queue.size) {
          const last = mine[mine.length - 1];
          $("[data-last]").textContent = last ? `${FACES[last - 1]} ${last}` : "";
          msg("confirmed on chain");
        }
      }
      draw();
    } catch (e) {
      msg(e.message);
    }
  };

  $("[data-roll]").addEventListener("click", async () => {
    msg("waiting for the wallet…");
    let item = null;
    try {
      const tx = await call("Roll", [], {
        onSubmit: () => {
          if (!queue.size) base = total;
          item = queue.add({});
          draw();
        },
      });
      const v = parseEval(wallet.result(tx));
      if (typeof v === "number") $("[data-last]").textContent = `${FACES[v - 1]} ${v}${tx.simulated ? " (dry run)" : ""}`;
      msg(wallet.describe(tx));
      refresh();
    } catch (e) {
      if (item) { queue.remove(item); draw(); }
      $("[data-last]").textContent = "";
      msg(e.message);
    }
  });

  refresh();
  const timer = setInterval(refresh, 5000);
  return () => clearInterval(timer);
}
