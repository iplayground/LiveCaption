# Relay Azure Functions 部署

本文記錄 Relay 的 Azure Functions 部署方式與正式基礎設施。Relay 架構、資料流與 app settings 請見 [Relay 架構與資料流](../architecture/relay.md)。

## 範圍

Relay 目前以 Python 3.13 Azure Functions 實作，HTTP endpoints 為：

```http
GET /
HEAD /api/caption-events
POST /api/caption-events
POST /api/viewer/negotiate
GET /api/health
```

`GET /` 會重新導向到 LiveCaption GitHub repository。未知 GET path 會回傳 `404` JSON。

本專案只規劃單一正式 Relay Function App，不建立 staging、test slot 或第二套測試用 Function App。

## 本機設定與啟動

`Relay/local.settings.json` 不得提交。請從範例建立：

```sh
cd Relay
cp local.settings.sample.json local.settings.json
```

本機驗證 Relay Functions 固定使用 port `7071`：

```sh
cd Relay
func start --port 7071
```

重啟本機 Functions 時，必須先確認目標行程使用的是 port `7071`，只能停止該 port 對應的 `func` 行程。

本機測試可不啟動 Functions runtime：

```sh
cd Relay
python -m pytest
```

## 正式部署檔案

部署相關檔案放在 `Relay/infra/`：

| 檔案 | 用途 |
| --- | --- |
| `main.bicep` | 建立正式 Relay Function App、Storage、Log Analytics、Application Insights、Managed Identity、Azure Web PubSub、RBAC 與 GitHub Actions OIDC 部署身分。 |
| `speech-role-assignment.bicep` | 在既有 Azure Speech resource 上指派 Relay Managed Identity 讀取 Speech key 所需權限。 |
| `prod.example.bicepparam` | 正式部署參數範例，只能放非機密範例值。 |
| `automation/switch-livecaption-sku.ps1` | Azure SKU 排程切換 runbook。 |

`prod.bicepparam`、Bicep build 產物、`local.settings.json`、virtual environment、pytest 快取、測試檔與部署時不需要的本機檔案都不應包含在 Functions 部署包或提交內容中。

## Azure Tags

正式 Azure 資源應使用 `app=LiveCaption` 標示產品歸屬，並以 `component` 標示資源所屬元件或服務，例如 Relay 相關資源使用 `component=Relay`，既有 Azure Speech resource 使用 `component=Speech`，Azure Automation 排程與 runbook 等維運資源使用 `component=Operations`。

`environment` tag 已廢除，不應再加到新資源或既有資源。若部署或維運時發現 Azure resource 仍有 `environment` tag，應移除該 tag，而不是改成其他 environment 值。

## 正式 Azure 資源

`Relay/infra/main.bicep` 建立或設定：

- Azure Functions Flex Consumption Function App，Python 3.13。
- Storage Account。
- Log Analytics Workspace。
- Application Insights。
- Azure Web PubSub。
- Azure OpenAI resource 與精準 final 字幕所需 model deployment。
- Relay system-assigned Managed Identity。
- Storage、Application Insights、Azure Web PubSub 與 Azure Speech 所需 RBAC。
- Azure Web PubSub hub `connected` event handler，用於 Viewer WebSocket 連線後補送目前控制狀態。
- GitHub Actions 專用 user-assigned Managed Identity 與 federated credential。
- Function App `RollingUpdate` site update strategy。

正式環境使用 Managed Identity 讀取 Azure Speech key、呼叫 Azure Web PubSub data-plane publish API、讀寫 Azure Table Storage 中的 Relay 控制狀態，並產生觀眾端短效 client access URL。觀眾端 URL 可接收字幕與控制事件，但不得授予發布字幕權限。Relay runtime 不呼叫 Azure OpenAI，也不保存 Azure OpenAI endpoint、API key 或 session token。不得在 App Settings、參數檔或 repo 中保存 Speech key、Azure OpenAI API key、Web PubSub connection string 或 SAS token 真值。

所有部署參數與 app settings 都必須以「外部使用者不可讀取、不可列舉、不可交換敏感資料」為設計前提。Azure 基礎設施建立後預設為閒置模式；活動模式由 Azure Automation schedule 觸發 runbook 切換。

## 基礎設施部署

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

部署前需確認 `prod.bicepparam` 中的 Azure OpenAI 參數符合目標 region 的 model availability
與 quota。Portal 精準 final 字幕流程只依 deployment name 呼叫 Azure OpenAI：transcription
deployment 產生原始語言 draft，text model deployment 比對 OpenAI transcription 與 Azure Speech
final 候選文字，產生校正後原始語言字幕與其他輸出語言字幕。目前範例參數的預設模型為
`gpt-4o-mini-transcribe` 與 `gpt-5.4-mini`；若模型只在特定 region 可用，Azure OpenAI resource
需部署在同時支援這兩個模型的 region。

| 參數 | 預設值 | 說明 |
| --- | --- | --- |
| `azureOpenAILocation` | `southindia` | 目前用於 accurate transcription / text model 校正與翻譯的 Azure OpenAI region。 |
| `azureOpenAIDisableLocalAuth` | `false` | 是否停用 Azure OpenAI local key authentication。Portal 目前直接使用 Azure OpenAI API key，因此正式活動設定需維持 `false`。 |
| `azureOpenAITranscriptionDeploymentName` | `accurate-transcribe` | Portal 精準模式原始語言 draft 使用的 Azure OpenAI transcription deployment name。 |
| `azureOpenAITranscriptionModelName` | `gpt-4o-mini-transcribe` | 精準模式原始語言 draft 目標模型。 |
| `azureOpenAITranscriptionModelVersion` | `2025-12-15` | 目前 South India 已驗證可部署的 transcription model version。 |
| `azureOpenAITranslationDeploymentName` | `accurate-translate` | Portal 精準模式校正原文與翻譯字幕使用的 Azure OpenAI text model deployment name。 |
| `azureOpenAITranslationModelName` | `gpt-5.4-mini` | 精準 final 校正原文與翻譯字幕目標模型。 |
| `azureOpenAITranslationModelVersion` | `2026-03-17` | 目前 South India 已驗證可部署的 text model version。 |
| `azureOpenAITranscriptionDeploymentSkuName` / `azureOpenAITranslationDeploymentSkuName` | `GlobalStandard` | 目前 South India 已驗證可部署的 deployment SKU。 |

Azure OpenAI resource 與 deployment 由 Bicep 管理。Portal 目前使用 Azure OpenAI API key
連線 transcription / text model，因此 `azureOpenAIDisableLocalAuth` 必須為
`false`。Azure OpenAI endpoint 與 deployment name 可由 Bicep output 取得；API key
必須由操作端在 Azure Portal 或 Azure CLI 取得後輸入 Portal，不得注入 Relay Function App
app settings、Bicep output、GitHub Actions secrets 或文件範例，也不授權 Relay runtime
進行字幕加工。

操作端需要的 Portal 設定：

| Portal 欄位 | 來源 |
| --- | --- |
| Azure OpenAI Endpoint | Bicep output `azureOpenAIEndpoint`。 |
| Transcription Deployment | Bicep output `azureOpenAITranscriptionDeploymentName`。 |
| Translation Deployment | Bicep output `azureOpenAITranslationDeploymentName`。 |
| Azure OpenAI Key | Azure OpenAI resource 的 key；只輸入 Portal 本機設定，不寫入 repo、Relay 或部署參數。 |

基礎設施部署完成後，若 GitHub Actions secrets 尚未設定，需將 Bicep outputs 寫入 GitHub Actions secrets：

| Secret | 對應 Bicep output |
| --- | --- |
| `AZURE_CLIENT_ID` | `githubActionsIdentityClientId` |
| `AZURE_TENANT_ID` | `tenantId` |
| `AZURE_SUBSCRIPTION_ID` | `subscriptionId` |
| `AZURE_FUNCTIONAPP_NAME` | `functionAppName` |

若已完成 `gh auth login`：

```sh
gh secret set AZURE_CLIENT_ID --body "<github-actions-identity-client-id>" -R iplayground/LiveCaption
gh secret set AZURE_TENANT_ID --body "<azure-tenant-id>" -R iplayground/LiveCaption
gh secret set AZURE_SUBSCRIPTION_ID --body "<azure-subscription-id>" -R iplayground/LiveCaption
gh secret set AZURE_FUNCTIONAPP_NAME --body "<function-app-name>" -R iplayground/LiveCaption
```

## GitHub Actions 部署

Relay 程式碼部署使用 `.github/workflows/deploy-relay-functions.yml`。workflow 只部署既有 Function App 的程式碼，不在每次 push 時重跑 Bicep。

觸發條件：

- push 到 `main`，且變更包含 `Relay/**` 或 workflow 本身。
- 手動執行 `workflow_dispatch`。

部署流程：

1. checkout repo。
2. 設定 Python 3.13。
3. 安裝 `Relay/requirements.txt`。
4. 執行 `compileall` 與 `function_app` import 檢查。
5. 寫入 `build-info.json`。
6. 使用 GitHub OIDC 登入 Azure。
7. 透過 `Azure/functions-action@v1` 與 `remote-build: true` 部署 `Relay/`。
8. 輪詢 `GET /api/health`，確認正式 endpoint 回傳目前 commit SHA。
9. 健康檢查通過後，建立 `livecaption-relay-production` GitHub deployment success 紀錄。
10. 健康檢查失敗時，重新部署上一個健康 deployment、手動 `rollback_ref` 或 push event `before` SHA。

GitHub Deployments 只記錄健康版本與選擇 rollback ref；它不保存部署包，也不提供 Azure 原生 rollback。

Azure Portal 的 GitHub 來源綁定是必要手動步驟，而且只能手動完成。部署中心必須選擇使用 repo 內既有 workflow，不得讓 Azure Portal 產生新的 workflow，也不得使用 publish profile 或長效 Service Principal secret 建立第二套部署路徑。

Workflow、Azure Functions action、health check 與 rollback 步驟不得輸出完整 environment、app settings、HTTP headers、request/response body、Web PubSub client URL、access code、Speech key、connection string 或 Azure/GitHub CLI debug logs。需要診斷時，只能輸出 commit SHA、部署狀態、HTTP 狀態碼、錯誤代碼與遮蔽後摘要。

## 自訂網域

正式 Portal 的 Relay URL 應設定為：

```text
https://<relay-domain>/api/caption-events
```

正式 Relay Function App 綁定自訂網域：

```text
<relay-domain>
```

DNS 端需設定：

- 自訂網域指向正式 Relay Function App 的預設 hostname。
- Azure 驗證需要的 `asuid` TXT 值以 Function App 當下的 `customDomainVerificationId` 為準，不寫入文件。

Flex Consumption Function App 的 App Service Managed Certificate 需使用 `Microsoft.Web/sites/certificates` ARM endpoint 建立，再更新 `Microsoft.Web/sites/hostNameBindings`，將 `sslState` 設為 `SniEnabled` 並填入 managed certificate `thumbprint`。

## 安全規則

- 不得提交 `local.settings.json`、`prod.bicepparam` 或任何真實機密。
- 不得提交 Azure Storage connection string、Web PubSub connection string、SAS token、Speech key 或 Azure OpenAI API key 真值。
- Relay log 不得包含完整逐字稿、翻譯文字、Speech key、HMAC 簽章、連線字串、Web PubSub token 或可識別個人的資料。
- Relay 不處理 Azure OpenAI 音訊串流、prompt、response 或 session secret。
- CI/CD、部署 logs 與 Automation runbook output 不得包含完整 environment、完整 HTTP headers、完整 request/response body、viewer URL、access code 或可用來交換敏感資料的參數值。
- `VIEWER_ACCESS_CODE_REQUIRED=false` 是公開活動模式規格，會讓外部觀眾端取得短效 viewer URL；仍不得授予發布字幕權限，且不得輸出或保存完整 viewer URL。
- `roomName` 若需診斷，只記錄長度或遮蔽後的值。
- `trackNumber` 可記錄，但必須維持為整數欄位，不得混入其他識別資訊。
