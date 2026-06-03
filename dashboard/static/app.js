/* GS Service Monitor — app.js
   Editable cells (host_name / host_ip / port) + Start/Stop actions. */
"use strict";

const REFRESH_MS = 5000;
const $ = id => document.getElementById(id);

let _timer      = null;
let _countdown  = 0;
let _presets    = ["local", "local-wsl", "gb10", "dell"];
let _editing    = null;   // { name, env, field, el } — currently open edit cell
let _busy       = new Set();  // "name:env:start" or "name:env:stop"


// ── Toast ─────────────────────────────────────────────────────────────────────

function toast(msg, type = "info", ms = 3500) {
  const d = document.createElement("div");
  d.className = `toast toast-${type}`;
  d.textContent = msg;
  $("toast-container").appendChild(d);
  setTimeout(() => d.remove(), ms);
}


// ── API helpers ───────────────────────────────────────────────────────────────

async function apiGet(path) {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

async function apiPatch(path, body) {
  const r = await fetch(path, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return r.json();
}

async function apiPost(path, body = {}) {
  const r = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return r.json();
}


// ── Editable cell helpers ─────────────────────────────────────────────────────

function closeEditing() {
  if (!_editing) return;
  const { el } = _editing;
  const disp  = el.querySelector(".cell-display");
  const inp   = el.querySelector(".cell-input, .cell-select");
  const addWr = el.querySelector(".add-preset-input");
  if (disp)  disp.style.display  = "";
  if (inp)   inp.style.display   = "none";
  if (addWr) addWr.style.display = "none";
  _editing = null;
}

async function commitEdit(name, env, field, value) {
  if (value === "" || value === null || value === undefined) { closeEditing(); return; }
  const body = { [field]: field === "port" ? parseInt(value, 10) : String(value) };
  try {
    const d = await apiPatch(`/api/services/${encodeURIComponent(name)}/${env}`, body);
    if (d.ok) {
      toast(`✓ ${name}[${env}] ${field} = ${value}`, "ok");
      if (d.row) updateRowInPlace(d.row);
    } else {
      toast(`✗ 儲存失敗`, "err");
    }
  } catch (e) {
    toast(`✗ ${e.message}`, "err");
  }
  closeEditing();
}

function makeEditableText(name, env, field, displayEl) {
  const td = displayEl.parentElement;
  const inp = document.createElement("input");
  inp.className = "cell-input";
  inp.type  = field === "port" ? "number" : "text";
  inp.value = displayEl.dataset.val || "";
  inp.style.display = "none";
  td.appendChild(inp);

  displayEl.addEventListener("click", () => {
    if (_editing) closeEditing();
    _editing = { name, env, field, el: td };
    displayEl.style.display = "none";
    inp.style.display = "";
    inp.focus(); inp.select();
  });

  inp.addEventListener("keydown", e => {
    if (e.key === "Enter")  { commitEdit(name, env, field, inp.value.trim()); }
    if (e.key === "Escape") { closeEditing(); }
  });
  inp.addEventListener("blur", () => {
    if (_editing && _editing.el === td) commitEdit(name, env, field, inp.value.trim());
  });
}

function makeEditableSelect(name, env, displayEl) {
  const td  = displayEl.parentElement;
  const sel = document.createElement("select");
  sel.className = "cell-select";
  sel.style.display = "none";

  const addInp = document.createElement("input");
  addInp.className = "add-preset-input";
  addInp.placeholder = "新主機名稱…";
  addInp.style.display = "none";

  function rebuildOptions(current) {
    sel.innerHTML = "";
    for (const p of _presets) {
      const o = document.createElement("option");
      o.value = p; o.textContent = p;
      if (p === current) o.selected = true;
      sel.appendChild(o);
    }
    const addOpt = document.createElement("option");
    addOpt.value = "__add__"; addOpt.textContent = "＋ 新增主機…";
    sel.appendChild(addOpt);
  }
  rebuildOptions(displayEl.dataset.val || "local");

  td.appendChild(sel);
  td.appendChild(addInp);

  displayEl.addEventListener("click", () => {
    if (_editing) closeEditing();
    _editing = { name, env, field: "host_name", el: td };
    rebuildOptions(displayEl.dataset.val || "local");
    displayEl.style.display = "none";
    sel.style.display = "";
    sel.focus();
  });

  sel.addEventListener("change", async () => {
    if (sel.value === "__add__") {
      addInp.style.display = "";
      addInp.focus();
      return;
    }
    await commitEdit(name, env, "host_name", sel.value);
  });
  sel.addEventListener("blur", () => {
    if (sel.value !== "__add__" && _editing && _editing.el === td) {
      setTimeout(() => {
        if (document.activeElement !== addInp) closeEditing();
      }, 100);
    }
  });
  sel.addEventListener("keydown", e => { if (e.key === "Escape") closeEditing(); });

  addInp.addEventListener("keydown", async e => {
    if (e.key === "Enter") {
      const newName = addInp.value.trim();
      if (newName) {
        try {
          const d = await apiPost("/api/host-presets", { name: newName });
          if (d.ok) {
            _presets = d.presets;
            toast(`✓ 已新增主機 "${newName}"`, "ok");
            await commitEdit(name, env, "host_name", newName);
            return;
          }
        } catch (e) { toast(`✗ ${e.message}`, "err"); }
      }
      closeEditing();
    }
    if (e.key === "Escape") closeEditing();
  });
  addInp.addEventListener("blur", () => {
    setTimeout(() => {
      if (document.activeElement !== sel) closeEditing();
    }, 100);
  });
}


// ── In-place row updater (for non-editing cells) ──────────────────────────────

function updateRowInPlace(row) {
  const key = `${row.name}:${row.env}`;
  // Update status, PID, latency, url button — leave editable cells alone
  const statusEl  = document.querySelector(`[data-row-key="${key}"] .status-cell`);
  const pidEl     = document.querySelector(`[data-row-key="${key}"] .pid-cell`);
  const latEl     = document.querySelector(`[data-row-key="${key}"] .latency-cell`);
  const actionEl  = document.querySelector(`[data-row-key="${key}"] .action-cell`);

  if (statusEl) {
    statusEl.className = `status-cell ${statusClass(row.status)}`;
    statusEl.innerHTML = `<span class="status-dot"></span><span class="status-text">${statusLabel(row.status)}</span>`;
  }
  if (pidEl) {
    pidEl.innerHTML = row.pid
      ? `<span class="pid-text">${row.pid}</span>`
      : `<span class="dim-dash">—</span>`;
  }
  if (latEl) latEl.innerHTML = latencyHTML(row.latency_ms);
  if (actionEl) updateActionCell(actionEl, row);
}

function updateActionCell(cell, row) {
  // Don't update if a start/stop is in progress for this row
  const busyKey = `${row.name}:${row.env}`;
  if (_busy.has(busyKey + ":start") || _busy.has(busyKey + ":stop")) return;
  cell.innerHTML = "";
  appendActionButtons(cell, row);
}

function appendActionButtons(cell, row) {
  if (!row.supported) return;

  const busyKey = `${row.name}:${row.env}`;
  const isStarting = _busy.has(busyKey + ":start");
  const isStopping = _busy.has(busyKey + ":stop");

  const canStart = row.status === "stopped" || row.status === "dead";
  const canStop  = row.status === "running" || row.status === "starting";

  if (canStart || isStarting) {
    const btn = document.createElement("button");
    btn.className = `action-btn btn-start${isStarting ? " loading" : ""}`;
    btn.textContent = isStarting ? "啟動中…" : "▶ 啟動";
    btn.disabled = isStarting;
    btn.addEventListener("click", () => handleStart(row.name, row.env, cell));
    cell.appendChild(btn);
  }
  if (canStop || isStopping) {
    const btn = document.createElement("button");
    btn.className = `action-btn btn-stop${isStopping ? " loading" : ""}`;
    btn.textContent = isStopping ? "停止中…" : "■ 停止";
    btn.disabled = isStopping;
    btn.addEventListener("click", () => handleStop(row.name, row.env, cell));
    cell.appendChild(btn);
  }

  if (row.url) {
    const a = document.createElement("a");
    a.href = row.url; a.target = "_blank";
    a.className = `open-btn${row.status !== "running" ? " disabled" : ""}`;
    a.textContent = "↗";
    a.title = row.url;
    if (row.status !== "running") a.removeAttribute("href");
    cell.appendChild(a);
  }
}


// ── Start / Stop ──────────────────────────────────────────────────────────────

async function handleStart(name, env, cell) {
  const busyKey = `${name}:${env}`;
  _busy.add(busyKey + ":start");
  cell.innerHTML = `<button class="action-btn btn-start loading" disabled>啟動中…</button>`;
  try {
    const d = await apiPost(`/api/services/${encodeURIComponent(name)}/${env}/start`);
    if (d.ok) {
      toast(`▶ ${name}[${env}] 已啟動`, "ok");
    } else {
      toast(`✗ 啟動失敗：${(d.output || "").slice(0, 120)}`, "err", 6000);
    }
  } catch (e) {
    toast(`✗ ${e.message}`, "err");
  } finally {
    _busy.delete(busyKey + ":start");
  }
  // Force immediate re-poll
  await poll(true);
}

async function handleStop(name, env, cell) {
  const busyKey = `${name}:${env}`;
  _busy.add(busyKey + ":stop");
  cell.innerHTML = `<button class="action-btn btn-stop loading" disabled>停止中…</button>`;
  try {
    const d = await apiPost(`/api/services/${encodeURIComponent(name)}/${env}/stop`);
    if (d.ok) {
      toast(`■ ${name}[${env}] 已停止`, "ok");
    } else {
      toast(`✗ 停止失敗：${(d.output || "").slice(0, 120)}`, "err", 6000);
    }
  } catch (e) {
    toast(`✗ ${e.message}`, "err");
  } finally {
    _busy.delete(busyKey + ":stop");
  }
  await poll(true);
}


// ── Render helpers ────────────────────────────────────────────────────────────

function statusClass(s) {
  return { running:"s-running", stopped:"s-stopped", starting:"s-starting", dead:"s-dead" }[s] || "s-na";
}
function statusLabel(s) {
  return { running:"running", stopped:"stopped", starting:"starting…", dead:"dead (stale)", "N/A":"N/A" }[s] || s;
}
function latencyHTML(ms) {
  if (ms == null) return `<span class="dim-dash">—</span>`;
  const cls = ms < 30 ? "latency-fast" : ms < 200 ? "latency-text" : "latency-slow";
  return `<span class="${cls}">${ms} ms</span>`;
}


// ── Build full row (first render) ─────────────────────────────────────────────

function buildRow(row, isFirst, isLast) {
  const tr = document.createElement("tr");
  tr.dataset.rowKey = `${row.name}:${row.env}`;
  if (isFirst) tr.classList.add("group-start");
  if (isLast)  tr.classList.add("group-end");

  // Col 1: service name + description (first row only)
  const tdSvc = document.createElement("td");
  if (isFirst) {
    tdSvc.innerHTML = `<div class="svc-name">${row.name}</div>` +
      (row.description ? `<div class="svc-desc">${row.description}</div>` : "");
  }
  tr.appendChild(tdSvc);

  // Col 2: env badge
  const envCls = row.env === "prod" ? "env-prod" : "env-test";
  const tdEnv = document.createElement("td");
  tdEnv.innerHTML = `<span class="env-badge ${envCls}">${row.env}</span>`;
  tr.appendChild(tdEnv);

  // Col 3: host_name (editable select)
  const tdHN = document.createElement("td");
  tdHN.className = "editable-cell";
  const hnVal = row.host_name || "—";
  const hnDisp = document.createElement("span");
  hnDisp.className = "cell-display host-name-display";
  hnDisp.textContent = hnVal;
  hnDisp.dataset.val = row.host_name || "";
  if (row.supported) {
    tdHN.appendChild(hnDisp);
    makeEditableSelect(row.name, row.env, hnDisp);
  } else {
    hnDisp.style.cursor = "default";
    hnDisp.innerHTML = `<span class="dim-dash">—</span>`;
    hnDisp.removeAttribute("data-val");
    tdHN.appendChild(hnDisp);
  }
  tr.appendChild(tdHN);

  // Col 4: host_ip (editable text)
  const tdIP = document.createElement("td");
  tdIP.className = "editable-cell";
  const ipVal  = row.host_ip || "—";
  const ipDisp = document.createElement("span");
  ipDisp.className = "cell-display host-ip";
  ipDisp.textContent = ipVal;
  ipDisp.dataset.val = row.host_ip || "";
  if (row.supported) {
    tdIP.appendChild(ipDisp);
    makeEditableText(row.name, row.env, "host_ip", ipDisp);
  } else {
    ipDisp.style.cursor = "default";
    ipDisp.innerHTML = `<span class="dim-dash">—</span>`;
    tdIP.appendChild(ipDisp);
  }
  tr.appendChild(tdIP);

  // Col 5: port (editable number)
  const tdPort = document.createElement("td");
  tdPort.className = "editable-cell";
  const portDisp = document.createElement("span");
  portDisp.className = "cell-display port-num";
  portDisp.textContent = row.port != null ? String(row.port) : "—";
  portDisp.dataset.val = row.port != null ? String(row.port) : "";
  if (row.supported && row.port != null) {
    tdPort.appendChild(portDisp);
    makeEditableText(row.name, row.env, "port", portDisp);
  } else {
    portDisp.style.cursor = "default";
    portDisp.innerHTML = `<span class="dim-dash">—</span>`;
    tdPort.appendChild(portDisp);
  }
  tr.appendChild(tdPort);

  // Col 6: status
  const tdStatus = document.createElement("td");
  const sc = statusClass(row.status);
  tdStatus.innerHTML =
    `<div class="status-cell ${sc}"><span class="status-dot"></span><span class="status-text">${statusLabel(row.status)}</span></div>`;
  tr.appendChild(tdStatus);

  // Col 7: PID
  const tdPid = document.createElement("td");
  tdPid.className = "pid-cell";
  tdPid.innerHTML = row.pid
    ? `<span class="pid-text">${row.pid}</span>`
    : `<span class="dim-dash">—</span>`;
  tr.appendChild(tdPid);

  // Col 8: latency
  const tdLat = document.createElement("td");
  tdLat.className = "col-latency latency-cell";
  tdLat.innerHTML = latencyHTML(row.latency_ms);
  tr.appendChild(tdLat);

  // Col 9: actions
  const tdAct = document.createElement("td");
  tdAct.className = "action-cell";
  appendActionButtons(tdAct, row);
  tr.appendChild(tdAct);

  return tr;
}


// ── Table render / update ─────────────────────────────────────────────────────

let _lastRows = [];

function renderTable(rows) {
  const tbody = $("services-tbody");

  // First render or row count changed → rebuild
  if (!_lastRows.length || _lastRows.length !== rows.length) {
    tbody.innerHTML = "";
    const groups = new Map();
    for (const r of rows) {
      if (!groups.has(r.name)) groups.set(r.name, []);
      groups.get(r.name).push(r);
    }
    for (const [, group] of groups) {
      group.forEach((row, i) =>
        tbody.appendChild(buildRow(row, i === 0, i === group.length - 1)));
    }
    _lastRows = rows;
    return;
  }

  // Subsequent renders → update only non-editable cells in place
  for (const row of rows) {
    updateRowInPlace(row);
    // Update editable display values (if not currently being edited)
    const key = `${row.name}:${row.env}`;
    if (_editing && `${_editing.name}:${_editing.env}` === key) continue;
    const tr = document.querySelector(`[data-row-key="${key}"]`);
    if (!tr) continue;
    const hnDisp   = tr.querySelector(".host-name-display");
    const ipDisp   = tr.querySelector(".host-ip.cell-display");
    const portDisp = tr.querySelector(".port-num.cell-display");
    if (hnDisp)   { hnDisp.textContent = row.host_name || "—"; hnDisp.dataset.val = row.host_name || ""; }
    if (ipDisp)   { ipDisp.textContent = row.host_ip   || "—"; ipDisp.dataset.val = row.host_ip   || ""; }
    if (portDisp) { portDisp.textContent = row.port != null ? String(row.port) : "—"; portDisp.dataset.val = row.port != null ? String(row.port) : ""; }
  }
  _lastRows = rows;
}

function renderSummary(rows) {
  const running = rows.filter(r => r.status === "running").length;
  const stopped = rows.filter(r => r.status === "stopped").length;
  const issues  = rows.filter(r => r.status === "dead" || r.status === "starting").length;
  const na      = rows.filter(r => r.status === "N/A").length;
  const active  = rows.length - na;

  const bar = $("summary-bar");
  bar.innerHTML = "";
  const pills = [
    { cls: "pill-running", label: `${running} running` },
    { cls: "pill-stopped", label: `${stopped} stopped` },
  ];
  if (issues > 0) pills.push({ cls: "pill-issue", label: `${issues} issue${issues > 1 ? "s" : ""}` });
  pills.push({ cls: "pill-total", label: `${active} monitored` });
  for (const { cls, label } of pills) {
    const p = document.createElement("div");
    p.className = `summary-pill ${cls}`;
    p.innerHTML = `<span class="dot"></span>${label}`;
    bar.appendChild(p);
  }
  $("footer-counts").textContent = `${running} / ${active} 服務運行中`;
}

function renderUpdatedAt(isoStr) {
  if (!isoStr) return;
  const d   = new Date(isoStr);
  const hms = d.toLocaleTimeString("zh-TW", { hour12: false });
  $("updated-at").textContent = `最後更新 ${hms}`;
}

function startCountdown() {
  _countdown = Math.round(REFRESH_MS / 1000);
  clearInterval(_timer);
  _timer = setInterval(() => {
    _countdown--;
    $("refresh-badge").textContent = _countdown <= 0 ? "更新中…" : `${_countdown}s 後更新`;
  }, 1000);
}


// ── Poll loop ─────────────────────────────────────────────────────────────────

async function poll(immediate = false) {
  if (!immediate) startCountdown();
  try {
    const data = await apiGet("/api/status");
    if (data.host_presets) _presets = data.host_presets;
    renderTable(data.rows || []);
    renderSummary(data.rows || []);
    renderUpdatedAt(data.last_updated_iso);
  } catch (e) {
    $("services-tbody").innerHTML =
      `<tr><td colspan="9" class="loading-cell">⚠ 無法取得狀態：${e.message}</td></tr>`;
    $("refresh-badge").textContent = "錯誤";
  }
}

poll();
setInterval(poll, REFRESH_MS);
