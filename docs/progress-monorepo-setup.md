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

## M2 — 設定 GH_PAT secret

- `gh secret set GH_PAT --repo gsinvest017-ai/gs-monorepo` 設定完成（使用現有 gh auth token，具 repo+workflow scope）
- 驗證：`gh secret list` 確認 GH_PAT 存在（2026-06-02T02:27:32Z）

## M1 — 建立 GitHub repo 並 push

- `gh repo create gsinvest017-ai/gs-monorepo --private` → https://github.com/gsinvest017-ai/gs-monorepo
- `git push -u origin master` 成功
- Commit: 83577a4（M0 進度檔）+ 初始 feat commit 05dd579

## Fallback 指引

若需手動接手：
1. `cd C:\Users\User\gs-monorepo`
2. 確認已有 remote：`git remote -v`
3. 查進度：`git log --oneline`
4. submodule 狀態：`git submodule status`
