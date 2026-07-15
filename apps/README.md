# apps ディレクトリ

IaC だけでなく、検証に必要なアプリケーション資産を管理します。

## 想定用途
- Teams 連携アプリ
- ダッシュボード
- デモ補助ツール

## アプリケーション

- `foundry-chat-baseline/`: Microsoft Foundry を利用するチャット API / UI
- `foundry-chat-baseline-test/`: Foundry Chat Baseline の接続テスト
- `service-group-sli-demo/`: Service Group / Health Model / SLI デモ用の注文 API / UI
- `service-group-sli-demo-function/`: 注文を処理する任意デプロイの Azure Functions worker

各アプリケーションのデプロイ方法は、対応する `infra/scenarios/` 配下の README を参照してください。
