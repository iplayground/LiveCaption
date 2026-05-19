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
   - 精準：使用 Azure OpenAI 結果，其中 transcription deployment 先產生原始語言 draft，
     再由 text model deployment 依詞彙提示校正原始語言字幕並產生其他輸出語言。
3. Azure Speech 即時 recognizing / partial 字幕流程不因精準模式而改變。
4. 精準模式需要 Portal 建立 Azure OpenAI 音訊 pipeline。Portal 以 Azure Speech final
   句段時間作為 anchor，切出同一區段音訊送往 Azure OpenAI transcription deployment 取得原始語言 draft，
   並把同一段 draft、語音輸入語言、字幕輸出語言與詞彙提示送往 Azure OpenAI text model deployment，
   取得校正後原始語言 final 字幕與其他輸出語言 final 字幕。
5. 發布精準模式時，原始語言字幕也使用 Azure OpenAI 結果，不使用 Azure Speech final
   補原始語言。
6. 精準模式以 Azure Speech final 作為每筆字幕事件的起訖時間與句段邊界；Azure OpenAI
   text model 校正後原文作為原文，Azure OpenAI text model 翻譯結果補入同一筆精準字幕事件的其他輸出語言。
7. Relay 不負責用 Azure OpenAI 判斷或改寫字幕內容。Relay 只負責驗證 Portal 請求、
   發送 Portal 選定的 final 字幕結果，並產生 Viewer WebSocket URL。
8. Portal 發布 Relay 字幕事件時依模式分開送出；快速事件只包含 `fast`，精準事件只包含
   `accurate`，避免觀眾端或後端將 Azure Speech 與 Azure OpenAI final 字幕視為同一筆
   Relay 發布。
9. Relay 字幕事件使用單一 top-level `captionMode` 表示本筆事件模式。舊版
   `captionModes` 多模式 object 廢除；`captionProvider` 只作為選填顯示欄位，不用來決定
   Relay 行為，也不與 `captionMode` 綁定。
10. Portal 結束字幕時，SRT 輸出也依模式分開保存。Azure Speech final 字幕寫入 `fast/`
   子資料夾，Azure OpenAI final 字幕寫入 `accurate/` 子資料夾；未產生內容的模式不寫空
   SRT 檔。
11. Portal 使用本機設定保存 Azure OpenAI API key；不得寫入範例文件、logs 或 Relay
   設定。Azure OpenAI 授權方式若後續改為短效 token 或其他流程，仍不得混入
   Relay 字幕轉發流程。
12. 若精準模式失敗、逾時或尚未取得 final 結果，產品行為必須保守：明確標示精準字幕不
   可用，不得中斷即時字幕，也不得用 Azure Speech final 補入精準模式的語音輸入語言字幕。

## 影響

正面影響：

- 即時字幕維持 Azure Speech 低延遲路徑。
- 快速模式可沿用既有 Azure Speech final，成本與延遲可控。
- 精準模式可使用 Azure OpenAI transcription deployment 處理原始語言 draft，並沿用 Azure Speech final
  句段時間作為字幕時間 anchor；校正後原文與其他輸出語言使用 Azure OpenAI text model 產生。
- Relay 的字幕內容邊界維持乾淨，不把後端變成音訊串流轉送與字幕推論服務。

代價與限制：

- Portal 需新增 Azure OpenAI 音訊 pipeline、transcription request 生命週期、失敗處理與 UI 狀態。
- 精準模式會增加操作端網路需求、Azure OpenAI 成本與配額壓力。
- Portal 需要處理 Azure OpenAI transcription request 與 text model 校正/翻譯 request 的句段對齊策略。
- Relay 發布與 Portal 主控板計數會出現 fast / accurate 兩套路徑，文件與 UI 需清楚標示來源。
- 本機 SRT 保存會出現 fast / accurate 兩套輸出目錄，文件需清楚標示來源，避免活動後製誤用。
- `captionProvider` 不具備路由或驗證模式的語意，只能作為顯示與診斷資訊；需要判斷字幕品質
  時應使用 `captionMode`。
- 精準模式需等同一 transcription draft 句段的 text model 校正/翻譯 request 回傳必要輸出語言後才發布；
  若缺少必要語言，該筆精準字幕不得送往 Relay。
- Azure OpenAI transcription 與 text model 的可用 region、deployment type
  與 quota 需在部署前確認。
- Relay 不處理 Azure OpenAI 音訊串流、prompt、response 或 session secret。
