# gs-monorepo 完整建立進度

## 目標

把 gs-monorepo 推上 GitHub，補上 GH_PAT secret，並把 gs-scraper（WSL）和
trading-SySTEM（gb10 遠端機器）也初始化成 git repo、push 到 GitHub、掛入 monorepo 作為 submodule。

## 計畫 Milestones

- **M1** — 建立 `gsinvest017-ai/gs-monorepo` GitHub repo 並 push 初始 commit
- **M2** — 設定 `GH_PAT` secret（供 release workflow push submodule tags 用）
- **M3** — 初始化 `/home/kevin/gs-scraper`（WSL），push 到 GitHub，加入 submodule
- **M4** — SSH 進 gb10，處理 `trading-SySTEM`，push 到 GitHub，加入 submodule

## 進度日誌

（各 milestone 完成後追加）

## Fallback 指引

若需手動接手：
1. `cd C:\Users\User\gs-monorepo`
2. 確認已有 remote：`git remote -v`
3. 查進度：`git log --oneline`
4. submodule 狀態：`git submodule status`
