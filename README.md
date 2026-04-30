# LiveCaption

LiveCaption 是一套用於現場活動的即時語音辨識與翻譯系統。

## 目前狀態

目前專案已建立 Portal macOS App 的主畫面，
用來確認現場操作台的資訊架構與逐步接上本機功能。
Relay 後端仍維持為後續整合目標。

## 元件

### Portal

Portal 是 macOS 操作端 App。它會擷取音訊、執行語音辨識與翻譯，並將字幕事件傳送至 Relay。

目前 Portal 的狀態：

- 需求系統為 macOS 26。
- App 介面在地化目前支援 `zh-TW` 與 `en-US`，預設開發語言為 `zh-TW`。
  Swift UI 與錯誤、事件文字透過 `Localizable.strings` 查表，
  並和語音輸入語言、字幕輸出語言分開管理。
- 語音輸入語言支援國語與英語。
- 字幕輸出支援台灣繁體中文、日文、英文與韓文；
  台灣繁體中文與英文為必要輸出，日文與韓文可在 Speech 設定中切換。
- 主畫面包含工作階段、音訊輸入、字幕檔案、字幕預覽、Speech 設定、
  Relay 設定、最近狀態與底部可展開事件紀錄。
- 工作階段區塊會以醒目狀態顯示目前工作階段、收音、Speech、Relay 與檔案權限。
  工作階段狀態會依「尚未開始」、「準備就緒」、「字幕中」、
  「正在停止」、「已完成」、
  「完成但有警告」與「結束失敗」呈現字幕 session 生命週期。
  其中 Speech 列顯示 Azure Speech 授權測試狀態，Relay 列顯示 Portal 目前保存的 Relay 連線狀態。
  字幕事件計數移至右側 Relay 區塊，並在每次新的字幕工作階段開始時從 0 重新計算。
- 音訊輸入區塊可列出本機音訊輸入裝置（包含 3.5mm 外部輸入等來源）、
  在尚未有使用者選取時預設選取 macOS 目前預設音訊輸入、
  隱藏系統標示為虛擬的音訊裝置、
  保存使用者選取來源，並透過開關控制是否收音。
- 開啟收音時，Portal 會先檢查麥克風權限；若沒有權限，
  收音開關會回到關閉狀態並提示使用者是否前往系統設定，不會直接開啟系統設定。
- 音訊輸入區塊會顯示麥克風權限狀態，並以可切換自動校準的即時音量表呈現輸入音量；
  音量條會平滑回落，peak indicator 會以較快速度回落。
- 字幕檔案區塊可設定 SRT 輸出根目錄，路徑以尾段為主顯示，
  點擊路徑會用 Finder 開啟該資料夾。
  Portal 會保存使用者選取資料夾的 security-scoped bookmark，
  並在工作階段區塊顯示檔案權限狀態。
- App 開啟後字幕區會依每個字幕框的語言顯示歡迎文字；點擊「開始字幕」後，
  即時字幕區只使用 Speech recognizing 階段回傳的非空中間辨識結果。
  若 Speech SDK 傳回空字串，Portal 不會更新畫面，也不會用最終辨識結果補進即時字幕區。
- 字幕預覽中央區可輸入本次工作階段標題。標題輸入框不會在 App 啟動時自動取得焦點；
  只有使用者點擊輸入框時才進入焦點模式，
  點擊其他地方或按下 Return、Esc、Tab 會退出焦點模式。
- 只有在已開啟收音、Speech 授權測試狀態為「已授權」、字幕檔案位置可存取，
  且 Relay 連線測試成功時，「開始字幕」才可使用；
  點擊後會以主控板選定的音訊來源啟動 Speech Translation。
- 「開始字幕」左側會顯示本次字幕工作階段計時器，格式為分與秒。
  計時器只供使用者觀察；SRT 時間碼使用 Speech SDK 回傳的 `offset` 與 `duration`。
- 字幕預覽會排除與即時語音相同的語言；即時區顯示目前語音語言的中間辨識文字，
  預覽區顯示其他字幕輸出語言。若 Speech SDK 在 recognizing 階段提供中間翻譯，
  Portal 會優先顯示中間翻譯；否則顯示最後一次可用的最終翻譯。
  字幕預覽更新是 Portal 主執行緒的最高優先 UI 工作，Relay 發布、SRT 累積、
  事件計數與事件紀錄會延後處理，避免阻塞即時字幕畫面。
- Relay 設定由 Portal 右側 Relay 區塊開啟，
  包含 Relay URL、可留空的會議室名稱與整數軌道值。
  測試 Relay 時，Portal 會先儲存並正規化設定，再發送測試請求；
  若 Relay 發布字幕事件失敗，
  Portal 會記錄事件並重試，但不會中斷 Speech Translation 或本機字幕預覽。
- 停止字幕時，Portal 會依工作階段開始時間建立 SRT 輸出資料夾，
  資料夾名稱格式為 `MMdd_HHmm`。
  若有工作階段標題，資料夾名稱會加上空格與清理後的標題。
  資料夾內依字幕輸出語言代碼命名 SRT，例如 `zh-Hant.srt`、`en.srt`、`ja.srt`、`ko.srt`。
- 若使用者設定的字幕檔案位置寫入失敗，
  Portal 會改將 SRT 暫存到 App 可存取的 Application Support 備援位置，
  並在事件紀錄中寫入原始失敗原因與暫存路徑。
- 底部事件紀錄可依層級篩選；展開時事件內容欄會使用剩餘寬度、
  多行顯示並允許選取文字，方便檢查完整檔案路徑與錯誤訊息。
- App 限制為單一實例，且同時間只允許一個主視窗；主視窗關閉後 App 會結束。
- Xcode 專案使用本機 ad-hoc 簽署，不設定 `DEVELOPMENT_TEAM`。

Portal 原始碼目前依責任分層：

- `Portal/LiveCaptionPortal/ContentView.swift`：主視窗畫面組合、
  App 生命週期事件與字幕 session 協調。
- `Portal/LiveCaptionPortal/Audio/`：音訊來源列舉、麥克風權限、收音控制與音量計算。
- `Portal/LiveCaptionPortal/Speech/`：語音輸入語言、字幕輸出語言、
  Azure Speech 設定與 Speech Translation 控制。
- `Portal/LiveCaptionPortal/Subtitle/`：字幕檔案位置設定、SRT 工作階段輸出與備援暫存。
- `Portal/LiveCaptionPortal/Relay/`：Portal 端 Relay URL、會議室名稱、軌道、
  連線測試與字幕事件發佈請求組裝。
- `Portal/LiveCaptionPortal/Logging/`：Portal 事件紀錄資料模型與時間格式。
- `Portal/LiveCaptionPortal/UI/`：Header、側欄、字幕預覽、Speech 與 Relay 設定 sheet、
  Log drawer 與共用 SwiftUI 元件。
- `Portal/LiveCaptionPortal/L10n.swift` 與 `Portal/LiveCaptionPortal/*.lproj/`：
  App 介面在地化查表與 `zh-TW`、`en-US` 文字資源。

### Portal 快速建置

Portal 使用 CocoaPods 管理 Azure Speech SDK。
初次建置或 Podfile 更新後，先安裝 Ruby gem 並更新 Pods：

```sh
cd Portal
bundle install
bundle exec pod install
```

之後請使用 CocoaPods 產生的 workspace 開啟或建置 Portal。

```sh
cd Portal
xcodebuild -scheme LiveCaptionPortal \
  -workspace LiveCaptionPortal.xcworkspace \
  -destination platform=macOS \
  -derivedDataPath /tmp/LiveCaptionDerivedData \
  build
```

建置後可從以下路徑開啟本機 Debug App：

```sh
open /tmp/LiveCaptionDerivedData/Build/Products/Debug/LiveCaptionPortal.app
```

### Relay

Relay 是後端服務。它會接收來自 Portal 的字幕事件，驗證事件格式與請求簽章，並透過 Azure Web PubSub publisher adapter 發布字幕。

- [字幕事件 API](docs/api/caption-events.md)
- [Relay Azure Functions 設定](docs/deployment/relay-functions.md)

## 部署與雲端資源

- [Azure Speech 資源設定](docs/deployment/azure-speech.md)
- [Relay Azure Functions 設定](docs/deployment/relay-functions.md)
