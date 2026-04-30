param(
    [string] $ResourceGroup = "iplayground",

    [Parameter(Mandatory = $true)]
    [string] $FunctionAppName,

    [Parameter(Mandatory = $true)]
    [string] $WebPubSubName,

    [Parameter(Mandatory = $true)]
    [string] $WebPubSubSku,

    [Parameter(Mandatory = $true)]
    [string] $WebPubSubTier,

    [Parameter(Mandatory = $true)]
    [string] $WebPubSubSize,

    [Parameter(Mandatory = $true)]
    [int] $WebPubSubUnitCount,

    [Parameter(Mandatory = $true)]
    [string] $ViewerAccessCodeRequired,

    [string] $SpeechResourceGroup = "iplayground",

    [Parameter(Mandatory = $true)]
    [string] $SpeechAccountName,

    [Parameter(Mandatory = $true)]
    [string] $SpeechSku
)

$ErrorActionPreference = "Stop"
$null = Disable-AzContextAutosave -Scope Process
$context = (Connect-AzAccount -Identity).Context
$null = Set-AzContext -Context $context
$SubscriptionId = $context.Subscription.Id

$functionAppId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$FunctionAppName"

function Set-ViewerAccessCodeRequired {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    $appSettingsResponse = Invoke-AzRestMethod `
        -Method POST `
        -Path "$functionAppId/config/appsettings/list?api-version=2024-04-01"

    $appSettingsPayload = $appSettingsResponse.Content | ConvertFrom-Json
    $settings = @{}
    foreach ($property in $appSettingsPayload.properties.PSObject.Properties) {
        $settings[$property.Name] = $property.Value
    }
    $settings["VIEWER_ACCESS_CODE_REQUIRED"] = $Value

    $appSettingsBody = @{
        properties = $settings
    } | ConvertTo-Json -Depth 20

    Invoke-AzRestMethod `
        -Method PUT `
        -Path "$functionAppId/config/appsettings?api-version=2024-04-01" `
        -Payload $appSettingsBody | Out-Null
}

if ($ViewerAccessCodeRequired -eq "true") {
    Set-ViewerAccessCodeRequired -Value $ViewerAccessCodeRequired
}

$webPubSubId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.SignalRService/webPubSub/$WebPubSubName"
$webPubSubBody = @{
    sku = @{
        name = $WebPubSubSku
        tier = $WebPubSubTier
        size = $WebPubSubSize
        capacity = $WebPubSubUnitCount
    }
} | ConvertTo-Json -Depth 8

Invoke-AzRestMethod `
    -Method PATCH `
    -Path "$webPubSubId`?api-version=2024-03-01" `
    -Payload $webPubSubBody | Out-Null

$speechId = "/subscriptions/$SubscriptionId/resourceGroups/$SpeechResourceGroup/providers/Microsoft.CognitiveServices/accounts/$SpeechAccountName"
$speechBody = @{
    sku = @{
        name = $SpeechSku
    }
} | ConvertTo-Json -Depth 8

Invoke-AzRestMethod `
    -Method PATCH `
    -Path "$speechId`?api-version=2024-10-01" `
    -Payload $speechBody | Out-Null

if ($ViewerAccessCodeRequired -ne "true") {
    Set-ViewerAccessCodeRequired -Value $ViewerAccessCodeRequired
}

Write-Output "Applied LiveCaption SKU mode."
Write-Output "WebPubSub=$WebPubSubSku, Speech=$SpeechSku, VIEWER_ACCESS_CODE_REQUIRED=$ViewerAccessCodeRequired"
