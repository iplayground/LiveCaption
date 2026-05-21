# Portal 架構與操作端行為

Portal 是 LiveCaption 的 macOS 操作端 App，需求系統為 macOS 26。Portal 只處理操作端責任：音訊擷取、語音辨識、翻譯、字幕預覽、SRT 輸出與呼叫 Relay；Azure Web PubSub 發布細節由 Relay 管理。

## 語言邊界

- App 介面在地化：`zh-TW`、`en-US`。
- 語音輸入語言：國語、英語。
- 字幕輸出語言：台灣繁體中文、英文為必要分析與顯示；日文、韓文可由使用者設定為不分析、分析但不在 Portal 主畫面顯示、分析且在 Portal 主畫面顯示。

App 介面語言、語音輸入語言與字幕輸出語言必須分開管理，不得互相推論。字幕輸出語言的「分析」決定 Portal 是否向 Azure Speech / Azure OpenAI 產生該語言字幕，並影響 Relay 發布與 SRT 輸出；「Portal 主畫面顯示」只影響主畫面語音分析預覽，不影響獨立字幕預覽、投影截取預覽、Relay 發布或 SRT 輸出。

## 主要畫面

Portal 主畫面包含：

- 上方字幕預覽：白底投影截取區，可調整語言、字幕來源、尺寸、字體、行距、間距與累加模式。
- 工作階段狀態：顯示收音、Speech、Relay、檔案權限與字幕 session 生命週期。
- 音訊輸入：列出本機輸入裝置，保存使用者選取來源，並顯示麥克風權限與音量。
- 語音分析預覽：顯示目前語音語言的 recognizing/final 結果，以及 Speech 設定中標記為 Portal 主畫面顯示的其他字幕語言 final 翻譯。
- Speech 設定：保存 Speech region、key、字幕輸出語言分析狀態、Portal 主畫面顯示語言、句子靜音分段設定與辨識詞彙提示。
- Relay 設定：保存 Relay URL、會議室名稱與字幕軌道值。
- 字幕檔案：保存 SRT 輸出根目錄 security-scoped bookmark。
- PubSub 字幕：透過 Viewer negotiate 取得 WebSocket URL，以觀眾端 delivery path 顯示 Relay 發送後的最新字幕。
- 事件紀錄：顯示操作、錯誤與檔案輸出狀態，但不得記錄完整字幕內容。

主畫面中央的語音分析預覽應把操作端當下需要持續監看的內容固定在上方：標題、辨識狀態、語音輸入語言、場次標題與即時 recognizing 字幕不得隨下方內容捲動。只有 final 字幕預覽與 PubSub 字幕區塊可在中央內容區內垂直捲動。PubSub 字幕區塊外層標題負責標示資料來源，卡片內只顯示連線狀態與說明，避免重複顯示 `PubSub` 名稱或重複圖示。

主控板在語音輸入語言為 `English` 時，於語音語言切換左側顯示暫存的講者身份選項：華人、日本、韓國、印度、其他。此設定只供當下 Portal 主控板使用，不保存到 `SpeechSettings`、`UserDefaults`、環境匯出檔或任何本機設定檔。選擇「其他」代表不提供講者身份線索，不得在 Azure OpenAI prompt 中加入講者身份或口音處理說明。

## 字幕 Session

開始字幕前必須同時符合：

- 已開啟收音。
- Speech 授權測試成功。
- 字幕檔案位置可存取。
- Relay 連線測試成功。

開始後 Portal 會使用主控板選定的音訊來源建立 Azure Speech Translation recognizer。字幕預覽是最高優先 UI 工作；Relay 發布、SRT 累積、事件計數與事件紀錄可延後處理，避免阻塞現場字幕畫面。

Portal 的字幕 session 內部有兩個處理階段：

- 開場階段：開始字幕後一律以國語作為 Speech 與 Azure OpenAI 的處理語言，符合台灣活動通常先以中文開場的流程。
- 講者階段：操作端按下「進入講者模式」後，才改用主控板選定的語音輸入語言進行後續 Speech 與 Azure OpenAI 分析。

這個階段切換只屬於 Portal 內部的語音分析策略。Relay、Viewer 與 SRT 仍視為同一個字幕 session，不新增對外的開場/講者標記。切換時 Portal 必須保留同一場 session 的時間軸；後續字幕的 `offsetTicks` 不得從 0 重新開始，SRT 時間碼也不得因 recognizer 重建而重置。

Azure OpenAI 精準字幕可能晚於 Azure Speech final 回來。Portal 必須記錄每筆 Speech final 屬於哪一個處理階段與 session 時間位置，讓對應的 OpenAI 精準結果即使延遲回來，也依原本的 Speech 句段、語音處理語言與 session offset 產生字幕；不得因操作端已切到講者階段，就把開場階段的 OpenAI 結果丟棄或改用新的語音語言解讀。

上方字幕預覽的累加模式只保留 GUI 顯示所需的最近字幕筆數，保留數量與 `projectionCapture.appendLineLimit` 同步，範圍為 1 到 10 筆，預設 3 筆。此限制只影響投影截取區的累加顯示，不影響 SRT 輸出、Relay 發布或字幕事件計數。

上方字幕預覽可在主畫面內嵌顯示或獨立視窗顯示。主畫面內嵌預覽維持 Azure Speech 來源，用於低延遲現場截取。獨立視窗預覽提供 `Speech` 與 `OpenAI` 字幕來源選項：`Speech` 顯示 Azure Speech 即時 recognizing 與 final 結果；`OpenAI` 只顯示 Azure OpenAI final 字幕，不顯示 partial 或 interim 文字。獨立視窗預覽與投影截取預覽使用已設定為「分析」的字幕輸出語言，不受 Speech 設定中 Portal 主畫面顯示開關影響。OpenAI 預覽的累加顯示必須依字幕輸出語言保存歷史文字，不得用目前的語音輸入語言重新解讀已完成的舊字幕；例如開場階段的繁體中文精準字幕在切到英文講者階段後，仍應留在 `zh-Hant` 區塊，不得跑到 `en` 區塊或被清空。此選項只影響操作端投影截取預覽，不改變 Relay 發布、SRT 輸出或字幕品質模式的資料邊界。

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
字幕輸出語言、詞彙提示與同一場 session 最近 5 段已完成的 OpenAI 原始語言字幕送往 Azure OpenAI text model deployment，由 OpenAI 產生校正後原始語言字幕與其他輸出語言字幕。Azure OpenAI transcription draft 是精準原文的主要候選；Azure Speech final 只作為輔助證據，當它明顯亂碼、近音誤轉或與穩定前文衝突時不得採用，只有 Azure OpenAI transcription 缺失、空白或明顯損壞時才作為 fallback。詞彙提示只可作為音訊與上下文支持時的詞形拼寫參考，不得被當成逐字稿本身；若 Azure OpenAI transcription 回傳內容等同本次詞彙提示清單，Portal 應把該 OpenAI transcription draft 視為損壞候選，記錄不含逐字稿內容的診斷，並讓後續 text model 流程改以 Azure Speech final 作為 fallback 候選。最近字幕只能作為來源語言的保守上下文，用於處理同音、近音、斷詞、詞形拼寫、外語 code-switch 與相鄰字幕主題一致性；不得用翻譯結果回推原文，也不得用來續寫、摘要、補內容、潤飾文句或把口語改成書面語。當語音輸入語言為 `en-US` 且操作端選擇華人、日本、韓國或印度講者身份時，Portal 可在 Azure OpenAI transcription prompt 中加入通用的講者背景與口音留意說明，要求只在音訊與來源語言上下文支持時採用對應詞形；若講者身份為「其他」或語音輸入不是 `en-US`，不得加入講者身份或口音提示。Portal 的 Azure OpenAI prompt 應描述通用判斷規則，不以單一錯誤案例或案例詞類列舉作為主要約束；若不確定，必須保留較可靠的候選原文。精準模式輸出
`zh-Hant` 時，Portal 必須要求 Azure OpenAI 使用台灣繁體中文與台灣用語。
Portal 使用固定位置的本機 secrets 設定檔保存 Azure Speech key 與 Azure OpenAI API key；
不得寫入 `UserDefaults`、範例文件、logs 或 Relay 設定。
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
或 API key。Portal 可記錄請求階段、HTTP status、字元數、replacement character 數量、
詞彙提示清單外洩偵測結果與音訊時間區段，用來判斷精準模式品質。

Azure OpenAI 整合使用 Portal 的 `AVCaptureAudioDataOutput` 音訊 sample 分流，轉為 24 kHz
mono PCM16 後保存在 Portal 本機記憶體。Azure Speech final 事件產生後，Portal 依該事件的
offset / duration 切出對應音訊片段，送往 Azure OpenAI `/audio/transcriptions` 取得
OpenAI transcription draft。若該 draft 等同本次詞彙提示清單，Portal 不得把它送入後續流程作為有效 OpenAI 候選。
Portal 再把同一段 OpenAI transcription draft 與 Azure Speech final
候選文字與最近 5 段 OpenAI 原始語言字幕透過 Azure OpenAI text model
一次請求產生校正後原始語言字幕與非原始語言的字幕輸出語言。Portal 只有在需要的翻譯字幕
都取得後，才會發布 `accurate` Relay payload；若翻譯缺失，該筆精準字幕保留在本機 SRT
診斷輸出，但不送往 Relay。Azure Speech final 僅作為 Azure OpenAI text model 的候選輸入與 fallback 參考，
Portal 不會直接用 Azure Speech final 補入精準模式的原始語言文字。
校正原始語言字幕時，Portal 要求 Azure OpenAI 保留候選文字或最近前文支持的外語 code-switch，不得把外語片段替換成來源語言的近音詞；模糊候選若會改變當前主題，必須有當前候選明確支持才可採用。

精準字幕的顯示與輸出順序以 Speech final 的 session offset 為準，而不是以 Azure OpenAI response 抵達順序為準。SRT 輸出也必須依時間碼排序並處理相鄰 cue 的重疊，避免晚回來的第一句被寫在較早抵達的第二句後面。

## Speech 辨識詞彙提示

Portal 的 Speech 設定提供辨識詞彙提示編輯器，讓操作端可加入活動專有名詞、產品名稱或講者姓名，提升 Azure Speech Translation recognizer 對常見詞的辨識穩定性。

詞彙提示分成三個範圍：

- `shared`：套用所有語音輸入語言。
- `zh-TW`：只套用 `zh-TW` 語音輸入。
- `en-US`：只套用 `en-US` 語音輸入。

建立 recognizer 時，Portal 會合併 `shared` 與目前語音輸入語言的詞彙，透過 Azure Speech SDK `SPXPhraseListGrammar` 加入 phrase list，並固定 `setWeight(2.0)`。Azure OpenAI 精準字幕也會把同一組詞彙加入 transcription prompt 與 text model 校正/翻譯 prompt，要求 OpenAI 只在音訊與上下文支持時使用詞彙表作為詞形拼寫參考。詞彙只在 recognizer 與 Azure OpenAI session 建立或重建時套用；若字幕 session 已在執行中，編輯詞彙不會即時改變目前的 recognizer 或精準字幕 prompt，需重新開始或觸發 session 重建後才會生效。

合併後每個語音輸入語言最多套用 250 筆詞彙。UI 會依 `shared + 語言專屬` 計算容量，例如 `shared` 已有 70 筆時，`zh-TW` 與 `en-US` 各自最多再新增 180 筆。預設詞彙只包含 `iPlayground`，避免開源專案內建活動以外的專有名詞。

詞彙提示不會送往 Relay、字幕事件、SRT 檔案或事件紀錄。

## Portal 環境設定匯入與匯出

Portal 透過 macOS File menu 提供 `匯入 Portal 環境設定…` 與 `匯出 Portal 環境設定…`，用於把同一套現場環境設定轉移到其他操作端電腦。環境設定檔使用 JSON，預設檔名為 `LiveCaption-Portal-Environment.json`。

匯出時操作端可勾選要包含的設定區塊：

- Azure Speech 設定。
- Azure OpenAI 設定。
- 字幕輸出與分句設定。
- 詞彙提示。
- Relay URL。

匯出檔只包含已勾選的區塊。字幕輸出與分句設定會一併保存輸出語言分析狀態、Portal 主畫面顯示語言與分句靜音時間；舊版設定檔若沒有 Portal 主畫面顯示語言，匯入時會把已分析語言視為 Portal 主畫面可見語言。詞彙提示在環境設定檔中只保存文字陣列，不保存 Portal 內部 UI 使用的 UUID；匯入時會依文字重新建立本機 `SpeechPhraseHint`。Relay 匯出只包含 Relay URL，不包含會議室名稱與軌數，避免把同一場次或同一軌道的操作端狀態誤帶到其他電腦。

匯入時 Portal 會先讀取設定檔內實際包含的區塊，再顯示可勾選的匯入確認面板。只有使用者勾選的區塊會覆蓋本機設定，未勾選或檔案未包含的區塊會保留本機現值。匯入 Azure Speech、Azure OpenAI 或 Relay URL 後，對應連線狀態會重設為待重新測試。

環境設定檔可能包含 Speech Key 或 Azure OpenAI Key。此檔案不得提交到儲存庫、不得貼到 issue / PR / log，也不得透過不可信任管道傳送。若環境設定檔曾外洩，應輪替其中包含的金鑰。

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
- `Portal/LiveCaptionPortal/PortalEnvironmentSettingsConfigurationFile.swift`：Portal 環境設定 JSON 匯入/匯出格式、版本檢查與部分區塊套用邏輯。
- `Portal/LiveCaptionPortal/Audio/`：音訊來源、麥克風權限、收音控制與音量。
- `Portal/LiveCaptionPortal/Speech/`：語音輸入語言、字幕輸出語言、Azure Speech 設定、Speech Translation 與 Azure OpenAI transcription / text model 校正翻譯。
- `Portal/LiveCaptionPortal/Subtitle/`：字幕檔案位置、SRT 輸出與備援暫存。
- `Portal/LiveCaptionPortal/Relay/`：Relay URL、會議室、軌道、連線測試、字幕事件請求、字幕發布重試、viewer negotiate 與 PubSub 字幕接收流程。
- `Portal/LiveCaptionPortal/Logging/`：事件紀錄資料模型與時間格式。
- `Portal/LiveCaptionPortal/UI/`：主視窗 layout、主畫面區塊、設定 sheet、Portal 環境設定匯入/匯出面板、PubSub 字幕卡片、Log drawer 與共用 SwiftUI 元件。
- `Portal/LiveCaptionPortal/L10n.swift` 與 `*.lproj/`：介面在地化查表與字串資源。
