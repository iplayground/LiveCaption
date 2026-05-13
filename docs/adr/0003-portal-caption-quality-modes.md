# ADR 0003: Portal final 字幕分為快速與精準模式

- 狀態：Accepted
- 日期：2026-05-09

## 背景

LiveCaption 需要同時支援低延遲與較高精準度的字幕輸出。即時解析必須維持穩定，
不可因 Azure OpenAI 的延遲、配額或連線狀態影響現場即時字幕。

## 決策

1. 即時解析一律由 Portal 使用 Azure Speech 處理。
2. Portal 將 final 字幕輸出分為兩種品質模式：
   - 快速：使用 Azure Speech final 結果。
   - 精準：使用 Azure OpenAI realtime 結果，其中原始語言使用 `gpt-realtime-whisper`，
     其他輸出語言使用 `gpt-realtime-translate`。
3. Azure Speech 即時 recognizing / partial 字幕流程不因精準模式而改變。
4. 精準模式需要 Portal 建立 Azure OpenAI realtime 音訊 pipeline，並把同一場活動音訊
   送往 `gpt-realtime-whisper` 取得原始語言 final 字幕結果，送往
   `gpt-realtime-translate` 取得其他輸出語言 final 字幕結果。
5. 發布精準模式時，原始語言字幕也使用 Azure OpenAI 結果，不使用 Azure Speech final
   補原始語言。
6. Relay 不負責用 Azure OpenAI 判斷或改寫字幕內容。Relay 只負責驗證 Portal 請求、
   發送 Portal 選定的 final 字幕結果，並產生 Viewer WebSocket URL。
7. Portal 發布 Relay 字幕事件時依模式分開送出；快速事件只包含 `fast`，精準事件只包含
   `accurate`，避免觀眾端或後端將 Azure Speech 與 Azure OpenAI final 字幕視為同一筆
   Relay 發布。
8. Relay 字幕事件使用單一 top-level `captionMode` 表示本筆事件模式。舊版
   `captionModes` 多模式 object 廢除；`captionProvider` 只作為選填顯示欄位，不用來決定
   Relay 行為，也不與 `captionMode` 綁定。
9. Portal 結束字幕時，SRT 輸出也依模式分開保存。Azure Speech final 字幕寫入 `fast/`
   子資料夾，Azure OpenAI final 字幕寫入 `accurate/` 子資料夾；未產生內容的模式不寫空
   SRT 檔。
10. Portal 使用本機設定保存 Azure OpenAI API key；不得寫入範例文件、logs 或 Relay
   設定。Azure OpenAI realtime 授權方式若後續改為短效 token 或其他流程，仍不得混入
   Relay 字幕轉發流程。
11. 若精準模式失敗、逾時或尚未取得 final 結果，產品行為必須保守：明確標示精準字幕不
   可用，不得中斷即時字幕，也不得用 Azure Speech final 補入精準模式的語音輸入語言字幕。

## 影響

正面影響：

- 即時字幕維持 Azure Speech 低延遲路徑。
- 快速模式可沿用既有 Azure Speech final，成本與延遲可控。
- 精準模式可使用 `gpt-realtime-whisper` 處理原始語言字幕，並使用專為即時翻譯設計的
  `gpt-realtime-translate` 處理其他輸出語言。
- Relay 的字幕內容邊界維持乾淨，不把後端變成音訊串流轉送與字幕推論服務。

代價與限制：

- Portal 需新增 Azure OpenAI realtime 音訊 pipeline、連線生命週期、失敗處理與 UI 狀態。
- 精準模式會增加操作端網路需求、Azure OpenAI 成本與配額壓力。
- Portal 需要處理 Azure Speech final 與 Azure OpenAI final 的句段對齊策略。
- Relay 發布與 Portal 主控板計數會出現 fast / accurate 兩套路徑，文件與 UI 需清楚標示來源。
- 本機 SRT 保存會出現 fast / accurate 兩套輸出目錄，文件需清楚標示來源，避免活動後製誤用。
- `captionProvider` 不具備路由或驗證模式的語意，只能作為顯示與診斷資訊；需要判斷字幕品質
  時應使用 `captionMode`。
- 第一版可先採用 Azure Speech final 時擷取 OpenAI transcript buffer 的保守對齊策略，後續需
  改進為更可靠的 output item / audio boundary 對齊。
- `gpt-realtime-whisper` 與 `gpt-realtime-translate` 的可用 region、deployment type
  與 quota 需在部署前確認。
- Relay 不處理 Azure OpenAI 音訊串流、prompt、response 或 realtime session secret。
