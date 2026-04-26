# LiveCaption

LiveCaption 是一套用於現場活動的即時語音辨識與翻譯系統。

## 元件

### Portal

Portal 是 macOS 操作端 App。它會擷取音訊、執行語音辨識與翻譯，並將字幕事件傳送至 Relay。

### Relay

Relay 是後端服務。它會接收來自 Portal 的字幕事件，並透過 Azure Web PubSub 發布。
