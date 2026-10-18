# Loading this helper defines functions only; it does not contact a device.
function Resolve-PostDeeAndroidAvdHome {
  param([string]$AvdHome, [string]$AndroidUserHome, [scriptblock]$PathExists)
  if (-not [string]::IsNullOrWhiteSpace($AvdHome)) { return $AvdHome }
  if ([string]::IsNullOrWhiteSpace($AndroidUserHome)) { return $null }
  $candidate = Join-Path $AndroidUserHome 'avd'
  $exists = if ($PathExists) { & $PathExists $candidate } else { Test-Path -LiteralPath $candidate -PathType Container }
  if ($exists) { return $candidate }
  return $null
}

function Resolve-PostDeeAndroidAdb {
  param([Parameter(Mandatory = $true)][string]$MobileRoot)
  $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
  $propertiesPath = Join-Path $MobileRoot 'android\local.properties'
  if (Test-Path -LiteralPath $propertiesPath) {
    foreach ($line in Get-Content -LiteralPath $propertiesPath) {
      if ($line -match '^\s*sdk\.dir\s*=\s*(.+)$') {
        $candidates += $Matches[1].Trim().Replace('\\', '\').Replace('\:', ':')
      }
    }
  }
  if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    $adbCandidate = Join-Path $candidate 'platform-tools\adb.exe'
    if (Test-Path -LiteralPath $adbCandidate) { return (Resolve-Path -LiteralPath $adbCandidate).Path }
  }
  throw 'Android adb was not found. Set ANDROID_HOME/ANDROID_SDK_ROOT or android/local.properties before a Staging run.'
}

function Invoke-PostDeeAndroidAdb {
  param([string]$Adb, [string[]]$Arguments, [scriptblock]$AdbRunner)
  if ($AdbRunner) { return & $AdbRunner $Arguments }
  $output = @(& $Adb @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output | ForEach-Object { [string]$_ }) }
}

function ConvertFrom-PostDeeAndroidPackageDump {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PackageDump,
    [Parameter(Mandatory = $true)][string]$PackageName
  )
  $packageHeaders = [regex]::Matches($PackageDump, '(?m)^\s*Package \[([^\]]+)\] \([^\r\n]*\):\s*$')
  $codePaths = [regex]::Matches($PackageDump, '(?m)^\s+codePath=([^\s]+)\s*$')
  $uids = [regex]::Matches($PackageDump, '(?m)^\s+(?:userId|appId)=(\d+)\s*$')
  $versionCodes = [regex]::Matches($PackageDump, '(?m)^\s+versionCode=(\d+)(?:[ \t]+[^\r\n]*)?\r?$')
  $volumes = [regex]::Matches($PackageDump, '(?m)^\s+volumeUuid=([^\s]+)\s*$')
  if ($packageHeaders.Count -ne 1 -or $packageHeaders[0].Groups[1].Value -cne $PackageName -or
      $codePaths.Count -ne 1 -or $uids.Count -ne 1 -or $versionCodes.Count -ne 1 -or $volumes.Count -gt 1) {
    throw 'Could not verify the existing Android package and storage. No installation is safe from this package probe.'
  }
  $codePath = $codePaths[0].Groups[1].Value
  $uid = [long]$uids[0].Groups[1].Value
  if ($uid -le 0) { throw 'Android returned an invalid package UID.' }
  $versionCode = [long]$versionCodes[0].Groups[1].Value
  if ($versionCode -lt 1 -or $versionCode -gt [int]::MaxValue) { throw 'Android returned an invalid installed versionCode.' }
  $volumeUuid = ''
  $reportedVolume = if ($volumes.Count -eq 1) { $volumes[0].Groups[1].Value } else { '' }
  $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  if ($codePath -match "^/mnt/expand/($guidPattern)/app/[^\s]+$") {
    $volumeUuid = $Matches[1].ToLowerInvariant()
    if ($reportedVolume -ine $volumeUuid) { throw 'The Android package path and adopted volume do not match. Installation stopped.' }
  } elseif ($codePath -match '^/data/app/[^\s]+$') {
    if ($reportedVolume -and $reportedVolume -cne 'null') { throw 'The internal Android package reports a conflicting volume. Installation stopped.' }
  } else {
    throw 'The Android package has an unsupported storage path. Installation stopped.'
  }
  return [pscustomobject]@{ Exists = $true; Uid = $uid; VolumeUuid = $volumeUuid; VersionCode = $versionCode }
}

function Test-PostDeeAndroidBootStorageReady {
  param([string]$Adb, [string]$DeviceId, [string]$PackageName, [scriptblock]$AdbRunner)
  $storage = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('-s', $DeviceId, 'shell', 'sm', 'list-volumes', 'private') -AdbRunner $AdbRunner
  if ($storage.ExitCode -ne 0) { throw 'Android private storage could not be inspected during boot.' }
  $internalCount = 0
  $hasExternal = $false
  $mountPending = $false
  $seenIds = @()
  foreach ($line in @($storage.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })) {
    if ($line -notmatch '^(private(?::\d+,\d+)?)\s+(unmounted|checking|mounted|mounted_ro|formatting|ejecting|unmountable|removed|bad_removal)\s+(null|[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})$') {
      throw 'Android returned invalid private storage metadata during boot.'
    }
    $volumeId = $Matches[1]
    $volumeState = $Matches[2]
    $volumeUuid = $Matches[3]
    if ($seenIds -contains $volumeId) { throw 'Android returned duplicate private storage metadata during boot.' }
    $seenIds += $volumeId
    if ($volumeId -ceq 'private') {
      $internalCount++
      if ($volumeUuid -cne 'null') { throw 'Android returned conflicting internal storage metadata during boot.' }
    } else {
      $hasExternal = $true
      if ($volumeUuid -ceq 'null') { $mountPending = $true }
    }
    if ($volumeState -cne 'mounted') { $mountPending = $true }
  }
  if ($internalCount -ne 1) { throw 'Android internal storage could not be verified during boot.' }
  if ($mountPending) { return $false }
  if (-not $hasExternal) { return $true }
  $listed = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('-s', $DeviceId, 'shell', 'pm', 'list', 'packages', '--user', '0', $PackageName) -AdbRunner $AdbRunner
  if ($listed.ExitCode -ne 0) { throw 'Android could not inspect its adopted package scan during boot.' }
  $packageLines = @($listed.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
  if ($packageLines.Count -eq 0) { return $false }
  if ($packageLines.Count -ne 1 -or $packageLines[0] -cne "package:$PackageName") { throw 'Android returned invalid package metadata during boot.' }
  return $true
}

function Get-PostDeeAndroidPackageState {
  param([string]$Adb, [string]$DeviceId, [string]$PackageName, [scriptblock]$AdbRunner)
  $listed = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('-s', $DeviceId, 'shell', 'pm', 'list', 'packages', '--user', '0', $PackageName) -AdbRunner $AdbRunner
  if ($listed.ExitCode -ne 0) { throw 'Android could not inspect the existing package. Installation stopped.' }
  $packageLines = @($listed.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
  $matchingPackages = @($packageLines | Where-Object { $_ -ceq "package:$PackageName" })
  if ($packageLines.Count -eq 0) {
    # boot_completed can precede adopted-volume mounting and package scanning.
    # An unavailable existing app must never be treated as a fresh install.
    $storage = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('-s', $DeviceId, 'shell', 'sm', 'list-volumes', 'private') -AdbRunner $AdbRunner
    if ($storage.ExitCode -ne 0) { throw 'Android storage could not be verified while PostDee is unavailable. Installation stopped.' }
    $storageLines = @($storage.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($storageLines.Count -ne 1 -or $storageLines[0] -cne 'private mounted null') {
      throw 'PostDee is unavailable while private storage may still be mounting or scanning. Wait for Android storage and its existing package, then retry; no installation was started.'
    }
    $retained = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('-s', $DeviceId, 'shell', 'pm', 'list', 'packages', '-u', '--user', '0', $PackageName) -AdbRunner $AdbRunner
    if ($retained.ExitCode -ne 0 -or @($retained.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -ne 0) {
      throw 'Android retains PostDee metadata or cannot confirm a fresh install. Wait for the existing package and inspect its storage; installation stopped.'
    }
    return [pscustomobject]@{ Exists = $false; Uid = $null; VolumeUuid = ''; VersionCode = 1 }
  }
  if ($matchingPackages.Count -ne 1 -or $packageLines.Count -ne 1) { throw 'Android returned an ambiguous package listing. Installation stopped.' }
  $dump = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('-s', $DeviceId, 'shell', 'dumpsys', 'package', $PackageName) -AdbRunner $AdbRunner
  if ($dump.ExitCode -ne 0) { throw 'Android could not read package storage metadata. Installation stopped.' }
  # Do not log dumpsys output: it can include account-related intent details.
  return ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($dump.Output -join "`n") -PackageName $PackageName
}

function Get-PostDeeAndroidBuildNumber {
  param([string]$Adb, [string]$DeviceId, [string]$PackageName, [scriptblock]$AdbRunner)
  # The pubspec starts at +1. Reuse the installed debug build number so a
  # launcher rebuild is an update, never a downgrade or forced reinstall.
  $state = Get-PostDeeAndroidPackageState -Adb $Adb -DeviceId $DeviceId -PackageName $PackageName -AdbRunner $AdbRunner
  return $state.VersionCode
}

function Invoke-PostDeeAndroidApkUpdate {
  param([string]$Adb, [string]$DeviceId, [string]$PackageName, [string]$Apk, [scriptblock]$AdbRunner)
  $before = Get-PostDeeAndroidPackageState -Adb $Adb -DeviceId $DeviceId -PackageName $PackageName -AdbRunner $AdbRunner
  $installArguments = @('-s', $DeviceId, 'install', '-r')
  if ($before.VolumeUuid) {
    $volumes = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('-s', $DeviceId, 'shell', 'sm', 'list-volumes', 'private') -AdbRunner $AdbRunner
    if ($volumes.ExitCode -ne 0) { throw 'Android could not check the current adopted volume. Installation stopped.' }
    $mountedPattern = '^private(?::\d+,\d+)?\s+mounted\s+' + [regex]::Escape($before.VolumeUuid) + '$'
    $mounted = @($volumes.Output | Where-Object { ([string]$_).Trim() -match $mountedPattern })
    if ($mounted.Count -ne 1) { throw 'The existing adopted volume is not mounted. Installation stopped.' }
    # Pin the already installed volume. This is never a cross-volume migration.
    $installArguments += @('--force-uuid', $before.VolumeUuid)
  }
  $installArguments += $Apk
  $installed = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments $installArguments -AdbRunner $AdbRunner
  if ($installed.ExitCode -ne 0) {
    throw 'Android could not update PostDee. The launcher will not uninstall, clear data, or retry on another volume.'
  }
  $after = Get-PostDeeAndroidPackageState -Adb $Adb -DeviceId $DeviceId -PackageName $PackageName -AdbRunner $AdbRunner
  if (-not $after.Exists -or ($before.Exists -and ($after.Uid -ne $before.Uid -or $after.VolumeUuid -ine $before.VolumeUuid -or $after.VersionCode -lt $before.VersionCode))) {
    throw 'Android installed the APK but its package UID, storage, or version changed unexpectedly. Do not launch it; inspect the preserved data before proceeding.'
  }
  return $after
}

function Assert-PostDeeAndroidFlutterRunSafe {
  param([string]$Adb, [string]$MobileRoot, [string]$PackageName, [string[]]$FlutterArgs = @(), [scriptblock]$AdbRunner)
  $requestedDevice = $null
  for ($argumentIndex = 0; $argumentIndex -lt $FlutterArgs.Count; $argumentIndex++) {
    $argument = $FlutterArgs[$argumentIndex]
    if ($argument -in @('-d', '--device-id')) {
      if ($requestedDevice -or $argumentIndex + 1 -ge $FlutterArgs.Count) { throw 'Pass one complete -d/--device-id value for the Staging run.' }
      $argumentIndex++
      $requestedDevice = $FlutterArgs[$argumentIndex]
    } elseif ($argument -match '^(?:-d|--device-id)=(.+)$') {
      if ($requestedDevice) { throw 'Pass only one device selection for the Staging run.' }
      $requestedDevice = $Matches[1]
    }
  }
  if ($requestedDevice -in @('windows', 'linux', 'macos', 'chrome', 'web-server', 'edge')) { return }
  if ([string]::IsNullOrWhiteSpace($Adb)) { $Adb = Resolve-PostDeeAndroidAdb -MobileRoot $MobileRoot }
  $devices = Invoke-PostDeeAndroidAdb -Adb $Adb -Arguments @('devices') -AdbRunner $AdbRunner
  if ($devices.ExitCode -ne 0) { throw 'Android devices could not be inspected before Flutter run. Use build-apk without installing until this is resolved.' }
  if (@($devices.Output | Where-Object { ([string]$_).Trim() -ceq 'List of devices attached' }).Count -ne 1) {
    throw 'Android returned an invalid device inventory. Flutter run stopped before installing.'
  }
  $deviceIds = @($devices.Output | ForEach-Object { if ([string]$_ -match '^(\S+)\s+device\s*$') { $Matches[1] } })
  if ($requestedDevice -and $requestedDevice -cne 'all') {
    $deviceIds = @($deviceIds | Where-Object { $_ -ceq $requestedDevice -or $_.StartsWith($requestedDevice, [StringComparison]::OrdinalIgnoreCase) })
    if ($deviceIds.Count -eq 0) { throw 'The device selection could not be verified as an online Android device. Use the full -d Android device ID or an explicit desktop/web target.' }
    if ($deviceIds.Count -gt 1) { throw 'The Android device selection is ambiguous. Pass the full -d device ID.' }
  }
  foreach ($deviceId in $deviceIds) {
    $state = Get-PostDeeAndroidPackageState -Adb $Adb -DeviceId $deviceId -PackageName $PackageName -AdbRunner $AdbRunner
    if ($state.VolumeUuid) {
      throw "Flutter run can reinstall PostDee on a different volume and hide existing data on $deviceId. Update through launch-postdee-android.ps1, then use flutter attach -d $deviceId for debugging. No installation was started."
    }
  }
}
