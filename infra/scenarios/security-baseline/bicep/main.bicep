targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード')
param scenarioCode string = 'csa01'

@description('主デプロイリージョン')
param location string = 'southwestasia'

var namePrefix = toLower('${scenarioCode}-${uniqueString(resourceGroup().id)}')
var tags = {
	scenario: 'security-baseline'
	managedBy: 'AzureDemoEnv'
}
var baselineNsgName = '${take(namePrefix, 35)}-baseline-nsg'
var baselineRtName = '${take(namePrefix, 37)}-baseline-rt'
var baselineVnetName = '${take(namePrefix, 36)}-baseline-vnet'

resource baselineNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
	name: baselineNsgName
	location: location
	tags: tags
	properties: {
		securityRules: [
			{
				name: 'deny-inbound-rdp'
				properties: {
					access: 'Deny'
					direction: 'Inbound'
					priority: 200
					protocol: 'Tcp'
					sourceAddressPrefix: '*'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '3389'
				}
			}
			{
				name: 'deny-inbound-ssh'
				properties: {
					access: 'Deny'
					direction: 'Inbound'
					priority: 210
					protocol: 'Tcp'
					sourceAddressPrefix: '*'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '22'
				}
			}
			{
				name: 'allow-vnet-inbound'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 300
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

resource baselineRouteTable 'Microsoft.Network/routeTables@2023-11-01' = {
	name: baselineRtName
	location: location
	tags: tags
	properties: {
		routes: [
			{
				name: 'default-egress'
				properties: {
					addressPrefix: '0.0.0.0/0'
					nextHopType: 'VirtualAppliance'
					nextHopIpAddress: '10.50.0.4'
				}
			}
		]
	}
}

resource baselineVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
	name: baselineVnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: [
				'10.50.0.0/16'
			]
		}
		subnets: [
			{
				name: 'secure-app'
				properties: {
					addressPrefix: '10.50.1.0/24'
					networkSecurityGroup: {
						id: baselineNsg.id
					}
					routeTable: {
						id: baselineRouteTable.id
					}
				}
			}
		]
	}
}

output scenario string = 'security-baseline'
output resourcePrefix string = namePrefix
output selectedLocation string = location
output baselineNsgResourceId string = baselineNsg.id
output baselineRouteTableResourceId string = baselineRouteTable.id
output baselineVnetResourceId string = baselineVnet.id
