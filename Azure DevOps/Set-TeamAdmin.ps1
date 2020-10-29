# Configuration
$orgName = "OrgName"
$projectName = "Project"
$teamName = "Project Team"
$adminGroupNameOrUserUpn = "[Project]]\My Custom Group" # Valid formats "[ProjectName]\Group Name", "userid@domain.tld", "Collection Group Name"
$personalToken = "PAT" # Required scopes: vso.identity (read), vso.security_manage

# Generate authentication header
Write-Host "Initialize authentication context" -ForegroundColor Yellow
$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($personalToken)"))
$header = @{authorization = "Basic $token"}

# Get team
$getTeamIdentityUrl = "https://vssps.dev.azure.com/$orgName/_apis/identities?searchFilter=LocalGroupName&filterValue=[$projectName]\$teamName&queryMembership=None&api-version=6.0"
$teamIdentity =  Invoke-RestMethod -Uri $getTeamIdentityUrl -Method Get -Headers $header

$projectId = $teamIdentity.value[0].properties.LocalScopeId.'$value'
$teamId = $teamIdentity.value[0].id;

# Get user/group identity
$getAdminIdentityUrl = "https://vssps.dev.azure.com/$orgName/_apis/identities?searchFilter=AccountName&filterValue=$adminGroupNameOrUserUpn&queryMembership=None&api-version=6.0"
$adminIdentity = Invoke-RestMethod -Uri $getAdminIdentityUrl -Method Get -Headers $header

$adminIdentityDescriptor = $adminIdentity.value[0].descriptor.Replace("\", "\\")

# Get Identity Security Namespace
$getSecurityNamespacesUrl = "https://dev.azure.com/$orgName/_apis/securitynamespaces?api-version=6.0"
$securityNamespaces = Invoke-RestMethod -Uri $getSecurityNamespacesUrl -Method Get -Headers $header

$identitySecurityNamespaceId = ($securityNamespaces.value | Where-Object name -eq "Identity").namespaceId

# Assign user/group as team admin
$assignTeamAdminUrl = "https://dev.azure.com/$orgName/_apis/accesscontrolentries/$($identitySecurityNamespaceId)" + "?api-version=6.0"

$assignTeamAdminBody = @"
{
  "token": "$projectId\\$teamId",
  "merge": true,
  "accessControlEntries": [
    {
      "descriptor": "$adminIdentityDescriptor",
      "allow": 31
    }
  ]
}
"@

$result = Invoke-RestMethod -Uri $assignTeamAdminUrl -Method Post -ContentType "application/json" -Headers $header -Body $assignTeamAdminBody

$result