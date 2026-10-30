param(
  [ValidateRange(10, 900)]
  [int]$EmulatorBootTimeoutSeconds = 180,
  [ValidateNotNullOrEmpty()]
  [string]$AvdName = 'Pixel_8',
  [switch]$ResolveOnly,
  [switch]$OpenOnly
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
$resolveBuildPaths = -not $OpenOnly -or $ResolveOnly
$requiredPaths = @($mobileRoot)
if ($resolveBuildPaths) { $requiredPaths += @($stagingHelper, $stagingDefines) }
foreach ($requiredPath in $requiredPaths) {
  if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required main-worktree path was not found: $requiredPath" }
}
$flutter = if ($resolveBuildPaths) { Resolve-WorkspaceFlutter } else { $null }
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

. (Join-Path $mobileRoot 'tool\android-install-volume.ps1')

function Get-ReadyEmulatorId {
  param([Parameter(Mandatory = $true)][string]$TargetAvdName)
  if ([string]::IsNullOrWhiteSpace($TargetAvdName)) { throw 'An exact Android AVD name is required.' }
  $lines = @(& $adb devices 2>$null)
  if ($LASTEXITCODE -ne 0) { throw 'Android emulator inventory could not be inspected.' }
  $headerCount = 0
  $readyEmulators = @()
  $seenDevices = @()
  foreach ($line in $lines) {
    $line = ([string]$line).Trim()
    if (-not $line) { continue }
    if ($line -ceq 'List of devices attached') { $headerCount++; continue }
    if ($line -notmatch '^(\S+)\s+(device|offline|unauthorized)$') {
      throw 'Android returned invalid emulator inventory.'
    }
    $serial = $Matches[1]
    $state = $Matches[2]
    if ($seenDevices -ccontains $serial) { throw 'Android returned duplicate device identifiers.' }
    $seenDevices += $serial
    if ($serial -match '^emulator-\d+$' -and $state -ceq 'device') { $readyEmulators += $serial }
  }
  if ($headerCount -ne 1) { throw 'Android emulator inventory could not be verified.' }
  $matchingDevices = @()
  foreach ($serial in $readyEmulators) {
    $nameOutput = @(& $adb -s $serial emu avd name 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not verify the AVD name for $serial." }
    $names = @($nameOutput | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and $_ -cne 'OK' })
    if ($names.Count -ne 1 -or $names[0] -match '^(KO:|error:)') {
      throw "Android returned an invalid AVD name for $serial."
    }
    if ($names[0] -ceq $TargetAvdName) { $matchingDevices += $serial }
  }
  if ($matchingDevices.Count -gt 1) { throw "More than one running emulator uses AVD $TargetAvdName. Close the duplicate before continuing." }
  if ($matchingDevices.Count -eq 1) { return $matchingDevices[0] }
  return $null
}

function Show-EmulatorWindow {
  param([string]$DeviceId)
  if ($DeviceId -notmatch '^emulator-(\d+)$') { return }
  $port = $Matches[1]
  $windows = @(Get-Process emulator, qemu-system-x86_64 -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match "(?:^|\D)$port(?:\D|$)" })
  if ($windows.Count -ne 1) { return }
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
  [PostDeeWindowFocus]::ShowWindow($windows[0].MainWindowHandle, 9) | Out-Null
  [PostDeeWindowFocus]::SetForegroundWindow($windows[0].MainWindowHandle) | Out-Null
}

$createdNew = $false
$launcherMutex = New-Object System.Threading.Mutex($true, 'PostDeeAndroidLauncher', [ref]$createdNew)
if (-not $createdNew) {
  $launcherMutex.Dispose()
  Write-Output 'PostDee is already starting. Wait for the existing launcher to finish.'
  exit 0
}
$launcherExitCode = 0
$launcherAvdHomeBefore = $env:ANDROID_AVD_HOME
$launcherChangedAvdHome = $false
try {
  $env:ANDROID_HOME = $androidSdk
  $env:ANDROID_SDK_ROOT = $androidSdk
  # Keep the user's Android home/debug keystore. Some emulator versions do not
  # discover ANDROID_USER_HOME/avd unless ANDROID_AVD_HOME is also explicit.
  if ([string]::IsNullOrWhiteSpace($env:ANDROID_AVD_HOME)) {
    $resolvedAvdHome = Resolve-PostDeeAndroidAvdHome -AvdHome $env:ANDROID_AVD_HOME -AndroidUserHome $env:ANDROID_USER_HOME
    if ($resolvedAvdHome) {
      $env:ANDROID_AVD_HOME = $resolvedAvdHome
      $launcherChangedAvdHome = $true
    }
  }
  & $adb start-server | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not start the Android device bridge.' }
  $deviceId = Get-ReadyEmulatorId -TargetAvdName $AvdName
  if (-not $deviceId) {
    $availableAvds = @(& $emulator -list-avds 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0 -or @($availableAvds | Where-Object { $_ -ceq $AvdName }).Count -ne 1) {
      throw 'No matching Android virtual device was found. Create an AVD or pass its exact name with -AvdName.'
    }
    Write-Host "Starting Android Emulator $AvdName..."
    Start-Process -FilePath $emulator -ArgumentList @('-avd', ('"{0}"' -f $AvdName)) -WindowStyle Hidden | Out-Null
  }
  $packageName = 'com.postdee.postdee_mobile.staging'
  $deadline = (Get-Date).AddSeconds($EmulatorBootTimeoutSeconds)
  $deviceId = $null
  do {
    $candidateId = Get-ReadyEmulatorId -TargetAvdName $AvdName
    if ($candidateId) {
      $bootCompleted = @(& $adb -s $candidateId shell getprop sys.boot_completed 2>$null)
      if ($LASTEXITCODE -ne 0) { throw 'Android boot state could not be inspected.' }
      if (($bootCompleted -join '').Trim() -eq '1' -and
          (Test-PostDeeAndroidBootStorageReady -Adb $adb -DeviceId $candidateId -PackageName $packageName)) {
        $deviceId = $candidateId
        break
      }
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  if (-not $deviceId) { throw "Android storage and its existing PostDee package did not finish starting within $EmulatorBootTimeoutSeconds seconds. No installation was started; wait for storage and retry." }

  if ($OpenOnly) {
    $installed = Get-PostDeeAndroidPackageState -Adb $adb -DeviceId $deviceId -PackageName $packageName
    if (-not $installed.Exists) { throw "PostDee Staging is not installed on $AvdName. OpenOnly will not build or install it; use the update command explicitly." }
  } else {
    $buildNumber = Get-PostDeeAndroidBuildNumber -Adb $adb -DeviceId $deviceId -PackageName $packageName
    Write-Host "Building main $sourceCommit through the validated Staging helper (build $buildNumber)..."
    & $stagingHelper -Command build-apk "--build-number=$buildNumber"
    if ($LASTEXITCODE -ne 0) { throw "The Staging build failed (exit $LASTEXITCODE)." }
    $apk = Join-Path $mobileRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'The Staging APK was not created.' }
    # A long build can outlive an emulator; serials may be reused by another AVD.
    if ((Get-ReadyEmulatorId -TargetAvdName $AvdName) -cne $deviceId) {
      throw 'The selected Android emulator changed. No installation was started.'
    }
    Invoke-PostDeeAndroidApkUpdate -Adb $adb -DeviceId $deviceId -PackageName $packageName -Apk $apk | Out-Null
    if ((Get-ReadyEmulatorId -TargetAvdName $AvdName) -cne $deviceId) {
      throw 'The selected Android emulator changed after installation. No app was force-stopped.'
    }
    & $adb -s $deviceId shell am force-stop $packageName | Out-Null
  }
  if ((Get-ReadyEmulatorId -TargetAvdName $AvdName) -cne $deviceId) {
    throw 'The selected Android emulator changed. The app was not opened.'
  }
  & $adb -s $deviceId shell am start -n "$packageName/com.postdee.postdee_mobile.MainActivity"
  if ($LASTEXITCODE -ne 0) { throw 'Android could not open PostDee Staging.' }
  Show-EmulatorWindow -DeviceId $deviceId
  if ($OpenOnly) {
    Write-Host "Opened existing PostDee Staging on $AvdName without building, installing or force-stopping the app."
  } else {
    Write-Host 'PostDee Staging is ready. The update kept the existing package UID and storage volume; no data was cleared.'
  }
} catch {
  $launcherExitCode = 1
  Write-Error -Message $_.Exception.Message -ErrorAction Continue
} finally {
  if ($launcherChangedAvdHome) { $env:ANDROID_AVD_HOME = $launcherAvdHomeBefore }
  if ($createdNew) { $launcherMutex.ReleaseMutex() | Out-Null }
  $launcherMutex.Dispose()
}
exit $launcherExitCode
