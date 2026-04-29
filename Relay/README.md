# Relay

Relay 是 LiveCaption 的後端服務，負責接收 Portal 傳來的字幕事件，驗證事件格式，並在後續整合中發布到 Azure Web PubSub。

目前 Relay 已建立 Python 3.13 Azure Functions 骨架、字幕事件 validator 與 Speech key HMAC 請求驗證。Azure Web PubSub publisher 仍待後續實作。

## 目錄

- `function_app.py`：Azure Functions HTTP 入口。
- `src/relay/models.py`：字幕事件資料模型。
- `src/relay/validation.py`：字幕事件驗證規則。
- `src/relay/http.py`：HTTP handler 與 Web PubSub payload builder。
- `tests/`：pytest 測試。

## 本機環境

建立並啟用 Python 3.13 virtual environment：

```sh
cd Relay
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt pytest
```

若本機沒有 `python3.13`，請先安裝 Python 3.13。Relay 的主要支援版本是 Python 3.13。

## 測試

```sh
cd Relay
python -m pytest
```

## Azure Functions 本機設定

`local.settings.json` 不得提交。請從範例建立本機設定：

```sh
cd Relay
cp local.settings.sample.json local.settings.json
```

Relay 透過 `AZURE_SUBSCRIPTION_ID`、`AZURE_SPEECH_RESOURCE_GROUP` 與
`AZURE_SPEECH_ACCOUNT_NAME` 定位 Azure Speech resource，執行時向 Azure 讀取實際
Speech key 並驗證 Portal 請求簽章。Portal 不會把 Speech key 直接傳給 Relay，而是用
本機 Speech key 對 request body 產生 HMAC 簽章。

## 本機啟動

需要安裝 Azure Functions Core Tools。啟動前確認已建立 `local.settings.json`。

```sh
cd Relay
func start --port 7071
```

本機 endpoint：

```text
POST http://localhost:7071/api/caption-events
```

## API 契約

字幕事件格式與安全規則記錄於 [../docs/api/caption-events.md](../docs/api/caption-events.md)。
