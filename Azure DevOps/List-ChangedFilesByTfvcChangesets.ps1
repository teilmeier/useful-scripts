# Configuration
$orgUrl = "https://dev.azure.com/<OrgName>"
$projectName = "ProjectName"
$personalToken = "Azure DevOps PAT"

# Generate authentication header
Write-Host "Initialize authentication context" -ForegroundColor Yellow
$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($personalToken)"))
$header = @{authorization = "Basic $token"}

# Get work items with relations
$workItemIds = @("280", "281")
$witUrl = "$($orgUrl)/$projectName/_apis/wit/workitemsbatch?api-version=5.1"
$witRequestBody = @"
{
    "`$expand" : "relations",
    "ids": [
      $($workItemIds -join ", ")
    ]
  }
"@
$workitems = Invoke-RestMethod -Uri $witUrl -Method Post -ContentType "application/json" -Headers $header -Body $witRequestBody

# Get changeset IDs from work items
$changesetIds = @()
$workitems.value | ForEach-Object {
    $changesetIds += $_.relations | Where-Object { $_.attributes.name -eq "Fixed in Changeset" } | Select-Object  @{E={$_.url.split('/')[5]};L="ChangesetID"}
}
$changesetIds = $changesetIds | Select-Object ChangesetID -Unique

# Get unique changed or added files form changesets
$changesUrl = "$($orgUrl)/_apis/tfvc/changesets/{0}/changes?api-version=5.1"
$changes = @()
$changesetIds | ForEach-Object {
    $changedFiles = Invoke-RestMethod -Uri ([string]::Format($changesUrl, $_.ChangesetID)) -Method Get -ContentType "application/json" -Headers $header
    $changes += $changedFiles.value | Select-Object @{E={$_.item.path};L="ChangedFile"}
}
$changes = $changes | Select-Object ChangedFile -Unique

# Display file paths
$changes