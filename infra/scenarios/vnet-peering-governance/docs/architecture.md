# vnet-peering-governance アーキテクチャ

## 概要
2つの VNet を双方向ピアリングし、将来的な Policy 適用を前提としたガバナンス境界をタグで明示する構成です。

## 構成図

```mermaid
flowchart LR
  LeftVNet[Left VNet\n(governanceDomain=left)] <-->|VNet Peering| RightVNet[Right VNet\n(governanceDomain=right)]
  LeftVNet --> LeftSubnet[left-app Subnet]
  RightVNet --> RightSubnet[right-app Subnet]
  Policy[Subscription Scope Policy\n(別デプロイ)] -. 適用 .-> LeftVNet
  Policy -. 適用 .-> RightVNet
```

## 主要ポイント
- ピアリングは Bicep 内で構成。
- ガバナンスはサブスクリプションスコープで別デプロイ。
- 既定リージョンは southwestasia。
