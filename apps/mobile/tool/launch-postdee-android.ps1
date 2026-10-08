param(
  [ValidateRange(10, 900)]
  [int]$EmulatorBootTimeoutSeconds = 180,
  [string]$AvdName = '',
  [switch]$ResolveOnly
)

$ErrorActionPreference = 'Stop'
$launcherMobileRoot = Split-Path -Parent $PSScriptRoot
$launcherRepositoryRoot = Split-Path -Parent (Split-Path -Parent $launcherMobileRoot)

function Get-MainWorktreeRoot {
  $currentWorktree = $null
  $lines = @(& git -C $launcherRepositoryRoot worktree list --porcelain 2>$null)
  if ($LASTEXITCODE -ne 0) { throw 'Git could not inspect the PostDee worktrees.' }
  foreach ($line in $lines) {
    if ($line.StartsWith('worktree ')) {
      $currentWorktree = $line.Substring('worktree '.Length).Trim()
    } elseif ($line -eq 'branch refs/heads/main' -and $currentWorktree) {
      return $currentWorktree
    } elseif ([string]::IsNullOrWhiteSpace($line)) {
      $currentWorktree = $null
    }
  }
  throw 'No worktree is checked out on the exact main branch. Open a main worktree before using this launcher.'
}

function Resolve-WorkspaceFlutter {
  $searchRoot = $launcherRepositoryRoot
  while (-not [string]::IsNullOrWhiteSpace($searchRoot)) {
    $candidate = Join-Path $searchRoot '.tools\flutter\bin\flutter.bat'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $parent = Split-Path -Parent $searchRoot
    if ($parent -eq $searchRoot) { break }
    $searchRoot = $parent
  }
  $commonDirectory = & git -C $launcherRepositoryRoot rev-parse --path-format=absolute --git-common-dir 2>$null
  if ($LASTEXITCODE -eq 0 -and $commonDirectory) {
    $candidate = Join-Path (Split-Path -Parent ([string]$commonDirectory).Trim()) '.tools\flutter\bin\flutter.bat'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  throw 'The workspace .tools/flutter SDK was not found.'
}

function Resolve-AndroidSdk {
  $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
  foreach ($candidateMobileRoot in @($mobileRoot, $launcherMobileRoot)) {
    $propertiesPath = Join-Path $candidateMobileRoot 'android\local.properties'
    if (Test-Path -LiteralPath $propertiesPath) {
      foreach ($line in Get-Content -LiteralPath $propertiesPath) {
        if ($line -match '^\s*sdk\.dir\s*=\s*(.+)$') {
          $candidates += $Matches[1].Trim().Replace('\\', '\').Replace('\:', ':')
        }
      }
    }
  }
  if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
  if ($env:USERPROFILE) { $candidates += Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk' }
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    if ((Test-Path -LiteralPath (Join-Path $candidate 'platform-tools\adb.exe')) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'emulator\emulator.exe'))) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw 'Android SDK with platform-tools and emulator was not found. Set ANDROID_HOME/ANDROID_SDK_ROOT or android/local.properties.'
}

$mainWorktreeRoot = Get-MainWorktreeRoot
$mobileRoot = Join-Path $mainWorktreeRoot 'apps\mobile'
$stagingHelper = Join-Path $mobileRoot 'tool\postdee-staging.ps1'
$stagingDefines = Join-Path $mobileRoot 'staging.local.json'
if (-not (Test-Path -LiteralPath $stagingDefines)) {
  $stagingDefines = Join-Path $mobileRoot 'staging.local.example.json'
}
foreach ($requiredPath in @($mobileRoot, $stagingHelper, $stagingDefines)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required main-worktree path was not found: $requiredPath" }
}
$flutter = Resolve-WorkspaceFlutter
$androidSdk = Resolve-AndroidSdk
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
$emulator = Join-Path $androidSdk 'emulator\emulator.exe'
$sourceCommit = & git -C $mainWorktreeRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the main worktree commit.' }

# ResolveOnly performs path inspection only: no adb, build, install, log or UI.
if ($ResolveOnly) {
  Write-Output 'SourceBranch=main'
  Write-Output "SourceCommit=$sourceCommit"
  Write-Output "SourceWorktreeRoot=$mainWorktreeRoot"
  Write-Output "SourceMobileRoot=$mobileRoot"
  Write-Output "Flutter=$flutter"
  Write-Output "AndroidSdk=$androidSdk"
  Write-Output "StagingHelper=$stagingHelper"
  Write-Output "StagingDefines=$stagingDefines"
  Write-Output 'BuildValidation=postdee-staging.ps1 (including the ignored RevenueCat Test Store overlay)'
  exit 0
}

function Get-ReadyEmulatorId {
  $lines = @(& $adb devices 2>$null)
  foreach ($line in $lines) {
    if ($line -match '^(emulator-\d+)\s+device$') { return $Matches[1] }
  }
  return $null
}

function Show-EmulatorWindow {
  if (-not ('PostDeeWindowFocus' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PostDeeWindowFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int command);
}
'@
  }
  $window = Get-Process emulator, qemu-system-x86_64 -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($window) {
    [PostDeeWindowFocus]::ShowWindow($window.MainWindowHandle, 9) | Out-Null
    [PostDeeWindowFocus]::SetForegroundWindow($window.MainWindowHandle) | Out-Null
  }
}

$createdNew = $false
$launcherMutex = New-Object System.Threading.Mutex($true, 'PostDeeAndroidLauncher', [ref]$createdNew)
if (-not $createdNew) {
  $launcherMutex.Dispose()
  Write-Output 'PostDee is already starting. Wait for the existing launcher to finish.'
  exit 0
}
$launcherExitCode = 0
try {
  $env:ANDROID_HOME = $androidSdk
  $env:ANDROID_SDK_ROOT = $androidSdk
  # Leave ANDROID_AVD_HOME/ANDROID_USER_HOME intact for the user's existing AVDs
  # and debug keystore. Replacing those paths can break update signatures.
  & $adb start-server | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not start the Android device bridge.' }
  $deviceId = Get-ReadyEmulatorId
  if (-not $deviceId) {
    $availableAvds = @(& $emulator -list-avds 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $selectedAvd = $AvdName
    if ([string]::IsNullOrWhiteSpace($selectedAvd)) {
      $selectedAvd = $availableAvds | Select-Object -First 1
    }
    if (-not $selectedAvd -or $availableAvds -cnotcontains $selectedAvd) {
      throw 'No matching Android virtual device was found. Create an AVD or pass its exact name with -AvdName.'
    }
    Write-Host "Starting Android Emulator $selectedAvd..."
    Start-Process -FilePath $emulator -ArgumentList @('-avd', ('"{0}"' -f $selectedAvd)) -WindowStyle Hidden | Out-Null
  }
  $deadline = (Get-Date).AddSeconds($EmulatorBootTimeoutSeconds)
  $deviceId = $null
  do {
    $candidateId = Get-ReadyEmulatorId
    if ($candidateId) {
      $bootCompleted = @(& $adb -s $candidateId shell getprop sys.boot_completed 2>$null)
      if (($bootCompleted -join '').Trim() -eq '1') { $deviceId = $candidateId; break }
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  if (-not $deviceId) { throw "Android did not finish starting within $EmulatorBootTimeoutSeconds seconds." }

  Write-Host "Building main $sourceCommit through the validated Staging helper..."
  & $stagingHelper -Command build-apk
  if ($LASTEXITCODE -ne 0) { throw "The Staging build failed (exit $LASTEXITCODE)." }
  $apk = Join-Path $mobileRoot 'build\app\outputs\flutter-apk\app-debug.apk'
  if (-not (Test-Path -LiteralPath $apk)) { throw 'The Staging APK was not created.' }
  & $adb -s $deviceId install -r $apk
  if ($LASTEXITCODE -ne 0) {
    throw 'Android could not update PostDee. Keep the existing app/data and inspect the build signature; this launcher does not uninstall or clear data.'
  }
  $packageName = 'com.postdee.postdee_mobile.staging'
  & $adb -s $deviceId shell am force-stop $packageName | Out-Null
  & $adb -s $deviceId shell am start -n "$packageName/com.postdee.postdee_mobile.MainActivity"
  if ($LASTEXITCODE -ne 0) { throw 'Android installed PostDee but could not open it.' }
  Show-EmulatorWindow
  Write-Host 'PostDee Staging is ready. Existing app data was retained by install -r.'
} catch {
  $launcherExitCode = 1
  Write-Error -Message $_.Exception.Message -ErrorAction Continue
} finally {
  if ($createdNew) { $launcherMutex.ReleaseMutex() | Out-Null }
  $launcherMutex.Dispose()
}
exit $launcherExitCode
