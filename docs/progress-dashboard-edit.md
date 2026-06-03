# Dashboard 可編輯欄位 + Start/Stop — 進度追蹤

## 目標

1. Host IP / Port 欄位可手動 inline 編輯（覆蓋值存 `configs/overrides.json`）
2. 新增 **Host Name** 欄位：下拉選單預設 local/local-wsl/gb10/dell，可手動新增
3. 每列新增 **Start / Stop** 按鈕，直接在 dashboard 啟停服務
4. 變更均持久化，重啟 dashboard 後仍保留

---

## Milestones

| # | 標題 | 狀態 |
|---|------|------|
| M1 | 進度檔 + `configs/overrides.json` 初始化 | ✅ |
| M2 | `server.py` 擴充（overrides CRUD + start/stop endpoints） | ✅ |
| M3 | `app.js` + `style.css` + `index.html` 更新 | ✅ |
| M4 | 收尾 + smoke test | ✅ |

---

## API 設計

```
GET  /api/status                       → 含 host_presets + overrides 的完整狀態
GET  /api/host-presets                 → 主機名稱選項列表
POST /api/host-presets                 → 新增選項 { "name": "myhost" }

PATCH /api/services/{name}/{env}       → 更新欄位 { host_name?, host_ip?, port? }
POST  /api/services/{name}/{env}/start → 啟動（呼叫 start-env.ps1 -Detach）
POST  /api/services/{name}/{env}/stop  → 停止（呼叫 stop-env.ps1）
```

## Fallback

```powershell
git checkout <M2-hash> -- dashboard/server.py
git checkout <M2-hash> -- dashboard/static/
```
