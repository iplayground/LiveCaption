# 字幕事件 API

本文定義 Portal 傳送字幕事件到 Relay 的 API 契約。Relay 負責驗證、正規化與發布事件，不負責語音辨識、翻譯或保存完整逐字稿。

## Endpoint

```http
POST /api/caption-events
Content-Type: application/json
X-LiveCaption-Timestamp: <utc-iso-8601-timestamp>
X-LiveCaption-Signature: sha256=<hmac-sha256-signature>
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
  }
}
```

## 欄位

| 欄位 | 必填 | 說明 |
| --- | --- | --- |
| `roomName` | 是 | 會議室名稱，可為空字串；不得作為唯一性或佔用判斷依據。 |
| `trackNumber` | 是 | 字幕軌編號，必須是 JSON integer 且大於 0。未使用多軌時送 `1`。 |
| `createdAt` | 是 | Portal 建立事件的 UTC ISO 8601 時間。 |
| `source.bundleIdentifier` | 是 | Portal App bundle identifier，目前為 `io.iplayground.LiveCaptionPortal`。 |
| `source.appVersion` | 否 | Portal App 版本，用於診斷相容性，不得含使用者識別資料。 |
| `speech.inputLanguage` | 是 | 語音輸入語言，目前允許 `zh-TW` 或 `en-US`。 |
| `speech.offsetTicks` | 是 | Azure Speech SDK 回傳的 offset ticks，1 tick = 100 ns。 |
| `speech.durationTicks` | 是 | Azure Speech SDK 回傳的 duration ticks，1 tick = 100 ns。 |
| `speech.text` | 是 | 最終辨識文字，只供 Relay 發布或轉換，不得完整寫入 log。 |
| `captions` | 是 | 字幕輸出語言 object，至少包含 `zh-Hant` 與 `en`。 |
| `captions.<language>` | 是 | 字幕文字，目前允許 `zh-Hant`、`en`、`ja`、`ko`。 |

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
- `roomName` 是 string，可為空字串；若非空，去除前後空白後長度 1 到 80 字元，不得包含換行、控制字元、`/`、`?`、`#`。
- `createdAt` 是有效 UTC 時間，且不能明顯來自未來。
- `speech.inputLanguage` 在允許清單內。
- `speech.offsetTicks` 與 `speech.durationTicks` 是非負整數，且 `durationTicks` 大於 0。
- `speech.text` 去除前後空白後不可為空。
- `captions` 至少包含 `zh-Hant` 與 `en`。
- `captions` key 在字幕輸出語言允許清單內，value 是非空 string。

軌道佔用判斷不在每一筆字幕事件上執行，應放在 Relay 設定檢查或未來的軌道租用流程。

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

Relay 會把每筆字幕發布到 base group 與字幕軌專用 group：

```text
caption-live
caption-live-track-<trackNumber>
```

Portal 不需要知道 group 命名規則。多軌活動時，觀眾端應透過 `POST /api/viewer/negotiate` 帶入 `trackNumber`，取得對應 track group 的 receive-only URL。

發布 payload 保留 Portal 傳入的公開字幕欄位，並加入 Relay metadata：

```json
{
  "relay": {
    "receivedAt": "2026-04-29T12:34:56.900Z"
  },
  "roomName": "A101",
  "trackNumber": 1,
  "createdAt": "2026-04-29T12:34:56.789Z",
  "speech": {
    "inputLanguage": "zh-TW",
    "offsetTicks": 120000000,
    "durationTicks": 35000000
  },
  "captions": {
    "zh-Hant": "歡迎來到今天的活動",
    "en": "Welcome to today's event"
  }
}
```

若沒有產品需求需要顯示原始辨識文字，Relay 應省略 `speech.text`，只保留字幕輸出與時間碼。
