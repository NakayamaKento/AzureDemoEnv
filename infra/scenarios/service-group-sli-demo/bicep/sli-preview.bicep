targetScope = 'resourceGroup'

@description('SLI を関連付ける root Service Group 名。service-groups.bicep の serviceGroupNames.root を指定。')
param rootServiceGroupName string

@description('main.bicep の出力 azureMonitorWorkspaceName。')
param azureMonitorWorkspaceName string

@description('SLI が AMW metrics を読むために使う user-assigned managed identity resource ID。')
param sliManagedIdentityResourceId string

var metricNamespace = 'customdefault'

resource rootServiceGroup 'Microsoft.Management/serviceGroups@2024-02-01-preview' existing = {
  scope: tenant()
  name: rootServiceGroupName
}

resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' existing = {
  name: azureMonitorWorkspaceName
}

resource availabilitySli 'Microsoft.Monitor/slis@2025-03-01-preview' = {
  scope: rootServiceGroup
  name: 'OrderAvailability'
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
    description: 'Request-based availability for the order submission path.'
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
        signalFormula: 'A'
        signalSources: [
          {
            filters: [
              {
                dimensionName: 'job'
                operator: 'eq'
                value: 'order-api'
              }
              {
                dimensionName: 'environment'
                operator: 'eq'
                value: 'service-group-sli-demo'
              }
            ]
            metricName: 'order_sli_good_requests_1m'
            metricNamespace: metricNamespace
            signalSourceId: 'A'
            sourceAmwAccountManagedIdentity: sliManagedIdentityResourceId
            sourceAmwAccountResourceId: azureMonitorWorkspace.id
            spatialAggregation: {
              dimensions: [
                'job'
              ]
              type: 'Sum'
            }
            temporalAggregation: {
              type: 'Sum'
              windowSizeMinutes: 1
            }
          }
        ]
      }
      totalSignals: {
        signalFormula: 'A+B'
        signalSources: [
          {
            filters: [
              {
                dimensionName: 'job'
                operator: 'eq'
                value: 'order-api'
              }
              {
                dimensionName: 'environment'
                operator: 'eq'
                value: 'service-group-sli-demo'
              }
            ]
            metricName: 'order_sli_good_requests_1m'
            metricNamespace: metricNamespace
            signalSourceId: 'A'
            sourceAmwAccountManagedIdentity: sliManagedIdentityResourceId
            sourceAmwAccountResourceId: azureMonitorWorkspace.id
            spatialAggregation: {
              dimensions: [
                'job'
              ]
              type: 'Sum'
            }
            temporalAggregation: {
              type: 'Sum'
              windowSizeMinutes: 1
            }
          }
          {
            filters: [
              {
                dimensionName: 'job'
                operator: 'eq'
                value: 'order-api'
              }
              {
                dimensionName: 'environment'
                operator: 'eq'
                value: 'service-group-sli-demo'
              }
            ]
            metricName: 'order_sli_failed_requests_1m'
            metricNamespace: metricNamespace
            signalSourceId: 'B'
            sourceAmwAccountManagedIdentity: sliManagedIdentityResourceId
            sourceAmwAccountResourceId: azureMonitorWorkspace.id
            spatialAggregation: {
              dimensions: [
                'job'
              ]
              type: 'Sum'
            }
            temporalAggregation: {
              type: 'Sum'
              windowSizeMinutes: 1
            }
          }
        ]
      }
    }
  }
}

output availabilitySliName string = availabilitySli.name
