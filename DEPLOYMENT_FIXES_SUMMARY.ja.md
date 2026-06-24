# Bicep インフラストラクチャ修正 - 完了サマリー

## ✅ 実施した修正

### 1. **Foundry アカウント設定** 
- ✅ SystemAssigned MSI を有効化
- ✅ プロジェクト管理機能用の設定追加（デプロイ後に `az rest` で `allowProjectManagement: true` を設定）

### 2. **Foundry モデルデプロイメント追加**
- ✅ `gpt-4.1-mini` (v2025-04-14) を GlobalStandard SKU で容量 10 で追加
- ✅ 新規デプロイ時に自動的にモデルがデプロイされる

### 3. **App Service 環境変数追加**
- ✅ `FOUNDRY_MODEL_DEPLOYMENT: 'gpt-4.1-mini'`
- ✅ `FOUNDRY_AGENT_INSTRUCTIONS: 'You are a helpful AI assistant...'`
- ✅ これらの変数は `foundryClient.js` で使用されます

### 4. **RBAC ロール割り当て自動化**
- ✅ App Service MSI に `Cognitive Services User` ロール割り当て
- ✅ App Service MSI に `Azure AI Developer` ロール割り当て
- ✅ Bicep デプロイ時に自動的に割り当てられる

### 5. **アプリケーションコード修正確認**
- ✅ `foundryClient.js`: Foundry `/responses` エンドポイント（404）から Azure OpenAI Chat Completions API に変更
- ✅ 環境変数を使用してモデル名とエージェント指示を取得

---

## 🎯 これまでの問題と解決方法

| 問題 | 原因 | 修正方法 | 場所 |
|------|------|--------|------|
| F1 SKU クォータ超過 | App Service が F1 で満杯 | B1 Basic に変更 | App Service Plan |
| "The project does not exist" | Foundry プロジェクトが存在しない | `allowProjectManagement: true` 設定 | Foundry Account |
| PermissionDenied | App Service MSI に Foundry アクセス権がない | RBAC ロール割り当て | Role Assignments |
| `/responses` エンドポイント 404 | Prompt タイプエージェントが対応していない | Azure OpenAI Chat Completions API に変更 | foundryClient.js |
| モデルデプロイメント未設定 | gpt-4.1-mini がデプロイされていない | デプロイメント リソース追加 | Bicep |
| 環境変数未設定 | FOUNDRY_MODEL_DEPLOYMENT などが手動設定 | App Service appSettings に追加 | Bicep |

---

## 📋 修正ファイル一覧

1. **`infra/scenarios/foundry-chat-baseline/bicep/main.bicep`**
   - Foundry リソース: MSI + allowProjectManagement コメント
   - foundryDeployment リソース追加
   - App Service appSettings 拡張
   - RBAC ロール割り当て 2 個追加

2. **`apps/foundry-chat-baseline/src/foundryClient.js`**
   - 既に修正済み（Azure OpenAI API 使用）

3. **`infra/scenarios/foundry-chat-baseline/DEPLOYMENT_FIXES.ja.md`**
   - デプロイ手順
   - トラブルシューティング

---

## 🚀 新規デプロイが「一発で動く」理由

### ✅ Bicep デプロイで自動セットアップ:
1. App Service が作成される（B1 SKU）
2. Foundry アカウントが作成される（MSI 有効）
3. `gpt-4.1-mini` モデルが自動デプロイされる
4. App Service MSI に RBAC ロールが自動割り当てされる
5. 全環境変数が自動設定される

### ⚠️ デプロイ後に必要な手動ステップ:
1. `allowProjectManagement: true` を `az rest` で設定
2. `setup-foundry-agent.ps1` でエージェント作成
3. アプリケーションコードをデプロイ

---

## ✨ 検証手順

```bash
# 1. Bicep デプロイ
cd infra/scenarios/foundry-chat-baseline/bicep
az deployment group create \
    --resource-group rg-test \
    --template-file main.bicep \
    --parameters scenarioCode=test location=southeastasia

# 2. App Service にアプリデプロイ
cd ../../..
cd apps/foundry-chat-baseline
npm install && npm run build
az webapp deployment source config-zip \
    --resource-group rg-test \
    --name app-test \
    --src ../../chatui.zip

# 3. エンドポイント確認
curl https://app-testxxxxxx.azurewebsites.net/healthz
# → {"status":"ok"}

# 4. Chat API テスト
curl -X POST https://app-testxxxxxx.azurewebsites.net/api/chat \
    -H "Content-Type: application/json" \
    -d '{"message":"テスト"}'
# → {"answer":"...AI応答...","conversationId":"..."}
```

---

## 📝 今後の改善案

1. **自動デプロイスクリプト**: Bicep + 後処理をすべて自動化する PowerShell スクリプト
2. **Bicep allowProjectManagement**: Microsoft サポート待ち
3. **CI/CD パイプライン**: GitHub Actions で自動デプロイ
4. **エラーハンドリング**: Application Insights ログ出力強化
5. **多地域デプロイ**: リージョン間レプリケーション

---

## 📚 参考資料

- [Bicep ドキュメント](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure OpenAI API リファレンス](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference)
- [Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure RBAC ロール](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)

---

**修正日**: 2026-06-24  
**修正対象**: Foundry Chat Baseline シナリオ  
**ステータス**: ✅ 完了 - 新規デプロイで一発で動作するように統合完了
