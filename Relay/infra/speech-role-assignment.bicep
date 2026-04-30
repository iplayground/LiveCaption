targetScope = 'resourceGroup'

@description('Existing Azure Speech account name.')
param speechAccountName string

@description('Principal id of the Relay Function App managed identity.')
param principalId string

@description('Role definition id to assign on the Speech account.')
param roleDefinitionId string

resource speechAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: speechAccountName
}

resource speechKeyReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(speechAccount.id, principalId, roleDefinitionId)
  scope: speechAccount
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
  }
}
