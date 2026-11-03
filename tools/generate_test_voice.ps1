$ErrorActionPreference = 'Stop'
$output = Join-Path $PSScriptRoot '../material/test_voice'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$voice = New-Object -ComObject SAPI.SpVoice
$tokens = $voice.GetVoices()
$selected = $null
foreach ($token in $tokens) {
    if ($token.GetDescription() -match 'Huihui') { $selected = $token; break }
}
if ($null -eq $selected) { throw 'Installed Huihui voice was not found' }
$voice.Voice = $selected
$voice.Rate = 3
$voice.Volume = 100
$phrases = @('第一张', '第二张', '第三张', '第四张')
for ($index = 0; $index -lt $phrases.Count; $index++) {
    $path = Join-Path $output ('voice{0}.wav' -f ($index + 1))
    if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite $path" }
    $stream = New-Object -ComObject SAPI.SpFileStream
    $format = New-Object -ComObject SAPI.SpAudioFormat
    $format.Type = 22 # SAPI SAFT22kHz16BitMono; Python validates actual WAV header.
    $stream.Format = $format
    $stream.Open($path, 3, $false)
    try {
        $voice.AudioOutputStream = $stream
        $null = $voice.Speak($phrases[$index])
    } finally { $stream.Close() }
    Write-Output "Generated $path : $($phrases[$index])"
}
