# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$KeepStore)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $repoRoot 'build/controlled'
$provenance = Get-Content -LiteralPath (Join-Path $buildRoot 'provenance.json') -Raw | ConvertFrom-Json
if ($provenance.dirty -or -not $provenance.signed) { throw 'A clean, signed controlled build is required' }
$package = Join-Path $buildRoot 'KeePassPasskey-Controlled_1.4.1.0_x64.msix'
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne $provenance.packageSha256) { throw 'Signed package hash mismatch' }
$certificatePath = Join-Path $buildRoot 'ControlledBuild.cer'
$cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
if ($cert.Subject -ne 'CN=badigit.KeePassPasskey' -or $cert.Thumbprint -ne $provenance.signingCertificate) { throw 'Certificate does not match provenance' }
$signature = Get-AuthenticodeSignature -LiteralPath $package
if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $cert.Thumbprint) { throw 'Unexpected package signer' }
if (-not (Test-Path -LiteralPath "Cert:/CurrentUser/TrustedPeople/$($cert.Thumbprint)")) {
    Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:/CurrentUser/TrustedPeople | Out-Null
}
Add-AppxPackage -Path $package -ErrorAction Stop
$installed = Get-AppxPackage -Name 'Badigit.KeePassPasskey'
if (-not $installed -or $installed.Version -ne '1.4.1.0' -or $installed.PackageFamilyName -ne 'Badigit.KeePassPasskey_v6qz1enbfjpbm') { throw 'Installed identity mismatch' }
$exe = Join-Path $installed.InstallLocation 'KeePassPasskeyProvider/KeePassPasskeyProvider.exe'
$registration = Start-Process -FilePath $exe -ArgumentList '/register' -WindowStyle Hidden -PassThru
if (-not $registration.WaitForExit(20000)) { throw 'Provider registration timed out' }
if ($registration.ExitCode -ne 0) { throw 'Provider registration failed; Store package retained' }
if (-not $KeepStore) {
    $store = Get-AppxPackage -Name '51133UweKgel.KeePassPasskey'
    if ($store) {
        $backup = Join-Path $env:LOCALAPPDATA ('KeePassPasskey-migration/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $backup 'previous-package.json'), ($store | Select-Object Name,Version,PackageFullName,PackageFamilyName | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        $oldState = Join-Path $env:LOCALAPPDATA "Packages/$($store.PackageFamilyName)/LocalState"
        if (Test-Path -LiteralPath $oldState) { Copy-Item -LiteralPath $oldState -Destination (Join-Path $backup 'LocalState') -Recurse }
        $oldExe = Join-Path $store.InstallLocation 'KeePassPasskeyProvider/KeePassPasskeyProvider.exe'
        $oldRegistration = Start-Process -FilePath $oldExe -ArgumentList '/unregister' -WindowStyle Hidden -PassThru
        if (-not $oldRegistration.WaitForExit(20000)) { throw 'Store unregister timed out' }
        if ($oldRegistration.ExitCode -ne 0) { throw 'Store unregister failed; package retained' }
        Remove-AppxPackage -Package $store.PackageFullName -ErrorAction Stop
    }
    if (Get-AppxPackage -Name '51133UweKgel.KeePassPasskey') { throw 'Store package is still installed' }
}
$installed | Select-Object Name,Version,PackageFamilyName,SignatureKind,Status
Write-Output 'Installed and registered. Enable the controlled provider manually in Windows passkey settings.'
