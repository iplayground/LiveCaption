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

`speech.key` 是機密，不得提交、不得寫入文件，也不得輸出到事件紀錄。

主控板的字幕區會把目前語音語言視為即時字幕語言，並從預覽列表排除相同語言。例如語音語言為國語時，即時區顯示繁體中文，預覽區只顯示其他已選字幕輸出語言；語音語言為英語時，預覽區不再顯示英文。

Portal 的主控板會依 `speech.authorizationStatus` 顯示 Speech 授權狀態：

- `未授權`：沒有 Speech key。
- `未驗證`：有 Speech key，但尚未通過連線測試。
- `驗證中`：App 啟動時，上次狀態為已授權，正在重新測試 Azure Speech。
- `已授權`：最近一次連線測試成功。
- `授權失敗`：最近一次連線測試失敗。

若 App 啟動時上次狀態為 `已授權`，Portal 會自動重新測試 Speech key 與 region，測試期間顯示 `驗證中`。若上次狀態為 `授權失敗`、`未驗證` 或 `未授權`，Portal 不會自動重測。

## 安全注意事項

- 不得提交 Speech key、authorization token、`.env` 真值或任何包含機密的本機設定。
- 日誌不得記錄完整逐字稿、音訊內容、Speech key 或 authorization token。
- Portal 直接使用本機保存的 Speech key。若部署情境改變，需重新檢視用戶端憑證暴露風險。
- 若後續改由後端提供短效 token，Portal 應重新設計設定項與憑證保存方式，不沿用目前的本機 Speech key 流程。
