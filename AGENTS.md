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
- 目前 Portal 的語音輸入支援國語與英語；字幕輸出支援台灣繁體中文、日文、英文與韓文，其中台灣繁體中文與英文為必要輸出，並依使用者字幕輸出設定傳送給 Relay。
- App 介面在地化目前只支援 `zh-TW` 與 `en-US`，且需清楚區分語音輸入語言、字幕輸出語言與 App 介面在地化語言。
- Portal 一台電腦同時間只允許一個 App 實例，且同一個 App 同時間只允許一個主視窗；主視窗關閉時 App 應結束。
- Portal 沒有對外散佈需求時，Xcode 專案應使用本機 ad-hoc 簽署，不設定 `DEVELOPMENT_TEAM` 或個人 Apple ID 相關資訊。
- 避免把後端發布、連線廣播、Azure Web PubSub 細節放進 Portal，除非是呼叫 Relay 所需的最小整合。

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
