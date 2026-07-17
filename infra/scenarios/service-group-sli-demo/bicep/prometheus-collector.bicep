targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード。')
param scenarioCode string

@description('collector VM のリージョン。')
param location string

@description('Prometheus がスクレイプする App Service のホスト名。')
param apiHostName string

@description('Azure Monitor Workspace の metrics ingestion endpoint。')
param metricsIngestionEndpoint string

@description('collector VM の SSH 公開鍵。VM に inbound NSG rule は作成しない。')
@secure()
param adminSshPublicKey string

@description('collector VM のローカル管理者名。')
param adminUsername string = 'azureuser'

var suffix = toLower(uniqueString(subscription().id, resourceGroup().id, scenarioCode))
var shortSuffix = take(suffix, 6)
var namePrefix = toLower('${scenarioCode}-${shortSuffix}')
var collectorName = 'prom-${namePrefix}'
var tags = {
  scenario: 'service-group-sli-demo'
  scenarioCode: scenarioCode
  workload: 'observability'
}
var cloudInitTemplate = loadTextContent('../cloud-init/prometheus-collector.yaml')
var cloudInitWithApi = replace(cloudInitTemplate, '__API_HOST__', apiHostName)
var cloudInitWithEndpoint = replace(cloudInitWithApi, '__METRICS_INGESTION_ENDPOINT__', metricsIngestionEndpoint)

resource collectorIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${namePrefix}-prometheus'
  location: location
  tags: tags
}

resource collectorPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${collectorName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource collectorNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${collectorName}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource collectorVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${collectorName}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/24'
      ]
    }
    subnets: [
      {
        name: 'collector'
        properties: {
          addressPrefix: '10.42.0.0/27'
          networkSecurityGroup: {
            id: collectorNsg.id
          }
        }
      }
    ]
  }
}

resource collectorNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${collectorName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: collectorPublicIp.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', collectorVnet.name, 'collector')
          }
        }
      }
    ]
  }
}

resource collectorVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'vm-${collectorName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${collectorIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2als_v2'
    }
    osProfile: {
      computerName: take(collectorName, 15)
      adminUsername: adminUsername
      customData: base64(replace(cloudInitWithEndpoint, '__MANAGED_IDENTITY_CLIENT_ID__', collectorIdentity.properties.clientId))
      linuxConfiguration: {
        disablePasswordAuthentication: true
        patchSettings: {
          assessmentMode: 'AutomaticByPlatform'
          patchMode: 'AutomaticByPlatform'
        }
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              keyData: adminSshPublicKey
              path: '/home/${adminUsername}/.ssh/authorized_keys'
            }
          ]
        }
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      imageReference: {
        offer: 'ubuntu-24_04-lts'
        publisher: 'Canonical'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: collectorNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

output collectorIdentityName string = collectorIdentity.name
output collectorIdentityPrincipalId string = collectorIdentity.properties.principalId
output collectorIdentityResourceId string = collectorIdentity.id
output collectorVmName string = collectorVm.name
output collectorVmResourceId string = collectorVm.id
