targetScope = 'subscription'

@description('SLI が使用する user-assigned managed identity の principal ID。')
param sliManagedIdentityPrincipalId string

@description('SLI の source / destination Azure Monitor Workspace resource ID。')
param azureMonitorWorkspaceResourceId string

@description('Azure Monitor Workspace が自動生成した既定 Data Collection Rule resource ID。')
param defaultDataCollectionRuleResourceId string

var amwSegments = split(azureMonitorWorkspaceResourceId, '/')
var dcrSegments = split(defaultDataCollectionRuleResourceId, '/')

module amwRbac 'sli-amw-rbac.bicep' = {
  name: 'sli-amw-rbac-${uniqueString(azureMonitorWorkspaceResourceId, sliManagedIdentityPrincipalId)}'
  scope: resourceGroup(amwSegments[2], amwSegments[4])
  params: {
    azureMonitorWorkspaceName: last(amwSegments)
    sliManagedIdentityPrincipalId: sliManagedIdentityPrincipalId
  }
}

module dcrRbac 'sli-dcr-rbac.bicep' = {
  name: 'sli-dcr-rbac-${uniqueString(defaultDataCollectionRuleResourceId, sliManagedIdentityPrincipalId)}'
  scope: resourceGroup(dcrSegments[2], dcrSegments[4])
  params: {
    defaultDataCollectionRuleName: last(dcrSegments)
    sliManagedIdentityPrincipalId: sliManagedIdentityPrincipalId
  }
}

output azureMonitorWorkspaceName string = amwRbac.outputs.azureMonitorWorkspaceName
output defaultDataCollectionRuleName string = dcrRbac.outputs.defaultDataCollectionRuleName
