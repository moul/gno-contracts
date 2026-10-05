// Counter Club, the first custom page: what the generic view cannot do.
// It polls Value() and Total() with vm/qeval instead of re-rendering markdown,
// turns Inc / Dec into wallet buttons, and shows a click at once: the number
// moves before the chain has it, marked pending until a refresh confirms it.

import { parseEval } from "../lib/gno.js";
import { Queue } from "../lib/optimistic.js";

export function mount(el, { client, path, call, wallet }) {
  el.innerHTML = `
    <div class="counter">
      <div class="big" data-v>…</div>
      <div class="muted"><span data-t>…</span> changes · refreshed every 4s <span data-p></span></div>
      <div class="row">
        <button data-f="Dec" data-d="-1">− Dec</button>
        <button data-f="Inc" data-d="1">+ Inc</button>
      </div>
      <div class="muted" data-msg></div>
    </div>`;
  const $ = (s) => el.querySelector(s);
  const msg = (s) => { $("[data-msg]").textContent = s; };

  // Total() counts every change, so "the chain caught up by n" is Total
  // minus what it read when the first pending change went out.
  const chain = { v: null, t: null };
  let base = 0;
  const queue = new Queue({ onExpire: () => { msg("not seen on chain after 3 minutes, rolled back"); draw(); } });

  const draw = () => {
    if (chain.v === null) return;
    const delta = queue.items.reduce((n, x) => n + x.delta, 0);
    $("[data-v]").textContent = chain.v + delta;
    $("[data-v]").classList.toggle("pending", queue.size > 0);
    $("[data-t]").textContent = chain.t + queue.size;
    $("[data-p]").innerHTML = queue.size ? `<span class="pending-chip">${queue.size} pending</span>` : "";
  };

  const refresh = async () => {
    try {
      const [v, t] = await Promise.all([client.eval(path, "Value()"), client.eval(path, "Total()")]);
      chain.v = parseEval(v);
      chain.t = parseEval(t);
      if (queue.size) {
        const n = chain.t - base;
        queue.take(n);
        base = chain.t;
        if (!queue.size) msg("confirmed on chain");
      }
      draw();
    } catch (e) {
      msg(e.message);
    }
  };

  el.querySelectorAll("button[data-f]").forEach((b) =>
    b.addEventListener("click", async () => {
      msg("waiting for the wallet…");
      let item = null;
      try {
        const tx = await call(b.dataset.f, [], {
          onSubmit: () => {
            if (!queue.size) base = chain.t;
            item = queue.add({ delta: Number(b.dataset.d) });
            draw();
          },
        });
        msg(wallet.describe(tx));
        refresh();
      } catch (e) {
        if (item) { queue.remove(item); draw(); }
        msg(e.message);
      }
    }));

  refresh();
  const timer = setInterval(refresh, 4000);
  return () => clearInterval(timer);
}
