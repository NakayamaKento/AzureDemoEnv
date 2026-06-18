# VNet 双方向ピアリング（Bilateral VNet Peering）シナリオ

## 概要

このシナリオは、**2つの VNet を双方向でピアリング（相互接続）** するデモンストレーションです。

## 用途

- VNet 間通信のテスト
- ピアリング接続のベストプラクティス確認
- ガバナンスドメイン間の通信デモ

## 構成

```
┌─────────────────────────────┬─────────────────────────────┐
│   Left VNet (10.30.0.0/16)  │  Right VNet (10.40.0.0/16)  │
│   - left-app subnet         │  - right-app subnet         │
│   - governanceDomain: left  │  - governanceDomain: right  │
└────────────────┬────────────┴─────────────┬────────────────┘
                 │                          │
                 └──────────  Peering  ──────┘
                  (Bilateral Connection)
```

## リソース

| リソースタイプ | 個数 | 説明 |
|---|---|---|
| Virtual Network | 2 | Left VNet, Right VNet |
| VNet Peering | 2 | Left→Right, Right→Left（相互接続） |

## デプロイ方法

```bash
az deployment group create \
  --resource-group myResourceGroup \
  --template-file infra/scenarios/vnet-peering-governance/bicep/main.bicep \
  --parameters scenarioCode=csa01 location=southwestasia
```

## 主要パラメータ

| パラメータ | デフォルト | 説明 |
|---|---|---|
| `scenarioCode` | `csa01` | リソース名プレフィックス |
| `location` | `southwestasia` | デプロイリージョン |

## ユースケース

- **マルチテナント環境**: テナント間の VNet ピアリング
- **HUB-SPOKE 検証**: ピアリング接続の基本確認
- **ハイブリッドネットワーク**: オンプレミスと Azure の相互接続テスト
