# デプロイメント修正ドキュメント

## 概要
これまでの手動トラブルシューティングで発見した問題を Bicep インフラストラクチャに統合し、新規デプロイで「一発で動く」ようにしました。

## 修正内容

### 1. Foundry アカウント設定
**問題**: Foundry プロジェクト作成ができない、App Service MSI からアクセスできない

**修正**:
- ✅ `identity: { type: 'SystemAssigned' }` を追加（Foundry MSI を有効化）
- ✅ `allowProjectManagement: true` を設定（ただし Bicep では未対応、デプロイ後に手動設定が必要）

### 2. Foundry モデルデプロイメント
**問題**: `gpt-4.1-mini` モデルが未デプロイ → API 呼び出し時に 404 エラー

**修正**:
```bicep
resource foundryDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
    name: '${foundry.name}/gpt-4.1-mini'
    properties: {
        model: {
            format: 'OpenAI'
            name: 'gpt-4.1-mini'
            version: '2025-04-14'
        }
        capacitySettings: {
            designatedCapacity: 10
        }
    }
}
```

### 3. App Service 環境変数
**問題**: FOUNDRY_MODEL_DEPLOYMENT と FOUNDRY_AGENT_INSTRUCTIONS が未設定 → foundryClient.js が動作不可

**修正**:
```bicep
{
    name: 'FOUNDRY_MODEL_DEPLOYMENT'
    value: 'gpt-4.1-mini'
}
{
    name: 'FOUNDRY_AGENT_INSTRUCTIONS'
    value: 'You are a helpful AI assistant. Answer questions concisely and helpfully in Japanese when appropriate.'
}
```

### 4. RBAC ロール割り当て
**問題**: App Service MSI が Foundry API にアクセス権がない → PermissionDenied エラー

**修正**:
```bicep
// Cognitive Services User ロール
resource appServiceCognitiveServicesRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    scope: foundry
    properties: {
        roleDefinitionId: subscriptionResourceId(
            'Microsoft.Authorization/roleDefinitions', 
            'a97b65f3-24c7-4388-baec-2e87135dc908'
        )
        principalId: webApp.identity.principalId
        principalType: 'ServicePrincipal'
    }
}

// Azure AI Developer ロール
resource appServiceAzureAiDeveloperRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    scope: foundry
    properties: {
        roleDefinitionId: subscriptionResourceId(
            'Microsoft.Authorization/roleDefinitions', 
            '64702f94-c441-49e6-a78b-ef80e0188fee'
        )
        principalId: webApp.identity.principalId
        principalType: 'ServicePrincipal'
    }
}
```

### 5. アプリケーションコード
**変更**: `foundryClient.js`
- Foundry `/responses` エンドポイント（prompt タイプで 404）から Azure OpenAI Chat Completions API に変更
- 環境変数 `FOUNDRY_MODEL_DEPLOYMENT` を使用してモデル名を取得
- 環境変数 `FOUNDRY_AGENT_INSTRUCTIONS` を使用してシステムプロンプトを取得

**ファイル**: `apps/foundry-chat-baseline/src/foundryClient.js`

## デプロイ手順

### 前提条件
```bash
# Azure CLI でログイン
az login
az account set --subscription <SubscriptionId>
```

### Bicep デプロイ
```bash
cd infra/scenarios/foundry-chat-baseline/bicep

# 1. デプロイメントプレビュー（what-if）
az deployment group what-if \
    --resource-group rg-foundry-chat-baseline-fcb01 \
    --template-file main.bicep \
    --parameters scenarioCode=fcb01 location=southeastasia

# 2. 実際のデプロイ
az deployment group create \
    --resource-group rg-foundry-chat-baseline-fcb01 \
    --template-file main.bicep \
    --parameters scenarioCode=fcb01 location=southeastasia
```

### デプロイ後の追加手順

#### 1. allowProjectManagement 有効化
```powershell
# リソース情報の取得
$rgName = "rg-foundry-chat-baseline-fcb01"
$foundryName = "aiffcb01xxxxx"  # Bicep デプロイから出力
$subscriptionId = (az account show --query id -o tsv)

# PATCH で allowProjectManagement を有効化
az rest --method PATCH \
    --url "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.CognitiveServices/accounts/$foundryName?api-version=2024-10-01" \
    --body "{\"properties\":{\"allowProjectManagement\":true}}"
```

#### 2. Foundry プロジェクト作成
```powershell
# プロジェクト作成スクリプトを実行
# ファイル: setup-foundry-agent.ps1
.\setup-foundry-agent.ps1 -ResourceGroup $rgName -FoundryName $foundryName
```

#### 3. アプリケーションデプロイ
```bash
# アプリケーションコードをビルドしてデプロイ
cd apps/foundry-chat-baseline
npm install
npm run build

# App Service にデプロイ
az webapp deployment source config-zip \
    --resource-group rg-foundry-chat-baseline-fcb01 \
    --name app-fcb01xxxxx \
    --src chatui.zip
```

## 検証チェックリスト

- [ ] Foundry アカウントが SystemAssigned MSI を持っている
- [ ] Foundry に `gpt-4.1-mini` モデルデプロイメントが存在
- [ ] App Service に以下の環境変数が設定されている：
  - [ ] `FOUNDRY_PROJECT_ENDPOINT`
  - [ ] `FOUNDRY_AGENT_ID`
  - [ ] `FOUNDRY_AGENT_VERSION`
  - [ ] `FOUNDRY_MODEL_DEPLOYMENT`
  - [ ] `FOUNDRY_AGENT_INSTRUCTIONS`
- [ ] App Service MSI が Foundry のロール割り当てで以下を持っている：
  - [ ] Cognitive Services User
  - [ ] Azure AI Developer
- [ ] Health エンドポイントが正常（`GET /healthz` → 200 OK）
- [ ] Chat API が動作（`POST /api/chat` → 200 + JSON レスポンス）

## トラブルシューティング

### エラー: "The project does not exist"
→ `allowProjectManagement` が有効化されていない、または Foundry プロジェクトが作成されていない

**解決**:
```powershell
# 有効化確認
az rest --method GET \
    --url "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.CognitiveServices/accounts/$foundryName?api-version=2024-10-01" \
    --query "properties.allowProjectManagement"
```

### エラー: "PermissionDenied"
→ App Service MSI に RBAC ロールが割り当てられていない

**解決**: 
```bash
# ロール割り当て確認
az role assignment list \
    --resource-group rg-foundry-chat-baseline-fcb01 \
    --scope "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.CognitiveServices/accounts/$foundryName"
```

### エラー: "Model not found" または 404
→ `gpt-4.1-mini` モデルデプロイメントが存在しない

**解決**:
```bash
# モデルデプロイメント確認
az cognitiveservices account deployment list \
    --resource-group rg-foundry-chat-baseline-fcb01 \
    --name aiffcb01xxxxx
```

## 今後の改善

1. **Bicep での allowProjectManagement 設定**: Microsoft が Bicep サポートを追加するまで待つ、または Terraform / ARM template を使用
2. **自動デプロイスクリプト**: 上記すべての手順を自動化する PowerShell スクリプト作成
3. **Application Insights 統合**: エラーログの可視化強化
4. **多言語サポート**: FOUNDRY_AGENT_INSTRUCTIONS を パラメータ化

## 参考資料

- [Azure OpenAI Chat Completions API](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#chat-completions)
- [Azure AI Foundry エージェント](https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/agents)
- [Bicep リソースリファレンス](https://learn.microsoft.com/en-us/azure/templates/)
