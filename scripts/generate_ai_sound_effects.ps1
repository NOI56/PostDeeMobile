Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$soundEffectRoot = Join-Path $repositoryRoot 'apps/mobile/assets/sfx'
$ffmpegPath = (Get-Command ffmpeg -ErrorAction Stop).Source
$generationProvenanceDate = '2026-08-09'

New-Item -ItemType Directory -Path $soundEffectRoot -Force | Out-Null

$soundEffects = @(
    @{
        Name = 'soft_pop'
        Duration = '0.220'
        Filter = 'aevalsrc=0.42*sin(2*PI*(180+900*t)*t)*exp(-20*t):s=48000:d=0.22'
    },
    @{
        Name = 'clean_tap'
        Duration = '0.120'
        Filter = 'anoisesrc=color=white:seed=101:amplitude=0.35:sample_rate=48000:duration=0.12,highpass=f=1800,lowpass=f=7000,afade=t=out:st=0:d=0.12'
    },
    @{
        Name = 'short_whoosh'
        Duration = '0.450'
        Filter = 'anoisesrc=color=pink:seed=102:amplitude=0.32:sample_rate=48000:duration=0.45,highpass=f=300,lowpass=f=5500,afade=t=in:st=0:d=0.12,afade=t=out:st=0.25:d=0.20'
    },
    @{
        Name = 'medium_whoosh'
        Duration = '0.750'
        Filter = 'anoisesrc=color=pink:seed=103:amplitude=0.30:sample_rate=48000:duration=0.75,highpass=f=220,lowpass=f=6000,afade=t=in:st=0:d=0.25,afade=t=out:st=0.45:d=0.30'
    },
    @{
        Name = 'sparkle'
        Duration = '0.800'
        Filter = 'aevalsrc=(0.18*sin(2*PI*1300*t)+0.13*sin(2*PI*1950*t)+0.09*sin(2*PI*2600*t))*exp(-4.5*t):s=48000:d=0.80'
    },
    @{
        Name = 'success_ding'
        Duration = '0.700'
        Filter = 'aevalsrc=(0.24*sin(2*PI*880*t)+0.14*sin(2*PI*1320*t))*exp(-5*t):s=48000:d=0.70'
    },
    @{
        Name = 'coin_ping'
        Duration = '0.420'
        Filter = 'aevalsrc=(0.20*sin(2*PI*1760*t)+0.10*sin(2*PI*2346.67*t))*exp(-8*t):s=48000:d=0.42'
    },
    @{
        Name = 'soft_impact'
        Duration = '0.350'
        Filter = 'anoisesrc=color=brown:seed=104:amplitude=0.55:sample_rate=48000:duration=0.35,lowpass=f=420,afade=t=out:st=0:d=0.35'
    },
    @{
        Name = 'short_riser'
        Duration = '0.900'
        Filter = 'aevalsrc=0.18*sin(2*PI*(180*t+620*t*t))*sin(PI*t/0.9):s=48000:d=0.90'
    },
    @{
        Name = 'attention_boop'
        Duration = '0.320'
        Filter = 'aevalsrc=(0.22*sin(2*PI*660*t)+0.11*sin(2*PI*990*t))*exp(-9*t):s=48000:d=0.32'
    }
)

foreach ($soundEffect in $soundEffects) {
    $outputPath = Join-Path $soundEffectRoot ($soundEffect.Name + '.wav')
    & $ffmpegPath `
        -hide_banner `
        -loglevel error `
        -y `
        -f lavfi `
        -i $soundEffect.Filter `
        -ac 2 `
        -ar 48000 `
        -c:a pcm_s16le `
        $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg failed while generating $($soundEffect.Name)"
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$shaLines = foreach ($soundEffect in $soundEffects) {
    $fileName = $soundEffect.Name + '.wav'
    $filePath = Join-Path $soundEffectRoot $fileName
    $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    "$hash  $fileName"
}
[System.IO.File]::WriteAllLines(
    (Join-Path $soundEffectRoot 'manifest.sha256'),
    $shaLines,
    $utf8NoBom
)

$csvLines = @(
    'id,file,bytes,duration_seconds,format,sample_rate_hz,channels,provenance,generated_utc'
)
foreach ($soundEffect in $soundEffects) {
    $fileName = $soundEffect.Name + '.wav'
    $filePath = Join-Path $soundEffectRoot $fileName
    $bytes = (Get-Item -LiteralPath $filePath).Length
    $csvLines += "$($soundEffect.Name),$fileName,$bytes,$($soundEffect.Duration),pcm_s16le,48000,2,postdee_procedural,$generationProvenanceDate"
}
[System.IO.File]::WriteAllLines(
    (Join-Path $soundEffectRoot 'manifest.csv'),
    $csvLines,
    $utf8NoBom
)

Write-Output "Generated $($soundEffects.Count) PostDee sound effects and manifests in $soundEffectRoot"
