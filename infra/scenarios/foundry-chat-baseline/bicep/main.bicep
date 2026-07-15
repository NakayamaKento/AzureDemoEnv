targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード。例: fcb01')
param scenarioCode string = 'fcb01'

@description('主デプロイリージョン')
param location string = 'southeastasia'

var suffix = toLower(uniqueString(resourceGroup().id, scenarioCode, location))
var namePrefix = toLower('${scenarioCode}${take(suffix, 6)}')

var tags = {
	scenario: 'foundry-chat-baseline'
	managedBy: 'AzureDemoEnv'
	waf: 'aligned'
}

var vnetName = '${namePrefix}-vnet'
var appGatewaySubnetName = 'snet-appgateway'
var appServiceSubnetName = 'snet-appservice'
var privateEndpointSubnetName = 'snet-privateendpoints'

var appGatewayPipName = '${namePrefix}-agw-pip'
var appGatewayNsgName = '${namePrefix}-agw-nsg'
var appServiceNsgName = '${namePrefix}-app-nsg'
var appGatewayName = '${namePrefix}-agw'
var appGatewayWafPolicyName = '${namePrefix}-agw-wafp'

var planName = '${namePrefix}-plan'
var webAppName = take('app-${namePrefix}', 60)

var lawName = '${namePrefix}-law'
var appInsightsName = '${namePrefix}-appi'

var foundryName = take('aif${namePrefix}', 24)
var storageName = take('st${namePrefix}chat', 24)
var searchName = take('srch-${namePrefix}', 60)
var cosmosName = take('cdb-${namePrefix}-chat', 44)

var webBackendFqdn = '${webAppName}.azurewebsites.net'

module appGatewayPip 'br/public:avm/res/network/public-ip-address:0.12.0' = {
	name: 'appGatewayPip'
	params: {
		name: appGatewayPipName
		location: location
		tags: tags
		skuName: 'Standard'
		skuTier: 'Regional'
		publicIPAllocationMethod: 'Static'
	}
}

module appGatewayNsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
	name: 'appGatewayNsg'
	params: {
		name: appGatewayNsgName
		location: location
		tags: tags
		securityRules: [
			{
				name: 'allow-http-inbound'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 110
					protocol: 'Tcp'
					sourceAddressPrefix: 'Internet'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '80'
				}
			}
			{
				name: 'allow-gatewaymanager-inbound'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 115
					protocol: 'Tcp'
					sourceAddressPrefix: 'GatewayManager'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRanges: [
						'65200-65535'
					]
				}
			}
			{
				name: 'allow-azure-lb'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 120
					protocol: '*'
					sourceAddressPrefix: 'AzureLoadBalancer'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '*'
				}
			}
		]
	}
}

module appServiceNsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
	name: 'appServiceNsg'
	params: {
		name: appServiceNsgName
		location: location
		tags: tags
		securityRules: [
			{
				name: 'deny-inbound-all'
				properties: {
					access: 'Deny'
					direction: 'Inbound'
					priority: 100
					protocol: '*'
					sourceAddressPrefix: '*'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '*'
				}
			}
		]
	}
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
	name: vnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: [
				'10.60.0.0/16'
			]
		}
		subnets: [
			{
				name: appGatewaySubnetName
				properties: {
					addressPrefix: '10.60.0.0/24'
					networkSecurityGroup: {
						id: appGatewayNsg.outputs.resourceId
					}
				}
			}
			{
				name: appServiceSubnetName
				properties: {
					addressPrefix: '10.60.1.0/24'
					delegations: [
						{
							name: 'web-delegation'
							properties: {
								serviceName: 'Microsoft.Web/serverFarms'
							}
						}
					]
					networkSecurityGroup: {
						id: appServiceNsg.outputs.resourceId
					}
				}
			}
			{
				name: privateEndpointSubnetName
				properties: {
					addressPrefix: '10.60.2.0/24'
					privateEndpointNetworkPolicies: 'Disabled'
				}
			}
		]
	}
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
	name: planName
	location: location
	tags: tags
	sku: {
		name: 'F1'
		tier: 'Free'
	}
	kind: 'linux'
	properties: {
		reserved: true
		zoneRedundant: false
	}
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
	name: lawName
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

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
	name: webAppName
	location: location
	tags: tags
	kind: 'app,linux'
	identity: {
		type: 'SystemAssigned'
	}
	properties: {
		serverFarmId: appServicePlan.id
		httpsOnly: true
		siteConfig: {
			alwaysOn: false
			linuxFxVersion: 'NODE|20-lts'
			minTlsVersion: '1.2'
			appSettings: [
				{
					name: 'WEBSITES_PORT'
					value: '3000'
				}
				{
					name: 'WEBSITE_NODE_DEFAULT_VERSION'
					value: '~20'
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
					name: 'FOUNDRY_PROJECT_ENDPOINT'
					value: 'https://${foundryName}.services.ai.azure.com/api/projects/projchat'
				}
				{
					name: 'FOUNDRY_AGENT_ID'
					value: 'baseline-chatbot-agent'
				}
				{
					name: 'FOUNDRY_AGENT_VERSION'
					value: 'latest'
				}
				{
					name: 'FOUNDRY_MODEL_DEPLOYMENT'
					value: 'gpt-4.1-mini'
				}
				{
					name: 'FOUNDRY_AGENT_INSTRUCTIONS'
					value: 'You are a helpful AI assistant. Answer questions concisely and helpfully in Japanese when appropriate.'
				}
			]
		}
	}
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
	name: storageName
	location: location
	tags: tags
	sku: {
		name: 'Standard_ZRS'
	}
	kind: 'StorageV2'
	properties: {
		minimumTlsVersion: 'TLS1_2'
		allowBlobPublicAccess: false
		supportsHttpsTrafficOnly: true
	}
}

resource search 'Microsoft.Search/searchServices@2023-11-01' = {
	name: searchName
	location: location
	tags: tags
	sku: {
		name: 'standard'
	}
	properties: {
		replicaCount: 1
		partitionCount: 1
		hostingMode: 'default'
		publicNetworkAccess: 'enabled'
	}
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' = {
	name: cosmosName
	location: location
	tags: tags
	kind: 'GlobalDocumentDB'
	properties: {
		databaseAccountOfferType: 'Standard'
		enableAutomaticFailover: false
		locations: [
			{
				locationName: location
				failoverPriority: 0
				isZoneRedundant: false
			}
		]
		capabilities: [
			{
				name: 'EnableServerless'
			}
		]
		publicNetworkAccess: 'Enabled'
		disableLocalAuth: false
		minimalTlsVersion: 'Tls12'
	}
}

resource foundryDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
	name: 'gpt-4.1-mini'
	parent: foundry
	sku: {
		name: 'GlobalStandard'
		capacity: 10
	}
	properties: {
		model: {
			format: 'OpenAI'
			name: 'gpt-4.1-mini'
			version: '2025-04-14'
		}
	}
}

resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
	name: foundryName
	location: location
	tags: tags
	kind: 'AIServices'
	sku: {
		name: 'S0'
	}
	identity: {
		type: 'SystemAssigned'
	}
	properties: {
		publicNetworkAccess: 'Enabled'
		customSubDomainName: foundryName
		// allowProjectManagement: true // NOTE: Set via az rest API after deployment
		networkAcls: {
			defaultAction: 'Allow'
			virtualNetworkRules: []
			ipRules: []
		}
	}
}

resource appGatewayWafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-05-01' = {
	name: appGatewayWafPolicyName
	location: location
	tags: tags
	properties: {
		policySettings: {
			state: 'Enabled'
			mode: 'Prevention'
			requestBodyCheck: true
			maxRequestBodySizeInKb: 128
			fileUploadLimitInMb: 100
		}
		managedRules: {
			managedRuleSets: [
				{
					ruleSetType: 'OWASP'
					ruleSetVersion: '3.2'
				}
			]
		}
	}
}

resource appGateway 'Microsoft.Network/applicationGateways@2024-05-01' = {
	name: appGatewayName
	location: location
	tags: tags
	properties: {
		firewallPolicy: {
			id: appGatewayWafPolicy.id
		}
		sku: {
			name: 'WAF_v2'
			tier: 'WAF_v2'
			capacity: 1
		}
		gatewayIPConfigurations: [
			{
				name: 'gw-ipcfg'
				properties: {
					subnet: {
						id: '${vnet.id}/subnets/${appGatewaySubnetName}'
					}
				}
			}
		]
		frontendIPConfigurations: [
			{
				name: 'fe-public'
				properties: {
					publicIPAddress: {
						id: appGatewayPip.outputs.resourceId
					}
				}
			}
		]
		frontendPorts: [
			{
				name: 'port-80'
				properties: {
					port: 80
				}
			}
		]
		backendAddressPools: [
			{
				name: 'be-webapp'
				properties: {
					backendAddresses: [
						{
							fqdn: webBackendFqdn
						}
					]
				}
			}
		]
		backendHttpSettingsCollection: [
			{
				name: 'be-https'
				properties: {
					protocol: 'Https'
					port: 443
					requestTimeout: 60
					pickHostNameFromBackendAddress: true
					probeEnabled: true
				}
			}
		]
		probes: [
			{
				name: 'probe-webapp'
				properties: {
					protocol: 'Https'
					path: '/healthz'
					interval: 30
					timeout: 30
					unhealthyThreshold: 3
					pickHostNameFromBackendHttpSettings: true
					match: {
						statusCodes: [
							'200-399'
						]
					}
				}
			}
		]
		httpListeners: [
			{
				name: 'listener-http'
				properties: {
					frontendIPConfiguration: {
						id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'fe-public')
					}
					frontendPort: {
						id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'port-80')
					}
					protocol: 'Http'
				}
			}
		]
		requestRoutingRules: [
			{
				name: 'rule-http'
				properties: {
					priority: 100
					ruleType: 'Basic'
					httpListener: {
						id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'listener-http')
					}
					backendAddressPool: {
						id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'be-webapp')
					}
					backendHttpSettings: {
						id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'be-https')
					}
				}
			}
		]
	}
	dependsOn: [
		webApp
	]
}

// RBAC: App Service MSI に Foundry アクセス権を付与
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var azureAiDeveloperRoleId = '64702f94-c441-49e6-a78b-ef80e0188fee'

resource appServiceCognitiveServicesRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
	name: guid(resourceGroup().id, webApp.id, foundry.id, cognitiveServicesUserRoleId)
	scope: foundry
	properties: {
		roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
		principalId: webApp.identity.principalId
		principalType: 'ServicePrincipal'
	}
}

resource appServiceAzureAiDeveloperRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
	name: guid(resourceGroup().id, webApp.id, foundry.id, azureAiDeveloperRoleId)
	scope: foundry
	properties: {
		roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiDeveloperRoleId)
		principalId: webApp.identity.principalId
		principalType: 'ServicePrincipal'
	}
}

output scenarioName string = namePrefix
output scenarioLocation string = location
output appServiceName string = webApp.name
output appGatewayPublicIp string = appGatewayPip.outputs.ipAddress
output appGatewayUrl string = 'http://${appGatewayPip.outputs.ipAddress}'
output foundryAccountName string = foundry.name
output foundryEndpoint string = foundry.properties.endpoint

