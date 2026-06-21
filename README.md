# AzureDemoEnv

CSA向けの Azure デモ環境および検証環境を運用するためのリポジトリです。

## 依頼の受付チャネル
- 追跡可能な依頼: シナリオ依頼テンプレートを使った GitHub Issue
- すぐに下書きする依頼: VS Code ローカル YAML で起票し、承認後に Issue へ同期

## 基本方針
- AVM 優先の IaC 設計
- パラメータ最小化テンプレート
- 既定リージョンは `southwestasia`（必要時のみ上書き可）
- 再利用モジュール追加時は既存シナリオを見直す
- AVM 未適用の判断はシナリオ README に理由と移行条件を記録する

## 参照ドキュメント
- docs/operations/scenario-intake-and-standards.md
- docs/operations/module-refactor-policy.md
