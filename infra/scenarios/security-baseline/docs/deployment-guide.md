# security-baseline デプロイガイド

## 前提条件
- Azure CLI が利用可能
- デプロイ先リソースグループが作成済み
- 対象サブスクリプションへログイン済み

## デプロイ

```powershell
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file infra/scenarios/security-baseline/bicep/main.bicep \
  --parameters scenarioCode=csa01 location=southwestasia
```

## 主要パラメータ
- scenarioCode: 命名に使用する短いコード
- location: デプロイリージョン（既定: southwestasia）

## 検証例

```powershell
az network nsg list --resource-group <resource-group-name> -o table
az network route-table list --resource-group <resource-group-name> -o table
```
