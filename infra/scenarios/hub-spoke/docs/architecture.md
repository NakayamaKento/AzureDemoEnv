# hub-spoke アーキテクチャ

## 概要
Hub VNet と Spoke VNet をピアリングし、Hub 側でセキュリティ制御と経路制御を集約する構成です。

## 構成図

```mermaid
flowchart LR
  User[利用者/運用者] --> HubVNet[Hub VNet]
  HubVNet --> HubNSG[Network Security Group]
  HubVNet --> HubRT[Route Table]
  HubVNet <-->|VNet Peering| SpokeVNet[Spoke VNet]
  SpokeVNet --> SpokeSubnet[spoke-app Subnet]
  HubVNet --> HubSubnet[hub-app Subnet]
```

## 主要ポイント
- Hub 側に NSG と Route Table を配置して制御点を集約。
- Spoke は最小構成でアプリ用途のサブネットのみ配置。
- リージョン既定値は southwestasia。
