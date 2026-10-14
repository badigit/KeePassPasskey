# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CertificatePath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedThumbprint
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
if ($cert.Thumbprint -ne $ExpectedThumbprint -or $cert.Subject -ne 'CN=badigit.KeePassPasskey') { throw 'Unexpected certificate' }
$codeSigning = $false
foreach ($extension in $cert.Extensions) {
    if ($extension -is [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension] -and $extension.CertificateAuthority) { throw 'CA certificates are not allowed' }
    if ($extension -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
        foreach ($usage in $extension.EnhancedKeyUsages) {
            if ($usage.Value -ne '1.3.6.1.5.5.7.3.3') { throw 'Only the code-signing EKU is allowed' }
            $codeSigning = $true
        }
    }
}
if (-not $codeSigning) { throw 'Code-signing EKU is required' }
Import-Certificate -FilePath $CertificatePath -CertStoreLocation Cert:/LocalMachine/TrustedPeople | Out-Null
if (-not (Test-Path -LiteralPath "Cert:/LocalMachine/TrustedPeople/$ExpectedThumbprint")) { throw 'Certificate trust could not be verified' }
