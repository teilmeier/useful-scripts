$aadTenantId = "Azure AD Tenant ID Guid"
$password  = "Your certificate password"
$cerificateFileName = "examplecert.pfx"
Connect-AzureAD -TenantId $aadTenantId

# Create the self signed cert
$currentDate = Get-Date
$endDate  = $currentDate.AddYears(1)
$notAfter  = $endDate.AddYears(1)
$thumb = (New-SelfSignedCertificate -CertStoreLocation cert:\localmachine\my -DnsName AzureADPowerShellModule.local -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter $notAfter).Thumbprint
$password = ConvertTo-SecureString -String $password -Force -AsPlainText
Export-PfxCertificate -cert "cert:\localmachine\my\$thumb" -FilePath $cerificateFileName -Password $password
$pfxPath = (Get-Item $cerificateFileName).FullName

# Load the certificate
$cert  = New-Object System.Security.Cryptography.X509Certificates.X509Certificate($pfxPath , $password)
$keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())

# Create the Azure Active Directory Application
$application = Get-AzureADApplication -Filter "DisplayName eq 'AzureADPowerShellModule'"
if ($null -eq $application)
{
    $application = New-AzureADApplication -DisplayName "AzureADPowerShellModule" -IdentifierUris "https://AzureADPowerShellModule"
}
New-AzureADApplicationKeyCredential -ObjectId $application.ObjectId -CustomKeyIdentifier "AzureADPowerShellModule" -StartDate $currentDate -EndDate $endDate -Type AsymmetricX509Cert -Usage Verify -Value $keyValue

# Create the Service Principal and connect it to the Application
$sp = Get-AzureADServicePrincipal -Filter "AppId eq '$($application.AppId)'"
{
    $sp = New-AzureADServicePrincipal -AppId $application.AppId
}

# Give the Service Principal Reader access to the current tenant (Get-AzureADDirectoryRole)
$role = Get-AzureADDirectoryRole -Filter "DisplayName eq 'Directory Readers'"
Add-AzureADDirectoryRoleMember -ObjectId $role.ObjectId -RefObjectId $sp.ObjectId

Write-Output "Use these credentials for a non-interactive sign-in to Azure AD"
Write-Output "Connect-AzureAD -TenantId $aadTenantId -ApplicationId $($sp.AppId) -CertificateThumbprint $thumb"
