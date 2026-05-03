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
4. Relay 建立 Web PubSub payload，省略不需給觀眾端的原始辨識文字。
5. Relay 使用 Managed Identity 發布到 base group 與字幕軌專用 group。
6. 觀眾端透過 `POST /api/viewer/negotiate` 取得 receive-only Web PubSub URL 後直接接收字幕。

任何回傳給觀眾端的 Web PubSub URL 都包含短效 bearer token，必須視為敏感資料。Relay、GitHub Actions、Azure Functions logs 與觀眾端 App 都不得記錄完整 URL、完整 headers 或完整 response body。

## Web PubSub 邊界

Portal 不設定 Web PubSub hub、group、connection string、SAS token 或發布權限。Web PubSub 相關設定只存在 Relay 與 Azure 基礎設施中。

第一版設定：

- Hub：`livecaption`
- Base group：`caption-live`
- Track group：`caption-live-track-<trackNumber>`

Relay 會同時發布到 base group 與 track group。多軌活動時，觀眾端應在 negotiate body 帶入 `trackNumber`，只加入指定軌道 group。

## App Settings

Relay 主要 app settings：

| 名稱 | 說明 |
| --- | --- |
| `AZURE_SPEECH_ACCOUNT_ID` | Azure Speech resource ARM resource id。 |
| `AZURE_WEBPUBSUB_ENDPOINT` | Azure Web PubSub endpoint。 |
| `AZURE_WEBPUBSUB_HUB_NAME` | Web PubSub hub name。 |
| `AZURE_WEBPUBSUB_GROUP_NAME` | Web PubSub base group name。 |
| `VIEWER_ACCESS_CODE_REQUIRED` | 是否要求觀眾端 negotiate 帶 access code；預設與無效值視為 `true`。 |

本機 `local.settings.json` 不得提交。正式環境由 Bicep 寫入非機密設定，並優先使用 Managed Identity。

App settings、Bicep parameters、GitHub Actions secrets 與 Automation runbook parameters 不得設計成讓外部使用者可讀取、列舉或交換到 access code、Web PubSub URL、Speech key、connection string、SAS token 或其他敏感資料。

## 程式碼分層

- `Relay/function_app.py`：Azure Functions HTTP 入口。
- `Relay/src/relay/models.py`：字幕事件資料模型。
- `Relay/src/relay/validation.py`：字幕事件驗證規則。
- `Relay/src/relay/http.py`：HTTP handler 與 Web PubSub payload builder。
- `Relay/src/relay/webpubsub.py`：Azure Web PubSub publisher adapter 與觀眾端 token provider。
- `Relay/tests/`：pytest 測試。

## Logging 規則

Relay 可以記錄 track number、語言代碼、字幕數量、文字長度、驗證錯誤代碼與發布狀態。不得記錄完整逐字稿、翻譯文字、Speech key、HMAC 簽章、Web PubSub token、連線字串、SAS token、Portal 本機路徑或可識別個人的資料。

Relay 也不得記錄完整 environment、完整 HTTP headers、完整 request/response body、完整 viewer URL 或 access code。若 GitHub Actions、Azure Functions 或 Azure Automation 需要診斷輸出，只能輸出狀態碼、錯誤代碼、資源名稱與遮蔽後的摘要。
