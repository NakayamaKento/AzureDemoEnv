# well-architected-checker スキル

## 目的
IaC を Well-Architected 5本柱の観点で確認し、改善提案を出す。

## 観点
- 信頼性
- セキュリティ
- コスト最適化
- 運用効率
- パフォーマンス効率

## 出力
- 指摘一覧
- 修正候補
- 残リスク

## AVM 確認
- Bicep が AVM を参照する場合、固定タグの妥当性を確認する。
- 定期確認結果は `docs/operations/avm-version-review.md` を参照する。
