/* GS Service Monitor — app.js
   Polls /api/status every REFRESH_MS, renders service table. */

"use strict";

const REFRESH_MS = 5000;

const $ = id => document.getElementById(id);

let _timer = null;
let _countdown = 0;


// ── API ───────────────────────────────────────────────────────────────────────

async function fetchStatus() {
  const r = await fetch("/api/status");
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}


// ── Render helpers ────────────────────────────────────────────────────────────

function statusClass(s) {
  if (s === "running")  return "s-running";
  if (s === "stopped")  return "s-stopped";
  if (s === "starting") return "s-starting";
  if (s === "dead")     return "s-dead";
  return "s-na";
}

function statusLabel(s) {
  const MAP = {
    running:  "running",
    stopped:  "stopped",
    starting: "starting…",
    dead:     "dead (stale)",
    "N/A":    "N/A",
  };
  return MAP[s] || s;
}

function el(tag, attrs = {}, children = []) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "className") e.className = v;
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    if (typeof c === "string") e.appendChild(document.createTextNode(c));
    else if (c) e.appendChild(c);
  }
  return e;
}

function latencyEl(ms) {
  if (ms === null || ms === undefined) return el("span", { className: "dim-dash" }, ["—"]);
  const cls = ms < 30 ? "latency-fast" : ms < 200 ? "latency-text" : "latency-slow";
  return el("span", { className: cls }, [`${ms} ms`]);
}

function buildRow(row, isFirst, isLast) {
  const tr = document.createElement("tr");
  if (isFirst) tr.classList.add("group-start");
  if (isLast)  tr.classList.add("group-end");

  // Col 1: service name + description (only on first row of group)
  const tdSvc = document.createElement("td");
  if (isFirst) {
    tdSvc.appendChild(el("div", { className: "svc-name" }, [row.name]));
    if (row.description)
      tdSvc.appendChild(el("div", { className: "svc-desc" }, [row.description]));
  }
  tr.appendChild(tdSvc);

  // Col 2: env badge
  const envClass = row.env === "prod" ? "env-prod" : "env-test";
  tr.appendChild(el("td", {}, [el("span", { className: `env-badge ${envClass}` }, [row.env])]));

  // Col 3: host IP
  tr.appendChild(el("td", {}, [
    row.host_ip ? el("span", { className: "host-ip" }, [row.host_ip]) : el("span", { className: "dim-dash" }, ["—"])
  ]));

  // Col 4: port
  tr.appendChild(el("td", {}, [
    row.port ? el("span", { className: "port-num" }, [String(row.port)]) : el("span", { className: "dim-dash" }, ["—"])
  ]));

  // Col 5: status
  const sc = statusClass(row.status);
  const statusDiv = el("div", { className: `status-cell ${sc}` }, [
    el("span", { className: "status-dot" }),
    el("span", { className: "status-text" }, [statusLabel(row.status)]),
  ]);
  tr.appendChild(el("td", {}, [statusDiv]));

  // Col 6: PID
  const pidStr = row.pid != null ? String(row.pid) : "—";
  tr.appendChild(el("td", {}, [
    el("span", { className: row.pid ? "pid-text" : "dim-dash" }, [pidStr])
  ]));

  // Col 7: latency
  const tdLat = el("td", { className: "col-latency" }, [latencyEl(row.latency_ms)]);
  tr.appendChild(tdLat);

  // Col 8: open link
  const tdBtn = document.createElement("td");
  if (row.url && row.status === "running") {
    const a = el("a", { href: row.url, target: "_blank", className: "open-btn" }, ["↗ 開啟"]);
    tdBtn.appendChild(a);
  } else if (row.url) {
    const span = el("span", { className: "open-btn disabled" }, ["↗ 開啟"]);
    tdBtn.appendChild(span);
  }
  tr.appendChild(tdBtn);

  return tr;
}


// ── Main render ───────────────────────────────────────────────────────────────

function renderTable(rows) {
  const tbody = $("services-tbody");
  tbody.innerHTML = "";

  // Group rows by service name (preserving order)
  const groups = new Map();
  for (const r of rows) {
    if (!groups.has(r.name)) groups.set(r.name, []);
    groups.get(r.name).push(r);
  }

  for (const [, group] of groups) {
    group.forEach((row, idx) => {
      tbody.appendChild(buildRow(row, idx === 0, idx === group.length - 1));
    });
  }
}

function renderSummary(rows) {
  const running  = rows.filter(r => r.status === "running").length;
  const stopped  = rows.filter(r => r.status === "stopped").length;
  const issues   = rows.filter(r => r.status === "dead" || r.status === "starting").length;
  const total    = rows.length;
  const na       = rows.filter(r => r.status === "N/A").length;
  const active   = total - na;

  const bar = $("summary-bar");
  bar.innerHTML = "";

  const pills = [
    { cls: "pill-running", label: `${running} running` },
    { cls: "pill-stopped", label: `${stopped} stopped` },
  ];
  if (issues > 0) pills.push({ cls: "pill-issue", label: `${issues} issue${issues > 1 ? "s" : ""}` });
  pills.push({ cls: "pill-total", label: `${active} monitored` });

  for (const { cls, label } of pills) {
    const pill = el("div", { className: `summary-pill ${cls}` }, [
      el("span", { className: "dot" }),
      label,
    ]);
    bar.appendChild(pill);
  }

  $("footer-counts").textContent = `${running} / ${active} 服務運行中`;
}

function renderUpdatedAt(isoStr) {
  if (!isoStr) return;
  // Convert UTC ISO to local HH:MM:SS
  const d = new Date(isoStr);
  const hms = d.toLocaleTimeString("zh-TW", { hour12: false });
  $("updated-at").textContent = `最後更新 ${hms}`;
}

function startCountdown() {
  _countdown = Math.round(REFRESH_MS / 1000);
  clearInterval(_timer);
  _timer = setInterval(() => {
    _countdown--;
    if (_countdown <= 0) {
      $("refresh-badge").textContent = "更新中…";
    } else {
      $("refresh-badge").textContent = `${_countdown}s 後更新`;
    }
  }, 1000);
}


// ── Poll loop ─────────────────────────────────────────────────────────────────

async function poll() {
  startCountdown();
  try {
    const data = await fetchStatus();
    renderTable(data.rows || []);
    renderSummary(data.rows || []);
    renderUpdatedAt(data.last_updated_iso);
  } catch (e) {
    $("services-tbody").innerHTML =
      `<tr><td colspan="8" class="loading-cell">⚠ 無法取得狀態：${e.message}</td></tr>`;
    $("refresh-badge").textContent = "錯誤";
  }
}

// Initial fetch + set up interval
poll();
setInterval(poll, REFRESH_MS);
