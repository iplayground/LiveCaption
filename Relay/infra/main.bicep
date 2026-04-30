targetScope = 'resourceGroup'

@description('Azure region for the Relay Function App resources.')
param location string = resourceGroup().location

@description('Globally unique Azure Functions app name.')
@minLength(2)
@maxLength(60)
param functionAppName string

@description('Globally unique Storage Account name for Functions host and deployment storage.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('App Service plan name for the Flex Consumption Function App.')
param functionPlanName string = '${functionAppName}-plan'

@description('Log Analytics workspace name for Relay logs.')
param logAnalyticsWorkspaceName string = '${functionAppName}-logs'

@description('Application Insights resource name for Relay telemetry.')
param applicationInsightsName string = '${functionAppName}-appi'

@description('Globally unique Azure Web PubSub resource name.')
@minLength(3)
@maxLength(63)
param webPubSubName string

@description('Azure Web PubSub SKU. Use Free_F1 while idle and Standard_S1 for events that need more than 20 concurrent clients.')
@allowed([
  'Free_F1'
  'Standard_S1'
  'Premium_P1'
])
param webPubSubSkuName string = 'Free_F1'

@description('Azure Web PubSub unit count. Free_F1 supports only 1 unit.')
@minValue(1)
param webPubSubUnitCount int = 1

@description('Azure Web PubSub hub used by Relay.')
param webPubSubHubName string = 'livecaption'

@description('Azure Web PubSub group used for live caption broadcasts.')
param webPubSubGroupName string = 'caption-live'

@description('Require the Portal-provided viewer access code when negotiating a viewer Web PubSub URL.')
param viewerAccessCodeRequired bool = true

@description('Existing Azure Speech resource group name.')
param speechResourceGroupName string = resourceGroup().name

@description('Existing Azure Speech account name used for request signature verification.')
param speechAccountName string

@description('GitHub repository in owner/name form.')
param githubRepository string = 'iplayground/LiveCaption'

@description('GitHub branch allowed to deploy through OIDC.')
param githubBranch string = 'main'

@description('Deployment package container name for Flex Consumption.')
param deploymentStorageContainerName string = 'app-package'

@description('Maximum Flex Consumption scale-out instance count.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 40

@description('Flex Consumption instance memory size in MB.')
@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048

@description('Common tags applied to Relay Azure resources.')
param tags object = {
  app: 'LiveCaption'
  component: 'Relay'
  environment: 'production'
}

var roleDefinitions = {
  storageBlobDataOwner: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  )
  storageQueueDataContributor: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  )
  storageTableDataContributor: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  )
  monitoringMetricsPublisher: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '3913510d-42f4-4e42-8a64-420c390055eb'
  )
  websiteContributor: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'de139f84-1756-47ae-9be6-808fbbe84772'
  )
  webPubSubServiceOwner: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '12cf5a90-567b-43ae-8102-96cf46c7d9b4'
  )
  cognitiveServicesUser: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'a97b65f3-24c7-4388-baec-2e87135dc908'
  )
}

var githubActionsIdentityName = '${functionAppName}-gh-oidc'
var githubOidcSubject = 'repo:${githubRepository}:ref:refs/heads/${githubBranch}'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    DisableLocalAuth: true
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentStorageContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource functionPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: functionPlanName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource githubActionsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: githubActionsIdentityName
  location: location
  tags: tags
}

resource githubFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: githubActionsIdentity
  name: 'github-${githubBranch}'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: 'https://token.actions.githubusercontent.com'
    subject: githubOidcSubject
  }
}

resource webPubSub 'Microsoft.SignalRService/webPubSub@2024-03-01' = {
  name: webPubSubName
  location: location
  tags: tags
  sku: {
    name: webPubSubSkuName
    capacity: webPubSubUnitCount
  }
  properties: {
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    tls: {
      clientCertEnabled: false
    }
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainer.name}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      runtime: {
        name: 'python'
        version: '3.13'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: 'https://${storage.name}.blob.${environment().suffixes.storage}'
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: 'https://${storage.name}.queue.${environment().suffixes.storage}'
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: 'https://${storage.name}.table.${environment().suffixes.storage}'
        }
        {
          name: 'AzureWebJobsDisableHomepage'
          value: 'true'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
          value: 'Authorization=AAD'
        }
        {
          name: 'AZURE_SPEECH_ACCOUNT_ID'
          value: resourceId(
            speechResourceGroupName,
            'Microsoft.CognitiveServices/accounts',
            speechAccountName
          )
        }
        {
          name: 'AZURE_WEBPUBSUB_ENDPOINT'
          value: 'https://${webPubSub.properties.hostName}'
        }
        {
          name: 'AZURE_WEBPUBSUB_HUB_NAME'
          value: webPubSubHubName
        }
        {
          name: 'AZURE_WEBPUBSUB_GROUP_NAME'
          value: webPubSubGroupName
        }
        {
          name: 'VIEWER_ACCESS_CODE_REQUIRED'
          value: string(viewerAccessCodeRequired)
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

resource storageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, roleDefinitions.storageBlobDataOwner)
  scope: storage
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitions.storageBlobDataOwner
  }
}

resource storageQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, roleDefinitions.storageQueueDataContributor)
  scope: storage
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitions.storageQueueDataContributor
  }
}

resource storageTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, roleDefinitions.storageTableDataContributor)
  scope: storage
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitions.storageTableDataContributor
  }
}

resource appInsightsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsights.id, functionApp.id, roleDefinitions.monitoringMetricsPublisher)
  scope: applicationInsights
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitions.monitoringMetricsPublisher
  }
}

resource githubWebsiteContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, githubActionsIdentity.id, roleDefinitions.websiteContributor)
  scope: functionApp
  properties: {
    principalId: githubActionsIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitions.websiteContributor
  }
}

resource webPubSubServiceOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(webPubSub.id, functionApp.id, roleDefinitions.webPubSubServiceOwner)
  scope: webPubSub
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitions.webPubSubServiceOwner
  }
}

module speechKeyReaderRole 'speech-role-assignment.bicep' = {
  name: 'speech-key-reader-role-${uniqueString(functionApp.id, speechAccountName)}'
  scope: resourceGroup(speechResourceGroupName)
  params: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: roleDefinitions.cognitiveServicesUser
    speechAccountName: speechAccountName
  }
}

output functionAppResourceId string = functionApp.id
output functionAppName string = functionApp.name
output relayEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/caption-events'
output managedIdentityPrincipalId string = functionApp.identity.principalId
output webPubSubResourceId string = webPubSub.id
output webPubSubName string = webPubSub.name
output webPubSubEndpoint string = 'https://${webPubSub.properties.hostName}'
output webPubSubHubName string = webPubSubHubName
output webPubSubGroupName string = webPubSubGroupName
output githubActionsIdentityClientId string = githubActionsIdentity.properties.clientId
output githubActionsIdentityPrincipalId string = githubActionsIdentity.properties.principalId
output githubActionsIdentityResourceId string = githubActionsIdentity.id
output githubOidcSubject string = githubOidcSubject
output githubRepository string = githubRepository
output githubBranch string = githubBranch
output tenantId string = tenant().tenantId
output subscriptionId string = subscription().subscriptionId
