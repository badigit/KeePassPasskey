# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$KeePassDirectory = "$env:ProgramFiles/KeePass Password Safe 2",
    [string]$EvaluationRoot = "$env:LOCALAPPDATA/KeePassPasskey-controlled-test"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $repoRoot 'build/controlled'
$provenance = Get-Content -LiteralPath (Join-Path $buildRoot 'provenance.json') -Raw | ConvertFrom-Json
if ($provenance.dirty -or -not $provenance.signed) { throw 'Use the final reviewed build for the test setup' }
$installed = Get-AppxPackage -Name 'Badigit.KeePassPasskey'
if (-not $installed) { throw 'Install the controlled MSIX first' }
$sourcePlugin = Join-Path $installed.InstallLocation 'KeePassPasskeyPlugin/KeePassPasskey.dll'
$pluginHash = ($provenance.files | Where-Object path -eq 'KeePassPasskeyPlugin\KeePassPasskey.dll').sha256
if ((Get-FileHash -LiteralPath $sourcePlugin -Algorithm SHA256).Hash -ne $pluginHash) { throw 'Installed plugin hash differs from reviewed build' }
$testDb = Join-Path $EvaluationRoot 'Passkey-Test.kdbx'
if (Test-Path -LiteralPath $testDb) { throw 'Test database exists; refusing to overwrite it' }
$portable = Join-Path $EvaluationRoot 'portable'
$pluginDir = Join-Path $portable 'Plugins/KeePassPasskey'
New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
foreach ($name in @('KeePass.exe','KeePass.exe.config','KeePass.XmlSerializers.dll','KeePassLibN.x64.dll','KeePassLibN.x32.dll')) {
    Copy-Item -LiteralPath (Join-Path $KeePassDirectory $name) -Destination $portable
}
Copy-Item -LiteralPath $sourcePlugin -Destination $pluginDir
[void][Reflection.Assembly]::LoadFrom((Join-Path $portable 'KeePass.exe'))
$master = [KeePassLib.Keys.CompositeKey]::new()
$master.AddUserKey([KeePassLib.Keys.KcpPassword]::new('Passkey-Test-Only-2026!'))
$db = [KeePassLib.PwDatabase]::new()
try {
    $db.New([KeePassLib.Serialization.IOConnectionInfo]::FromPath($testDb), $master)
    $db.Name = 'Controlled passkey test - no real credentials'
    $entry = [KeePassLib.PwEntry]::new($true, $true)
    $entry.Strings.Set('Title', [KeePassLib.Security.ProtectedString]::new($false, 'WebAuthn test account'))
    $entry.Strings.Set('URL', [KeePassLib.Security.ProtectedString]::new($false, 'https://webauthn.io'))
    $entry.Strings.Set('UserName', [KeePassLib.Security.ProtectedString]::new($false, 'controlled-test'))
    $db.RootGroup.AddEntry($entry, $true)
    $db.Save($null)
    $db.Close()
    $db.Open([KeePassLib.Serialization.IOConnectionInfo]::FromPath($testDb), $master, $null)
    if ($db.RootGroup.GetEntries($true).UCount -ne 1) { throw 'Test database roundtrip failed' }
} finally { $db.Close() }
$config = [KeePass.App.Configuration.AppConfigEx]::new()
$config.Meta.PreferUserConfiguration = $false
$config.Application.Start.OpenLastFile = $false
$config.Application.Start.CheckForUpdate = $false
$config.Integration.LimitToSingleInstance = $false
$config.Application.AutoSaveAfterEntryEdit = $true
$config.CustomConfig.SetString('KeePassPasskey.Settings', '{"checkForPluginUpdates":false,"logLevel":"Info"}')
$configPath = Join-Path $portable 'KeePass.config.xml'
$serializer = [Xml.Serialization.XmlSerializer]::new([KeePass.App.Configuration.AppConfigEx])
$writer = [IO.StreamWriter]::new($configPath, $false, [Text.UTF8Encoding]::new($false))
try { $serializer.Serialize($writer, $config) } finally { $writer.Dispose() }
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'KeePass Controlled Test.lnk'
if (Test-Path -LiteralPath $shortcutPath) { throw 'Test shortcut already exists' }
$links = New-Object -ComObject WScript.Shell
$shortcut = $links.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $portable 'KeePass.exe'
$shortcut.Arguments = '"' + $testDb + '" -cfg-local:"' + $configPath + '"'
$shortcut.WorkingDirectory = $portable
$shortcut.Description = 'Controlled passkey build; synthetic test database only'
$shortcut.Save()
Write-Output "Test database and shortcut ready: $testDb"
Write-Output 'TEST ONLY password: Passkey-Test-Only-2026!'
