// Adena, the gno.land browser wallet, injects `window.adena`. Reads never need
// it; only a transaction does. Gas is left out of every message on purpose: the
// wallet simulates and sizes it, and shows it to the user before signing.

const adena = () => window.adena;

export const hasWallet = () => Boolean(adena());

let account = null;

export async function connect() {
  if (!adena()) throw new Error("Adena is not installed: https://adena.app");
  await adena().AddEstablish("moul's gno dapps");
  const res = await adena().GetAccount();
  if (res.status !== "success") throw new Error(res.message || "wallet refused");
  account = res.data;
  return account;
}

export const current = () => account;

// call sends one MsgCall. args are strings, without the `cur realm` parameter.
export async function call(chainId, pkgPath, func, args = [], send = "") {
  const acc = account || (await connect());
  if (acc.chainId !== chainId) {
    if (adena().SwitchNetwork) {
      const sw = await adena().SwitchNetwork(chainId);
      if (sw.status !== "success") throw new Error(`switch the wallet to ${chainId} first`);
      account = (await adena().GetAccount()).data;
    } else {
      throw new Error(`the wallet is on ${acc.chainId}, this page on ${chainId}`);
    }
  }
  const res = await adena().DoContract({
    messages: [{ type: "/vm.m_call", value: { caller: account.address, send, pkg_path: pkgPath, func, args } }],
  });
  if (res.status !== "success") throw new Error(res.message || res.type || "transaction failed");
  return res.data;
}

// result decodes what the called function returned, e.g. `("Yes." string)`,
// from the DoContract answer. Empty when the wallet did not hand it back.
export function result(tx) {
  const d = tx?.deliverTx?.ResponseBase?.Data ?? tx?.deliverTx?.Data ?? tx?.deliverTx?.data;
  if (!d) return "";
  try {
    return new TextDecoder().decode(Uint8Array.from(atob(d), (c) => c.charCodeAt(0)));
  } catch {
    return "";
  }
}
