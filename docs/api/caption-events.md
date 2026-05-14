# 字幕事件 API

本文定義 Portal 傳送字幕事件到 Relay 的 API 契約。Relay 負責驗證、正規化與發布事件，不負責語音辨識、翻譯或保存完整逐字稿。

## Endpoint

```http
POST /api/caption-events
Content-Type: application/json
X-LiveCaption-Timestamp: <utc-iso-8601-timestamp>
X-LiveCaption-Signature: sha256=<hmac-sha256-signature>
```

Portal 會依 final 字幕品質模式分開呼叫同一個 endpoint。快速字幕與精準字幕是兩筆獨立
POST；快速字幕的 `captionMode` 為 `fast`，精準字幕的 `captionMode` 為 `accurate`。
Relay 會拒絕舊版 `captionModes` 多模式 object。

Portal 也使用同一個 endpoint 發送控制事件，例如 Portal 狀態、字幕 session 狀態與
`captionAvailability`。控制事件 payload 的 `type` 必須為 `control`。

Portal 未進行字幕 session 時，使用下列 endpoint 更新 Relay 內部 Portal 活動時間。此請求只用於
判斷已保存的 `portalStatus: online` 是否仍新鮮，不會發布 Web PubSub 控制事件給 Viewer：

```http
POST /api/portal/activity
Content-Type: application/json
X-LiveCaption-Timestamp: <utc-iso-8601-timestamp>
X-LiveCaption-Signature: sha256=<hmac-sha256-signature>
```

```json
{
  "trackNumber": 1
}
```

Portal 使用同一個 endpoint 的 `HEAD` 方法測試 Relay 連線與簽章驗證：

```http
HEAD /api/caption-events
X-LiveCaption-Timestamp: <utc-iso-8601-timestamp>
X-LiveCaption-Signature: sha256=<hmac-sha256-signature>
```

`HEAD` body 為空 bytes。成功時 Relay 不發布字幕，只回傳觀眾端 access code：

```http
HTTP/1.1 204 No Content
X-LiveCaption-Viewer-Access-Code: <viewer-access-code>
X-LiveCaption-Viewer-Access-Expires-At: 2026-05-01T00:00:00.000Z
```

## 授權

第一版 Relay 使用 Azure Speech key 衍生的 HMAC 簽章驗證 Portal 請求。Portal 不得把 Speech key 直接送進 Relay；Relay 透過 `AZURE_SPEECH_ACCOUNT_ID` 定位 Azure Speech resource，並用 Managed Identity 讀取 Speech key 驗章。

簽章規則：

```text
message = X-LiveCaption-Timestamp + "." + raw request body bytes
signature = "sha256=" + HMAC-SHA256(<azure-speech-key>, message)
```

`X-LiveCaption-Timestamp` 必須是 UTC ISO 8601 時間，例如 `2026-04-29T12:34:56.789Z`。Relay 應拒絕超出允許時間窗的請求，避免重放。

## 請求格式

```json
{
  "roomName": "A101",
  "trackNumber": 1,
  "sessionId": "2026-04-29T12:34:00.000",
  "createdAt": "2026-04-29T12:34:56.789Z",
  "source": {
    "bundleIdentifier": "io.iplayground.LiveCaptionPortal",
    "appVersion": "1.0"
  },
  "speech": {
    "inputLanguage": "zh-TW",
    "offsetTicks": 120000000,
    "durationTicks": 35000000,
    "text": "歡迎來到今天的活動"
  },
  "captions": {
    "zh-Hant": "歡迎來到今天的活動",
    "en": "Welcome to today's event",
    "ja": "本日のイベントへようこそ"
  },
  "captionMode": "fast",
  "captionProvider": "azure-speech"
}
```

精準字幕會另以獨立 POST 傳送。Azure OpenAI 由模型端決定 final 區段，因此精準字幕可依語言逐筆送出；`captions` 只需包含本次 OpenAI final 已產出的語言。Portal 不會使用 `speech.text` 或 Azure Speech final 補入精準模式的語音輸入語言字幕：

```json
{
  "roomName": "A101",
  "trackNumber": 1,
  "sessionId": "2026-04-29T12:34:00.000",
  "createdAt": "2026-04-29T12:34:57.250Z",
  "source": {
    "bundleIdentifier": "io.iplayground.LiveCaptionPortal",
    "appVersion": "1.0"
  },
  "speech": {
    "inputLanguage": "zh-TW",
    "offsetTicks": 120000000,
    "durationTicks": 35000000,
    "text": "Welcome, everyone, to today's event."
  },
  "captions": {
    "en": "Welcome, everyone, to today's event."
  },
  "captionMode": "accurate",
  "captionProvider": "azure-openai"
}
```

## 欄位

| 欄位 | 必填 | 說明 |
| --- | --- | --- |
| `roomName` | 是 | 會議室名稱，可為空字串；不得作為唯一性或佔用判斷依據。 |
| `trackNumber` | 是 | 字幕軌編號，必須是 JSON integer 且大於 0。未使用多軌時送 `1`。 |
| `sessionId` | 是 | 字幕 session id，由 Portal 產生，用於讓 Relay 對外字幕事件標示同一場 session。不得包含本機路徑、使用者識別資料或機密。 |
| `createdAt` | 是 | Portal 建立事件的 UTC ISO 8601 時間。 |
| `source.bundleIdentifier` | 是 | Portal App bundle identifier，目前為 `io.iplayground.LiveCaptionPortal`。 |
| `source.appVersion` | 否 | Portal App 版本，用於診斷相容性，不得含使用者識別資料。 |
| `source.captionQualityMode` | 否 | final 字幕品質模式；快速為 `fast`，精準為 `accurate`。 |
| `source.captionProvider` | 否 | 舊版診斷欄位；新請求應使用 top-level `captionProvider`。 |
| `speech.inputLanguage` | 是 | 語音輸入語言，目前允許 `zh-TW` 或 `en-US`。 |
| `speech.offsetTicks` | 是 | 字幕區段起點 ticks，1 tick = 100 ns。快速模式來自 Azure Speech；精準模式來自 Azure OpenAI 區段或 Portal 的保守時間估算。 |
| `speech.durationTicks` | 是 | 字幕區段長度 ticks，1 tick = 100 ns。快速模式來自 Azure Speech；精準模式來自 Azure OpenAI 區段或 Portal 的保守時間估算。 |
| `speech.text` | 是 | 本筆事件的 Speech final 文字，只供 Relay 驗證、相容性與時序脈絡使用，不代表精準模式字幕內容，不得完整寫入 log。 |
| `captions` | 是 | 向後相容欄位，代表本筆 POST 的 final 字幕輸出語言 object。快速 POST 至少包含 `zh-Hant` 與 `en`；精準 POST 可只包含本次 Azure OpenAI final 已產出的語言。 |
| `captions.<language>` | 是 | 字幕文字，目前允許 `zh-Hant`、`en`、`ja`、`ko`。 |
| `captionMode` | 是 | final 字幕模式；允許 `fast` 或 `accurate`。 |
| `captionProvider` | 否 | final 字幕來源顯示值；Relay 不會用它決定處理流程，也不要求它與 `captionMode` 對應。若提供必須是 string，去除前後空白後可為空；非空時長度上限 50，且只允許英數、`.`、`_`、`-`。未提供或空白時 Relay 保持空值，不自動補齊。 |

## 語言規則

語音輸入語言：

- `zh-TW`
- `en-US`

字幕輸出語言：

- `zh-Hant`，必要
- `en`，必要
- `ja`，選用
- `ko`，選用

Relay 不應使用 App 介面在地化語言推論語音輸入或字幕輸出。

## 驗證規則

Relay 接收事件後必須先驗證：

- body 是 JSON object，且大小未超過上限。
- `trackNumber` 是大於 0 的 integer。
- `sessionId` 是非空 string，長度上限 80，只允許英數、`.`、`_`、`:`、`-`。
- `roomName` 是 string，可為空字串；若非空，去除前後空白後長度 1 到 80 字元，不得包含換行、控制字元、`/`、`?`、`#`。
- `createdAt` 是有效 UTC 時間，且不能明顯來自未來。
- `speech.inputLanguage` 在允許清單內。
- `speech.offsetTicks` 與 `speech.durationTicks` 是非負整數，且 `durationTicks` 大於 0。
- `speech.text` 去除前後空白後不可為空。
- `captions` 不可為空；若 `captionMode` 為 `fast`，則至少包含 `zh-Hant` 與 `en`。`accurate` 可只包含本次 OpenAI final 已產出的語言，且不以 `speech.text` 補語音輸入語言。
- `captions` key 在字幕輸出語言允許清單內，value 是非空 string。
- `captionMode` 必填，且只允許 `fast` 與 `accurate`。
- `captionProvider` 選填；若存在必須是 string，去除前後空白後可為空。非空時長度上限 50，且只允許英數、`.`、`_`、`-`。Relay 不驗證它是否與 `captionMode` 對應。
- `captionModes` 已廢除；Relay 會拒絕包含此欄位的請求。

軌道佔用判斷不在每一筆字幕事件上執行，應放在 Relay 設定檢查或未來的軌道租用流程。

## 控制事件請求

Portal 控制事件同樣使用 HMAC 驗證。Relay 依 `trackNumber` 轉送到對應 Viewer WebSocket
group，但不把 `trackNumber` 放進對外控制事件 payload。

Portal 上線：

```json
{
  "type": "control",
  "trackNumber": 1,
  "event": "portalStatus",
  "status": "online",
  "updatedAt": "2026-05-13T09:30:00.000Z"
}
```

字幕 session 開始：

```json
{
  "type": "control",
  "trackNumber": 1,
  "event": "sessionStatus",
  "status": "started",
  "sessionId": "2026-05-13T09:30:00.000",
  "updatedAt": "2026-05-13T09:30:00.000Z"
}
```

字幕可用性：

```json
{
  "type": "control",
  "trackNumber": 1,
  "event": "captionAvailability",
  "availableCaptionModes": ["fast", "accurate"],
  "availableLanguages": ["zh-Hant", "en", "ja", "ko"],
  "updatedAt": "2026-05-13T09:30:00.000Z"
}
```

控制事件允許值：

| 欄位 | 說明 |
| --- | --- |
| `event` | `portalStatus`、`sessionStatus` 或 `captionAvailability`。 |
| `status` | `portalStatus` 使用 `online` / `offline`；`sessionStatus` 使用 `started` / `stopped`。 |
| `availableCaptionModes` | `captionAvailability` 必填，允許 `fast`、`accurate`。 |
| `availableLanguages` | `captionAvailability` 必填，允許 `zh-Hant`、`en`、`ja`、`ko`。 |

## 成功回應

```http
HTTP/1.1 202 Accepted
Content-Type: application/json
```

```json
{
  "accepted": true
}
```

## 錯誤回應

Relay 已知業務錯誤使用一致 JSON 格式。部分非預期 `500 Internal Server Error` 可能由 Azure Functions runtime 或外部服務層產生，不保證符合此 envelope。

```json
{
  "error": {
    "code": "invalid_caption_event",
    "message": "Caption event is invalid.",
    "details": [
      {
        "field": "captions.en",
        "reason": "Required output language en is missing."
      }
    ]
  }
}
```

| 狀態碼 | 情境 |
| --- | --- |
| `400 Bad Request` | JSON 格式錯誤、缺少必要欄位或欄位值不合法。 |
| `401 Unauthorized` | 缺少或無效的 HMAC 簽章，或 Relay 無法取得 Azure Speech key。 |
| `413 Payload Too Large` | 保留狀態碼；未來 body 或文字欄位超過 Relay 設定上限時使用。 |
| `429 Too Many Requests` | 保留狀態碼；未來實作速率限制時使用。 |
| `500 Internal Server Error` | Relay 非預期錯誤。 |
| `502 Bad Gateway` | Azure Web PubSub 發布失敗或逾時。 |

錯誤訊息不得包含完整 `speech.text`、`captions` value、Speech key、簽章、連線字串或可識別個人的資料。

## Web PubSub 發布

Relay 會把每筆 Portal 字幕事件整理成對外字幕事件，並依 `trackNumber` 發送給觀眾端。

Portal 不需要自行組合 group 命名規則。觀眾端透過 `POST /api/viewer/negotiate` 帶入
`trackNumber`，取得該字幕軌道的單一 Viewer WebSocket URL；negotiate 不帶 `captionMode`、
`captionModes` 或語言偏好。Relay 一律發送完整字幕事件，Viewer 自行依使用者選擇的模式與
語言過濾顯示內容。
Portal 主控板若要確認觀眾實際會收到什麼，也應使用同一條 Viewer delivery path。

發布 payload 會整理成 Viewer WebSocket 字幕事件。若 Portal 提供
top-level `captionProvider`，Relay 會在非空時保留這個非敏感欄位供觀眾端或 Portal 主控板顯示
final 字幕來源；若 Portal 未提供或只提供空白，Relay 不會自動補齊，發布 payload 也會省略此欄位。

```json
{
  "type": "caption",
  "sessionId": "2026-04-29T12:34:00.000",
  "sequence": 42,
  "captionMode": "fast",
  "captionProvider": "azure-speech",
  "createdAt": "2026-04-29T12:34:56.789Z",
  "offsetTicks": 120000000,
  "durationTicks": 35000000,
  "captions": {
    "zh-Hant": "歡迎來到今天的活動",
    "en": "Welcome to today's event"
  }
}
```

若沒有產品需求需要顯示原始辨識文字，Relay 應省略 `speech.text`，只保留字幕輸出與時間碼。

## final 字幕品質模式

Portal 的 final 字幕品質模式分為：

- `fast`：final 字幕使用 Azure Speech 結果。
- `accurate`：final 字幕使用 Azure OpenAI `gpt-realtime-translate` 結果。

即時 recognizing / partial 解析一律由 Azure Speech 處理，不因 final 字幕品質模式而改變。
Relay 不負責呼叫 Azure OpenAI 改寫字幕內容；Relay 只驗證並發布 Portal 傳入的 final 字幕。
Portal 必須將 `fast` 與 `accurate` 分成兩筆事件送出；Relay 會拒絕同一筆事件同時包含兩種模式。

精準模式不得新增未經允許的字幕輸出語言。Portal、Relay 與部署流程都不得把完整音訊內容、
逐字稿、字幕文字、Azure OpenAI token 或 realtime session secret 寫入 log。
