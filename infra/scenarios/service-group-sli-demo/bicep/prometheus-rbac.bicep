targetScope = 'subscription'

@description('Prometheus collector managed identity の principal ID。')
param collectorIdentityPrincipalId string

@description('Azure Monitor Workspace が自動生成した既定 Data Collection Rule resource ID。')
param defaultDataCollectionRuleResourceId string

var dcrSegments = split(defaultDataCollectionRuleResourceId, '/')

module dcrRbac 'prometheus-dcr-rbac.bicep' = {
  name: 'prometheus-dcr-rbac-${uniqueString(defaultDataCollectionRuleResourceId, collectorIdentityPrincipalId)}'
  scope: resourceGroup(dcrSegments[2], dcrSegments[4])
  params: {
    collectorIdentityPrincipalId: collectorIdentityPrincipalId
    defaultDataCollectionRuleName: last(dcrSegments)
  }
}

output defaultDataCollectionRuleName string = dcrRbac.outputs.defaultDataCollectionRuleName
