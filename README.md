# LiveCaption

[![Portal](https://github.com/iplayground/LiveCaption/actions/workflows/portal-build.yml/badge.svg?branch=main)](https://github.com/iplayground/LiveCaption/actions/workflows/portal-build.yml)
[![Relay Deploy](https://github.com/iplayground/LiveCaption/actions/workflows/deploy-relay-functions.yml/badge.svg?branch=main)](https://github.com/iplayground/LiveCaption/actions/workflows/deploy-relay-functions.yml)

LiveCaption 是一套用於現場活動的即時語音辨識與翻譯系統。

## 元件

- `Portal/`：macOS 操作端 App，負責擷取現場音訊、執行語音辨識與翻譯、產生字幕事件，並送往 Relay。
- `Relay/`：Python Azure Functions 後端，負責驗證 Portal 請求、整理字幕事件，並透過 Azure Web PubSub 發布給觀眾端。

目前 Portal 可產生字幕事件並送往 Relay；Relay 可驗證 Portal 請求、發布字幕到 Azure Web PubSub，並提供觀眾端取得短效 Web PubSub 連線 URL 的 negotiate API。觀眾端 WebSocket 可接收字幕與控制事件，字幕模式與語言由 Viewer 本機自行過濾。

## CI/CD 狀態

- `Portal`：驗證 Portal macOS App 是否能在 GitHub Actions 上編譯成功；只在 push 或 PR 到 `main` 且 Portal 程式碼或 workflow 變更時執行。
- `Relay Deploy`：部署 Relay Azure Function App，並以健康檢查確認正式 endpoint 已載入目標 commit。

## 快速開始

### Portal

Portal 使用 Swift Package Manager 管理 Azure Speech SDK。專案內的本地 package 會以 binary target 下載 Microsoft 提供的 `MicrosoftCognitiveServicesSpeech.xcframework`。此 package 使用 `swift-tools-version: 6.2` 與 macOS 26 deployment target，建置時需使用支援 SPM 6.2 的 Xcode。

```sh
cd Portal
xcodebuild -scheme LiveCaptionPortal \
  -project LiveCaptionPortal.xcodeproj \
  -destination platform=macOS \
  -derivedDataPath /tmp/LiveCaptionDerivedData \
  build
```

建置後可開啟本機 Debug App：

```sh
open /tmp/LiveCaptionDerivedData/Build/Products/Debug/LiveCaptionPortal.app
```

### Relay

```sh
cd Relay
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt pytest
python -m pytest
```

本機 Azure Functions 設定檔不得提交，請從範例建立：

```sh
cd Relay
cp local.settings.sample.json local.settings.json
func start --port 7071
```

Relay 本機固定使用 port `7071`。

## 文件索引

- [Portal 架構與操作端行為](docs/architecture/portal.md)
- [Relay 架構與資料流](docs/architecture/relay.md)
- [字幕事件 API](docs/api/caption-events.md)
- [觀眾端連線 API](docs/api/viewer-negotiate.md)
- [Relay 健康檢查 API](docs/api/health.md)
- [Azure Speech 資源設定](docs/deployment/azure-speech.md)
- [Relay Azure Functions 部署](docs/deployment/relay-functions.md)
- [Azure SKU 排程操作](docs/operations/azure-sku-schedule.md)
- [ADR](docs/adr/)

## 安全原則

不得提交任何機密、金鑰、連線字串、SAS Token、`local.settings.json`、本機環境檔或建置產物。Relay 與 Portal 的日誌都不得記錄完整逐字稿、音訊內容、權杖、簽章或可識別個人的資料。
