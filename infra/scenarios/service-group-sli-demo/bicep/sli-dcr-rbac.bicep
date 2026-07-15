targetScope = 'resourceGroup'

@description('Azure Monitor Workspace が自動生成した既定 Data Collection Rule 名。')
param defaultDataCollectionRuleName string

@description('SLI が使用する user-assigned managed identity の principal ID。')
param sliManagedIdentityPrincipalId string

var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource defaultDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: defaultDataCollectionRuleName
}

resource monitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(defaultDataCollectionRule.id, sliManagedIdentityPrincipalId, monitoringReaderRoleId)
  scope: defaultDataCollectionRule
  properties: {
    principalId: sliManagedIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
  }
}

resource monitoringMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(defaultDataCollectionRule.id, sliManagedIdentityPrincipalId, monitoringMetricsPublisherRoleId)
  scope: defaultDataCollectionRule
  properties: {
    principalId: sliManagedIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
  }
}

output defaultDataCollectionRuleName string = defaultDataCollectionRule.name
