# 觀眾端連線 API

本文件定義觀眾端 App 取得 Azure Web PubSub client access URL 的 API。觀眾端字幕只能 receive-only，不得發布字幕；字幕發布只能由 Portal 透過 Relay 的 `POST /api/caption-events` 完成。

Portal 主控板也可使用此 API 建立 receive-only 觀察連線，用來顯示 Relay 發布到 Azure Web PubSub 後再收到的字幕。這個連線只用於操作端確認 PubSub 實際輸出，不授予 Portal 任何 Web PubSub 發布權限。

## 取得觀眾端連線 URL

公開活動模式不需要 access code：

```http
POST /api/viewer/negotiate
Content-Type: application/json

{
  "trackNumber": 1,
  "captionMode": "accurate"
}
```

閒置模式或限制 negotiate 時需帶 Portal 顯示的 access code：

```http
POST /api/viewer/negotiate
Content-Type: application/json
X-LiveCaption-Viewer-Access-Code: <viewer-access-code>

{
  "trackNumber": 1,
  "captionMode": "fast"
}
```

當 Relay 設定 `VIEWER_ACCESS_CODE_REQUIRED=true` 時，觀眾端 App 必須在 `X-LiveCaption-Viewer-Access-Code` header 帶入 Portal 透過 `HEAD /api/caption-events` 取得並顯示的 access code。Portal 主控板的 PubSub 觀察連線也使用同一個 Relay 回傳的 access code；Portal 不自行計算 access code。Request body 可選；多軌活動時應帶入 `trackNumber` 做字幕軌過濾。若觀眾端要選擇 final 字幕品質，應帶入 `captionMode`，允許值為 `fast` 或 `accurate`。

Relay 驗證通過後會回傳可接收指定 group 訊息的短效 WebSocket URL。多軌活動時，觀眾端 App 與 Portal 主控板觀察連線應在 request body 帶入要收看的 `trackNumber`，Relay 會回傳該軌專用 group，例如 `caption-live-track-1`。帶入 `captionMode=accurate` 時，Relay 回傳 `caption-live-accurate-track-1`。未帶 `captionMode` 時，Relay 保留舊行為，回傳快速模式 group；未帶 `trackNumber` 時，Relay 回傳對應模式的 base group。

成功回應：

```json
{
  "url": "wss://<web-pubsub-name>.webpubsub.azure.com/client/hubs/livecaption?access_token=<token>",
  "hub": "livecaption",
  "group": "caption-live-accurate-track-1",
  "expiresAt": "2026-04-30T13:00:00.000Z"
}
```

欄位說明：

| 欄位 | 說明 |
| --- | --- |
| `url` | 觀眾端 App 用來連線 Azure Web PubSub 的短效 WebSocket URL。包含 bearer token，不應寫入 log 或長期保存。 |
| `hub` | Web PubSub hub 名稱，第一版為 `livecaption`。 |
| `group` | Relay 發布字幕的 group 名稱。多軌與模式過濾時格式為 `<base-group>-<captionMode>-track-<trackNumber>`；未帶模式時為快速模式相容 group，例如 `caption-live` 或 `caption-live-track-1`。 |
| `expiresAt` | URL 內 token 的預期到期時間。觀眾端 App 應在到期前或斷線後重新 negotiate。 |

## 權限

Relay 產生的觀眾端 URL 只會讓 client 連線後加入 negotiate 回傳的 group，不會授予任何 `webpubsub.sendToGroup` 權限。

觀眾端 App 不得直接取得 Web PubSub connection string、SAS token 或 server key。Portal 發布字幕必須走 Relay 的 HMAC 驗證 API；Portal 若為主控板顯示 PubSub 字幕而連線 Web PubSub，也只能使用此 endpoint 回傳的 receive-only URL。

## Access code

Access code 由 Relay 以 Azure Speech key、UTC 日期、Web PubSub hub 與 group 衍生，不需要 DB。Portal 透過 `HEAD /api/caption-events` 完成 Relay 連線測試時，Relay 會用 response headers 回傳當日 access code；當 `VIEWER_ACCESS_CODE_REQUIRED=true` 時，觀眾端 App 呼叫 `POST /api/viewer/negotiate` 需將該 code 放在 `X-LiveCaption-Viewer-Access-Code` request header。

Relay 驗證 negotiate request 時接受當日 access code，並允許前一日 access code 通過，避免活動跨 UTC 午夜時觀眾端立即失效。Access code 只用來限制公開 wss URL 的取得，不是使用者身份驗證。

Access code 不綁定 `trackNumber` 或 `captionMode`；同一場活動可用同一組 access code 取得不同字幕軌與字幕品質模式的 viewer URL。字幕軌與模式過濾由 Azure Web PubSub group 權限完成，觀眾端只會被加入 negotiate 指定的 group。

Relay 不會在 negotiate runtime 查詢 Azure Web PubSub SKU。是否要求 access code 由 `VIEWER_ACCESS_CODE_REQUIRED` app setting 控制，預設與無效值都視為 `true`。

`VIEWER_ACCESS_CODE_REQUIRED=false` 是 LiveCaption 活動模式規格，代表公開活動期間任何可呼叫此 endpoint 的觀眾端都可取得短效 viewer URL。這只開放接收字幕，不授予發布權限；短效 URL 仍是 bearer token，不得寫入 log 或長期保存。

## Token lifetime

第一版觀眾端 URL lifetime 為 60 分鐘。這覆蓋目前最長 40 分鐘議程，並讓 App 有足夠時間在到期前重新 negotiate。

觀眾端 App 應：

- 開啟字幕頁時呼叫 negotiate。
- WebSocket 斷線、授權失敗或接近 `expiresAt` 時重新 negotiate。
- 不把完整 `url` 寫入 log、crash report 或長期設定。
- 不把 access code、完整 request headers 或完整 response body 寫入 log、crash report 或分析事件。

Portal 主控板的 PubSub 觀察連線應：

- 在字幕 session 開始時呼叫 negotiate，並帶入 Relay 連線測試取得的 access code 與目前 `trackNumber`。
- 只顯示 Web PubSub 訊息中的 `captions` 欄位與必要接收狀態。
- 字幕 session 停止或 Relay 設定變更時關閉 WebSocket。
- 不記錄完整 WebSocket URL、access code、token、完整 headers 或完整 PubSub payload。

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

若 `trackNumber` 不是正整數，或 `captionMode` 不是 `fast` / `accurate`：

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
```

```json
{
  "error": {
    "code": "invalid_viewer_filter",
    "message": "Viewer filter is invalid.",
    "details": [
      {
        "field": "trackNumber",
        "reason": "Track number must be a positive integer."
      }
    ]
  }
}
```
