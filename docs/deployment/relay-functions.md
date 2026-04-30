# Relay Azure Functions 設定

本文記錄 Relay 的 Azure Functions 設定方式、本機設定、Azure Web PubSub 基礎設施與目前整合邊界。

Relay 目前以 Python 3.13 Azure Functions 實作，HTTP endpoints 為：

```http
HEAD /api/caption-events
POST /api/caption-events
POST /api/viewer/negotiate
GET /api/health
```

字幕事件 API 契約請見 [字幕事件 API](../api/caption-events.md)。
觀眾端連線 API 契約請見 [觀眾端連線 API](../api/viewer-negotiate.md)。
健康檢查 API 契約請見 [Relay 健康檢查 API](../api/health.md)。

## 目前狀態

已完成：

- Azure Functions Python 專案骨架。
- 字幕事件資料模型。
- 字幕事件 validator。
- HTTP handlers。
- Azure Web PubSub 正式資源與 Relay app settings 的 Bicep 設定。
- Web PubSub 發布 payload builder。
- Azure Web PubSub publisher adapter。
- 觀眾端 receive-only Web PubSub negotiate endpoint。
- 正式 Azure Functions 與 Azure Web PubSub 基礎設施部署。
- 正式 Azure Functions 已套用 Flex Consumption `RollingUpdate` site update strategy。
- GitHub Actions 部署後健康檢查與失敗時自動 rollback。
- pytest 測試。

尚未完成：

- 觀眾端 App Web PubSub 連線與字幕顯示介面。

目前 Relay 程式可接收 Portal 字幕事件並發布到 Web PubSub group；Portal 可用 `HEAD /api/caption-events` 測試 Relay 並取得觀眾端 access code。當 `VIEWER_ACCESS_CODE_REQUIRED=true` 時，觀眾端 App 需帶 access code 呼叫 Relay negotiate endpoint，取得 receive-only client access URL，再直接連線 Azure Web PubSub 接收字幕。

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
| `VIEWER_ACCESS_CODE_REQUIRED` | 否 | 控制 `POST /api/viewer/negotiate` 是否必須帶 `X-LiveCaption-Viewer-Access-Code`。預設與無效值都視為 `true`；切到 Web PubSub Free tier 時應為 `true`，切到付費層且不需要限制 negotiate 時可設為 `false`。 |

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

## 觀眾端 access code 開關

Relay 不在 `POST /api/viewer/negotiate` runtime 查詢 Azure Web PubSub SKU。是否要求
觀眾端 access code 由 `VIEWER_ACCESS_CODE_REQUIRED` 控制：

- `true`：必須帶 `X-LiveCaption-Viewer-Access-Code`，適合 Web PubSub Free tier 或需要限制 negotiate 的環境。
- `false`：不驗證 access code，直接回傳 receive-only Web PubSub client access URL。

這個設定不存在或填入無效值時，Relay 會以 `true` 處理。若未來用 GitHub Actions
排程切換 Web PubSub SKU，應在同一個流程同步更新 Function app setting；例如切到
`Free_F1` 時設為 `true`，切到 `Standard_S1` 或 `Premium_P1` 且不需限制 negotiate
時設為 `false`。更新 Function app setting 可能會觸發 Function App restart，應在
workflow 後段執行健康檢查或 negotiate smoke test。

## 本機啟動

安裝 Azure Functions Core Tools 後：

本專案本機驗證 Relay Functions 固定使用 port `7071`：

```sh
cd Relay
func start --port 7071
```

本機 endpoint：

```text
HEAD http://localhost:7071/api/caption-events
POST http://localhost:7071/api/caption-events
POST http://localhost:7071/api/viewer/negotiate
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

## 目前 Azure 需要套用的更新

目前工作區新增了 Relay 觀眾端 negotiate、`HEAD /api/caption-events` access code
回傳，以及 `VIEWER_ACCESS_CODE_REQUIRED` 行為開關。這些變更在 Azure 生效需要：

1. 重新部署 Relay Function App 程式碼。
2. 重新套用 `Relay/infra/main.bicep`，讓 Function App app settings 包含 `VIEWER_ACCESS_CODE_REQUIRED`。

`viewerAccessCodeRequired` 參數預設為 `true`，因此未特別調整時，正式環境會要求
`POST /api/viewer/negotiate` 帶 `X-LiveCaption-Viewer-Access-Code`。若後續排程將
Azure Web PubSub 切到付費層且不需限制 negotiate，可在同一個流程把 Function App
app setting 更新為 `VIEWER_ACCESS_CODE_REQUIRED=false`。

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
送出的 HMAC 簽章與衍生觀眾端 access code；Relay 也使用 Managed Identity 呼叫
Web PubSub data-plane publish API 與產生觀眾端 receive-only client access URL。
正式環境不應在 App Settings、參數檔或 repo 中保存 Speech key 或 Web PubSub
connection string 真值。

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

push 觸發時，GitHub Actions 會以 workflow 的 `paths` 篩選判斷是否需要自動部署；
手動執行 `workflow_dispatch` 時則直接登入 Azure 並上傳 Functions 程式碼。

正式 Function App 採用 Flex Consumption `RollingUpdate` site update strategy，
降低部署時因預設 `Recreate` 策略一次重啟全部執行個體造成的中斷風險。此功能目前
仍屬 Azure preview；它不是 rollback 機制，也無法保證有 runtime bug 的新版本在
替換完成後不影響正式服務。

`RollingUpdate` 是 Azure Function App 的站台設定，需先透過
`az deployment group create` 套用 `Relay/infra/main.bicep` 後才會在 Azure 生效。
只修改 workflow 或只部署程式碼不會改變既有 Function App 的 site update strategy。

每次 workflow 部署前會在部署包寫入 `build-info.json`，內容包含該次 commit SHA。
Relay 提供不需授權的 `GET /api/health`，回傳 `status` 與部署包內的 commit SHA。
部署完成後，workflow 會輪詢健康檢查，直到確認正式 endpoint 回傳目前 commit SHA。
健康檢查通過後，workflow 才會建立 `livecaption-relay-production` GitHub deployment
success 紀錄。此紀錄代表上一個已知健康部署版本，供後續自動 rollback 選擇 ref。

若健康檢查未通過，workflow 會重新部署 rollback ref，優先順序如下：

1. 上一個 `livecaption-relay-production` GitHub deployment success 紀錄的 commit SHA。
2. 手動執行時填入的 `rollback_ref` input。
3. push 觸發時 GitHub push event 的 `before` SHA。

rollback 會重新 checkout rollback ref，並再次透過 `Azure/functions-action@v1`
上傳該版本。GitHub Deployments 只用來記錄健康版本與選擇 rollback ref；它不保存
部署包，也不提供 Azure 原生 rollback。

手動執行 `workflow_dispatch` 不會做額外 diff 判斷；操作者需自行確認是否需要
重新上傳 Relay。

workflow 使用單一 job：

- `deploy`：驗證 Relay 程式碼，使用 GitHub OIDC 登入 Azure，並上傳 Azure
  Functions 程式碼。

執行順序：

1. checkout repo。
2. 設定 Python 3.13。
3. 安裝 `Relay/requirements.txt`。
4. 執行 `compileall` 檢查 Python 語法。
5. 直接 import `function_app` 確認應用可載入。
6. 寫入 `build-info.json`。
7. 使用 GitHub OIDC 登入 Azure。
8. 透過 `Azure/functions-action@v1` 以 `remote-build: true` 部署 `Relay/`。
9. 輪詢 `GET /api/health`，確認 endpoint 回傳目前 commit SHA。
10. 健康檢查通過後，建立 GitHub deployment success 紀錄。
11. 若健康檢查失敗且可取得 rollback ref，重新部署 rollback ref。

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

程式碼部署成功後，Portal 發出的字幕事件會由 Relay 發布到 Web PubSub 的
`livecaption` hub 與 `caption-live` group。Azure Web PubSub 不保存字幕內容歷史，
Azure Portal 只能觀察連線數、訊息數與服務狀態；若要看到字幕 payload，需使用
觀眾端或測試 client 透過 `POST /api/viewer/negotiate` 取得短效 URL 後連上。
當 `VIEWER_ACCESS_CODE_REQUIRED=true` 時，negotiate request 必須在
`X-LiveCaption-Viewer-Access-Code` header 帶入 Portal 顯示的 access code。

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
- `VIEWER_ACCESS_CODE_REQUIRED`

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
