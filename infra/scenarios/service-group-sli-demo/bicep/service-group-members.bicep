targetScope = 'resourceGroup'

type ServiceGroupIds = {
  root: string
}

type WorkloadNames = {
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

@description('service-groups.bicep の出力 serviceGroupIds。')
param serviceGroupIds ServiceGroupIds

@description('main.bicep の出力 workloadNames。')
param workloadNames WorkloadNames

resource webApp 'Microsoft.Web/sites@2024-11-01' existing = {
  name: workloadNames.webApp
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' existing = {
  name: workloadNames.functionApp
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: workloadNames.serviceBusNamespace
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' existing = {
  parent: serviceBusNamespace
  name: workloadNames.serviceBusQueue
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: workloadNames.cosmosAccount
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: workloadNames.storageAccount
}

resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: workloadNames.appConfiguration
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: workloadNames.applicationInsights
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workloadNames.logAnalytics
}

resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' existing = {
  name: workloadNames.azureMonitorWorkspace
}

resource webAppMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: webApp
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource functionAppMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: functionApp
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource serviceBusNamespaceMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: serviceBusNamespace
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource serviceBusQueueMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: serviceBusQueue
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource cosmosMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: cosmosAccount
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource storageMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: storageAccount
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource appConfigurationMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: appConfiguration
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource appInsightsMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: applicationInsights
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource logAnalyticsMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: logAnalytics
  properties: {
    targetId: serviceGroupIds.root
  }
}

resource azureMonitorWorkspaceMember 'Microsoft.Relationships/serviceGroupMember@2023-09-01-preview' = {
  name: 'sgMember'
  scope: azureMonitorWorkspace
  properties: {
    targetId: serviceGroupIds.root
  }
}

output membershipNames object = {
  webApp: webAppMember.name
  functionApp: functionAppMember.name
  serviceBusNamespace: serviceBusNamespaceMember.name
  serviceBusQueue: serviceBusQueueMember.name
  cosmos: cosmosMember.name
  storage: storageMember.name
  appConfiguration: appConfigurationMember.name
  applicationInsights: appInsightsMember.name
  logAnalytics: logAnalyticsMember.name
  azureMonitorWorkspace: azureMonitorWorkspaceMember.name
}
