targetScope = 'tenant'

@description('生成される Service Group 名に使用するシナリオコード。例: sgsli01')
param scenarioCode string = 'sgsli01'

@description('既存 Service Group 配下にぶら下げる場合の親 Service Group resource ID。空の場合はテナント直下に作成。')
param parentServiceGroupResourceId string = ''

var normalizedScenarioCode = toLower(replace(scenarioCode, '-', ''))
var rootServiceGroupName = 'sg-${normalizedScenarioCode}-order-service'
var defaultRootServiceGroupResourceId = '/providers/Microsoft.Management/serviceGroups/${tenant().tenantId}'
var rootParentServiceGroupResourceId = empty(parentServiceGroupResourceId) ? defaultRootServiceGroupResourceId : parentServiceGroupResourceId
var tags = {
  scenario: 'service-group-sli-demo'
  scenarioCode: scenarioCode
  workload: 'order-processing'
}
var rootProperties = {
  displayName: '注文処理サービス'
  parent: {
    resourceId: rootParentServiceGroupResourceId
  }
}

resource rootServiceGroup 'Microsoft.Management/serviceGroups@2024-02-01-preview' = {
  name: rootServiceGroupName
  tags: tags
  properties: rootProperties
}

output serviceGroupNames object = {
  root: rootServiceGroup.name
}

output serviceGroupIds object = {
  root: rootServiceGroup.id
}
