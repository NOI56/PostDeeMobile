param(
  [ValidateSet('run', 'build-apk', 'test')]
  [string]$Command = 'run',

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'

$mobileRoot = Split-Path -Parent $PSScriptRoot
$localDefines = Join-Path $mobileRoot 'staging.local.json'
$exampleDefines = Join-Path $mobileRoot 'staging.local.example.json'
$googleServices = Join-Path $mobileRoot 'android\app\src\debug\google-services.json'

function Resolve-RevenueCatTestStoreDefines {
  $localCandidate = Join-Path $mobileRoot 'revenuecat.local.json'
  if (Test-Path -LiteralPath $localCandidate) {
    return (Resolve-Path -LiteralPath $localCandidate).Path
  }

  $searchRoot = Split-Path -Parent $mobileRoot
  while (-not [string]::IsNullOrWhiteSpace($searchRoot)) {
    # A Git worktree intentionally does not copy ignored local credentials.
    # Reuse the ignored Test Store overlay from the ancestor workspace when it
    # exists, without copying the public SDK key into the worktree or Git.
    $candidate = Join-Path $searchRoot 'apps\mobile\revenuecat.local.json'
    $gitMarker = Join-Path $searchRoot '.git'
    if ((Test-Path -LiteralPath $gitMarker) -and
        (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }

    $parent = Split-Path -Parent $searchRoot
    if ($parent -eq $searchRoot) {
      break
    }
    $searchRoot = $parent
  }

  return $null
}

function Assert-NoServerSecrets {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,

    [Parameter(Mandatory = $true)]
    [string]$SourceLabel
  )

  foreach ($blockedKey in @(
      'POSTDEE_MOCK_USER_ID',
      'POSTDEE_MOCK_SUBSCRIPTION_PLAN',
      'GEMINI_API_KEY',
      'GROQ_API_KEY',
      'ELEVENLABS_API_KEY',
      'REVENUECAT_WEBHOOK_AUTH_TOKEN',
      'REVENUECAT_REST_API_V1_KEY',
      'GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON',
      'GOOGLE_PLAY_ACCESS_TOKEN',
      'GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN'
    )) {
    if ($Config.PSObject.Properties.Name -contains $blockedKey) {
      throw "$blockedKey must not be passed to the mobile app from $SourceLabel."
    }
  }
}

function Assert-RevenueCatTestStoreDefines {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $config = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  Assert-NoServerSecrets -Config $config -SourceLabel 'revenuecat.local.json'

  $allowedKeys = @(
    'ENABLE_REVENUECAT_BILLING',
    'REVENUECAT_API_KEY',
    'REVENUECAT_ANDROID_API_KEY'
  )
  foreach ($keyName in $config.PSObject.Properties.Name) {
    if ($allowedKeys -cnotcontains $keyName) {
      throw "$keyName is not allowed in revenuecat.local.json. Keep Staging, Firebase, product ids, and server settings in their dedicated configuration."
    }
  }

  if ($config.ENABLE_REVENUECAT_BILLING -ne $true) {
    throw 'ENABLE_REVENUECAT_BILLING must be true in revenuecat.local.json.'
  }

  $genericKey = ([string]$config.REVENUECAT_API_KEY).Trim()
  $androidKey = ([string]$config.REVENUECAT_ANDROID_API_KEY).Trim()
  $providedKeys = @($genericKey, $androidKey) | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
  }

  if ($providedKeys.Count -eq 0) {
    throw 'REVENUECAT_API_KEY or REVENUECAT_ANDROID_API_KEY is required in revenuecat.local.json.'
  }

  foreach ($sdkKey in $providedKeys) {
    if ($sdkKey.Length -le 5 -or
        -not $sdkKey.StartsWith('test_', [System.StringComparison]::Ordinal)) {
      throw 'Only a RevenueCat Test Store public SDK key beginning with test_ is allowed in Staging device builds.'
    }
  }
}

$stagingDefines = if (Test-Path $localDefines) {
  $localDefines
} elseif (Test-Path $exampleDefines) {
  Write-Host 'staging.local.json was not found; using the checked-in non-secret staging example.'
  $exampleDefines
} else {
  throw 'Missing staging configuration. Restore staging.local.example.json or add an ignored staging.local.json.'
}

if (-not (Test-Path $googleServices)) {
  throw 'Missing android/app/src/debug/google-services.json for Firebase Staging.'
}

foreach ($argument in $FlutterArgs) {
  if ($argument -match '^--(release|profile|debug)(?:=|$)' -or
      $argument -match '^--dart-define(?:=|$)' -or
      $argument -match '^--dart-define-from-file(?:=|$)') {
    throw 'Build mode and Dart define overrides are not allowed by the staging helper.'
  }
}

$defines = Get-Content -Raw -LiteralPath $stagingDefines | ConvertFrom-Json
Assert-NoServerSecrets -Config $defines -SourceLabel 'Staging configuration'

if ($defines.ENABLE_REVENUECAT_BILLING -ne $false) {
  throw 'ENABLE_REVENUECAT_BILLING must remain false in the base Staging configuration. Enable it only in revenuecat.local.json.'
}

foreach ($sdkKeyName in @(
    'REVENUECAT_API_KEY',
    'REVENUECAT_ANDROID_API_KEY',
    'REVENUECAT_IOS_API_KEY'
  )) {
  if ($defines.PSObject.Properties.Name -contains $sdkKeyName) {
    throw 'RevenueCat SDK keys must be kept in the ignored revenuecat.local.json Test Store overlay.'
  }
}

if ([string]$defines.API_BASE_URL -ne 'https://postdee-api-staging.onrender.com') {
  throw 'API_BASE_URL must point to https://postdee-api-staging.onrender.com for staging runs.'
}

if ($defines.ENABLE_FIREBASE_AUTH -ne $true) {
  throw 'ENABLE_FIREBASE_AUTH must be true for staging runs.'
}

if ($defines.ALLOW_LOCAL_MOCK_AUTH -ne $false) {
  throw 'ALLOW_LOCAL_MOCK_AUTH must be false for staging runs.'
}

$serverClientId = ([string]$defines.GOOGLE_SERVER_CLIENT_ID).Trim()
if ([string]::IsNullOrWhiteSpace($serverClientId)) {
  throw 'GOOGLE_SERVER_CLIENT_ID is required for staging runs.'
}

$firebaseConfig = Get-Content -Raw $googleServices | ConvertFrom-Json
$stagingClients = @(
  $firebaseConfig.client | Where-Object {
    $_.client_info.android_client_info.package_name -eq 'com.postdee.postdee_mobile.staging'
  }
)

if ($stagingClients.Count -ne 1) {
  throw 'Firebase Staging must contain exactly one com.postdee.postdee_mobile.staging client.'
}

$webClients = @(
  $stagingClients[0].oauth_client | Where-Object { $_.client_type -eq 3 }
)

if ($webClients.Count -ne 1 -or [string]$webClients[0].client_id -ne $serverClientId) {
  throw 'GOOGLE_SERVER_CLIENT_ID must match the Web OAuth client in the Firebase Staging config.'
}

$revenueCatDefines = $null
if ($Command -in @('run', 'build-apk')) {
  $revenueCatDefines = Resolve-RevenueCatTestStoreDefines
  if ([string]::IsNullOrWhiteSpace($revenueCatDefines)) {
    throw 'RevenueCat Test Store config is required for Staging device builds. Add an ignored apps/mobile/revenuecat.local.json with ENABLE_REVENUECAT_BILLING=true and a public test_ SDK key.'
  }

  Assert-RevenueCatTestStoreDefines -Path $revenueCatDefines
  Write-Host "Using validated RevenueCat Test Store config from $revenueCatDefines (SDK key hidden)."
}

function Resolve-FlutterBat {
  $searchRoot = $mobileRoot

  while (-not [string]::IsNullOrWhiteSpace($searchRoot)) {
    $candidate = Join-Path $searchRoot '.tools\flutter\bin\flutter.bat'
    if (Test-Path $candidate) {
      return $candidate
    }

    $parent = Split-Path -Parent $searchRoot
    if ($parent -eq $searchRoot) {
      break
    }
    $searchRoot = $parent
  }

  throw 'Workspace Flutter SDK was not found in this checkout or its parent directories.'
}

$flutter = Resolve-FlutterBat
$flutterCommand = @(
  switch ($Command) {
    'run' {
      'run'
      '--debug'
    }
    'build-apk' {
      'build'
      'apk'
      '--debug'
    }
    'test' { 'test' }
  }
)

Push-Location $mobileRoot
try {
  $dartDefineArgs = @("--dart-define-from-file=$stagingDefines")
  if (-not [string]::IsNullOrWhiteSpace($revenueCatDefines)) {
    $dartDefineArgs += "--dart-define-from-file=$revenueCatDefines"
  }

  & $flutter @flutterCommand @dartDefineArgs @FlutterArgs
  $flutterExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

exit $flutterExitCode
