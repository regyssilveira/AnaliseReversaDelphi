param(
    [int]$UnitCount = 2200,
    [string]$Destination = 'bin/stress-fixture'
)

$ErrorActionPreference = 'Stop'

$fixtureRoot = [IO.Path]::GetFullPath($Destination)
$projectRoot = Join-Path $fixtureRoot 'Project'
$libraryRoots = 1..3 | ForEach-Object { Join-Path $fixtureRoot "Library$_" }
$directories = @($projectRoot) + $libraryRoots
New-Item -ItemType Directory -Force $directories | Out-Null

Set-Content -LiteralPath (Join-Path $libraryRoots[0] 'Target.pas') -Value "unit Target;`r`ninterface`r`nimplementation`r`nend." -Encoding ascii

for ($i = 1; $i -le $UnitCount; $i++) {
    $unitName = 'U{0:D4}' -f $i
    $previous = if ($i -eq 1) { 'Target' } else { 'U{0:D4}' -f ($i - 1) }
    $folder = if ($i % 4 -eq 0) { $libraryRoots[([int]($i / 4) - 1) % 3] } else { $projectRoot }
    $content = "unit $unitName;`r`ninterface`r`nuses $previous;`r`nimplementation`r`nend."
    Set-Content -LiteralPath (Join-Path $folder "$unitName.pas") -Value $content -Encoding ascii
}

$lastUnit = 'U{0:D4}' -f $UnitCount
Set-Content -LiteralPath (Join-Path $projectRoot 'Stress.dpr') -Value "program Stress;`r`nuses $lastUnit;`r`nbegin`r`nend." -Encoding ascii
$searchPath = [Security.SecurityElement]::Escape(($libraryRoots -join ';'))
$projectXml = "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`"><PropertyGroup><MainSource>Stress.dpr</MainSource><DCC_UnitSearchPath>$searchPath</DCC_UnitSearchPath></PropertyGroup></Project>"
Set-Content -LiteralPath (Join-Path $projectRoot 'Stress.dproj') -Value $projectXml -Encoding ascii
Write-Output (Join-Path $projectRoot 'Stress.dproj')
