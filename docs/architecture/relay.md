# Relay 架構與資料流

Relay 是 LiveCaption 的後端服務，以 Python 3.13 Azure Functions 實作。Relay 負責接收 Portal 字幕事件、驗證請求與事件格式、整理發布 payload，並透過 Azure Web PubSub 發布給觀眾端。

## HTTP Endpoints

```http
GET /
HEAD /api/caption-events
POST /api/caption-events
POST /api/viewer/negotiate
GET /api/health
```

`GET /` 會重新導向到 LiveCaption GitHub repository。未知 GET path 回傳 `404` JSON。

API 契約分別記錄於：

- [字幕事件 API](../api/caption-events.md)
- [觀眾端連線 API](../api/viewer-negotiate.md)
- [Relay 健康檢查 API](../api/health.md)

## 資料流

1. Portal 以 Azure Speech key 對 request body 產生 HMAC 簽章。
2. Relay 透過 `AZURE_SPEECH_ACCOUNT_ID` 定位 Azure Speech resource，並使用 Managed Identity 讀取 Speech key 驗章。
3. Relay 驗證字幕事件欄位、語言、時間碼、文字長度與安全邊界。
4. Portal 依 final 字幕品質模式選擇字幕來源：快速使用 Azure Speech final，精準使用 Azure Speech final 作為時間 anchor，並以 Azure OpenAI transcription deployment 產生原始語言 draft，再由 Azure OpenAI text model 產生校正後原文與翻譯結果。
5. Relay 要求每筆字幕事件提供單一 top-level `captionMode`，允許 `fast` 或 `accurate`；
   舊版 `captionModes` 多模式 object 會被拒絕。
6. `captionProvider` 是選填顯示欄位。Relay 只驗證它是簡單短字串，不用它決定處理流程，
   也不要求它與 `captionMode` 對應；未提供或空白時不會自動補齊。
7. Relay 建立 Web PubSub payload，省略不需給觀眾端的原始辨識文字。
8. Relay 使用 Managed Identity 透過 Azure Web PubSub 對 Viewer WebSocket 發送控制事件與字幕事件。
9. 觀眾端透過 `POST /api/viewer/negotiate` 帶入活動前可知道的 `trackNumber`，取得該軌道的
   單一 Viewer WebSocket URL；negotiate 不帶字幕模式或語言偏好。
10. Viewer WebSocket 實際連線成功時，Azure Web PubSub 會呼叫 Relay event handler；Relay 從
    Azure Table Storage 讀取該軌道最新控制狀態，直接補送給該 connection。
11. Portal 主控板若要確認觀眾實際會收到什麼，也使用 `/api/viewer/negotiate` 建立 Viewer
    WebSocket，並在本機依模式與語言過濾顯示內容。

任何回傳給觀眾端或 Portal 主控板的 Web PubSub URL 都包含短效 bearer token，必須視為敏感資料。Relay、Portal、GitHub Actions、Azure Functions logs 與觀眾端 App 都不得記錄完整 URL、完整 headers 或完整 response body。

## Web PubSub 邊界

Portal 不設定 Web PubSub hub、group、connection string、SAS token 或發布權限。Web PubSub 相關設定只存在 Relay 與 Azure 基礎設施中。

Viewer WebSocket 設定：

- Hub：`livecaption`
- 字幕 group：`caption-live-track-<trackNumber>`

Relay 對 Viewer 採用單一 WebSocket session 模型。Viewer negotiate 只負責依 `trackNumber`
取得特定字幕軌道的短效 WebSocket URL，不負責選擇 `captionMode` 或語言。Relay 在同一條 WebSocket 對 Viewer 發送
Portal 狀態、字幕 session 狀態、`captionAvailability` 控制事件與完整字幕事件。Viewer 與
Portal 主控板在本機依使用者選擇的模式與語言過濾顯示內容。

Relay 會把每個 `trackNumber` 最新的 `portalStatus`、`sessionStatus` 與 `captionAvailability`
保存到 Azure Table Storage。這份狀態不能放在 Function process memory，因為 Azure Functions
scale-out 後不同 instance 不共享記憶體。Web PubSub `connected` system event 抵達 Relay 時，
Relay 依 Viewer access token 內的 `userId` 判斷軌道，並使用 connection id 對該 Viewer 補送目前
控制狀態。若該次回放的 `portalStatus` 為 `offline`，Relay 不補送 `captionAvailability`。

`portalStatus: online` 以 Portal 活動時間維持新鮮度。Portal 未進行字幕時會定期送內部 activity
更新；字幕 session 進行中則以字幕事件與控制事件更新活動時間，不另送 activity 更新。activity
更新不會發送給 Viewer，只有 `portalStatus` 狀態改變時才會發送控制事件。若 Portal 關閉或閃退而
沒有成功發布 `offline`，新 Viewer 連線時 Relay 會在已保存的 `online` 超過有效時間後，對該
connection 補送一筆合成的 `portalStatus: offline`；此合成事件不會寫回控制狀態，也不會推送給
既有連線 Viewer。`offline` 不會因時間過期而被忽略。當新 connection 的回放狀態為 `offline`
時，Relay 不補送已保存的 `captionAvailability`。

Relay 必須使用 Azure Web PubSub track group fan-out 發送字幕。Viewer negotiate 成功後，Relay
讓該 connection 加入對應 `trackNumber` 的字幕 group。Portal 字幕事件進入 Relay 後，Relay 保留
`captionMode` 與完整 `captions` object，整理成單一 `caption` event 送到 track group，由 Azure
Web PubSub fan-out 給該 group 內的 Viewer。Relay 不應在每筆字幕事件中逐一列舉 Viewer
connection 發送，也不依 Viewer 的模式或語言偏好拆分訊息。

Portal 開啟、關閉、開始字幕、停止字幕，或開關 Azure OpenAI 精準字幕支援時，Relay 需發布
新的控制事件給 Viewer。Portal 開關精準字幕時只需更新 `captionAvailability`，不需要另外讓
Viewer 得知 OpenAI 連線狀態或詳細錯誤。

## App Settings

Relay 主要 app settings：

| 名稱 | 說明 |
| --- | --- |
| `AZURE_SPEECH_ACCOUNT_ID` | Azure Speech resource ARM resource id。 |
| `AZURE_WEBPUBSUB_ENDPOINT` | Azure Web PubSub endpoint。 |
| `AZURE_WEBPUBSUB_HUB_NAME` | Web PubSub hub name。 |
| `AZURE_WEBPUBSUB_GROUP_NAME` | Web PubSub base group name。 |
| `VIEWER_ACCESS_CODE_REQUIRED` | 是否要求觀眾端 negotiate 帶 access code；預設與無效值視為 `true`。 |
| `AzureWebJobsStorage__tableServiceUri` | Relay 控制狀態使用的 Azure Table endpoint；由 Bicep 設定並搭配 Managed Identity。 |
| `RELAY_CONTROL_STATE_TABLE_NAME` | 選填。Relay 控制狀態 table name；未設定時使用 `LiveCaptionRelayControlState`。 |

本機 `local.settings.json` 不得提交。正式環境由 Bicep 寫入非機密設定，並優先使用 Managed Identity。Relay runtime 不設定 Azure OpenAI endpoint、deployment、API key 或 token，也不呼叫 Azure OpenAI 進行字幕加工。

App settings、Bicep parameters、GitHub Actions secrets 與 Automation runbook parameters 不得設計成讓外部使用者可讀取、列舉或交換到 access code、Web PubSub URL、Speech key、connection string、SAS token 或其他敏感資料。

## 程式碼分層

- `Relay/function_app.py`：Azure Functions HTTP 入口。
- `Relay/src/relay/models.py`：字幕事件資料模型。
- `Relay/src/relay/validation.py`：字幕事件驗證規則。
- `Relay/src/relay/control_state.py`：Relay 控制事件最新狀態儲存，正式環境使用 Azure Table Storage。
- `Relay/src/relay/http.py`：HTTP handler 與 Web PubSub payload builder。
- `Relay/src/relay/webpubsub.py`：Azure Web PubSub publisher adapter 與觀眾端 token provider。
- `Relay/tests/`：pytest 測試。

## Logging 規則

Relay 可以記錄 track number、語言代碼、字幕數量、文字長度、驗證錯誤代碼與發布狀態。不得記錄完整逐字稿、翻譯文字、Speech key、HMAC 簽章、Web PubSub token、連線字串、SAS token、Portal 本機路徑或可識別個人的資料。

Relay 也不得記錄完整 environment、完整 HTTP headers、完整 request/response body、完整 viewer URL 或 access code。若 GitHub Actions、Azure Functions 或 Azure Automation 需要診斷輸出，只能輸出狀態碼、錯誤代碼、資源名稱與遮蔽後的摘要。

Relay 不處理 Azure OpenAI 音訊串流、prompt、response 或 session secret。若未來需要 Portal 取得 Azure OpenAI 授權，必須另行設計，不得混入 Relay 字幕轉發流程。
