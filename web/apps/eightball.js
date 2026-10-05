// Magic 8-ball: type a question, shake, read the answer the transaction
// returned. The realm's own Render below keeps the history.

import { parseEval } from "../lib/gno.js";

export function mount(el, { client, path, call, wallet }) {
  el.innerHTML = `
    <form class="app-panel">
      <div style="font-size:4rem">🎱</div>
      <div class="row" style="justify-content:center">
        <input name="q" maxlength="200" placeholder="Will it ship today?" required>
        <button>Shake</button>
      </div>
      <div class="answer" data-a></div>
      <p class="muted"><span data-n>…</span> questions asked so far</p>
      <p class="muted" data-msg></p>
    </form>`;
  const $ = (s) => el.querySelector(s);
  const form = el.querySelector("form");

  const refresh = async () => {
    try {
      $("[data-n]").textContent = parseEval(await client.eval(path, "Asked()"));
    } catch (e) {
      $("[data-msg]").textContent = e.message;
    }
  };

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    $("[data-a]").textContent = "";
    $("[data-msg]").textContent = "waiting for the wallet…";
    try {
      const tx = await call("Ask", [form.elements.q.value]);
      const answer = parseEval(wallet.result(tx));
      $("[data-a]").textContent = answer ? `“${answer}”` : "asked: the answer is in the history below";
      $("[data-msg]").textContent = wallet.describe(tx);
      refresh();
    } catch (e) {
      $("[data-msg]").textContent = e.message;
    }
  });

  refresh();
}
