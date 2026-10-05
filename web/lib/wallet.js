// How a write leaves the page. Reads never come here.
//   dry run     simulate as the connected address, show the result, send nothing
//   adena       the wallet signs; gas is left out on purpose, the wallet sizes it
//   by hand     a modal with the gnokey command to paste, gas measured (lib/gnokey.js)
// Who the page acts for is lib/identity.js's.

import * as gnokey from "./gnokey.js";
import * as identity from "./identity.js";
import * as simview from "./simview.js";
import { Client, NETWORKS } from "./gno.js";

const adena = () => window.adena;

export const current = () => identity.get();

// describe says what happened, for a status line.
export function describe(tx) {
  if (tx.simulated) return tx.error ? `dry run: would fail, ${tx.error}` : "dry run: nothing was sent";
  return tx.manual ? "sent with gnokey, refreshing" : `included at height ${tx.height}`;
}

// call sends one MsgCall. args are strings, without the `cur realm` parameter.
// slot is where a dry run draws its result.
export async function call(net, pkgPath, func, args = [], send = "", { slot } = {}) {
  const cfg = NETWORKS[net];
  let id = identity.get();

  if (identity.dryRun()) {
    if (!id) id = await identity.open();
    if (!id) throw new Error("connect an address to dry run as");
    if (send) throw new Error("a dry run cannot carry coins yet");
    const sim = await new Client(net).simulate(id.address, pkgPath, func, args);
    simview.render(slot, { func, args, caller: id.address, net, sim });
    return { simulated: true, data: sim.data, error: sim.error };
  }

  if (id?.mode !== "adena" || !adena()) {
    return gnokey.open({ net, cfg, pkgPath, func, args, send, address: id?.address || "", key: id?.key || "" });
  }

  if (id.chainId !== cfg.chainId) {
    if (adena().SwitchNetwork) {
      const sw = await adena().SwitchNetwork(cfg.chainId);
      if (sw.status !== "success") throw new Error(`switch the wallet to ${cfg.chainId} first`);
    }
    id = { ...id, ...(await identity.connectAdena()) };
    if (id.chainId !== cfg.chainId) throw new Error(`the wallet is on ${id.chainId}, this page on ${cfg.chainId}`);
  }
  const res = await adena().DoContract({
    messages: [{ type: "/vm.m_call", value: { caller: id.address, send, pkg_path: pkgPath, func, args } }],
  });
  if (res.status !== "success") throw new Error(res.message || res.type || "transaction failed");
  return res.data;
}

// result decodes what the called function returned, e.g. `("Yes." string)`.
// Empty when the wallet did not hand it back.
export function result(tx) {
  if (tx?.simulated) return tx.data || "";
  const d = tx?.deliverTx?.ResponseBase?.Data ?? tx?.deliverTx?.Data ?? tx?.deliverTx?.data;
  if (!d) return "";
  try {
    return new TextDecoder().decode(Uint8Array.from(atob(d), (c) => c.charCodeAt(0)));
  } catch {
    return "";
  }
}
