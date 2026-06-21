# SRE Agent Teams Bot 図解 1ページ

このページは、初見の人に 3 分で全体像を伝えるための図解資料です。

## 1. 一言でいうと

Teams で質問した内容を Bot が受け取り、Azure SRE Agent に中継し、調査結果を Teams に返す仕組みです。

## 2. 論理アーキテクチャ

```mermaid
flowchart LR
  User[Teams ユーザー]
  Teams[Microsoft Teams]
  BotSvc[Azure Bot Service<br/>MsTeams Channel]
  BotApp[Azure Container Apps<br/>Node.js Bot]
  Sre[Azure SRE Agent]
  Table[Azure Table Storage<br/>ConversationThreadMap]
  UAMI[User Assigned Managed Identity]
  ACR[Azure Container Registry]
  Obs[Application Insights<br/>Log Analytics]

  User --> Teams --> BotSvc --> BotApp
  BotApp -->|質問を送信| Sre
  Sre -->|回答を返却| BotApp
  BotApp -->|会話IDとスレッドIDを保存| Table
  BotApp -->|コンテナーイメージ取得| ACR
  BotApp -->|テレメトリ送信| Obs

  UAMI -.認証.-> BotApp
  UAMI -.認証.-> Sre
  UAMI -.認証.-> Table
  UAMI -.認証.-> ACR
```

## 3. 会話シーケンス

```mermaid
sequenceDiagram
  autonumber
  participant U as Teams User
  participant T as Teams
  participant B as Bot Service
  participant A as Bot App
  participant S as Table Storage
  participant G as SRE Agent

  U->>T: 質問を送信
  T->>B: Activity
  B->>A: POST /api/messages
  A->>S: conversationId から threadId 取得または作成
  A-->>U: 調査中メッセージを即時返信
  A->>G: メッセージ送信
  loop 3秒間隔で最大120秒
    A->>G: 新しい回答を確認
  end
  G-->>A: 回答
  A-->>T: プロアクティブ返信
  T-->>U: 回答表示
```

## 4. サービス責務マップ

```mermaid
flowchart TB
  subgraph Entry[利用者接点]
    Teams2[Microsoft Teams]
    BotSvc2[Azure Bot Service]
  end

  subgraph Runtime[実行と処理]
    App[Container Apps の Bot]
    Agent[SRE Agent]
  end

  subgraph Data[状態管理]
    Store[Table Storage]
  end

  subgraph Security[認証]
    Id[User Assigned Managed Identity]
  end

  subgraph Ops[運用監視]
    Monitor[App Insights と Log Analytics]
    Repo[ACR]
  end

  Teams2 --> BotSvc2 --> App --> Agent
  App --> Store
  App --> Monitor
  App --> Repo
  Id -.-> App
  Id -.-> Agent
  Id -.-> Store
```

## 5. 代替サービス早見表

| 領域 | 現在 | 代替候補 | 使い分けの目安 |
|---|---|---|---|
| Bot実行基盤 | Container Apps | App Service, Azure Functions, AKS | 小中規模は Container Apps、大規模制御は AKS |
| 会話マッピング | Table Storage | Cosmos DB, Redis | 大規模分散は Cosmos DB、高速キャッシュは Redis |
| AI基盤 | Azure SRE Agent | Azure OpenAI | 汎用対話中心なら Azure OpenAI |
| 認証 | UAMI | Service Principal + Secret | 原則 UAMI を優先 |
| IaC | Bicep | Terraform | マルチクラウド統一要件なら Terraform |

## 6. 説明トーク 60 秒版

1. Teams の質問が Bot Service 経由で Container Apps の Bot に届きます。
2. Bot は会話の対応表を Table Storage で管理し、まず調査中メッセージを即時返信します。
3. 裏で SRE Agent に問い合わせ、回答が出たらプロアクティブに Teams へ返します。
4. 認証は UAMI で統一し、シークレットを持たない運用にしています。
