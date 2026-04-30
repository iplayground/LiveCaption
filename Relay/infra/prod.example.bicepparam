using './main.bicep'

param location = 'japaneast'
param functionAppName = '<function-app-name>'
param storageAccountName = '<storage-account-name>'
param functionPlanName = '<function-plan-name>'
param logAnalyticsWorkspaceName = '<log-analytics-workspace-name>'
param applicationInsightsName = '<application-insights-name>'
param webPubSubName = '<web-pubsub-name>'
param webPubSubSkuName = 'Free_F1'
param webPubSubUnitCount = 1
param webPubSubHubName = 'livecaption'
param webPubSubGroupName = 'caption-live'
param viewerAccessCodeRequired = true
param speechResourceGroupName = 'iplayground'
param speechAccountName = '<speech-account-name>'
param githubRepository = 'iplayground/LiveCaption'
param githubBranch = 'main'
