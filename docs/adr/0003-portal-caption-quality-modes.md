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
     再由 text model deployment 比對 OpenAI transcription 與 Azure Speech final 候選文字，
     依詞彙提示校正原始語言字幕並產生其他輸出語言。
3. Azure Speech 即時 recognizing / partial 字幕流程不因精準模式而改變。
4. 精準模式需要 Portal 建立 Azure OpenAI 音訊 pipeline。Portal 以 Azure Speech final
   句段時間作為 anchor，切出同一區段音訊送往 Azure OpenAI transcription deployment 取得原始語言 draft，
   並把同一段 OpenAI transcription draft、Azure Speech final、語音輸入語言、字幕輸出語言、詞彙提示與最近 OpenAI 原文上下文送往
   Azure OpenAI text model deployment，取得校正後原始語言 final 字幕與其他輸出語言 final 字幕。
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
11. Portal 的字幕 session 可以先以開場階段處理語言執行，再由操作端切換到講者階段處理語言。
   這是 Portal 內部語音分析策略，不新增 Relay 或 Viewer 對外狀態；Relay 仍只接收同一個
   `sessionId` 的連續字幕事件。
12. 開場與講者階段切換時，Portal 必須維持同一條 session 時間軸。Speech final 與 Azure OpenAI
   精準字幕都應使用 session offset，SRT 也依時間碼排序；不得因 recognizer 或 transcription
   session 重建而把 offset 重置為 0。
13. Azure OpenAI 精準字幕可晚於後續句段回來。Portal 必須依原本 Speech final 句段的處理語言、
   session offset 與字幕輸出語言歸位，避免晚到結果被丟棄、被新的語音語言重新解讀，或在預覽與
   SRT 中以抵達順序取代時間順序。
14. Portal 使用 app sandbox 內固定的本機 secrets 設定檔保存 Azure OpenAI API key；
   不得寫入 `UserDefaults`、範例文件、logs 或 Relay 設定。Azure OpenAI 授權方式若後續改為短效 token 或其他流程，仍不得混入
   Relay 字幕轉發流程。
15. 若精準模式失敗、逾時或尚未取得 final 結果，產品行為必須保守：明確標示精準字幕不
   可用，不得中斷即時字幕。Azure Speech final 只作為 Azure OpenAI text model 的輔助候選與 fallback 參考，
   但不得直接補入精準模式的語音輸入語言字幕。
16. 詞彙提示只可作為音訊與上下文支持時的拼寫參考。若 Azure OpenAI transcription draft
   等同本次詞彙提示清單，Portal 必須把該 draft 視為損壞候選，記錄不含逐字稿內容的診斷，
   並讓 text model 流程改以 Azure Speech final 作為 fallback 候選。

## 影響

正面影響：

- 即時字幕維持 Azure Speech 低延遲路徑。
- 快速模式可沿用既有 Azure Speech final，成本與延遲可控。
- 精準模式可使用 Azure OpenAI transcription deployment 處理原始語言 draft，並沿用 Azure Speech final
  句段時間作為字幕時間 anchor 與輔助候選文字；校正後原文與其他輸出語言使用 Azure OpenAI text model 產生。
- Azure OpenAI transcription draft 是精準原文主要候選。Azure Speech final 明顯亂碼、近音誤轉或與穩定前文衝突時不得採用，只有 Azure OpenAI transcription 缺失、空白或明顯損壞時才作為 fallback。
- Portal 會防止 Azure OpenAI transcription 把詞彙提示清單本身當作逐字稿進入精準字幕、Relay
  或 SRT 輸出。
- Relay 的字幕內容邊界維持乾淨，不把後端變成音訊串流轉送與字幕推論服務。

代價與限制：

- Portal 需新增 Azure OpenAI 音訊 pipeline、transcription request 生命週期、失敗處理與 UI 狀態。
- 精準模式會增加操作端網路需求、Azure OpenAI 成本與配額壓力。
- Portal 需要處理 Azure OpenAI transcription request 與 text model 校正/翻譯 request 的句段對齊策略。
- Relay 發布與 Portal 主控板計數會出現 fast / accurate 兩套路徑，文件與 UI 需清楚標示來源。
- 本機 SRT 保存會出現 fast / accurate 兩套輸出目錄，文件需清楚標示來源，避免活動後製誤用。
- 開場與講者階段切換會讓 Portal 內部出現多個 recognizer 或 transcription session generation；
  實作必須保留每筆 Speech final 的 session offset、處理語言與對應 OpenAI request 身分，避免 late response
  破壞字幕順序或語言歸屬。
- `captionProvider` 不具備路由或驗證模式的語意，只能作為顯示與診斷資訊；需要判斷字幕品質
  時應使用 `captionMode`。
- 精準模式需等同一 transcription draft 句段的 text model 校正/翻譯 request 回傳必要輸出語言後才發布；
  若缺少必要語言，該筆精準字幕不得送往 Relay。
- Azure OpenAI transcription 與 text model 的可用 region、deployment type
  與 quota 需在部署前確認。
- Relay 不處理 Azure OpenAI 音訊串流、prompt、response 或 session secret。
