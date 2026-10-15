# 0.1.8 更新驗證（2026-10-15）

以本機 Apple Silicon Mac 執行，測試 App 使用 `com.jacksou.LearningShelf.update-test` 與 `dist/update-test/data`，沒有使用個人學習紀錄或真實 API key。

- 通用 arm64／x86_64 App 編譯成功，`codesign --verify --strict --deep` 通過。
- `core-checks.cjs`、`pagination-checks.cjs`、`sync-checks.cjs` 通過。
- 真實 Swift 分享服務 `share_checks.swift` 通過，涵蓋同步、SQLite／MD、取消及刪除。
- `update_checks.swift` 通過：舊版課程路徑搬移、外部課程位置保留、惡意路徑／ID 不符拒絕、草稿及 SQLite 重開、延遲 MD 保存、保存失敗恢復與 AI 進行中阻擋。
- 真實 App／WKWebView 中寫入中文筆記與問答草稿，從 macOS 選單啟動 Sparkle。
- 使用本機 HTTP 更新服務；更新包和清單以正式 Keychain 中的 EdDSA 金鑰簽署。
- 修改 ZIP 一個 byte：出現更新簽章錯誤，未安裝。
- 修改 XML 更新內容而未重簽：出現清單簽章錯誤，未顯示未驗證的更新。
- 有效更新：下載、驗證、解壓、Install and Relaunch、實際替換 App、自動啟動新程序、畫面顯示 0.1.8（11）。
- 更新後 SQLite 內測試筆記與問答草稿保留；內建課程仍可定位。
- 新版按「檢查更新」顯示已是最新版。

Intel Mac、其他 macOS 版本、跨裝置 Wi-Fi、首次從網路下載後的 Gatekeeper 授權、Keychain 既有 API key 授權提示尚需各自實機核對。安裝測試不等同 Apple 公證，此版未公證。
