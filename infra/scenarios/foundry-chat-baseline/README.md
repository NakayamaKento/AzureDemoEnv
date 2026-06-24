# Foundry チャット ベースラインシナリオ

## 概要

このシナリオは、Microsoft Learn の「ベースライン Microsoft Foundry チャットリファレンスアーキテクチャ」を土台に、AzureDemoEnv 向けに **最小パラメータ** で実装した標準シナリオです。

この実装では、次の要素をデプロイします。

- Azure Application Gateway (WAF_v2)
- App Service (Linux / Node.js)
- Microsoft Foundry (Azure AI Services)
- Azure Cosmos DB (Serverless)
- Azure AI Search
- Azure Storage
- Log Analytics / Application Insights
- VNet + サブネット + NSG

## 用途

- Foundry Agent Service ベースのチャットワークロード検証
- WAF + App Service フロントのセキュア公開パターン確認
- Foundry 連携アプリの最小 PoC 立ち上げ

## 🚀 クイックスタート（推奨）

**5分でチャットアプリが動く自動スクリプト方式です。**

詳細ガイド → [**QUICK_START.md**](./QUICK_START.md)

```powershell
# ステップ 1: インフラ＋アプリのワンストップデプロイ（10～15分）
.\deploy.ps1 -ScenarioCode fcb01 -Location southeastasia

# ステップ 2: Foundry エージェント作成
.\setup-foundry-agent.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01

# ステップ 3: App Service 環境変数を更新して完成
.\update-app-settings.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01 -AgentId baseline-chatbot-agent -AgentVersion 1
```

### 実装内容（スクリプト経由）

| スクリプト | 実施内容 |
|---|---|
| `deploy.ps1` | ✓ リソースグループ作成 ✓ Bicep インフラデプロイ ✓ npm install ✓ App Service へ zip デプロイ |
| `setup-foundry-agent.ps1` | ✓ Foundry エージェント作成 ✓ 接続設定 ✓ エージェント ID 取得 |
| `update-app-settings.ps1` | ✓ 環境変数設定（Foundry 情報） ✓ App Service 再起動 |

---

## デプロイ方法

### 方式 1: 自動スクリプト（推奨）

[QUICK_START.md](./QUICK_START.md) を参照してください。

### 方式 2: 手動 Azure CLI コマンド

```bash
az deployment group create \
  --resource-group myResourceGroup \
  --template-file infra/scenarios/foundry-chat-baseline/bicep/main.bicep \
  --parameters scenarioCode=fcb01 location=southeastasia
```

## 主要パラメータ

| パラメータ | デフォルト | 説明 |
|---|---|---|
| `scenarioCode` | `fcb01` | リソース名プレフィックス |
| `location` | `southeastasia` | デプロイリージョン |

## AVM 適用状況

### 適用済み（このシナリオで AVM を使用）

- `br/public:avm/res/network/public-ip-address`（Application Gateway Public IP）
- `br/public:avm/res/network/network-security-group`（App Gateway / App Service サブネット NSG）

### 未適用（現時点でインライン維持）

- Virtual Network
  - 理由: サブネット構成（委任、PE 用サブネット無効化）を含む依存を明示しやすいため
  - 移行条件: VNet + Subnet 定義を AVM 入力へ安全にマッピングできることを検証後
- Application Gateway
  - 理由: バックエンドプローブ、ルーティング規則、WAF チューニングの制御を優先
  - 移行条件: 運用ルールセットが固まり、AVM で同等設定を検証できた時点
- App Service / Foundry / Cosmos / Search / Storage
  - 理由: このリポジトリの既存検証履歴で一部 AVM モジュールの `bicep build` 安定性に課題があったため、まずは確実にデプロイ可能なインライン実装を優先
  - 移行条件: AVM バージョン見直しで安定版を確認し、段階適用を再実施

## Well-Architected の反映ポイント

- Reliability: 監視基盤（Log Analytics + App Insights）を標準搭載
- Security: WAF 有効化、NSG 適用、TLS 1.2 以上、Storage の公開アクセス禁止
- Cost: 最小構成（単一リージョン、Search/Cosmos の最小 SKU）
- Operational Excellence: シナリオコードによる命名一貫性、IaC 一元管理
- Performance Efficiency: App Service PremiumV3 で安定稼働を優先

## アプリケーションコード

- チャット UI / API コード: `apps/foundry-chat-baseline`
- App Service にデプロイする前提の Node.js サンプルです。

## スクリプトの詳細

### deploy.ps1 - インフラ＋アプリ展開

**実施内容：**
```
[1/5] Azure 認証・サブスクリプション確認
[2/5] リソースグループ作成
[3/5] Bicep インフラをデプロイ（VNet, App Service, Foundry, Storage, Cosmos DB, Search, App Gateway）
[4/5] チャットアプリの npm install と App Service へのデプロイ
[5/5] 完了メッセージと次のステップを表示
```

**パラメータ：**

| パラメータ | デフォルト | 説明 |
|---|---|---|
| `-ScenarioCode` | `fcb01` | リソース名プレフィックス |
| `-Location` | `southeastasia` | デプロイリージョン |
| `-ResourceGroup` | `rg-foundry-chat-baseline-<code>` | リソースグループ名 |
| `-SubscriptionId` | 現在のコンテキスト | 対象サブスクリプション ID |

### setup-foundry-agent.ps1 - Foundry エージェント作成

**実施内容：**
```
[1/3] Foundry リソース情報取得
[2/3] Foundry 接続設定（Bing, モデル）
[3/3] Foundry にエージェントを作成し、ID とバージョンを出力
```

**パラメータ：**

| パラメータ | 必須 | 説明 |
|---|---|---|
| `-ResourceGroup` | ✓ | `deploy.ps1` で作成したリソースグループ名 |
| `-ScenarioCode` | - | `deploy.ps1` と同じコード（デフォルト: fcb01） |
| `-FoundryProjectName` | - | Foundry プロジェクト名（デフォルト: projchat） |

### update-app-settings.ps1 - App Service 環境変数設定

**実施内容：**
```
[1/3] App Service 検索
[2/3] Foundry リソース情報取得
[3/3] 環境変数を設定して App Service 再起動
```

**パラメータ：**

| パラメータ | 必須 | 説明 |
|---|---|---|
| `-ResourceGroup` | ✓ | `deploy.ps1` で作成したリソースグループ名 |
| `-AppServiceName` | - | App Service 名（省略時は自動検索） |
| `-AgentId` | ✓ | `setup-foundry-agent.ps1` で出力されたエージェント ID |
| `-AgentVersion` | ✓ | `setup-foundry-agent.ps1` で出力されたバージョン |

**設定される環境変数：**

| 環境変数 | 説明 |
|---|---|
| `FOUNDRY_PROJECT_ENDPOINT` | Foundry の API エンドポイント `https://<foundry-name>.services.ai.azure.com/api/projects/projchat` |
| `FOUNDRY_AGENT_ID` | チャットに使用するエージェント ID |
| `FOUNDRY_AGENT_VERSION` | エージェントのバージョン |

## 次のステップ

1. Foundry プロジェクト/エージェントを作成し、環境変数へ設定
2. App Gateway を HTTPS 化（証明書を Key Vault 管理へ移行）
3. Private Endpoint と Firewall を追加してネットワーク分離を強化
