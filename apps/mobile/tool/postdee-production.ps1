param(
  [ValidateSet('run', 'build-apk', 'test')]
  [string]$Command = 'run',

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'

$mobileRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $mobileRoot)
$flutter = Join-Path $workspaceRoot '.tools\flutter\bin\flutter.bat'
$productionDefines = Join-Path $mobileRoot 'production.local.json'
$revenueCatDefines = Join-Path $mobileRoot 'revenuecat.local.json'
$mergedDefines = Join-Path $mobileRoot '.dart_tool\postdee_production.dartdefine.json'

if (-not (Test-Path $productionDefines)) {
  throw "Missing production.local.json. Copy production.local.example.json to production.local.json first."
}

if (-not (Test-Path $flutter)) {
  throw "Flutter SDK was not found at $flutter"
}

$merged = [ordered]@{}

function Merge-DartDefines($path) {
  if (-not (Test-Path $path)) {
    return
  }

  $json = Get-Content -Raw $path | ConvertFrom-Json

  foreach ($property in $json.PSObject.Properties) {
    $merged[$property.Name] = $property.Value
  }
}

Merge-DartDefines $productionDefines
Merge-DartDefines $revenueCatDefines

foreach ($blockedKey in @(
    'POSTDEE_MOCK_USER_ID',
    'POSTDEE_MOCK_SUBSCRIPTION_PLAN',
    'GEMINI_API_KEY',
    'GROQ_API_KEY',
    'REVENUECAT_WEBHOOK_AUTH_TOKEN'
  )) {
  if ($merged.Contains($blockedKey)) {
    throw "$blockedKey must not be passed to the mobile app."
  }
}

if ([string]$merged['API_BASE_URL'] -ne 'https://postdee-api.onrender.com') {
  throw "API_BASE_URL must point to https://postdee-api.onrender.com for production runs."
}

if ($merged['ENABLE_FIREBASE_AUTH'] -ne $true) {
  throw "ENABLE_FIREBASE_AUTH must be true for production runs."
}

if ($merged['ALLOW_LOCAL_MOCK_AUTH'] -ne $false) {
  throw "ALLOW_LOCAL_MOCK_AUTH must be false for production runs."
}

if ($merged['ENABLE_REVENUECAT_BILLING'] -eq $true) {
  $hasRevenueCatKey = $false

  foreach ($key in @('REVENUECAT_API_KEY', 'REVENUECAT_ANDROID_API_KEY', 'REVENUECAT_IOS_API_KEY')) {
    if ($merged.Contains($key) -and -not [string]::IsNullOrWhiteSpace([string]$merged[$key])) {
      $hasRevenueCatKey = $true
    }
  }

  if (-not $hasRevenueCatKey) {
    throw "RevenueCat billing is enabled, but no RevenueCat SDK key was found. Add one to revenuecat.local.json."
  }
}

New-Item -ItemType Directory -Force (Split-Path -Parent $mergedDefines) | Out-Null
$merged | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $mergedDefines

$flutterCommand = @(
  switch ($Command) {
    'run' { 'run' }
    'build-apk' {
      'build'
      'apk'
      '--release'
    }
    'test' { 'test' }
  }
)

& $flutter @flutterCommand "--dart-define-from-file=$mergedDefines" @FlutterArgs
exit $LASTEXITCODE
