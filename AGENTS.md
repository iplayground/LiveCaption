# AGENTS

## 專案定位

LiveCaption 是一套用於現場活動的即時語音辨識與翻譯系統。

系統目前分成兩個主要元件：

- `Portal/`：macOS 操作端 App。
- `Relay/`：後端服務。

## Portal

Portal 放置 Xcode 專案，用來實作 macOS App。

Portal 的責任：

- 擷取現場音訊。
- 執行即時語音辨識。
- 執行翻譯。
- 產生字幕事件。
- 將字幕事件送往 Relay。

開發 Portal 時：

- 以 macOS App 的使用情境為主。
- 保留 `Portal` 作為操作端名稱。
- Portal 目前需求系統為 macOS 26。
- 調整 macOS App UI 時，可依實際情況調整視窗最小尺寸，但不得超出使用者螢幕大小。
- 目前 Portal 的語音輸入支援國語與英語；字幕輸出支援台灣繁體中文、日文、英文與韓文，其中台灣繁體中文與英文為必要輸出，並依使用者字幕輸出設定傳送給 Relay。
- App 介面在地化目前只支援 `zh-TW` 與 `en-US`，且需清楚區分語音輸入語言、字幕輸出語言與 App 介面在地化語言。
- Portal 一台電腦同時間只允許一個 App 實例，且同一個 App 同時間只允許一個主視窗；主視窗關閉時 App 應結束。
- Portal 沒有對外散佈需求時，Xcode 專案應使用本機 ad-hoc 簽署，不設定 `DEVELOPMENT_TEAM` 或個人 Apple ID 相關資訊。
- 避免把後端發布、連線廣播、Azure Web PubSub 細節放進 Portal，除非是呼叫 Relay 所需的最小整合。
- Xcode 產物、使用者設定、DerivedData 與本機建置輸出不應提交。

## Relay

Relay 以 Python 實作 Azure Web PubSub 相關功能。

Relay 的責任：

- 接收 Portal 傳來的字幕事件。
- 驗證、整理或轉換字幕事件。
- 透過 Azure Web PubSub 發布字幕事件。
- 管理後端服務需要的本機設定與部署設定。

開發 Relay 時：

- 以 Python 3.13 為主要實作語言。
- Azure、本機 secrets、連線字串與 `local.settings.json` 不應提交。
- 後端應保持清楚的事件輸入與發布邊界，避免把 macOS App 專屬邏輯放進 Relay。
- Azure 中的主要設定不應依賴手動 Portal 設定作為配置來源，應優先使用可版本化的檔案或自動化部署流程；只有 GitHub 綁定等外部整合必要操作才允許手動處理。

## 安全規則

- 不得將任何機密、金鑰、連線字串或 SAS Token 提交到儲存庫。
- 只要 Azure 能乾淨支援，就優先使用 Managed Identity，而非長效機密。
- 除非有文件化的營運需求，否則避免記錄完整的個人可識別資訊。
- 日誌應避免包含完整逐字稿、音訊內容、存取權杖、使用者識別資料或可回推身分的事件內容。
- 本機設定應使用未提交的環境檔或 Azure Functions 本機設定檔；需要範例時只提交不含真實值的 sample 或 example 檔。
- 對外 API 與 Web PubSub 相關端點應驗證呼叫來源與授權，不應只依賴前端或用戶端行為。

## 程式碼品質標準

- Python 程式碼應使用型別註記。
- 優先採用職責清楚的小型模組。
- 針對領域規則、解析、驗證與授權邏輯撰寫測試。
- 只有在程式意圖不夠明顯時才加入註解。
- 優先使用清楚命名，而非炫技式抽象設計。
- 讓 I/O、外部服務整合與核心領域邏輯保持分離，方便測試與替換。
- 新增功能時，測試範圍應涵蓋主要成功路徑、錯誤輸入與安全邊界。

## 文件要求

- 重大技術決策變更時，必須同步更新本檔案。
- 重要架構、元件邊界、資料流與關鍵依賴應記錄在文件中；重大架構決策與取捨應以 ADR 記錄。
- 一旦引入環境變數，應補上文件。
- 公開或管理 API 一旦實作，應提供 API 範例。
- Azure 資源、部署流程或必要手動操作一旦變更，應同步更新相關文件。
- 文件中的範例值不得包含真實機密、連線字串、權杖或可識別個人的資料。

## 文件放置位置

- 根目錄 `README.md` 放置專案總覽、快速開始與主要元件說明。
- 根目錄 `AGENTS.md` 放置本專案對開發代理與協作者的工作規則。
- `docs/architecture/` 放置目前架構現況、元件邊界、資料流與關鍵依賴。
- `docs/adr/` 放置 Architecture Decision Records，記錄重大架構決策、取捨、替代方案與決策結果。
- `docs/api/` 放置公開 API、管理 API 與事件格式範例。
- `docs/deployment/` 放置 Azure 資源、部署流程、環境變數與必要手動操作說明。
- `Portal/` 或 `Relay/` 內若需要元件專屬文件，應放在各自目錄下的 `docs/`，並避免和根目錄文件重複。

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

- README 與面向人的說明文件使用台灣繁體中文。
- 保留產品與元件專有名詞：`LiveCaption`、`Portal`、`Relay`、`Azure Web PubSub`。
- 優先維持 `Portal/` 與 `Relay/` 的責任分離。
- 系統設計應保有足夠模組化，讓 Portal、Relay 與未來功能可以獨立演進。
- 若未來任務與本文件衝突，必須在同一個變更中同步更新 `AGENTS.md`，或明確說明為何本文件不需變更。
- 不提交本機環境檔、憑證、建置產物、快取與 log。
- 新增技術棧或工具前，先確認是否符合 Portal 或 Relay 的既定責任。
