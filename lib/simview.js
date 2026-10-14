// The dry-run result: what the transaction would have done, in a dashed
// yellow box that cannot be mistaken for something that happened.

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const gnot = (ugnot) => `${(ugnot / 1e6).toFixed(6).replace(/\.?0+$/, "")} GNOT`;

export function render(slot, { func, args, caller, net, sim }) {
  if (!slot) return;
  const call = `${esc(func)}(${args.map((a) => esc(JSON.stringify(a))).join(", ")})`;
  const fee = Math.ceil((sim.gasUsed * 1.3) / 1000) * 2;
  slot.innerHTML = `
    <div class="simulated${sim.error ? " failed" : ""}">
      <div class="sim-head"><span>🧪 <b>Dry run, nothing was sent</b> · <code>${call}</code> as <code>${esc(caller.slice(0, 10))}…</code> on ${esc(net)}</span>
        <button type="button" class="sim-close" aria-label="dismiss">×</button></div>
      ${sim.error
        ? `<p><b>Would fail:</b> ${esc(sim.error.replace(/^\d+ - /, ""))}</p>`
        : `<p><b>Would return:</b> ${sim.data ? `<code>${esc(sim.data)}</code>` : '<span class="muted">nothing</span>'}</p>`}
      <p class="muted">${sim.gasUsed.toLocaleString()} gas · about ${gnot(fee)} in fees${sim.deposits.map((d) =>
        ` · ${d.kind === "unlock" ? "frees" : "locks"} ${Math.abs(d.bytes).toLocaleString()} bytes (${esc(d.amount)})`).join("")}</p>
      ${sim.events.length ? `<p><b>Events</b></p><ul>${sim.events.map((e) =>
        `<li><code>${esc(e.type)}</code> ${e.attrs.map(([k, v]) => `${esc(k)}=<code>${esc(v)}</code>`).join(" ")}</li>`).join("")}</ul>` : ""}
    </div>`;
  slot.querySelector(".sim-close").addEventListener("click", () => { slot.innerHTML = ""; });
}
