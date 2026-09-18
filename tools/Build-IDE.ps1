# SPDX-License-Identifier: Apache-2.0

param([ValidateSet('Debug','Release')][string]$Config = 'Release')

$ErrorActionPreference = 'Stop'
$bdsRoot = $null
if ($env:BDS -and (Split-Path -Leaf $env:BDS.TrimEnd('\')) -eq '37.0' -and
    (Test-Path -LiteralPath $env:BDS -PathType Container)) {
    $bdsRoot = $env:BDS
}
if (-not $bdsRoot) {
    foreach ($key in @('HKCU:\Software\Embarcadero\BDS\37.0',
                       'HKLM:\Software\WOW6432Node\Embarcadero\BDS\37.0')) {
        if (Test-Path -LiteralPath $key) {
            $candidate = (Get-ItemProperty -LiteralPath $key -Name RootDir -ErrorAction SilentlyContinue).RootDir
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
                $bdsRoot = $candidate
                break
            }
        }
    }
}
if (-not $bdsRoot) { throw 'Instalacao do Delphi 13 (BDS 37.0) nao encontrada.' }
$bdsRoot = (Resolve-Path -LiteralPath $bdsRoot).Path
$compiler = Join-Path $bdsRoot 'bin\dcc32.exe'
$library = Join-Path $bdsRoot "lib\win32\$($Config.ToLowerInvariant())"
$unitPaths = @('src','ide','vendor\DelphiAST\Source',
    'vendor\DelphiAST\Source\SimpleParser',$library) -join ';'
New-Item -ItemType Directory -Force 'bin\IDE','obj\IDE' | Out-Null
& $compiler -B '-NSSystem;Winapi;Vcl;Xml' "-U$unitPaths" '-LEbin\IDE' '-LNobj\IDE' '-Nobj\IDE' UnitBacktraceIDE.dpk
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output (Resolve-Path -LiteralPath 'bin\IDE\UnitBacktraceIDE.bpl').Path
