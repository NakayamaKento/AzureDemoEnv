# デプロイガイド

## 1. 前提

- Azure CLI が利用可能
- 対象サブスクリプションでリソースプロバイダーが登録済み
- デプロイ先リージョンで必要 SKU が利用可能

## 2. インフラをデプロイ

```bash
az group create -n rg-foundry-chat-baseline -l southeastasia

az deployment group create \
  --resource-group rg-foundry-chat-baseline \
  --template-file infra/scenarios/foundry-chat-baseline/bicep/main.bicep \
  --parameters scenarioCode=fcb01 location=southeastasia
```

## 3. チャットアプリをデプロイ

このリポジトリのアプリコードは `apps/foundry-chat-baseline` にあります。

Node.js アプリを zip 化して App Service に反映します。

```bash
# 例: リポジトリルートで実行
cd apps/foundry-chat-baseline
npm install

# zip を作成（方法は環境に応じて変更）
# Windows PowerShell の例
Compress-Archive -Path * -DestinationPath ../../chatui.zip -Force

# App Service へ zip deploy
az webapp deploy \
  --resource-group rg-foundry-chat-baseline \
  --name <Bicepで生成されたwebapp名> \
  --src-path ../../chatui.zip \
  --type zip
```

## 4. 環境変数を設定

最低限、以下を App Service 設定で確認/更新します。

- `FOUNDRY_PROJECT_ENDPOINT`
- `FOUNDRY_AGENT_ID`
- `FOUNDRY_AGENT_VERSION`

## 5. 動作確認

- Bicep 出力 `appGatewayUrl` にブラウザアクセス
- `/healthz` が `ok` を返すことを確認
- チャット入力で Foundry から応答が返ることを確認

## 6. 既知の注意点

- 現状は HTTP リスナーのため、運用では HTTPS 化が必須
- Foundry 側のプロジェクト/エージェント作成は別手順で実施
- ネットワーク分離を厳格化する場合は Private Endpoint + Firewall を追加
