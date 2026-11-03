param(
    [string]$BuildDirectory = (Join-Path $PSScriptRoot 'work_build')
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$packageRoot = $PSScriptRoot
$sourceManifest = Get-Content -LiteralPath (Join-Path $packageRoot 'validation/album_input_sha256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $sourceManifest.PSObject.Properties) {
    $inputPath = Join-Path $packageRoot $entry.Name
    if (!(Test-Path -LiteralPath $inputPath)) { throw "Missing frozen source: $($entry.Name)" }
    if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw "Frozen input changed: $($entry.Name)" }
}
$buildRoot = [IO.Path]::GetFullPath($BuildDirectory)
if (Test-Path -LiteralPath $buildRoot) { throw "BuildDirectory already exists. Use a new directory to preserve existing work: $buildRoot" }
New-Item -ItemType Directory -Path $buildRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $packageRoot 'proj') -Destination $buildRoot -Recurse
$projectRoot = (Join-Path $buildRoot 'proj/src/td_project').Replace('\','/')
$projectFile = Join-Path $projectRoot 'HDMI1.4b_Transmitter_v1.0.al'
$projectText = [IO.File]::ReadAllText($projectFile)
$projectText = [regex]::Replace($projectText, '(<Project\b[^>]*\bPath=")[^"]*(")', {param($m) $m.Groups[1].Value + $projectRoot + $m.Groups[2].Value})
[IO.File]::WriteAllText($projectFile, $projectText, $utf8)
$overlayPath = Join-Path $buildRoot 'proj/src/user_source/hdl_source/lyric_overlay.v'
$overlayText = [IO.File]::ReadAllText($overlayPath)
$fontRoot = (Join-Path $buildRoot 'proj/src/user_source/hdl_source').Replace('\','/')
foreach ($i in 0..3) {
    $fontPath = $fontRoot + '/lyric_font' + $i + '.hex'
    if (!(Test-Path -LiteralPath $fontPath)) { throw "Missing lyric font: $fontPath" }
    $pattern = '(parameter\s+FONT' + $i + '\s*=\s*")[^"]*(")'
    $replacement = '${1}' + $fontPath + '${2}'
    $overlayText = [regex]::Replace($overlayText, $pattern, $replacement)
}
[IO.File]::WriteAllText($overlayPath, $overlayText, $utf8)
$changed = @('proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al','proj/src/user_source/hdl_source/lyric_overlay.v')
$mapping = @{}
foreach ($entry in $sourceManifest.PSObject.Properties) {
    $f = Join-Path $buildRoot $entry.Name
    $actual = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($entry.Name -notin $changed -and $actual -ne $entry.Value) { throw "Unexpected source mutation: $($entry.Name)" }
    $mapping[$entry.Name] = $actual
}
$record = @{ profile='MEM50_150.75deg'; sourceInputs=113; pathOnlyChangedFiles=$changed; project=$projectFile; hashes=$mapping }
[IO.File]::WriteAllText((Join-Path $buildRoot 'prepared_project.json'), ($record | ConvertTo-Json -Depth 6), $utf8)
Write-Output "Prepared project: $projectFile"
