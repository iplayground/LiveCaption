# Relay Azure Functions 設定

本文記錄 Relay 的 Azure Functions 設定方式、本機設定、Azure Web PubSub 基礎設施與目前尚未完成的整合邊界。

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
- Azure Web PubSub 正式資源與 Relay app settings 的 Bicep 設定。
- Web PubSub 發布 payload builder。
- 正式 Azure Functions 與 Azure Web PubSub 基礎設施部署。
- pytest 測試。

尚未完成：

- Azure Web PubSub publisher adapter。
- 觀眾端 Web PubSub 連線或 negotiate endpoint。

在 publisher adapter 完成前，Relay 可用來驗證事件接收與授權，但不會實際發布字幕到觀眾端。

## 必要 App Settings

Azure Functions 需要下列設定：

| 名稱 | 必填 | 說明 |
| --- | --- | --- |
| `FUNCTIONS_WORKER_RUNTIME` | 本機是，正式否 | 本機 `local.settings.json` 固定為 `python`。Azure Functions Flex Consumption 正式環境不得設定此 app setting，runtime 由 Bicep 的 `functionAppConfig.runtime` 指定。 |
| `AzureWebJobsStorage` | 是 | Azure Functions runtime 使用的 Storage 設定。本機可使用 Azurite 的 `UseDevelopmentStorage=true`；正式環境由 Bicep 設定 managed identity 型 app settings，例如 `AzureWebJobsStorage__accountName` 與各 service URI，不得提交真值。 |
| `AzureWebJobsDisableHomepage` | 正式是 | 正式環境固定為 `true`，避免 Function App 根路徑顯示 Azure Functions 預設首頁。 |
| `AZURE_SPEECH_ACCOUNT_ID` | 是 | Azure Speech resource 的 ARM resource id。正式環境由 Bicep 產生，Relay 依此定位 Azure Speech resource 並讀取實際 Speech key。 |
| `AZURE_WEBPUBSUB_ENDPOINT` | 是 | Azure Web PubSub endpoint，例如 `https://<name>.webpubsub.azure.com`。正式環境由 Bicep 產生，不應使用 connection string。 |
| `AZURE_WEBPUBSUB_HUB_NAME` | 是 | Relay 發布字幕使用的 Web PubSub hub，第一版預設為 `livecaption`。 |
| `AZURE_WEBPUBSUB_GROUP_NAME` | 是 | Relay 發布字幕使用的 Web PubSub group，第一版固定為 `caption-live`。 |

## 本機設定

本機開發使用 `Relay/local.settings.json`，該檔案不得提交。請從範例複製：

```sh
cd Relay
cp local.settings.sample.json local.settings.json
```

`Relay/local.settings.sample.json` 只能放不含真實機密的範例值。本機
`local.settings.json` 只應保存 Azure Speech resource 定位資訊，不應保存 Speech
key 真值。Web PubSub 本機設定只保存 endpoint、hub name 與 group name，不應保存
Web PubSub connection string 或 SAS token。若需要使用 Azure Storage connection string，
只能放在未提交的 `local.settings.json` 或本機 shell 環境。

正式 Azure Functions 不設定 `AZURE_SUBSCRIPTION_ID` 與
`AZURE_SPEECH_RESOURCE_GROUP`。Relay 只使用 Bicep 寫入的
`AZURE_SPEECH_ACCOUNT_ID` 定位 Azure Speech resource，避免依賴 Azure Functions
runtime 是否提供 subscription 或 resource group 環境變數。

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

## 正式部署檔案

Relay Functions 只規劃單一正式環境，不建立 staging、test slot 或第二套測試用
Function App。部署相關檔案放在 `Relay/infra/`：

部署檔案：

- `main.bicep`：建立正式 Relay Function App、Storage Account、
  Log Analytics、Application Insights、Managed Identity 與必要 RBAC。
  同時建立 GitHub Actions OIDC 部署用的 user-assigned Managed Identity、
  federated credential 與 Function App 範圍的 Website Contributor 權限。
- `speech-role-assignment.bicep`：在既有 Azure Speech resource 上指派
  Relay Managed Identity 讀取 Speech key 所需權限。
- `prod.example.bicepparam`：正式部署參數範例，只能放非機密範例值。
  實際 `prod.bicepparam` 不應提交。

部署包排除規則放在 `Relay/.funcignore`，正式發布時不得包含：

- `local.settings.json`
- Python virtual environment
- pytest 與其他本機快取
- 測試檔
- `Relay/infra/` 部署檔

`az bicep build` 產生的 JSON 是本機衍生檔，不應提交。

## 正式 Azure 資源

`Relay/infra/main.bicep` 會建立下列資源；目前已部署到 `iplayground` resource group：

- Azure Functions Flex Consumption Function App，Python 3.13。
- Storage Account，供 Functions host 與部署 package 使用。
- Log Analytics Workspace。
- Application Insights。
- Azure Web PubSub，預設以 `Free_F1` 建立，活動前可升級為 `Standard_S1`。
- System-assigned Managed Identity。
- Storage Blob、Queue、Table 與 Application Insights 所需 RBAC。
- Web PubSub resource 範圍的 `Web PubSub Service Owner` 角色指派，供 Relay 使用
  Managed Identity 呼叫 data-plane publish API。
- 既有 Azure Speech resource 上的 `Cognitive Services User` 角色指派。
- GitHub Actions 專用 user-assigned Managed Identity。
- 綁定到 `iplayground/LiveCaption` 的 `main` 分支 federated credential。

Relay 使用 Managed Identity 向 Azure 讀取 Speech key，並以該 key 驗證 Portal
送出的 HMAC 簽章。正式環境不應在 App Settings、參數檔或 repo 中保存 Speech
key 真值。

目前 Web PubSub 現況：

- Resource name：`<web-pubsub-name>`
- Region：`japaneast`
- SKU：`Free_F1`
- Unit count：`1`
- Endpoint：`https://<web-pubsub-name>.webpubsub.azure.com`
- Hub：`livecaption`
- Group：`caption-live`
- Relay Managed Identity 已在此 Web PubSub resource 範圍取得 `Web PubSub Service Owner`。
- Web PubSub local auth 已關閉，Relay 後續應使用 Managed Identity，不使用 connection string。

## 正式基礎設施部署

以下命令是正式基礎設施部署流程範例；執行後會建立或修改 Azure 資源。
部署前需確認目前 commit、參數值與 Azure subscription 都正確。

先從 repo root 複製正式參數範例，並確認資源名稱：

```sh
cp Relay/infra/prod.example.bicepparam Relay/infra/prod.bicepparam
```

部署正式 Azure 資源：

```sh
az deployment group create \
  --resource-group iplayground \
  --template-file Relay/infra/main.bicep \
  --parameters Relay/infra/prod.bicepparam
```

基礎設施部署完成後，若 GitHub Actions secrets 尚未設定，需把 Bicep outputs 寫入 GitHub Actions secrets：

- `AZURE_CLIENT_ID`
  說明：Bicep output `githubActionsIdentityClientId`
- `AZURE_TENANT_ID`
  說明：Bicep output `tenantId`
- `AZURE_SUBSCRIPTION_ID`
  說明：Bicep output `subscriptionId`
- `AZURE_FUNCTIONAPP_NAME`
  說明：Bicep output `functionAppName`

若已完成 `gh auth login`，可用 GitHub CLI 設定：

```sh
gh secret set AZURE_CLIENT_ID --body "<github-actions-identity-client-id>" -R iplayground/LiveCaption
gh secret set AZURE_TENANT_ID --body "<azure-tenant-id>" -R iplayground/LiveCaption
gh secret set AZURE_SUBSCRIPTION_ID --body "<azure-subscription-id>" -R iplayground/LiveCaption
gh secret set AZURE_FUNCTIONAPP_NAME --body "<function-app-name>" -R iplayground/LiveCaption
```

## GitHub Actions 程式碼部署

Relay 程式碼部署使用 `.github/workflows/deploy-relay-functions.yml`。workflow
只負責部署既有 Function App 的程式碼，不在每次 push 時重跑 Bicep。

Azure Portal 的 GitHub 來源綁定是必要手動步驟，而且只能手動完成。Bicep 只負責
建立 GitHub Actions OIDC 登入 Azure 所需的 Managed Identity、federated
credential 與 Function App 部署權限，不會替 Azure Portal 完成 GitHub OAuth
授權或部署中心來源綁定。

在基礎設施已建立、GitHub OAuth 可用後，於 Azure Portal 內完成以下設定：

1. 開啟正式 Relay Function App 的 `部署中心`。
2. `來源` 選擇 `GitHub`。
3. 在 `登入身分` 完成 GitHub OAuth 授權。
4. 選擇對應的 GitHub `組織`、`存放庫` 與 `分支`。
5. `工作流程選項` 選擇 `使用可用的工作流程`。
6. 按下 `儲存`，完成 Azure Portal 的 GitHub 來源綁定。

Azure Portal 在選擇 `使用可用的工作流程` 後，可能不會顯示或預覽實際使用的
workflow yml。因此到此只能假定部署中心已正確綁定 repo 內既有 workflow；實際
是否採用 `.github/workflows/deploy-relay-functions.yml`，需以 GitHub Actions
後續執行結果確認。

不得讓 Azure Portal 產生新的 workflow，也不得另外使用 publish profile 或長效
Service Principal secret 建立第二套部署路徑。

觸發條件：

- push 到 `main`，且變更包含 `Relay/**` 或 workflow 本身。
- 手動執行 `workflow_dispatch`。

workflow 觸發後，會先找出上一個成功 Azure 上傳所建立的 GitHub deployment
紀錄，並比對該 deployment commit 到目前 HEAD 的檔案差異。只要差異中包含
任何 `Relay/` 底下的檔案，就會登入 Azure 並上傳 Functions 程式碼。

若同一次 push 同時包含 `Relay/` 與 `Portal/`、`docs/`、根目錄文件或 workflow
本身的變更，仍會部署 Relay。若從上一個成功 Azure 上傳到目前 HEAD 完全沒有
`Relay/` 變更，才會略過 Azure 上傳。

若找不到上一個成功 Azure 上傳紀錄，workflow 會視為需要重新建立部署基準並允許
Azure 上傳。若該紀錄指向的 commit 不在目前 checkout，workflow 會先嘗試從
origin 以該 commit SHA 抓取；只有遠端也無法取得該 commit 時，才會直接允許
Azure 上傳。
Azure 上傳成功後，workflow 會在 GitHub 建立 `livecaption-relay-production`
deployment success 紀錄，作為下次 diff 比對的基準。若 workflow 因沒有 `Relay/`
差異而略過 Azure 上傳，不會建立新的 deployment 紀錄，也不會改變下次比對基準。

workflow 拆成兩個 job：

- `detect-relay-changes`：判斷是否有 `Relay/` 變更，並在 Summary 寫入結果。
- `deploy`：只有 `detect-relay-changes` 判斷需要部署時才執行 Azure 上傳。

若沒有 `Relay/` 變更，`detect-relay-changes` 會成功結束，`deploy` 會顯示為
skipped，不會讓 GitHub Actions 亮紅燈。

執行順序：

1. `detect-relay-changes` checkout repo。
2. 找出上一個成功 Azure 上傳 deployment commit。
3. 檢查從上一個成功 Azure 上傳到目前 HEAD 是否有 `Relay/` 差異。
4. 若需要部署，執行 `deploy` job。
5. 設定 Python 3.12。
6. 安裝 `Relay/requirements.txt`。
7. 執行 `compileall` 檢查 Python 語法。
8. 直接 import `function_app` 確認應用可載入。
9. 使用 GitHub OIDC 登入 Azure。
10. 透過 `Azure/functions-action@v1` 以 `remote-build: true` 部署 `Relay/`。
11. Azure 上傳成功後，建立 GitHub deployment success 紀錄。

workflow 使用的官方 GitHub Actions 需採用 Node.js 24 runtime：

- `actions/checkout@v6`
- `actions/setup-python@v6`
- `actions/github-script@v8`
- `azure/login@v3`
- `Azure/functions-action@v1`

上述版本需要 GitHub Actions runner `v2.327.1` 或更新版本。GitHub-hosted runner
通常會自動維持新版；若改用 self-hosted runner，需先確認 runner 版本。

部署完成後，Portal 的 Relay URL 應設定為：

```text
https://<relay-domain>/api/caption-events
```

正式 Relay Function App 綁定自訂網域：

```text
<relay-domain>
```

DNS 端需設定：

- 自訂網域指向正式 Relay Function App 的預設 hostname。
- Azure 驗證需要的 `asuid` TXT 值應以 Function App 當下的
  `customDomainVerificationId` 為準，不寫入文件。

Flex Consumption Function App 可以透過 `az webapp config hostname add` 綁定
hostname，但 Azure CLI 的 `az webapp config ssl create` 舊路徑不支援 Flex
Consumption。建立 App Service Managed Certificate 時需使用
`Microsoft.Web/sites/certificates` ARM endpoint；建立後再更新
`Microsoft.Web/sites/hostNameBindings`，將 `sslState` 設為 `SniEnabled` 並填入
managed certificate 的 `thumbprint`。

## Azure Web PubSub 設定

Relay 發布字幕到 Azure Web PubSub 時，Portal 不應知道 Web PubSub hub、connection string、SAS token 或 group name。

`Relay/infra/main.bicep` 已建立 Web PubSub resource，並把下列非機密設定寫入
Relay Function App：

- `AZURE_WEBPUBSUB_ENDPOINT`
- `AZURE_WEBPUBSUB_HUB_NAME`
- `AZURE_WEBPUBSUB_GROUP_NAME`

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
