# Portal 連線 API

本文件定義 Portal 取得 operator 用 Azure Web PubSub client access URL 的 API。此連線只供
Portal 觀察 Relay 已發布的 final 字幕，不得授予 Portal 透過 Web PubSub 發布字幕的權限。

## 取得 Portal operator 連線 URL

```http
POST /api/portal/negotiate
Content-Type: application/json
X-LiveCaption-Timestamp: <utc-iso-8601-timestamp>
X-LiveCaption-Signature: sha256=<hmac-sha256-signature>

{
  "trackNumber": 1,
  "captionMode": "accurate"
}
```

授權規則與 `POST /api/caption-events` 相同，Portal 使用 Azure Speech key 衍生的 HMAC
簽章驗證請求。Request body 可選；多軌活動時應帶入 `trackNumber`，Relay 會回傳該軌
operator group 的 receive-only URL。若要觀察特定 final 字幕品質，應帶入 `captionMode`，
允許值為 `fast` 或 `accurate`。未帶 `captionMode` 時，Relay 回傳快速模式相容 group。

成功回應：

```json
{
  "url": "wss://<web-pubsub-name>.webpubsub.azure.com/client/hubs/livecaption?access_token=<token>",
  "hub": "livecaption",
  "group": "caption-operator-accurate-track-1",
  "expiresAt": "2026-04-30T13:00:00.000Z"
}
```

欄位說明：

| 欄位 | 說明 |
| --- | --- |
| `url` | Portal 用來連線 Azure Web PubSub 的短效 WebSocket URL。包含 bearer token，不應寫入 log 或長期保存。 |
| `hub` | Web PubSub hub 名稱，第一版為 `livecaption`。 |
| `group` | Portal operator 接收字幕的 group 名稱。多軌與模式過濾時格式為 `<operator-group>-<captionMode>-track-<trackNumber>`；未帶模式時為快速模式相容 group，例如 `caption-operator` 或 `caption-operator-track-1`。 |
| `expiresAt` | URL 內 token 的預期到期時間。Portal 應在到期前或斷線後重新 negotiate。 |

## 權限與資料流

Relay 產生的 Portal operator URL 只會讓 client 連線後加入 negotiate 回傳的 operator group，
不會授予任何 `webpubsub.sendToGroup` 權限。

Relay 發布字幕事件時會同時送到：

- 觀眾端 base group：`caption-live`
- 觀眾端 track group：`caption-live-track-<trackNumber>`
- 觀眾端模式 group：`caption-live-<captionMode>`
- 觀眾端模式 track group：`caption-live-<captionMode>-track-<trackNumber>`
- Portal operator base group：`caption-operator`
- Portal operator track group：`caption-operator-track-<trackNumber>`
- Portal operator 模式 group：`caption-operator-<captionMode>`
- Portal operator 模式 track group：`caption-operator-<captionMode>-track-<trackNumber>`

Portal 可訂閱 operator track group，在操作端 UI 顯示 Relay 實際發布出去的 final 字幕。
快速模式下 final 字幕來源為 Azure Speech；精準模式下 final 字幕來源為 Azure OpenAI
`gpt-realtime-translate`。

## 錯誤回應

缺少或無效 HMAC 簽章：

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json
```

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Request is not authorized.",
    "details": []
  }
}
```

若 Relay 無法向 Azure Web PubSub 產生 operator client access URL：

```http
HTTP/1.1 502 Bad Gateway
Content-Type: application/json
```

```json
{
  "error": {
    "code": "portal_negotiate_failed",
    "message": "Portal connection could not be negotiated.",
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
    "code": "invalid_portal_filter",
    "message": "Portal filter is invalid.",
    "details": [
      {
        "field": "trackNumber",
        "reason": "Track number must be a positive integer."
      }
    ]
  }
}
```

錯誤訊息不得包含 Web PubSub token、Azure OpenAI prompt、字幕文字、connection string、
SAS token、Speech key、HMAC 簽章或其他機密。
