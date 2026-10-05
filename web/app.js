// The dashboard: one page, hash-routed, no build step.
//   #/                       the list: featured dapps, then every realm
//   #/r/<path>[:<args>]      one realm: its custom page if it has one, then
//                            Render, Functions, Source

import { Client, NETWORKS, goLiteral, isRealmParam } from "./lib/gno.js";
import { render as renderMD, makeLinker } from "./lib/md.js";
import * as wallet from "./lib/wallet.js";
import { FEATURED } from "./apps/index.js";

const CATALOG = "https://raw.githubusercontent.com/moul/gno-contracts/main/contracts.json";
const REPO = "https://github.com/moul/gno-contracts/tree/main/";

const main = document.querySelector("main");
const netSelect = document.querySelector("#net");
const walletBtn = document.querySelector("#wallet");

let net = new URLSearchParams(location.search).get("net") || localStorage.getItem("net") || "mainnet";
if (!NETWORKS[net]) net = "mainnet";
let client = new Client(net);
let unmount = null;
let catalog = null;

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const h = (html) => Object.assign(document.createElement("div"), { innerHTML: html }).firstElementChild;
const short = (p) => p.replace(/^gno\.land/, "");
const LIVE = '<span class="live" title="A custom interactive app: try it">⚡ live app</span>';
const CUSTOM = new Set(FEATURED.filter((a) => a.module).map((a) => a.path));

for (const name of Object.keys(NETWORKS)) netSelect.add(new Option(`${name} (${NETWORKS[name].chainId})`, name));
netSelect.value = net;
netSelect.addEventListener("change", () => {
  net = netSelect.value;
  localStorage.setItem("net", net);
  client = new Client(net);
  route();
});

walletBtn.addEventListener("click", async () => {
  try {
    const acc = await wallet.connect();
    walletBtn.textContent = `${acc.address.slice(0, 8)}…${acc.address.slice(-4)} · ${acc.chainId}`;
  } catch (e) {
    alert(e.message);
  }
});
if (!wallet.hasWallet()) walletBtn.title = "Install Adena to send transactions";

async function loadCatalog() {
  if (catalog) return catalog;
  try {
    const res = await fetch(CATALOG);
    catalog = (await res.json()).contracts.filter((c) => c.kind === "r" && !c.superseded && !c.draft);
  } catch {
    catalog = [];
  }
  return catalog;
}

const live = (c) => net === "local" || c.published?.[net]?.uploaded;

// ---------------------------------------------------------------- list

async function viewHome() {
  main.innerHTML = `
    <section><h2>Featured</h2>
      <p class="muted">${LIVE} marks a custom interactive app: live data, buttons wired to your wallet. The rest open in the generic view.</p>
      <div class="grid" id="featured"></div></section>
    <section>
      <h2>Every realm <span class="muted" id="count"></span></h2>
      <input id="filter" placeholder="filter: counter, x/daily, amm…" autocomplete="off">
      <ul class="catalog" id="all"></ul>
    </section>`;

  const byPath = new Map((await loadCatalog()).map((c) => [c.pkgpath, c]));
  for (const app of FEATURED) {
    const c = byPath.get(app.path);
    const off = c && !live(c);
    main.querySelector("#featured").append(h(`
      <a class="card${app.module ? " app" : ""}${off ? " off" : ""}" href="#${short(app.path)}">
        <div><strong>${esc(app.title)}</strong>${app.module ? ` ${LIVE}` : ""}</div>
        <span class="muted">${esc(app.blurb || c?.description || "")}</span>
        <code>${esc(short(app.path))}</code>
        ${off ? `<span class="tag warn">not on ${net}</span>` : ""}
      </a>`));
  }

  const list = main.querySelector("#all");
  const draw = (q) => {
    const rows = [...byPath.values()].filter((c) => live(c) && c.pkgpath.includes(q))
      .sort((a, b) => CUSTOM.has(b.pkgpath) - CUSTOM.has(a.pkgpath));
    main.querySelector("#count").textContent = `${rows.length} on ${net}`;
    list.innerHTML = rows.map((c) =>
      `<li><a href="#${short(c.pkgpath)}">${esc(short(c.pkgpath))}</a>${CUSTOM.has(c.pkgpath) ? ` ${LIVE}` : ""} <span class="muted">${esc(c.description || "")}</span></li>`).join("");
  };
  main.querySelector("#filter").addEventListener("input", (e) => draw(e.target.value.trim()));
  draw("");
}

// ---------------------------------------------------------------- one realm

async function viewRealm(route) {
  const [p, ...rest] = route.split(":");
  const pkgpath = "gno.land" + p;
  const args = decodeURIComponent(rest.join(":"));
  const app = FEATURED.find((a) => a.path === pkgpath);
  const web = NETWORKS[net].web;
  const entry = (await loadCatalog()).find((c) => c.pkgpath === pkgpath);

  main.innerHTML = `
    <nav class="crumbs"><a href="#/">← all dapps</a>
      <code>${esc(short(pkgpath))}${args ? ":" + esc(args) : ""}</code>
      <a href="${web}${short(pkgpath)}${args ? ":" + esc(args) : ""}" target="_blank" rel="noopener">gnoweb ↗</a>
      ${entry ? `<a href="${REPO}${esc(entry.dir)}" target="_blank" rel="noopener">repo ↗</a>` : ""}
    </nav>
    ${app?.module ? '<section class="custom" id="custom"></section>' : ""}
    <div class="tabs"><button data-tab="render" class="on">Render</button><button data-tab="funcs">Functions</button><button data-tab="source">Source</button></div>
    <section id="pane"></section>`;

  if (app?.module) {
    const mod = await import(`./apps/${app.module}.js`);
    unmount = mod.mount(main.querySelector("#custom"), {
      client, net, path: pkgpath,
      wallet,
      call: (func, a = [], send = "") => wallet.call(NETWORKS[net].chainId, pkgpath, func, a, send),
    });
  }

  const pane = main.querySelector("#pane");
  const tabs = { render: () => paneRender(pane, pkgpath, args), funcs: () => paneFuncs(pane, pkgpath), source: () => paneSource(pane, pkgpath) };
  main.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => {
    main.querySelectorAll(".tabs button").forEach((x) => x.classList.toggle("on", x === b));
    tabs[b.dataset.tab]();
  }));
  tabs.render();
}

async function paneRender(pane, pkgpath, args) {
  pane.innerHTML = '<p class="muted">rendering…</p>';
  try {
    const md = await client.render(pkgpath, args);
    pane.innerHTML = `<article class="md">${renderMD(md, makeLinker(pkgpath, NETWORKS[net].web))}</article>`;
  } catch (e) {
    pane.innerHTML = `<p class="err">${esc(e.message)}</p>`;
  }
}

async function paneFuncs(pane, pkgpath) {
  pane.innerHTML = '<p class="muted">loading…</p>';
  let funcs;
  try {
    funcs = (await client.funcs(pkgpath)).filter((f) => f.FuncName !== "Render");
  } catch (e) {
    pane.innerHTML = `<p class="err">${esc(e.message)}</p>`;
    return;
  }
  pane.innerHTML = funcs.length ? "" : '<p class="muted">no exported function</p>';
  for (const f of funcs) {
    const params = f.Params || [];
    const crossing = params.length > 0 && isRealmParam(params[0]);
    const inputs = params.filter((x) => !isRealmParam(x));
    const results = (f.Results || []).map((r) => r.Type).join(", ");
    const form = h(`
      <form class="func">
        <div><strong>${esc(f.FuncName)}</strong>(${inputs.map((x) => `${esc(x.Name)} <span class="muted">${esc(x.Type.replace(".uverse.", ""))}</span>`).join(", ")})
          ${results ? `<span class="muted">→ ${esc(results)}</span>` : ""} ${crossing ? '<span class="tag">tx</span>' : '<span class="tag">read</span>'}</div>
        <div class="row">${inputs.map((x) => `<input name="${esc(x.Name)}" placeholder="${esc(x.Name)}">`).join("")}
          ${crossing ? "<button>Send tx</button>" : "<button>Query</button>"}</div>
        <pre class="out" hidden></pre>
      </form>`);
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const out = form.querySelector(".out");
      out.hidden = false;
      out.textContent = "…";
      const values = inputs.map((x) => form.elements[x.Name].value);
      try {
        if (crossing) {
          const tx = await wallet.call(NETWORKS[net].chainId, pkgpath, f.FuncName, values);
          out.textContent = `included at height ${tx.height}\nhash ${tx.hash}`;
        } else {
          const lits = inputs.map((x, i) => goLiteral(values[i], x.Type.replace(".uverse.", "")));
          out.textContent = await client.eval(pkgpath, `${f.FuncName}(${lits.join(", ")})`);
        }
      } catch (e) {
        out.textContent = e.message;
      }
    });
    pane.append(form);
  }
}

async function paneSource(pane, pkgpath) {
  pane.innerHTML = '<p class="muted">loading…</p>';
  try {
    // Every file on one page, in reading order: code, then tests, then the rest.
    const rank = (f) => (f.endsWith("_test.gno") ? 1 : f.endsWith(".gno") ? 0 : 2);
    const files = (await client.file(pkgpath)).split("\n").filter(Boolean)
      .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
    const bodies = await Promise.all(files.map((f) => client.file(`${pkgpath}/${f}`)));
    pane.innerHTML = files.map((f, i) => `
      <section class="file"><h3 id="src-${esc(f)}">${esc(f)} <span class="muted">${bodies[i].split("\n").length} lines</span></h3>
      <pre class="src">${esc(bodies[i])}</pre></section>`).join("");
  } catch (e) {
    pane.innerHTML = `<p class="err">${esc(e.message)}</p>`;
  }
}

// ---------------------------------------------------------------- router

function route() {
  if (unmount) unmount();
  unmount = null;
  const hash = decodeURI(location.hash.slice(1)) || "/";
  window.scrollTo(0, 0);
  if (/^\/[rp]\//.test(hash)) viewRealm(hash);
  else viewHome();
}

window.addEventListener("hashchange", route);
route();
