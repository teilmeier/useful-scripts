####################
# Prerequisites
#
# 0. Store secets in a secure place like Azure Key Vault and retrieve them from there. At least:
#    - App Registration's ClientId
#    - Azure AD user's UserName
#    - Azure AD user's Password

$tenantId = "<<GUID>>"
$subscriptionId = "<<GUID>>"
$keyVaultName = "<<NAME>"
Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId
#
# 1. Azure AD App Registration with:
#    - A Redirect URI like "https://localhost"
#    - "Allow public client flows" enabled for non-interactive ROPC sign-in
#    - API Permissions for "Azure DevOps" -> "user_impersonation" scope
#    - Optional: "User assignment required?" enabled
$clientId = Get-AzKeyVaultSecret -VaultName $keyVaultName -SecretName "azureDevOpsPATManagementClientId" -AsPlainText
$scope = "499b84ac-1321-427f-aa17-267ca6975798/.default" # Azure DevOps (well-known - do not change)
$redirectUri = "https://localhost"
#
# 2. An administrative/technical Azure AD user for:
#    - Requesting an Azure AD Access Token
#    - Owning and managing the Azure DevOps PAT(s)
#    - Optional: Assignment to App Registration Enterprise Application
$userName = Get-AzKeyVaultSecret -VaultName $keyVaultName -SecretName "azureDevOpsPATManagementUserName" -AsPlainText
$password = Get-AzKeyVaultSecret -VaultName $keyVaultName -SecretName "azureDevOpsPATManagementPassword" -AsPlainText
#
# 3. A consent to allow the App Registration access on the Azure DevOps API
#    - For the administrative/technical Azure AD user only or for all users by perfoming an admin consent
#    - Admin consent documentation: https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-admin-consent
Start-Process "https://login.microsoftonline.com/$tenantId/v2.0/adminconsent?client_id=$clientId&scope=$scope&redirect_uri=$redirectUri" # Admin Consent
Start-Process "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize?client_id=$clientId&scope=$scope&redirect_uri=$redirectUri&response_type=code" # User Consent
#
# 4. An Azure DevOps Organization
#    - Azure AD user has to be added to the organization
$orgName = "<<OrgName>>"
#
####################

####################
# Token Management
####################

$tokenName = "AgentRegistration"
$tokenScope = "vso.agentpools_manage"

####################
# Get Access Token using ROPC Flow
# https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth-ropc

$tokenResponse = Invoke-WebRequest -Method Post -ContentType "application/x-www-form-urlencoded" -Body "client_id=$clientId&scope=$scope&username=$userName&password=$password&grant_type=password" -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$accessToken = ($tokenResponse.Content | ConvertFrom-Json).access_token
$accessTokenSecureString = (ConvertTo-SecureString -AsPlainText $accessToken)

$patApiBase = "https://vssps.dev.azure.com/$orgName/_apis/Tokens/Pats?api-version=6.1-preview"

####################
# Create PAT
# https://docs.microsoft.com/en-us/rest/api/azure/devops/tokens/pats/create?view=azure-devops-rest-6.1
$expiryDate = (Get-Date -AsUTC).AddHours(1)
$expiryDateString = $expiryDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
$createPatBody = @"
{
  "displayName": "$tokenName",
  "scope": "$tokenScope",
  "validTo": "$expiryDateString",
  "allOrgs": false
}
"@
$createPatResponse = Invoke-WebRequest -Method Post -ContentType "application/json" -Authentication "Bearer" -Token $accessTokenSecureString -Body $createPatBody -Uri "$patApiBase"
$newPat = ($createPatResponse.Content | ConvertFrom-Json).patToken
$newPat

####################
# List PATs
# https://docs.microsoft.com/en-us/rest/api/azure/devops/tokens/pats/list?view=azure-devops-rest-6.1
$listPatsResponse = Invoke-WebRequest -Method Get -Authentication "Bearer" -Token $accessTokenSecureString -Uri "$patApiBase&displayFilterOption=active"
$pats = ($listPatsResponse.Content | ConvertFrom-Json).patTokens
$pats

####################
# Get PAT
# https://docs.microsoft.com/en-us/rest/api/azure/devops/tokens/pats/get?view=azure-devops-rest-6.1
$authorizationId = ($pats | Where-Object displayName -eq $tokenName).authorizationId
$getPatResponse = Invoke-WebRequest -Method Get -Authentication "Bearer" -Token $accessTokenSecureString -Uri "$patApiBase&authorizationId=$authorizationId"
$pat = ($getPatResponse.Content | ConvertFrom-Json).patToken
$pat

####################
# Update PAT
# https://docs.microsoft.com/en-us/rest/api/azure/devops/tokens/pats/update?view=azure-devops-rest-6.1
$authorizationId = ($pats | Where-Object displayName -eq $tokenName).authorizationId
$newExpiryDate = (Get-Date -AsUTC).AddHours(1)
$newExpiryDateString = $newExpiryDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
$updatePatBody = @"
{
  "authorizationId": "$authorizationId",
  "displayName": "$tokenName",
  "scope": "vso.machinegroup_manage",
  "validTo": "$newExpiryDateString",
  "allOrgs": false
}
"@
$updatePatResponse = Invoke-WebRequest -Method Put -ContentType "application/json" -Authentication "Bearer" -Token $accessTokenSecureString -Body $updatePatBody -Uri "$patApiBase"
$updatedPat = ($updatePatResponse.Content | ConvertFrom-Json).patToken
$updatedPat

####################
# Revoke PAT
# https://docs.microsoft.com/en-us/rest/api/azure/devops/tokens/pats/revoke?view=azure-devops-rest-6.1
$authorizationId = ($pats | Where-Object displayName -eq $tokenName).authorizationId
$revokePatResponse = Invoke-WebRequest -Method Delete -Authentication "Bearer" -Token $accessTokenSecureString -Uri "$patApiBase&authorizationId=$authorizationId"
