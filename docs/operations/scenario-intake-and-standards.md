# シナリオ受付と運用標準

## 1) 受付チャネル

### A. GitHub Issue（推奨・既定）
追跡性、レビュー性、チーム可視性を確保するため、基本は GitHub Issue で受け付けます。

手順:
1. `.github/ISSUE_TEMPLATE/scenario-request.yml` から Issue を起票する。
2. `standard` または `adhoc` に分類する。
3. `standard` は `infra/scenarios`、`adhoc` は `infra/custom` に実装する。
4. 検証とドキュメント整備が完了した後に Issue をクローズする。

### B. VS Code ローカル依頼（高速下書き）
打ち合わせ中など即時に下書きしたい場合は、ローカル YAML で受け付けます。

手順:
1. `requests/local/scenario-request.template.yaml` をコピーする。
2. 最小限の必須項目を記入する。
3. 下書き IaC を実装する。
4. 最終化前に監査証跡として GitHub Issue に変換する。

ルール:
- ローカルのみの依頼は暫定扱い。最終採用する依頼は必ず Issue として残す。

## 2) シナリオ分類
- standard: 再利用を見込むシナリオ。`infra/scenarios` で管理。
- adhoc: 単発または再利用未確定のシナリオ。`infra/custom` で管理。

昇格ルール:
- `adhoc` は 2 回以上再利用された場合、または再利用見込みが明確な場合に `standard` へ昇格する。

## 3) パラメータ最小化ポリシー
シナリオの意図を実質的に変える項目のみをパラメータ化します。

基本で許可するパラメータ:
- `scenarioCode`（命名のプレフィックス/サフィックスに使用）
- `location`（既定値 `southwestasia`、上書き可能）

原則としてパラメータ化しない項目:
- 明示要求がない IP 範囲
- 明示要求がないリソース名
- 既定値で安全に判断できる低価値な切り替え項目

## 4) 既定値戦略
- 既定リージョン: `southwestasia`
- 命名: `scenarioCode` + 決定的サフィックスで自動生成
- IP/サブネット: テンプレート変数で安全な内部既定値を使用
- タグ: 標準タグを自動適用

## 5) 品質ゲート（必須）
1. Bicep 検証（`bicep build`）
2. Terraform がある場合の検証（`terraform validate`）
3. Well-Architected 観点のレビュー記録
4. シナリオ README と Mermaid 図
5. AVM 適用状況の記録（適用済み/未適用と理由）

## 5.1) AVM 適用判定ルール
- 新規 Bicep 実装時は、対象リソースに AVM があるかを最初に確認する。
- AVM がある場合は AVM を優先して採用する。
- AVM が使えない場合は、シナリオ README に未適用理由と今後の移行条件を記録する。

## 6) ドキュメント言語ルール
- 本リポジトリのドキュメントは日本語で統一する。
- 例外として、Azure リソース型名、CLI コマンド、コード識別子は原文の英語表記を維持する。

## 7) 自動化ルール
- Issue 作成/更新時は `.github/workflows/issue-auto-label.yml` で `standard` / `adhoc` ラベルを自動付与する。
- 雛形生成は `infra/scripts/new-scenario.ps1` を使用し、受け付け内容を最短で実装可能な状態にする。

## 8) AVM バージョン見直しルール
- AVM 参照バージョンは定期的に見直し、最新タグへ更新する。
- 定期確認は `.github/workflows/avm-version-review.yml` を毎週実行する。
- ローカル確認/更新は `infra/scripts/review-avm-versions.ps1` を使用する。
- 更新結果は `docs/operations/avm-version-review.md` に記録する。
