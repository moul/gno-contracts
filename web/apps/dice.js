// Dice: the six faces as a live bar chart from Distribution(), a Roll button,
// and your own last rolls once a wallet is connected.

import { parseEval } from "../lib/gno.js";

const FACES = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"];

export function mount(el, { client, path, call, wallet }) {
  el.innerHTML = `
    <div class="app-panel">
      <div class="bars" data-bars>${FACES.map((f) => `<div style="height:2px"><b>0</b><span>${f}</span></div>`).join("")}</div>
      <p class="muted" style="margin-top:2.2rem"><span data-t>…</span> rolls in total</p>
      <div class="answer" data-last></div>
      <button data-roll>🎲 Roll</button>
      <p class="muted" data-mine></p>
      <p class="muted" data-msg></p>
    </div>`;
  const $ = (s) => el.querySelector(s);

  const refresh = async () => {
    try {
      const [dist, total] = await Promise.all([client.eval(path, "Distribution()"), client.eval(path, "Total()")]);
      const counts = [...dist.matchAll(/\((\d+) int\)/g)].map((m) => Number(m[1]));
      const max = Math.max(1, ...counts);
      [...$("[data-bars]").children].forEach((bar, i) => {
        bar.style.height = `${Math.max(2, (counts[i] / max) * 100)}%`;
        bar.querySelector("b").textContent = counts[i] ?? 0;
      });
      $("[data-t]").textContent = parseEval(total);
      const me = wallet.current();
      if (me) {
        const mine = [...(await client.eval(path, `RollsOf(${JSON.stringify(me.address)})`)).matchAll(/\((\d) int\)/g)].map((m) => FACES[m[1] - 1]);
        $("[data-mine]").textContent = mine.length ? `your rolls: ${mine.slice(-20).join(" ")}` : "you have not rolled yet";
      }
    } catch (e) {
      $("[data-msg]").textContent = e.message;
    }
  };

  $("[data-roll]").addEventListener("click", async () => {
    $("[data-msg]").textContent = "waiting for the wallet…";
    try {
      const tx = await call("Roll");
      const v = parseEval(wallet.result(tx));
      $("[data-last]").textContent = typeof v === "number" ? `${FACES[v - 1]} ${v}` : "";
      $("[data-msg]").textContent = wallet.describe(tx);
      refresh();
    } catch (e) {
      $("[data-msg]").textContent = e.message;
    }
  });

  refresh();
  const timer = setInterval(refresh, 5000);
  return () => clearInterval(timer);
}
