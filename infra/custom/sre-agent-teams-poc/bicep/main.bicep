targetScope = 'resourceGroup'

@description('命名プレフィックスに使用するコード')
param scenarioCode string = 'poc'

@description('デプロイリージョン（SRE Agent 対応リージョン）')
param location string = 'koreacentral'

@description('Azure テナント ID')
param tenantId string = tenant().tenantId

var prefix = 'sre-${scenarioCode}'
var uniqueSuffix = take(uniqueString(resourceGroup().id), 8)
var uamiName = 'uami-${prefix}'
var lawName = 'law-${prefix}'
var aiName = 'ai-${prefix}'
var storageAccountName = 'st${replace(prefix, '-', '')}${uniqueSuffix}'
var aspName = 'asp-${prefix}'
var funcAppName = 'func-${prefix}-${uniqueSuffix}'
var botName = 'bot-${prefix}'

// ── User-Assigned Managed Identity ──────────────────────────────────────────
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
}

// ── Log Analytics Workspace ──────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Application Insights ─────────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ── Storage Account（Functions 用 + Table Storage：会話スレッドマッピング）─
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource conversationTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'ConversationThreadMap'
}

// ── App Service Plan（B1 Dedicated: SignalR 長時間接続に対応）───────────────
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: aspName
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
}

// ── Azure Functions App（Node.js 20、Bot ミドルウェア）─────────────────────
var storageConnString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

resource funcApp 'Microsoft.Web/sites@2023-12-01' = {
  name: funcAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      nodeVersion: '~20'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: storageConnString }
        { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING', value: storageConnString }
        { name: 'WEBSITE_CONTENTSHARE', value: toLower(funcAppName) }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~20' }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY', value: appInsights.properties.InstrumentationKey }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        // Bot Framework（UAMI ベース認証 — クライアントシークレット不要）
        { name: 'MICROSOFT_APP_ID', value: uami.properties.clientId }
        { name: 'MICROSOFT_APP_TYPE', value: 'UserAssignedMSI' }
        { name: 'MICROSOFT_APP_TENANT_ID', value: tenantId }
        { name: 'AZURE_CLIENT_ID', value: uami.properties.clientId }
        // Table Storage（会話スレッドマッピング）
        { name: 'STORAGE_ACCOUNT_NAME', value: storageAccount.name }
        { name: 'STORAGE_TABLE_CONN', value: storageConnString }
        // SRE Agent（deploy.ps1 が後で設定する）
        { name: 'SRE_AGENT_RESOURCE_ID', value: '' }
        { name: 'SRE_AGENT_ENDPOINT', value: '' }
      ]
      cors: {
        allowedOrigins: ['https://portal.azure.com']
      }
    }
  }
}

// ── Azure Bot Service（UAMI を App Identity として使用）────────────────────
resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  location: 'global'
  sku: { name: 'F0' }
  kind: 'azurebot'
  properties: {
    displayName: 'SRE Agent Teams Bot (POC)'
    endpoint: 'https://${funcApp.properties.defaultHostName}/api/messages'
    msaAppId: uami.properties.clientId
    msaAppTenantId: tenantId
    msaAppType: 'UserAssignedMSI'
    msaAppMSIResourceId: uami.id
  }
}

// ── Teams チャネル有効化 ─────────────────────────────────────────────────────
resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
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

// ── RBAC: Storage Table Data Contributor（会話マッピング書き込み）──────────
resource rbacTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, uami.id, 'StorageTableDataContributor')
  scope: storageAccount
  properties: {
    // Storage Table Data Contributor
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────
output funcAppName string = funcApp.name
output funcAppHostname string = funcApp.properties.defaultHostName
output botName string = botService.name
output botMsaAppId string = uami.properties.clientId
output uamiId string = uami.id
output uamiClientId string = uami.properties.clientId
output uamiPrincipalId string = uami.properties.principalId
output appInsightsId string = appInsights.id
output resourceGroupId string = resourceGroup().id
output storageAccountName string = storageAccount.name
