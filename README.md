# gs-monorepo

GS Invest 統一 monorepo — 以 **git submodules** 管理所有子專案，保留各 repo 獨立 git 歷史。

## 子專案一覽

| Submodule | 說明 | GitHub |
|-----------|------|--------|
| autogo | Windows 桌面螢幕 agent | [link](https://github.com/gsinvest017-ai/autogo) |
| gs-claude-config | `~/.claude` chezmoi 設定管理 | [link](https://github.com/gsinvest017-ai/gs-claude-config) |
| gs-gh-summary | GitHub 活動摘要工具 | [link](https://github.com/gsinvest017-ai/gs-gh-summary) |
| gs-risk-manager | 風險管理系統 | [link](https://github.com/gsinvest017-ai/gs-risk-manager) |
| gs-strategy | 量化策略研究 + 爬蟲 | [link](https://github.com/gsinvest017-ai/gs-strategy) |
| gs-trading-portal | 交易入口 (Genesis gold UI) | [link](https://github.com/gsinvest017-ai/gs-trading-portal) |
| gs-zipline-tej | Zipline + TEJ 台灣回測框架 | [link](https://github.com/gsinvest017-ai/gs-zipline-tej) |
| tw-news-board | 台灣新聞看板 | [link](https://github.com/gsinvest017-ai/tw-news-board) |
| tw-sentiment-radar | 台股情緒雷達 | [link](https://github.com/gsinvest017-ai/tw-sentiment-radar) |
| gs-scraper | 量化資料爬蟲 (QUANTDATA) | [link](https://github.com/gsinvest017-ai/gs-scraper) |
| trading-SySTEM | 實盤交易系統 (gb10, branch: dev) | [link](https://github.com/gsinvest017-ai/trading-SySTEM) |

## 快速開始

```powershell
# 第一次 clone 整個 monorepo（含所有 submodule）
git clone --recurse-submodules https://github.com/gsinvest017-ai/gs-monorepo.git

# 若已 clone，補初始化 submodules
git submodule update --init --recursive
```

## 日常指令

```powershell
# 把所有 submodule 更新到各自 remote 最新 HEAD
.\scripts\pull-all.ps1

# 查看每個 submodule 最近 3 個 commit + status
.\scripts\status-all.ps1

# 在每個 submodule 跑任意指令
.\scripts\run-in.ps1 "git log --oneline -1"

# 把更新後的 submodule SHA pin 存回 monorepo
.\scripts\sync-pins.ps1 -Message "chore: sync 2025-06-02"
```

## Service Monitor Dashboard

監控所有 submodule server 的 prod/test 運行狀態（port 探測 + PID 追蹤）。

```powershell
# 啟動 dashboard（前景，port 9000）
.\scripts\start-dashboard.ps1

# 啟動並自動開瀏覽器
.\scripts\start-dashboard.ps1 -Open

# 背景執行
.\scripts\start-dashboard.ps1 -Detach
```

Dashboard 位於 `http://localhost:9000/` — 每 5 秒自動重整。
顯示欄位：服務名稱 / Env(prod|test) / Host IP / Port / 狀態 / PID / 延遲 / 開啟連結。

---

## 生產/測試環境分離

各 server 型 submodule 可透過 monorepo 層腳本以不同 port 分別啟動，
**不需修改任何 submodule codebase**。

### Port 對照表

| 服務 | Prod | Test | 說明 |
|------|------|------|------|
| gs-trading-portal | 8123 | 8223 | Genesis gold UI |
| gs-gh-summary | 8790 | 8890 | GitHub 活動看板 |
| tw-news-board | 8787 | 8887 | 台股消息面看板 |
| tw-sentiment-radar | 8788 | 8888 | 情緒雷達（依賴 tw-news-board） |
| gs-risk-manager | 5066 | 5166 | 風險 dashboard |
| autogo | 8765 | 8865 | 桌面 agent |
| gs-scraper | 5050 | ⚠️ — | port 硬編碼，test 暫不支援 |
| trading-SySTEM | 8501 | 8601 | Test 僅起 Streamlit UI |

### 快速指令

```powershell
# 啟動全部 prod 服務（背景）
.\scripts\start-env.ps1 -Env prod

# 啟動全部 test 服務（背景）
.\scripts\start-env.ps1 -Env test

# 啟動單一 test 服務（前景，Ctrl-C 結束）
.\scripts\start-env.ps1 -Env test -Service tw-news-board

# 查看所有服務狀態（prod + test 並排）
.\scripts\status-env.ps1

# 停止 test 環境所有服務
.\scripts\stop-env.ps1 -Env test

# 試跑（只印指令，不實際啟動）
.\scripts\start-env.ps1 -Env test -DryRun
```

### 設定檔位置

| 路徑 | 說明 |
|------|------|
| `configs/services.ps1` | 服務定義表（port、指令、env vars） |
| `envs/prod/{service}.env` | Prod 環境變數覆蓋（機密填此） |
| `envs/test/{service}.env` | Test 環境變數覆蓋 |
| `run/{env}/{service}.pid` | 執行中 PID（gitignored） |
| `run/{env}/{service}.log` | stdout log（gitignored） |

> 詳細設計見 `docs/progress-env-separation.md`。

## CI/CD

- **ci-all.yml** — push 到 main / PR 時，自動偵測變動的 submodule 並平行跑各自 CI（Python pytest / Node npm test）。
- **release.yml** — `workflow_dispatch` 觸發，在所有（或指定）submodule 打協調版本 tag。

> `GH_PAT` secret 已設定（2026-06-02）。

## packages/

保留給未來共用套件（例如 Python `gs-common`、TS shared types）。目前為空。
