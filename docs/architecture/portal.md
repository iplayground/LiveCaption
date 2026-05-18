# Portal 架構與操作端行為

Portal 是 LiveCaption 的 macOS 操作端 App，需求系統為 macOS 26。Portal 只處理操作端責任：音訊擷取、語音辨識、翻譯、字幕預覽、SRT 輸出與呼叫 Relay；Azure Web PubSub 發布細節由 Relay 管理。

## 語言邊界

- App 介面在地化：`zh-TW`、`en-US`。
- 語音輸入語言：國語、英語。
- 字幕輸出語言：台灣繁體中文、英文為必要輸出；日文、韓文可由使用者設定。

App 介面語言、語音輸入語言與字幕輸出語言必須分開管理，不得互相推論。

## 主要畫面

Portal 主畫面包含：

- 上方字幕預覽：白底投影截取區，可調整語言、尺寸、字體、行距、間距與累加模式。
- 工作階段狀態：顯示收音、Speech、Relay、檔案權限與字幕 session 生命週期。
- 音訊輸入：列出本機輸入裝置，保存使用者選取來源，並顯示麥克風權限與音量。
- 語音分析預覽：顯示目前語音語言的 recognizing/final 結果與其他字幕語言 final 翻譯。
- Speech 設定：保存 Speech region、key、輸出語言、句子靜音分段設定與辨識詞彙提示。
- Relay 設定：保存 Relay URL、會議室名稱與字幕軌道值。
- 字幕檔案：保存 SRT 輸出根目錄 security-scoped bookmark。
- PubSub 字幕：透過 Viewer negotiate 取得 WebSocket URL，以觀眾端 delivery path 顯示 Relay 發送後的最新字幕。
- 事件紀錄：顯示操作、錯誤與檔案輸出狀態，但不得記錄完整字幕內容。

## 字幕 Session

開始字幕前必須同時符合：

- 已開啟收音。
- Speech 授權測試成功。
- 字幕檔案位置可存取。
- Relay 連線測試成功。

開始後 Portal 會使用主控板選定的音訊來源建立 Azure Speech Translation recognizer。字幕預覽是最高優先 UI 工作；Relay 發布、SRT 累積、事件計數與事件紀錄可延後處理，避免阻塞現場字幕畫面。

上方字幕預覽的累加模式只保留 GUI 顯示所需的最近字幕筆數，保留數量與 `projectionCapture.appendLineLimit` 同步，範圍為 1 到 10 筆，預設 3 筆。此限制只影響投影截取區的累加顯示，不影響 SRT 輸出、Relay 發布或字幕事件計數。

停止字幕時，Portal 會依工作階段開始時間建立 SRT 輸出資料夾，格式為 `MMdd_HHmm`，可附加清理後的工作階段標題。SRT 會依 final 字幕品質模式分別保存到子資料夾：

- `fast/`：Azure Speech final 字幕。
- `accurate/`：Azure OpenAI final 字幕。

各模式底下的 SRT 檔案依字幕語言代碼命名，例如 `zh-Hant.srt`、`en.srt`、`ja.srt`、`ko.srt`。若某模式沒有產生可寫入的字幕，例如未啟用精準模式或 Azure OpenAI 尚未回傳 final 結果，Portal 不會為該模式產生空檔案。若主要輸出位置失敗，Portal 會寫入 Application Support 下的 `LiveCaptionPortal/SRT Recovery/`，並維持相同的模式子資料夾結構。

事件紀錄中的 SRT 成功訊息應保留操作端需要的摘要，例如已寫入檔案數與工作階段輸出資料夾，不逐一列出每個語言與模式的完整檔案路徑。備援暫存或寫入失敗時，才記錄足以讓操作端找回檔案或排除權限問題的路徑與錯誤摘要。

## 字幕品質模式

Portal 的字幕輸出分為快速與精準兩種 final 字幕品質模式，且可在同一場 session 同時產生兩種 final 字幕：

- 快速：final 字幕使用 Azure Speech 結果。
- 精準：final 字幕使用 Azure OpenAI 結果，其中 transcription deployment
  先產生原始語言 draft，再由 text model deployment 比對 OpenAI transcription 與 Azure Speech final
  候選文字，依詞彙提示校正原始語言字幕並產生其他輸出語言。

不論使用哪一種 final 字幕品質模式，即時 recognizing / partial 解析一律由 Azure
Speech 處理，不得改由 Azure OpenAI 取代。精準模式只能影響每一句 final 字幕的輸出來源。

精準模式需要 Portal 建立 Azure OpenAI 音訊 pipeline。Portal 仍以 Azure Speech final
句段作為精準字幕的起訖時間與句段邊界，切出同一區段音訊後送往 Azure OpenAI transcription deployment
取得原始語言 draft；Portal 再把 OpenAI transcription draft、Azure Speech final、目前語音輸入語言、
字幕輸出語言、詞彙提示與同一場 session 最近 3 段已完成的 OpenAI 原始語言字幕送往 Azure OpenAI text model deployment，由 OpenAI 產生校正後原始語言字幕與其他輸出語言字幕。最近字幕只能作為同音字、近音字、斷詞、專有名詞與技術詞辨識錯誤的保守上下文，不得用來續寫、摘要、補內容、潤飾文句或把口語改成書面語；若不確定，必須保留較可靠的候選原文。精準模式輸出
`zh-Hant` 時，Portal 必須要求 Azure OpenAI 使用台灣繁體中文與台灣用語。
Portal 使用本機設定保存 Azure OpenAI API key；不得寫入範例文件、logs 或 Relay 設定。
Azure OpenAI 授權方式後續若改為短效 token 或其他流程，仍不得讓 Relay 字幕轉發流程承擔
Azure OpenAI 字幕加工責任。

Portal 送往 Relay 的字幕事件會依品質模式分開發布：快速字幕事件的 top-level
`captionMode` 為 `fast`，精準字幕事件的 top-level `captionMode` 為 `accurate`。舊版
`captionModes` 多模式 object 已廢除，Relay 會拒絕同一筆事件同時包含兩種模式。
`captionProvider` 只供觀眾端或 Portal 主控板顯示來源；Relay 不用它決定處理流程，也不要求
它與 `captionMode` 對應。Relay 一律把完整字幕事件送到對應字幕軌道的 Viewer WebSocket，
Viewer 與 Portal 主控板自行依使用者選擇的模式與語言過濾顯示內容。Portal 主控板的 Relay
計數也依模式分別統計成功發布筆數。

精準模式失敗、逾時或尚未取得 final 結果時，不得中斷 Azure Speech 即時字幕。產品行為
應保守處理，在操作端明確標示精準字幕不可用；精準模式不得使用 Azure Speech final
補原始語言字幕。若 Azure OpenAI 未產生必要輸出語言，該筆精準字幕不得送往 Relay；
本機 `accurate/` SRT 可保留已產生的語言，供診斷與活動後檢查。
Azure OpenAI 連線測試失敗時，Portal 可把 Foundation / URLSession 明確提供的
診斷欄位寫入本機事件紀錄，例如測試階段、deployment name、錯誤 domain /
code 與 HTTP status；若底層 API 沒有提供 Azure response body，Portal 不應推測伺服器端
原因。任何診斷紀錄都不得包含 API key、完整 headers、request / response body、prompt、
字幕文字、逐字稿或 session secret。

Azure OpenAI 診斷紀錄不得包含字幕文字、逐字稿、音訊內容、完整 request / response body
或 API key。Portal 可記錄請求階段、HTTP status、字元數、replacement character 數量與
音訊時間區段，用來判斷精準模式品質。

Azure OpenAI 整合使用 Portal 的 `AVCaptureAudioDataOutput` 音訊 sample 分流，轉為 24 kHz
mono PCM16 後保存在 Portal 本機記憶體。Azure Speech final 事件產生後，Portal 依該事件的
offset / duration 切出對應音訊片段，送往 Azure OpenAI `/audio/transcriptions` 取得
OpenAI transcription draft。Portal 再把同一段 OpenAI transcription draft 與 Azure Speech final
候選文字與最近 3 段 OpenAI 原始語言字幕透過 Azure OpenAI text model
一次請求產生校正後原始語言字幕與非原始語言的字幕輸出語言。Portal 只有在需要的翻譯字幕
都取得後，才會發布 `accurate` Relay payload；若翻譯缺失，該筆精準字幕保留在本機 SRT
診斷輸出，但不送往 Relay。Azure Speech final 僅作為 Azure OpenAI text model 的候選輸入與 fallback 參考，
Portal 不會直接用 Azure Speech final 補入精準模式的原始語言文字。

## Speech 辨識詞彙提示

Portal 的 Speech 設定提供辨識詞彙提示編輯器，讓操作端可加入活動專有名詞、產品名稱或講者姓名，提升 Azure Speech Translation recognizer 對常見詞的辨識穩定性。

詞彙提示分成三個範圍：

- `shared`：套用所有語音輸入語言。
- `zh-TW`：只套用 `zh-TW` 語音輸入。
- `en-US`：只套用 `en-US` 語音輸入。

建立 recognizer 時，Portal 會合併 `shared` 與目前語音輸入語言的詞彙，透過 Azure Speech SDK `SPXPhraseListGrammar` 加入 phrase list，並固定 `setWeight(2.0)`。Azure OpenAI 精準字幕也會把同一組詞彙加入 transcription prompt 與 text model 校正/翻譯 prompt，要求 OpenAI 依詞彙表保留專有名詞的完整拼寫與大小寫。詞彙只在 recognizer 與 Azure OpenAI session 建立或重建時套用；若字幕 session 已在執行中，編輯詞彙不會即時改變目前的 recognizer 或精準字幕 prompt，需重新開始或觸發 session 重建後才會生效。

合併後每個語音輸入語言最多套用 250 筆詞彙。UI 會依 `shared + 語言專屬` 計算容量，例如 `shared` 已有 70 筆時，`zh-TW` 與 `en-US` 各自最多再新增 180 筆。預設詞彙只包含 `iPlayground`，避免開源專案內建活動以外的專有名詞。

詞彙提示不會送往 Relay、字幕事件、SRT 檔案或事件紀錄。

## Relay 整合

Portal 只知道 Relay API，不知道 Azure Web PubSub hub、group、connection string 或 SAS token。

- 連線測試：`HEAD /api/caption-events`，驗證 HMAC 並取得觀眾端 access code。
- 字幕發布：`POST /api/caption-events`，送出字幕事件。
- 控制事件發布：`POST /api/caption-events`，送出 `portalStatus`、`sessionStatus` 與
  `captionAvailability` 控制事件。
- PubSub 接收檢查：字幕 session 開始時呼叫 `POST /api/viewer/negotiate`，使用 Relay 連線測試回傳的 access code 與目前 `trackNumber` 取得 Viewer WebSocket URL，並在本機依要監看的模式與語言過濾顯示內容。

若 Relay 發布失敗，Portal 會記錄事件並重試，但不應中斷 Speech Translation、本機預覽或 SRT 累積。

Portal 不自行計算 access code；access code 一律來自 Relay 的 `HEAD /api/caption-events` response headers。Portal 不得記錄或長期保存完整 viewer WebSocket URL、access code、token、完整 headers 或完整 PubSub payload。

## App 生命週期

Portal 同時間只允許一個 App 實例與一個主視窗；主視窗關閉時 App 應結束。字幕 session 進行期間，Portal 會鎖定會影響 session 的設定並建立 power assertion，停止、啟動失敗或 App 關閉時釋放。

## 原始碼分層

- `Portal/LiveCaptionPortal/ContentView.swift`：主視窗狀態持有、App 生命週期與字幕 session 協調。
- `Portal/LiveCaptionPortal/ContentView+Previews.swift`：主視窗 SwiftUI preview。
- `Portal/LiveCaptionPortal/PortalLaunchVerifier.swift`：啟動時 Speech 授權與 Relay 連線重新驗證流程。
- `Portal/LiveCaptionPortal/PortalWorkflowLog.swift`：Portal workflow helper 回傳事件紀錄 payload。
- `Portal/LiveCaptionPortal/Audio/`：音訊來源、麥克風權限、收音控制與音量。
- `Portal/LiveCaptionPortal/Speech/`：語音輸入語言、字幕輸出語言、Azure Speech 設定、Speech Translation 與 Azure OpenAI transcription / text model 校正翻譯。
- `Portal/LiveCaptionPortal/Subtitle/`：字幕檔案位置、SRT 輸出與備援暫存。
- `Portal/LiveCaptionPortal/Relay/`：Relay URL、會議室、軌道、連線測試、字幕事件請求、字幕發布重試、viewer negotiate 與 PubSub 字幕接收流程。
- `Portal/LiveCaptionPortal/Logging/`：事件紀錄資料模型與時間格式。
- `Portal/LiveCaptionPortal/UI/`：主視窗 layout、主畫面區塊、設定 sheet、PubSub 字幕卡片、Log drawer 與共用 SwiftUI 元件。
- `Portal/LiveCaptionPortal/L10n.swift` 與 `*.lproj/`：介面在地化查表與字串資源。
