// Counter Club, the first custom page: what the generic view cannot do.
// It polls Value() and Total() with vm/qeval instead of re-rendering markdown,
// turns Inc / Dec into wallet buttons, and shows a click at once: the number
// moves before the chain has it, marked pending until a refresh confirms it.
// While a click is pending it reads Render instead: its history says who made
// each change, and only the visitor's own change may settle the visitor's click.

import { parseEval } from "../lib/gno.js";
import { Queue, ordered } from "../lib/optimistic.js";

// history lifts the value, the total and the change log out of Render. The log
// is the last 20 changes; each gets its change number (`at`, 1 for the first
// change ever), oldest first.
const history = (md) => {
  const v = md.match(/## Current value\s+# (-?\d+)/);
  const t = md.match(/\*\*Total changes:\*\* (\d+)/);
  if (!v || !t) throw new Error("unexpected Render layout");
  const total = Number(t[1]);
  const changes = [...md.matchAll(/^\| (\d+) \| (g1\w+) \| ([+-]\d+) \| -?\d+ \| \d+ \|$/gm)]
    .map((m) => ({ at: total - Number(m[1]) + 1, caller: m[2], delta: Number(m[3]) }))
    .reverse();
  return { value: Number(v[1]), total, changes };
};

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

  // A pending click remembers Total() as last read (`after`) and who sent it;
  // it settles on the first change by that address numbered past `after`.
  const chain = { v: null, t: null };
  const fresh = ordered();
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
    const current = fresh();
    try {
      let read;
      if (queue.size) read = history(await client.render(path, ""));
      else {
        const [v, t] = await Promise.all([client.eval(path, "Value()"), client.eval(path, "Total()")]);
        read = { value: parseEval(v), total: parseEval(t), changes: [] };
      }
      if (!current()) return;
      chain.v = read.value;
      chain.t = read.total;
      if (queue.size) {
        const r = queue.claim(read.changes, (x, c) => c.caller === x.addr && c.delta === x.delta);
        if (r.confirmed) msg("confirmed on chain");
      }
      draw();
    } catch (e) {
      if (current()) msg(e.message);
    }
  };

  el.querySelectorAll("button[data-f]").forEach((b) =>
    b.addEventListener("click", async () => {
      msg("waiting for the wallet…");
      let item = null;
      try {
        const tx = await call(b.dataset.f, [], {
          onSubmit: () => {
            // Nothing read yet, or nobody to attribute it to: show nothing
            // rather than a change no refresh could ever reconcile.
            const me = wallet.current();
            if (chain.t === null || !me) return;
            item = queue.add({ delta: Number(b.dataset.d), after: chain.t, addr: me.address });
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
