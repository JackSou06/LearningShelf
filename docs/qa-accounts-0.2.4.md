# Q&A 連線與金鑰保留（0.2.4 build21）

## 使用

在任何課程的主題問答按「AI 設定」。

- **ChatGPT 帳號**：選此方式，按 **Continue with ChatGPT**，在官方瀏覽器頁登入、選工作區並授權方案使用。完成後回到 App，選擇帳號可用模型。可以新增帳號、切換已保存的註冊、重新登入、取消登入、登出及查看 ChatGPT 使用量。
- **API Key**：填入金鑰與模型，按保存。預設「保存在此 Mac，更新 App 後保留」。之後留空保存會沿用；取消勾選只對新輸入金鑰使用暫時模式，不刪除已保存值。要移除請按「清除金鑰」。

兩種方式的主題閱讀、Q&A、筆記、隱藏詳述、來源引用、表格／公式、問答保存、刪除和取消流程相同。Mac 分享到平板後，平板沿用 Mac 的選擇，由 Mac 完成請求與保存；平板沒有金鑰或登入權杖。獨立 HTML 仍使用 API Key，不提供此原生 OAuth 登入。

ChatGPT 方案資格、模型和可用額度以 OpenAI 授權及模型目錄為準，目前官方文件對符合資格的 Plus／Pro 帳號提供此流程。它不是通用 API 儲值金，也不承諾無限使用。額度不足會回報錯誤，讓使用者決定等待或切換 API Key。製作課程的 Codex CLI 帳號登入與 Q&A 的授權獨立。

## 更新與儲存

舊版未勾選記住時，保存設定會刪除已存 Keychain 值，且新金鑰預設只在記憶體中；更新關閉 App 後便須再填。舊版安裝包採 ad-hoc 簽章，更換版本時也可能遇到 Keychain 存取授權；這部分是可能原因，未在使用者實際 Keychain 上重現。

新版預設持久保存、不再因空白或暫時模式刪除既有值。憑證位於固定的 `~/Library/Application Support/LearningShelf/Credentials/`，不在 App bundle、教材、作者包或學習紀錄中：

| 檔案 | 用途 |
| --- | --- |
| `api-key` | 持久 API Key |
| `legacy-key-handled` | 遷移／清除標記，防止清除後再次帶入舊版金鑰 |
| `connection.json` | ChatGPT 主機 ID、帳號註冊、選定方式／模型與 OAuth 憑證 |
| `refresh.lock` | 多個 App 執行個體之間的 refresh 排他鎖 |

目錄權限 0700，檔案 0600；憑證以同目錄暫存檔和原子重新命名替換。OAuth 依官方建議使用本機權限保護檔案，不宣稱另有應用層加密。舊 Keychain 可讀時遷移，讀取失敗會提示且保留原資料；沒有保存過、已被舊版清除或失去 Keychain 授權的金鑰無法憑空恢復。自訂 `LEARNING_APP_DATA_DIR` 使用各自獨立設定，刻意切換此路徑不會沿用另一份設定。

## 實作約束

使用 OpenAI 開源客戶端官方 Sign in with ChatGPT 流程：安裝專屬 host ID、動態 client 註冊、loopback `127.0.0.1` 回傳、PKCE S256、state／nonce、JWKS RS256 驗證、issuer／audience／期限檢查。回傳的 client ID 綁定經驗證身分；只有授予 `resource.invoke` 與 `chatgpt.tokens.use.direct` 才啟用推論。重新登入期間保留原帳號；取消或驗證失敗不取代原有憑證。

近到期才 refresh，同一程序合併更新，跨程序使用排他鎖並重讀最新輪替憑證。登出嘗試撤銷可續期工作階段，清除該帳號本機權杖，保留註冊映射與 host ID；遠端撤銷未確認時明說並提供 ChatGPT 管理入口。有效 Q&A 需先取消／完成才能登出。

ChatGPT 模式使用公開 `/v1/models` 帳號目錄和 `/v1/responses`，`store:false`、`stream:true`。解析 SSE 並等待 `response.completed`，區分失敗、額度錯誤、未完成與連線中斷；不把部分文字當成完成。兩種模式均不啟用代理工具或額外讀檔，只送相同的主題文字上下文。

## 驗證範圍

- 隔離的原生 OAuth、簽章、refresh、撤銷、儲存、主題上下文和串流測試。
- 設定畫面的保存預設、空白保存、模式切換、登入／取消、模型／登出與手機版排版。
- 原有 Q&A 公式、表格、實際 Swift 區網分享的電腦／平板同步、取消與刪除回歸。
- 教材庫、更新、筆記與 SQLite／MD 保存的回歸；Apple Silicon／Intel 通用 App 編譯及簽章檢查。
- 官方公開 discovery 與 JWKS 已實際連線核對，宣告 RS256，端點符合實作。

未使用使用者真實 API Key 或 ChatGPT 權杖發問。因此真人授權成功、帳號方案適用性、真實模型回答與實際額度扣用尚未完成端到端驗證。Intel 執行與真實 iPad 仍須實機核對；通用編譯不等同這兩項驗證。

官方依據：[註冊與登入](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)、[帳號與續期](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)、[模型與推論](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)。
