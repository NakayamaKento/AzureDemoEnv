# infra ディレクトリ

このディレクトリでは Azure デモ環境向け IaC を管理します。

## 構成
- `scenarios/`: 再利用可能な標準シナリオ
- `custom/`: 単発検証シナリオ
- `modules/`: 共通化した再利用モジュール
- `scripts/`: シナリオ作成、検証、レビュー用の補助スクリプト

## 運用方針
- 既定リージョンは `southeastasia`
- 最小パラメータ（`scenarioCode`, `location`）を原則とする
- モジュール追加時は既存シナリオを見直す
- AVM があるリソースは AVM を優先して採用する
- AVM 未適用の理由は対象シナリオの README に記載する
