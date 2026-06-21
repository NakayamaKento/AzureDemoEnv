targetScope = 'resourceGroup'

@description('命名プレフィックスに使用するコード')
param scenarioCode string = 'poc'

@description('アプリ系リソースのデプロイリージョン')
param location string = 'koreacentral'

@description('SRE Agent のデプロイリージョン')
param agentLocation string = 'eastus2'

@description('Azure テナント ID')
param tenantId string = tenant().tenantId

@description('Container App 名')
param containerAppName string = 'ca-sre-teams-bot'

@description('SRE Agent 名')
param agentName string = 'sre-agent-poc'

@description('Container App が利用するコンテナーイメージのリポジトリ名')
param containerImageRepository string = 'sre-teams-bot'

@description('Container App が利用するコンテナーイメージのタグ')
param containerImageTag string = 'aca-v7'

var prefix = 'sre-${scenarioCode}'
var uniqueSuffix = take(uniqueString(resourceGroup().id), 8)
var managedIdentityName = 'uami-${prefix}'
var logAnalyticsName = 'law-${prefix}'
var appInsightsName = 'ai-${prefix}'
var storageAccountName = 'st${replace(prefix, '-', '')}${uniqueSuffix}'
var containerRegistryName = 'acr${replace(prefix, '-', '')}${uniqueSuffix}'
var containerAppsEnvironmentName = 'cae-${prefix}'
var botName = 'bot-${prefix}-${uniqueSuffix}'
var containerImage = '${containerRegistryName}.azurecr.io/${containerImageRepository}:${containerImageTag}'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: managedIdentityName
  location: location
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2022-06-01' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-11-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${storageAccountName}-${uniqueSuffix}'
  scope: storageAccount
  properties: {
    workspaceId: logAnalytics.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-11-01' = {
  parent: storageAccount
  name: 'default'
}

resource conversationTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-11-01' = {
  parent: tableService
  name: 'ConversationThreadMap'
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
    }
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-11-02' = {
  name: containerAppsEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    publicNetworkAccess: 'Enabled'
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

resource sreAgent 'Microsoft.App/agents@2026-01-01' = {
  name: agentName
  location: agentLocation
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    actionConfiguration: {
      accessLevel: 'Low'
      identity: managedIdentity.id
      mode: 'Review'
    }
    defaultModel: {
      provider: 'Anthropic'
      name: 'Automatic'
    }
    knowledgeGraphConfiguration: {
      identity: managedIdentity.id
      managedResources: [
        resourceGroup().id
      ]
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsights.properties.AppId
        connectionString: appInsights.properties.ConnectionString
      }
    }
    upgradeChannel: 'Stable'
  }
}

resource containerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        allowInsecure: false
        transport: 'Auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: '${containerRegistry.name}.azurecr.io'
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: containerImage
          env: [
            {
              name: 'MICROSOFT_APP_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'MICROSOFT_APP_TYPE'
              value: 'UserAssignedMSI'
            }
            {
              name: 'MICROSOFT_APP_TENANT_ID'
              value: tenantId
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccount.name
            }
            {
              name: 'SRE_AGENT_RESOURCE_ID'
              value: sreAgent.id
            }
            {
              name: 'SRE_AGENT_ENDPOINT'
              value: sreAgent.properties.agentEndpoint
            }
            {
              name: 'PORT'
              value: '8080'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 12
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              initialDelaySeconds: 3
              periodSeconds: 5
              timeoutSeconds: 2
              failureThreshold: 6
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              periodSeconds: 30
              timeoutSeconds: 3
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

resource containerAppsEnvironmentDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${containerAppsEnvironmentName}-${uniqueSuffix}'
  scope: containerAppsEnvironment
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource botService 'Microsoft.BotService/botServices@2024-03-01' = {
  name: botName
  location: 'global'
  sku: {
    name: 'F0'
  }
  kind: 'azurebot'
  properties: {
    displayName: 'SRE Agent Teams Bot (POC)'
    endpoint: 'https://${containerApp.properties.configuration.ingress.fqdn}/api/messages'
    msaAppId: managedIdentity.properties.clientId
    msaAppTenantId: tenantId
    msaAppType: 'UserAssignedMSI'
    msaAppMSIResourceId: managedIdentity.id
  }
}

resource teamsChannel 'Microsoft.BotService/botServices/channels@2024-03-01' = {
  parent: botService
  name: 'MsTeamsChannel'
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
    }
  }
}

resource storageTableContributor 'Microsoft.Authorization/roleAssignments@2024-07-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'StorageTableDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobReader 'Microsoft.Authorization/roleAssignments@2024-07-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'StorageBlobDataReader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sreAgentAdministrator 'Microsoft.Authorization/roleAssignments@2024-07-01' = {
  name: guid(sreAgent.id, managedIdentity.id, 'SreAgentAdministrator')
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2024-07-01' = {
  name: guid(containerRegistry.id, managedIdentity.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output botName string = botService.name
output botMsaAppId string = managedIdentity.properties.clientId
output uamiId string = managedIdentity.id
output uamiClientId string = managedIdentity.properties.clientId
output uamiPrincipalId string = managedIdentity.properties.principalId
output appInsightsId string = appInsights.id
output managedEnvironmentId string = containerAppsEnvironment.id
output resourceGroupId string = resourceGroup().id
output storageAccountName string = storageAccount.name
output containerRegistryName string = containerRegistry.name
output containerImage string = containerImage
output agentResourceId string = sreAgent.id
output agentEndpoint string = sreAgent.properties.agentEndpoint
