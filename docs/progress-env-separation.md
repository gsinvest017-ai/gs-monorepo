# 生產/測試環境分離 — 進度追蹤

## 目標

在 gs-monorepo 層（不動任何 submodule codebase）為所有 server 型 submodule
建立生產（prod）與測試（test）環境分離機制：

- 不同 port 號（prod = 原始 port，test = prod port + 100）
- 不同啟動指令/環境變數
- 生產環境持續在線，不受測試開發影響

參考 gs-gh-summary repo_paths panel schema（path / host_ip / server_port）
設計 `configs/services.ps1` 的服務定義格式。

---

## 計畫 Milestones

| # | 標題 | 預期產出 | 狀態 |
|---|------|---------|------|
| M1 | 探索 + 進度檔 | 此檔 + 服務清單 | ✅ 完成 |
| M2 | 服務定義 + env files | `configs/services.ps1`、`envs/prod/*.env`、`envs/test/*.env` | ✅ 完成 |
| M3 | 啟動腳本 | `scripts/start-env.ps1`、`stop-env.ps1`、`status-env.ps1` | ✅ 完成 |
| M4 | 收尾 | `.gitignore` + `README.md` 更新 | ✅ 完成 |

---

## 服務清單（探索結果）

| 服務名稱 | Prod Port | Test Port | Port 機制 | 啟動方式 |
|---------|-----------|-----------|----------|---------|
| gs-trading-portal | 8123 | 8223 | `--port` CLI arg | `python server.py --port P --bind B` |
| gs-gh-summary | 8790 | 8890 | `--port` CLI arg | `python server.py --port P --host H` |
| tw-news-board | 8787 | 8887 | `$env:TWBOARD_PORT` | `python serve.py` |
| tw-sentiment-radar | 8788 | 8888 | `$env:TWRADAR_PORT` | `python serve.py` (需 tw-news-board) |
| gs-risk-manager | 5066 | 5166 | `--port` CLI arg | `python -m dashboard --port P` |
| autogo | 8765 | 8865 | `--port` CLI arg | `uvicorn web.app:app --host H --port P` |
| gs-scraper (UI) | 5050 | ⚠️ 無 | hardcoded | `python -m ui.search.app`（port 硬編碼，無 env override） |
| trading-SySTEM | 8501 | 8601 | Streamlit `--server.port` | Prod: `run.ps1`；Test: 單獨起 Streamlit |

---

## M1 — 探索 + 進度檔

**做了什麼**：掃描各 server submodule 的 run.ps1 / serve.py / server.py，
確認每個服務的 port 設定機制（env var vs CLI arg vs hardcoded）。

**參考**：gs-gh-summary `ghsummary/repo_paths.py` 的 schema：
```
{ path, host_name, host_ip, server_port, updated_at }
```
services.ps1 將採相同欄位名稱並擴展 ProdPort / TestPort / Cmd / EnvVars。

**注意**：
- gs-scraper `ui/search/app.py:262` 硬編碼 `port = 5050`，無 env var 支援，
  test 環境暫不啟動（記錄為 `Test = $null`）。
- trading-SySTEM test 環境只啟動 Streamlit UI（port 8601），
  KGI/sim backend 沿用 prod port（純資料源，可共用）。

---

## Fallback 指引

若要 rollback 到某個 milestone 或由他人接手：

```powershell
# 查看每個 milestone 的 commit
git log --oneline docs/progress-env-separation.md

# 回到 M2 前
git checkout <M1-commit-hash> -- configs/ envs/

# 手動啟動任一服務（不用腳本）
$env:TWBOARD_PORT = "8887"
cd gs-monorepo\tw-news-board
python serve.py
```

**新增的檔案清單**（不含 submodule）：
```
configs/services.ps1
envs/prod/{service}.env  (× 8)
envs/test/{service}.env  (× 7)
scripts/start-env.ps1
scripts/stop-env.ps1
scripts/status-env.ps1
run/  (gitignored — PID + log 暫存)
```
