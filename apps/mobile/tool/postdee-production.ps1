param(
  [ValidateSet('run', 'build-apk', 'build-appbundle', 'test')]
  [string]$Command = 'run',

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'

$mobileRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $mobileRoot)
$flutter = Join-Path $workspaceRoot '.tools\flutter\bin\flutter.bat'
$productionDefines = Join-Path $mobileRoot 'production.local.json'
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

function Assert-ProductionRevenueCatKey {
  param(
    [string]$Name,
    [AllowNull()]
    [object]$Value
  )

  $normalizedValue = ([string]$Value).Trim()

  if ([string]::IsNullOrWhiteSpace($normalizedValue)) {
    throw "$Name must contain a production RevenueCat SDK key."
  }

  if ($normalizedValue.StartsWith('test_', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Name uses a RevenueCat Test Store key. Test Store keys are not allowed by the production helper."
  }

  if ($normalizedValue.StartsWith('replace_with_', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Name still contains a placeholder RevenueCat SDK key. Add the real platform SDK key before using the production helper."
  }
}

Merge-DartDefines $productionDefines

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
  $revenueCatKeyNames = @(
    'REVENUECAT_API_KEY',
    'REVENUECAT_ANDROID_API_KEY',
    'REVENUECAT_IOS_API_KEY'
  )
  $configuredRevenueCatKeyNames = @(
    $revenueCatKeyNames | Where-Object { $merged.Contains($_) }
  )

  if (
    $Command -in @('build-apk', 'build-appbundle') -and
    -not $merged.Contains('REVENUECAT_ANDROID_API_KEY')
  ) {
    throw 'REVENUECAT_ANDROID_API_KEY is required for production Android APK/AAB builds.'
  }

  if ($configuredRevenueCatKeyNames.Count -eq 0) {
    throw "RevenueCat billing is enabled, but no RevenueCat SDK key was found. Add the platform SDK key to production.local.json."
  }

  foreach ($keyName in $configuredRevenueCatKeyNames) {
    Assert-ProductionRevenueCatKey -Name $keyName -Value $merged[$keyName]
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
    'build-appbundle' {
      'build'
      'appbundle'
      '--release'
    }
    'test' { 'test' }
  }
)

& $flutter @flutterCommand "--dart-define-from-file=$mergedDefines" @FlutterArgs
exit $LASTEXITCODE
