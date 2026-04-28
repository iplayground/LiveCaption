# LiveCaption

LiveCaption 是一套用於現場活動的即時語音辨識與翻譯系統。

## 目前狀態

目前專案已建立 Portal macOS App 的主畫面，用來確認現場操作台的資訊架構與逐步接上本機功能。Relay 後端仍維持為後續整合目標。

## 元件

### Portal

Portal 是 macOS 操作端 App。它會擷取音訊、執行語音辨識與翻譯，並將字幕事件傳送至 Relay。

目前 Portal 的狀態：

- 需求系統為 macOS 26。
- App 介面在地化目前支援 `zh-TW` 與 `en-US`，預設開發語言為 `zh-TW`。
- 語音輸入語言支援國語與英語。
- 字幕輸出固定為台灣繁體中文、日文與英文三種語言。
- 主畫面包含工作階段、音訊輸入、字幕預覽、Speech 設定、Relay 設定、最近狀態與底部可展開事件紀錄。
- 工作階段區塊會以醒目狀態顯示目前工作階段、收音、Speech 授權與字幕事件計數；字幕事件計數目前會統計來源語音辨識產生的最終結果。
- 音訊輸入區塊可列出本機音訊輸入裝置（包含 3.5mm 外部輸入等來源）、在尚未有使用者選取時預設選取 macOS 目前預設音訊輸入、隱藏系統標示為虛擬的音訊裝置、保存使用者選取來源，並透過開關控制是否收音。
- 開啟收音時，Portal 會先檢查麥克風權限；若沒有權限，收音開關會回到關閉狀態並提示使用者是否前往系統設定，不會直接開啟系統設定。
- 音訊輸入區塊會顯示麥克風權限狀態，並以可切換自動校準的即時音量表呈現輸入音量；音量條會平滑回落，peak indicator 會以較快速度回落。
- 已授權 Speech 設定並開啟收音後，點擊「開始字幕」才會以主控板選定的音訊來源啟動來源語音辨識；即時區顯示目前語音語言的中間與最終辨識文字。
- 字幕預覽會排除與即時語音相同的語言；即時區顯示目前語音語言，預覽區只顯示其他字幕輸出語言。翻譯字幕與 Relay 發布仍待後續整合。
- App 限制為單一實例，且同時間只允許一個主視窗；主視窗關閉後 App 會結束。
- Xcode 專案使用本機 ad-hoc 簽署，不設定 `DEVELOPMENT_TEAM`。

### Portal 快速建置

Portal 使用 CocoaPods 管理 Azure Speech SDK。初次建置或 Podfile 更新後，先安裝 Ruby gem 並更新 Pods：

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

Relay 是後端服務。它會接收來自 Portal 的字幕事件，並透過 Azure Web PubSub 發布。

## 部署與雲端資源

- [Azure Speech 資源設定](docs/deployment/azure-speech.md)
