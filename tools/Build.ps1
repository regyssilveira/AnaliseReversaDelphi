# SPDX-License-Identifier: Apache-2.0

param([switch]$Tests, [ValidateSet('Win32','Win64')][string]$Platform='Win32')

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
$compiler = if ($Platform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
$compilerPath = Join-Path $bdsRoot "bin\$compiler"
if (-not (Test-Path -LiteralPath $compilerPath)) { throw "Compilador nao encontrado: $compilerPath" }
$library = Join-Path $bdsRoot "lib\$($Platform.ToLowerInvariant())\release"
$unitPaths = @('src','tests','vendor\DelphiAST\Source','vendor\DelphiAST\Source\SimpleParser',
    (Join-Path $bdsRoot 'source\DUnitX'),$library) -join ';'
$exeDir = Join-Path 'bin' $Platform
$dcuDir = Join-Path 'obj' $Platform
New-Item -ItemType Directory -Force $exeDir,$dcuDir | Out-Null
$project = if ($Tests) { 'UnitBacktraceTests.dpr' } else { 'UnitBacktrace.dpr' }
& $compilerPath -B '-NSSystem;Winapi;Vcl;Xml' "-U$unitPaths" "-E$exeDir" "-N$dcuDir" $project
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
