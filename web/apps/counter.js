// Counter Club, the first custom page: what the generic view cannot do.
// It polls Value() and Total() with vm/qeval instead of re-rendering markdown,
// and turns Inc / Dec into wallet buttons.

import { parseEval } from "../lib/gno.js";

export function mount(el, { client, path, call, wallet }) {
  el.innerHTML = `
    <div class="counter">
      <div class="big" data-v>…</div>
      <div class="muted"><span data-t>…</span> changes · refreshed every 4s</div>
      <div class="row">
        <button data-f="Dec">− Dec</button>
        <button data-f="Inc">+ Inc</button>
      </div>
      <div class="muted" data-msg></div>
    </div>`;
  const $ = (s) => el.querySelector(s);

  const refresh = async () => {
    try {
      const [v, t] = await Promise.all([client.eval(path, "Value()"), client.eval(path, "Total()")]);
      $("[data-v]").textContent = parseEval(v);
      $("[data-t]").textContent = parseEval(t);
    } catch (e) {
      $("[data-msg]").textContent = e.message;
    }
  };

  el.querySelectorAll("button[data-f]").forEach((b) =>
    b.addEventListener("click", async () => {
      $("[data-msg]").textContent = "waiting for the wallet…";
      try {
        const tx = await call(b.dataset.f);
        $("[data-msg]").textContent = wallet.describe(tx);
        refresh();
      } catch (e) {
        $("[data-msg]").textContent = e.message;
      }
    }));

  refresh();
  const timer = setInterval(refresh, 4000);
  return () => clearInterval(timer);
}
