# SRE Agent + Teams Bot 運用ランブック（初回ユーザー向け）

この文書は、初めて触る人でも次の 3 つを迷わず実行できるように作成しています。

- 新規作成
- テスト
- クリーンアップ（ローカル + Azure + Teams）

対象ディレクトリ:

- infra/custom/sre-agent-teams-poc

---

## 1. まず最初に（5 分で確認）

### 1.1 前提

- Azure CLI が使える
- Azure にログイン済み
- 対象サブスクリプション: 41071e92-3ceb-44a2-a41e-5c5255c5e5b9
- Teams 側でアプリ追加/削除できる権限がある

### 1.2 事前確認コマンド

```powershell
cd infra/custom/sre-agent-teams-poc
az account show --query "{name:name,id:id}" -o table
```

---

## 2. 最短ルート（推奨）

初回ユーザーは、この 1 コマンドだけ実行してください。

```powershell
cd infra/custom/sre-agent-teams-poc
pwsh -File .\reset-and-run-from-zero.ps1 -ScenarioCode poc-v3 -Location koreacentral -AgentLocation eastus2
```

このコマンドが自動で実施すること:

1. ローカル生成物のクリーンアップ
2. 既存の rg-sre-*（既定では rg-sre-prod-* を除外）の削除
3. 新規デプロイ
4. ヘルスチェック
5. Teams 配布 ZIP 生成

補足:

- コンテナーイメージが ACR に無い場合は自動でビルドして再試行します
- ACR 作成直後の DNS 伝播遅延もリトライで吸収します

---

## 3. 成功判定（ここだけ見れば OK）

実行ログで次を確認します。

1. Step 5 で「デプロイ完了」
2. Step 7 で「Container App は Running」
3. Step 8 で「ヘルスチェック成功 (200)」
4. Step 9 で TeamsAppPackage-rg-sre-test-xxxx.zip が出力される

追加確認（任意）:

```powershell
az group list --query "[?starts_with(name, 'rg-sre-test-')].name" -o tsv
```

---

## 4. Teams テスト手順

1. 出力された TeamsAppPackage-rg-sre-test-xxxx.zip を Teams にアップロード
2. Bot へ hello を送信
3. 応答が返ることを確認

期待値:

- 送信に対して Bot から応答が返る
- エンドポイントは /api/messages になっている

---

## 5. クリーンアップ手順

### 5.1 ローカルのみ

```powershell
cd infra/custom/sre-agent-teams-poc
pwsh -File .\cleanup-artifacts.ps1
```

### 5.2 Azure（指定 RG を削除）

```powershell
az account set --subscription 41071e92-3ceb-44a2-a41e-5c5255c5e5b9
az group delete --name <cleanup-target-rg> --yes --no-wait
az group exists --name <cleanup-target-rg>
```

false なら削除完了です。

### 5.3 Teams（手動・必須）

1. Teams クライアントでアプリをアンインストール
2. Teams 管理センターでカスタムアプリを削除
3. 必要なら Developer Portal 側の定義も削除

---

## 6. よく使うオプション

```powershell
# 既存 RG の削除をスキップして新規デプロイだけ実行
pwsh -File .\reset-and-run-from-zero.ps1 -SkipDelete

# rg-sre-prod-* も含めて削除対象にする（要注意）
pwsh -File .\reset-and-run-from-zero.ps1 -IncludeProd
```

---

## 7. よくある失敗と対処

1. MANIFEST_UNKNOWN
- 原因: ACR にタグが無い
- 対処: スクリプトが自動で ACR build -> 再デプロイ

2. ACR の no such host / failed to login
- 原因: ACR 作成直後の DNS 伝播
- 対処: スクリプトが待機してリトライ

3. InvalidApplicationInsightsConfiguration
- 対処: applicationInsightsConfiguration に appId と connectionString を両方設定済み

4. InvalidBotData（Bot 名重複）
- 対処: Bot 名に一意 suffix を付与済み

---

## 8. 日次運用の型（毎回これ）

1. 新規作成
- reset-and-run-from-zero.ps1 を実行

2. テスト
- Teams へ ZIP アップロード -> hello 応答確認

3. クリーンアップ
- cleanup-artifacts.ps1
- 対象 RG 削除
- Teams からアプリ削除

この 1→2→3 を繰り返せば、毎回同じ品質で運用できます。
