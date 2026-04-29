# Relay Azure Functions 設定

本文記錄 Relay 的 Azure Functions 設定方式、本機設定與目前尚未完成的整合邊界。

Relay 目前以 Python 3.13 Azure Functions 實作，HTTP endpoint 為：

```http
POST /api/caption-events
```

字幕事件 API 契約請見 [字幕事件 API](../api/caption-events.md)。

## 目前狀態

已完成：

- Azure Functions Python 專案骨架。
- 字幕事件資料模型。
- 字幕事件 validator。
- HTTP handler 雛形。
- Web PubSub 發布 payload builder。
- pytest 測試。

尚未完成：

- Azure Web PubSub publisher adapter。
- Azure 資源部署自動化。
- 正式環境 App Settings 與 Managed Identity 綁定。

在 Web PubSub 發布完成前，Relay 不應對外開放作為正式服務。

## 必要 App Settings

Azure Functions 需要下列設定：

| 名稱 | 必填 | 說明 |
| --- | --- | --- |
| `FUNCTIONS_WORKER_RUNTIME` | 是 | 固定為 `python`。 |
| `AzureWebJobsStorage` | 是 | Azure Functions runtime 使用的 Storage 設定。本機可使用 Azurite 的 `UseDevelopmentStorage=true`；正式環境由部署流程設定，不得提交真值。 |
| `AZURE_SUBSCRIPTION_ID` | 是 | Azure Speech resource 所在的 subscription id。 |
| `AZURE_SPEECH_RESOURCE_GROUP` | 是 | Azure Speech resource 所在的 resource group。 |
| `AZURE_SPEECH_ACCOUNT_NAME` | 是 | Azure Speech resource 名稱。Relay 使用此資訊向 Azure 讀取實際 Speech key 並驗證 Portal HMAC 簽章。 |

## 本機設定

本機開發使用 `Relay/local.settings.json`，該檔案不得提交。請從範例複製：

```sh
cd Relay
cp local.settings.sample.json local.settings.json
```

`Relay/local.settings.sample.json` 只能放不含真實機密的範例值。本機 `local.settings.json` 只應保存 Azure Speech resource 定位資訊，不應保存 Speech key 真值。若需要使用 Azure Storage connection string，只能放在未提交的 `local.settings.json` 或本機 shell 環境。

## 本機啟動

安裝 Azure Functions Core Tools 後：

本專案本機驗證 Relay Functions 固定使用 port `7071`：

```sh
cd Relay
func start --port 7071
```

本機 endpoint：

```text
http://localhost:7071/api/caption-events
```

重啟本機 Functions 時，必須先確認目標行程使用的是 port `7071`，只能停止該 port 對應的 `func` 行程，不得關閉其他 `func` 行程。

本機測試可先使用 `pytest` 驗證 validator，不需要啟動 Functions runtime：

```sh
cd Relay
python -m pytest
```

## Azure Web PubSub 設定方向

Relay 後續發布字幕到 Azure Web PubSub 時，Portal 不應知道 Web PubSub hub、connection string、SAS token 或 group name。

第一版發布 group 由 Relay 固定管理：

```text
caption-live
```

正式環境應優先使用 Managed Identity 讓 Relay 存取 Azure Web PubSub。只有 Azure SDK 或服務限制導致無法乾淨使用 Managed Identity 時，才可改用受控的應用程式設定保存短期或可輪替的連線資訊，且必須同步更新本文件與安全風險說明。

## 安全規則

- 不得提交 `local.settings.json`。
- 不得提交 Azure Storage connection string、Web PubSub connection string、SAS token 或 Speech key 真值。
- Relay log 不得包含完整逐字稿、翻譯文字、Speech key、HMAC 簽章、連線字串或可識別個人的資料。
- `roomName` 是可為空字串的顯示資訊；若需記錄，只記錄長度或遮蔽後的值。
- `trackNumber` 是 Relay 判斷字幕軌佔用狀態的主要識別值，可記錄，但必須維持為整數欄位，不得混入其他識別資訊。
