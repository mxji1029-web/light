param(
    [string]$TDHome = 'D:\Anlogic',
    [string]$BuildDirectory = (Join-Path $PSScriptRoot 'work_build')
)
$ErrorActionPreference='Stop'
$tdCommand = Join-Path $TDHome 'bin/td_commands_prompt.exe'
$defaultFlow = Join-Path $TDHome 'doc/scripts/DefaultFlow.tcl'
if (!(Test-Path -LiteralPath $tdCommand) -or !(Test-Path -LiteralPath $defaultFlow)) { throw 'Set -TDHome to the installed TangDynasty directory.' }
if (!(Test-Path -LiteralPath $BuildDirectory)) { & (Join-Path $PSScriptRoot 'prepare_project.ps1') -BuildDirectory $BuildDirectory }
$marker = Join-Path $BuildDirectory 'prepared_project.json'
if (!(Test-Path -LiteralPath $marker)) { throw 'Use a directory prepared with prepare_project.ps1.' }
$prepared = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $prepared.hashes.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $BuildDirectory $entry.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw "Prepared input changed: $($entry.Name)" }
}
$runs=Join-Path $BuildDirectory 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
$buildStarted=Get-Date
Push-Location (Join-Path $runs 'syn_1')
try {
    & $tdCommand ($defaultFlow.Replace('\','/')) *> synthesis_build.log
    $nativeExit=$LASTEXITCODE
    $log=Get-Content -LiteralPath synthesis_build.log -Raw
    $gate='HDMI1.4b_Transmitter_v1.0_gate.db'
    if($nativeExit -ne 0 -or $log -match '(?m)\bERROR\s*:|^Error:|^invalid command' -or $log -notmatch 'finish command "optimize_gate' -or !(Test-Path -LiteralPath $gate)) {throw 'Synthesis failed; read synthesis_build.log.'}
    if((Get-Item -LiteralPath $gate).LastWriteTime -lt $buildStarted.AddSeconds(-2)) {throw 'Synthesis output is stale.'}
}
finally { Pop-Location }
Push-Location (Join-Path $runs 'phy_1')
try {
    & $tdCommand ((Join-Path $PSScriptRoot 'build_flow/physical.tcl').Replace('\','/')) *> physical_build.log
    $nativeExit=$LASTEXITCODE
    $log=Get-Content -LiteralPath physical_build.log -Raw
    $bit='HDMI1.4b_Transmitter_v1.0.bit'
    if($nativeExit -ne 0 -or $log -match '(?m)\bERROR\s*:|^Error:|^invalid command' -or $log -notmatch 'Generate bitstream completely' -or !(Test-Path -LiteralPath $bit)) {throw 'Place/route failed; read physical_build.log.'}
    if((Get-Item -LiteralPath $bit).LastWriteTime -lt $buildStarted.AddSeconds(-2)) {throw 'Bitstream output is stale.'}
}
finally { Pop-Location }
Write-Output ('Bitstream: '+(Join-Path $runs 'phy_1/HDMI1.4b_Transmitter_v1.0.bit'))
