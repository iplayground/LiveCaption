# Relay 健康檢查 API

本文件定義 Relay 的健康檢查 endpoint。此 endpoint 供 GitHub Actions 部署流程確認
Azure Functions 正式 endpoint 已載入指定 commit 的部署包。

## 健康檢查

```http
GET /api/health
```

此 endpoint 不需要授權，不讀取 Azure Speech key，也不發布 Azure Web PubSub 訊息。
回應不得包含機密、逐字稿、使用者識別資料或可回推身分的事件內容。

成功回應：

```json
{
  "status": "ok",
  "commit": "7395d628611932685ab58c397eb0f990832a0ca7"
}
```

欄位說明：

| 欄位 | 說明 |
| --- | --- |
| `status` | 固定為 `ok`，表示 Relay process 可回應 HTTP 請求。 |
| `commit` | 部署包內 `build-info.json` 記錄的 commit SHA。若本機或舊部署包沒有該檔案，會回傳 `unknown`。 |
