# Azure Speech 資源設定

本文只記錄 Azure Speech resource 的建立、SKU 切換與本機設定原則。Portal 的操作端行為請見 [Portal 架構與操作端行為](../architecture/portal.md)。

開發期優先使用 `F0` 免費層。活動或正式測試前，若免費額度、併發或節流限制不足，再升級為 `S0`。

## 建立資源

確認 Azure CLI subscription：

```sh
az account show
```

確認 resource group 存在：

```sh
az group show --name <resource-group>
```

確認是否已有 Cognitive Services 或 Speech resource，避免重複建立：

```sh
az cognitiveservices account list \
  --resource-group <resource-group> \
  --output table
```

確認目標 region 可用 SKU：

```sh
az cognitiveservices account list-skus \
  --kind SpeechServices \
  --location <speech-region> \
  --output table
```

建立 Speech resource：

```sh
az cognitiveservices account create \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --location <speech-region> \
  --kind SpeechServices \
  --sku F0 \
  --yes
```

確認狀態：

```sh
az cognitiveservices account show \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --query "{name:name,kind:kind,location:location,sku:sku.name,endpoint:properties.endpoint,provisioningState:properties.provisioningState}" \
  --output json
```

預期 `provisioningState` 為 `Succeeded`。

## 升級與降級

活動前若需要升級為 `S0`：

```sh
az cognitiveservices account update \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --sku S0
```

閒置期若要回到免費層：

```sh
az cognitiveservices account update \
  --name <speech-resource-name> \
  --resource-group <resource-group> \
  --sku F0
```

正式環境的 Speech SKU 會和 Azure Web PubSub SKU 由 Azure Automation runbook 同步切換；操作流程請見 [Azure SKU 排程操作](../operations/azure-sku-schedule.md)。

## Token 測試

若要測試 Speech authorization token，需先取得其中一組 key。key 不得提交到儲存庫，也不得寫入文件。

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

執行 token 測試時不得將 terminal output、完整 curl headers、完整 response body 或 token 值貼到 GitHub issue、PR、文件、CI logs 或聊天室。若需要記錄測試結果，只記錄成功/失敗、HTTP 狀態碼與遮蔽後的錯誤摘要。

## Portal 本機設定

Portal 使用 `UserDefaults` 保存短小的 Speech 設定：

| Key | 說明 |
| --- | --- |
| `speech.region` | Azure Speech region，例如 `japaneast`。 |
| `speech.key` | Azure Speech key，只保存在本機。 |
| `speech.outputLanguageIDs` | 字幕輸出語言清單。 |
| `speech.sentenceSilenceTimeoutMilliseconds` | Speech 句子分段靜音時間，範圍 100 ms 到 5000 ms，預設 800 ms。 |
| `speech.authorizationStatus` | 上次 Speech 授權測試狀態。 |

`speech.key` 是機密，不得提交、不得寫入文件，也不得輸出到事件紀錄。若後續改由後端提供短效 token，Portal 應重新設計設定項與憑證保存方式，不沿用目前的本機 Speech key 流程。

辨識詞彙提示不放在 `UserDefaults`。Portal 啟動時會從 Application Support 讀取：

```text
~/Library/Application Support/LiveCaptionPortal/speech-phrase-hints.json
```

若檔案不存在，Portal 使用預設詞彙設定：`shared` 只有 `iPlayground`。使用者透過 Speech 設定中的 GUI 編輯器更新詞彙後，Portal 會把內容寫回同一個 JSON 檔案。

詞彙提示資料以 `phraseHintsByScope` 結構管理，範圍包含：

| Scope | 說明 |
| --- | --- |
| `shared` | 套用所有語音輸入語言。 |
| `zh-TW` | 只套用 `zh-TW` 語音輸入。 |
| `en-US` | 只套用 `en-US` 語音輸入。 |

每次建立 Azure Speech Translation recognizer 時，Portal 會合併 `shared` 與目前語音輸入語言的詞彙，最多 250 筆，並以 `SPXPhraseListGrammar` 加入 recognizer。Phrase list weight 固定為 `2.0`，不提供 GUI 或 `UserDefaults` 設定。詞彙不應寫入 log、字幕事件、Relay request 或文件範例。
