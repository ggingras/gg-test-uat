@description('Naming prefix for resources')
param name string

@minLength(3)
@maxLength(15)
@description('The Azure region in which the resource will be deployed')
param location string

@description('The sql Sku Tier')
param sqlTier string

@minLength(2)
@maxLength(15)
@description('The SKU name of the sql server')
param sqlSkuName string

@description('Maximum throughput for the container')
@minValue(1073741824)
@maxValue(10737418240)
param sqlSize int

@minLength(2)
@maxLength(15)
@description('The Azure region in which the Application Service Plan will be deployed')
param skuName string

@description('Tag object that will be applied to every resource created in the current environment')
param globalTags object = {}

resource log_analytics_workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${name}-la'
  location: location
  properties: {
    sku: {
      name: 'Standalone'
    }
  }
}

resource application_insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${name}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: log_analytics_workspace.id
  }
}

// Creates the App Service Plan
resource app_service_plan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: format('${name}-asp')
  location: location
  tags: globalTags
  sku: {
    name: skuName
    capacity: 1
  }
  kind: 'windows'
}

var sql_server_name = '${name}-sql'
var sql_database_name = '${name}-sqldb'
// Creates the Web App service off the App Service Plan with a Managed Identity
resource web_app 'Microsoft.Web/sites@2022-03-01' = {
  name: format('${name}-app')
  location: location
  tags: globalTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: app_service_plan.id
    httpsOnly: true
    siteConfig: {
      http20Enabled: true
      netFrameworkVersion: 'v6.0'
      ftpsState: 'FtpsOnly'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: application_insights.properties.ConnectionString
        }
      ]
      connectionStrings: [
        {
          name: 'MyDbConnection'
          connectionString: 'Server=tcp:${sql_server_name}${environment().suffixes.sqlServerHostname};Authentication=Active Directory Default; Database=${sql_database_name};'
          type: 'SQLServer'
        }
      ]
    }
  }
  kind: 'windows'
}

// Configure the Web App to the dotnet stack
resource web_app_config 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'metadata'
  kind: 'string'
  parent: web_app
  properties: {
    CURRENT_STACK: 'dotnet'
  }
}

// Creates an Azure SQL Server
resource sql_server 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sql_server_name
  location: location
  tags: globalTags
  properties: {
    minimalTlsVersion: '1.2'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Application'
      login: web_app.name
      sid: web_app.identity.principalId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource sql_firewall 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  parent: sql_server
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Creates a SQL Server Contributor Role
// Built-in Role definition IDs sourced from https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
resource sqlDbContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: sql_server
  name: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
}

// Grant the Contributor role to the App Service Identity
resource sql_server_contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sqlDbContributorRole.name, sql_server.name)
  scope: sql_server
  properties: {
    roleDefinitionId: sqlDbContributorRole.id
    principalId: web_app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Creates a Azure SQL Database
resource sql_database 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  name: sql_database_name
  parent: sql_server
  location: location
  tags: globalTags
  sku: {
    name: sqlSkuName
    tier: sqlTier
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: sqlSize
  }
}
