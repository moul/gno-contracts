// The no-wallet path: a modal with the exact gnokey command a transaction
// needs, ready to paste. Gas is never guessed: once the visitor gives their
// address, the call is simulated and the command carries the measured figure.
//
// The command string itself is lib/cmd.js's, which is pure and tested.

import { Client } from "./gno.js";
import * as identity from "./identity.js";
import { command, gasFor } from "./cmd.js";

export { command };

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

// open shows the modal and resolves when the visitor says they sent it, or
// rejects when they close it.
export function open({ net, cfg, pkgPath, func, args = [], send = "", address = "", key = "" }) {
  return new Promise((resolve, reject) => {
    const dlg = document.createElement("dialog");
    dlg.className = "modal";
    dlg.innerHTML = `
      <form method="dialog">
        <h3>Send it with gnokey</h3>
        <p class="muted">No wallet needed: paste this into a terminal with
          <a href="https://docs.gno.land/users/interact-with-gnokey" target="_blank" rel="noopener">gnokey</a>.
          Your address is only used to measure the gas, by simulating the call; nothing is signed here.</p>
        <div class="row">
          <input name="addr" placeholder="your address, g1…" size="44" autocomplete="off" spellcheck="false">
          <input name="key" placeholder="key name" size="10" autocomplete="off" spellcheck="false">
        </div>
        <p class="muted" data-sim></p>
        <pre data-cmd></pre>
        <div class="row">
          <button type="button" data-copy>Copy</button>
          <span class="spacer"></span>
          <button value="cancel">Close</button>
          <button value="sent" class="primary">I sent it, refresh</button>
        </div>
      </form>`;
    document.body.append(dlg);
    const $ = (s) => dlg.querySelector(s);
    const f = dlg.querySelector("form").elements;
    f.addr.value = address;
    f.key.value = key;
    let gas = {};

    const draw = () => { $("[data-cmd]").textContent = command({ net, cfg, pkgPath, func, args, send, key: f.key.value.trim(), ...gas }); };
    const measure = async () => {
      const addr = f.addr.value.trim();
      gas = {};
      draw();
      if (!/^g1[02-9ac-hj-np-z]{38}$/.test(addr)) { $("[data-sim]").textContent = addr ? "not a g1 address" : ""; return; }
      if (!identity.get()) identity.set("manual", addr);
      if (send) { $("[data-sim]").textContent = "this call sends coins, which this page cannot simulate: size the gas yourself"; return; }
      $("[data-sim]").textContent = "simulating…";
      try {
        const sim = await new Client(net).simulate(addr, pkgPath, func, args);
        if (sim.error) throw new Error(sim.error);
        gas = gasFor(sim.gasUsed);
        $("[data-sim]").innerHTML = `simulated on ${esc(net)}: <b>${sim.gasUsed.toLocaleString()}</b> gas used${sim.data ? `, would return <code>${esc(sim.data)}</code>` : ""}. Fee ${(gas.gasFee / 1e6).toFixed(6).replace(/0+$/, "")} GNOT, plus any storage deposit.`;
      } catch (e) {
        $("[data-sim]").textContent = `simulation failed: ${e.message}` +
          (/does not exist/.test(e.message) ? " (fund this address first: an empty account has nothing to pay the fee with)"
            : /pubkey|public key/i.test(e.message) ? " (an account that never sent a transaction has no public key on chain yet)" : "");
      }
      draw();
    };

    f.addr.addEventListener("input", measure);
    f.key.addEventListener("input", () => { identity.setKey(f.key.value.trim()); draw(); });
    $("[data-copy]").addEventListener("click", async () => {
      await navigator.clipboard.writeText($("[data-cmd]").textContent.replace(/^# .*\n/, ""));
      $("[data-copy]").textContent = "Copied";
    });
    dlg.addEventListener("close", () => {
      dlg.remove();
      if (dlg.returnValue === "sent") resolve({ manual: true });
      else reject(new Error("cancelled"));
    });
    draw();
    measure();
    dlg.showModal();
  });
}
