# Service Monitor Dashboard — 進度追蹤

## 目標

在 gs-monorepo 建立一個 Web dashboard，監控所有 server 型 submodule 的
生產（prod）/ 測試（test）執行狀態，顯示 hostname / IP / port / 運行狀態 / PID / 延遲。

- Python stdlib only（零新依賴）
- GS theme（Dark warm-black + gold，對齊 gs-trading-portal）
- Port: **9000**（dashboard 本身）
- 資料源：`configs/services.json` + `run/{env}/{name}.pid`
- 狀態檢查：TCP port 探測（主）+ PID 檔（次）

---

## Milestones

| # | 標題 | 預期產出 | 狀態 |
|---|------|---------|------|
| M1 | 進度檔 + 服務登錄 | 此檔 + `configs/services.json` | ✅ |
| M2 | Backend server | `dashboard/server.py` | ⬜ |
| M3 | Frontend UI | `dashboard/static/{index.html,style.css,app.js}` | ⬜ |
| M4 | Launcher + 收尾 | `scripts/start-dashboard.ps1` + README | ⬜ |

---

## Fallback 指引

```powershell
# 手動啟動 dashboard
cd C:\Users\User\gs-monorepo
python dashboard/server.py --port 9000

# Rollback M2+ (保留 M1)
git checkout <M1-hash> -- dashboard/ scripts/start-dashboard.ps1
```

---

## M1 — 進度檔 + services.json

**建立** `configs/services.json`：dashboard 專用資料源，
欄位對齊 gs-gh-summary repo_paths schema（path/host_ip/server_port）。
PS scripts 繼續讀 `configs/services.ps1`；兩者分工不同，保持同步。
