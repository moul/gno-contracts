// Who the page acts for, and the one Connect modal that sets it.
//   adena    the address Adena hands over; writes go through the wallet
//   manual   an address typed by hand; writes become a gnokey command to paste
// Either way the address is what dry runs simulate as, and what the gnokey
// command is prefilled for.

const adena = () => window.adena;
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
export const ADDR = /^g1[02-9ac-hj-np-z]{38}$/;

// The previous version kept a typed address under gnokey.addr: carry it over.
if (!localStorage.getItem("id.mode") && localStorage.getItem("gnokey.addr")) {
  localStorage.setItem("id.mode", "manual");
  localStorage.setItem("id.addr", localStorage.getItem("gnokey.addr"));
  localStorage.removeItem("gnokey.addr");
}

const listeners = new Set();
export const onChange = (fn) => listeners.add(fn);
const changed = () => listeners.forEach((fn) => fn(get()));

export function get() {
  const mode = localStorage.getItem("id.mode");
  const address = localStorage.getItem("id.addr");
  return mode && address ? { mode, address, chainId: localStorage.getItem("id.chain") || "", key: localStorage.getItem("gnokey.key") || "" } : null;
}

export function set(mode, address, chainId = "") {
  if (!mode) ["id.mode", "id.addr", "id.chain"].forEach((k) => localStorage.removeItem(k));
  else { localStorage.setItem("id.mode", mode); localStorage.setItem("id.addr", address); localStorage.setItem("id.chain", chainId); }
  changed();
}

export const setKey = (k) => localStorage.setItem("gnokey.key", k);
export const hasAdena = () => Boolean(adena());

export async function connectAdena() {
  if (!adena()) throw new Error("Adena is not installed: https://adena.app");
  await adena().AddEstablish("moul's gno dapps");
  const res = await adena().GetAccount();
  if (res.status !== "success") throw new Error(res.message || "wallet refused");
  set("adena", res.data.address, res.data.chainId);
  return res.data;
}

export const dryRun = () => localStorage.getItem("dryrun") === "1";
export function setDryRun(on) { localStorage.setItem("dryrun", on ? "1" : "0"); changed(); }

export const label = (id) => `${id.address.slice(0, 8)}…${id.address.slice(-4)}`;

// open shows the Connect modal. Resolves with the identity, or null if closed
// without one.
export function open() {
  return new Promise((resolve) => {
    const dlg = document.createElement("dialog");
    dlg.className = "modal";
    document.body.append(dlg);
    const draw = (msg = "") => {
      const id = get();
      dlg.innerHTML = `
        <form method="dialog">
          <h3>Connect</h3>
          <p class="current">${id
            ? `Acting as <code>${esc(id.address)}</code> <span class="tag">${id.mode === "adena" ? "from Adena" : "entered by hand"}</span>`
            : '<span class="muted">Not connected: reads work, writes need an address.</span>'}</p>
          <h4>With a wallet</h4>
          ${hasAdena()
            ? `<p><button type="button" data-adena class="primary">Connect Adena</button>
                 <span class="muted">transactions are signed in the wallet</span></p>`
            : `<p class="muted">Adena is the gno.land browser wallet, the smoothest way to use these apps.
                 <a href="https://adena.app" target="_blank" rel="noopener">Install Adena ↗</a>, then reload.</p>`}
          <h4>Without a wallet</h4>
          <p class="muted">Give your address and every write becomes a ready-to-paste
            <a href="https://docs.gno.land/users/interact-with-gnokey" target="_blank" rel="noopener">gnokey</a> command, its gas measured for you.</p>
          <div class="row">
            <input name="addr" placeholder="g1…" size="44" autocomplete="off" spellcheck="false" value="${id?.mode === "manual" ? esc(id.address) : ""}">
            <input name="key" placeholder="gnokey key name" size="14" autocomplete="off" spellcheck="false" value="${esc(localStorage.getItem("gnokey.key") || "")}">
            <button type="button" data-manual>Use this address</button>
          </div>
          <p class="err" data-msg>${esc(msg)}</p>
          <div class="row">
            ${id ? '<button type="button" data-off>Disconnect</button>' : ""}
            <span class="spacer"></span>
            <button value="close">Done</button>
          </div>
        </form>`;
      const f = dlg.querySelector("form").elements;
      dlg.querySelector("[data-adena]")?.addEventListener("click", async () => {
        try { await connectAdena(); draw(); } catch (e) { draw(e.message); }
      });
      dlg.querySelector("[data-manual]").addEventListener("click", () => {
        const a = f.addr.value.trim();
        if (!ADDR.test(a)) return draw("that is not a g1 address");
        setKey(f.key.value.trim());
        set("manual", a);
        draw();
      });
      dlg.querySelector("[data-off]")?.addEventListener("click", () => { set(null); draw(); });
    };
    dlg.addEventListener("close", () => { dlg.remove(); resolve(get()); });
    draw();
    dlg.showModal();
  });
}
