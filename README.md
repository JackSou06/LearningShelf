# LearningShelf 學習工具

macOS 課程庫 App，搭配可獨立使用的瀏覽器閱讀器。課程由 JSON／Markdown 組成，新增教材不需改閱讀器。個人紀錄與教材分開。

## 開啟

- macOS：`dist/LearningShelf.app`，macOS 13 以上；安裝包為 Apple Silicon／Intel 通用版本（本機編譯，尚未公證）。
- 瀏覽器：`dist/LearningShelf.html`，雙擊可離線閱讀；AI Q&A 需網路與使用者 API key。
- App 主頁 →「匯入課程」，選課程 ZIP 或含 `course.json` 的資料夾；也可拖到 App。驗證成功後教材收進統一課程庫，原始 ZIP／資料夾可移動或刪除。
- 主頁 →「製作課程」，將開啟的 `AUTHORING.md` 與教材交給外部 AI，請 AI 交付一門課程的 ZIP。
- 內建完整 CH3（51 主題／42 題／七組演練）與線性代數範例（2 主題）。CH3 原始來源放在該課程 sources 中。

## 學習

目錄可收起，支援鍵盤左右鍵、觸控滑動與橫向觸控板翻頁。筆記與 Q&A 依主題保存；Q 預設收合，點擊查看 A。每筆問題旁的垃圾桶圖示可直接刪除，刪除後立即從 AI 上下文移除，不提供復原。刪除標記會保存，匯入舊備份不會自動把它加回。圖片、表格、長程式及演練可獨立捲動。已讀與答題分開處理。

Mac 紀錄以 SQLite 存在 `~/Library/Application Support/LearningShelf/`，課程列表、教材副本與有效快照也保存在此。新匯入教材由 App 保存，筆記不會修改原始教材；同課程 ID 的新 ZIP 會提示更新並保留紀錄，拒絕較舊版本。0.1.8 以前登記的外部資料夾會在下次開啟時收存；原資料夾若已遺失，仍可用快照閱讀並重新匯入。

瀏覽器的個人紀錄存在目前來源的 localStorage；換瀏覽器、裝置或分享網址前先匯出 JSON。透過資料夾選擇器臨時加入的瀏覽器課程，需要下次重新選擇；內建與分享課程直接可開啟。獨立瀏覽器檔案的紀錄與 App 分開；從 Mac 分享網址開啟的平板則使用下述電腦同步模式。

「紀錄」可匯出 JSON、完整課程與個人紀錄 MD，也可合併匯入 JSON。Q&A 依 ID 去重、衝突筆記一併保留。CH3 可直接匯入原講義的進度 JSON。未再出現的主題紀錄仍保留於匯出中。

AI 設定使用 OpenAI Responses API；模型可改。Mac 可由使用者勾選保存於 Keychain，未勾選則只記本次 App 執行期間；瀏覽器只保存在記憶體。API key 不進教材、備份或平板；分享模式由 Mac 代送請求。傳送範圍為目前主題教材、該主題全部 Q&A、筆記與新問題；不暗中截斷。API 回報的 Input／Output 用量顯示在回答下方。參考：[OpenAI Docs](https://developers.openai.com/api/docs/guides/text)。

## 平板與區網分享

App 開啟課程後點視窗上方「分享到平板」，將顯示的區網網址貼到同一網路的平板／瀏覽器。平板是電腦所選課程的操作畫面，筆記、Q&A、草稿、作答與複習標記均由 Mac 的同一份紀錄保存，兩邊開著時約每秒更新。翻頁時各自維持目前畫面，不會因另一端操作被突然跳頁。

先在 Mac 的「API 設定」填寫金鑰；已存於此 Mac Keychain 的金鑰會直接使用。平板不需填 API key，問題交給 Mac 依最新的當前主題教材、筆記與歷史 Q&A 建立請求。金鑰只存在 Mac，平板取得問題狀態與回答；模型設定也沿用 Mac。已送達 Mac 的問題由 Mac 完成並寫入 SQLite 與完整 MD，平板重新整理或關閉不會丟掉這筆問答。兩端都可以取消或刪除問答，刪除標記仍阻止舊畫面／備份把問答加回。

一般瀏覽器離線 HTML 仍使用自己的紀錄與 API 設定。分享模式不在平板 localStorage 保存筆記、Q&A 或 MD；更新只在 Mac 確認保存後顯示「已同步電腦」。同一筆記同時被不同畫面修改時會保留兩段內容並標示待核對，其他主題的修改不互相覆蓋。失去 Mac 連線時會顯示未連線／尚未同步，保留畫面中尚未送達的修改並於連線恢復後重試；這時請先等待同步完成再重新整理或關閉平板頁面。

此分享網址可讀寫選定課程的個人紀錄及使用此 Mac 的 API。靜態教材不包含原始 PDF／來源檔，也不提供任意檔案或金鑰讀取服務。

可隨時停止；切回主頁、切換課程或離開 App 會停止分享。Mac 睡眠、離線或防火牆封鎖時無法連線。分享網址含本次工作階段隨機路徑，重開分享後需用新的網址。

## 模組

- `protocol/`：作者協議與 JSON Schema。
- `courses/`：可直接交給 App 開啟的課程資料夾。
- `web/course-core.js`：純資料驗證、通用主題模型與 AI 上下文；Mac 與瀏覽器共用。
- `web/records.js`：紀錄格式、衝突合併、原 CH3 備份遷移。
- `web/reader.js`：閱讀與內容元件、測驗、筆記與問答 UI。
- `web/pagination.js`：分頁、觸控與觸控板手勢。
- `web/platform.js`：瀏覽器／原生檔案、保存與網路介面。
- `native/CourseLoader.swift`：安全資料夾存取、載入與共用驗證器。
- `native/RecordStore.swift`：SQLite 持久保存。
- `native/AppStore.swift`、`LearningShelf.swift`：原生主頁、課程庫與更新。
- `native/WebReader.swift`：WKWebView、具體動作橋接與原生 API transport。
- `native/ShareServer.swift`：選定課程的區網閱讀、紀錄同步及問答端點。
- `native/HostSession.swift`：電腦共用紀錄、API 請求生命週期與 MD 生成。
- `web/record-sync.js`：依編輯前後狀態合併修改，保留並行筆記與 Q&A 刪除標記。

## 建置與驗證

需要 Python 3、Node.js、Xcode command line tools。App 執行不需 Python／Node；KaTeX 已本機打包，授權見 `web/KaTeX-LICENSE.txt`。

```sh
node scripts/validate-course.cjs courses/ch3
node tests/core-checks.cjs
node tests/pagination-checks.cjs
node tests/sync-checks.cjs
node scripts/build_browser.cjs
python3 scripts/build_mac.py
```

macOS 圖示使用 `resources/learningShelf_icon_macos.png`：外圍透明、圓角主體置中，大小對齊系統 App 圖示。原始圖片保留在 `resources/learningShelf_icon.png`。`build_mac.py` 會透過 `build_icon.py` 產生各尺寸的 `LearningShelf.icns` 並寫入 App 設定。

原生測試：

```sh
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .swift-cache native/CourseLoader.swift native/RecordStore.swift native/MarkdownArchiveStore.swift tests/native_checks.swift -framework JavaScriptCore -framework PDFKit -lsqlite3 -o /tmp/learning-native-checks
/tmp/learning-native-checks "$PWD"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .swift-cache native/CourseLoader.swift native/RecordStore.swift native/MarkdownArchiveStore.swift native/KeyStore.swift native/HostSession.swift native/ShareServer.swift tests/share_checks.swift -framework JavaScriptCore -framework Network -framework Security -framework PDFKit -lsqlite3 -o /tmp/learning-share-checks
/tmp/learning-share-checks "$PWD"
```

`migrate_ch3.py` 與 `create_example.py` 是範例課程產生工具。執行移植會重建範例教材，不影響原 CH3 檔案或個人紀錄。

## 驗證與目前限制（2026-10-13）

已驗證 App 關閉重開後筆記與閱讀位置仍可恢復，兩門課程使用同一閱讀器，完整 CH3 轉換與七組演練、格式錯誤與不安全路徑拒絕、主題 AI 上下文隔離、備份合併及舊紀錄遷移、SQLite 關閉重開恢復。原生 App 主頁、課程開啟、外部資料夾選擇、筆記與實際 JSON 檔案匯出均已透過 UI 驗證。瀏覽器版以本機模擬回應驗證 Q&A 收合、用量、紀錄保存、測驗及逐步解說；1024×768 下 51 個 CH3 主題沒有整頁溢出。分享模組以 HTTP 驗證選定課程可讀及私有紀錄路徑拒絕；亦從 App 按分享後，以瀏覽器透過實際區網 IP 開啟課程。

未使用使用者真實 API key 發出驗證請求。實體 iPad 手勢、不同 Wi-Fi 裝置與 Intel Mac 尚需實機驗證。安裝包使用本機 ad-hoc 簽署，尚未 Apple 公證；此版可在開發用 Mac 使用。0.1.8 已加入手動檢查更新；尚未 Apple 公證，Intel Mac 與不同 macOS 版本仍需實機核對。

目前保留原有電子書模式，未加入連續捲動模式、自動 OCR、雲端同步、App 內產課或任意程式外掛。課程拆分／合併尚無自動筆記定位映射；舊主題紀錄會保留。原生 PDF 使用 PDFKit，按課程提供的實際 PDF 頁序跳頁。

### 0.1.1 修正

演練的下一步、Q&A 送出／展開／刪除造成的內容與高度更新均維持目前頁碼；逐步解說採固定的閱讀頁高度與獨立捲動。重新開課程才依保存的內容區塊定位。修正翻頁動畫中保存到上一頁錨點的問題。加入單筆 Q&A 刪除、復原及舊備份刪除標記合併。


## 0.1.2：恢復原教學功能

完整恢復九個結構／流程／sparse 圖解、程式演練 0/N 計數與完整程式行、byte/EOF/offset 圖、lseek 寫入、buffer 長條、範圍篩選、答題統計及原教學來源定位。Mac 以 PDFKit 跳至指定 PDF 頁序。

每門課的完整 MD（教學、原文附錄、筆記、全部 Q&A）自動寫入 `~/Library/Application Support/LearningShelf/Markdown/`，亦可在「紀錄」連結自選 MD。瀏覽器自動保存 MD，支援 File System Access API 時可連結檔案；其他瀏覽器使用匯出。

API 新預設與既有 0.1.1 設定一次性更新為 `gpt-6.1-sol`。每次請求仍僅包含該主題，不傳完整附錄。既有筆記、Q&A、答案與刪除標記保留。

資料與介面差異的完整核對在 `../planning/CH3移植差異.md`；原 0.1.1 未移植項目保留作歷史紀錄。


## 0.1.3：Q&A 刪除介面

刪除文字改為垃圾桶圖示，移除刪除後的復原提示與功能。已保存的刪除標記仍阻止舊備份重新帶回刪除的問答。


## 0.1.4：平板同步電腦（2026-10-14）

分享模式改用 Mac 的共同紀錄與 API transport。資料同步採編輯前、編輯後及主機最新狀態的合併，避免舊快照覆蓋其他主題、已完成回答與刪除標記。問答由主機建立上下文並管理完成、錯誤與取消，平板刷新不取消已接受的請求。MD 由主機依最新紀錄產生。

已執行原有內容與分頁檢查、同步合併檢查、原生 SQLite／MD 檢查，以及真實 Swift 分享服務的 HTTP 測試。兩個隔離瀏覽器畫面（其中一端以訊息轉接器測原生 Platform 分支）完成筆記雙向更新、連續輸入、既有問答載入、平板提問與刷新、回答回到上下文、跨端刪除／取消及不寫平板 localStorage；沒有瀏覽器直接對 OpenAI 發請求。API 回應使用測試替身，沒有使用真實金鑰產生付費請求；實體 iPad／不同 Wi-Fi 裝置與真實 API 呼叫仍需實機核對。

瀏覽器整合檢查需 Playwright 與 Chrome。先編譯上方 learning-share-checks，再執行 `node tests/mirror-browser-checks.cjs`；可用 LEARNING_PLAYWRIGHT_PATH 指定 Playwright 模組位置、LEARNING_SHARE_TEST_BIN 指定測試執行檔位置。測試只使用暫存資料庫與模擬 transport。


## 0.1.5：練習題點擊與同步修正

改用忽略物件欄位排列的內容比較，避免 Swift／JavaScript 序列化順序差異造成無限保存與練習題重畫。資料沒有變更時不重建畫面；只有真正改變的題目重畫，另一端重新作答時也會清除該題舊選取。

已用隔離紀錄重現舊版約 3 秒內替換題目控制項 201 次；修正版通過舊版本重答、選取保留、答案提交與解說、兩端作答同步、跨端重答、錯答與刷新保存，以及原內容／分頁／同步檢查。沒有替使用者提交練習答案，也沒有使用真實 API。

## 0.1.6：減少 Q&A 來源資料

「傳送內容」及實際API請求不再額外附上來源清單和每個區塊的引用定位JSON。課程正文、圖片原文／位置／標記詳述、當前主題筆記與全部Q&A保留；正文中的必要頁次或引用字句不被自動刪除。Mac、分享平板及獨立瀏覽器共用相同規則。閱讀器來源面板與完整MD匯出仍保留來源及定位，課程檔案與個人紀錄不變。


## 0.1.7：逐步解說顯示

簡短逐步解說依所有步驟中最長內容配置固定高度，避免初始說明被強制撐滿整頁。切換只顯示目前步驟，其他步驟不出現在鍵盤操作與輔助閱讀中；長內容在目前步驟內捲動，上／下一步控制保留在區塊底部。完整程式演練仍使用原有頁面高度。教材、ID、筆記與 Q&A 均保留。


## 0.1.8：App 更新與發布

主頁及 macOS「學習工具」選單的「檢查更新」會讀取 GitHub 上的簽署清單，顯示版本與更新內容。下載完成後按「Install and Relaunch」安裝並重開。只提供手動檢查與安裝，不在背景定時檢查、下載或更新；Sparkle 的視窗會依其支援的系統語言顯示。

首次請從 [GitHub Releases](https://github.com/JackSou06/LearningShelf/releases/latest) 下載 `LearningShelf-版本.zip`，解壓縮後將 `LearningShelf.app` 放入「應用程式」再開啟。0.1.7 與更舊的版本沒有更新入口，需要手動安裝一次。此發行版使用 ad-hoc 程式簽署，未經 Apple 公證；macOS 首次啟動可能需在「系統設定 → 隱私權與安全性」允許開啟。Sparkle 的 EdDSA 簽章驗證與 Apple 公證為不同用途；不必停用 Gatekeeper。

更新／結束 App 前會等待所有原生閱讀器將筆記、草稿與進度寫入 SQLite，再同步 MD 及 checkpoint。保存失敗會保持 App 開啟；AI 回答進行中會提示等待或先取消，再按安裝。安裝將停止區網分享，平板請先確認「已同步電腦」；重開 App 後重新分享並使用新網址。紀錄資料夾、外部課程與 Keychain 項目不隨 app 替換；macOS 可能再次要求授權存取既有 Keychain 金鑰。

內建課程以相對位置跟隨目前 App；也支援舊版 catalog 中的 app 內絕對路徑。使用者匯入的外部課程仍依原位置開啟。

### 建置與金鑰

`app-version.json` 是版本、遞增 build number、repo、清單網址及公開金鑰的唯一設定來源。正式 App 仍為 Apple Silicon／Intel 通用版本、macOS 13 以上。

```sh
python3 scripts/build_mac.py
```

首次建置會從 Sparkle 官方下載固定的 2.10.0 並驗證 SHA-256，快取於忽略追蹤的 `.build-tools/`。App 內嵌框架與授權，執行時不需要 Python、Git 或 Sparkle 開發工具。

更新私鑰保存在發行者 Mac 的 login Keychain，account 為 `LearningShelf-update-signing`；原始碼與 App 僅包含公開金鑰。另一台 Mac 可以建置但無法代替原金鑰簽署更新。第一次初始化新專案時可執行下列命令；本專案已完成，請保留既有金鑰：

```sh
python3 scripts/sparkle_tools.py
.build-tools/Sparkle-2.10.0/bin/generate_keys --account LearningShelf-update-signing
```

切勿把私鑰、Keychain 密碼或 GitHub token 放入 repo。請自行安全備份原更新私鑰；遺失時，此無 Developer ID 的發行方式可能需要使用者手動重新安裝新版才能換金鑰。框架會在解壓前驗證更新包，並驗證更新清單；不得手動修改已簽署 XML。

### 發布新版

1. 修改程式，增加 `app-version.json` 的 `version` 與整數 `build`（兩者均須比上一版大）。
2. 新增 `updates/版本.md` 更新說明，執行相關檢查，將原始碼 commit。
3. 在有原更新私鑰的 Mac 執行：

```sh
python3 scripts/release_mac.py --publish
```

不加 `--publish` 只準備本機更新包。`--skip-build` 可使用已建好的正式 App；腳本會檢查版本、Bundle ID、更新金鑰與 feed 設定，拒絕測試 App。GitHub 認證沿用 Git credential helper，亦支援此命令的 `GH_TOKEN`／`GITHUB_TOKEN` 環境變數；不把 token 寫入檔案或命令列參數。

腳本依序建置、產生 ZIP、簽署並驗證 ZIP 與清單、推送原始碼、建立 draft Release、上傳並驗證資產雜湊、公開 Release、匿名下載核對內容，最後才 commit/push `updates/appcast.xml`。更新包位於 Releases；清單固定由 `raw.githubusercontent.com` 的 main 分支提供，不需另外設定 GitHub Pages。失敗時不提前發布清單；已公開的版本與資產不自動覆寫，修正後請增加版本重發。GitHub/CDN 快取可能讓剛發布的版本稍晚才出現。

產物位於 `dist/releases/版本/`。本階段由這台 Mac 發布，尚未加入 GitHub Actions。

### 更新驗證

`tests/update_checks.swift` 使用獨立資料夾核對內建課程搬移、外部課程位置、SQLite／草稿重開、MD flush、保存失敗恢復與 AI 進行中保護。可用以下方式執行：

```sh
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .swift-cache native/AppStore.swift native/CourseLibrary.swift native/CourseLoader.swift native/RecordStore.swift native/MarkdownArchiveStore.swift native/KeyStore.swift native/HostSession.swift native/ShareServer.swift tests/update_checks.swift -I native/CArchive -larchive -framework SwiftUI -framework JavaScriptCore -framework Network -framework Security -framework PDFKit -lsqlite3 -o /tmp/learning-update-checks
/tmp/learning-update-checks "$PWD"
```

實際安裝驗證使用 `build_mac.py --test-config 測試設定.json --output dist/測試資料夾`；設定需提供 `version`、`build`、`feedURL` 與絕對路徑 `testDataDirectory`。此模式使用獨立 Bundle ID 與資料目錄，只放寬本機測試網路，發布腳本會拒絕上傳測試版。


## 0.1.9：課程 ZIP、統一課程庫、教材更新與刪除

課程 ZIP 可拖到主頁或閱讀畫面，也可按「匯入課程」選擇 ZIP／資料夾，一次加入多份。每個 ZIP 只含一門課，`course.json` 位於根目錄或唯一一個最上層資料夾內；支援中文 UTF-8 檔名。Finder 自帶的 `__MACOSX`／`.DS_Store`／AppleDouble metadata 會忽略。

App 使用 macOS 系統 libarchive 串流讀取 ZIP，不依賴使用者安裝 Python 或解壓工具。先解壓至暫存位置、驗證全部教材，再將完整內容保存到 `~/Library/Application Support/LearningShelf/Courses/`。解壓限制為 200 MB／10,000 個項目；課程 JSON／Markdown／圖片原有 20 MB 限制仍適用。加密、連結、路徑穿越、重複檔名、損壞內容與不完整 ZIP 會拒絕匯入。

同一 `courseId` 對應同一門課。再次匯入會顯示版本、主題數與保留紀錄說明；使用者取消時不改動教材。較舊版號不能覆蓋新版；同版號重新匯入也須確認。作者需保留穩定 ID 並提高 `contentVersion`。更新採完整驗證後的新教材副本，課程清單成功寫入後才清理舊教材；儲存失敗時舊版保持可用。

筆記、Q&A、草稿、進度、複習標記、已作答答案與刪除標記依課程 ID 保留；題目版本改變時閱讀器仍會提示重新作答。更新／刪除會先保存開啟中的紀錄；該課程的 AI 回答進行中時會要求先等待或取消。切換課程後原平板分享停止，需要重新分享。舊閱讀畫面的延遲請求不能重新寫回已更新／刪除的課程。

每門課旁的垃圾桶與右鍵選單均可刪除課程。預設只刪 App 收存的教材與課程列表，保留學習紀錄；重新匯入同一 ID 可以接續。勾選「一併刪除」會同時刪除此課程在 App 的紀錄及自動 MD，並解除 MD 綁定。原始 ZIP、外部來源資料夾與使用者另存／匯出的檔案不刪除。內建課程從列表刪除後不會在重新開 App 時自動出現；App 內建資源不直接修改，以維持程式簽章。

核心回歸檢查使用隔離資料，不接觸個人學習紀錄：

0.1.9 已通過課程庫、更新保存、分享同步與 JavaScript 回歸檢查，以及 Apple Silicon／Intel 通用版本建置。另以獨立資料目錄實際操作 ZIP 選取匯入、版本確認、重新匯入後筆記與草稿保留，並檢查刪除確認視窗。刪除／清除紀錄與重新匯入由原生測試驗證；Finder 拖曳尚未完成介面實測。

```sh
python3 tests/create_course_packages.py /tmp/learningshelf-course-fixtures
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .swift-cache -I native/CArchive native/AppStore.swift native/CourseLibrary.swift native/CourseLoader.swift native/RecordStore.swift native/MarkdownArchiveStore.swift native/KeyStore.swift native/HostSession.swift native/ShareServer.swift tests/course_library_checks.swift -framework SwiftUI -framework JavaScriptCore -framework Network -framework Security -framework PDFKit -lsqlite3 -larchive -o /tmp/learning-course-library-checks
/tmp/learning-course-library-checks "$PWD" /tmp/learningshelf-course-fixtures
```
