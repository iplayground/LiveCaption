# LiveCaption

LiveCaption 是一套用於現場活動的即時語音辨識與翻譯系統。

## 目前狀態

目前專案已建立 Portal macOS App 的靜態主畫面，用來確認現場操作台的資訊架構與視覺配置。Relay 後端仍維持為後續整合目標。

## 元件

### Portal

Portal 是 macOS 操作端 App。它會擷取音訊、執行語音辨識與翻譯，並將字幕事件傳送至 Relay。

目前 Portal 的狀態：

- 需求系統為 macOS 26。
- App 介面在地化目前支援 `zh-TW` 與 `en-US`，預設開發語言為 `zh-TW`。
- 語音輸入語言支援國語與英語。
- 字幕輸出固定為台灣繁體中文、日文與英文三種語言。
- 主畫面包含工作階段、音訊輸入、字幕預覽、Speech 設定、Relay 設定、最近狀態與底部可展開事件紀錄。
- App 限制為單一實例，且同時間只允許一個主視窗；主視窗關閉後 App 會結束。
- Xcode 專案使用本機 ad-hoc 簽署，不設定 `DEVELOPMENT_TEAM`。

### Portal 快速建置

```sh
xcodebuild -scheme LiveCaptionPortal \
  -project Portal/LiveCaptionPortal.xcodeproj \
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
