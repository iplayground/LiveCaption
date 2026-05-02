# 觀眾端連線 API

本文件定義觀眾端 App 取得 Azure Web PubSub client access URL 的 API。觀眾端字幕是公開接收，但不得發布字幕；字幕發布只能由 Portal 透過 Relay 的 `POST /api/caption-events` 完成。

## 取得觀眾端連線 URL

```http
POST /api/viewer/negotiate
Content-Type: application/json
X-LiveCaption-Viewer-Access-Code: 482913

{
  "trackNumber": 1
}
```

當 Relay 設定 `VIEWER_ACCESS_CODE_REQUIRED=true` 時，觀眾端 App 必須在 `X-LiveCaption-Viewer-Access-Code` header 帶入 Portal 透過 `HEAD /api/caption-events` 取得並顯示的 access code。Request body 可選；多軌活動時應帶入 `trackNumber` 做字幕軌過濾。

Relay 驗證通過後會回傳可接收指定 group 訊息的短效 WebSocket URL。多軌活動時，觀眾端 App 應在 request body 帶入要收看的 `trackNumber`，Relay 會回傳該軌專用 group，例如 `caption-live-track-1`。未帶 `trackNumber` 時，Relay 保留舊行為，回傳可接收 `caption-live` base group 的 URL。

成功回應：

```json
{
  "url": "wss://<web-pubsub-name>.webpubsub.azure.com/client/hubs/livecaption?access_token=<token>",
  "hub": "livecaption",
  "group": "caption-live-track-1",
  "expiresAt": "2026-04-30T13:00:00.000Z"
}
```

欄位說明：

| 欄位 | 說明 |
| --- | --- |
| `url` | 觀眾端 App 用來連線 Azure Web PubSub 的短效 WebSocket URL。包含 bearer token，不應寫入 log 或長期保存。 |
| `hub` | Web PubSub hub 名稱，第一版為 `livecaption`。 |
| `group` | Relay 發布字幕的 group 名稱。多軌過濾時格式為 `<base-group>-track-<trackNumber>`；未帶過濾時為 base group，例如 `caption-live`。 |
| `expiresAt` | URL 內 token 的預期到期時間。觀眾端 App 應在到期前或斷線後重新 negotiate。 |

## 權限

Relay 產生的觀眾端 URL 只會讓 client 連線後加入 negotiate 回傳的 group，不會授予任何 `webpubsub.sendToGroup` 權限。

觀眾端 App 不得直接取得 Web PubSub connection string、SAS token 或 server key。Portal 也不直接連 Web PubSub；Portal 發布字幕必須走 Relay 的 HMAC 驗證 API。

## Access code

Access code 由 Relay 以 Azure Speech key、UTC 日期、Web PubSub hub 與 group 衍生，不需要 DB。Portal 透過 `HEAD /api/caption-events` 完成 Relay 連線測試時，Relay 會用 response headers 回傳當日 access code；當 `VIEWER_ACCESS_CODE_REQUIRED=true` 時，觀眾端 App 呼叫 `POST /api/viewer/negotiate` 需將該 code 放在 `X-LiveCaption-Viewer-Access-Code` request header。

Relay 驗證 negotiate request 時接受當日 access code，並允許前一日 access code 通過，避免活動跨 UTC 午夜時觀眾端立即失效。Access code 只用來限制公開 wss URL 的取得，不是使用者身份驗證。

Access code 不綁定 `trackNumber`；同一場活動可用同一組 access code 取得不同字幕軌的 viewer URL。字幕軌過濾由 Azure Web PubSub group 權限完成，觀眾端只會被加入 negotiate 指定的 group。

Relay 不會在 negotiate runtime 查詢 Azure Web PubSub SKU。是否要求 access code 由 `VIEWER_ACCESS_CODE_REQUIRED` app setting 控制，預設與無效值都視為 `true`；切換 Web PubSub 付費層時，部署或排程流程應同步更新這個 app setting。

## Token lifetime

第一版觀眾端 URL lifetime 為 60 分鐘。這覆蓋目前最長 40 分鐘議程，並讓 App 有足夠時間在到期前重新 negotiate。

觀眾端 App 應：

- 開啟字幕頁時呼叫 negotiate。
- WebSocket 斷線、授權失敗或接近 `expiresAt` 時重新 negotiate。
- 不把完整 `url` 寫入 log、crash report 或長期設定。

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
