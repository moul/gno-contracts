// Dice: the six faces as a live bar chart from Distribution(), a Roll button,
// and your own last rolls once connected. A roll shows at once as a spinning
// die and a bumped total, until the chain confirms it and the face is known.
// A roll settles on RollsOf(your address) growing, never on Total(), which
// every player moves.

import { parseEval } from "../lib/gno.js";
import { Queue, ordered } from "../lib/optimistic.js";

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

  // mine is the visitor's rolls as last read, and the address they were read
  // for: a pending roll remembers how many there were (`after`).
  let total = null, mine = null;
  const fresh = ordered();
  const queue = new Queue({
    onExpire: () => {
      if (!queue.size) $("[data-last]").textContent = "";
      msg("not seen on chain after 3 minutes, rolled back");
      draw();
    },
  });

  const draw = () => {
    if (total === null) return;
    $("[data-t]").textContent = total + queue.size;
    $("[data-t]").classList.toggle("pending", queue.size > 0);
    $("[data-p]").innerHTML = queue.size ? `<span class="pending-chip">${queue.size} pending</span>` : "";
    // The newest pending roll: its face once the wallet returned it, else the spinner.
    const last = queue.items[queue.items.length - 1];
    if (last?.face) $("[data-last]").textContent = `${FACES[last.face - 1]} ${last.face}`;
    else if (last) $("[data-last]").innerHTML = '<span class="spin">🎲</span> <span class="muted">rolling…</span>';
  };

  const refresh = async () => {
    const current = fresh();
    try {
      // Your rolls first, so any roll they show is also in the totals read after.
      const me = wallet.current();
      const rolls = me && [...(await client.eval(path, `RollsOf(${JSON.stringify(me.address)})`)).matchAll(/\((\d) int\)/g)].map((m) => Number(m[1]));
      const [dist, t] = await Promise.all([client.eval(path, "Distribution()"), client.eval(path, "Total()")]);
      if (!current()) return;
      const counts = [...dist.matchAll(/\((\d+) int\)/g)].map((m) => Number(m[1]));
      const max = Math.max(1, ...counts);
      [...$("[data-bars]").children].forEach((bar, i) => {
        bar.style.height = `${Math.max(2, (counts[i] / max) * 100)}%`;
        bar.querySelector("b").textContent = counts[i] ?? 0;
      });
      total = parseEval(t);
      mine = me ? { addr: me.address, rolls } : null;
      if (mine) $("[data-mine]").textContent = rolls.length ? `your rolls: ${rolls.slice(-20).map((v) => FACES[v - 1]).join(" ")}` : "you have not rolled yet";
      if (queue.size) {
        const seen = mine ? mine.rolls.map((face, i) => ({ at: i + 1, key: `${mine.addr}#${i + 1}`, face })) : [];
        const r = queue.claim(seen, (x) => x.addr === mine.addr);
        if (r.confirmed) {
          const face = r.claimed[r.claimed.length - 1].seen.face;
          $("[data-last]").textContent = `${FACES[face - 1]} ${face}`;
          msg("confirmed on chain");
        }
      }
      draw();
    } catch (e) {
      if (current()) msg(e.message);
    }
  };

  $("[data-roll]").addEventListener("click", async () => {
    msg("waiting for the wallet…");
    let item = null;
    try {
      const tx = await call("Roll", [], {
        onSubmit: () => {
          // Only against rolls actually read for this address: otherwise
          // show nothing rather than a roll no refresh could reconcile.
          const me = wallet.current();
          if (total === null || !me || mine?.addr !== me.address) return;
          item = queue.add({ after: mine.rolls.length, addr: me.address });
          draw();
        },
      });
      const v = parseEval(wallet.result(tx));
      if (typeof v === "number") {
        if (item) item.face = v;
        $("[data-last]").textContent = `${FACES[v - 1]} ${v}${tx.simulated ? " (dry run)" : ""}`;
      }
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
