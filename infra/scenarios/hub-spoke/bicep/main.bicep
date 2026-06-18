targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード')
param scenarioCode string = 'csa01'

@description('主デプロイリージョン')
param location string = 'southwestasia'

@description('スポーク VNet の数（1-4）')
param spokeCount int = 2

@description('Firewall の内部 IP アドレス')
param firewallPrivateIp string = '10.10.0.4'

var namePrefix = toLower('${scenarioCode}-${uniqueString(resourceGroup().id)}')
var tags = {
	scenario: 'hub-spoke'
	managedBy: 'AzureDemoEnv'
}

// ============ Hub VNet ============

var hubVnetName = '${take(namePrefix, 36)}-hub-vnet'
var hubNsgName = '${take(namePrefix, 35)}-hub-nsg'
var bastionNsgName = '${take(namePrefix, 32)}-bastion-nsg'
var firewallName = '${take(namePrefix, 34)}-fw'
var firewallPipName = '${take(namePrefix, 27)}-fw-pip'

// Hub NSG
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

// Bastion NSG
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
	name: bastionNsgName
	location: location
	tags: tags
	properties: {
		securityRules: [
			{
				name: 'allow-https-inbound'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 100
					protocol: 'Tcp'
					sourceAddressPrefix: '*'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '443'
				}
			}
			{
				name: 'allow-gateway-manager'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 110
					protocol: 'Tcp'
					sourceAddressPrefix: 'GatewayManager'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '443'
				}
			}
			{
				name: 'allow-rdp-ssh-outbound'
				properties: {
					access: 'Allow'
					direction: 'Outbound'
					priority: 100
					protocol: 'Tcp'
					sourceAddressPrefix: '*'
					sourcePortRange: '*'
					destinationAddressPrefix: 'VirtualNetwork'
					destinationPortRange: '22,3389'
				}
			}
		]
	}
}

// Firewall Public IP
resource firewallPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
	name: firewallPipName
	location: location
	tags: tags
	sku: {
		name: 'Standard'
		tier: 'Regional'
	}
	properties: {
		publicIPAllocationMethod: 'Static'
	}
}

// Hub VNet
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
					addressPrefix: '10.10.0.0/26'
				}
			}
			{
				name: 'AzureBastionSubnet'
				properties: {
					addressPrefix: '10.10.1.0/27'
					networkSecurityGroup: {
						id: bastionNsg.id
					}
				}
			}
			{
				name: 'GatewaySubnet'
				properties: {
					addressPrefix: '10.10.1.32/27'
				}
			}
			{
				name: 'hub-app'
				properties: {
					addressPrefix: '10.10.2.0/24'
					networkSecurityGroup: {
						id: hubNsg.id
					}
				}
			}
		]
	}
}

// Azure Firewall（スケルトンのみ、実装は別途）
resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
	name: firewallName
	location: location
	tags: tags
	properties: {
		sku: {
			name: 'AZFW_VNet'
			tier: 'Standard'
		}
		threatIntelMode: 'Alert'
		ipConfigurations: [
			{
				name: 'firewall-config'
				properties: {
					publicIPAddress: {
						id: firewallPip.id
					}
					subnet: {
						id: '${hubVnet.id}/subnets/AzureFirewallSubnet'
					}
				}
			}
		]
		networkRuleCollections: []
		applicationRuleCollections: []
		natRuleCollections: []
	}
}

// Azure Bastion（スケルトンのみ、実装は別途）
resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
	name: '${take(namePrefix, 35)}-bastion'
	location: location
	tags: tags
	sku: {
		name: 'Basic'
	}
	properties: {
		virtualNetwork: {
			id: hubVnet.id
		}
		disableCopyPaste: false
		enableTunneling: false
	}
}

// ============ Spoke VNets and Resources ============

var spokeConfigs = [for i in range(0, spokeCount): {
	index: i
	spokeNum: i + 1
	vnetName: '${take(namePrefix, 33)}-spoke-${i + 1}-vnet'
	vnetPrefix: '10.${20 + i}.0.0/16'
	vmSubnetPrefix: '10.${20 + i}.1.0/24'
	peSubnetPrefix: '10.${20 + i}.2.0/24'
	udrName: '${take(namePrefix, 32)}-spoke-${i + 1}-udr'
	nsgName: '${take(namePrefix, 31)}-spoke-${i + 1}-nsg'
}]

// Spoke NSGs
resource spokeNsgs 'Microsoft.Network/networkSecurityGroups@2023-11-01' = [for config in spokeConfigs: {
	name: config.nsgName
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
			{
				name: 'allow-rdp-from-bastion'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 110
					protocol: 'Tcp'
					sourceAddressPrefix: '10.10.1.0/27'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '3389'
				}
			}
			{
				name: 'allow-ssh-from-bastion'
				properties: {
					access: 'Allow'
					direction: 'Inbound'
					priority: 120
					protocol: 'Tcp'
					sourceAddressPrefix: '10.10.1.0/27'
					sourcePortRange: '*'
					destinationAddressPrefix: '*'
					destinationPortRange: '22'
				}
			}
		]
	}
}]

// Spoke UDRs (User Defined Routes)
resource spokeUdrs 'Microsoft.Network/routeTables@2023-11-01' = [for config in spokeConfigs: {
	name: config.udrName
	location: location
	tags: tags
	properties: {
		routes: [
			{
				name: 'to-firewall'
				properties: {
					addressPrefix: '0.0.0.0/0'
					nextHopType: 'VirtualAppliance'
					nextHopIpAddress: firewallPrivateIp
				}
			}
		]
	}
}]

// Spoke VNets
resource spokeVnets 'Microsoft.Network/virtualNetworks@2023-11-01' = [for (config, idx) in spokeConfigs: {
	name: config.vnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: [
				config.vnetPrefix
			]
		}
		subnets: [
			{
				name: 'spoke-vm'
				properties: {
					addressPrefix: config.vmSubnetPrefix
					networkSecurityGroup: {
						id: spokeNsgs[idx].id
					}
					routeTable: {
						id: spokeUdrs[idx].id
					}
				}
			}
			{
				name: 'spoke-pe'
				properties: {
					addressPrefix: config.peSubnetPrefix
					routeTable: {
						id: spokeUdrs[idx].id
					}
				}
			}
		]
	}
}]

// Hub to Spoke Peerings
resource hubToSpokePeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = [for (config, idx) in spokeConfigs: {
	parent: hubVnet
	name: 'to-spoke-${config.spokeNum}'
	properties: {
		remoteVirtualNetwork: {
			id: spokeVnets[idx].id
		}
		allowVirtualNetworkAccess: true
		allowForwardedTraffic: true
		allowGatewayTransit: true
	}
}]

// Spoke to Hub Peerings
resource spokeToHubPeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = [for (config, idx) in spokeConfigs: {
	parent: spokeVnets[idx]
	name: 'to-hub'
	properties: {
		remoteVirtualNetwork: {
			id: hubVnet.id
		}
		allowVirtualNetworkAccess: true
		allowForwardedTraffic: true
		useRemoteGateways: true
	}
}]

// ============ VMs in Spokes ============

// Windows VM images and Linux VM images
var windowsVmSku = {
	publisher: 'MicrosoftWindowsServer'
	offer: 'WindowsServer'
	sku: '2022-datacenter-azure-edition-smalldisk'
	version: 'latest'
}

var linuxVmSku = {
	publisher: 'Canonical'
	offer: '0001-com-ubuntu-server-focal'
	sku: '20_04-lts-gen2'
	version: 'latest'
}

// VM Network Interfaces - Windows VMs
resource winVmNics 'Microsoft.Network/networkInterfaces@2023-11-01' = [for (config, idx) in spokeConfigs: {
	name: '${take(namePrefix, 27)}-spoke${config.spokeNum}-win-nic'
	location: location
	tags: tags
	properties: {
		ipConfigurations: [
			{
				name: 'ipconfig1'
				properties: {
					subnet: {
						id: '${spokeVnets[idx].id}/subnets/spoke-vm'
					}
					privateIPAllocationMethod: 'Dynamic'
				}
			}
		]
	}
	dependsOn: [
		spokeVnets
	]
}]

// VM Network Interfaces - Linux VMs
resource lnxVmNics 'Microsoft.Network/networkInterfaces@2023-11-01' = [for (config, idx) in spokeConfigs: {
	name: '${take(namePrefix, 27)}-spoke${config.spokeNum}-lnx-nic'
	location: location
	tags: tags
	properties: {
		ipConfigurations: [
			{
				name: 'ipconfig1'
				properties: {
					subnet: {
						id: '${spokeVnets[idx].id}/subnets/spoke-vm'
					}
					privateIPAllocationMethod: 'Dynamic'
				}
			}
		]
	}
	dependsOn: [
		spokeVnets
	]
}]

// Windows Virtual Machines
resource winVms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for (config, idx) in spokeConfigs: {
	name: '${take(namePrefix, 28)}-spoke${config.spokeNum}-win'
	location: location
	tags: tags
	identity: {
		type: 'SystemAssigned'
	}
	properties: {
		hardwareProfile: {
			vmSize: 'Standard_B2s'
		}
		osProfile: {
			computerName: 'spoke${config.spokeNum}win'
			adminUsername: 'azureuser'
			windowsConfiguration: {
				enableAutomaticUpdates: true
				timeZone: 'Tokyo Standard Time'
			}
		}
		storageProfile: {
			imageReference: windowsVmSku
			osDisk: {
				createOption: 'FromImage'
				managedDisk: {
					storageAccountType: 'Premium_LRS'
				}
			}
		}
		networkProfile: {
			networkInterfaces: [
				{
					id: winVmNics[idx].id
					properties: {
						primary: true
					}
				}
			]
		}
	}
	dependsOn: [
		winVmNics
	]
}]

// Linux Virtual Machines
resource lnxVms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for (config, idx) in spokeConfigs: {
	name: '${take(namePrefix, 28)}-spoke${config.spokeNum}-lnx'
	location: location
	tags: tags
	identity: {
		type: 'SystemAssigned'
	}
	properties: {
		hardwareProfile: {
			vmSize: 'Standard_B2s'
		}
		osProfile: {
			computerName: 'spoke${config.spokeNum}lnx'
			adminUsername: 'azureuser'
			linuxConfiguration: {
				disablePasswordAuthentication: false
			}
		}
		storageProfile: {
			imageReference: linuxVmSku
			osDisk: {
				createOption: 'FromImage'
				managedDisk: {
					storageAccountType: 'Premium_LRS'
				}
			}
		}
		networkProfile: {
			networkInterfaces: [
				{
					id: lnxVmNics[idx].id
					properties: {
						primary: true
					}
				}
			]
		}
	}
	dependsOn: [
		lnxVmNics
	]
}]

// ============ Outputs ============

output scenario string = 'hub-spoke'
output resourcePrefix string = namePrefix
output selectedLocation string = location
output spokeCount int = spokeCount
output hubVnetResourceId string = hubVnet.id
output hubVnetName string = hubVnetName
output firewallName string = firewallName
output firewallPrivateIp string = firewallPrivateIp
output bastionName string = bastion.name
output vmDeploymentNote string = 'Windows VM (×${spokeCount}) + Linux VM (×${spokeCount}) deployed in spoke subnets'
