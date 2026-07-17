targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード。例: sgsli01')
param scenarioCode string = 'sgsli01'

@description('主デプロイリージョン。preview リソースの対応状況により変更可能。')
param location string = 'southeastasia'

var normalizedScenarioCode = toLower(replace(scenarioCode, '-', ''))
var suffix = toLower(uniqueString(subscription().id, resourceGroup().id, scenarioCode))
var shortSuffix = take(suffix, 6)
var namePrefix = toLower('${scenarioCode}-${shortSuffix}')
var tags = {
  scenario: 'service-group-sli-demo'
  scenarioCode: scenarioCode
  workload: 'order-processing'
}

var apiIdentityName = 'id-${namePrefix}-api'
var workerIdentityName = 'id-${namePrefix}-worker'
var sliIdentityName = 'id-${namePrefix}-sli'
var apiPlanName = 'asp-${namePrefix}-api'
var functionPlanName = 'asp-${namePrefix}-worker'
var webAppName = 'app-${namePrefix}-api'
var functionAppName = 'func-${namePrefix}-worker'
var storageName = take('st${normalizedScenarioCode}${suffix}', 24)
var serviceBusNamespaceName = 'sb-${namePrefix}'
var serviceBusQueueName = 'orders'
var cosmosAccountName = take('cosmos-${namePrefix}', 44)
var cosmosDatabaseName = 'orders'
var cosmosContainerName = 'orders'
var appConfigName = 'appcs-${namePrefix}'
var logAnalyticsName = 'log-${namePrefix}'
var appInsightsName = 'appi-${namePrefix}'
var azureMonitorWorkspaceName = 'amw-${namePrefix}'
var deploymentContainerName = 'function-packages'
var receiptsContainerName = 'receipts'

var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
var appConfigurationDataOwnerRoleId = '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'
var appConfigurationDataReaderRoleId = '516239f1-63e1-4d78-a4de-a74fb236a071'
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var cosmosSqlDataContributorRoleDefinitionId = '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'

resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: apiIdentityName
  location: location
  tags: tags
}

resource workerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: workerIdentityName
  location: location
  tags: tags
}

resource sliIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: sliIdentityName
  location: location
  tags: tags
}

resource apiPlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: apiPlanName
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
    zoneRedundant: false
  }
}

resource functionPlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: functionPlanName
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
    zoneRedundant: false
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' = {
  name: azureMonitorWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    metrics: {
      enableAccessUsingResourcePermissions: true
    }
    publicNetworkAccess: 'Enabled'
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource receiptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: receiptsContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: serviceBusQueueName
  properties: {
    defaultMessageTimeToLive: 'P7D'
    deadLetteringOnMessageExpiration: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    lockDuration: 'PT1M'
    maxDeliveryCount: 5
    requiresDuplicateDetection: true
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    locations: [
      {
        failoverPriority: 0
        isZoneRedundant: false
        locationName: location
      }
    ]
    publicNetworkAccess: 'Enabled'
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: cosmosDatabaseName
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/_etag/?'
          }
        ]
      }
      partitionKey: {
        kind: 'Hash'
        paths: [
          '/tenantId'
        ]
      }
    }
  }
}

resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: appConfigName
  location: location
  tags: tags
  sku: {
    name: 'free'
  }
  properties: {
    createMode: 'Default'
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource apiServiceBusSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, apiIdentity.id, serviceBusDataSenderRoleId)
  scope: serviceBusNamespace
  properties: {
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
  }
}

resource workerServiceBusReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, workerIdentity.id, serviceBusDataReceiverRoleId)
  scope: serviceBusNamespace
  properties: {
    principalId: workerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
  }
}

resource apiAppConfigOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appConfiguration.id, apiIdentity.id, appConfigurationDataOwnerRoleId)
  scope: appConfiguration
  properties: {
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigurationDataOwnerRoleId)
  }
}

resource workerAppConfigReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appConfiguration.id, workerIdentity.id, appConfigurationDataReaderRoleId)
  scope: appConfiguration
  properties: {
    principalId: workerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigurationDataReaderRoleId)
  }
}

resource apiCosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, apiIdentity.id, 'api-cosmos-data-contributor')
  properties: {
    principalId: apiIdentity.properties.principalId
    roleDefinitionId: cosmosSqlDataContributorRoleDefinitionId
    scope: cosmosAccount.id
  }
}

resource workerCosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, workerIdentity.id, 'worker-cosmos-data-contributor')
  properties: {
    principalId: workerIdentity.properties.principalId
    roleDefinitionId: cosmosSqlDataContributorRoleDefinitionId
    scope: cosmosAccount.id
  }
}

resource workerStorageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, workerIdentity.id, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    principalId: workerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${apiIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: apiPlan.id
    httpsOnly: true
    siteConfig: {
      alwaysOn: true
      appCommandLine: 'npm start'
      ftpsState: 'Disabled'
      http20Enabled: true
      linuxFxVersion: 'NODE|22-lts'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: '3000'
        }
        {
          name: 'WEBSITES_CONTAINER_START_TIME_LIMIT'
          value: '600'
        }
        {
          name: 'WEBSITE_WARMUP_PATH'
          value: '/metrics'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~22'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'APP_CONFIG_ENDPOINT'
          value: appConfiguration.properties.endpoint
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: apiIdentity.properties.clientId
        }
        {
          name: 'SERVICE_BUS_NAMESPACE'
          value: '${serviceBusNamespace.name}.servicebus.windows.net'
        }
        {
          name: 'SERVICE_BUS_QUEUE_NAME'
          value: serviceBusQueue.name
        }
        {
          name: 'COSMOS_ENDPOINT'
          value: cosmosAccount.properties.documentEndpoint
        }
        {
          name: 'COSMOS_DATABASE'
          value: cosmosDatabase.name
        }
        {
          name: 'COSMOS_CONTAINER'
          value: cosmosContainer.name
        }
        {
          name: 'DEMO_TENANT_ID'
          value: 'contoso-retail'
        }
      ]
    }
  }
  dependsOn: [
    apiServiceBusSender
    apiAppConfigOwner
    apiCosmosDataContributor
  ]
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${workerIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${deploymentContainer.name}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: workerIdentity.id
          }
        }
      }
      runtime: {
        name: 'node'
        version: '22'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 20
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: workerIdentity.properties.clientId
        }
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: '${serviceBusNamespace.name}.servicebus.windows.net'
        }
        {
          name: 'ServiceBusConnection__credential'
          value: 'managedidentity'
        }
        {
          name: 'ServiceBusConnection__clientId'
          value: workerIdentity.properties.clientId
        }
        {
          name: 'SERVICE_BUS_QUEUE_NAME'
          value: serviceBusQueue.name
        }
        {
          name: 'ServiceBusQueueName'
          value: serviceBusQueue.name
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'APP_CONFIG_ENDPOINT'
          value: appConfiguration.properties.endpoint
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: workerIdentity.properties.clientId
        }
        {
          name: 'COSMOS_ENDPOINT'
          value: cosmosAccount.properties.documentEndpoint
        }
        {
          name: 'COSMOS_DATABASE'
          value: cosmosDatabase.name
        }
        {
          name: 'COSMOS_CONTAINER'
          value: cosmosContainer.name
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'RECEIPTS_CONTAINER'
          value: receiptsContainer.name
        }
      ]
      ftpsState: 'Disabled'
      http20Enabled: true
      minTlsVersion: '1.2'
    }
  }
  dependsOn: [
    workerServiceBusReceiver
    workerAppConfigReader
    workerCosmosDataContributor
    workerStorageBlobOwner
  ]
}

output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output functionAppName string = functionApp.name
output serviceBusNamespaceName string = serviceBusNamespace.name
output serviceBusQueueName string = serviceBusQueue.name
output cosmosAccountName string = cosmosAccount.name
output storageAccountName string = storageAccount.name
output appConfigurationName string = appConfiguration.name
output applicationInsightsName string = appInsights.name
output logAnalyticsName string = logAnalytics.name
output azureMonitorWorkspaceName string = azureMonitorWorkspace.name
output apiIdentityPrincipalId string = apiIdentity.properties.principalId
output workerIdentityPrincipalId string = workerIdentity.properties.principalId
output sliIdentityPrincipalId string = sliIdentity.properties.principalId
output apiIdentityResourceId string = apiIdentity.id
output workerIdentityResourceId string = workerIdentity.id
output sliIdentityResourceId string = sliIdentity.id
output azureMonitorWorkspaceResourceId string = azureMonitorWorkspace.id
output azureMonitorDefaultDcrResourceId string = azureMonitorWorkspace.properties.defaultIngestionSettings.dataCollectionRuleResourceId
output azureMonitorMetricsIngestionEndpoint string = '${azureMonitorWorkspace.properties.defaultIngestionSettings.ingestionEndpoints.metrics}/dataCollectionRules/${azureMonitorWorkspace.properties.defaultIngestionSettings.dataCollectionRuleImmutableId}/streams/Microsoft-PrometheusMetrics/api/v1/write?api-version=2023-04-24'
output workloadNames object = {
  webApp: webApp.name
  functionApp: functionApp.name
  serviceBusNamespace: serviceBusNamespace.name
  serviceBusQueue: serviceBusQueue.name
  cosmosAccount: cosmosAccount.name
  storageAccount: storageAccount.name
  appConfiguration: appConfiguration.name
  applicationInsights: appInsights.name
  logAnalytics: logAnalytics.name
  azureMonitorWorkspace: azureMonitorWorkspace.name
}
output workloadResourceIds object = {
  webApp: webApp.id
  functionApp: functionApp.id
  serviceBusNamespace: serviceBusNamespace.id
  serviceBusQueue: serviceBusQueue.id
  cosmosAccount: cosmosAccount.id
  storageAccount: storageAccount.id
  appConfiguration: appConfiguration.id
  applicationInsights: appInsights.id
  logAnalytics: logAnalytics.id
  azureMonitorWorkspace: azureMonitorWorkspace.id
}
