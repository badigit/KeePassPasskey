# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CertificateThumbprint,
    [string]$WindowsSdkBin = ([Environment]::GetFolderPath('ProgramFilesX86') + '/Windows Kits/10/bin/10.0.26100.0/x64')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$outRoot = Join-Path $repoRoot 'build/controlled'
$provenancePath = Join-Path $outRoot 'provenance.json'
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
if ($provenance.dirty) { throw 'Refusing to sign an uncommitted build' }
if ($provenance.signed) { throw 'Build is already signed' }
$cert = Get-Item -LiteralPath "Cert:/CurrentUser/My/$CertificateThumbprint"
if ($cert.Subject -ne 'CN=badigit.KeePassPasskey' -or -not $cert.HasPrivateKey) { throw 'Wrong signing certificate' }
$signTool = Join-Path $WindowsSdkBin 'signtool.exe'
$inputs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'controlled-inputs.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $signTool -Algorithm SHA256).Hash -ne $inputs.windowsSdk.signtoolSha256) { throw 'signtool hash mismatch' }
$msix = Join-Path $outRoot 'KeePassPasskey-Controlled_1.4.1.0_x64.msix'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($msix)
try {
    foreach ($file in $provenance.files) {
        $entry = $archive.GetEntry($file.path.Replace('\', '/'))
        if (-not $entry) { $entry = $archive.GetEntry($file.path) }
        if (-not $entry -or $entry.Length -ne $file.size) { throw "Package payload missing or resized: $($file.path)" }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose(); $sha.Dispose() }
        if ($actualHash -ne $file.sha256) { throw "Package payload hash mismatch: $($file.path)" }
    }
} finally { $archive.Dispose() }
& $signTool sign /fd SHA256 /sha1 $CertificateThumbprint /s My $msix
if ($LASTEXITCODE -ne 0) { throw 'MSIX signing failed' }
Export-Certificate -Cert $cert -FilePath (Join-Path $outRoot 'ControlledBuild.cer') | Out-Null
$provenance | Add-Member NoteProperty signingCertificate $CertificateThumbprint
$provenance | Add-Member NoteProperty packageSha256 (Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash
$provenance.signed = $true
[IO.File]::WriteAllText($provenancePath, ($provenance | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Output "Signed controlled package: $msix"
