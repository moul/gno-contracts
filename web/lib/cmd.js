// The gnokey command a transaction would need, as a string. No DOM, no
// storage, no network: a browser cannot run gnokey, so the only honest
// "gnokey support" a page can offer is the exact command to paste, and that
// is a pure function of the call.
//
// Split out of lib/gnokey.js (which owns the modal, and reads localStorage) so
// the builder can be unit-tested under node and reused by any app that wants
// to show the command inline rather than behind a modal.

const GAS_HEADROOM = 1.3; // gas_wanted over measured use; a ceiling, not charged
const FEE_PER_GAS_DEN = 1000; // the ante handler wants gas_fee >= gas_wanted / 1000 ugnot
const FEE_MARGIN = 2; // fee over that floor; still a few thousandths of a GNOT

// sh quotes one argument for a POSIX shell, leaving the plain ones bare so the
// command stays readable.
export const sh = (s) => (/^[\w./:@=-]+$/.test(s) ? s : `'${String(s).replace(/'/g, `'\\''`)}'`);

// gasFor turns a measured gas figure into the pair the command carries. Never
// call it with a number the chain did not report: the whole point of measuring
// is that the command does not guess.
export function gasFor(gasUsed) {
  const gasWanted = Math.ceil(gasUsed * GAS_HEADROOM);
  return { gasWanted, gasFee: Math.ceil(gasWanted / FEE_PER_GAS_DEN) * FEE_MARGIN };
}

// command renders `gnokey maketx call`, one flag per line. Without a measured
// gasWanted it says so in place of a number rather than inventing one, and
// gasHint says where the measurement comes from, which differs between the
// modal (an address field of its own) and a page that already has one.
export function command({ net, cfg, pkgPath, func, args, send, key, gasWanted, gasFee, gasHint = "enter your address above" }) {
  const lines = [
    "gnokey maketx call",
    `-pkgpath ${pkgPath}`,
    `-func ${func}`,
    ...args.map((a) => `-args ${sh(a)}`),
    ...(send ? [`-send ${send}`] : []),
    gasWanted ? `-gas-wanted ${gasWanted} -gas-fee ${gasFee}ugnot` : `-gas-wanted <measure it: ${gasHint}> -gas-fee <same>`,
    `-broadcast -chainid ${cfg.chainId} -remote ${cfg.rpc}`,
    key || "mykey",
  ];
  return `# ${net}\n` + lines.join(" \\\n  ");
}
