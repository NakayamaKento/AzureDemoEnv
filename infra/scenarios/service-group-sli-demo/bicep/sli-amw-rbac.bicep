targetScope = 'resourceGroup'

@description('SLI の source / destination Azure Monitor Workspace 名。')
param azureMonitorWorkspaceName string

@description('SLI が使用する user-assigned managed identity の principal ID。')
param sliManagedIdentityPrincipalId string

var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' existing = {
  name: azureMonitorWorkspaceName
}

resource monitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureMonitorWorkspace.id, sliManagedIdentityPrincipalId, monitoringReaderRoleId)
  scope: azureMonitorWorkspace
  properties: {
    principalId: sliManagedIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
  }
}

resource monitoringMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureMonitorWorkspace.id, sliManagedIdentityPrincipalId, monitoringMetricsPublisherRoleId)
  scope: azureMonitorWorkspace
  properties: {
    principalId: sliManagedIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
  }
}

output azureMonitorWorkspaceName string = azureMonitorWorkspace.name
