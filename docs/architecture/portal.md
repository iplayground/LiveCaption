# Portal 架構與操作端行為

Portal 是 LiveCaption 的 macOS 操作端 App，需求系統為 macOS 26。Portal 只處理操作端責任：音訊擷取、語音辨識、翻譯、字幕預覽、SRT 輸出與呼叫 Relay；Azure Web PubSub 發布細節由 Relay 管理。

## 語言邊界

- App 介面在地化：`zh-TW`、`en-US`。
- 語音輸入語言：國語、英語。
- 字幕輸出語言：台灣繁體中文、英文為必要輸出；日文、韓文可由使用者設定。

App 介面語言、語音輸入語言與字幕輸出語言必須分開管理，不得互相推論。

## 主要畫面

Portal 主畫面包含：

- 上方字幕預覽：白底投影截取區，可調整語言、尺寸、字體、行距、間距與疊加模式。
- 工作階段狀態：顯示收音、Speech、Relay、檔案權限與字幕 session 生命週期。
- 音訊輸入：列出本機輸入裝置，保存使用者選取來源，並顯示麥克風權限與音量。
- 語音分析預覽：顯示目前語音語言的 recognizing/final 結果與其他字幕語言 final 翻譯。
- Speech 設定：保存 Speech region、key、輸出語言與句子靜音分段設定。
- Relay 設定：保存 Relay URL、會議室名稱與字幕軌道值。
- 字幕檔案：保存 SRT 輸出根目錄 security-scoped bookmark。
- 事件紀錄：顯示操作、錯誤與檔案輸出狀態，但不得記錄完整字幕內容。

## 字幕 Session

開始字幕前必須同時符合：

- 已開啟收音。
- Speech 授權測試成功。
- 字幕檔案位置可存取。
- Relay 連線測試成功。

開始後 Portal 會使用主控板選定的音訊來源建立 Azure Speech Translation recognizer。字幕預覽是最高優先 UI 工作；Relay 發布、SRT 累積、事件計數與事件紀錄可延後處理，避免阻塞現場字幕畫面。

停止字幕時，Portal 會依工作階段開始時間建立 SRT 輸出資料夾，格式為 `MMdd_HHmm`，可附加清理後的工作階段標題。SRT 檔案依字幕語言代碼命名，例如 `zh-Hant.srt`、`en.srt`、`ja.srt`、`ko.srt`。若主要輸出位置失敗，Portal 會寫入 Application Support 下的 `LiveCaptionPortal/SRT Recovery/`。

## Relay 整合

Portal 只知道 Relay API，不知道 Azure Web PubSub hub、group、connection string 或 SAS token。

- 連線測試：`HEAD /api/caption-events`，驗證 HMAC 並取得觀眾端 access code。
- 字幕發布：`POST /api/caption-events`，送出字幕事件。

若 Relay 發布失敗，Portal 會記錄事件並重試，但不應中斷 Speech Translation、本機預覽或 SRT 累積。

## App 生命週期

Portal 同時間只允許一個 App 實例與一個主視窗；主視窗關閉時 App 應結束。字幕 session 進行期間，Portal 會鎖定會影響 session 的設定並建立 power assertion，停止、啟動失敗或 App 關閉時釋放。

## 原始碼分層

- `Portal/LiveCaptionPortal/ContentView.swift`：主視窗組合、App 生命週期與字幕 session 協調。
- `Portal/LiveCaptionPortal/Audio/`：音訊來源、麥克風權限、收音控制與音量。
- `Portal/LiveCaptionPortal/Speech/`：語音輸入語言、字幕輸出語言、Azure Speech 設定與 Speech Translation。
- `Portal/LiveCaptionPortal/Subtitle/`：字幕檔案位置、SRT 輸出與備援暫存。
- `Portal/LiveCaptionPortal/Relay/`：Relay URL、會議室、軌道、連線測試與字幕事件請求。
- `Portal/LiveCaptionPortal/Logging/`：事件紀錄資料模型與時間格式。
- `Portal/LiveCaptionPortal/UI/`：主畫面區塊、設定 sheet、Log drawer 與共用 SwiftUI 元件。
- `Portal/LiveCaptionPortal/L10n.swift` 與 `*.lproj/`：介面在地化查表與字串資源。
