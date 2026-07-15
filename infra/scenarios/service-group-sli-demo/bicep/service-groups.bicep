targetScope = 'tenant'

@description('生成される Service Group 名に使用するシナリオコード。例: sgsli01')
param scenarioCode string = 'sgsli01'

@description('既存 Service Group 配下にぶら下げる場合の親 Service Group resource ID。空の場合はテナント直下に作成。')
param parentServiceGroupResourceId string = ''

var normalizedScenarioCode = toLower(replace(scenarioCode, '-', ''))
var rootServiceGroupName = 'sg-${normalizedScenarioCode}-order-service'
var apiServiceGroupName = 'sg-${normalizedScenarioCode}-api'
var processingServiceGroupName = 'sg-${normalizedScenarioCode}-processing'
var dataServiceGroupName = 'sg-${normalizedScenarioCode}-data'
var observabilityServiceGroupName = 'sg-${normalizedScenarioCode}-observability'
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

resource apiServiceGroup 'Microsoft.Management/serviceGroups@2024-02-01-preview' = {
  name: apiServiceGroupName
  tags: tags
  properties: {
    displayName: 'エントリ/API'
    parent: {
      resourceId: rootServiceGroup.id
    }
  }
}

resource processingServiceGroup 'Microsoft.Management/serviceGroups@2024-02-01-preview' = {
  name: processingServiceGroupName
  tags: tags
  properties: {
    displayName: '注文処理'
    parent: {
      resourceId: rootServiceGroup.id
    }
  }
}

resource dataServiceGroup 'Microsoft.Management/serviceGroups@2024-02-01-preview' = {
  name: dataServiceGroupName
  tags: tags
  properties: {
    displayName: 'データストア'
    parent: {
      resourceId: rootServiceGroup.id
    }
  }
}

resource observabilityServiceGroup 'Microsoft.Management/serviceGroups@2024-02-01-preview' = {
  name: observabilityServiceGroupName
  tags: tags
  properties: {
    displayName: '観測基盤'
    parent: {
      resourceId: rootServiceGroup.id
    }
  }
}

output serviceGroupNames object = {
  root: rootServiceGroup.name
  api: apiServiceGroup.name
  processing: processingServiceGroup.name
  data: dataServiceGroup.name
  observability: observabilityServiceGroup.name
}

output serviceGroupIds object = {
  root: rootServiceGroup.id
  api: apiServiceGroup.id
  processing: processingServiceGroup.id
  data: dataServiceGroup.id
  observability: observabilityServiceGroup.id
}
