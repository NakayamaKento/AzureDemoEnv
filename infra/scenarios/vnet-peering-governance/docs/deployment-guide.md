# vnet-peering-governance デプロイガイド

## 前提条件
- Azure CLI が利用可能
- デプロイ先リソースグループが作成済み
- 対象サブスクリプションへログイン済み

## デプロイ

```powershell
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file infra/scenarios/vnet-peering-governance/bicep/main.bicep \
  --parameters scenarioCode=csa01 location=southwestasia
```

## 主要パラメータ
- scenarioCode: 命名に使用する短いコード
- location: デプロイリージョン（既定: southwestasia）

## 補足
- Azure Policy は subscription スコープで別テンプレートとして適用してください。
