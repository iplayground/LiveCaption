# Relay

Relay 是 LiveCaption 的 Python 3.13 Azure Functions 後端，負責接收 Portal 字幕事件、驗證 HMAC 與事件格式，並發布到 Azure Web PubSub。

## 目錄

- `function_app.py`：Azure Functions HTTP 入口。
- `src/relay/models.py`：字幕事件資料模型。
- `src/relay/validation.py`：字幕事件驗證規則。
- `src/relay/http.py`：HTTP handler 與 Web PubSub payload builder。
- `src/relay/webpubsub.py`：Azure Web PubSub publisher adapter 與觀眾端 token provider。
- `tests/`：pytest 測試。

## 本機環境

```sh
cd Relay
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt pytest
```

## 測試

```sh
cd Relay
python -m pytest
```

## 本機啟動

`local.settings.json` 不得提交，請先從範例建立：

```sh
cd Relay
cp local.settings.sample.json local.settings.json
func start --port 7071
```

本機 endpoint：

```text
HEAD http://localhost:7071/api/caption-events
POST http://localhost:7071/api/caption-events
POST http://localhost:7071/api/viewer/negotiate
GET http://localhost:7071/api/health
```

## 相關文件

- [Relay 架構與資料流](../docs/architecture/relay.md)
- [字幕事件 API](../docs/api/caption-events.md)
- [觀眾端連線 API](../docs/api/viewer-negotiate.md)
- [Relay Azure Functions 部署](../docs/deployment/relay-functions.md)
