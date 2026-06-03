"""
GS Monorepo Service Monitor — Python stdlib HTTP server (zero deps).

Routes (GET):
  /                           → static/index.html
  /static/*                   → static/
  /api/health                 → {"ok": true}
  /api/status                 → cached service statuses + host_presets
  /api/host-presets           → preset list

Routes (PATCH):
  /api/services/{name}/{env}  → update overrides { host_name?, host_ip?, port? }

Routes (POST):
  /api/services/{name}/{env}/start  → start via start-env.ps1 -Detach
  /api/services/{name}/{env}/stop   → stop  via stop-env.ps1
  /api/host-presets                 → add preset { "name": "myhost" }

Usage:
  python dashboard/server.py                  # http://0.0.0.0:9000
  python dashboard/server.py --port 9001
"""
from __future__ import annotations

import argparse
import json
import logging
import mimetypes
import re
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

# ── Paths ─────────────────────────────────────────────────────────────────────

DASHBOARD_DIR  = Path(__file__).resolve().parent
REPO_ROOT      = DASHBOARD_DIR.parent
STATIC_DIR     = DASHBOARD_DIR / "static"
SERVICES_JSON  = REPO_ROOT / "configs" / "services.json"
OVERRIDES_JSON = REPO_ROOT / "configs" / "overrides.json"
SCRIPTS_DIR    = REPO_ROOT / "scripts"
RUN_DIR        = REPO_ROOT / "run"

REFRESH_SECS         = 5
TCP_TIMEOUT          = 0.5
DEFAULT_HOST_PRESETS = ["local", "local-wsl", "gb10", "dell"]

log = logging.getLogger("gs.monitor")

# ── Route patterns ────────────────────────────────────────────────────────────

_RE_SVC      = re.compile(r"^/api/services/([^/]+)/(prod|test)$")
_RE_SVC_ACT  = re.compile(r"^/api/services/([^/]+)/(prod|test)/(start|stop)$")


# ── Overrides store ───────────────────────────────────────────────────────────

_ovr_lock = threading.Lock()
_ovr: dict[str, Any] = {"_host_presets": list(DEFAULT_HOST_PRESETS), "services": {}}


def _load_overrides() -> None:
    global _ovr
    if not OVERRIDES_JSON.exists():
        return
    try:
        data = json.loads(OVERRIDES_JSON.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            with _ovr_lock:
                _ovr = data
                if "_host_presets" not in _ovr:
                    _ovr["_host_presets"] = list(DEFAULT_HOST_PRESETS)
                if "services" not in _ovr:
                    _ovr["services"] = {}
    except Exception as exc:
        log.warning("overrides.json load error: %s", exc)


def _save_overrides() -> None:
    try:
        with _ovr_lock:
            snapshot = json.dumps(_ovr, ensure_ascii=False, indent=2)
        OVERRIDES_JSON.write_text(snapshot, encoding="utf-8")
    except Exception as exc:
        log.warning("overrides.json save error: %s", exc)


def _get_svc_ovr(name: str, env: str) -> dict[str, Any]:
    with _ovr_lock:
        return dict(_ovr.get("services", {}).get(name, {}).get(env, {}))


def _patch_svc_ovr(name: str, env: str, fields: dict) -> None:
    with _ovr_lock:
        _ovr.setdefault("services", {}).setdefault(name, {}).setdefault(env, {}).update(fields)
    _save_overrides()


def _get_presets() -> list[str]:
    with _ovr_lock:
        return list(_ovr.get("_host_presets", DEFAULT_HOST_PRESETS))


def _add_preset(name: str) -> list[str]:
    with _ovr_lock:
        presets = _ovr.setdefault("_host_presets", list(DEFAULT_HOST_PRESETS))
        if name not in presets:
            presets.append(name)
    _save_overrides()
    return _get_presets()


# ── Status helpers ─────────────────────────────────────────────────────────────

def tcp_check(host: str, port: int) -> tuple[bool, float | None]:
    check_host = "127.0.0.1" if host in ("0.0.0.0", "") else host
    try:
        t0 = time.monotonic()
        with socket.create_connection((check_host, port), timeout=TCP_TIMEOUT):
            return True, round((time.monotonic() - t0) * 1000, 1)
    except Exception:
        return False, None


def read_pid(name: str, env: str) -> int | None:
    pid_file = RUN_DIR / env / f"{name}.pid"
    if not pid_file.exists():
        return None
    try:
        return int(pid_file.read_text(encoding="utf-8").strip())
    except (ValueError, OSError):
        return None


def is_pid_alive(pid: int) -> bool:
    try:
        r = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            capture_output=True, text=True, timeout=3,
        )
        return str(pid) in r.stdout
    except Exception:
        return False


def check_one(name: str, svc: dict[str, Any], env: str) -> dict[str, Any]:
    env_cfg = svc.get(env)
    base = {
        "name": name, "env": env,
        "repo":        svc.get("repo", ""),
        "description": svc.get("description", ""),
        "sub_path":    svc.get("sub_path", ""),
    }

    if env_cfg is None:
        return {**base, "supported": False, "host_name": None,
                "port": None, "host_ip": None,
                "status": "N/A", "tcp_ok": False, "latency_ms": None,
                "pid": None, "pid_alive": None, "url": None}

    # Merge overrides (override wins over services.json defaults)
    ovr       = _get_svc_ovr(name, env)
    port      = ovr.get("port")      or env_cfg["port"]
    host_ip   = ovr.get("host_ip")   or env_cfg["host_ip"]
    host_name = ovr.get("host_name") or "local"

    tcp_ok, latency_ms = tcp_check(host_ip, port)
    pid       = read_pid(name, env)
    pid_alive = is_pid_alive(pid) if pid is not None else None

    if tcp_ok:
        status = "running"
    elif pid is not None and pid_alive:
        status = "starting"
    elif pid is not None and pid_alive is False:
        status = "dead"
    else:
        status = "stopped"

    check_host = "127.0.0.1" if host_ip in ("0.0.0.0", "") else host_ip
    return {
        **base,
        "supported": True,
        "host_name": host_name,
        "host_ip":   host_ip,
        "port":      port,
        "status":    status,
        "tcp_ok":    tcp_ok,
        "latency_ms": latency_ms,
        "pid":       pid,
        "pid_alive": pid_alive,
        "url":       f"http://{check_host}:{port}/",
    }


# ── Background refresher ───────────────────────────────────────────────────────

_cache_lock = threading.Lock()
_cache: dict[str, Any] = {"rows": [], "last_updated_iso": None,
                           "last_updated_ts": 0, "host_presets": []}


def _refresh() -> None:
    try:
        raw = json.loads(SERVICES_JSON.read_text(encoding="utf-8"))
    except Exception as exc:
        log.warning("services.json read error: %s", exc)
        return

    rows: list[dict] = []
    for name, svc in raw.get("services", {}).items():
        for env in ("prod", "test"):
            rows.append(check_one(name, svc, env))

    ts  = time.time()
    iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))
    with _cache_lock:
        _cache["rows"]             = rows
        _cache["last_updated_iso"] = iso
        _cache["last_updated_ts"]  = ts
        _cache["host_presets"]     = _get_presets()
    log.debug("refreshed %d rows", len(rows))


def _bg_loop() -> None:
    while True:
        try:
            _refresh()
        except Exception as exc:
            log.exception("refresh error: %s", exc)
        time.sleep(REFRESH_SECS)


# ── PowerShell helper ──────────────────────────────────────────────────────────

def run_pwsh(script_name: str, *extra_args: str, timeout: int = 30) -> tuple[bool, str]:
    script = SCRIPTS_DIR / script_name
    if not script.exists():
        return False, f"script not found: {script}"
    try:
        r = subprocess.run(
            ["pwsh", "-NoProfile", "-File", str(script)] + list(extra_args),
            capture_output=True, text=True, cwd=str(REPO_ROOT), timeout=timeout,
        )
        out = (r.stdout + r.stderr).strip()
        return r.returncode == 0, out[-800:] if len(out) > 800 else out
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except Exception as exc:
        return False, str(exc)


# ── HTTP handler ───────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        log.debug(fmt, *args)

    def _send(self, status: int, ctype: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, payload: Any, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send(status, "application/json; charset=utf-8", body)

    def _file(self, path: Path) -> None:
        if not path.is_file():
            self._json({"error": "not found"}, 404); return
        ctype, _ = mimetypes.guess_type(path.name)
        self._send(200, ctype or "application/octet-stream", path.read_bytes())

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    # ── GET ───────────────────────────────────────────────────────────────────

    def do_GET(self) -> None:
        p = urlparse(self.path).path.rstrip("/") or "/"

        if p == "/":
            self._file(STATIC_DIR / "index.html")
        elif p.startswith("/static/"):
            self._file(STATIC_DIR / p[len("/static/"):])
        elif p == "/api/health":
            self._json({"ok": True})
        elif p == "/api/status":
            with _cache_lock:
                self._json(dict(_cache))
        elif p == "/api/host-presets":
            self._json({"presets": _get_presets()})
        else:
            self._json({"error": "not found"}, 404)

    # ── PATCH ─────────────────────────────────────────────────────────────────

    def do_PATCH(self) -> None:
        p = urlparse(self.path).path
        m = _RE_SVC.match(p)
        if not m:
            self._json({"error": "not found"}, 404); return

        name, env = m.group(1), m.group(2)
        try:
            body = self._read_body()
        except Exception:
            self._json({"error": "invalid JSON"}, 400); return

        allowed = {"host_name", "host_ip", "port"}
        fields  = {k: v for k, v in body.items() if k in allowed}
        if not fields:
            self._json({"error": "no valid fields"}, 400); return

        if "port" in fields:
            try:
                fields["port"] = int(fields["port"])
            except (TypeError, ValueError):
                self._json({"error": "port must be integer"}, 400); return

        _patch_svc_ovr(name, env, fields)
        # Force an immediate status refresh so the response reflects new values
        _refresh()
        with _cache_lock:
            updated_row = next(
                (r for r in _cache["rows"] if r["name"] == name and r["env"] == env),
                None
            )
        self._json({"ok": True, "row": updated_row})

    # ── POST ──────────────────────────────────────────────────────────────────

    def do_POST(self) -> None:
        p = urlparse(self.path).path

        # Add host preset
        if p == "/api/host-presets":
            try:
                body = self._read_body()
                preset_name = str(body.get("name", "")).strip()
            except Exception:
                self._json({"error": "invalid JSON"}, 400); return
            if not preset_name:
                self._json({"error": "name required"}, 400); return
            presets = _add_preset(preset_name)
            self._json({"ok": True, "presets": presets})
            return

        # Start / Stop service
        m = _RE_SVC_ACT.match(p)
        if not m:
            self._json({"error": "not found"}, 404); return

        svc_name, env, action = m.group(1), m.group(2), m.group(3)

        if action == "start":
            ok, out = run_pwsh("start-env.ps1", "-Env", env, "-Service", svc_name, "-Detach")
        else:
            ok, out = run_pwsh("stop-env.ps1", "-Env", env, "-Service", svc_name)

        # Small delay so PID file is written before next refresh
        time.sleep(0.8)
        _refresh()

        self._json({"ok": ok, "action": action, "output": out})

    # ── OPTIONS (CORS preflight) ──────────────────────────────────────────────

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PATCH,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(description="GS Service Monitor")
    ap.add_argument("--port",      type=int, default=9000)
    ap.add_argument("--host",      default="0.0.0.0")
    ap.add_argument("--refresh",   type=int, default=REFRESH_SECS)
    ap.add_argument("--log-level", default="INFO")
    args = ap.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s  %(levelname)-7s  %(name)s  %(message)s",
        datefmt="%H:%M:%S",
    )

    for f in (SERVICES_JSON,):
        if not f.exists():
            log.error("required file not found: %s", f); sys.exit(1)

    _load_overrides()
    _refresh()

    t = threading.Thread(target=_bg_loop, daemon=True, name="monitor-refresh")
    t.start()

    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    svc_count = len(json.loads(SERVICES_JSON.read_text(encoding="utf-8"))["services"])
    log.info("GS Service Monitor → http://%s:%d/", args.host, args.port)
    log.info("monitoring %d services  (refresh every %ds)", svc_count, args.refresh)
    log.info("Ctrl-C to stop")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        log.info("stopping")
        srv.shutdown()


if __name__ == "__main__":
    main()
