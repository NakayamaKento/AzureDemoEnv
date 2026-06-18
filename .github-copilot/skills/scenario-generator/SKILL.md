# scenario-generator スキル

## 目的
要求内容から standard / adhoc を判定し、最小パラメータの IaC 雛形を生成する。

## 入力
- シナリオ目的
- 必要リソース
- 制約（セキュリティ・コスト・性能・ガバナンス）

## 出力
- Bicep/Terraform 雛形
- 初期 README
- 下書き Mermaid 図

## AVM バージョンルール
- AVM を参照する場合は固定タグで記述する。
- 新規生成時に最新タグを確認してから出力する。
- 既存ファイル更新時は `infra/scripts/review-avm-versions.ps1` の結果を優先する。
