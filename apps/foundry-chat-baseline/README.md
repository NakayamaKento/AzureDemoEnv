# Foundry Chat Baseline App

App Service で動作する最小チャット UI/API サンプルです。

## ローカル実行

```bash
cd apps/foundry-chat-baseline
npm install
set FOUNDRY_PROJECT_ENDPOINT=https://<foundry>.services.ai.azure.com/api/projects/<project>
set FOUNDRY_AGENT_ID=<agent-id>
set FOUNDRY_AGENT_VERSION=latest
npm start
```

## 必須環境変数

- `FOUNDRY_PROJECT_ENDPOINT`
- `FOUNDRY_AGENT_ID`

## 任意環境変数

- `FOUNDRY_AGENT_VERSION`（省略時 `latest`）
- `PORT`（省略時 `3000`）

## エンドポイント

- `GET /healthz`
- `POST /api/chat`
