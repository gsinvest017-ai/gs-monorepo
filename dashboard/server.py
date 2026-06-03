"""
GS Monorepo Service Monitor — Python stdlib HTTP server (zero deps).

Routes:
  GET /              → static/index.html
  GET /static/*      → static/
  GET /api/status    → JSON: all service statuses (cached, refreshed every 5 s)
  GET /api/health    → {"ok": true}

Usage:
  python dashboard/server.py                       # http://127.0.0.1:9000
  python dashboard/server.py --port 9001 --host 0.0.0.0
"""
from __future__ import annotations

import argparse
import json
import logging
import mimetypes
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

# ── Paths ────────────────────────────────────────────────────────────────────

DASHBOARD_DIR  = Path(__file__).resolve().parent
REPO_ROOT      = DASHBOARD_DIR.parent
STATIC_DIR     = DASHBOARD_DIR / "static"
SERVICES_JSON  = REPO_ROOT / "configs" / "services.json"
RUN_DIR        = REPO_ROOT / "run"

REFRESH_SECS   = 5      # background refresh interval
TCP_TIMEOUT    = 1.5    # seconds

log = logging.getLogger("gs.monitor")


# ── Status helpers ────────────────────────────────────────────────────────────

def tcp_check(host: str, port: int) -> tuple[bool, float | None]:
    """Return (reachable, latency_ms). host 0.0.0.0 → 127.0.0.1 for check."""
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
    """Windows-compatible PID liveness check via tasklist."""
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
        "repo": svc.get("repo", ""),
        "description": svc.get("description", ""),
        "sub_path": svc.get("sub_path", ""),
    }

    if env_cfg is None:
        return {**base, "supported": False, "port": None, "host_ip": None,
                "status": "N/A", "tcp_ok": False, "latency_ms": None,
                "pid": None, "pid_alive": None, "url": None}

    port    = env_cfg["port"]
    host_ip = env_cfg["host_ip"]
    tcp_ok, latency_ms = tcp_check(host_ip, port)
    pid    = read_pid(name, env)
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
        "supported": True, "port": port, "host_ip": host_ip,
        "status": status, "tcp_ok": tcp_ok, "latency_ms": latency_ms,
        "pid": pid, "pid_alive": pid_alive,
        "url": f"http://{check_host}:{port}/",
    }


# ── Background refresher ──────────────────────────────────────────────────────

_lock  = threading.Lock()
_cache: dict[str, Any] = {"rows": [], "last_updated_iso": None, "last_updated_ts": 0}


def _refresh() -> None:
    try:
        raw = json.loads(SERVICES_JSON.read_text(encoding="utf-8"))
    except Exception as exc:
        log.warning("failed to read services.json: %s", exc)
        return

    rows: list[dict] = []
    for name, svc in raw.get("services", {}).items():
        for env in ("prod", "test"):
            rows.append(check_one(name, svc, env))

    ts  = time.time()
    iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))
    with _lock:
        _cache["rows"]              = rows
        _cache["last_updated_iso"]  = iso
        _cache["last_updated_ts"]   = ts
    log.debug("refreshed %d rows", len(rows))


def _bg_loop() -> None:
    while True:
        try:
            _refresh()
        except Exception as exc:
            log.exception("refresh error: %s", exc)
        time.sleep(REFRESH_SECS)


# ── HTTP handler ──────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        log.debug(fmt, *args)

    def _send(self, status: int, ctype: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, payload: Any, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send(status, "application/json; charset=utf-8", body)

    def _file(self, path: Path) -> None:
        if not path.is_file():
            self._json({"error": "not found"}, 404)
            return
        ctype, _ = mimetypes.guess_type(path.name)
        self._send(200, ctype or "application/octet-stream", path.read_bytes())

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        p = parsed.path.rstrip("/") or "/"

        if p == "/":
            self._file(STATIC_DIR / "index.html")
        elif p.startswith("/static/"):
            rel = p[len("/static/"):]
            self._file(STATIC_DIR / rel)
        elif p == "/api/health":
            self._json({"ok": True})
        elif p == "/api/status":
            with _lock:
                payload = dict(_cache)
            self._json(payload)
        else:
            self._json({"error": "not found"}, 404)


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(description="GS Service Monitor dashboard")
    ap.add_argument("--port", type=int, default=9000)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--refresh", type=int, default=REFRESH_SECS,
                    help="background refresh interval (seconds)")
    ap.add_argument("--log-level", default="INFO")
    args = ap.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s  %(levelname)-7s  %(name)s  %(message)s",
        datefmt="%H:%M:%S",
    )

    if not SERVICES_JSON.exists():
        log.error("services.json not found: %s", SERVICES_JSON)
        sys.exit(1)

    # Prime the cache synchronously before accepting requests
    _refresh()

    t = threading.Thread(target=_bg_loop, daemon=True, name="monitor-refresh")
    t.start()

    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("GS Service Monitor → http://%s:%d/", args.host, args.port)
    log.info("monitoring %d services  (refresh every %ds)",
             len(json.loads(SERVICES_JSON.read_text())["services"]), args.refresh)
    log.info("Ctrl-C to stop")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        log.info("stopping")
        srv.shutdown()


if __name__ == "__main__":
    main()
