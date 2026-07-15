# Foundry Chat Baseline クイックスタートガイド

**5分でチャットアプリが動く手順** - 自動スクリプト利用版

## 前提

- Windows 10 以上、PowerShell 7.0 以上
- Azure CLI がインストール済み（[インストール](https://learn.microsoft.com/cli/azure/install-azure-cli)）
- Node.js 20+ がインストール済み
- 対象 Azure サブスクリプションで以下が利用可能
  - `Microsoft.Web`（App Service）
  - `Microsoft.CognitiveServices`（Foundry）
  - `Microsoft.Storage`
  - `Microsoft.Search`
  - `Microsoft.DocumentDB`
  - `Microsoft.Network`

## ⚡ ステップ 1: インフラ＋アプリのワンストップデプロイ

このスクリプトは **10～15分** でインフラをデプロイし、アプリを App Service に反映します。

```powershell
cd C:\Users\<you>\AzureDemoEnv

# デフォルト設定（scnearioCode=fcb01, location=southeastasia）でデプロイ
.\infra\scenarios\foundry-chat-baseline\deploy.ps1

# または、カスタム設定
.\infra\scenarios\foundry-chat-baseline\deploy.ps1 -ScenarioCode mychat01 -Location southeastasia
```

### 実装内容

| ステップ | 内容 |
|---------|------|
| 1. Azure ログイン | Azure CLI で認証 |
| 2. リソースグループ作成 | `rg-foundry-chat-baseline-fcb01` など |
| 3. Bicep デプロイ | VNet, App Service, Foundry, Storage, Cosmos DB, Search, Application Gateway, WAF |
| 4. npm install | `apps/foundry-chat-baseline` に依存パッケージをインストール |
| 5. zip deploy | アプリを App Service にデプロイ |

**完了後の表示例：**
```
✅ インフラとアプリのデプロイが完了しました！

【次に実施する作業】
1. Foundry プロジェクト/エージェント作成：
   .\infra\scenarios\foundry-chat-baseline\setup-foundry-agent.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01
...
```

---

## ⚡ ステップ 2: Foundry エージェント作成

デプロイ完了後、Foundry 側でエージェント（AI 会話用）を作成します。

```powershell
# deploy.ps1 のリソースグループ名を指定
.\infra\scenarios\foundry-chat-baseline\setup-foundry-agent.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01
```

### 実装内容

| ステップ | 内容 |
|---------|------|
| 1. Foundry リソース検索 | デプロイされた Foundry アカウントを検索 |
| 2. 接続設定 | Bing 検索、モデル接続を設定 |
| 3. エージェント作成 | `baseline-chatbot-agent` という名前のエージェントを Foundry に作成 |
| 4. ID/バージョン取得 | 次のステップで使用する ID とバージョンを出力 |

**完了後の表示例：**
```
✅ Foundry エージェント作成完了！

【次に実施する作業】
App Service の環境変数を更新してください：
  .\infra\scenarios\foundry-chat-baseline\update-app-settings.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01 -AgentId baseline-chatbot-agent -AgentVersion 1
```

---

## ⚡ ステップ 3: App Service 環境変数を更新して完成

エージェント ID をアプリに設定します。

```powershell
# setup-foundry-agent.ps1 で表示されたエージェント ID とバージョンを指定
.\infra\scenarios\foundry-chat-baseline\update-app-settings.ps1 `
  -ResourceGroup rg-foundry-chat-baseline-fcb01 `
  -AgentId baseline-chatbot-agent `
  -AgentVersion 1
```

### 実装内容

| ステップ | 内容 |
|---------|------|
| 1. App Service 検索 | リソースグループ内の App Service を自動検索 |
| 2. Foundry 情報取得 | Foundry エンドポイントを自動取得 |
| 3. 環境変数設定 | `FOUNDRY_PROJECT_ENDPOINT`, `FOUNDRY_AGENT_ID`, `FOUNDRY_AGENT_VERSION` を設定 |
| 4. アプリ再起動 | App Service を再起動して設定を反映 |

**完了後の表示例：**
```
✅ 設定更新完了！

【ブラウザでアクセス】
  http://<Application Gateway IP>
```

---

## 🎯 完了 - チャットアプリが使える状態に！

ブラウザで表示されたURL（例：`http://40.50.60.70`）にアクセスすると、チャット画面が表示されます。  
メッセージを入力すると、Foundry エージェントが Bing 検索を活用して回答します。

---

## 🔧 各スクリプトの詳細

### `deploy.ps1` - インフラ＋アプリ展開

**何をしているか：**
1. リソースグループを作成/確認
2. Bicep でネットワーク、Foundry、App Service などをデプロイ
3. Node.js アプリを npm install で依存パッケージをインストール
4. アプリを zip 化して App Service にデプロイ

**失敗時の対応：**
- リソースグループが既に存在する場合は、そのまま利用します
- Bicep デプロイでエラーが出た場合は、リソースプロバイダーの登録を確認してください

```bash
# リソースプロバイダー登録の例
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.Search
```

### `setup-foundry-agent.ps1` - Foundry エージェント作成

**何をしているか：**
1. リソースグループ内の Foundry アカウント名を検索
2. Foundry REST API を呼び出してエージェントを作成
3. エージェント ID とバージョンを出力

**失敗時の対応：**
- 「Foundry が見つかりません」→ `deploy.ps1` が正常に完了していることを確認
- 「接続エラー」→ VPN/ジャンプボックスの設定を確認

### `update-app-settings.ps1` - App Service 設定反映

**何をしているか：**
1. App Service の環境変数を更新
2. アプリを再起動して設定を反映

**環境変数一覧：**

| 環境変数 | 説明 | 例 |
|---------|------|-----|
| `FOUNDRY_PROJECT_ENDPOINT` | Foundry の API エンドポイント | `https://aif12345678.services.ai.azure.com/api/projects/projchat` |
| `FOUNDRY_AGENT_ID` | チャットに使用するエージェント ID | `baseline-chatbot-agent` |
| `FOUNDRY_AGENT_VERSION` | エージェントのバージョン | `1` |

---

## 📋 トラブルシューティング

### Q: `deploy.ps1` が失敗した

**A:** 以下を確認してください：

1. Azure CLI でログインしているか
   ```powershell
   az account show
   ```

2. リソースプロバイダーが登録されているか
   ```powershell
   az provider register --namespace Microsoft.CognitiveServices
   az provider register --namespace Microsoft.Search
   az provider register --namespace Microsoft.Storage
   az provider register --namespace Microsoft.Network
   ```

3. 対象リージョンに必要な SKU があるか
   ```powershell
   # 例：PremiumV3 App Service Plan
   az vm list-skus --location southeastasia --resource-type "Microsoft.Web/serverFarms"
   ```

### Q: `setup-foundry-agent.ps1` が失敗した

**A:** 以下を確認してください：

1. `deploy.ps1` がエラーなく完了したか
2. Foundry に直接アクセス可能なネットワークにいるか（ジャンプボックス VM を使用）
3. リソースグループ名が正しいか

### Q: チャットで回答が返ってこない

**A:** 以下を確認してください：

1. App Insights でログを確認
   ```powershell
   az monitor app-insights query \
     --resource-group rg-foundry-chat-baseline-fcb01 \
     --resource-name <app-insights-name> \
     --query "value | [0]"
   ```

2. App Service の環境変数が正しく設定されているか
   ```powershell
   az webapp config appsettings list --name <app-service-name> --resource-group rg-foundry-chat-baseline-fcb01
   ```

---

## 🗑️ リソース削除（クリーンアップ）

すべてのリソースを削除する場合：

```powershell
az group delete --name rg-foundry-chat-baseline-fcb01 --yes
```

⚠️ **注意:** Cosmos DB、Key Vault は `soft-delete` が有効なため、リソースグループ削除後も一定期間残ります。  
完全削除する場合は以下を実行：

```powershell
az keyvault purge --name <key-vault-name> --location southeastasia
az cosmosdb account purge --name <cosmos-db-name> --resource-group <rg> --location southeastasia
```

---

## 📚 参考リンク

- [Microsoft Learn - ベースライン Microsoft Foundry チャットリファレンスアーキテクチャ](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-chat)
- [GitHub - microsoft-foundry-baseline](https://github.com/Azure-Samples/microsoft-foundry-baseline)
- [Foundry Agent Service REST API](https://learn.microsoft.com/rest/api/aifoundry/)
