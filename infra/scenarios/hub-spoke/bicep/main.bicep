targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード')
param scenarioCode string = 'csa01'

@description('主デプロイリージョン')
param location string = 'southwestasia'

var namePrefix = toLower('${scenarioCode}-${uniqueString(resourceGroup().id)}')
var tags = {
	scenario: 'hub-spoke'
	managedBy: 'AzureDemoEnv'
}

var hubNsgName = '${take(namePrefix, 35)}-hub-nsg'

resource hubNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
	name: hubNsgName
	location: location
	tags: tags
	properties: {
		securityRules: [
			{
				name: 'allow-vnet-inbound'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 100
					protocol: '*'
					sourceAddressPrefix: 'VirtualNetwork'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '*'
				}
			}
		]
	}
}

var hubRtName = '${take(namePrefix, 40)}-hub-rt'

resource hubRouteTable 'Microsoft.Network/routeTables@2023-11-01' = {
	name: hubRtName
	location: location
	tags: tags
	properties: {
		routes: [
			{
				name: 'default-to-firewall-placeholder'
				properties: {
					addressPrefix: '0.0.0.0/0'
					nextHopType: 'VirtualAppliance'
					nextHopIpAddress: '10.10.0.4'
				}
			}
		]
	}
}

var hubVnetName = '${take(namePrefix, 40)}-hub-vnet'

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
	name: hubVnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: [
				'10.10.0.0/16'
			]
		}
		subnets: [
			{
				name: 'AzureFirewallSubnet'
				properties: {
					addressPrefix: '10.10.0.0/24'
				}
			}
			{
				name: 'hub-app'
				properties: {
					addressPrefix: '10.10.1.0/24'
					networkSecurityGroup: {
						id: hubNsg.id
					}
					routeTable: {
						id: hubRouteTable.id
					}
				}
			}
		]
	}
}

var spokeVnetName = '${take(namePrefix, 38)}-spoke-vnet'

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
	name: spokeVnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: [
				'10.20.0.0/16'
			]
		}
		subnets: [
			{
				name: 'spoke-app'
				properties: {
					addressPrefix: '10.20.1.0/24'
				}
			}
		]
	}
}

resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
	name: '${hubVnetName}/to-spoke'
	properties: {
		remoteVirtualNetwork: {
			id: spokeVnet.id
		}
		allowVirtualNetworkAccess: true
		allowForwardedTraffic: true
	}
}

resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
	name: '${spokeVnetName}/to-hub'
	properties: {
		remoteVirtualNetwork: {
			id: hubVnet.id
		}
		allowVirtualNetworkAccess: true
		allowForwardedTraffic: true
	}
}

output scenario string = 'hub-spoke'
output resourcePrefix string = namePrefix
output selectedLocation string = location
output hubVnetResourceId string = hubVnet.id
output spokeVnetResourceId string = spokeVnet.id
output hubNsgResourceId string = hubNsg.id
output hubRouteTableResourceId string = hubRouteTable.id
