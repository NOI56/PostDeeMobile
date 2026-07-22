param(
  [Parameter(Mandatory = $true)]
  [string]$InputDirectory,
  [string]$OutputDirectory = ".tmp/ai-edit-visual-proxy-smoke",
  [string]$Ffmpeg = "ffmpeg",
  [string]$Ffprobe = "ffprobe"
)

$ErrorActionPreference = "Stop"
$resolvedInput = (Resolve-Path -LiteralPath $InputDirectory).Path
$resolvedOutput = [System.IO.Path]::GetFullPath(
  (Join-Path (Get-Location) $OutputDirectory)
)
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

$extensions = @(".mp4", ".mov", ".webm", ".mkv")
$sources = Get-ChildItem -LiteralPath $resolvedInput -File |
  Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }

if ($sources.Count -eq 0) {
  throw "No supported video files found in $resolvedInput"
}

$report = foreach ($source in $sources) {
  $output = Join-Path $resolvedOutput "$($source.BaseName)-proxy.mp4"
  & $Ffmpeg -y -v error -i $source.FullName `
    -vf "fps=1,scale=360:-2" `
    -c:v mpeg4 -q:v 5 -pix_fmt yuv420p `
    -ac 1 -ar 16000 -c:a aac -b:a 32k `
    -movflags +faststart $output
  if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg failed for $($source.Name)"
  }

  $sourceProbe = & $Ffprobe -v error -show_entries format=duration,size `
    -of json -- $source.FullName | ConvertFrom-Json
  $proxyProbe = & $Ffprobe -v error `
    -show_entries format=duration,size `
    -show_entries stream=codec_type,width,height,avg_frame_rate `
    -of json -- $output | ConvertFrom-Json
  $video = $proxyProbe.streams |
    Where-Object { $_.codec_type -eq "video" } |
    Select-Object -First 1

  $sourceSeconds = [double]$sourceProbe.format.duration
  $proxySeconds = [double]$proxyProbe.format.duration
  $durationDelta = [Math]::Abs($sourceSeconds - $proxySeconds)
  $proxyBytes = [double]$proxyProbe.format.size

  if ($durationDelta -gt 1.1) {
    throw "Proxy duration differs by more than 1.1 seconds for $($source.Name)"
  }
  if ($video.width -ne 360 -or $video.avg_frame_rate -ne "1/1") {
    throw "Proxy does not use 360 px / 1 fps for $($source.Name)"
  }
  if ($proxyBytes -gt 50MB) {
    throw "Proxy exceeds the 50 MiB upload cap for $($source.Name)"
  }

  [PSCustomObject]@{
    Name = $source.Name
    SourceSeconds = [Math]::Round($sourceSeconds, 2)
    ProxySeconds = [Math]::Round($proxySeconds, 2)
    DurationDelta = [Math]::Round($durationDelta, 2)
    SourceMB = [Math]::Round(([double]$sourceProbe.format.size / 1MB), 2)
    ProxyMB = [Math]::Round(($proxyBytes / 1MB), 2)
    Width = $video.width
    FrameRate = $video.avg_frame_rate
  }
}

$report | Format-Table -AutoSize
