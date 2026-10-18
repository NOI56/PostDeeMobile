$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-install-volume.ps1')

$script:passed = 0
$testPackage = 'com.postdee.postdee_mobile.staging'
$testVolume = '11111111-2222-4333-8444-555555555555'

function Assert-Equal($Expected, $Actual) {
  if ($Expected -cne $Actual) { throw "Expected '$Expected', got '$Actual'." }
}

function Assert-Throws([scriptblock]$Action) {
  $failed = $false
  try { & $Action | Out-Null } catch { $failed = $true }
  if (-not $failed) { throw 'Expected the operation to stop.' }
}

function Test-Case([string]$Name, [scriptblock]$Action) {
  & $Action
  if ($script:commands -and @($script:commands | Where-Object { $_ -match '\b(uninstall|clear|move-package|set-install-location|run-as)\b' }).Count -ne 0) {
    throw 'A test attempted an unexpected device mutation.'
  }
  $script:passed++
  Write-Output "PASS $Name"
}

function New-PackageDump([string]$Volume = '', [int]$Uid = 10190) {
  $codePath = if ($Volume) { "/mnt/expand/$Volume/app/random/$testPackage-random" } else { "/data/app/random/$testPackage-random" }
  $volumeLine = if ($Volume) { "    volumeUuid=$Volume" } else { '' }
  return "Packages:`n  Package [$testPackage] (abc):`n    userId=$Uid`n    codePath=$codePath`n    versionCode=12024 minSdk=24 targetSdk=36`n$volumeLine`n    User 0: installed=true"
}

$internalDump = New-PackageDump
$adoptedDump = New-PackageDump $testVolume

Test-Case 'internal package keeps internal storage' {
  $state = ConvertFrom-PostDeeAndroidPackageDump -PackageDump $internalDump -PackageName $testPackage
  Assert-Equal $true $state.Exists
  Assert-Equal 10190 $state.Uid
  Assert-Equal 12024 $state.VersionCode
  Assert-Equal '' $state.VolumeUuid
}
Test-Case 'adopted package reads its exact current volume' {
  $state = ConvertFrom-PostDeeAndroidPackageDump -PackageDump $adoptedDump -PackageName $testPackage
  Assert-Equal $testVolume $state.VolumeUuid
}
Test-Case 'explicit null volume is valid on internal storage' {
  $state = ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump + "`n    volumeUuid=null") -PackageName $testPackage
  Assert-Equal '' $state.VolumeUuid
}
Test-Case 'missing dump stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump '' -PackageName $testPackage }
}
Test-Case 'wrong package stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($adoptedDump.Replace($testPackage, 'com.other.app')) -PackageName $testPackage }
}
Test-Case 'duplicate package records stop' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($adoptedDump + "`n" + $adoptedDump) -PackageName $testPackage }
}
Test-Case 'missing adopted volume stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($adoptedDump -replace '(?m)^.*volumeUuid=.*$', '') -PackageName $testPackage }
}
Test-Case 'conflicting adopted volume stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($adoptedDump.Replace("volumeUuid=$testVolume", 'volumeUuid=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')) -PackageName $testPackage }
}
Test-Case 'internal path with adopted metadata stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump + "`n    volumeUuid=$testVolume") -PackageName $testPackage }
}
Test-Case 'malformed adopted path stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($adoptedDump.Replace($testVolume, 'not-a-volume')) -PackageName $testPackage }
}
Test-Case 'unknown code path stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump.Replace('/data/app/', '/unknown/app/')) -PackageName $testPackage }
}
Test-Case 'missing UID stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump -replace '(?m)^.*userId=.*$', '') -PackageName $testPackage }
}
Test-Case 'duplicate code path stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump + "`n    codePath=/data/app/other") -PackageName $testPackage }
}
Test-Case 'duplicate UID stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump + "`n    userId=10191") -PackageName $testPackage }
}
Test-Case 'duplicate volume stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($adoptedDump + "`n    volumeUuid=$testVolume") -PackageName $testPackage }
}
Test-Case 'missing installed version stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump -replace '(?m)^.*versionCode=.*$', '') -PackageName $testPackage }
}
Test-Case 'duplicate installed version stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump + "`n    versionCode=12023 minSdk=24") -PackageName $testPackage }
}
Test-Case 'zero installed version stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump.Replace('versionCode=12024', 'versionCode=0')) -PackageName $testPackage }
}
Test-Case 'out of range installed version stops' {
  Assert-Throws { ConvertFrom-PostDeeAndroidPackageDump -PackageDump ($internalDump.Replace('versionCode=12024', 'versionCode=2147483648')) -PackageName $testPackage }
}

# All command execution below uses this fake bridge, never a real adb/device.
function Reset-FakeBridge {
  $script:commands = [System.Collections.Generic.List[string]]::new()
  $script:dumpReads = 0
  $script:beforeDump = $adoptedDump
  $script:afterDump = $adoptedDump
  $script:packagePresent = $true
  $script:probeExit = 0
  $script:dumpExit = 0
  $script:packageListingOverride = $null
  $script:installExit = 0
  $script:volumeMounted = $true
  $script:privateVolumePresent = $true
  $script:volumeOutputOverride = $null
  $script:retainedPackagePresent = $false
  $script:volumeExit = 0
  $script:deviceExit = 0
  $script:deviceOutputOverride = $null
  $script:secondDeviceDump = $internalDump
}
$fakeBridge = {
  param([string[]]$Arguments)
  $command = $Arguments -join ' '
  $script:commands.Add($command)
  $exitCode = 0
  $output = @()
  if ($command -eq 'devices') {
    $exitCode = $script:deviceExit
    $output = @('List of devices attached', "emulator-5556`tdevice", "emulator-5558`tdevice")
    if ($null -ne $script:deviceOutputOverride) { $output = @($script:deviceOutputOverride) }
  } elseif ($command -match 'shell pm list packages -u ') {
    $exitCode = $script:probeExit
    if ($script:retainedPackagePresent) { $output = @("package:$testPackage") }
  } elseif ($command -match 'shell pm list packages') {
    $exitCode = $script:probeExit
    if ($script:packagePresent) { $output = @("package:$testPackage") }
    if ($null -ne $script:packageListingOverride) { $output = @($script:packageListingOverride) }
  } elseif ($command -match 'shell dumpsys package') {
    $exitCode = $script:dumpExit
    $script:dumpReads++
    $output = @(if ($command.StartsWith('-s emulator-5558 ')) { $script:secondDeviceDump } elseif ($script:dumpReads -eq 1) { $script:beforeDump } else { $script:afterDump })
  } elseif ($command -match 'shell sm list-volumes private$') {
    $exitCode = $script:volumeExit
    $volumeState = if ($script:volumeMounted) { 'mounted' } else { 'unmounted' }
    $output = @('private mounted null')
    if ($script:privateVolumePresent) { $output += "private:253,82 $volumeState $testVolume" }
    if ($null -ne $script:volumeOutputOverride) { $output = @($script:volumeOutputOverride) }
  } elseif ($command -match ' install -r(?: |$)') {
    $exitCode = $script:installExit
    $script:packagePresent = $true
  } else { throw "Unexpected fake command: $command" }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}
function Invoke-FakeUpdate {
  Invoke-PostDeeAndroidApkUpdate -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -Apk 'fixture.apk' -AdbRunner $fakeBridge | Out-Null
}
function Assert-NoInstall {
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match ' install ' }).Count
}

Test-Case 'internal-only boot permits a genuine first install' {
  Reset-FakeBridge
  $script:privateVolumePresent = $false
  $script:packagePresent = $false
  Assert-Equal $true (Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge)
  Assert-NoInstall
}
Test-Case 'boot readiness waits for an adopted volume to mount' {
  Reset-FakeBridge
  $script:volumeOutputOverride = @('private mounted null', 'private:253,82 unmounted null')
  $script:packagePresent = $false
  Assert-Equal $false (Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge)
  Assert-NoInstall
}
Test-Case 'boot readiness waits for the adopted package scan' {
  Reset-FakeBridge
  $script:packagePresent = $false
  Assert-Equal $false (Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge)
  Assert-NoInstall
}
Test-Case 'boot readiness accepts a mounted volume and known package' {
  Reset-FakeBridge
  Assert-Equal $true (Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge)
  Assert-NoInstall
}
Test-Case 'boot readiness does not swallow a failed storage probe' {
  Reset-FakeBridge
  $script:volumeExit = 1
  Assert-Throws { Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'boot readiness does not swallow malformed storage metadata' {
  Reset-FakeBridge
  $script:volumeOutputOverride = 'Error: storage service unavailable'
  Assert-Throws { Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'boot readiness does not swallow a failed package probe' {
  Reset-FakeBridge
  $script:probeExit = 1
  Assert-Throws { Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'boot readiness does not swallow malformed package metadata' {
  Reset-FakeBridge
  $script:packageListingOverride = 'Error: package service unavailable'
  Assert-Throws { Test-PostDeeAndroidBootStorageReady -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}

Test-Case 'launcher build preserves installed versionCode 12024' {
  Reset-FakeBridge
  $buildNumber = Get-PostDeeAndroidBuildNumber -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge
  Assert-Equal 12024 $buildNumber
  Assert-NoInstall
}
Test-Case 'launcher first build uses versionCode 1' {
  Reset-FakeBridge
  $script:packagePresent = $false
  $script:privateVolumePresent = $false
  $buildNumber = Get-PostDeeAndroidBuildNumber -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge
  Assert-Equal 1 $buildNumber
  Assert-NoInstall
}
Test-Case 'failed version probe stops before any build or install' {
  Reset-FakeBridge
  $script:probeExit = 1
  Assert-Throws { Get-PostDeeAndroidBuildNumber -Adb 'FAKE-ADB-NEVER-EXECUTE' -DeviceId 'emulator-5556' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'actual launcher build invocation forwards the preserved number' {
  $launcherTokens = $null
  $launcherErrors = $null
  $launcherAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'launch-postdee-android.ps1'), [ref]$launcherTokens, [ref]$launcherErrors)
  if ($launcherErrors.Count) { throw 'Launcher parsing failed.' }
  $buildCommands = @($launcherAst.FindAll({
    param($Node)
    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.CommandElements[0].Extent.Text -ceq '$stagingHelper'
  }, $true))
  Assert-Equal 1 $buildCommands.Count
  $buildNumber = 12024
  $stagingHelper = {
    param([string]$Command, [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
    return [pscustomobject]@{ Command = $Command; FlutterArgs = $FlutterArgs }
  }
  $captured = & ([scriptblock]::Create($buildCommands[0].Extent.Text))
  Assert-Equal 'build-apk' $captured.Command
  Assert-Equal '--build-number=12024' ($captured.FlutterArgs -join ' ')
  Assert-NoInstall
}

Test-Case 'adopted update pins only the same current volume' {
  Reset-FakeBridge
  Invoke-FakeUpdate
  Assert-Equal "-s emulator-5556 install -r --force-uuid $testVolume fixture.apk" @($script:commands | Where-Object { $_ -match ' install ' })[0]
  Assert-Equal 2 $script:dumpReads
}
Test-Case 'internal update preserves existing command behavior' {
  Reset-FakeBridge
  $script:beforeDump = $internalDump
  $script:afterDump = $internalDump
  Invoke-FakeUpdate
  Assert-Equal '-s emulator-5556 install -r fixture.apk' @($script:commands | Where-Object { $_ -match ' install ' })[0]
}
Test-Case 'first install does not invent an adopted destination' {
  Reset-FakeBridge
  $script:packagePresent = $false
  $script:privateVolumePresent = $false
  $script:afterDump = $internalDump
  $script:beforeDump = $internalDump
  Invoke-FakeUpdate
  Assert-Equal '-s emulator-5556 install -r fixture.apk' @($script:commands | Where-Object { $_ -match ' install ' })[0]
}
Test-Case 'cold boot unmounted volume cannot masquerade as a first install' {
  Reset-FakeBridge
  $script:packagePresent = $false
  $script:volumeOutputOverride = @('private mounted null', 'private:253,82 unmounted null')
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'mounted volume awaiting package scan cannot masquerade as a first install' {
  Reset-FakeBridge
  $script:packagePresent = $false
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'retained internal package cannot masquerade as a first install' {
  Reset-FakeBridge
  $script:packagePresent = $false
  $script:privateVolumePresent = $false
  $script:retainedPackagePresent = $true
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'an empty package listing with failed storage probe stops' {
  Reset-FakeBridge
  $script:packagePresent = $false
  $script:volumeExit = 1
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'an empty package listing with unknown storage metadata stops' {
  Reset-FakeBridge
  $script:packagePresent = $false
  $script:volumeOutputOverride = 'Error: storage service unavailable'
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'failed package probe cannot fall back to first install' {
  Reset-FakeBridge
  $script:probeExit = 1
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'malformed package probe prevents installation' {
  Reset-FakeBridge
  $script:beforeDump = 'Error: unavailable'
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'failed dumpsys command prevents installation' {
  Reset-FakeBridge
  $script:dumpExit = 1
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'error output cannot be interpreted as a first install' {
  Reset-FakeBridge
  $script:packageListingOverride = 'Error: package service unavailable'
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'unmounted current volume prevents installation' {
  Reset-FakeBridge
  $script:volumeMounted = $false
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'failed volume probe prevents installation' {
  Reset-FakeBridge
  $script:volumeExit = 1
  Assert-Throws { Invoke-FakeUpdate }
  Assert-NoInstall
}
Test-Case 'installation failure does not trigger recovery writes' {
  Reset-FakeBridge
  $script:installExit = 1
  Assert-Throws { Invoke-FakeUpdate }
  Assert-Equal 1 @($script:commands | Where-Object { $_ -match ' install ' }).Count
  Assert-Equal 1 $script:dumpReads
}
Test-Case 'changed volume after update is reported as failure' {
  Reset-FakeBridge
  $script:afterDump = $internalDump
  Assert-Throws { Invoke-FakeUpdate }
}
Test-Case 'changed UID after update is reported as failure' {
  Reset-FakeBridge
  $script:afterDump = New-PackageDump $testVolume 10191
  Assert-Throws { Invoke-FakeUpdate }
}
Test-Case 'Flutter run stops before an adopted target can install' {
  Reset-FakeBridge
  Assert-Throws { Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -FlutterArgs @('-d', 'emulator-5556') -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'Flutter run allows an internal Android target' {
  Reset-FakeBridge
  $script:beforeDump = $internalDump
  Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -FlutterArgs @('--device-id=emulator-5556') -AdbRunner $fakeBridge
  Assert-NoInstall
}
Test-Case 'explicit desktop target does not inspect Android packages' {
  Reset-FakeBridge
  Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -FlutterArgs @('-d', 'windows') -AdbRunner $fakeBridge
  Assert-Equal 0 $script:dumpReads
  Assert-NoInstall
}
Test-Case 'explicit desktop target does not require an Android SDK' {
  Assert-PostDeeAndroidFlutterRunSafe -PackageName $testPackage -FlutterArgs @('-d', 'windows')
}
Test-Case 'another adopted device does not block the explicit internal target' {
  Reset-FakeBridge
  Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -FlutterArgs @('-d', 'emulator-5558') -AdbRunner $fakeBridge
  Assert-Equal 1 $script:dumpReads
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match '^-s emulator-5556 ' }).Count
}
Test-Case 'failed Android inventory stops Flutter run' {
  Reset-FakeBridge
  $script:deviceExit = 1
  Assert-Throws { Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'malformed Android inventory stops Flutter run' {
  Reset-FakeBridge
  $script:deviceOutputOverride = 'Error: bridge unavailable'
  Assert-Throws { Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'unspecified run cannot silently pick an adopted Android device' {
  Reset-FakeBridge
  Assert-Throws { Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'ambiguous Android device prefix stops' {
  Reset-FakeBridge
  Assert-Throws { Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -FlutterArgs @('-d', 'emulator-') -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'unknown device ID cannot bypass storage checks' {
  Reset-FakeBridge
  Assert-Throws { Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -FlutterArgs @('-d', 'unknown-device') -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'a friendly Flutter device name cannot bypass storage checks' {
  Reset-FakeBridge
  Assert-Throws { Assert-PostDeeAndroidFlutterRunSafe -Adb 'FAKE-ADB-NEVER-EXECUTE' -PackageName $testPackage -FlutterArgs @('-d', 'PostDee Pixel') -AdbRunner $fakeBridge }
  Assert-NoInstall
}
Test-Case 'test harness never executes an uninstall or data-clear command' {
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match '\b(uninstall|clear|move-package|set-install-location|run-as)\b' }).Count
}

Test-Case 'an explicit AVD home is preserved without probing alternatives' {
  $resolved = Resolve-PostDeeAndroidAvdHome -AvdHome 'D:\explicit-avds' -AndroidUserHome 'D:\other' -PathExists { throw 'Should not probe.' }
  Assert-Equal 'D:\explicit-avds' $resolved
}
Test-Case 'existing Android user home avd directory supplies the fallback' {
  $resolved = Resolve-PostDeeAndroidAvdHome -AndroidUserHome 'D:\fixture-user' -PathExists { param($Path) $Path -ceq 'D:\fixture-user\avd' }
  Assert-Equal 'D:\fixture-user\avd' $resolved
}
Test-Case 'an absent fallback directory does not invent an AVD home' {
  Assert-Equal $null (Resolve-PostDeeAndroidAvdHome -AndroidUserHome 'D:\fixture-user' -PathExists { $false })
}
Test-Case 'an unset Android user home does not invent an AVD home' {
  Assert-Equal $null (Resolve-PostDeeAndroidAvdHome -PathExists { throw 'Should not probe.' })
}

Write-Output "$script:passed PowerShell storage-guard tests passed (mock bridge only)."
