# 課程製作協議 1.0（LearningShelf）

本協議供外部 AI 製作可由 LearningShelf 開啟的課程。請連同教材交給 AI。格式驗證器：web/course-core.js；命令列：node scripts/validate-course.cjs 課程資料夾。Schema：course.schema.json。

作者要求補充：2026-10-14，新增每張圖片的完整視覺描述、標記辨識、圖意理解與 Q&A 上下文要求；資料格式仍為 1.0。

## A. 給教材作者與 AI 的任務

將使用者提供的教材編排為可供學習的課程資料夾，最後交付一個可直接拖進 LearningShelf 的 ZIP 壓縮包。完整保留原教材的正文、圖解、程式演練、表格、題目及例外說明；不得為了套用通用元件而刪減或把圖解退化成文字。保留內容來源，解釋概念、提供適量例子與理解檢查，依以下格式輸出。不要生成一套新的網站或 App。

開始前確認或明示假設：目標學習者、先備知識、希望學會什麼、此次範圍、教材優先順序、語言。缺失資料列為待核對，不虛構頁碼、時間碼、引用或來源內容。

建議先輸出大綱供使用者調整，再產生課程；使用者要求直接完成時可採明示假設繼續。

每個主題聚焦一個可說清楚的學習目標。建議次序是問題或動機、概念、例子、常見誤解、核心重點、理解檢查；並非每個主題都需要硬套全部段落。避免裝飾性口號及為了湊長度而重複解釋。

## B. 資料夾

```text
my-course/
  course.json
  topics/
    topic-one.json
    topic-one.md
  assets/                  # 選用：本課程使用的圖片等
  sources/                 # 選用：使用者允許隨課程提供的原始教材
  AUTHOR_NOTES.md           # 選用：教材缺口、推論、待核對事項
```

UTF-8；JSON 使用嚴格語法，不含註解與尾端逗號。所有檔案引用相對於課程根目錄，使用 `/`。不可用絕對路徑、`..`、符號連結跳出課程根目錄或從網路載入程式。

`course.json` 是唯一入口。教材不得包含使用者的 API key、私人 Q&A、學習進度或 App 設定。

## C. 最小完整範例

以下三個檔案構成一份最小課程，檔案間的 ID 與引用須一致。

### course.json

```json
{
  "schemaVersion": "1.0",
  "courseId": "example-linear-algebra",
  "contentVersion": "1.0.0",
  "title": "線性代數入門",
  "language": "zh-Hant",
  "audience": "初學者",
  "objectives": ["能解釋線性組合"],
  "modules": [
    {
      "id": "vectors",
      "title": "向量",
      "topics": ["linear-combination"]
    }
  ],
  "topics": [
    {"id": "linear-combination", "file": "topics/topic-one.json"}
  ],
  "sources": []
}
```

### topics/topic-one.json

```json
{
  "id": "linear-combination",
  "title": "什麼是線性組合？",
  "objectives": ["能以純量倍數與相加說明線性組合"],
  "prerequisites": [],
  "blocks": [
    {
      "id": "explanation",
      "type": "markdown",
      "file": "topics/topic-one.md",
      "references": []
    },
    {
      "id": "check-understanding",
      "type": "singleChoice",
      "question": "線性組合包含哪兩種操作？",
      "options": [
        {"id": "scale-add", "text": "向量乘純量，再相加"},
        {"id": "length-only", "text": "只比較向量長度"}
      ],
      "answerId": "scale-add",
      "explanation": "先對各向量乘上係數，再將結果相加。"
    }
  ]
}
```

### topics/topic-one.md

```markdown
給定數個向量，將每個向量乘上一個純量，再把結果相加，所得就是這些向量的線性組合。

例如 u = (1, 0)、v = (0, 1)，則 2u + 3v = (2, 3)。

重點是「乘上係數」與「相加」。係數可以是零，並不要求每個向量都對結果產生非零貢獻。
```

上例是作者自編說明，因此 sources 與 references 可空白。依指定教材編寫的正式課程應記錄實際來源；沒有可靠定位時只提供來源名稱與定位不詳，不能補造頁碼。

## D. 欄位與排序規則

- schemaVersion：協議主版本／次版本，與課程內容版號分開。目前版本為 1.0。
- courseId：課程庫中的穩定唯一識別；正式課程建議 UUID。示例使用易讀 ID。更新不更改，另建課程則換新 ID。
- contentVersion：教材版本，格式 major.minor.patch；每次內容更新提高版號。
- title、language 必填；audience、objectives 選填但建議提供。
- modules、topics 都不可空。章節順序與章節內 topics 陣列共同決定閱讀順序。每個主題恰屬一個章節。
- topics 是 ID 到檔案路徑的目錄，與主題檔內 id 必須一致。
- 主題 title 與非空 blocks 必填；objectives、prerequisites 選填。先備主題 ID 必須存在，不可形成依賴循環。
- topic ID 在課程內唯一；block ID 在主題內唯一；option ID 在題目內唯一。ID 使用穩定識別，不能使用畫面頁碼。
- 主題 blocks 陣列決定呈現順序。Markdown 中的段落不是獨立可持久定位區塊；需要精確標註時分成數個有 ID 的 block。
- 課程可選填 scopes：`[{"id":"core","title":"本次課程"},{"id":"next","title":"後續內容"}]`，主題 scope 指向其中 ID；未定義時不顯示範圍選單。
- 主題可選填 lead（導讀）、focus（本主題問題）、estimatedMinutes（正數）、assessment（整組題目顯示成績）、backTo（返回的 topic ID）。
- archiveFiles：選用的 `[{"title":"原教材附錄","file":"topics/appendix.md"}]`，僅加入完整 MD，不加入每次 AI 的主題上下文。
- 公開欄位拼錯應視為錯誤；擴充資料只放明確的 extensions 物件，不偷偷依賴未知欄位。

## E. 內容區塊

所有區塊必須有 id、type，可附 references。下列欄位是各型別額外要求。

| type | 必填內容 | 顯示與上下文 |
|---|---|---|
| markdown | file | 安全 Markdown 子集；正文直接進主題上下文 |
| code | language、code | 程式碼顯示與複製；不執行 |
| table | columns 字串陣列、rows 二維字串陣列 | 每列欄位數須相同；生成可讀文字表格 |
| image | file、alt、description | alt 為簡短替代文字，description 說明圖中關鍵物件與關係，供 AI 與無圖環境使用；每張圖片須另依 E.1 提供主題 MD 詳述 |
| math | latex、description | 顯示數學式；LaTeX 原文與說明可加入上下文，不執行 TeX 程式 |
| singleChoice | question、options、answerId、explanation | 至少兩個選項、唯一正解；答案 ID 必須存在；回答後解釋 |
| reveal | prompt、answerMarkdown | 自我預測後展開解答；與個人 AI Q&A 分開 |
| steps | steps 非空陣列 | 每一步含 id、title、bodyMarkdown，可有 code 與 snapshot。程式演練指定 presentation: "program"、initialState: true；第一筆為初始狀態，計數從 0 / N 開始，列出所有程式行並標示目前行 |
| diagram | layout | flow 三層／多節點結構卡、routes 箭頭流程、sparse 區段示意；結構和說明都進 AI 上下文 |

Markdown 子集先包含標題、段落、列表、強調、行內程式碼、程式碼區塊、表格和安全連結。圖片、公式、互動題目使用對應區塊，避免私創 Markdown 語法。原始 HTML、腳本、iframe 不屬於格式。

另有兩個檔案 I/O 教學元件：filePosition（initialText 字串、maxOffset 正整數且不超過 1000）、callCount（bytes 正整數、buffers 正整數陣列）。

diagram 使用安全結構化資料，不寫 HTML。所有字串以文字或安全 Markdown 呈現：

- layout: "flow" → 非空 nodes，每筆 kicker、title、detailMarkdown，可選 dark 布林值。
- layout: "routes" → 非空 routes，每筆 label 與非空 nodes 字串陣列。
- layout: "sparse" → 非空 segments，每筆 text 與 range。
- 可附 title、captionMarkdown、metrics（每筆 label、value）。所有圖中資訊都要完整填入，不能只留下籠統圖名。每組 1–20 筆。
- markdown 可用 role: "takeaway" 顯示重點框；file 內容不需要再次寫「重點」標題。
- callCount 可選 initialBuffer（須在 buffers 中），例如 4096，顯示完整呼叫數及相對 1-byte buffer 的長條。

steps 的 snapshot 僅供展示，不執行程式；欄位為 processes（process 名稱 → fd/entry 對照）、entries（entry 名稱 → offset、file、flags、refs）、files（檔名 → 字串內容）、output（最近輸出）。一般課程不需要提供 snapshot。程式演練以逐 byte 格、索引、EOF 與各 entry offset 指標呈現檔案，並列 fd table、entry refs、flags、file size 及最近讀寫。initialState: true 表示 steps[0] 不計入操作步數。

所有教學內容只維護一份；App 從同一組 blocks 生成閱讀畫面與 AI 上下文。不得額外提供一份內容不同的 topicTeaching。

未知元件與未知公開欄位會被拒絕，不默默略過。第一版僅使用此協議定義的元件；其他資料放 extensions 物件。目前尚無外掛／fallback 載入功能。

## E.1 每張圖片的詳細描述、標記辨識與理解（必做）

此要求適用於課程中**每一張圖片**，包含 PPT／PPTX 或 PDF 投影片、講義掃描、照片、截圖、圖表、改編圖與含手寫標記的教材，不限於概念圖。製作者必須逐張實際檢視，以足夠解析度渲染、放大或分區查看。文字層擷取或 OCR 只能輔助辨識，不能代替看圖。保留圖片，並把詳細視覺資訊與理解後的解說寫進所屬主題的 Markdown，讓使用者可詢問圖中的任意可辨識內容。

1. **完整辨識可見內容**：記錄所有可辨識的文字、標題、圖中標籤、數值與單位、表格欄列、公式、程式、註解、頁腳及例外條件，不因判斷「不是核心概念」而省略。保留原文用字、大小寫、符號、上下標，以及會影響含義的換行或排列；可在旁邊補翻譯與解釋。小字、手寫字及重疊部分需放大核對；看不清時指出具體位置與「無法辨識／待核對」，不得猜補。
2. **描述版面與物件**：依閱讀順序分區描述，例如「左上標題」「右側流程圖」「下方第二段」。交代各區的位置、相對排列、形狀、顏色、線條、字體強調、圖例、圖示、照片物件、介面元素及彼此關係。若多處有相同文字或相似圖案，給各區／物件可區分的文字識別。定位以真實可見位置為準；只有可靠量測時才使用座標，不能捏造精確位置或顏色。
3. **逐一記錄所有標記**：圈選、highlight／螢光底色、底線、框線、箭頭、括號、刪除線、勾叉、星號、編號、手寫補充及其他可見記號，都要描述其種類、可辨識的顏色、位置、覆蓋範圍、指向對象與彼此連接。每個標記使用可引用的文字識別，如「標記 M1：右上紅圈」。逐字寫出被圈起／highlight 的內容，區分整句或部分字詞、跨行或跨區；標記包住圖形時描述該圖形，箭頭要記錄起點與終點。手寫註記保留可辨識原文。無標記也明示「未見額外圈選、highlight 或手寫註記」；不要把原圖的配色自動當成使用者 highlight。
4. **解釋內容及被標記項目**：在上述可見事實之外，說明物件、文字、圖表、程式與標記所指內容的意思。圖表交代座標、趨勢、比較與條件；公式交代符號、前提與推導；程式交代輸入輸出、前後狀態與錯誤路徑。對每個被標記的字詞或句子，依頁面脈絡解釋其含義，讓「黃色 highlight 的字是什麼意思」能由文字回答。分清「圖中可見事實」「內容解釋」「推論／待核對」；看得到圈選不等於知道標記者的意圖，不能自行聲稱圈起是因為考試重點、疑惑或錯誤。只抄文字、只描述概念或寫籠統圖名都不足以完成。
5. **每圖連接至當前主題**：每個 `image` block 必須有對應的詳細 MD，透過同一主題內的 `markdown` block 的 `file` 引用，依教學順序相鄰呈現。MD 明示對應圖片的 block ID／檔名與可靠來源定位；同一 MD 可描述多張圖，但每張要有獨立段落與各自標記清單，不混在一起。表格、公式、程式與步驟可另用協議元件精確呈現，MD 須清楚對應這些元件。完整描述屬於正式教學內容，不能只存於未引用的 MD、附錄或作者備註。
6. **圖片摘要與改版一致**：`alt` 提供簡短識別；`description` 摘要關鍵物件、關係與明顯標記，詳細內容放在對應 MD。以最終交付、App 實際顯示的圖片核對描述，包括裁切範圍、文字、數值、箭頭及新增／刪除標記；改圖或改標記時同步更新 MD、description、相關元件與 contentVersion。分清原教材、使用者隨教材提供的可見註記、作者新增說明；無法判斷標記出處時註明出處不明。原 PDF 頁碼只定位原來源，改編圖差異另註。
7. **檢查 Q&A 的實際文字**：目前 App 的 Q&A 取得當前主題的 blocks 文字及圖片 alt／description，不會自動辨識圖片像素、原 PDF／PPT，也不會自動取得其他主題。只放在 `sources`、`archiveFiles` 或 AUTHOR_NOTES.md 的描述不足以支援當前主題問答。交付前用「傳送內容」或 `CourseCore.context`，確認每圖的原文、位置、標記及解釋均在實際上下文中。描述較長時分成多個有穩定 ID 的 markdown blocks，不得為縮短上下文而悄悄刪去圖片細節；若超過協議容量或有無法辨識的區域，明列限制與待核對事項。

### 連接圖片與 MD 的示例

以下是**自編示意**：左側 fd 3、fd 4 的箭頭指向右側 E1；「open file description」有黃色 highlight，E1 有紅色圈選。真實課程必須按實際圖片填寫，只有來源確實存在時才加入 references。

在主題的 `blocks` 加入：

```json
[
  {
    "id": "dup-slide",
    "type": "image",
    "file": "assets/dup-slide.png",
    "alt": "兩個 fd 指向 E1，含黃色 highlight 與紅圈",
    "description": "左側 fd 3 與 fd 4 的箭頭指向右側 E1。右側 open file description 字樣有黃色 highlight（M1），E1 有紅圈（M2）。兩個 fd 共享 E1 的檔案位置；詳述與標記解釋見相鄰的圖片 MD。"
  },
  {
    "id": "dup-slide-explanation",
    "type": "markdown",
    "file": "topics/dup-slide-explanation.md"
  }
]
```

對應 MD 示意片段（正式交付還須補齊該圖所有可辨識內容）：

```markdown
### 圖片識別與可見內容

對應 image block：dup-slide；檔案：assets/dup-slide.png。本例為自編示意。

左側由上至下列出「fd 3」「fd 4」，各有一條向右箭頭連至右側「E1」。右側另有文字「open file description」。

### 標記清單

- M1：右側文字「open file description」整個詞組有黃色 highlight；範圍不包含旁邊的「E1」。
- M2：右側「E1」被紅色圈線包住；不包含左側兩個 fd。
- 本示例未見其他額外標記或手寫文字。

### 標記內容的意思與圖中關係

M1 的「open file description」是核心維護的開啟檔案狀態；在這張示意圖中以 E1 表示。fd 是程序用來參照它的整數。M2 圈住的 E1 是同一個 entry 的識別，不是另一個 fd。

兩條箭頭連到同一個 E1，表示 dup 後 fd 3 與 fd 4 共享同一個 open file description，也共享其中的檔案位置；不是兩份獨立位置。圖中可確認 highlight 與圈選的位置，但無法由此判定標記者為何標記。
```

描述應細到不看圖的人也能辨認使用者所指的區域、文字或記號，再根據圖意回答。圈選與 highlight 是例子，要求不限於這些標記或上述示意圖。

## F. 來源與定位

來源及references仍須完整保留，供閱讀器查閱與完整MD匯出。2026-10-14起，Q&A「主題傳送內容」不再額外附上sources清單與references定位JSON，以減少重複token；正文、圖片詳細MD、圖像頁次／標記識別、當前主題筆記與Q&A仍完整傳送。不要因此刪除課程來源或正文中理解所需的圖片定位，也不要把必要教學內容只放在來源欄位。

course.json 的 sources 每筆至少含 id、title、kind；kind 為 pdf、text、web 或 reference。

- pdf／text 可含 file，指向包內來源。
- web 含 https URL。
- reference 可只記錄書名、版次等，不代表 App 可開啟未附帶的原始檔。
- 引用格式為 `{ "sourceId": "slides", "locator": { "kind": "pdfPage", "value": 17 } }`。
- pdfPage 是從 1 開始的 PDF 實際頁序；printedPage 另存書面頁碼字串，兩者不可混淆。
- 其他定位提案：section + 字串值、lineRange + 起訖正整數陣列、timeRange + 起訖秒數陣列、unknown + 說明字串。只有原始資料可支持時才填。
- sourceId 必須存在；引用到來源檔時檔案必須存在。未附檔的 reference 可作文字引用，介面須表明原文未附。
- 原教材間矛盾、AI 補充與不確定資訊寫進 AUTHOR_NOTES.md；面向學習者的重要不確定性也須在正文清楚表達。

## G. 更新既有課程

收到舊課程時保留語意未變的 ID，不因重新排序或改標題而全面產生新 ID。

- 修改文字：沿用 block ID，提高 contentVersion。
- 改版投影片：重新檢視最終顯示圖片，同步更新所屬主題的 MD、圖片 description 及相關元件；核對所有可見內容、圈選、highlight、手寫註記、位置與狀態一致，移除已不適用的舊說明。沿用語意未變的 ID，提高 contentVersion。
- 修改題目概念或答案：給新題目 block ID，避免把舊作答算成新題目的掌握度。
- 移動主題到別章：沿用 topic ID。
- 拆分／合併主題：提出舊新 ID 對照供匯入器處理，不自行修改個人紀錄。
- 不覆寫來源原文，不碰筆記、Q&A 或 API 設定。

更新以整包有效課程為單位。App 驗證與預覽後才套用；讀到寫入一半的 JSON 不得取代現有可用版本。

## H. 自檢與交付

交付前確認：JSON 可解析、ID 唯一、主題有歸屬、引用檔存在、圖片有說明、選項答案對應、來源不虛構、沒有私人資料與執行腳本。

所有圖片另需完成內容自檢：

- 列出每張圖片對應的主題、image block、詳細 MD 與相關語意區塊，核對每個標記的覆蓋原文與位置，並列出尚未辨識的區域，避免漏頁或圖片與解說錯配。
- 逐張看圖核對完整文字、數值、物件、版面、顏色、箭頭方向、流程與條件，以及所有圈選、highlight、底線、框線、刪除線、手寫註記等；改版圖以最終交付素材為準。
- 每張圖片檢查其詳述已進入實際 Q&A 傳送文字；每個有圖的主題另抽選圖意問題與視覺定位問題，例如「兩條箭頭為何指向同一物件？」和「右上黃色 highlight 的原文與意思是什麼？」。有標記時必須涵蓋標記原文、位置、範圍及含義；無標記時改查其他可見細節。只有圖名或概念摘要不算通過。
- 分開報告格式驗證、視覺內容核對與 Q&A 上下文檢查；格式驗證器無法判斷 OCR 或圖意解說是否正確。未呼叫 AI 時只能聲稱上下文已檢查，不能聲稱 AI 回答已測試。

如實區分「已執行驗證器」與「僅人工／AI 自檢」，不要宣稱未執行的測試通過。

正式交付一個 ZIP 壓縮包，以及簡短說明：課程名稱、範圍、主題數、所用來源、待核對事項。ZIP 內只放一門課，可直接放 `course.json`、`topics/`、`assets/`、`sources/`，或將它們包在唯一一個課程資料夾內。不可多包一層容器、放多門課、加密 ZIP 或加入符號連結／絕對路徑。請使用 UTF-8 檔名，保留相對目錄結構，不要打包 `.app`、閱讀器或另一套網站。

App 會驗證後將教材複製進統一課程庫；匯入成功後可移動或刪除原始 ZIP。更新同一門課時保留 `courseId` 與未變更概念的 ID，並提高 `contentVersion`。App 會提示取代教材且保留筆記、Q&A、草稿與進度；較舊版本不會覆蓋新版。格式驗證失敗不會改動既有課程。

如果所在環境無法產生 ZIP，請明確說明尚未交付壓縮包，交付完整資料夾或逐檔完整內容，再提供壓縮步驟；不能將散落程式碼聲稱為可匯入的 ZIP。每段程式碼前標示完整相對路徑，不用省略號代替教材。

未來 App 的錯誤清單範例：

```json
{
  "errors": [
    {
      "code": "MISSING_FILE",
      "file": "topics/topic-one.json",
      "pointer": "/blocks/0/file",
      "message": "找不到 topics/topic-one.md"
    }
  ]
}
```

將協議、原課程與這份報告交回同一 AI，要求只修正相關內容並保留穩定 ID，即可形成修正循環。

## I. 可複製的製作提示詞

> 請依隨附的《課程明文協議》將我的教材製作成課程資料夾。我的程度是＿＿，希望學會＿＿，本次範圍是＿＿，語言是＿＿。先整理大綱、先備知識與資料缺口，再依我的確認產出完整檔案。不要寫新的網站或 App；使用協議內建的內容區塊。完整保留教材與圖解、程式演練，不要簡化內容；對每張圖片逐張看圖、放大辨識並詳細描述，不只做 OCR 或概念摘要。將所有可辨識文字與物件、版面位置、顏色、圖表關係、程式狀態，以及每個圈選、highlight、箭頭、底線、手寫註記等的原文、範圍、位置與內容含義，寫入所屬主題的 markdown blocks，讓 App 的 Q&A 實際收到。分清可見事實與解釋，不猜測標記意圖；無法辨識的部分明列待核對。保留圖片並填寫有意義的 description；改版圖的文字解說須對應最終顯示版本。保留來源及可靠定位，不虛構教材細節。教學以理解、例子與自我檢查為主，避免冗餘文字。若在更新舊課程，保留未改變概念的 ID。最後交付一個只含一門課、可直接拖進 LearningShelf 匯入的 ZIP 壓縮包；保留 courseId，更新時提高 contentVersion。列出檔案清單、每張圖片與詳細 MD 的對照及標記辨識結果、自檢及 Q&A 上下文檢查結果；無法辨識或驗證的部分請明說。

## J. 大小與版本限制

每個 ZIP 與解壓後全部檔案各不得超過 200 MB，最多 10,000 個項目；每門課最多 2000 個主題、每主題最多 300 個區塊；JSON、Markdown 與圖片合計上限 20 MB；個人紀錄匯入上限 10 MB。PDF 原文按需開啟，不計入 AI 每次上下文。

Markdown 支援標題、段落、列表、粗體、行內程式碼、程式碼區塊及 HTTPS 連結。表格、公式、圖片請用專用元件。原始 HTML 以文字顯示。數學公式由本機 KaTeX 呈現；危險命令不允許。

schemaVersion 目前僅接受 1.0；未知元件拒絕匯入。JSON Schema 提供結構檢查，內建驗證器另檢查實際檔案、唯一 ID、章節歸屬、答案、先備循環和來源定位。通過格式檢查不代表內容事實正確。

目前主題拆分／合併尚無自動遷移映射；移除主題的個人紀錄保留於匯出中。請保留未變概念的 ID。
