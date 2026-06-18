# avm-version-review スキル

## 目的
Bicep で参照している Azure Verified Modules (AVM) のバージョンを定期的に確認し、必要に応じて更新する。

## 入力
- 対象ディレクトリ（既定: infra）
- 更新適用の有無（確認のみ / 自動更新）

## 出力
- バージョン確認レポート
- 更新後 Bicep（適用時）
- 変更 PR（GitHub Actions 実行時）

## 実行方法
- ローカル: infra/scripts/review-avm-versions.ps1
- 定期実行: .github/workflows/avm-version-review.yml

## ルール
- AVM 参照は固定タグを使用し、常に最新タグへの更新可否を確認する。
- 更新対象がある場合はレポートへ明記する。
