targetScope = 'resourceGroup'

@description('SLI を関連付ける root Service Group 名。service-groups.bicep の serviceGroupNames.root を指定。')
param rootServiceGroupName string

@description('main.bicep の出力 azureMonitorWorkspaceName。')
param azureMonitorWorkspaceName string

@description('SLI が AMW metrics を読むために使う user-assigned managed identity resource ID。')
param sliManagedIdentityResourceId string

var metricNamespace = 'service-group-sli-demo'

resource rootServiceGroup 'Microsoft.Management/serviceGroups@2024-02-01-preview' existing = {
  scope: tenant()
  name: rootServiceGroupName
}

resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' existing = {
  name: azureMonitorWorkspaceName
}

resource availabilitySli 'Microsoft.Monitor/slis@2025-03-01-preview' = {
  scope: rootServiceGroup
  name: 'AvailabilitySli'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sliManagedIdentityResourceId}': {}
    }
  }
  properties: {
    baselineProperties: {
      baseline: {
        evaluationCalculationType: 'RollingDays'
        evaluationPeriodDays: 7
        value: 99
      }
    }
    category: 'Availability'
    description: 'Request-based availability for the order submission path. This preview SLI expects matching metrics to be available in the Azure Monitor Workspace.'
    destinationAmwAccounts: [
      {
        identity: sliManagedIdentityResourceId
        resourceId: azureMonitorWorkspace.id
      }
    ]
    enableAlert: false
    evaluationType: 'RequestBased'
    sliProperties: {
      goodSignals: {
        signalFormula: 'ordersSubmitted'
        signalSources: [
          {
            filters: []
            metricName: 'orders_submitted'
            metricNamespace: metricNamespace
            signalSourceId: 'ordersSubmitted'
            sourceAmwAccountManagedIdentity: sliManagedIdentityResourceId
            sourceAmwAccountResourceId: azureMonitorWorkspace.id
            spatialAggregation: {
              dimensions: []
              type: 'Sum'
            }
            temporalAggregation: {
              type: 'Sum'
              windowSizeMinutes: 5
            }
          }
        ]
      }
      totalSignals: {
        signalFormula: 'ordersSubmitted + orderSubmitFailures'
        signalSources: [
          {
            filters: []
            metricName: 'orders_submitted'
            metricNamespace: metricNamespace
            signalSourceId: 'ordersSubmitted'
            sourceAmwAccountManagedIdentity: sliManagedIdentityResourceId
            sourceAmwAccountResourceId: azureMonitorWorkspace.id
            spatialAggregation: {
              dimensions: []
              type: 'Sum'
            }
            temporalAggregation: {
              type: 'Sum'
              windowSizeMinutes: 5
            }
          }
          {
            filters: []
            metricName: 'order_submit_failures'
            metricNamespace: metricNamespace
            signalSourceId: 'orderSubmitFailures'
            sourceAmwAccountManagedIdentity: sliManagedIdentityResourceId
            sourceAmwAccountResourceId: azureMonitorWorkspace.id
            spatialAggregation: {
              dimensions: []
              type: 'Sum'
            }
            temporalAggregation: {
              type: 'Sum'
              windowSizeMinutes: 5
            }
          }
        ]
      }
    }
  }
}

resource latencySli 'Microsoft.Monitor/slis@2025-03-01-preview' = {
  scope: rootServiceGroup
  name: 'LatencySli'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sliManagedIdentityResourceId}': {}
    }
  }
  properties: {
    baselineProperties: {
      baseline: {
        evaluationCalculationType: 'RollingDays'
        evaluationPeriodDays: 7
        value: 95
      }
    }
    category: 'Latency'
    description: 'Window-based latency SLI for order submission p95 latency. This preview SLI expects matching metrics to be available in the Azure Monitor Workspace.'
    destinationAmwAccounts: [
      {
        identity: sliManagedIdentityResourceId
        resourceId: azureMonitorWorkspace.id
      }
    ]
    enableAlert: false
    evaluationType: 'WindowBased'
    sliProperties: {
      signals: {
        signalFormula: 'orderSubmitLatencyMs'
        signalSources: [
          {
            filters: []
            metricName: 'order_submit_latency_ms'
            metricNamespace: metricNamespace
            signalSourceId: 'orderSubmitLatencyMs'
            sourceAmwAccountManagedIdentity: sliManagedIdentityResourceId
            sourceAmwAccountResourceId: azureMonitorWorkspace.id
            spatialAggregation: {
              dimensions: []
              type: 'Average'
            }
            temporalAggregation: {
              type: 'Average'
              windowSizeMinutes: 5
            }
          }
        ]
      }
      windowUptimeCriteria: {
        comparator: 'lte'
        target: 750
      }
    }
  }
}

output availabilitySliName string = availabilitySli.name
output latencySliName string = latencySli.name
