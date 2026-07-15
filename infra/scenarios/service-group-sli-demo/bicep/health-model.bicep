targetScope = 'resourceGroup'

type WorkloadResourceIds = {
  webApp: string
  functionApp: string
  serviceBusNamespace: string
  serviceBusQueue: string
  cosmosAccount: string
  storageAccount: string
  appConfiguration: string
  applicationInsights: string
  logAnalytics: string
  azureMonitorWorkspace: string
}

@description('main.bicep の出力 azureMonitorWorkspaceName。')
param azureMonitorWorkspaceName string

@description('main.bicep の出力 logAnalyticsName。')
param logAnalyticsName string

@description('Service Group root resource ID。enableServiceGroupDiscovery=true の場合に discovery scope として利用。')
param rootServiceGroupId string

@description('Health Model の Service Group discovery を有効化するか。preview API の環境差を避けるため既定は false。')
param enableServiceGroupDiscovery bool = false

@description('main.bicep の出力 workloadResourceIds。')
param workloadResourceIds WorkloadResourceIds

@description('Service Bus queue metric の EntityName dimension filter。')
param serviceBusQueueName string = 'orders'

@description('Health Model のリージョン。')
param location string = resourceGroup().location

var tags = {
  scenario: 'service-group-sli-demo'
  workload: 'order-processing'
}
var healthModelName = 'OrderServiceHealth'
var authSettingName = 'SystemAssignedAuth'
var monitoringReaderRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7'
)

resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' existing = {
  name: azureMonitorWorkspaceName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

resource healthModel 'Microsoft.Monitor/accounts/healthmodels@2025-05-03-preview' = {
  parent: azureMonitorWorkspace
  name: healthModelName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: enableServiceGroupDiscovery ? {
    discovery: {
      addRecommendedSignals: 'Disabled'
      identity: 'SystemAssigned'
      scope: rootServiceGroupId
    }
  } : {}
}

// Health Model の system-assigned identity が、同じ Resource Group 内の
// Log Analytics と Azure resource metrics を読み取るために必要。
resource healthModelMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, healthModel.id, monitoringReaderRoleDefinitionId)
  properties: {
    principalId: healthModel.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: monitoringReaderRoleDefinitionId
  }
}

resource authSetting 'Microsoft.Monitor/accounts/healthmodels/authenticationsettings@2025-05-03-preview' = {
  parent: healthModel
  name: authSettingName
  properties: {
    authenticationKind: 'ManagedIdentity'
    displayName: 'Health Model system-assigned identity'
    managedIdentityName: 'SystemAssigned'
  }
}

resource apiFailureRateSignal 'Microsoft.Monitor/accounts/healthmodels/signaldefinitions@2025-05-03-preview' = {
  parent: healthModel
  name: 'ApiFailureRate'
  properties: {
    dataUnit: 'Percent'
    displayName: 'API failure rate'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '5'
      }
      unhealthyRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '20'
      }
    }
    queryText: '''
AppRequests
| where TimeGenerated > ago(10m)
| summarize FailureRate = iff(count() == 0, 0.0, 100.0 * countif(Success == false) / count())
'''
    refreshInterval: 'PT1M'
    signalKind: 'LogAnalyticsQuery'
    timeGrain: 'PT10M'
    valueColumnName: 'FailureRate'
  }
}

resource apiLatencySignal 'Microsoft.Monitor/accounts/healthmodels/signaldefinitions@2025-05-03-preview' = {
  parent: healthModel
  name: 'ApiLatencyP95'
  properties: {
    dataUnit: 'MilliSeconds'
    displayName: 'API p95 latency'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '750'
      }
      unhealthyRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '1500'
      }
    }
    queryText: '''
AppRequests
| where TimeGenerated > ago(10m)
| summarize LatencyMs = percentile(DurationMs, 95)
'''
    refreshInterval: 'PT1M'
    signalKind: 'LogAnalyticsQuery'
    timeGrain: 'PT10M'
    valueColumnName: 'LatencyMs'
  }
}

resource workerFailureSignal 'Microsoft.Monitor/accounts/healthmodels/signaldefinitions@2025-05-03-preview' = {
  parent: healthModel
  name: 'WorkerFailures'
  properties: {
    dataUnit: 'Count'
    displayName: 'Worker exceptions'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '1'
      }
      unhealthyRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '5'
      }
    }
    queryText: '''
AppExceptions
| where TimeGenerated > ago(10m)
| summarize ExceptionCount = count()
'''
    refreshInterval: 'PT1M'
    signalKind: 'LogAnalyticsQuery'
    timeGrain: 'PT10M'
    valueColumnName: 'ExceptionCount'
  }
}

resource queueDepthSignal 'Microsoft.Monitor/accounts/healthmodels/signaldefinitions@2025-05-03-preview' = {
  parent: healthModel
  name: 'QueueDepth'
  properties: {
    aggregationType: 'Maximum'
    dataUnit: 'Count'
    dimension: 'EntityName'
    dimensionFilter: serviceBusQueueName
    displayName: 'Service Bus active messages'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '10'
      }
      unhealthyRule: {
        operator: 'GreaterThanOrEqual'
        threshold: '50'
      }
    }
    metricName: 'ActiveMessages'
    metricNamespace: 'Microsoft.ServiceBus/namespaces'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT5M'
  }
}

resource cosmosAvailabilitySignal 'Microsoft.Monitor/accounts/healthmodels/signaldefinitions@2025-05-03-preview' = {
  parent: healthModel
  name: 'CosmosAvailability'
  properties: {
    aggregationType: 'Average'
    dataUnit: 'Percent'
    displayName: 'Cosmos DB availability'
    evaluationRules: {
      degradedRule: {
        operator: 'LessThanOrEqual'
        threshold: '99'
      }
      unhealthyRule: {
        operator: 'LessThanOrEqual'
        threshold: '95'
      }
    }
    metricName: 'ServiceAvailability'
    metricNamespace: 'Microsoft.DocumentDB/databaseAccounts'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT5M'
  }
}

resource storageAvailabilitySignal 'Microsoft.Monitor/accounts/healthmodels/signaldefinitions@2025-05-03-preview' = {
  parent: healthModel
  name: 'StorageAvailability'
  properties: {
    aggregationType: 'Average'
    dataUnit: 'Percent'
    displayName: 'Storage availability'
    evaluationRules: {
      degradedRule: {
        operator: 'LessThanOrEqual'
        threshold: '99'
      }
      unhealthyRule: {
        operator: 'LessThanOrEqual'
        threshold: '95'
      }
    }
    metricName: 'Availability'
    metricNamespace: 'Microsoft.Storage/storageAccounts'
    refreshInterval: 'PT1M'
    signalKind: 'AzureResourceMetric'
    timeGrain: 'PT5M'
  }
}

resource rootEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'OrderService'
  properties: {
    canvasPosition: {
      x: 0
      y: 0
    }
    displayName: '注文処理サービス'
    healthObjective: 99
    impact: 'Standard'
    kind: 'Service'
    signals: {
      dependencies: {
        aggregationType: 'Thresholds'
        degradedThreshold: '1'
        unhealthyThreshold: '2'
      }
    }
  }
}

resource apiTierEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'ApiTier'
  properties: {
    canvasPosition: {
      x: -300
      y: 160
    }
    displayName: 'エントリ/API'
    healthObjective: 99
    impact: 'Standard'
    kind: 'Tier'
    signals: {
      dependencies: {
        aggregationType: 'WorstOf'
      }
    }
  }
}

resource processingTierEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'ProcessingTier'
  properties: {
    canvasPosition: {
      x: -80
      y: 160
    }
    displayName: '注文処理'
    healthObjective: 99
    impact: 'Standard'
    kind: 'Tier'
    signals: {
      dependencies: {
        aggregationType: 'Thresholds'
        degradedThreshold: '1'
        unhealthyThreshold: '2'
      }
    }
  }
}

resource dataTierEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'DataTier'
  properties: {
    canvasPosition: {
      x: 160
      y: 160
    }
    displayName: 'データストア'
    healthObjective: 99
    impact: 'Standard'
    kind: 'Tier'
    signals: {
      dependencies: {
        aggregationType: 'WorstOf'
      }
    }
  }
}

resource observabilityTierEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'ObservabilityTier'
  properties: {
    canvasPosition: {
      x: 400
      y: 160
    }
    displayName: '観測基盤'
    healthObjective: 99
    impact: 'Limited'
    kind: 'Tier'
    signals: {
      dependencies: {
        aggregationType: 'WorstOf'
      }
    }
  }
}

resource apiAppEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'ApiApp'
  properties: {
    canvasPosition: {
      x: -300
      y: 320
    }
    displayName: '注文 API App Service'
    healthObjective: 99
    impact: 'Standard'
    kind: 'AzureResource'
    signals: {
      azureLogAnalytics: {
        authenticationSetting: authSetting.name
        logAnalyticsWorkspaceResourceId: logAnalytics.id
        signalAssignments: [
          {
            signalDefinitions: [
              apiFailureRateSignal.name
              apiLatencySignal.name
            ]
          }
        ]
      }
    }
  }
}

resource workerAppEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'WorkerApp'
  properties: {
    canvasPosition: {
      x: -120
      y: 320
    }
    displayName: '注文処理 Function'
    healthObjective: 99
    impact: 'Standard'
    kind: 'AzureResource'
    signals: {
      azureLogAnalytics: {
        authenticationSetting: authSetting.name
        logAnalyticsWorkspaceResourceId: logAnalytics.id
        signalAssignments: [
          {
            signalDefinitions: [
              workerFailureSignal.name
            ]
          }
        ]
      }
    }
  }
}

resource queueEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'OrderQueue'
  properties: {
    canvasPosition: {
      x: 60
      y: 320
    }
    displayName: 'Service Bus Queue'
    healthObjective: 99
    impact: 'Standard'
    kind: 'AzureResource'
    signals: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: workloadResourceIds.serviceBusNamespace
        signalAssignments: [
          {
            signalDefinitions: [
              queueDepthSignal.name
            ]
          }
        ]
      }
    }
  }
}

resource cosmosEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'CosmosDb'
  properties: {
    canvasPosition: {
      x: 180
      y: 320
    }
    displayName: 'Cosmos DB'
    healthObjective: 99
    impact: 'Standard'
    kind: 'AzureResource'
    signals: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: workloadResourceIds.cosmosAccount
        signalAssignments: [
          {
            signalDefinitions: [
              cosmosAvailabilitySignal.name
            ]
          }
        ]
      }
    }
  }
}

resource storageEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'StorageAccount'
  properties: {
    canvasPosition: {
      x: 340
      y: 320
    }
    displayName: 'Receipt Storage'
    healthObjective: 99
    impact: 'Standard'
    kind: 'AzureResource'
    signals: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: workloadResourceIds.storageAccount
        signalAssignments: [
          {
            signalDefinitions: [
              storageAvailabilitySignal.name
            ]
          }
        ]
      }
    }
  }
}

resource observabilityEntity 'Microsoft.Monitor/accounts/healthmodels/entities@2025-05-03-preview' = {
  parent: healthModel
  name: 'Observability'
  properties: {
    canvasPosition: {
      x: 520
      y: 320
    }
    displayName: 'Azure Monitor / Application Insights'
    healthObjective: 99
    impact: 'Limited'
    kind: 'Observability'
    signals: {
      dependencies: {
        aggregationType: 'WorstOf'
      }
    }
  }
}

resource relRootApi 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'RootToApiTier'
  properties: {
    childEntityName: apiTierEntity.name
    displayName: 'root -> api tier'
    parentEntityName: rootEntity.name
  }
}

resource relRootProcessing 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'RootToProcessingTier'
  properties: {
    childEntityName: processingTierEntity.name
    displayName: 'root -> processing tier'
    parentEntityName: rootEntity.name
  }
}

resource relRootData 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'RootToDataTier'
  properties: {
    childEntityName: dataTierEntity.name
    displayName: 'root -> data tier'
    parentEntityName: rootEntity.name
  }
}

resource relRootObservability 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'RootToObservabilityTier'
  properties: {
    childEntityName: observabilityTierEntity.name
    displayName: 'root -> observability tier'
    parentEntityName: rootEntity.name
  }
}

resource relApiApp 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'ApiTierToApiApp'
  properties: {
    childEntityName: apiAppEntity.name
    displayName: 'api tier -> api app'
    parentEntityName: apiTierEntity.name
  }
}

resource relProcessingWorker 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'ProcessingTierToWorkerApp'
  properties: {
    childEntityName: workerAppEntity.name
    displayName: 'processing tier -> worker app'
    parentEntityName: processingTierEntity.name
  }
}

resource relProcessingQueue 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'ProcessingTierToQueue'
  properties: {
    childEntityName: queueEntity.name
    displayName: 'processing tier -> queue'
    parentEntityName: processingTierEntity.name
  }
}

resource relDataCosmos 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'DataTierToCosmosDb'
  properties: {
    childEntityName: cosmosEntity.name
    displayName: 'data tier -> cosmos db'
    parentEntityName: dataTierEntity.name
  }
}

resource relDataStorage 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'DataTierToStorage'
  properties: {
    childEntityName: storageEntity.name
    displayName: 'data tier -> storage'
    parentEntityName: dataTierEntity.name
  }
}

resource relObservability 'Microsoft.Monitor/accounts/healthmodels/relationships@2025-05-03-preview' = {
  parent: healthModel
  name: 'ObservabilityTierToMonitor'
  properties: {
    childEntityName: observabilityEntity.name
    displayName: 'observability tier -> monitor'
    parentEntityName: observabilityTierEntity.name
  }
}

output healthModelName string = healthModel.name
output healthModelId string = healthModel.id
output rootEntityName string = rootEntity.name
