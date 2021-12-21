# REMARK: This code reflects my best knowledge about identifying 
#         Java App Services in Azure Subscriptions. Before execution
#         please validate and use it on your own risk.

function Get-JavaAppServices {
  param (
    [guid] $SubscriptionId,
    [bool] $WarnOnContainer = $true
  )
  
  Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null
  $AppServices = Get-AzWebApp

  foreach ($appService in $AppServices) {
    Get-AppServiceRuntime -Context $appService -WarnOnContainer $WarnOnContainer
  }
}

function Get-AppServiceRuntime {
  param (
    [Microsoft.Azure.Management.WebSites.Models.Site] $Context,
    [bool] $WarnOnContainer = $true
  )

  $KindDetails = $Context.Kind.ToLower().Split(',')

  # Use "Reserved" property instead of $KindDetails.Contains("linux")
  # https://azure.github.io/AppService/2021/08/31/Kind-property-overview.html
  $IsLinuxAppService = $Context.Reserved
  $IsContainerBased = $KindDetails.Contains("container")
  $IsWebApp = $KindDetails.Contains("app")
  $IsFunctionApp = $KindDetails.Contains("functionapp")
  $OutputMessage = ""
  $IsJavaAppService = $false

  if ($IsContainerBased -and $WarnOnContainer) {
    # No automatic recognition of runtime inside container
    $OutputMessage = "Warning: Check for Java Runtime inside container manually"
    
  }
  elseif ($IsWebApp -and $IsLinuxAppService) {
    # Read LinuxFxVersion on Linux Web Apps to get Runtime Stack
    $webApp = Get-AzWebApp -ResourceGroupName $Context.ResourceGroup -Name $Context.Name
    if ($webApp.SiteConfig.LinuxFxVersion.ToLower().Contains("java")) {
      $IsJavaAppService = $true
    }
  }
  elseif ($IsWebApp -and -not $IsLinuxAppService) {
    # Config Metadata property "CURRENT_STACK" is set to the runtime stack if the App Service is not running .NET
    $webApp = Get-AzWebApp -ResourceGroupName $Context.ResourceGroup -Name $Context.Name

    $metadataResponse = Invoke-AzRestMethod -Uri "https://management.azure.com$($webApp.Id)/config/metadata/list?api-version=2020-06-01" -Method POST
    $metadata = $metadataResponse.Content | ConvertFrom-Json

    if ($metadata.properties.CURRENT_STACK -eq "java") {
      $IsJavaAppService = $true
    }
  }
  elseif ($IsFunctionApp) {
    # Same recognition logic for Windows and Linux Functions
    $appSettings = Get-AzFunctionAppSetting -ResourceGroupName $Context.ResourceGroup -Name $Context.Name
    if ($appSettings["FUNCTIONS_WORKER_RUNTIME"] -eq "java") {
      $IsJavaAppService = $true
    }
  }
  else {
    $OutputMessage = "Warning: Unhandeled App Service Type"
  }

  if($IsJavaAppService) {
    $OutputMessage = "Java App Service found"
  }

  if($OutputMessage.Length -gt 0) {
    Write-Output "$OutputMessage {Resource Id: $($Context.Id), IsLinuxAppService: $IsLinuxAppService, IsContainerBased: $IsContainerBased, IsWebApp: $IsWebApp, IsFunctionApp: $IsFunctionApp}"
  }
}

$Subscriptions = Get-AzSubscription | Where-Object State -eq "Enabled"

foreach ($subscription in $Subscriptions) {
  Get-JavaAppServices -SubscriptionId $subscription.Id -WarnOnContainer $true
}