param(
  [int]$EmulatorBootTimeoutSeconds = 180,
  [switch]$ResolveOnly
)

$ErrorActionPreference = 'Stop'

function Get-MainWorktreeRoot {
  param([string]$RepositoryRoot)

  $currentWorktree = $null
  $worktreeLines = @(& git -C $RepositoryRoot worktree list --porcelain 2>$null)
  if ($LASTEXITCODE -ne 0) {
    throw "Git could not inspect worktrees in: $RepositoryRoot"
  }

  foreach ($line in $worktreeLines) {
    if ($line.StartsWith('worktree ')) {
      $currentWorktree = $line.Substring('worktree '.Length).Trim()
      continue
    }

    if ($line -eq 'branch refs/heads/main' -and $currentWorktree) {
      return $currentWorktree
    }

    if ([string]::IsNullOrWhiteSpace($line)) {
      $currentWorktree = $null
    }
  }

  throw 'No Git worktree checked out on the exact main branch was found.'
}

$launcherMobileRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $launcherMobileRoot)
$mainWorktreeRoot = Get-MainWorktreeRoot -RepositoryRoot $workspaceRoot
$mobileRoot = Join-Path $mainWorktreeRoot 'apps\mobile'
$flutter = Join-Path $workspaceRoot '.tools\flutter\bin\flutter.bat'
$stagingDefines = Join-Path $launcherMobileRoot 'staging.local.json'
$androidStudio = 'C:\Program Files\Android\Android Studio\bin\studio64.exe'
$androidSdk = 'C:\Users\stopp\AppData\Local\Android\Sdk'
$androidAvdHome = 'D:\.android\avd'
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
$emulator = Join-Path $androidSdk 'emulator\emulator.exe'
$apk = Join-Path $mobileRoot 'build\app\outputs\flutter-apk\app-debug.apk'
$packageName = 'com.postdee.postdee_mobile.staging'
$launchActivity = 'com.postdee.postdee_mobile.MainActivity'
$logDirectory = Join-Path $mobileRoot '.dart_tool'
$logFile = Join-Path $logDirectory 'postdee-android-launcher.log'

if ($ResolveOnly) {
  foreach ($requiredPath in @($mobileRoot, $stagingDefines)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      throw "Required path was not found: $requiredPath"
    }
  }

  Write-Output 'SourceBranch=main'
  Write-Output "SourceWorktreeRoot=$mainWorktreeRoot"
  Write-Output "SourceMobileRoot=$mobileRoot"
  Write-Output "StagingDefines=$stagingDefines"
  exit 0
}

function Show-LauncherMessage {
  param(
    [string]$Message,
    [System.Windows.MessageBoxImage]$Icon = [System.Windows.MessageBoxImage]::Information
  )

  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show(
    $Message,
    'PostDee Android Launcher',
    [System.Windows.MessageBoxButton]::OK,
    $Icon
  ) | Out-Null
}

function Write-LauncherStatus {
  param([string]$Message)

  $timestamped = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
  Write-Host $timestamped -ForegroundColor Cyan
  Add-Content -LiteralPath $logFile -Value $timestamped -Encoding UTF8
}

function Get-ReadyEmulatorId {
  $deviceLines = @(& $adb devices 2>$null)
  foreach ($line in $deviceLines) {
    if ($line -match '^(emulator-\d+)\s+device$') {
      return $Matches[1]
    }
  }

  return $null
}

function Show-EmulatorWindow {
  if (-not ('PostDeeWindowFocus' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class PostDeeWindowFocus {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
  }

  $windowProcess = Get-Process emulator, qemu-system-x86_64 -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
  if ($windowProcess) {
    [PostDeeWindowFocus]::ShowWindow($windowProcess.MainWindowHandle, 9) | Out-Null
    [PostDeeWindowFocus]::SetForegroundWindow($windowProcess.MainWindowHandle) | Out-Null
  }
}

function Start-InstalledPostDee {
  param([string]$DeviceId)

  $installedPath = & $adb -s $DeviceId shell pm path $packageName 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $installedPath) {
    return $false
  }

  & $adb -s $DeviceId shell am force-stop $packageName | Out-Null
  & $adb -s $DeviceId shell am start -n "$packageName/$launchActivity" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return $false
  }

  Start-Sleep -Milliseconds 500
  Show-EmulatorWindow
  return $true
}

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
Set-Content -LiteralPath $logFile -Value "PostDee Android launcher $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8

$createdNew = $false
$launcherMutex = New-Object System.Threading.Mutex($true, 'PostDeeAndroidLauncher', [ref]$createdNew)
if (-not $createdNew) {
  Show-EmulatorWindow
  Show-LauncherMessage -Message 'PostDee is already starting. Please wait for the existing update to finish.'
  $launcherMutex.Dispose()
  exit 0
}

$launcherExitCode = 0

try {
  foreach ($requiredPath in @(
      $mobileRoot,
      $flutter,
      $stagingDefines,
      $androidStudio,
      $androidSdk,
      $androidAvdHome,
      $adb,
      $emulator
    )) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      throw "Required path was not found: $requiredPath"
    }
  }

  $env:ANDROID_HOME = $androidSdk
  $env:ANDROID_SDK_ROOT = $androidSdk
  $env:ANDROID_AVD_HOME = $androidAvdHome

  Write-LauncherStatus 'Opening the PostDee project in Android Studio...'
  Start-Process -FilePath $androidStudio -ArgumentList @($mobileRoot) | Out-Null

  & $adb start-server | Out-Null
  $deviceId = Get-ReadyEmulatorId

  if (-not $deviceId) {
    $availableAvds = @(
      & $emulator -list-avds 2>$null |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
    )
    $avdName = if ($availableAvds -contains 'Pixel_8') {
      'Pixel_8'
    } elseif ($availableAvds.Count -gt 0) {
      $availableAvds[0]
    } else {
      throw "No Android emulator was found in $androidAvdHome"
    }

    Write-LauncherStatus "Starting Android Emulator $avdName..."
    Start-Process -FilePath $emulator -ArgumentList @('-avd', $avdName) | Out-Null
  }

  Write-LauncherStatus 'Waiting for Android to be ready...'
  $deadline = (Get-Date).AddSeconds($EmulatorBootTimeoutSeconds)
  $deviceId = $null
  do {
    Start-Sleep -Seconds 2
    $candidateDeviceId = Get-ReadyEmulatorId
    if ($candidateDeviceId) {
      $bootCompleted = (& $adb -s $candidateDeviceId shell getprop sys.boot_completed 2>$null).Trim()
      if ($bootCompleted -eq '1') {
        $deviceId = $candidateDeviceId
        break
      }
    }
  } while ((Get-Date) -lt $deadline)

  if (-not $deviceId) {
    throw "Pixel_8 did not finish starting within $EmulatorBootTimeoutSeconds seconds."
  }

  Write-LauncherStatus 'Android is ready.'
  if (Start-InstalledPostDee -DeviceId $deviceId) {
    Write-LauncherStatus 'PostDee is open. Updating it to the latest code now...'
  } else {
    Write-LauncherStatus 'Building PostDee for the first launch...'
    Show-EmulatorWindow
  }

  Push-Location $mobileRoot
  try {
    & $flutter build apk --debug "--dart-define-from-file=$stagingDefines"
    if ($LASTEXITCODE -ne 0) {
      throw "Flutter could not build the latest PostDee debug app (exit $LASTEXITCODE)."
    }
  } finally {
    Pop-Location
  }

  if (-not (Test-Path -LiteralPath $apk)) {
    throw "The debug APK was not created: $apk"
  }

  Write-LauncherStatus 'Installing the latest PostDee app...'
  & $adb -s $deviceId install -r $apk | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Android could not install the PostDee debug app (exit $LASTEXITCODE)."
  }

  if (-not (Start-InstalledPostDee -DeviceId $deviceId)) {
    throw 'Android installed PostDee but could not open it.'
  }

  Write-LauncherStatus 'PostDee is ready and showing the latest app.'
} catch {
  $launcherExitCode = 1
  Add-Content -LiteralPath $logFile -Value $_.Exception.ToString() -Encoding UTF8
  Show-LauncherMessage -Message $_.Exception.Message -Icon ([System.Windows.MessageBoxImage]::Error)
} finally {
  if ($createdNew) {
    $launcherMutex.ReleaseMutex() | Out-Null
  }
  $launcherMutex.Dispose()
}

exit $launcherExitCode
