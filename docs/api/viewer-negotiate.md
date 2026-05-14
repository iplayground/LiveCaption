# 觀眾端連線與 WebSocket 事件 API

本文件定義觀眾端 App 取得 Azure Web PubSub client access URL，以及連線後接收 Relay 字幕與控制事件的 API 契約。

Viewer 只使用一條 WebSocket。Relay 透過同一條 WebSocket 發送字幕事件與控制事件。`/api/viewer/negotiate` 只帶活動前即可知道的字幕軌道編號，不帶字幕模式或語言偏好；Portal 是否已上線、字幕 session 是否開始或精準字幕是否可用，需以 WebSocket 控制事件為準。

Portal 主控板若要確認觀眾實際會收到什麼，也應使用本 API 建立 Viewer WebSocket。這可避免 Portal 主控板和觀眾端走不同 delivery path 而產生偏差。

## 取得觀眾端連線 URL

公開活動模式不需要 access code：

```http
POST /api/viewer/negotiate
Content-Type: application/json

{
  "trackNumber": 1
}
```

限制 negotiate 時需帶 Portal 顯示的 access code：

```http
POST /api/viewer/negotiate
Content-Type: application/json
X-LiveCaption-Viewer-Access-Code: <viewer-access-code>

{
  "trackNumber": 1
}
```

Request body 應帶入 `trackNumber`。字幕軌道代表活動前即可知道的會議室或字幕來源；Relay 依 `trackNumber` 建立該軌道的 Viewer WebSocket。Relay 不接受 `captionMode`、`captionModes`、`language`、`languages` 等偏好欄位；Viewer 若只需要特定模式或語言，應在收到字幕事件後自行過濾。

成功回應：

```json
{
  "url": "wss://<web-pubsub-name>.webpubsub.azure.com/client/hubs/livecaption?access_token=<token>",
  "hub": "livecaption",
  "expiresAt": "2026-04-30T13:00:00.000Z"
}
```

欄位說明：

| 欄位 | 說明 |
| --- | --- |
| `url` | 觀眾端 App 用來連線 Azure Web PubSub 的短效 WebSocket URL。包含 bearer token，不應寫入 log 或長期保存。 |
| `hub` | Web PubSub hub 名稱，第一版為 `livecaption`。 |
| `expiresAt` | URL 內 token 的預期到期時間。觀眾端 App 應在到期前或斷線後重新 negotiate。 |

Request body 欄位：

| 欄位 | 必填 | 說明 |
| --- | --- | --- |
| `trackNumber` | 是 | 字幕軌道編號，必須是正整數。活動開始前即可知道哪些會議室或軌道會有字幕；Viewer 以此選擇要連線的軌道。 |

## Viewer WebSocket 模型

Viewer WebSocket 是單一 session 通道：

- Server 到 Viewer：發送 Portal 狀態、字幕 session 狀態與字幕事件。
- Viewer 比 Portal 更早開啟時，Relay 仍可先完成 negotiate；Viewer 連線後等待控制事件。
- Viewer 比 Portal 晚連線時，Relay 會在 Web PubSub `connected` system event 後，補送該軌道目前最新的 `portalStatus`、`sessionStatus` 與 `captionAvailability` 給該 connection；若該次回放的 `portalStatus` 為 `offline`，Relay 不補送 `captionAvailability`。
- Portal 開啟、關閉、開始字幕、停止字幕、開關 Azure OpenAI 精準字幕支援時，Relay 需透過控制事件通知 Viewer。

Relay 不需要保存每個 Viewer 的字幕模式或語言偏好。模式與語言選擇是 Viewer UI 狀態，不是 Relay routing 狀態。

Relay 必須使用 Azure Web PubSub track group fan-out 發送字幕，不得在每筆字幕事件中逐一列舉 Viewer connection 發送。Viewer negotiate 成功後，Relay 讓該 connection 加入對應 `trackNumber` 的字幕 group。

Relay 會將最新控制狀態保存於 Azure Table Storage，而不是 Function instance memory。這是為了確保 Azure Functions scale-out 到多個 instance 時，任何 instance 收到 Web PubSub `connected` system event 都能讀到相同的目前狀態。

字幕 group 命名格式：

```text
caption-live-track-<trackNumber>
```

例如：

```text
caption-live-track-1
```

Portal 字幕事件進入 Relay 後，Relay 保留該事件的 `captionMode` 與 `captions` object，整理成單一 `caption` event 送到該 track group，由 Azure Web PubSub 負責 fan-out 給 group 內的 Viewer。Viewer 端再依自己的模式與語言選擇過濾要顯示的區段。

## Server 到 Viewer 事件

所有 server 發送的 WebSocket payload 都必須是 JSON object，且包含 `type`。

### Portal 狀態

Portal 開啟或關閉時，Relay 發送：

```json
{
  "type": "control",
  "event": "portalStatus",
  "status": "online",
  "updatedAt": "2026-05-13T09:30:00.000Z"
}
```

`status` 允許：

- `online`
- `offline`

`online` 是活動狀態。Portal 未進行字幕時會以內部 activity 更新維持狀態；字幕 session 進行中則以
字幕事件本身更新活動時間，不需額外 activity 更新。activity 更新不會發送給 Viewer，只有
`portalStatus` 狀態改變時才會發送控制事件。若 Portal 關閉或閃退而未能送出 `offline`，新 Viewer
連線時 Relay 會在目前保存的 `online` 超過有效時間後，對該 connection 補送一筆合成的
`portalStatus: offline`；此合成事件不會寫回控制狀態，也不會推送給既有連線 Viewer。`offline`
不會因時間過期而被忽略。當新 connection 的回放狀態為 `offline` 時，Relay 不補送已保存的
`captionAvailability`。

### 字幕 Session 狀態

Portal 開始或停止字幕 session 時，Relay 發送：

```json
{
  "type": "control",
  "event": "sessionStatus",
  "status": "started",
  "sessionId": "2026-05-13T09:30:00.000Z",
  "updatedAt": "2026-05-13T09:30:00.000Z"
}
```

`status` 允許：

- `started`
- `stopped`

`sessionId` 由 Relay 或 Portal 產生，僅用於區分目前字幕 session，不得包含本機路徑、使用者識別資料或機密。

### 字幕可用性

Portal 開關 Azure OpenAI 精準字幕支援、字幕輸出語言變更或 session 開始時，Relay 發送：

```json
{
  "type": "control",
  "event": "captionAvailability",
  "availableCaptionModes": ["fast", "accurate"],
  "availableLanguages": ["zh-Hant", "en", "ja", "ko"],
  "updatedAt": "2026-05-13T09:30:00.000Z"
}
```

欄位語意：

| 欄位 | 說明 |
| --- | --- |
| `availableCaptionModes` | 目前 session 可選的字幕模式。`fast` 表示 Azure Speech final，`accurate` 表示 Azure OpenAI final。 |
| `availableLanguages` | 目前 session 可選的字幕語言。 |

Viewer 規則：

- 尚未收到 `captionAvailability` 時，顯示等待 Portal 或等待字幕 session。
- 收到後依 `availableCaptionModes` 與 `availableLanguages` 更新可選項。

### 字幕事件

Relay 依 `trackNumber` 發送字幕。每筆字幕事件保留 Portal 傳入的 `captionMode` 與多語言 `captions`，Viewer 自行選擇要顯示的模式與語言：

```json
{
  "type": "caption",
  "sessionId": "2026-05-13T09:30:00.000Z",
  "sequence": 42,
  "captionMode": "accurate",
  "createdAt": "2026-05-13T09:31:12.345Z",
  "offsetTicks": 120000000,
  "durationTicks": 35000000,
  "captions": {
    "zh-Hant": "歡迎來到今天的活動",
    "en": "Welcome to today's event.",
    "ja": "本日のイベントへようこそ",
    "ko": "오늘 행사에 오신 것을 환영합니다"
  }
}
```

欄位語意：

| 欄位 | 說明 |
| --- | --- |
| `sessionId` | 字幕 session id。 |
| `sequence` | Relay 在同一 session 內遞增的字幕序號，用於排序與去重。 |
| `captionMode` | 字幕來源模式。 |
| `createdAt` | Portal 建立字幕事件的 UTC ISO 8601 時間。 |
| `offsetTicks` | 字幕區段起點 ticks，1 tick = 100 ns。 |
| `durationTicks` | 字幕區段長度 ticks，1 tick = 100 ns。 |
| `captions` | 本筆事件包含的字幕語言與文字。Viewer 可依使用者選擇自行過濾。 |

Relay 不應把完整 `speech.text`、access code、token 或完整上游 request/response body 發送給 Viewer。

## Access Code

Access code 由 Relay 以 Azure Speech key、UTC 日期、Web PubSub hub 與 group 衍生，不需要 DB。Portal 透過 `HEAD /api/caption-events` 完成 Relay 連線測試時，Relay 會用 response headers 回傳當日 access code；當 `VIEWER_ACCESS_CODE_REQUIRED=true` 時，觀眾端 App 呼叫 `POST /api/viewer/negotiate` 需將該 code 放在 `X-LiveCaption-Viewer-Access-Code` request header。

Relay 驗證 negotiate request 時接受當日 access code，並允許前一日 access code 通過，避免活動跨 UTC 午夜時觀眾端立即失效。Access code 只用來限制公開 WebSocket URL 的取得，不是使用者身份驗證。

Access code 不綁定字幕模式或語言；Viewer 在本機自行管理顯示偏好。

Relay 不會在 negotiate runtime 查詢 Azure Web PubSub SKU。是否要求 access code 由 `VIEWER_ACCESS_CODE_REQUIRED` app setting 控制，預設與無效值都視為 `true`。

`VIEWER_ACCESS_CODE_REQUIRED=false` 是 LiveCaption 活動模式規格，代表公開活動期間任何可呼叫此 endpoint 的觀眾端都可取得短效 viewer URL。這只開放接收字幕與控制事件，不授予發布字幕權限；短效 URL 仍是 bearer token，不得寫入 log 或長期保存。

## Token Lifetime

第一版觀眾端 URL lifetime 為 60 分鐘。這覆蓋目前最長 40 分鐘議程，並讓 App 有足夠時間在到期前重新 negotiate。

觀眾端 App 應：

- 開啟字幕頁時呼叫 negotiate。
- WebSocket 斷線、授權失敗或接近 `expiresAt` 時重新 negotiate。
- 不把完整 `url` 寫入 log、crash report 或長期設定。
- 不把 access code、完整 request headers 或完整 response body 寫入 log、crash report 或分析事件。
- 尚未收到 `portalStatus`、`sessionStatus` 或 `captionAvailability` 時，以等待狀態呈現，不自行假設 accurate 可用。

## 錯誤回應

若 Relay 無法向 Azure Web PubSub 產生 client access URL：

```http
HTTP/1.1 502 Bad Gateway
Content-Type: application/json
```

```json
{
  "error": {
    "code": "viewer_negotiate_failed",
    "message": "Viewer connection could not be negotiated.",
    "details": []
  }
}
```

錯誤訊息不得包含 Web PubSub token、connection string、SAS token 或其他機密。

當 `VIEWER_ACCESS_CODE_REQUIRED=true`，但缺少或帶入錯誤 access code：

```http
HTTP/1.1 403 Forbidden
Content-Type: application/json
```

```json
{
  "error": {
    "code": "viewer_access_denied",
    "message": "Viewer access code is invalid.",
    "details": []
  }
}
```

若 `trackNumber` 不是正整數：

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
```

```json
{
  "error": {
    "code": "invalid_viewer_negotiate_request",
    "message": "Viewer negotiate request is invalid.",
    "details": [
      {
        "field": "trackNumber",
        "reason": "Track number must be a positive integer."
      }
    ]
  }
}
```

若 negotiate request body 帶入字幕模式或語言偏好欄位：

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
```

```json
{
  "error": {
    "code": "invalid_viewer_negotiate_request",
    "message": "Viewer negotiate request is invalid.",
    "details": [
      {
        "field": "captionModes",
        "reason": "Caption preferences are not accepted by viewer negotiate."
      }
    ]
  }
}
```
