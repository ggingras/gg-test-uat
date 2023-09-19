targetScope = 'subscription'

@description('The is primary name that will be will be prefixed to every resource in combination with the environment')
@minLength(3)
@maxLength(24)
param namingPrefix string

@description('The application environment to be deployed, is combined with the naming prefix for all resources')
@allowed([
  'dev'
  'qa'
  'prod'
])
param environmentName string

@description('The location in which all the resources will be provisioned')
@minLength(3)
@maxLength(15)
param location string

@description('The app service plan SKU size to be deployed')
@allowed([
  'F1'
  'D1'
  'B1'
  'S1'
])
@minLength(2)
@maxLength(15)
param appServicePlanSKU string

@description('The sql server database server SQL tier to be deployed')
@allowed([
  'Basic'
  'Standard'
  'GeneralPurpose'
])
@minLength(2)
@maxLength(15)
param sqlTier string

@description('The sql server database server SKU name to be deployed')
@allowed([
  'Basic'
  'S0'
  'GP_S_Gen5_1'
])
@minLength(2)
@maxLength(15)
param sqlSkuName string

@description('Maximum size of the sql database')
@allowed([
  1073741824
  5368709120
  10737418240
])
param sqlSize int

@description('Tag object that will be applied to every resource created in the current environment')
param globalTags object = {}

// Creates the Azure resource group
resource resource_group 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${namingPrefix}-${environmentName}-rg'
  location: location
  tags: globalTags
  managedBy: 'string'
  properties: {}
}

// Creates all the Azure resources in the resource group, Cosmos DB, App Service Plan, Web App Service, Configuration
module environment 'modules/app-service-azsql-db.bicep' = {
  name: '${namingPrefix}-${environmentName}'
  scope: resource_group
  params: {
    name: '${namingPrefix}-${environmentName}'
    location: location
    sqlSize: sqlSize
    sqlTier: sqlTier
    sqlSkuName: sqlSkuName
    skuName: appServicePlanSKU
    globalTags: globalTags
  }
}
