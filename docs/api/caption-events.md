# 字幕事件 API

本文件定義 Portal 傳送字幕事件到 Relay 的第一版 API 契約。Relay 先負責驗證、正規化與發布事件，不負責執行語音辨識、翻譯或保存完整逐字稿。

## 目標

- 固定 Portal 與 Relay 之間的事件輸入邊界。
- 讓 Relay 可以在發布到 Azure Web PubSub 前驗證來源、語言、時間碼與事件內容。
- 以單一活動為前提，使用 `trackNumber` 區分同時進行的字幕軌，並用允許空字串的 `roomName` 提供觀眾端顯示用的會議室名稱。
- 避免 Relay 記錄完整逐字稿、翻譯內容、權杖或可回推身分的資料。
- 保持 Portal 語音輸入語言、字幕輸出語言與 App 介面在地化語言互相獨立。

## Portal Relay 設定

第一版 Portal 只需要設定 Relay 的最小連線與路由資訊：

- Relay URL
- `trackNumber`
- `roomName`，可留空

Portal 不應設定 Azure Web PubSub hub、連線字串、SAS token、group name 或 Azure 發布細節。

## 會議室與軌道識別

`trackNumber` 是同一場活動中的字幕軌編號，型別必須是 JSON integer。Relay 以 `trackNumber` 作為同時段字幕來源的主要識別值；當需要判斷某個 Relay 設定是否可用時，應判斷該 `trackNumber` 是否已被佔用，而不是判斷 `roomName` 是否重複。若未使用多軌，Portal 應送 `1`。

`roomName` 是會議室名稱欄位，由 Portal 操作者設定，允許空字串，並隨字幕事件送到 Relay。Relay 不應使用 `roomName` 判斷設定唯一性或佔用狀態；觀眾端可用它顯示目前字幕軌所在的會議室。

字幕事件 API 本身只驗證 `trackNumber` 格式與範圍，不應在每一筆字幕事件上做軌道互斥，避免同一個 Portal 後續送出的字幕被誤判為佔用衝突。軌道佔用判斷應放在 Relay 設定檢查或未來的軌道租用流程。

建議限制：

- `trackNumber` 必須大於 0。
- `roomName` 欄位必須存在，但允許空字串。
- Relay 應去除 `roomName` 前後空白；若去除後為空，正規化為空字串。
- 若 `roomName` 非空，長度 1 到 80 字元。
- 若 `roomName` 非空，不得包含換行、控制字元、URL 保留分隔字元 `/`、`?`、`#`。
- Relay 不應將完整 `roomName` 寫入一般 log；若需要診斷，可記錄長度或遮蔽後的值。
- Relay 可以記錄 `trackNumber`。

## 發送字幕事件

```http
POST /api/caption-events
Content-Type: application/json
X-LiveCaption-Timestamp: <utc-iso-8601-timestamp>
X-LiveCaption-Signature: sha256=<hmac-sha256-signature>
```

### 授權

第一版 Relay 使用 Azure Speech key 衍生的 HMAC 簽章驗證 Portal 請求。Portal 不得把 Speech key 直接送進 Relay；Portal 必須用本機設定的 Speech key 對請求產生簽章，Relay 則透過 Azure Speech resource 定位資訊向 Azure 讀取實際 Speech key 後驗章。

簽章規則：

```text
message = X-LiveCaption-Timestamp + "." + raw request body bytes
signature = "sha256=" + HMAC-SHA256(<azure-speech-key>, message)
```

`X-LiveCaption-Timestamp` 必須是 UTC ISO 8601 時間，例如 `2026-04-29T12:34:56.789Z`。Relay 應拒絕超出允許時間窗的請求，避免簽章被重放。

Relay 收到請求時必須驗證：

- Relay 可透過 `AZURE_SUBSCRIPTION_ID`、`AZURE_SPEECH_RESOURCE_GROUP` 與 `AZURE_SPEECH_ACCOUNT_NAME` 取得 Azure Speech key。
- `X-LiveCaption-Timestamp` 存在且在允許時間窗內。
- `X-LiveCaption-Signature` 存在且與 request body 驗算結果一致。

Relay 使用 Azure SDK 的 `DefaultAzureCredential` 讀取 Azure Speech resource key。正式環境應使用 Managed Identity；本機開發可讓 `DefaultAzureCredential` 使用目前的 Azure CLI 登入身分。

## 請求格式

```json
{
  "roomName": "A101",
  "trackNumber": 1,
  "createdAt": "2026-04-29T12:34:56.789Z",
  "source": {
    "bundleIdentifier": "io.iplayground.LiveCaptionPortal",
    "appVersion": "1.0"
  },
  "speech": {
    "inputLanguage": "zh-TW",
    "offsetTicks": 120000000,
    "durationTicks": 35000000,
    "text": "歡迎來到今天的活動"
  },
  "captions": {
    "zh-Hant": "歡迎來到今天的活動",
    "en": "Welcome to today's event",
    "ja": "本日のイベントへようこそ"
  }
}
```

### 欄位說明

| 欄位 | 必填 | 說明 |
| --- | --- | --- |
| `roomName` | 是 | 同一場活動中的會議室名稱，可為空字串；不得作為唯一性或佔用判斷依據。 |
| `trackNumber` | 是 | 同一場活動中的字幕軌編號，必須是 JSON integer 且大於 0。 |
| `createdAt` | 是 | Portal 建立事件的 UTC ISO 8601 時間。 |
| `source.bundleIdentifier` | 是 | Portal App 的 bundle identifier，目前為 `io.iplayground.LiveCaptionPortal`。 |
| `source.appVersion` | 否 | Portal App 版本，對應 Xcode 專案的 `MARKETING_VERSION`，用於診斷相容性，不得含使用者識別資料。 |
| `speech.inputLanguage` | 是 | 語音輸入語言，目前允許 `zh-TW` 或 `en-US`。 |
| `speech.offsetTicks` | 是 | Azure Speech SDK 回傳的 offset ticks，1 tick = 100 ns。 |
| `speech.durationTicks` | 是 | Azure Speech SDK 回傳的 duration ticks，1 tick = 100 ns。 |
| `speech.text` | 是 | 最終辨識文字，只供 Relay 發布，不得完整寫入 log。 |
| `captions` | 是 | 以字幕輸出語言代碼為 key、字幕文字為 value 的 object，至少包含 `zh-Hant` 與 `en`。 |
| `captions.<language>` | 是 | 字幕輸出語言目前允許 `zh-Hant`、`en`、`ja`、`ko`；value 是對應語言字幕文字，不得完整寫入 log。 |

## 語言規則

語音輸入語言只描述 Speech 辨識來源，目前允許：

- `zh-TW`
- `en-US`

字幕輸出語言只描述要發布給觀眾端的字幕，目前允許：

- `zh-Hant`，必要
- `en`，必要
- `ja`，選用
- `ko`，選用

Relay 不應使用 App 介面在地化語言推論語音輸入或字幕輸出。Portal 必須在每個事件中明確送出 `speech.inputLanguage`，並在 `captions` 以語言代碼作為 key。

## 驗證規則

Relay 接收事件後必須先完成以下驗證，全部通過後才可發布到 Azure Web PubSub：

- body 是 JSON object。
- `trackNumber` 是 integer，且大於 0。
- `roomName` 是 string，可為空字串；若非空，必須符合會議室名稱規則。
- `createdAt` 是有效 UTC 時間，且不能明顯來自未來。
- `speech.inputLanguage` 在允許清單內。
- `speech.offsetTicks` 與 `speech.durationTicks` 是非負整數，且 `durationTicks` 大於 0。
- `speech.text` 去除前後空白後不可為空。
- `captions` 是 JSON object，至少包含 `zh-Hant` 與 `en`。
- `captions` 的 key 必須在字幕輸出語言允許清單內。
- `captions` 的 value 必須是 string，且去除前後空白後不可為空。
- body 大小、單欄文字長度與字幕語言數量不得超過 Relay 設定上限。

## 成功回應

```http
HTTP/1.1 202 Accepted
Content-Type: application/json
```

```json
{
  "accepted": true
}
```

`202 Accepted` 代表 Relay 已接受事件並完成發布流程的排程或同步發布。若未來改成佇列式處理，語意仍可保持相容。

## 錯誤回應

Relay 錯誤回應使用一致 JSON 格式：

```json
{
  "error": {
    "code": "invalid_caption_event",
    "message": "Caption event is invalid.",
    "details": [
      {
        "field": "captions.en",
        "reason": "Required output language en is missing."
      }
    ]
  }
}
```

建議狀態碼：

| 狀態碼 | 情境 |
| --- | --- |
| `400 Bad Request` | JSON 格式錯誤、缺少必要欄位或欄位值不合法。 |
| `401 Unauthorized` | 缺少或無效的 HMAC 簽章，或 Relay 無法取得 Azure Speech key。 |
| `413 Payload Too Large` | body 或文字欄位超過 Relay 設定上限。 |
| `429 Too Many Requests` | 超過速率限制。 |
| `500 Internal Server Error` | Relay 非預期錯誤。 |
| `502 Bad Gateway` | Azure Web PubSub 發布失敗或逾時。 |

錯誤訊息不得包含完整 `speech.text`、`captions` value、Speech key、簽章、連線字串或可識別個人的資料。

## 發布邊界

Relay 發布到 Azure Web PubSub 前可加入 Relay 自己的 metadata，例如 `receivedAt`。Relay 不應加入 Portal 本機路徑、音訊裝置名稱、使用者帳號、IP 位置或未經必要性評估的診斷資料。

第一版 Azure Web PubSub group 建議使用固定 group：

```text
caption-live
```

同一場活動的所有字幕軌先發布到同一個 group，觀眾端依 payload 內的 `trackNumber` 判斷要顯示哪個軌道的字幕，並可用 `roomName` 顯示會議室名稱；`roomName` 為空字串時代表未設定。Portal 不需要知道 group 命名規則，觀眾端若需要訂閱也應透過 Relay 或前端設定取得對應資訊。

第一版建議 Web PubSub 發布 payload 保留 Portal 傳入的字幕欄位，並只加入 Relay metadata：

```json
{
  "relay": {
    "receivedAt": "2026-04-29T12:34:56.900Z"
  },
  "roomName": "A101",
  "trackNumber": 1,
  "createdAt": "2026-04-29T12:34:56.789Z",
  "speech": {
    "inputLanguage": "zh-TW",
    "offsetTicks": 120000000,
    "durationTicks": 35000000
  },
  "captions": {
    "zh-Hant": "歡迎來到今天的活動",
    "en": "Welcome to today's event"
  }
}
```

發布給觀眾端時，若沒有產品需求需要顯示原始辨識文字，Relay 應省略 `speech.text`，只保留字幕輸出與時間碼。

## Logging 規則

Relay 可以記錄：

- `roomName` 長度或遮蔽後的值
- `trackNumber`
- 語言代碼
- 字幕數量
- 文字長度
- 驗證錯誤代碼
- 發布成功或失敗狀態

Relay 不得記錄：

- 完整逐字稿或翻譯文字
- 音訊內容
- Speech key
- HMAC 簽章
- Azure Web PubSub 連線字串或 SAS token
- 可識別個人的使用者資料
- Portal 本機檔案路徑或裝置唯一識別資訊

## 後續實作順序

1. 在 `Relay/` 建立 Python 3.12 Azure Functions 專案骨架。
2. 實作字幕事件資料模型與 validator。
3. 為成功路徑、錯誤輸入、語言規則、授權邊界與 logging 遮蔽撰寫測試。
4. 實作 Azure Web PubSub publisher 介面，先以可替換 adapter 隔離外部服務。
5. 補上部署文件與必要環境變數範例。
