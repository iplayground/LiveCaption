# Azure Speech 資源設定

本文記錄 LiveCaption 建立 Azure Speech 資源的通用流程與開發期設定注意事項。

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

成功時 response body 會是一段短效 token。token 有效時間有限，Portal 實作時需要在過期前更新 token。

## 本機設定

Portal 串接 Speech SDK 時，開發期可使用未提交的本機設定保存下列值：

```sh
SPEECH_REGION=<speech-region>
SPEECH_ENDPOINT=https://<speech-region>.api.cognitive.microsoft.com/
SPEECH_KEY=<local-only-secret>
```

`SPEECH_KEY` 是機密，不得提交。若需要提交範例檔，只能使用空值或明顯假的 placeholder。

## 安全注意事項

- 不得提交 Speech key、authorization token、`.env` 真值或任何包含機密的本機設定。
- 日誌不得記錄完整逐字稿、音訊內容、Speech key 或 authorization token。
- Portal 初期可直接使用本機 key 進行開發；正式活動前應重新檢視用戶端憑證暴露風險。
- 若後續改由後端提供短效 token，Portal 應只保存 token endpoint 所需的最小設定。
