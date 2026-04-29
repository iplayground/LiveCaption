# Azure Speech 資源設定

本文記錄 LiveCaption 建立 Azure Speech 資源的通用流程與 Portal App 的 Speech 設定方式。

開發期先使用 `F0` 免費層。活動或正式測試前，若免費額度、併發或節流限制不足，再升級為 `S0`。

## 建立流程

先確認目前 Azure CLI 使用的 subscription：

```sh
az account show
```

確認 resource group 存在：

```sh
az group show --name <resource-group>
```

確認 resource group 內是否已有 Cognitive Services 或 Speech 資源，避免重複建立：

```sh
az cognitiveservices account list \
  --resource-group <resource-group> \
  --output table
```

確認目標 region 可用的 Speech SKU：

```sh
az cognitiveservices account list-skus \
  --kind SpeechServices \
  --location <speech-region> \
  --output table
```

常見可用 SKU 包含：

- `F0`：Free
- `S0`：Standard

建立 Speech 資源：

```sh
az cognitiveservices account create \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --location <speech-region> \
  --kind SpeechServices \
  --sku F0 \
  --yes
```

建立後確認資源狀態與 endpoint：

```sh
az cognitiveservices account show \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --query "{name:name,kind:kind,location:location,sku:sku.name,endpoint:properties.endpoint,provisioningState:properties.provisioningState}" \
  --output json
```

預期 `provisioningState` 為 `Succeeded`。

## 升級計費方案

活動前若需要從 `F0` 升級為 `S0`：

```sh
az cognitiveservices account update \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --sku S0
```

升級後再次確認：

```sh
az cognitiveservices account show \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --query "{name:name,sku:sku.name,provisioningState:properties.provisioningState}" \
  --output json
```

## Token 測試

若要測試 Speech authorization token，需先取得其中一組 key。key 不得提交到儲存庫，也不得寫入文件。

取得 key 時只在本機終端使用：

```sh
az cognitiveservices account keys list \
  --name <speech-resource-name> \
  --resource-group <resource-group>
```

用 key 向 Speech STS endpoint 換取短效 token：

```sh
curl -X POST \
  "https://<speech-region>.api.cognitive.microsoft.com/sts/v1.0/issueToken" \
  -H "Ocp-Apim-Subscription-Key: <speech-key>" \
  -H "Content-Length: 0"
```

成功時 response body 會是一段短效 token。這個指令只用來驗證 Azure Speech key 與 region 是否可用；Portal 目前不採用 token endpoint 模式。

## 本機設定

Portal 串接 Speech SDK 時，App 使用自己的 `UserDefaults` 保存下列值：

- `speech.region`：Azure Speech region，例如 `japaneast`。
- `speech.key`：Azure Speech key，只保存在本機。
- `speech.outputLanguageIDs`：字幕輸出語言清單。
- `speech.authorizationStatus`：上次 Speech 授權測試狀態。
- `subtitleFileSettings.storageDirectoryBookmark`：使用者選取的字幕檔案輸出根目錄 security-scoped bookmark。

`speech.key` 是機密，不得提交、不得寫入文件，也不得輸出到事件紀錄。

Portal 的 App 介面在地化支援 `zh-TW` 與 `en-US`。Swift UI、錯誤訊息與事件紀錄標題透過 `Portal/LiveCaptionPortal/L10n.swift` 讀取 `Localizable.strings`；`InfoPlist.strings` 目前保存 App 名稱與麥克風權限說明。這套 App 介面在地化設定應和語音輸入語言、字幕輸出語言保持分離。

主控板的字幕區會把目前語音語言視為即時字幕語言，並從預覽列表排除相同語言。例如語音語言為國語時，即時區顯示繁體中文，預覽區只顯示其他已選字幕輸出語言；語音語言為英語時，預覽區不再顯示英文。台灣繁體中文與英文是必要字幕輸出語言，日文與韓文可在 Speech 設定中切換。

Portal 使用 Azure Speech Translation 同一條流程取得來源語音辨識文字與目標語言翻譯文字。開啟收音只會啟動主控板選定音訊來源與音量監測；使用者點擊「開始字幕」後，Portal 才會使用同一個選定音訊來源建立 Azure Speech Translation recognizer。若沒有選定音訊來源，Speech Translation 不會 fallback 到系統預設麥克風。即時區會顯示來源語音的中間與最終辨識文字；預覽區只顯示目標語言的最終翻譯文字，避免中間翻譯反覆修正造成字幕跳動。Relay 發布仍待後續整合。

App 開啟後，字幕區會依各字幕框語言顯示歡迎文字。使用者點擊「開始字幕」後，Portal 會先清空歡迎文字；在 Speech Translation 回傳最終結果前，目標語言字幕框維持空白。使用者點擊「停止字幕」時，Portal 會保留字幕預覽中最後顯示的辨識與翻譯文字以及字幕事件計數，避免操作停止時清空現場畫面。

「開始字幕」左側的計時器只供使用者觀察目前工作階段經過時間；停止字幕時不會重置，下一次開始字幕時才會從 0 重新計算。SRT 輸出不使用此 UI 計時器，而是使用 Speech SDK 最終辨識結果回傳的 `offset` 與 `duration` 產生時間碼，並以本次工作階段第一筆字幕事件的 `offset` 作為相對基準。

Portal 會在使用者點擊「停止字幕」或工作階段被結束時輸出 SRT。輸出根目錄由主控板「字幕檔案」區塊設定，Portal 會保存該資料夾的 security-scoped bookmark，並在工作階段區塊顯示檔案權限狀態。開始字幕前必須已開啟收音、Speech 授權測試狀態為 `已授權`，且字幕檔案位置可存取。

SRT 輸出資料夾使用字幕工作階段開始時間命名，格式為 `MMdd_HHmm`。若字幕預覽中央區有輸入工作階段標題，資料夾名稱會加上空格與清理後的標題；檔名依字幕輸出語言代碼命名，例如：

- `zh-Hant.srt`
- `en.srt`
- `ja.srt`
- `ko.srt`

若使用者設定的字幕檔案位置寫入失敗，Portal 會改將 SRT 暫存到 App 可存取的 Application Support 備援位置 `LiveCaptionPortal/SRT Recovery/` 下，並在事件紀錄中寫入原始失敗原因與暫存路徑。若本次工作階段沒有 Speech SDK 最終字幕事件，Portal 不會產生空的 SRT 檔，事件紀錄會顯示本次沒有可輸出的字幕事件。

主控板的工作階段狀態代表字幕 session 生命週期，並和「開始字幕」按鈕條件聯動：

- `尚未開始`：尚未開始字幕，或目前缺少可開始條件。
- `準備就緒`：已開啟收音、Speech 已授權，且字幕檔案位置可存取；「開始字幕」可使用。
- `字幕中`：字幕 session 已開始，Speech Translation 會接收音訊並產生字幕事件。
- `正在停止`：正在結束字幕 session 並準備輸出 SRT；目前流程多為短暫狀態。
- `已完成`：字幕 session 已結束，SRT 輸出成功，或本次沒有可輸出的字幕事件。
- `完成但有警告`：主要字幕檔案位置寫入失敗，但已成功寫入 fallback recovery 位置。
- `結束失敗`：字幕 session 建立或結束輸出失敗，且 fallback recovery 也未成功。

字幕預覽旁的狀態標籤代表 Speech Translation 狀態：

- `等待語音`：Speech Translation recognizer 尚未啟動或已停止。
- `聆聽中`：Speech Translation recognizer 已啟動，正在等待可辨識語音。
- `辨識中`：Speech Translation recognizer 已收到來源語音的中間辨識結果。
- `辨識失敗`：Speech Translation recognizer 回報取消或錯誤。

Portal 主控板的工作階段區塊有一列標示為 `Speech`，該列會依 `speech.authorizationStatus` 顯示 Azure Speech 授權測試狀態：

- `未授權`：沒有 Speech key。
- `未驗證`：有 Speech key，但尚未通過連線測試。
- `驗證中`：App 啟動時，上次狀態為已授權，正在重新測試 Azure Speech。
- `已授權`：最近一次連線測試成功。
- `授權失敗`：最近一次連線測試失敗。

若 App 啟動時上次狀態為 `已授權`，Portal 會自動重新測試 Speech key 與 region，測試期間顯示 `驗證中`。若上次狀態為 `授權失敗`、`未驗證` 或 `未授權`，Portal 不會自動重測。

## 安全注意事項

- 不得提交 Speech key、authorization token、`.env` 真值或任何包含機密的本機設定。
- 日誌不得記錄完整逐字稿、音訊內容、Speech key 或 authorization token。
- 事件紀錄可以記錄 SRT 輸出資料夾、輸出檔案路徑、檔案權限狀態與寫檔錯誤原因，但不得記錄完整字幕內容。
- Portal 直接使用本機保存的 Speech key。若部署情境改變，需重新檢視用戶端憑證暴露風險。
- 若後續改由後端提供短效 token，Portal 應重新設計設定項與憑證保存方式，不沿用目前的本機 Speech key 流程。
