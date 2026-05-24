# Viewer 使用 Relay 整合指南

本文整理公開活動 Viewer 端如何透過 Relay 接收 LiveCaption 字幕。公開活動不需要 viewer access code；
本文聚焦 Viewer 實作流程與狀態處理。開發期、本機 Relay、非公開連線或完整 API 契約請改讀
[觀眾端連線與 WebSocket 事件 API](viewer-negotiate.md) 與 [Relay README](../../Relay/README.md)。

## Viewer 責任

Viewer 只負責觀眾端顯示與本機偏好，後端細節由 Relay 封裝。

Viewer 應處理：

- 讓使用者選擇字幕軌道 `trackNumber`。
- 向 Relay negotiate 取得短效 WebSocket URL。
- 建立單一 WebSocket，接收控制事件與字幕事件。
- 依使用者選擇的字幕模式與語言，在本機過濾與顯示。
- 在斷線、token 接近到期或授權失效時重新 negotiate。

Viewer 不應處理：

- 依賴 negotiate 回應以外的隱含路由規則。
- 將字幕模式或語言偏好送給 Relay negotiate。

## 整合流程

1. 取得活動資訊。

   Viewer 需要知道 Relay base URL 與 `trackNumber`。未使用多軌時 `trackNumber` 通常為 `1`。

   目前正式 Relay base URL：

   ```text
   https://livecaption-relay.iplayground.io
   ```

2. 呼叫 negotiate。

   ```http
   POST /api/viewer/negotiate
   Content-Type: application/json

   {
     "trackNumber": 1
   }
   ```

   Request body 只需要送 `trackNumber`。

3. 使用回應的 `url` 建立 WebSocket。

   成功回應包含：

   ```json
   {
     "url": "wss://<viewer-websocket-url>?access_token=<token>",
     "hub": "livecaption",
     "expiresAt": "2026-04-30T13:00:00.000Z"
   }
   ```

   `url` 用於建立當次 WebSocket。Viewer 可使用 `expiresAt` 安排重新 negotiate。

4. 等待控制事件建立 UI 狀態。

   Viewer 連線成功後，會透過同一條 WebSocket 收到目前已知的控制狀態。Viewer 不應在尚未收到控制事件前假設 Portal 已上線、session 已開始或精準字幕可用。

5. 接收字幕事件並本機過濾。

   字幕事件會包含 `captionMode` 與多語言 `captions`。Viewer 依使用者選擇顯示指定模式與語言；這些偏好不送到 Relay。

## WebSocket 事件處理

所有 server payload 都是 JSON object，且必有 `type`。

`type` 目前有兩種：

| `type` | 說明 |
| --- | --- |
| `control` | 狀態事件，用來更新 Portal、字幕 session 與字幕可用性。 |
| `caption` | 字幕事件，用來顯示實際字幕文字。 |

控制事件範例：

```json
{
  "type": "control",
  "event": "captionAvailability",
  "availableCaptionModes": ["fast", "accurate"],
  "availableLanguages": ["zh-Hant", "en", "ja", "ko"],
  "updatedAt": "2026-05-13T09:30:00.000Z"
}
```

字幕事件範例：

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

Viewer 應以 `sessionId`、`sequence`、`captionMode` 與語言 key 決定顯示內容。`sequence` 可用於排序與去重；`offsetTicks`、`durationTicks` 可用於字幕時間軸或除錯摘要。

## Viewer 狀態模型

Viewer 應以 `control` 事件驅動畫面狀態：

| 狀態來源 | Viewer 行為 |
| --- | --- |
| 尚未連線 | 顯示連線中或要求活動資訊。 |
| `portalStatus: offline` | 顯示 Portal 尚未上線或已離線；停止期待字幕可用性。 |
| `portalStatus: online` | 顯示 Portal 已上線，可等待 session。 |
| `sessionStatus: started` | 顯示字幕 session 進行中，準備接收字幕。 |
| `sessionStatus: stopped` | 顯示字幕 session 已停止；可保留最後字幕或清空，依產品設計決定。 |
| `captionAvailability` | 更新可選字幕模式與語言。 |

若 Viewer 比 Portal 晚連線，連線建立後仍會收到目前最新控制狀態。若收到 `portalStatus: offline`，Viewer 應停止期待字幕可用性，直到後續收到新的 online 或 session 事件。

## 模式與語言選擇

目前可能收到的字幕模式：

| 模式 | 說明 |
| --- | --- |
| `fast` | 低延遲 final 字幕。 |
| `accurate` | 校正後 final 字幕，可能晚於 fast 抵達。 |

目前支援的字幕語言：

| 語言 | 說明 |
| --- | --- |
| `zh-Hant` | 台灣繁體中文。 |
| `en` | 英文。 |
| `ja` | 日文。 |
| `ko` | 韓文。 |

Viewer 可以提供使用者偏好，例如優先顯示 `accurate`、fallback 到 `fast`，或固定顯示某一語言。但這些偏好只存在 Viewer 本機；negotiate 不帶這些偏好。

當 `captionAvailability` 不包含使用者目前選擇時，Viewer 應提示該模式或語言目前不可用，並選擇產品定義的 fallback。若某筆 `caption` event 的 `captions` 沒有選定語言，Viewer 應略過該語言或顯示等待狀態，不應向 Relay 重新要求特定語言。

## 重新連線與 token 更新

Viewer 應在下列情況重新呼叫 `POST /api/viewer/negotiate`：

- WebSocket 斷線。
- WebSocket 授權失敗或連線被拒。
- 目前時間接近 `expiresAt`。
- 使用者切換 `trackNumber`。

重新連線時應重新建立 WebSocket，不要重用舊的 `url`。短效 URL 預設 lifetime 為 60 分鐘，Viewer 可在到期前數分鐘主動更新，避免活動中斷線。

## 錯誤處理

常見 negotiate 錯誤：

| HTTP 狀態 | `error.code` | Viewer 行為 |
| --- | --- | --- |
| `400` | `invalid_viewer_filter` | 檢查 `trackNumber` 是否為正整數，且 request body 未帶字幕偏好欄位。 |
| `403` | `viewer_access_denied` | 公開活動不預期發生；確認活動是否已開放，或參考完整 API 契約。 |
| `502` | `viewer_negotiate_failed` | 顯示 Relay 暫時無法建立連線，稍後重試。 |

## 資料流順序

公開活動 Viewer 的資料流順序：

1. Viewer 取得 Relay base URL 與 `trackNumber`。
2. Viewer 呼叫 `POST /api/viewer/negotiate`，取得短效 WebSocket `url` 與 `expiresAt`。
3. Viewer 使用 `url` 建立 WebSocket。
4. Viewer 透過 WebSocket 接收 `control` 事件，更新 Portal、字幕 session 與字幕可用性狀態。
5. Viewer 透過同一條 WebSocket 接收 `caption` 事件。
6. Viewer 依本機選擇的字幕模式與語言顯示字幕。
7. WebSocket 斷線、授權失敗、接近 `expiresAt` 或切換 `trackNumber` 時，Viewer 重新 negotiate 並建立新 WebSocket。
