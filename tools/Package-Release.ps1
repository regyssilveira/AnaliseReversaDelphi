# SPDX-License-Identifier: Apache-2.0

param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Version,
    [ValidateSet('Win32','Win64')][string]$Platform = 'Win64'
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$binaryPath = Join-Path $workspaceRoot "bin\$Platform\UnitBacktrace.exe"
if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
    throw "Executable not found: $binaryPath"
}

$stagePath = Join-Path $workspaceRoot ('bin\package-' + [guid]::NewGuid().ToString('N'))
$licensePath = Join-Path $stagePath 'licenses'
New-Item -ItemType Directory -Force -Path $licensePath | Out-Null

Copy-Item -LiteralPath $binaryPath -Destination $stagePath
foreach ($name in @('LICENSE','NOTICE','README.md','README.en.md','THIRD_PARTY_LICENSES.md')) {
    Copy-Item -LiteralPath (Join-Path $workspaceRoot $name) -Destination $stagePath
}
Copy-Item -LiteralPath (Join-Path $workspaceRoot 'licenses\MPL-1.1.txt') -Destination $licensePath
Copy-Item -LiteralPath (Join-Path $workspaceRoot 'vendor\DelphiAST\LICENSE') -Destination (Join-Path $licensePath 'DelphiAST-MPL-2.0.txt')

$archivePath = Join-Path $workspaceRoot "bin\UnitBacktrace-$Version-$Platform.zip"
Compress-Archive -Path (Join-Path $stagePath '*') -DestinationPath $archivePath -Force
Write-Output $archivePath
