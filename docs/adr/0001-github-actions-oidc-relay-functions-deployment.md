# ADR 0001: Relay Functions 採用 GitHub Actions OIDC 部署

- 狀態：Accepted
- 日期：2026-04-29

## 背景

LiveCaption Relay 採用 Azure Functions Flex Consumption 作為正式執行環境。
系統只規劃單一正式環境，不建立 staging、test slot 或第二套測試用 Function App。

若部署流程依賴 publish profile、長效 client secret 或手動 Azure Portal 操作，
會提高機密管理負擔，且部署流程較難審查與重現。

## 決策

Relay Functions 採用以下部署基線：

1. 以 `Relay/infra/main.bicep` 定義正式 Azure Functions 資源。
2. Bicep 建立 GitHub Actions 專用 user-assigned Managed Identity。
3. Bicep 建立 federated credential，限制 `iplayground/LiveCaption` 的 `main`
   分支可透過 GitHub OIDC 取得 Azure token。
4. GitHub Actions workflow 放在 `.github/workflows/deploy-relay-functions.yml`。
5. Azure Portal 部署中心的 GitHub 來源綁定是必要手動步驟，且只能手動完成。
   部署中心必須選擇使用 repo 內既有 workflow，不得讓 Azure Portal 產生新 workflow。
   Azure Portal 可能無法預覽實際使用的 workflow yml，因此部署中心儲存後只能
   先假定設定正確，再以 GitHub Actions 執行結果驗證。
6. 日常 workflow 只負責部署 Relay 程式碼，不在每次 push 時重跑整份 Bicep。
7. Function App 程式碼部署採用 `Azure/functions-action@v1` 與 `remote-build: true`。
8. workflow 使用 GitHub Deployments 記錄「健康檢查通過後」的 Relay 部署版本。
   deployment success 紀錄作為未來自動 rollback 的上一個已知健康 commit。
9. push 觸發時以 GitHub Actions `paths` 篩選控制自動部署範圍；手動執行
   `workflow_dispatch` 時則直接部署 Relay。
10. Flex Consumption Function App 設定 `siteUpdateStrategy.type` 為
    `RollingUpdate`，降低部署時因預設 `Recreate` 策略造成的服務中斷風險。
11. workflow 部署後會檢查 `GET /api/health` 是否回傳目前 commit SHA；若失敗，
    會重新部署上一個 GitHub deployment success 紀錄指向的 commit。若沒有上一個
    健康 deployment，push 事件 fallback 使用 `github.event.before`。

## 影響

正面影響：

- GitHub 不需要保存 Azure publish profile 或長效 client secret。
- 日常部署身分只需要 Function App 範圍的部署權限。
- 基礎設施與程式碼部署流程都可由 pull request 審查。

代價與限制：

- 第一次部署基礎設施後，需將 Bicep outputs 設定為 GitHub Actions secrets。
- Azure Portal 的 GitHub OAuth 與部署中心來源綁定需手動完成，無法只靠 Bicep
  或 GitHub Actions 全自動建立。
- 若 GitHub repo、組織或主要分支改名，必須同步更新 federated credential。
- 若同一批 push 變更包含 Relay 與 Portal 或文件，workflow 仍會上傳 Relay。
  完全沒有 `Relay/` 或 workflow 檔案差異的 push 不會觸發自動部署。
- GitHub Deployments 只記錄通過健康檢查的版本，用於選擇 rollback ref；它不保存
  部署包，也不提供 Azure 原生 rollback。因此 rollback 仍需 checkout 該 commit
  並重新部署一次。
- Rolling update 是 Azure Functions Flex Consumption 的 preview 功能。它可避免
  部署更新時一次重啟全部執行個體，並讓執行中的請求自然完成；但它不是 rollback
  機制，也無法保證有 runtime bug 的新版本不會在替換完成後影響正式服務。
- 手動執行 `workflow_dispatch` 不會做額外 diff 判斷；操作者需自行確認是否
  需要重新上傳 Relay。
- 若未來要讓 GitHub Actions 也部署 Bicep，需另設計較高權限的部署身分與審核流程。
