param(
  [string]$ServiceName = "postdee-api",
  [string]$ServiceId = $env:RENDER_SERVICE_ID
)

$ErrorActionPreference = "Stop"

$apiKey = $env:RENDER_API_KEY
if (-not $apiKey) {
  $apiKey = $env:RENDER_TOKEN
}

if (-not $apiKey) {
  Write-Host "Missing RENDER_API_KEY."
  Write-Host "Set it in this terminal first, then run this script again."
  Write-Host "This script prints only key names/status, never secret values."
  exit 1
}

$headers = @{
  Authorization = "Bearer $apiKey"
  Accept = "application/json"
}

function Invoke-RenderApi {
  param([string]$Path)

  Invoke-RestMethod `
    -Method Get `
    -Uri "https://api.render.com/v1$Path" `
    -Headers $headers
}

function Get-RenderItems {
  param([object]$Response)

  if ($Response -is [array]) {
    return $Response
  }

  if ($Response.items) {
    return $Response.items
  }

  return @($Response)
}

function Get-RenderCursor {
  param([object[]]$Items)

  if (-not $Items -or $Items.Count -eq 0) {
    return $null
  }

  $last = $Items[$Items.Count - 1]
  if ($last.cursor) {
    return $last.cursor
  }

  return $null
}

if (-not $ServiceId) {
  $encodedName = [System.Uri]::EscapeDataString($ServiceName)
  $servicesResponse = Invoke-RenderApi "/services?name=$encodedName&limit=100"
  $serviceItems = @(Get-RenderItems $servicesResponse)
  $matchedServices = @()

  foreach ($item in $serviceItems) {
    $service = $item.service
    if (-not $service) {
      $service = $item
    }

    if ($service.name -eq $ServiceName) {
      $matchedServices += $service
    }
  }

  if ($matchedServices.Count -eq 0) {
    Write-Host "Could not find Render service named '$ServiceName'."
    Write-Host "If you know the service id, set RENDER_SERVICE_ID and run again."
    exit 1
  }

  if ($matchedServices.Count -gt 1) {
    Write-Host "Found more than one service named '$ServiceName'."
    Write-Host "Set RENDER_SERVICE_ID to the exact service id and run again."
    exit 1
  }

  $ServiceId = $matchedServices[0].id
}

$requiredNow = @(
  "CLOUDFLARE_R2_BUCKET",
  "CLOUDFLARE_R2_ACCOUNT_ID",
  "CLOUDFLARE_R2_ACCESS_KEY_ID",
  "CLOUDFLARE_R2_SECRET_ACCESS_KEY",
  "GEMINI_API_KEY",
  "GROQ_API_KEY",
  "POSTPEER_API_KEY",
  "FIREBASE_PROJECT_ID",
  "REVENUECAT_WEBHOOK_AUTH_TOKEN"
)

$optionalOrLater = @(
  "CLOUDFLARE_R2_ENDPOINT",
  "FIREBASE_SERVICE_ACCOUNT_JSON",
  "GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN"
)

$forbiddenProduction = @(
  "POSTPEER_TIKTOK_ACCOUNT_ID",
  "POSTPEER_YOUTUBE_ACCOUNT_ID",
  "POSTPEER_INSTAGRAM_ACCOUNT_ID",
  "POSTPEER_FACEBOOK_ACCOUNT_ID"
)

$envKeys = New-Object System.Collections.Generic.HashSet[string]
$cursor = $null

do {
  $path = "/services/$ServiceId/env-vars?limit=100"
  if ($cursor) {
    $encodedCursor = [System.Uri]::EscapeDataString($cursor)
    $path = "$path&cursor=$encodedCursor"
  }

  $envResponse = Invoke-RenderApi $path
  $envItems = @(Get-RenderItems $envResponse)

  foreach ($item in $envItems) {
    $envVar = $item.envVar
    if (-not $envVar) {
      $envVar = $item
    }

    if ($envVar.key) {
      [void]$envKeys.Add([string]$envVar.key)
    }
  }

  $cursor = Get-RenderCursor $envItems
} while ($cursor)

$presentRequired = @($requiredNow | Where-Object { $envKeys.Contains($_) })
$missingRequired = @($requiredNow | Where-Object { -not $envKeys.Contains($_) })
$presentOptional = @($optionalOrLater | Where-Object { $envKeys.Contains($_) })
$missingOptional = @($optionalOrLater | Where-Object { -not $envKeys.Contains($_) })
$presentForbidden = @($forbiddenProduction | Where-Object { $envKeys.Contains($_) })

Write-Host "Render service: $ServiceName ($ServiceId)"
Write-Host ""
Write-Host "Required now - present:"
if ($presentRequired.Count -eq 0) { Write-Host "- none" } else { $presentRequired | ForEach-Object { Write-Host "- $_" } }

Write-Host ""
Write-Host "Required now - missing:"
if ($missingRequired.Count -eq 0) { Write-Host "- none" } else { $missingRequired | ForEach-Object { Write-Host "- $_" } }

Write-Host ""
Write-Host "Optional / later - present:"
if ($presentOptional.Count -eq 0) { Write-Host "- none" } else { $presentOptional | ForEach-Object { Write-Host "- $_" } }

Write-Host ""
Write-Host "Optional / later - missing:"
if ($missingOptional.Count -eq 0) { Write-Host "- none" } else { $missingOptional | ForEach-Object { Write-Host "- $_" } }

Write-Host ""
Write-Host "Forbidden in production - present:"
if ($presentForbidden.Count -eq 0) { Write-Host "- none" } else { $presentForbidden | ForEach-Object { Write-Host "- $_" } }

Write-Host ""
Write-Host "Note: Render API env-vars returns only variables directly on the service, not variables from linked environment groups."

if ($missingRequired.Count -gt 0 -or $presentForbidden.Count -gt 0) {
  exit 2
}

exit 0
