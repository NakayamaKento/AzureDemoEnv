targetScope = 'resourceGroup'

@description('注文処理サービスの Service Group resource ID。')
param rootServiceGroupId string

@description('Prometheus collector VM 名。')
param collectorVmName string

@description('Prometheus collector managed identity 名。')
param collectorIdentityName string

resource collectorVm 'Microsoft.Compute/virtualMachines@2024-11-01' existing = {
  name: collectorVmName
}

resource collectorIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: collectorIdentityName
}

resource collectorVmMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: collectorVm
  properties: {
    targetId: rootServiceGroupId
  }
}

resource collectorIdentityMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: collectorIdentity
  properties: {
    targetId: rootServiceGroupId
  }
}

output membershipNames object = {
  collectorVm: collectorVmMember.name
  collectorIdentity: collectorIdentityMember.name
}
