# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DotNetPath = "$env:LOCALAPPDATA/KeePassPasskey-buildtools/dotnet/dotnet.exe",
    [string]$WindowsSdkBin = ([Environment]::GetFolderPath('ProgramFilesX86') + '/Windows Kits/10/bin/10.0.26100.0/x64'),
    [switch]$InitializeLock,
    [switch]$AllowDirty
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$env:DOTNET_ROOT = Split-Path $DotNetPath -Parent
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:PATH = "$env:DOTNET_ROOT;$env:PATH"
Push-Location $repoRoot
try {
    if ((& $DotNetPath --version) -ne '10.0.402') { throw 'Expected .NET SDK 10.0.402' }
    $makeAppx = Join-Path $WindowsSdkBin 'makeappx.exe'
    if (-not (Test-Path -LiteralPath $makeAppx)) { throw 'Pinned Windows SDK BuildTools are required' }
    $inputs = Get-Content -LiteralPath 'scripts/controlled-inputs.json' -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $makeAppx -Algorithm SHA256).Hash -ne $inputs.windowsSdk.makeappxSha256) { throw 'makeappx hash mismatch' }
    if ((Get-FileHash -LiteralPath 'build/KeePass.exe' -Algorithm SHA256).Hash -ne $inputs.keePassReference.sha256) { throw 'KeePass compile reference hash mismatch' }
    $dirty = [bool](& git status --porcelain)
    if ($dirty -and -not $AllowDirty) { throw 'Commit reviewed changes before building an installable package' }
    $sourceCommit = & git rev-parse HEAD
    $outRoot = Join-Path $repoRoot 'build/controlled'
    $stage = Join-Path $outRoot 'stage'
    if (Test-Path -LiteralPath $outRoot) { throw 'build/controlled already exists; archive it before rebuilding' }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $providerProject = 'src/KeePassPasskeyProvider/KeePassPasskeyProvider.csproj'
    $pluginProject = 'src/KeePassPasskeyPlugin/KeePassPasskeyPlugin.csproj'
    $testProjects = @('src/KeePassPasskeyPlugin.Tests/KeePassPasskeyPlugin.Tests.csproj', 'src/KeePassPasskeyProvider.Tests/KeePassPasskeyProvider.Tests.csproj')
    foreach ($project in @($providerProject, $pluginProject) + $testProjects) {
        $restoreArgs = @('restore', $project, '--nologo')
        if (-not $InitializeLock) { $restoreArgs += '--locked-mode' }
        & $DotNetPath @restoreArgs
        if ($LASTEXITCODE -ne 0) { throw "Restore failed: $project" }
    }
    & $DotNetPath tool restore --tool-manifest '.config/dotnet-tools.json'
    if ($LASTEXITCODE -ne 0) { throw 'Pinned ILRepack restore failed' }
    foreach ($testProject in $testProjects) {
        $resultName = [IO.Path]::GetFileNameWithoutExtension($testProject) + '.trx'
        & $DotNetPath test $testProject -c Release --no-restore --blame-hang-timeout 60s --nologo `
            --test-adapter-path "$env:USERPROFILE/.nuget/packages/xunit.runner.visualstudio/2.8.2/build/net462" `
            --results-directory "$outRoot/test-results" --logger "trx;LogFileName=$resultName"
        if ($LASTEXITCODE -ne 0) { throw "Tests failed: $testProject" }
        [xml]$testResult = Get-Content -LiteralPath "$outRoot/test-results/$resultName" -Raw
        if ([int]$testResult.TestRun.ResultSummary.Counters.executed -lt 1 -or [int]$testResult.TestRun.ResultSummary.Counters.failed -ne 0) { throw 'No passing test evidence' }
    }
    & $DotNetPath build $pluginProject -c Release --no-restore --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Plugin build failed' }
    $pluginStage = Join-Path $stage 'KeePassPasskeyPlugin'
    New-Item -ItemType Directory -Path $pluginStage | Out-Null
    $pluginDll = Join-Path $pluginStage 'KeePassPasskey.dll'
    $mergeInput = @('KeePassPasskey.dll', 'BouncyCastle.Cryptography.dll', 'CBOR.dll', 'Newtonsoft.Json.dll', 'Numbers.dll', 'URIUtility.dll', 'KeePassPasskeyShared.dll') |
        ForEach-Object { Join-Path $repoRoot "build/Release/$_" }
    foreach ($file in $mergeInput) { if (-not (Test-Path -LiteralPath $file)) { throw "Missing plugin input: $file" } }
    & $DotNetPath tool run ilrepack -- /internalize "/out:$pluginDll" @mergeInput
    if ($LASTEXITCODE -ne 0 -or (Get-Item -LiteralPath $pluginDll).Length -lt 1000000) { throw 'Merged plugin is invalid' }
    $providerStage = Join-Path $stage 'KeePassPasskeyProvider'
    & $DotNetPath publish $providerProject -c Release --no-restore --nologo -o $providerStage -p:PublishTrimmed=false -p:PublishReadyToRun=false
    if ($LASTEXITCODE -ne 0) { throw 'Provider publish failed' }
    foreach ($name in @('KeePassPasskeyProvider.exe', 'KeePassPasskeyProvider.dll', 'KeePassPasskeyShared.dll', 'coreclr.dll')) {
        $file = Join-Path $providerStage $name
        if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -lt 1000) { throw "Missing provider payload: $name" }
    }
    Copy-Item -LiteralPath 'src/KeePassPasskeyProvider.Package/Assets' -Destination (Join-Path $stage 'Assets') -Recurse
    [xml]$manifest = Get-Content -LiteralPath 'src/KeePassPasskeyProvider.Package/Package.appxmanifest' -Raw
    $manifest.Package.Identity.Version = '1.4.1.0'
    $manifest.Save((Join-Path $stage 'AppxManifest.xml'))
    Copy-Item -LiteralPath 'LICENSE' -Destination $stage
    $msix = Join-Path $outRoot 'KeePassPasskey-Controlled_1.4.1.0_x64.msix'
    & $makeAppx pack /d $stage /p $msix /o
    if ($LASTEXITCODE -ne 0 -or (Get-Item -LiteralPath $msix).Length -lt 10000000) { throw 'MSIX packaging failed' }
    $files = @(Get-ChildItem -LiteralPath $stage -File -Recurse | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($stage.Length + 1); size = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    $provenance = [ordered]@{
        source = $sourceCommit; dirty = $dirty; upstreamBase = '502d8b3af9a650c9025110c438033a2a96489b1a'
        sdk = '10.0.402'; ilrepack = '2.0.48'; package = 'Badigit.KeePassPasskey'; version = '1.4.1.0'
        signed = $false; files = $files
    }
    [IO.File]::WriteAllText((Join-Path $outRoot 'provenance.json'), ($provenance | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Write-Output "Unsigned controlled package ready: $msix"
} finally { Pop-Location }
