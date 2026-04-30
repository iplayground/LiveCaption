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
8. workflow 會以上一次成功 Azure 上傳建立的 GitHub deployment 紀錄作為基準，
   只要從該 commit 到目前 HEAD 的差異包含 `Relay/` 檔案，就執行 Azure 上傳。
9. workflow 拆成 `detect-relay-changes` 與 `deploy` 兩個 job。沒有 `Relay/`
   差異時，`detect-relay-changes` 成功結束，`deploy` 顯示 skipped。

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
- 若同一批變更包含 Relay 與 Portal 或文件，workflow 仍會上傳 Relay。只有完全
  沒有 `Relay/` 差異時才會略過 Azure 上傳，且略過時不會更新 GitHub deployment
  基準。
- 無 Relay 差異時不應使 GitHub Actions 失敗；Summary 需能看出 deploy job 是否
  實際執行。
- 若未來要讓 GitHub Actions 也部署 Bicep，需另設計較高權限的部署身分與審核流程。
