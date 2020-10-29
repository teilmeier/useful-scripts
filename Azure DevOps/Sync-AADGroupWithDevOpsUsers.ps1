# Modules
$aadModule = Get-Module AzureAD
if ($aadModule.Version.Major -lt 2)
{
  Install-Module AzureAD -AllowClobber
}

# Configuration
$azdoOrganization = "Your org name. Not the URL."
$azdoPersonalToken = "PAT with vso.memberentitlementmanagement and vso.memberentitlementmanagement_write permissions"
$aadTenantId = "Your Azure AD Tenant Id Guid"
#$aadAppId = "Azure AD App ID or Client ID" # required for non-interactive login
#$aadClientCetificateThumbprint = "Certificate Thumbprint" # required for non-interactive login
$aadGroupName = "Azure AD Group that should be synchronized"

# Define 5 Users that consume the free basic licenses. They are not allowed to access TFS or Azure DevOps Server.
$dummyPrincipalNames = @("user1@example.com", "user2@example.com", "user3@example.com", "user4@example.com", "user5@example.com")

# Authenticate Azure AD
if ($null -eq $aadConnection.Account)
{
  if ($null -eq $aadAppId -or $null -eq $aadClientCetificateThumbprint)
  {
    $aadConnection = Connect-AzureAD -TenantId $aadTenantId
  } else 
  {
    $aadConnection = Connect-AzureAD -TenantId $aadTenantId -ApplicationId $aadAppId -CertificateThumbprint $aadClientCetificateThumbprint
  }
}
$aadGroup = Get-AzureADGroup -Filter "DisplayName eq '$aadGroupName'"

# Generate authentication header for Azure DevOps
Write-Host "Initialize authentication context" -ForegroundColor Yellow
$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($azdoPersonalToken)"))
$header = @{authorization = "Basic $token"}

# Get group members
$aadGroupMembers = Get-AzureADGroupMember -ObjectId $aadGroup.ObjectId

# Get access levels (filter for Basic users only)
$entitlementsListUrl = "https://vsaex.dev.azure.com/$azdoOrganization/_apis/userentitlements?`$filter=licenseId eq 'Account-Express'&top=10000&api-version=5.1-preview.3"
$entitlementsListResponse = Invoke-RestMethod -Uri $entitlementsListUrl -Method Get -ContentType "application/json" -Headers $header

# Get differences
$entitlementsPrincipalNames = $entitlementsListResponse.members | Select-Object * -ExpandProperty user | Select-Object principalName, id
$aadGroupPrincipalNames = $aadGroupMembers | Select-Object UserPrincipalName, ObjectId, DisplayName

$entitlementsToBeDeleted = $entitlementsPrincipalNames | Where-Object { -not ($aadGroupPrincipalNames.UserPrincipalName -contains $_.principalName -or $dummyPrincipalNames -contains $_.principalName ) }
$entitlementsToBeAdded = $aadGroupPrincipalNames | Where-Object { -not ($entitlementsPrincipalNames.principalName -contains $_.UserPrincipalName) }

if ($entitlementsToBeDeleted.Count + $entitlementsToBeAdded.Count -eq 0)
{
  Write-Output "No changes detected!"
  return
}

# Create update request
$entitlementsUpdateBody = "["

foreach ($entitlementToBeDeleted in $entitlementsToBeDeleted)
{
  Write-Output "Removing user $($entitlementToBeDeleted.principalName)"
  $entitlementsUpdateBody += @"
  {
    "from": "",
    "op": "remove",
    "path": "/$($entitlementToBeDeleted.id)",
    "value": ""
  },
"@ # Important: No space before "@
}

foreach ($entitlementToBeAdded in $entitlementsToBeAdded)
{
  Write-Output "Adding user $($entitlementToBeAdded.UserPrincipalName)"
  $entitlementsUpdateBody += @"
  {
    "from": "",
    "op": "add",
    "path": "",
    "value": {
      "accessLevel": {
          "licensingSource": "account",
          "accountLicenseType": "express",
          "msdnLicenseType": "none",
          "licenseDisplayName": "Basic",
          "status": "active",
          "statusMessage": "",
          "assignmentSource": "unknown"
      },
      "user": {
          "displayName": "$($entitlementToBeAdded.DisplayName)",
          "origin": "aad",
          "originId": "$($entitlementToBeAdded.ObjectId)",
          "principalName": "$($entitlementToBeAdded.UserPrincipalName)",
          "subjectKind": "user"
      }
    }
  },
"@ # Important: No space before "@
}

$entitlementsUpdateBody = $entitlementsUpdateBody.TrimEnd(",")
$entitlementsUpdateBody += "]"

$entitlementsUpdateUrl = "https://vsaex.dev.azure.com/$azdoOrganization/_apis/userentitlements?doNotSendInviteForNewUsers=true&top=10000&api-version=5.1-preview.3"

$entitlementsUpdateResponse = Invoke-RestMethod -Uri $entitlementsUpdateUrl -Method Patch -ContentType "application/json-patch+json" -Headers $header -Body $entitlementsUpdateBody
$entitlementsUpdateResponse.results
