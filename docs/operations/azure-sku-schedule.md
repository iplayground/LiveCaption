# Azure SKU 排程操作

本文記錄 LiveCaption 正式環境的 Azure SKU 排程切換。Azure Speech resource 建立方式請見 [Azure Speech 資源設定](../deployment/azure-speech.md)，Relay 部署方式請見 [Relay Azure Functions 部署](../deployment/relay-functions.md)。

## 切換模式

Azure Automation `switch-livecaption-sku` runbook 會同步更新：

- Azure Speech SKU。
- Azure Web PubSub SKU 與 unit count。
- Relay Function App 的 `VIEWER_ACCESS_CODE_REQUIRED` app setting。

Azure 基礎設施建立後預設是閒置模式，不是活動模式。活動模式切換由 Azure Automation schedule 觸發 runbook 執行。

模式：

| 模式 | Speech | Web PubSub | `VIEWER_ACCESS_CODE_REQUIRED` |
| --- | --- | --- | --- |
| 活動模式 | `S0` | `Standard_S1` | `false`；LiveCaption 活動字幕是公開接收，觀眾端不需要 access code。 |
| 閒置模式 | `F0` | `Free_F1` | `true`。 |

實際排程時間由 Azure Automation schedules 管理，GitHub 文件不記錄正式活動的真實排程設定。檢查或修改排程時，以 Azure Portal 或 Azure CLI 查詢 Automation Account 的 schedules 與 job schedules 為準。

`VIEWER_ACCESS_CODE_REQUIRED=false` 是活動模式規格，代表任何可呼叫 Relay negotiate endpoint 的觀眾端都可取得短效 viewer URL。這符合公開活動字幕的產品定位，但 URL token 仍不得被 logs 或監控輸出保存，且觀眾端不得取得發布字幕權限。

## Runbook

Runbook 原始碼：

```text
Relay/infra/automation/switch-livecaption-sku.ps1
```

runbook 以 Automation Account 的 system-assigned Managed Identity 登入 Azure，並從 Azure context 取得 subscription ID。正式環境排程通常不需要另外設定 `SubscriptionId`。

Runbook output 不得列印完整 app settings、access code、Web PubSub client URL、Speech key、connection string、HTTP headers 或完整錯誤 response body。需要診斷時，只能輸出資源名稱、SKU、布林開關結果、狀態碼與遮蔽後的錯誤摘要。

## 更新 Runbook

變更 runbook 後，需重新上傳並 publish：

```sh
az automation runbook replace-content \
  --automation-account-name <automation-account-name> \
  --resource-group iplayground \
  --name switch-livecaption-sku \
  --content @Relay/infra/automation/switch-livecaption-sku.ps1

az automation runbook publish \
  --automation-account-name <automation-account-name> \
  --resource-group iplayground \
  --name switch-livecaption-sku
```

## 權限

Azure Automation Managed Identity 需要：

| 範圍 | 角色 |
| --- | --- |
| Function App | Contributor |
| Azure Web PubSub resource | Contributor |
| Azure Speech account | Contributor |

更新 Function App app setting 可能觸發 restart。排程執行後，應確認 Relay `GET /api/health` 或 viewer negotiate smoke test。
