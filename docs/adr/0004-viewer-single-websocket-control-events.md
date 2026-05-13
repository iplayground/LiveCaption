# ADR 0004: Viewer 使用單一 WebSocket 接收字幕與控制事件

- 狀態：Accepted
- 日期：2026-05-13

## 背景

Viewer 可能早於 Portal 開啟。若 `/api/viewer/negotiate` 在建立 WebSocket URL 時就要求指定
`captionMode` 或語言，Relay 在 Portal 尚未上線或字幕 session 尚未開始時無法可靠回答目前
是否有 `accurate` 或有哪些字幕語言。

原本以 `captionMode` / `trackNumber` negotiate 到不同 Web PubSub group 的模型，也讓 Viewer
必須建立多條 WebSocket 才能同時支援快速與精準字幕選擇。這不利於在 Portal 開關 Azure
OpenAI 精準字幕支援時即時更新 UI。

## 決策

1. Viewer 只建立一條 WebSocket。
2. `/api/viewer/negotiate` 驗證 access code 與活動前可知道的 `trackNumber`，並回傳該字幕軌道
   的短效 WebSocket URL；request 不帶 `captionMode`、語言或其他初始偏好。
3. Relay 在同一條 WebSocket 對 Viewer 發送字幕事件與控制事件。
4. Portal 上線、離線、開始字幕、停止字幕、開關 Azure OpenAI 精準字幕支援時，Relay 發送
   控制事件通知 Viewer。
5. 可用模式與可用語言使用 `captionAvailability` 表示。事件包含 `availableCaptionModes` 與
   `availableLanguages`。
6. Relay 以 Azure Web PubSub track group fan-out 發送字幕；group 維度為 `trackNumber`。
7. Portal 字幕事件進入 Relay 後，Relay 保留 `captionMode` 與完整 `captions` object，整理成
   單一字幕事件送到對應 track group，不逐一列舉 Viewer connection 發送。
8. Viewer 與 Portal 主控板自行依使用者選擇的模式與語言過濾顯示內容。

## 影響

正面影響：

- Viewer 比 Portal 早開時可先連線等待控制事件，不需要重複 negotiate。
- Portal 開關精準字幕支援時，Viewer 只需依新的 `captionAvailability` 更新 UI。
- Portal 主控板可用同一條 Viewer delivery path 確認觀眾實際可收到的內容。
- Viewer 人數增加時，字幕即時發送負載主要由 Azure Web PubSub fan-out 承擔，不讓 Relay 在每筆字幕上做 per-viewer send。
- Relay 不需要保存 Viewer 的模式或語言偏好。

代價與限制：

- Viewer 會收到同一字幕軌道的完整字幕事件，語言與模式過濾由 client 端處理。
- 每筆字幕訊息 payload 會包含該事件的多語言 `captions` object，需注意單筆訊息大小。
