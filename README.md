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

## CI/CD

- **ci-all.yml** — push 到 main / PR 時，自動偵測變動的 submodule 並平行跑各自 CI（Python pytest / Node npm test）。
- **release.yml** — `workflow_dispatch` 觸發，在所有（或指定）submodule 打協調版本 tag。

> `GH_PAT` secret 已設定（2026-06-02）。

## packages/

保留給未來共用套件（例如 Python `gs-common`、TS shared types）。目前為空。
