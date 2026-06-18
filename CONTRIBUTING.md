# 貢献ガイド

## 基本ルール
- ドキュメントは日本語で記述します。
- Azure リソース型名、CLI コマンド、コード識別子は英語表記を維持します。
- IaC は AVM 優先で実装します。
- パラメータは最小化し、既定値で安全に運用できる設計を優先します。

## シナリオ追加手順
1. `Scenario Request` Issue を起票します。
2. `standard` か `adhoc` を分類します。
3. 実装後に `bicep build` / `terraform validate`（該当時）を実行します。
4. README と Mermaid 図を追加します。

## レビュー観点
- Well-Architected 5本柱に反していないか
- 既存モジュールへ置換可能な重複がないか
- 不要なパラメータを増やしていないか
