targetScope = 'resourceGroup'

@description('生成される名前に使用するシナリオコード。例: csa01')
param scenarioCode string = 'csa01'

@description('主デプロイリージョン')
param location string = 'southwestasia'

var namePrefix = toLower('${scenarioCode}-${uniqueString(resourceGroup().id)}')

// 新規シナリオ向けの最小テンプレート。
output scenarioName string = namePrefix
output scenarioLocation string = location
