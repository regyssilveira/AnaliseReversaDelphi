param([switch]$Tests, [ValidateSet('Win32','Win64')][string]$Platform='Win32')

$bdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$compiler = if ($Platform -eq 'Win64') { 'dcc64.exe' } else { 'dcc32.exe' }
$library = Join-Path $bdsRoot "lib\$($Platform.ToLowerInvariant())\release"
$unitPaths = @('src','tests','vendor\DelphiAST\Source','vendor\DelphiAST\Source\SimpleParser',
    (Join-Path $bdsRoot 'source\DUnitX'),$library) -join ';'
$exeDir = Join-Path 'bin' $Platform
$dcuDir = Join-Path 'obj' $Platform
New-Item -ItemType Directory -Force $exeDir,$dcuDir | Out-Null
$project = if ($Tests) { 'UnitBacktraceTests.dpr' } else { 'UnitBacktrace.dpr' }
& (Join-Path $bdsRoot "bin\$compiler") -B '-NSSystem;Winapi;Vcl;Xml' "-U$unitPaths" "-E$exeDir" "-N$dcuDir" $project
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
