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

$defines = Get-Content -Raw $stagingDefines | ConvertFrom-Json

foreach ($blockedKey in @(
    'POSTDEE_MOCK_USER_ID',
    'POSTDEE_MOCK_SUBSCRIPTION_PLAN',
    'GEMINI_API_KEY',
    'GROQ_API_KEY',
    'ELEVENLABS_API_KEY',
    'REVENUECAT_WEBHOOK_AUTH_TOKEN'
  )) {
  if ($defines.PSObject.Properties.Name -contains $blockedKey) {
    throw "$blockedKey must not be passed to the mobile app."
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
  & $flutter @flutterCommand "--dart-define-from-file=$stagingDefines" @FlutterArgs
  $flutterExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

exit $flutterExitCode
