# HUB-SPOKE マルチスポークネットワークシナリオ

## 概要

このシナリオは、**Azure Firewall と Azure Bastion を備えた Hub-Spoke ネットワークトポロジー** のデモンストレーションです。複数のスポークをサポートし、一元化されたセキュリティとアクセス管理を実現します。

## 用途

- エンタープライズネットワークアーキテクチャのデモ
- 中央ファイアウォール経由のトラフィック制御
- Bastion による安全な RDP/SSH アクセス
- マルチスポーク VNet 管理

## 構成

```
                    ┌─────────────────────────┐
                    │   Azure Bastion (Basic) │
                    │   10.10.1.0/27          │
                    └────────────┬────────────┘
                                 │ (RDP/SSH Gateway)
                    ┌────────────▼────────────┐
        ┌───────────┤  Hub VNet 10.10.0.0/16 ├──────────┐
        │           │                        │          │
        │           │ ┌────────────────────┐ │          │
        │           │ │ Azure Firewall     │ │          │
        │           │ │ 10.10.0.4          │ │          │
        │           │ │ (Standard tier)    │ │          │
        │           │ └────────────────────┘ │          │
        │           │                        │          │
        │           │ ┌────────────────────┐ │          │
        │           │ │ GatewaySubnet      │ │          │
        │           │ │ 10.10.1.32/27      │ │          │
        │           │ │ (VPN ready)        │ │          │
        │           │ └────────────────────┘ │          │
        │           │                        │          │
        │           │ ┌────────────────────┐ │          │
        │           │ │ hub-app Subnet     │ │          │
        │           │ │ 10.10.2.0/24       │ │          │
        │           │ └────────────────────┘ │          │
        │           └────────────────────────┘          │
        │                                               │
    ┌───▼──────────┐                          ┌────────▼────┐
    │ Spoke 0      │                          │ Spoke 1     │
    │ 10.20.0.0/16 │                          │ 10.21.0.0/16│
    │              │                          │             │
    │ • Windows VM │ (Peering with UDR)      │ • Windows VM│
    │ • Linux VM   │◄─────────────────────────►│ • Linux VM │
    │ • Route→FW   │                          │ • Route→FW  │
    └──────────────┘                          └─────────────┘
          △                                           △
          │                                           │
          └───────────────┬──────────────────────────┘
                          │
                 (Default route 0.0.0.0/0
                  → Firewall 10.10.0.4)
```

## リソース（デフォルト: 2スポーク）

| リソースタイプ | 個数 | 説明 |
|---|---|---|
| Virtual Networks | 3（Hub + Spoke数） | Hub VNet + Spoke VNets |
| Azure Firewall | 1 | Standard tier，Public IP 付き |
| Azure Bastion | 1 | Basic SKU |
| Virtual Machines | Spoke数×2 | 各Spoke に Windows + Linux 1台ずつ |
| Network Interfaces | Spoke数×2 | VM用 NIC |
| Route Tables | Spoke数 | UDR（Spoke サブネット用） |
| Network Security Groups | 3 | Hub NSG + Firewall NSG + Bastion NSG |
| VNet Peering | Spoke数×2 | Hub ↔ Spoke（相互接続） |
| Public IP | 1 | Firewall 用 |

## サブネット構成

### Hub VNet (10.10.0.0/16)

| サブネット | CIDR | 用途 |
|---|---|---|
| AzureFirewallSubnet | 10.10.0.0/26 | Firewall **必須** |
| AzureBastionSubnet | 10.10.1.0/27 | Bastion **必須** |
| GatewaySubnet | 10.10.1.32/27 | VPN Gateway（将来用） |
| hub-app | 10.10.2.0/24 | Hub 内リソース |

### Spoke VNets

- **Spoke 0**: 10.20.0.0/16（app サブネット: 10.20.1.0/24）
- **Spoke 1**: 10.21.0.0/16（app サブネット: 10.21.1.0/24）
- Spoke数パラメータで 1-4 個をサポート（デフォルト: 2）

## デプロイ方法

### デフォルト構成（2スポーク）

```bash
az deployment group create \
  --resource-group myResourceGroup \
  --template-file infra/scenarios/hub-spoke/bicep/main.bicep \
  --parameters scenarioCode=csa01 location=southwestasia
```

### カスタムスポーク数（1-4）

```bash
az deployment group create \
  --resource-group myResourceGroup \
  --template-file infra/scenarios/hub-spoke/bicep/main.bicep \
  --parameters scenarioCode=csa01 location=southwestasia spokeCount=3
```

## 主要パラメータ

| パラメータ | デフォルト | 範囲 | 説明 |
|---|---|---|---|
| `scenarioCode` | `csa01` | - | リソース名プレフィックス |
| `location` | `southwestasia` | - | デプロイリージョン |
| `spokeCount` | `2` | 1-4 | スポーク数（VM ペア数） |
| `firewallPrivateIp` | `10.10.0.4` | - | Firewall Private IP |

## 主要機能

### 🔒 セキュリティ

- **Azure Firewall**: 一元化されたトラフィック制御
- **NSG ルール**: Bastion/Firewall 用の許可ルール
- **UDR**: すべてのアウトバウンドを Firewall 経由（0.0.0.0/0）

### 🚪 アクセス管理

- **Azure Bastion**: RDP/SSH の安全なゲートウェイ（Public IP 不要）
- **Private VMs**: Bastion 経由でのみアクセス可能

### 📊 トラフィックフロー

1. **Spoke-to-Spoke**: Spoke VM → UDR（0.0.0.0/0）→ Firewall → 相手 Spoke
2. **Spoke-to-Internet**: Spoke VM → Firewall → Internet
3. **Hub-to-Spoke**: Hub → Peering → Spoke
4. **管理アクセス**: Client → Bastion（Public IP） → VM（Private IP）

## ユースケース

- **エンタープライズ HUB-SPOKE**: 多数の部門/環境を一元管理
- **マルチテナント**: 各テナント = 各 Spoke
- **セキュアクラウド環境**: Firewall による全トラフィック監視
- **ハイブリッド接続**: Hub の GatewaySubnet で VPN/ExpressRoute を接続
- **CSA デモ**: クラウドセキュリティアーキテクチャのショーケース

## 次のステップ

1. **Firewall ルール設定**: Spoke 間のトラフィック許可ルール追加
2. **VPN/ExpressRoute 接続**: GatewaySubnet に VPN Gateway をデプロイ
3. **ログ集約**: Application Insights/Log Analytics で監視
4. **DDoS Protection**: Standard プラン追加でネットワーク層の保護
5. **UDR 最適化**: 実ネットワークに合わせてルート調整
