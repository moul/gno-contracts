// The small-grants surface: one page that can manage several grant desks.
//
// It is the apps/smallgrants.js app with a chooser bolted on top: a dropdown of
// known desks (from grants.json, so adding one is an edit not a rewrite), a box
// to type any realm path, and a network selector. The desk and the network both
// live in the URL and in localStorage, so a reload lands on the same desk and a
// pasted link points at exactly what the sender was looking at. Which network
// is being read is shown in plain words, because testnet data dressed as
// mainnet is the one answer worse than no answer.

import { Client, NETWORKS } from "./lib/gno.js";
import * as wallet from "./lib/wallet.js";
import * as identity from "./lib/identity.js";
import { mount as mountGrants } from "./apps/smallgrants.js";

const $ = (s) => document.querySelector(s);
const deskSel = $("#desk");
const realmInput = $("#realm");
const realmField = $(".deskpath");
const netSel = $("#net");
const badge = $("#netbadge");
const note = $("#netnote");
const slot = $("#grants");
const connectBtn = $("#connect");
const dryBtn = $("#dryrun");

// Which networks are testnets vs the real one. A network the config has never
// heard of is treated as a testnet: the safe assumption is "not mainnet".
const kind = (net) => (net === "mainnet" ? "mainnet" : net === "local" ? "local" : "testnet");
const KIND_LABEL = { mainnet: "MAINNET", testnet: "TESTNET", local: "LOCAL" };

// Built-in fallback, used only if grants.json cannot be read, so the page still
// opens on something rather than a blank chooser.
const FALLBACK = { default: "gno.land/r/moul/smallgrants/v0", desks: [{ label: "Small grants", path: "gno.land/r/moul/smallgrants/v0", network: "onyx" }] };

let config = FALLBACK;
let net = "mainnet";
let realm = FALLBACK.default;
let client = null;
let unmount = null;

// -------------------------------------------------- state in the URL + storage

const params = () => new URLSearchParams(location.search);

function readInitial() {
  const p = params();
  const deskFor = (path) => config.desks.find((d) => d.path === path);
  realm = p.get("realm") || localStorage.getItem("grants.realm") || config.default || FALLBACK.default;
  // Network precedence: an explicit ?net wins; then what was last used; then the
  // network the chosen desk names; then mainnet. A desk names where it lives, so
  // opening a testnet desk reads the testnet, not mainnet, by default.
  net = p.get("net") || localStorage.getItem("grants.net") || deskFor(realm)?.network || "mainnet";
  if (!NETWORKS[net]) net = "mainnet";
}

function syncState() {
  const p = params();
  p.set("realm", realm);
  p.set("net", net);
  history.replaceState(null, "", `${location.pathname}?${p.toString()}`);
  localStorage.setItem("grants.realm", realm);
  localStorage.setItem("grants.net", net);
}

// -------------------------------------------------- chooser

const OTHER = "__other__";

function buildNetSelect() {
  netSel.innerHTML = "";
  for (const name of Object.keys(NETWORKS)) {
    netSel.add(new Option(`${name} (${NETWORKS[name].chainId})`, name));
  }
  netSel.value = net;
}

function buildDeskSelect() {
  deskSel.innerHTML = "";
  for (const d of config.desks) deskSel.add(new Option(d.label, d.path));
  deskSel.add(new Option("Other realm…", OTHER));
  const known = config.desks.some((d) => d.path === realm);
  deskSel.value = known ? realm : OTHER;
  realmField.hidden = known;
  realmInput.value = known ? "" : realm;
}

function drawBadge() {
  const k = kind(net);
  badge.textContent = `${KIND_LABEL[k]} · ${NETWORKS[net].chainId}`;
  badge.className = `netbadge ${k}`;
  // A loud strip on anything that is not mainnet: the reader should never have
  // to infer it from a chain id in the corner.
  if (k === "mainnet") {
    note.className = "";
    note.innerHTML = "";
  } else {
    note.className = `netnote ${k}`;
    note.innerHTML = k === "local"
      ? `Reading a <b>local</b> node (<code>${esc(NETWORKS[net].rpc)}</code>). Nothing here is on a public chain.`
      : `Reading <b>${esc(net)}</b>, a <b>testnet</b> (<code>${esc(NETWORKS[net].chainId)}</code>). This is <b>not mainnet</b>: the GNOT here is test coin and the desk is a preview.`;
  }
}

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

// -------------------------------------------------- header (connect + dry run)

const drawHeader = (id = identity.get()) => {
  connectBtn.textContent = id ? `${identity.label(id)} · ${id.mode === "adena" ? "Adena" : "by hand"}` : "Connect";
  connectBtn.classList.toggle("on", Boolean(id));
  dryBtn.setAttribute("aria-pressed", String(identity.dryRun()));
  document.body.classList.toggle("dryrun", identity.dryRun());
};
connectBtn.addEventListener("click", () => identity.open());
dryBtn.addEventListener("click", () => identity.setDryRun(!identity.dryRun()));
identity.onChange(drawHeader);

// -------------------------------------------------- mount

function remount() {
  if (unmount) { unmount(); unmount = null; }
  client = new Client(net);
  slot.innerHTML = "";
  drawBadge();
  syncState();
  unmount = mountGrants(slot, {
    client, net, path: realm, wallet,
    call: (func, a = [], opts = {}) => {
      if (typeof opts === "string") throw new Error("call(func, args, { send, onSubmit }): pass the amount as { send }");
      return wallet.call(net, realm, func, a, opts.send || "", { slot: $("#sim-slot"), onSubmit: opts.onSubmit });
    },
  });
}

function pickDesk(value) {
  if (value === OTHER) {
    realmField.hidden = false;
    realmInput.focus();
    return; // nothing mounts until a path is typed
  }
  realmField.hidden = true;
  realm = value;
  const d = config.desks.find((x) => x.path === value);
  if (d?.network && NETWORKS[d.network]) { net = d.network; netSel.value = net; }
  remount();
}

function applyTypedRealm() {
  const typed = realmInput.value.trim();
  if (!typed || typed === realm) return;
  realm = typed;
  // If the typed path happens to be a known desk, reflect that in the dropdown.
  const known = config.desks.find((d) => d.path === typed);
  deskSel.value = known ? typed : OTHER;
  if (known?.network && NETWORKS[known.network]) { net = known.network; netSel.value = net; }
  remount();
}

deskSel.addEventListener("change", () => pickDesk(deskSel.value));
realmInput.addEventListener("change", applyTypedRealm);
realmInput.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); applyTypedRealm(); } });
netSel.addEventListener("change", () => { net = netSel.value; remount(); });

// A link pasted into a new tab, or the back button, should reselect the desk.
window.addEventListener("popstate", () => { readInitial(); buildDeskSelect(); netSel.value = net; remount(); });

// -------------------------------------------------- boot

async function boot() {
  try {
    const res = await fetch("./grants.json", { cache: "no-cache" });
    const json = await res.json();
    if (json && Array.isArray(json.desks) && json.desks.length) config = json;
  } catch { /* keep FALLBACK */ }
  readInitial();
  buildNetSelect();
  buildDeskSelect();
  drawHeader();
  remount();
}

boot();
