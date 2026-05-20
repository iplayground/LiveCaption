# AGENTS

## 專案定位

LiveCaption 是一套用於現場活動的即時語音辨識與翻譯系統。

系統目前分成兩個主要元件：

- `Portal/`：macOS 操作端 App。
- `Relay/`：後端服務。

## Portal 開發邊界

Portal 的責任：

- 擷取現場音訊。
- 執行即時語音辨識。
- 執行翻譯。
- 產生字幕事件。
- 將字幕事件送往 Relay。

開發 Portal 時應遵守：

- 以 macOS App 的使用情境為主。
- 保留 `Portal` 作為操作端名稱。
- Portal 目前需求系統為 macOS 26。
- 目前 Portal 的語音輸入支援國語與英語；字幕輸出支援台灣繁體中文、日文、英文與韓文，其中台灣繁體中文與英文為必要分析與 Portal 主畫面顯示語言。字幕輸出設定需清楚區分是否分析與是否在 Portal 主畫面顯示；Relay 發布、SRT 輸出與獨立字幕預覽依分析語言決定，不受 Portal 主畫面顯示設定影響。
- App 介面在地化目前只支援 `zh-TW` 與 `en-US`，且需清楚區分語音輸入語言、字幕輸出語言與 App 介面在地化語言。
- Portal 的 Azure OpenAI prompt 應描述通用判斷規則；避免為了修正單一案例而列舉特定詞或案例類別。處理中英 code-switch、近音誤判與前文一致性時，應以來源語言前文作為保守上下文，不得用翻譯結果回推原文。
- Portal 一台電腦同時間只允許一個 App 實例，且同一個 App 同時間只允許一個主視窗；主視窗關閉時 App 應結束。
- Portal 沒有對外散佈需求時，Xcode 專案應使用本機 ad-hoc 簽署，不設定 `DEVELOPMENT_TEAM` 或個人 Apple ID 相關資訊。
- 避免把後端發布、連線廣播、Azure Web PubSub 細節放進 Portal，除非是呼叫 Relay 所需的最小整合。

### Portal Swift 程式碼組織

Portal 的 Swift 程式碼應以「主要型別或單一功能責任」作為檔案邊界，避免為了就近修改而把不相關的 UI、平台橋接、狀態模型與服務邏輯塞進同一個檔案。

開發 Portal Swift 時應遵守：

- `ContentView.swift` 只負責主視窗的根層組合、主要狀態持有與流程協調；不可長期放置可重用 UI 元件、AppKit bridge、繪圖邏輯、文字排版演算法、音訊處理或網路整合細節。
- `UI/` 內的 SwiftUI 檔案應以主要畫面、面板或可重用元件命名；同一檔案若同時包含多個大型 view、設定面板、狀態列、繪圖 view 或 helper 型別，應拆成獨立檔案。
- AppKit / Foundation bridge，例如 `NSViewRepresentable`、`NSWindowDelegate`、`NSPanel` presenter、事件 monitor、睡眠防止 helper 或自訂 `NSView`，應放在明確命名的支援檔案中，除非只有該 view 私有使用且檔案仍保持小型清楚。
- 純資料型別、狀態模型、演算法與格式化邏輯應從 SwiftUI view 拆出；例如字幕預覽狀態、投影文字截斷、音訊輸入支援型別，不應藏在大型畫面檔中。
- 控制器或服務檔案應以外部整合或流程控制為主；若同時包含模型、delegate、低階取樣處理與狀態呈現邏輯，應拆出 `Support`、`Models` 或明確命名的同層支援檔。
- 單一 Swift 檔案超過約 500 行時，新增功能前必須先評估是否拆檔；超過約 800 行通常應視為需要拆分，除非能明確說明該檔仍是單一責任且拆分會降低可讀性。
- 新增大型 SwiftUI 區塊、設定 sheet、inspector、panel、繪圖/排版邏輯或平台 helper 時，優先建立新檔案，不要附加到既有綜合檔案。
- 拆檔應保持行為不變，先用純搬移與必要 import / 存取層級調整完成，再另行處理行為改動。
- Portal Swift 重構後應至少執行可用的 macOS build；若無法執行，需在回覆中明確說明原因與未驗證風險。

### Portal Xcode 建置工具使用

Portal 的 Xcode 建置與診斷應優先減少冗長輸出與重複設定，讓協作者能快速定位第一個真實錯誤。

處理 Portal Xcode build、scheme discovery、執行或診斷時應遵守：

- Apple Xcode MCP bridge（`xcode`，命令為 `xcrun mcpbridge`）是 Portal Xcode build、scheme discovery、執行與診斷的第一優先方案；若 Codex session 中可用，必須先使用它取得 Xcode 目前開啟 workspace、scheme、build diagnostics、執行狀態與 logs，避免直接讀取完整 `xcodebuild` 大量輸出。
- 若 Apple Xcode MCP 不可用，但 `xcodebuildmcp` 可用，且任務符合其 macOS build / diagnostics 能力，應優先使用 `xcodebuildmcp`；若它偏向 iOS simulator 工作流或無法乾淨支援 Portal macOS App，應回報限制並請使用者決定下一步。
- Xcode 的 Agent Activity 顯示 `Codex Inactive` 不代表設定失敗，只表示目前沒有 active Codex session 正在呼叫 Xcode MCP。若 `codex mcp list` 已顯示 `xcode` enabled，但 session 沒有露出 Xcode MCP tools，應提示重啟 Codex app 或開新 session 重新載入工具。
- 使用 Xcode MCP 前，應確認 Xcode 已開啟 `Portal/LiveCaptionPortal.xcodeproj` 或正確 project；若 Xcode 未開啟目標 project，必須提示使用者在 Xcode 開啟目標 project，不得自行改用 `xcodebuild` 指令。
- Xcode MCP 工具不可用、無法支援 macOS App 工作流、回傳資訊不足或缺少可用的 workspace/tab/project 識別資訊時，應明確回報限制與未驗證風險，並請使用者開啟正確 project、重啟 Codex app、開新 session 或明確指定下一步；不得自行退回 shell-first 流程。
- 只有使用者明確要求使用 `xcodebuild` 指令時，才可執行 shell-first `xcodebuild`。此時應優先用固定 project、scheme、configuration 與 `platform=macOS` destination；需要分析失敗時，先擷取最小必要錯誤片段，例如 `error:`、`warning:` 與第一個 failing command，避免把完整 build log 當成主要上下文。
- 對 Portal 的例行驗證，除非正在診斷 Xcode 專案設定或簽署問題，回覆中只需摘要 build 是否成功、第一個錯誤與必要警告，不應貼上完整 build 輸出。
- 若使用 Xcode MCP 或經使用者明確要求的 `xcodebuild` 會啟動、停止或操作正在執行的 Portal App，需確認不會干擾使用者目前工作；必要時先說明即將操作的 app/process。

## Relay 開發邊界

Relay 以 Python 實作 Azure Web PubSub 相關功能。

Relay 的責任：

- 接收 Portal 傳來的字幕事件。
- 驗證、整理或轉換字幕事件。
- 透過 Azure Web PubSub 發布字幕事件。
- 管理後端服務需要的本機設定與部署設定。

開發 Relay 時應遵守：

- 以 Python 3.13 為主要實作語言。
- 本機驗證 Azure Functions 時固定使用 port `7071`。
- 需要重啟本機 Azure Functions 時，必須先確認目標行程使用的是 port `7071`；只能停止該 port 對應的 `func` 行程，不得用寬鬆條件關閉其他 `func` 行程。
- 後端應保持清楚的事件輸入與發布邊界，避免把 macOS App 專屬邏輯放進 Relay。
- Azure 中的主要設定不應依賴手動 Portal 設定作為配置來源，應優先使用可版本化的檔案或自動化部署流程；只有 GitHub 綁定等外部整合必要操作才允許手動處理。

## 安全規則

- 不得將任何機密、金鑰、連線字串或 SAS Token 提交到儲存庫。
- 只要 Azure 能乾淨支援，就優先使用 Managed Identity，而非長效機密。
- 除非有文件化的營運需求，否則避免記錄完整的個人可識別資訊。
- 日誌應避免包含完整逐字稿、音訊內容、存取權杖、使用者識別資料或可回推身分的事件內容。
- 本機設定應使用未提交的環境檔或 Azure Functions 本機設定檔；需要範例時只提交不含真實值的 sample 或 example 檔。
- 對外 API 與 Web PubSub 相關端點應驗證呼叫來源與授權，不應只依賴前端或用戶端行為。
- 不提交本機環境檔、憑證、建置產物、DerivedData、快取與 log。
- 架構、部署與自動化設計不得讓 GitHub Actions、Azure Functions、Azure Automation、CLI 輸出或部署 logs 顯示機密、短效 token、簽章、完整連線 URL、逐字稿或可識別個人的資料。
- 建立 GitHub Actions secrets、Azure app settings、Bicep parameters、Automation runbook parameters 或 API 參數時，必須確認不會讓未授權外部使用者讀取、推導、列舉或交換到敏感資料。
- 對外可呼叫的 endpoint、Web PubSub negotiate、管理 API、部署 webhook 或 GitHub Actions trigger 必須明確定義授權邊界、允許來源、最小權限與失敗時的保守行為。
- CI/CD 與部署腳本不得輸出完整 environment、完整 HTTP headers、完整 request/response body 或 Azure/GitHub CLI debug logs，除非已確認內容不含敏感資料並經使用者明確要求。
- 不得使用 `git add -f` 加入被 `.gitignore` 忽略的檔案，除非使用者明確要求且該檔案已確認不含機密。
- 提交或推送前必須檢查 staged diff，確認沒有真實機密、本機設定、部署參數真值、逐字稿、音訊內容或可識別個人的資料。
- 一旦發現機密已提交或推送，應立即停止後續推送，通知使用者輪替外洩機密，並以 GitHub secret scanning 或歷史清理流程處理；不得只用後續 commit 刪除後視為已修復。

## 程式碼品質標準

- Python 程式碼應使用型別註記。
- 優先採用職責清楚的小型模組。
- 針對領域規則、解析、驗證與授權邏輯撰寫測試。
- 只有在程式意圖不夠明顯時才加入註解。
- 優先使用清楚命名，而非炫技式抽象設計。
- 讓 I/O、外部服務整合與核心領域邏輯保持分離，方便測試與替換。
- 新增功能時，測試範圍應涵蓋主要成功路徑、錯誤輸入與安全邊界。

## 文件規則

- 工作規則或協作約定變更時，必須同步更新本檔案。
- 重要架構、元件邊界、資料流與關鍵依賴應記錄在文件中；重大架構決策與取捨應以 ADR 記錄。
- 一旦引入環境變數，應補上文件。
- 公開或管理 API 一旦實作，應提供 API 範例。
- Azure 資源、部署流程或必要手動操作一旦變更，應同步更新相關文件。
- 文件中的範例值不得包含真實機密、連線字串、權杖或可識別個人的資料。
- 文件放置位置：
  - `README.md`：專案總覽、快速開始與文件索引。
  - `AGENTS.md`：開發代理與協作者的工作規則。
  - `docs/architecture/`：目前架構、元件邊界、資料流與關鍵依賴。
  - `docs/adr/`：Architecture Decision Records。
  - `docs/api/`：公開 API、管理 API 與事件格式範例。
  - `docs/deployment/`：Azure 資源、部署流程、環境變數與必要手動操作。
  - `docs/operations/`：例行操作、排程、維運檢查與 runbook。
  - `Portal/docs/` 或 `Relay/docs/`：元件專屬文件，避免和根目錄文件重複。

## 決策優先順序

當取捨不明確時，依下列順序優先考量：

1. 安全與隱私
2. 正確性與可稽核性
3. 維運簡單性
4. 成本效率
5. 開發便利性

## Commit 規則

- 若需要執行 `git commit`，commit message 必須使用 Conventional Commits，格式為 `<type>: <summary>`。
- `type` 必須使用英文，並遵循 Conventional Commits 慣例，例如 `build`、`chore`、`ci`、`docs`、`feat`、`fix`、`perf`、`refactor`、`revert`、`style`、`test` 等；應優先選擇最精確的 type。
- `summary` 與 body 預設應以台灣繁體中文撰寫；除非使用者明確指定其他語言。

## 共同開發準則

- 面向人的說明文件使用台灣繁體中文。
- 保留產品與元件專有名詞：`LiveCaption`、`Portal`、`Relay`、`Azure Web PubSub`。
- 優先維持 `Portal/` 與 `Relay/` 的責任分離。
- 系統設計應保有足夠模組化，讓 Portal、Relay 與未來功能可以獨立演進。
- 若未來任務與本文件衝突，必須在同一個變更中同步更新 `AGENTS.md`，或明確說明為何本文件不需變更。
- 新增技術棧或工具前，先確認是否符合 Portal 或 Relay 的既定責任。
