targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード')
param scenarioCode string = 'csa01'

@description('主デプロイリージョン')
param location string = 'southeastasia'

var namePrefix = toLower('${scenarioCode}-${uniqueString(resourceGroup().id)}')
var tags = {
	scenario: 'vnet-peering-governance'
	managedBy: 'AzureDemoEnv'
}
var leftTags = union(tags, { governanceDomain: 'left' })
var rightTags = union(tags, { governanceDomain: 'right' })
var leftVnetName = '${take(namePrefix, 40)}-left-vnet'
var rightVnetName = '${take(namePrefix, 39)}-right-vnet'

resource leftVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
	name: leftVnetName
	location: location
	tags: leftTags
	properties: {
		addressSpace: {
			addressPrefixes: [
				'10.30.0.0/16'
			]
		}
		subnets: [
			{
				name: 'left-app'
				properties: {
					addressPrefix: '10.30.1.0/24'
				}
			}
		]
	}
}

resource rightVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
	name: rightVnetName
	location: location
	tags: rightTags
	properties: {
		addressSpace: {
			addressPrefixes: [
				'10.40.0.0/16'
			]
		}
		subnets: [
			{
				name: 'right-app'
				properties: {
					addressPrefix: '10.40.1.0/24'
				}
			}
		]
	}
}

resource leftToRightPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
	parent: leftVnet
	name: 'to-right'
	properties: {
		remoteVirtualNetwork: {
			id: rightVnet.id
		}
		allowVirtualNetworkAccess: true
		allowForwardedTraffic: true
	}
}

resource rightToLeftPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
	parent: rightVnet
	name: 'to-left'
	properties: {
		remoteVirtualNetwork: {
			id: leftVnet.id
		}
		allowVirtualNetworkAccess: true
		allowForwardedTraffic: true
	}
}

output scenario string = 'vnet-peering-governance'
output resourcePrefix string = namePrefix
output selectedLocation string = location
output leftVnetResourceId string = leftVnet.id
output rightVnetResourceId string = rightVnet.id
output governanceNote string = 'ポリシー適用は subscription スコープで別デプロイとして運用します。'
