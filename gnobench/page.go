package main

// htmlPage is the generated dashboard. It is self-contained: no network, no
// libraries, the whole dataset inlined as JSON and the SVG drawn in the page.
//
// Every chart carries one series. There are more candidates than there are
// categorical hues that survive a colour-blindness check, so identity is
// carried by position and a direct label on every mark, and colour carries
// only "this is the data".
const htmlPage = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>gnobench</title>
<style>
:root {
  color-scheme: light;
  --plane:#f9f9f7; --surface:#fcfcfb; --ink:#0b0b0b; --ink-2:#52514e;
  --muted:#898781; --grid:#e1e0d9; --axis:#c3c2b7; --border:rgba(11,11,11,0.10);
  --series:#2a78d6; --warn:#d03b3b; --warnbg:rgba(208,59,59,0.09);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --plane:#0d0d0d; --surface:#1a1a19; --ink:#fff; --ink-2:#c3c2b7;
    --muted:#898781; --grid:#2c2c2a; --axis:#383835; --border:rgba(255,255,255,0.10);
    --series:#3987e5; --warn:#e66767; --warnbg:rgba(230,103,103,0.12);
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --plane:#0d0d0d; --surface:#1a1a19; --ink:#fff; --ink-2:#c3c2b7;
  --muted:#898781; --grid:#2c2c2a; --axis:#383835; --border:rgba(255,255,255,0.10);
  --series:#3987e5; --warn:#e66767; --warnbg:rgba(230,103,103,0.12);
}
* { box-sizing:border-box; }
body { margin:0; padding:24px 20px 72px; background:var(--plane); color:var(--ink);
  font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }
.wrap { max-width:1140px; margin:0 auto; }
h1 { font-size:26px; margin:0 0 6px; letter-spacing:-0.01em; }
h2 { font-size:17px; margin:0 0 4px; letter-spacing:-0.01em; }
h3 { font-size:14px; margin:16px 0 6px; color:var(--ink-2); font-weight:600; }
p.sub { color:var(--ink-2); margin:0 0 20px; font-size:14px; }
p.note { color:var(--ink-2); margin:0 0 14px; font-size:13px; }
code { font-size:0.92em; }
.card { background:var(--surface); border:1px solid var(--border); border-radius:10px;
  padding:18px; margin-bottom:20px; }
.warn { border-color:var(--warn); background:var(--warnbg); }
.warn b { color:var(--warn); }
.tiles { display:grid; grid-template-columns:repeat(auto-fit,minmax(215px,1fr)); gap:12px; margin-bottom:20px; }
.tile { background:var(--surface); border:1px solid var(--border); border-radius:10px; padding:14px 16px; }
.tile .big { font-size:29px; line-height:1.1; letter-spacing:-0.02em; }
.tile .cap { font-size:12.5px; color:var(--ink-2); margin-top:4px; }
.controls { display:flex; flex-wrap:wrap; gap:14px; align-items:flex-end; margin-bottom:14px; }
.ctl { display:flex; flex-direction:column; gap:5px; }
.ctl > span { font-size:11px; text-transform:uppercase; letter-spacing:0.06em; color:var(--muted); }
select, button.chip { font:inherit; font-size:13px; color:var(--ink); background:var(--surface);
  border:1px solid var(--border); border-radius:7px; padding:6px 9px; }
button.chip { cursor:pointer; }
button.chip[aria-pressed="true"] { background:var(--series); border-color:var(--series); color:#fff; }
.facets { display:flex; flex-wrap:wrap; gap:16px; margin-bottom:6px; }
.facet { display:flex; flex-direction:column; gap:5px; }
.facet > span { font-size:11px; text-transform:uppercase; letter-spacing:0.06em; color:var(--muted); }
.facet .row { display:flex; flex-wrap:wrap; gap:5px; }
.chips { display:flex; flex-wrap:wrap; gap:6px; margin-bottom:14px; }
.scroll { overflow-x:auto; }
svg { display:block; max-width:100%; }
svg text { fill:var(--ink-2); }
.tick { fill:var(--muted); font-size:11px; }
.lab { fill:var(--ink); font-size:12px; }
.val { fill:var(--ink-2); font-size:11px; font-variant-numeric:tabular-nums; }
.mark { fill:var(--series); }
.mark:hover,.mark:focus { opacity:.78; }
.grid { stroke:var(--grid); stroke-width:1; }
.axis { stroke:var(--axis); stroke-width:1; }
.small { display:grid; grid-template-columns:repeat(auto-fill,minmax(180px,1fr)); gap:12px; }
.small figure { margin:0; }
.small figcaption { font-size:12px; color:var(--ink); margin-bottom:2px; word-break:break-all; }
.small .cap2 { font-size:11px; color:var(--muted); }
table { border-collapse:collapse; width:100%; font-size:12.5px; font-variant-numeric:tabular-nums; }
th,td { text-align:right; padding:5px 8px; border-bottom:1px solid var(--grid); white-space:nowrap; }
th:first-child,td:first-child { text-align:left; }
th { color:var(--muted); font-weight:600; font-size:11px; text-transform:uppercase; letter-spacing:.05em; }
.tip { position:fixed; pointer-events:none; opacity:0; transition:opacity .1s; background:var(--ink);
  color:var(--plane); font-size:12px; padding:6px 9px; border-radius:6px; z-index:10; max-width:280px; }
details > summary { cursor:pointer; color:var(--ink-2); font-size:13px; margin:8px 0; }
</style>
</head>
<body>
<div class="wrap">
  <h1 id="title"></h1>
  <p class="sub" id="blurb"></p>

  <div class="card" id="envcard"></div>
  <div class="tiles" id="tiles"></div>

  <div class="card">
    <div class="controls" id="controls"></div>
    <div class="facets" id="facets"></div>
    <p class="note" id="filternote"></p>
  </div>

  <div class="card">
    <h2>One transaction, one operation</h2>
    <p class="note">
      Cold: the container was committed by an earlier transaction and this one touches it once.
      <b>This is what a realm pays per call.</b> A container held in a single persisted object has
      to be deserialised whole on first touch, which a warm benchmark never shows.
    </p>
    <div class="chips" id="txops"></div>
    <div class="scroll"><svg id="txbars"></svg></div>
    <div class="scroll" id="txtable"></div>
  </div>

  <div class="card">
    <h2>Warm against cold</h2>
    <p class="note">The same n reads, measured both ways. The ratio is how much a warm benchmark
      flatters each container.</p>
    <div class="scroll"><svg id="wcbars"></svg></div>
  </div>

  <div class="card">
    <h2>The cost frontier</h2>
    <p class="note">Storage per entry against the gas of one cold single-key read. Down and to the
      left is better; anything up and to the right of another mark is dominated by it on both axes.</p>
    <div class="scroll"><svg id="frontier"></svg></div>
    <p class="note" id="fr-note"></p>
  </div>

  <div class="card">
    <h2 id="wl-title">Every workload</h2>
    <p class="note" id="wl-note"></p>
    <div class="chips" id="wlchips"></div>
    <div class="scroll"><svg id="bars"></svg></div>
  </div>

  <div class="card">
    <h2>Scaling</h2>
    <p class="note" id="sc-note"></p>
    <div class="small" id="scaling"></div>
  </div>

  <div class="card">
    <h2>Raw results</h2>
    <p class="note">Every row behind every chart above. <code>d_</code> columns are
      baseline-subtracted.</p>
    <details id="rawdet"><summary>Expand</summary><div class="scroll"><table id="raw"></table></div></details>
  </div>
</div>
<div class="tip" id="tip"></div>
<script>
var DATA = /*DATA*/;
var S = DATA.suite, tip = document.getElementById("tip");

function fmt(n) {
  if (n === null || n === undefined || isNaN(n)) return "";
  var a = Math.abs(n);
  if (a >= 1000) return Math.round(n).toLocaleString("en-US");
  if (a >= 10) return n.toFixed(0);
  return n.toFixed(1);
}
function uniq(a) { var o = []; a.forEach(function (v) { if (o.indexOf(v) < 0) o.push(v); }); return o; }
function el(tag, cls, txt) {
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  if (txt !== undefined) e.textContent = txt;
  return e;
}
function svgEl(name, attrs) {
  var e = document.createElementNS("http://www.w3.org/2000/svg", name);
  for (var k in attrs) e.setAttribute(k, attrs[k]);
  return e;
}
function showTip(e, html) {
  tip.innerHTML = html; tip.style.opacity = 1;
  tip.style.left = Math.min(e.clientX + 14, window.innerWidth - 290) + "px";
  tip.style.top = (e.clientY + 16) + "px";
}
function hideTip() { tip.style.opacity = 0; }

var METRICS = {
  gas: "gas per operation",
  bytes: "bytes per operation",
  held: "bytes the realm holds",
  wall: "milliseconds for the phase"
};
function metricOf(r, m) {
  if (m === "held") return r.bytes;
  if (!r.ops) return null;
  if (m === "gas") return r.d_gas / r.ops;
  if (m === "bytes") return r.d_bytes / r.ops;
  return r.d_wall_ns / 1e6;
}

var state = {
  file: 0, n: null, value: "str", metric: "gas", group: "kv",
  workload: null, txop: null, facets: {}
};

// ---- indexing -------------------------------------------------------------
var IDX = {};
function reindex() {
  IDX = {};
  (DATA.files[state.file].rows || []).forEach(function (r) {
    IDX[r.structure + "|" + r.value + "|" + r.mode + "|" + r.workload + "|" + r.n] = r;
  });
}
function get(structure, value, mode, workload, n) {
  var r = IDX[structure + "|" + value + "|" + mode + "|" + workload + "|" + n];
  if (!r || r.skip || r.err) return null;
  return r;
}
function sizes() {
  return uniq((DATA.files[state.file].rows || []).map(function (r) { return r.n; }))
    .sort(function (a, b) { return a - b; });
}
function structTag(st, key) {
  for (var i = 0; i < st.tags.length; i++) {
    if (st.tags[i].indexOf(key + ":") === 0) return st.tags[i].slice(key.length + 1);
  }
  return null;
}
function passesFacets(st) {
  for (var key in state.facets) {
    var want = state.facets[key];
    if (!want.length) continue;
    var ok = false;
    for (var i = 0; i < want.length; i++) {
      if (st.tags.indexOf(key + ":" + want[i]) >= 0) { ok = true; break; }
    }
    if (!ok) return false;
  }
  return true;
}
function candidates(group, value) {
  return S.structures.filter(function (st) {
    if (group && st.group !== group) return false;
    if (!passesFacets(st)) return false;
    if (value) {
      // a candidate with no row for this value shape simply does not take it
      var any = (DATA.files[state.file].rows || []).some(function (r) {
        return r.structure === st.name && r.value === value;
      });
      if (!any) return false;
    }
    return true;
  });
}

// ---- header ---------------------------------------------------------------
function header() {
  document.getElementById("title").textContent = S.title;
  document.getElementById("blurb").textContent = S.blurb;
  var c = document.getElementById("envcard");
  c.innerHTML = "";
  c.appendChild(el("h2", null, "What produced these numbers"));
  var t = el("table");
  var head = el("tr");
  ["machine", "hardware", "go", "gno revision", "rows", "updated"].forEach(function (h) {
    head.appendChild(el("th", null, h));
  });
  t.appendChild(head);
  DATA.files.forEach(function (f) {
    var tr = el("tr");
    var gno = f.env.gno_commit ? f.env.gno_commit.slice(0, 9) : "unknown";
    if (f.env.gno_commit_date) gno += " (" + f.env.gno_commit_date + ")";
    if (f.env.gno_dirty) gno += " DIRTY";
    var hw = f.env.os + "/" + f.env.arch + ", " + (f.env.cpu || "?") + ", " + f.env.cpus + " cores" +
      (f.env.mem_gb ? ", " + f.env.mem_gb + " GB" : "");
    [f.env.id, hw, f.env.go_version, gno, String(f.rows.length), (f.updated_at || "").slice(0, 10)]
      .forEach(function (v) { tr.appendChild(el("td", null, v)); });
    t.appendChild(tr);
  });
  c.appendChild(t);
  var anyWarn = false;
  DATA.files.forEach(function (f) {
    (f.warnings || []).forEach(function (w) {
      anyWarn = true;
      var d = el("p", "note");
      d.innerHTML = "<b>" + f.env.id + ":</b> " + w;
      c.appendChild(d);
    });
  });
  if (anyWarn) c.classList.add("warn"); else c.classList.remove("warn");
  var gen = el("p", "note", "Generated " + (DATA.generated_at || "").slice(0, 19).replace("T", " ") + " UTC by gnobench report.");
  c.appendChild(gen);
}

// ---- controls -------------------------------------------------------------
function selector(label, values, labels, cur, onChange) {
  var w = el("label", "ctl");
  w.appendChild(el("span", null, label));
  var s = el("select");
  values.forEach(function (v, i) {
    var o = el("option", null, labels ? labels[i] : String(v));
    o.value = String(v);
    if (String(cur) === String(v)) o.selected = true;
    s.appendChild(o);
  });
  s.onchange = function () { onChange(s.value); };
  w.appendChild(s);
  return w;
}

function controls() {
  var c = document.getElementById("controls");
  c.innerHTML = "";
  if (DATA.files.length > 1) {
    c.appendChild(selector("Machine", DATA.files.map(function (_, i) { return i; }),
      DATA.files.map(function (f) { return f.env.id; }), state.file, function (v) {
        state.file = parseInt(v, 10); reindex(); render();
      }));
  }
  var groups = uniq(S.structures.map(function (st) { return st.group; }));
  if (groups.indexOf(state.group) < 0) state.group = groups[0];
  if (groups.length > 1) {
    c.appendChild(selector("Group", groups, null, state.group, function (v) {
      state.group = v; state.workload = null; state.txop = null; render();
    }));
  }
  var ns = sizes();
  if (state.n === null || ns.indexOf(state.n) < 0) state.n = ns[ns.length - 1];
  c.appendChild(selector(S.size_label || "Entries (n)", ns, null, state.n,
    function (v) { state.n = parseInt(v, 10); render(); }));
  var vals = uniq((DATA.files[state.file].rows || []).map(function (r) { return r.value; }));
  if (vals.indexOf(state.value) < 0) state.value = vals[0];
  if (vals.length > 1) {
    c.appendChild(selector("Value shape", vals,
      vals.map(function (v) { return v === "obj" ? "live object" : "encoded string"; }),
      state.value, function (v) { state.value = v; render(); }));
  }
  c.appendChild(selector("Metric", ["gas", "bytes", "held", "wall"],
    ["gas per op", "bytes per op", "bytes held", "phase ms"], state.metric,
    function (v) { state.metric = v; render(); }));

  var fc = document.getElementById("facets");
  fc.innerHTML = "";
  S.facets.forEach(function (f) {
    var present = [];
    S.structures.forEach(function (st) {
      st.tags.forEach(function (t) {
        if (t.indexOf(f.key + ":") === 0) {
          var v = t.slice(f.key.length + 1);
          if (present.indexOf(v) < 0) present.push(v);
        }
      });
    });
    var order = f.values.filter(function (v) { return present.indexOf(v) >= 0; });
    present.forEach(function (v) { if (order.indexOf(v) < 0) order.push(v); });
    if (!order.length) return;
    var box = el("div", "facet");
    box.appendChild(el("span", null, f.label));
    var row = el("div", "row");
    order.forEach(function (v) {
      var b = el("button", "chip", v);
      var on = (state.facets[f.key] || []).indexOf(v) >= 0;
      b.setAttribute("aria-pressed", on);
      b.onclick = function () {
        var cur = state.facets[f.key] || [];
        var i = cur.indexOf(v);
        if (i < 0) cur = cur.concat([v]); else cur = cur.slice(0, i).concat(cur.slice(i + 1));
        state.facets[f.key] = cur;
        render();
      };
      row.appendChild(b);
    });
    box.appendChild(row);
    fc.appendChild(box);
  });

  var active = [];
  for (var k in state.facets) if ((state.facets[k] || []).length) {
    active.push(k + " = " + state.facets[k].join(" or "));
  }
  var shown = candidates(state.group, state.value).length;
  document.getElementById("filternote").textContent = active.length
    ? shown + " candidate(s) match " + active.join(", ") + ". Click a chip again to clear it."
    : shown + " candidate(s). Click a chip to narrow by capability.";
}

// ---- charts ---------------------------------------------------------------
function bars(svgId, rows, caption) {
  var svg = document.getElementById(svgId);
  svg.innerHTML = "";
  if (!rows.length) { svg.setAttribute("height", 0); return; }
  rows = rows.slice().sort(function (a, b) { return a.v - b.v; });
  var padL = 250, padR = 86, padT = 8, rowH = 26, barH = 14;
  var w = Math.max(620, Math.min(1080, svg.parentNode.clientWidth || 940));
  var h = padT + rows.length * rowH + 26;
  svg.setAttribute("width", w); svg.setAttribute("height", h);
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  var lo = Math.min(0, Math.min.apply(null, rows.map(function (r) { return r.v; })));
  var hi = Math.max(0, Math.max.apply(null, rows.map(function (r) { return r.v; })));
  if (hi === lo) hi = lo + 1;
  var plotW = w - padL - padR;
  var zero = padL + (0 - lo) / (hi - lo) * plotW;
  var X = function (v) { return padL + (v - lo) / (hi - lo) * plotW; };
  svg.appendChild(svgEl("line", { x1: zero, x2: zero, y1: padT, y2: padT + rows.length * rowH, class: "axis" }));
  rows.forEach(function (r, i) {
    var y = padT + i * rowH + (rowH - barH) / 2;
    var x0 = Math.min(zero, X(r.v)), x1 = Math.max(zero, X(r.v));
    var rect = svgEl("rect", { x: x0, y: y, width: Math.max(1, x1 - x0), height: barH, rx: 4, class: "mark", tabindex: 0 });
    rect.addEventListener("mousemove", function (e) { showTip(e, "<b>" + r.name + "</b><br>" + r.tip); });
    rect.addEventListener("mouseleave", hideTip);
    svg.appendChild(rect);
    var lab = svgEl("text", { x: padL - 10, y: y + barH - 2, "text-anchor": "end", class: "lab" });
    lab.textContent = r.name;
    svg.appendChild(lab);
    var val = svgEl("text", { x: r.v < 0 ? x0 - 6 : x1 + 6, y: y + barH - 2,
      "text-anchor": r.v < 0 ? "end" : "start", class: "val" });
    val.textContent = fmt(r.v);
    svg.appendChild(val);
  });
  var cap = svgEl("text", { x: padL, y: h - 6, class: "tick" });
  cap.textContent = caption;
  svg.appendChild(cap);
}

function hide(id, on) {
  var e = document.getElementById(id);
  if (e && e.closest) { var c = e.closest(".card"); if (c) c.style.display = on ? "none" : ""; }
}

function txSection() {
  var ops = S.workloads.filter(function (w) {
    return w.group === state.group && w.light && w.baseline;
  });
  hide("txbars", ops.length === 0);
  var chips = document.getElementById("txops");
  chips.innerHTML = "";
  if (!ops.length) { document.getElementById("txbars").innerHTML = ""; document.getElementById("txtable").innerHTML = ""; return; }
  if (!state.txop || !ops.some(function (w) { return w.name === state.txop; })) state.txop = ops[0].name;
  ops.forEach(function (w) {
    var b = el("button", "chip", w.name);
    b.setAttribute("aria-pressed", w.name === state.txop);
    b.title = w.note;
    b.onclick = function () { state.txop = w.name; render(); };
    chips.appendChild(b);
  });
  var rows = [];
  candidates(state.group, state.value).forEach(function (st) {
    var r = get(st.name, state.value, "cold", state.txop, state.n);
    if (!r) return;
    rows.push({ name: st.name, v: r.d_gas / Math.max(r.ops, 1),
      tip: fmt(r.d_gas) + " gas, " + fmt(r.d_bytes) + " bytes, for the whole transaction" });
  });
  var note = (ops.filter(function (w) { return w.name === state.txop; })[0] || {}).note || "";
  bars("txbars", rows, note + " (gas, n = " + state.n.toLocaleString("en-US") + ")");

  var host = document.getElementById("txtable");
  host.innerHTML = "";
  var t = el("table");
  var head = el("tr");
  head.appendChild(el("th", null, "candidate"));
  ops.forEach(function (w) { head.appendChild(el("th", null, w.name)); });
  t.appendChild(head);
  candidates(state.group, state.value).forEach(function (st) {
    var tr = el("tr"), any = false;
    tr.appendChild(el("td", null, st.name));
    ops.forEach(function (w) {
      var r = get(st.name, state.value, "cold", w.name, state.n);
      if (r) { any = true; tr.appendChild(el("td", null, fmt(r.d_gas / Math.max(r.ops, 1)))); }
      else tr.appendChild(el("td", null, "n/a"));
    });
    if (any) t.appendChild(tr);
  });
  host.appendChild(t);
}

function warmCold() {
  var rows = [];
  candidates("kv", state.value).forEach(function (st) {
    var wr = get(st.name, state.value, "warm", "get_hit", state.n);
    var cr = get(st.name, state.value, "cold", "cold_get_all", state.n);
    if (!wr || !cr || !wr.ops || !cr.ops) return;
    var warm = wr.d_gas / wr.ops, cold = cr.d_gas / cr.ops;
    rows.push({ name: st.name, v: warm > 0 ? cold / warm : 0,
      tip: "warm " + fmt(warm) + " gas/read<br>cold " + fmt(cold) + " gas/read" });
  });
  hide("wcbars", rows.length === 0);
  bars("wcbars", rows, "cold gas per read divided by warm gas per read, n = " + state.n.toLocaleString("en-US"));
}

function frontier() {
  var svg = document.getElementById("frontier");
  svg.innerHTML = "";
  var pts = [];
  candidates(state.group, state.value).forEach(function (st) {
    var wl = state.group === "list" ? "append_n" : "insert_rand";
    var ins = get(st.name, state.value, "warm", wl, state.n);
    var rd = get(st.name, state.value, "cold", state.group === "list" ? "tx_at" : "tx_read", state.n);
    if (!ins || !rd || !ins.ops) return;
    pts.push({ name: st.name, x: ins.d_bytes / ins.ops, y: rd.d_gas / Math.max(rd.ops, 1) });
  });
  hide("frontier", pts.length === 0);
  if (!pts.length) { document.getElementById("fr-note").textContent = ""; return; }
  var ys = pts.map(function (p) { return p.y; }).sort(function (a, b) { return a - b; });
  var med = ys[Math.floor(ys.length / 2)];
  var off = pts.filter(function (p) { return p.y > med * 6; });
  pts = pts.filter(function (p) { return p.y <= med * 6; });
  document.getElementById("fr-note").textContent = off.length
    ? "Off the scale, cut so the rest is readable: " + off.map(function (p) {
        return p.name + " at " + fmt(p.y) + " gas and " + fmt(p.x) + " bytes per entry"; }).join("; ") + "."
    : "";
  var w = Math.max(620, Math.min(1080, svg.parentNode.clientWidth || 940)), h = 430;
  var padL = 70, padR = 30, padT = 18, padB = 52;
  svg.setAttribute("width", w); svg.setAttribute("height", h);
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  var xmax = Math.max.apply(null, pts.map(function (p) { return p.x; })) * 1.15 || 1;
  var ymax = Math.max.apply(null, pts.map(function (p) { return p.y; })) * 1.18 || 1;
  var X = function (v) { return padL + v / xmax * (w - padL - padR); };
  var Y = function (v) { return h - padB - v / ymax * (h - padT - padB); };
  for (var i = 0; i <= 4; i++) {
    var gy = padT + i * (h - padT - padB) / 4;
    svg.appendChild(svgEl("line", { x1: padL, x2: w - padR, y1: gy, y2: gy, class: "grid" }));
    var t = svgEl("text", { x: padL - 8, y: gy + 4, "text-anchor": "end", class: "tick" });
    t.textContent = fmt(ymax * (1 - i / 4)); svg.appendChild(t);
  }
  svg.appendChild(svgEl("line", { x1: padL, x2: w - padR, y1: h - padB, y2: h - padB, class: "axis" }));
  for (var j = 1; j <= 4; j++) {
    var gx = padL + j * (w - padL - padR) / 4;
    var tx = svgEl("text", { x: gx, y: h - padB + 17, "text-anchor": "middle", class: "tick" });
    tx.textContent = fmt(xmax * j / 4); svg.appendChild(tx);
  }
  var xl = svgEl("text", { x: (padL + w - padR) / 2, y: h - 10, "text-anchor": "middle", class: "tick" });
  xl.textContent = "bytes of realm state per entry"; svg.appendChild(xl);
  var ymid = (padT + h - padB) / 2;
  var yl = svgEl("text", { x: 16, y: ymid, class: "tick", "text-anchor": "middle",
    transform: "rotate(-90 16 " + ymid + ")" });
  yl.textContent = "gas for one cold read"; svg.appendChild(yl);

  var placed = [];
  function fits(b) {
    for (var i = 0; i < placed.length; i++) {
      var p = placed[i];
      if (b.x < p.x2 && b.x2 > p.x && b.y < p.y2 && b.y2 > p.y) return false;
    }
    return true;
  }
  pts.sort(function (a, b) { return b.y - a.y; });
  pts.forEach(function (p) {
    var cx = X(p.x), cy = Y(p.y);
    var c = svgEl("circle", { cx: cx, cy: cy, r: 6, class: "mark", tabindex: 0,
      stroke: "var(--surface)", "stroke-width": 2 });
    c.addEventListener("mousemove", function (e) {
      showTip(e, "<b>" + p.name + "</b><br>" + fmt(p.x) + " bytes per entry<br>" + fmt(p.y) + " gas for one cold read");
    });
    c.addEventListener("mouseleave", hideTip);
    svg.appendChild(c);
    var wpx = p.name.length * 6.2 + 4, hpx = 13;
    var cands = [{ dx: 10, dy: -8, a: "start" }, { dx: -10, dy: -8, a: "end" },
      { dx: 10, dy: 15, a: "start" }, { dx: -10, dy: 15, a: "end" }];
    for (var i = 0; i < cands.length; i++) {
      var d = cands[i];
      var x0 = d.a === "start" ? cx + d.dx : cx + d.dx - wpx;
      var box = { x: x0, x2: x0 + wpx, y: cy + d.dy - hpx, y2: cy + d.dy };
      if (i === cands.length - 1 || fits(box)) {
        placed.push(box);
        var t2 = svgEl("text", { x: cx + d.dx, y: cy + d.dy, "text-anchor": d.a, class: "val" });
        t2.textContent = p.name; svg.appendChild(t2);
        break;
      }
    }
  });
}

function workloadSection() {
  var wls = S.workloads.filter(function (w) { return w.group === state.group && !w.light; });
  var chips = document.getElementById("wlchips");
  chips.innerHTML = "";
  if (!wls.length) return;
  if (!state.workload || !wls.some(function (w) { return w.name === state.workload && w.group === state.group; })) {
    state.workload = wls[0].name;
  }
  wls.forEach(function (w) {
    var b = el("button", "chip", w.mode + " / " + w.name);
    b.setAttribute("aria-pressed", w.name === state.workload);
    b.title = w.note;
    b.onclick = function () { state.workload = w.name; render(); };
    chips.appendChild(b);
  });
  var wl = wls.filter(function (w) { return w.name === state.workload; })[0];
  document.getElementById("wl-title").textContent = wl.mode + " / " + wl.name;
  document.getElementById("wl-note").textContent = wl.note;
  var rows = [];
  candidates(state.group, state.value).forEach(function (st) {
    var r = get(st.name, state.value, wl.mode, wl.name, state.n);
    if (!r) return;
    var v = metricOf(r, state.metric);
    if (v === null) return;
    rows.push({ name: st.name, v: v,
      tip: fmt(r.d_gas) + " gas, " + fmt(r.d_bytes) + " bytes over " + r.ops + " op(s)" });
  });
  bars("bars", rows, METRICS[state.metric] + ", lower is better");
}

function scaling() {
  var host = document.getElementById("scaling");
  host.innerHTML = "";
  var wls = S.workloads.filter(function (w) { return w.group === state.group; });
  var wl = wls.filter(function (w) { return w.name === state.workload; })[0] || wls[0];
  var ns = sizes(), by = {};
  candidates(state.group, state.value).forEach(function (st) {
    ns.forEach(function (n) {
      var r = get(st.name, state.value, wl.mode, wl.name, n);
      if (!r) return;
      var v = metricOf(r, state.metric);
      if (v === null) return;
      if (!by[st.name]) by[st.name] = {};
      by[st.name][n] = v;
    });
  });
  var names = Object.keys(by).filter(function (k) { return Object.keys(by[k]).length >= 2; });
  document.getElementById("sc-note").textContent = names.length
    ? "One panel per candidate for " + wl.mode + " / " + wl.name + ", " + METRICS[state.metric] +
      " at n = " + ns.join(", ") + ". Shared logarithmic axis: flat is O(1), a straight rise is a power law."
    : "Nothing measured at two or more sizes for this selection.";
  if (!names.length) return;
  var all = [];
  names.forEach(function (k) { ns.forEach(function (n) { if (by[k][n] != null) all.push(by[k][n]); }); });
  var pos = all.filter(function (v) { return v > 0; });
  var floor = pos.length ? Math.min.apply(null, pos) : 1;
  var lg = function (v) { return Math.log10(Math.max(v, floor)); };
  var vmax = lg(Math.max.apply(null, all)), vmin = lg(floor);
  if (vmax === vmin) vmax = vmin + 1;
  names.sort(function (a, b) {
    var la = by[a][ns[ns.length - 1]] || 0, lb = by[b][ns[ns.length - 1]] || 0;
    return la - lb;
  });
  names.forEach(function (k) {
    var fig = el("figure");
    fig.appendChild(el("figcaption", null, k));
    var w = 180, h = 74, pad = 10;
    var svg = svgEl("svg", { width: w, height: h, viewBox: "0 0 " + w + " " + h });
    var X = function (i) { return pad + i * (w - 2 * pad) / Math.max(ns.length - 1, 1); };
    var Y = function (v) { return h - pad - (lg(v) - vmin) / (vmax - vmin) * (h - 2 * pad); };
    svg.appendChild(svgEl("line", { x1: pad, x2: w - pad, y1: h - pad, y2: h - pad, class: "grid" }));
    var d = "", pts = [];
    ns.forEach(function (n, i) {
      var v = by[k][n];
      if (v == null) return;
      pts.push({ i: i, n: n, v: v });
      d += (d ? " L" : "M") + X(i) + " " + Y(v);
    });
    svg.appendChild(svgEl("path", { d: d, fill: "none", stroke: "var(--series)", "stroke-width": 2, "stroke-linejoin": "round" }));
    pts.forEach(function (p) {
      var c = svgEl("circle", { cx: X(p.i), cy: Y(p.v), r: 4, class: "mark", stroke: "var(--surface)", "stroke-width": 2 });
      c.addEventListener("mousemove", function (e) {
        showTip(e, "<b>" + k + "</b><br>n = " + p.n.toLocaleString("en-US") + "<br>" + fmt(p.v) + " " + METRICS[state.metric]);
      });
      c.addEventListener("mouseleave", hideTip);
      svg.appendChild(c);
    });
    fig.appendChild(svg);
    var f = pts[0], l = pts[pts.length - 1];
    fig.appendChild(el("div", "cap2", fmt(f.v) + " at n=" + f.n + "  ->  " + fmt(l.v) + " at n=" + l.n));
    host.appendChild(fig);
  });
}

function tiles() {
  var out = [];
  if (S.name === "digest") { digestTiles(); return; }
  function cold(name, wl, n) {
    var r = get(name, "str", "cold", wl, n);
    return r ? r.d_gas / Math.max(r.ops, 1) : null;
  }
  var n = sizes()[sizes().length - 1];
  var mapR = cold("builtin map[string]any", "tx_read", n);
  var avlR = cold("p/nt/avl/v0", "tx_read", n);
  if (mapR && avlR) {
    out.push([(mapR / avlR).toFixed(1) + "x", "what one cold read of a builtin map costs over p/nt/avl/v0 at n=" + n.toLocaleString("en-US")]);
  }
  var wr = get("p/nt/avl/v0", "str", "warm", "get_hit", n), cr = get("p/nt/avl/v0", "str", "cold", "cold_get_all", n);
  if (wr && cr && wr.ops && cr.ops) {
    out.push([((cr.d_gas / cr.ops) / (wr.d_gas / wr.ops)).toFixed(2) + "x", "how much warmer p/nt/avl/v0 reads look when the benchmark never commits"]);
  }
  var ins = get("p/nt/avl/v0", "str", "warm", "insert_rand", n);
  var bp = get("p/nt/bptree/v0 fanout=128", "str", "warm", "insert_rand", n);
  if (ins && bp && ins.ops && bp.ops) {
    out.push([((ins.d_bytes / ins.ops) / (bp.d_bytes / bp.ops)).toFixed(1) + "x",
      "what p/nt/avl/v0 costs in storage over p/nt/bptree/v0 at fanout 128"]);
  }
  var o = get("p/nt/bptree/v0 fanout=32", "obj", "warm", "insert_rand", n);
  var s2 = get("p/nt/bptree/v0 fanout=32", "str", "warm", "insert_rand", n);
  if (o && s2 && o.ops && s2.ops) {
    out.push(["+" + fmt(o.d_bytes / o.ops - s2.d_bytes / s2.ops) + " B",
      "per entry, for storing a live object instead of an encoded string"]);
  }
  var host = document.getElementById("tiles");
  host.innerHTML = "";
  out.forEach(function (t) {
    var d = el("div", "tile");
    d.appendChild(el("div", "big", t[0]));
    d.appendChild(el("div", "cap", t[1]));
    host.appendChild(d);
  });
}

// digestTiles: the storage suite's headline ratios mean nothing for a suite
// that persists nothing, so this one leads with gas per byte.
function digestTiles() {
  var n = sizes()[sizes().length - 1], out = [];
  S.structures.forEach(function (st) {
    var r = get(st.name, state.value, "warm", "x64", n);
    if (!r || !r.ops) return;
    out.push({ name: st.name, perCall: r.d_gas / r.ops, perByte: r.d_gas / r.ops / n });
  });
  out.sort(function (a, b) { return a.perByte - b.perByte; });
  var host = document.getElementById("tiles");
  host.innerHTML = "";
  out.slice(0, 4).forEach(function (t) {
    var d = el("div", "tile");
    d.appendChild(el("div", "big", fmt(t.perByte)));
    d.appendChild(el("div", "cap", "gas per byte, " + t.name + ", at " + n.toLocaleString("en-US") + " bytes"));
    host.appendChild(d);
  });
}

function rawTable() {
  var t = document.getElementById("raw");
  t.innerHTML = "";
  var cols = ["candidate", "value", "mode", "workload", "n", "ops", "gas", "bytes", "d_gas", "d_bytes", "ms", "measured", "note"];
  var head = el("tr");
  cols.forEach(function (c) { head.appendChild(el("th", null, c)); });
  t.appendChild(head);
  var rows = (DATA.files[state.file].rows || []).slice().sort(function (a, b) {
    return (a.structure + a.value + a.mode + a.workload + a.n).localeCompare(b.structure + b.value + b.mode + b.workload + b.n);
  });
  rows.forEach(function (r) {
    var note = r.skip || "";
    if (r.err) note = "FAILED: " + r.err;
    else if (!r.skip && !r.stable) note = "unstable across repeats";
    var tr = el("tr");
    [r.structure, r.value, r.mode, r.workload, r.n, r.ops, r.gas, r.bytes, r.d_gas, r.d_bytes,
      (r.d_wall_ns / 1e6).toFixed(1), (r.measured_at || "").slice(0, 10), note]
      .forEach(function (v) { tr.appendChild(el("td", null, String(v))); });
    t.appendChild(tr);
  });
  document.getElementById("rawdet").firstChild.textContent = "Expand (" + rows.length + " rows)";
}

function render() {
  controls();
  tiles();
  txSection();
  warmCold();
  frontier();
  workloadSection();
  scaling();
  rawTable();
}

reindex();
header();
render();
window.addEventListener("resize", render);
</script>
</body>
</html>
`
