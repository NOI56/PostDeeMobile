$ErrorActionPreference = 'Stop'
$script:passed = 0
$script:failed = 0
$testPackage = 'com.postdee.postdee_mobile.staging'

# Load only functions and the launch workflow AST. The top-level resolver and
# mutex are not executed; every bridge/process/build/window operation is fake.
$tokens = $null
$parseErrors = $null
$launcherAst = [System.Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $PSScriptRoot 'launch-postdee-android.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Launcher parsing failed.' }
$selector = @($launcherAst.FindAll({
  param($Node)
  $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $Node.Name -ceq 'Get-ReadyEmulatorId'
}, $true))
if ($selector.Count -ne 1) { throw 'The emulator selector was not found.' }
. ([scriptblock]::Create($selector[0].Extent.Text))
$workflow = @($launcherAst.EndBlock.Statements | Where-Object {
  $_ -is [System.Management.Automation.Language.TryStatementAst]
})
if ($workflow.Count -ne 1) { throw 'The launch workflow was not found.' }
$workflowBody = [scriptblock]::Create($workflow[0].Body.Extent.Text.Trim().Substring(1).TrimEnd().TrimEnd('}'))
$parameterProbe = [scriptblock]::Create($launcherAst.ParamBlock.Extent.Text +
  "`n[pscustomobject]@{ AvdName = `$AvdName; OpenOnly = [bool]`$OpenOnly }")

function Assert-Equal($Expected, $Actual) {
  if ($Expected -cne $Actual) { throw "Expected '$Expected', got '$Actual'." }
}
function Assert-Throws([scriptblock]$Action) {
  $failed = $false
  try { & $Action | Out-Null } catch { $failed = $true }
  if (-not $failed) { throw 'Expected the operation to stop.' }
}
function Test-Case([string]$Name, [scriptblock]$Action) {
  try {
    & $Action
    $script:passed++
    Write-Output "PASS $Name"
  } catch {
    $script:failed++
    Write-Output "FAIL ${Name}: $($_.Exception.Message)"
  }
}
function Reset-FakeLauncher {
  $script:commands = [System.Collections.Generic.List[string]]::new()
  $script:events = [System.Collections.Generic.List[string]]::new()
  $script:clock = [datetime]'2026-10-30T00:00:00Z'
  $script:inventoryReads = 0
  $script:inventoryExit = 0
  $script:identityExit = 0
  $script:identityOverride = $null
  $script:launchExit = 0
  $script:buildExit = 0
  $script:packageExists = $true
  $script:afterBuild = $null
  $script:afterPackageProbe = $null
  $script:afterUpdate = $null
  $script:afterForceStop = $null
  $script:bootCompleted = '1'
  $script:availableAvds = @('Pixel_8', 'Other_AVD')
  $script:avdNames = @{ 'emulator-5554' = 'Other_AVD'; 'emulator-5556' = 'Pixel_8' }
  $script:inventory = { @('List of devices attached', "emulator-5554`tdevice", "emulator-5556`tdevice") }
  $script:AvdName = 'Pixel_8'
  $script:OpenOnly = $true
  $script:EmulatorBootTimeoutSeconds = 10
  $script:androidSdk = 'FAKE-SDK-NEVER-EXECUTE'
  $script:mobileRoot = Join-Path (Split-Path -Qualifier $PSScriptRoot) 'fixture-mobile'
  $script:sourceCommit = 'fixture-main'
  $script:adb = {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $command = $Arguments -join ' '
    $script:commands.Add($command)
    $global:LASTEXITCODE = 0
    if ($command -ceq 'start-server') { return }
    if ($command -ceq 'devices') {
      $script:inventoryReads++
      $output = & $script:inventory
      $global:LASTEXITCODE = $script:inventoryExit
      return $output
    }
    if ($command -match '^-s (emulator-\d+) emu avd name$') {
      $serial = $Matches[1]
      $global:LASTEXITCODE = $script:identityExit
      if ($null -ne $script:identityOverride) { return $script:identityOverride }
      return @($script:avdNames[$serial], 'OK')
    }
    if ($command -match '^-s emulator-\d+ shell getprop sys.boot_completed$') {
      return $script:bootCompleted
    }
    if ($command -match '^-s emulator-\d+ shell am start -n ') {
      $global:LASTEXITCODE = $script:launchExit
      return
    }
    if ($command -match '^-s emulator-\d+ shell am force-stop ') {
      if ($script:afterForceStop) { & $script:afterForceStop }
      return
    }
    throw "Unexpected fake bridge command: $command"
  }
  $script:emulator = {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    if (($Arguments -join ' ') -cne '-list-avds') { throw 'Unexpected emulator command.' }
    $global:LASTEXITCODE = 0
    return $script:availableAvds
  }
  $script:stagingHelper = {
    param([string]$Command, [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
    $script:events.Add("build:$Command $($FlutterArgs -join ' ')")
    if ($script:afterBuild) { & $script:afterBuild }
    $global:LASTEXITCODE = $script:buildExit
  }
}

function Resolve-PostDeeAndroidAvdHome { return $null }
function Get-Date { return $script:clock }
function Start-Sleep { param([int]$Seconds) $script:clock = $script:clock.AddSeconds($Seconds) }
function Start-Process {
  param($FilePath, [string[]]$ArgumentList, [string]$WindowStyle)
  $script:events.Add("emulator:$($ArgumentList -join ' ') window:$WindowStyle")
}
function Test-PostDeeAndroidBootStorageReady {
  param($Adb, [string]$DeviceId, [string]$PackageName)
  $script:events.Add("storage:$DeviceId")
  return $true
}
function Get-PostDeeAndroidPackageState {
  param($Adb, [string]$DeviceId, [string]$PackageName)
  $script:events.Add("package:$DeviceId")
  if ($script:afterPackageProbe) { & $script:afterPackageProbe }
  return [pscustomobject]@{ Exists = $script:packageExists; Uid = 10197; VolumeUuid = ''; VersionCode = 12093 }
}
function Get-PostDeeAndroidBuildNumber {
  param($Adb, [string]$DeviceId, [string]$PackageName)
  $script:events.Add("version:$DeviceId")
  return 12093
}
function Invoke-PostDeeAndroidApkUpdate {
  param($Adb, [string]$DeviceId, [string]$PackageName, [string]$Apk)
  $script:events.Add("update:$DeviceId")
  if ($script:afterUpdate) { & $script:afterUpdate }
}
function Show-EmulatorWindow {
  param([string]$DeviceId)
  $script:events.Add("focus:$DeviceId")
}
function Test-Path {
  param([string]$LiteralPath)
  if ($LiteralPath -cne (Join-Path $script:mobileRoot 'build\app\outputs\flutter-apk\app-debug.apk')) {
    throw "Unexpected fake filesystem probe: $LiteralPath"
  }
  return $true
}
function Invoke-FakeLauncher {
  $oldAndroidHome = $env:ANDROID_HOME
  $oldAndroidSdkRoot = $env:ANDROID_SDK_ROOT
  try { & $workflowBody } finally {
    $env:ANDROID_HOME = $oldAndroidHome
    $env:ANDROID_SDK_ROOT = $oldAndroidSdkRoot
  }
}
function Assert-NoUpdate {
  Assert-Equal 0 @($script:events | Where-Object { $_ -match '^(build|version|update):' }).Count
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match '\b(install|uninstall|force-stop|clear|move-package|set-install-location)\b' }).Count
}
function Assert-NoAppLaunch {
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match 'shell am start ' }).Count
}

Test-Case 'launcher defaults to the named Pixel_8 AVD' {
  Assert-Equal 'Pixel_8' (& $parameterProbe).AvdName
}
Test-Case 'launcher accepts an explicit open-existing mode' {
  Assert-Equal $true (& $parameterProbe -OpenOnly).OpenOnly
}
Test-Case 'selector uses the requested AVD even when another emulator is first' {
  Reset-FakeLauncher
  Assert-Equal 'emulator-5556' (Get-ReadyEmulatorId -TargetAvdName 'Pixel_8')
}
Test-Case 'selector does not fall back to another ready AVD' {
  Reset-FakeLauncher
  Assert-Equal $null (Get-ReadyEmulatorId -TargetAvdName 'Absent_AVD')
}
Test-Case 'duplicate instances of the requested AVD stop selection' {
  Reset-FakeLauncher
  $script:avdNames['emulator-5554'] = 'Pixel_8'
  Assert-Throws { Get-ReadyEmulatorId -TargetAvdName 'Pixel_8' }
}
Test-Case 'failed device inventory stops selection' {
  Reset-FakeLauncher
  $script:inventoryExit = 1
  Assert-Throws { Get-ReadyEmulatorId -TargetAvdName 'Pixel_8' }
}
Test-Case 'malformed device inventory stops selection' {
  Reset-FakeLauncher
  $script:inventory = { 'bridge unavailable' }
  Assert-Throws { Get-ReadyEmulatorId -TargetAvdName 'Pixel_8' }
}
Test-Case 'failed AVD identity lookup stops selection' {
  Reset-FakeLauncher
  $script:identityExit = 1
  Assert-Throws { Get-ReadyEmulatorId -TargetAvdName 'Pixel_8' }
}
Test-Case 'ambiguous AVD identity output stops selection' {
  Reset-FakeLauncher
  $script:identityOverride = @('Pixel_8', 'Other_AVD', 'OK')
  Assert-Throws { Get-ReadyEmulatorId -TargetAvdName 'Pixel_8' }
}
Test-Case 'open-existing mode opens only the requested installed app without updating it' {
  Reset-FakeLauncher
  Invoke-FakeLauncher
  Assert-NoUpdate
  Assert-Equal 1 @($script:commands | Where-Object { $_ -ceq "-s emulator-5556 shell am start -n $testPackage/com.postdee.postdee_mobile.MainActivity" }).Count
  Assert-Equal 1 @($script:events | Where-Object { $_ -ceq 'package:emulator-5556' }).Count
  Assert-Equal 1 @($script:events | Where-Object { $_ -ceq 'focus:emulator-5556' }).Count
}
Test-Case 'open-existing mode stops when the requested app is missing' {
  Reset-FakeLauncher
  $script:packageExists = $false
  Assert-Throws { Invoke-FakeLauncher }
  Assert-NoUpdate
  Assert-NoAppLaunch
}
Test-Case 'boot polling waits for the requested AVD while another remains ready' {
  Reset-FakeLauncher
  $script:inventory = {
    if ($script:inventoryReads -lt 3) { return @('List of devices attached', "emulator-5554`tdevice") }
    return @('List of devices attached', "emulator-5554`tdevice", "emulator-5556`tdevice")
  }
  Invoke-FakeLauncher
  Assert-NoUpdate
  Assert-Equal 1 @($script:events | Where-Object { $_ -ceq 'emulator:-avd "Pixel_8" window:Hidden' }).Count
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match '^-s emulator-5554 shell ' }).Count
  Assert-Equal 1 @($script:commands | Where-Object { $_ -match '^-s emulator-5556 shell am start ' }).Count
}
Test-Case 'an unavailable requested AVD never opens a different ready device' {
  Reset-FakeLauncher
  $script:inventory = { @('List of devices attached', "emulator-5554`tdevice") }
  $script:availableAvds = @('Other_AVD')
  Assert-Throws { Invoke-FakeLauncher }
  Assert-NoUpdate
  Assert-NoAppLaunch
  Assert-Equal 0 @($script:events | Where-Object { $_ -match '^emulator:' }).Count
}
Test-Case 'boot timeout does not launch the app on another ready device' {
  Reset-FakeLauncher
  $script:inventory = { @('List of devices attached', "emulator-5554`tdevice") }
  Assert-Throws { Invoke-FakeLauncher }
  Assert-NoUpdate
  Assert-NoAppLaunch
}
Test-Case 'update mode preserves the installed version and selected device' {
  Reset-FakeLauncher
  $script:OpenOnly = $false
  Invoke-FakeLauncher
  Assert-Equal 1 @($script:events | Where-Object { $_ -ceq 'version:emulator-5556' }).Count
  Assert-Equal 1 @($script:events | Where-Object { $_ -ceq 'build:build-apk --build-number=12093' }).Count
  Assert-Equal 1 @($script:events | Where-Object { $_ -ceq 'update:emulator-5556' }).Count
  Assert-Equal 1 @($script:commands | Where-Object { $_ -ceq "-s emulator-5556 shell am force-stop $testPackage" }).Count
}
Test-Case 'build failure prevents installation and app launch' {
  Reset-FakeLauncher
  $script:OpenOnly = $false
  $script:buildExit = 1
  Assert-Throws { Invoke-FakeLauncher }
  Assert-Equal 0 @($script:events | Where-Object { $_ -match '^update:' }).Count
  Assert-NoAppLaunch
}
Test-Case 'open-existing launch failure never attempts an update as recovery' {
  Reset-FakeLauncher
  $script:launchExit = 1
  Assert-Throws { Invoke-FakeLauncher }
  Assert-NoUpdate
}
Test-Case 'serial reuse during build stops before installing on a different AVD' {
  Reset-FakeLauncher
  $script:OpenOnly = $false
  $script:afterBuild = { $script:avdNames['emulator-5556'] = 'Replacement_AVD' }
  Assert-Throws { Invoke-FakeLauncher }
  Assert-Equal 0 @($script:events | Where-Object { $_ -match '^update:' }).Count
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match 'shell am force-stop ' }).Count
  Assert-NoAppLaunch
}
Test-Case 'an AVD moving to another serial during build does not change the update target' {
  Reset-FakeLauncher
  $script:OpenOnly = $false
  $script:afterBuild = {
    $script:avdNames['emulator-5554'] = 'Pixel_8'
    $script:avdNames['emulator-5556'] = 'Replacement_AVD'
  }
  Assert-Throws { Invoke-FakeLauncher }
  Assert-Equal 0 @($script:events | Where-Object { $_ -match '^update:' }).Count
  Assert-NoAppLaunch
}
Test-Case 'serial reuse after update stops before force-stopping another AVD' {
  Reset-FakeLauncher
  $script:OpenOnly = $false
  $script:afterUpdate = { $script:avdNames['emulator-5556'] = 'Replacement_AVD' }
  Assert-Throws { Invoke-FakeLauncher }
  Assert-Equal 1 @($script:events | Where-Object { $_ -ceq 'update:emulator-5556' }).Count
  Assert-Equal 0 @($script:commands | Where-Object { $_ -match 'shell am force-stop ' }).Count
  Assert-NoAppLaunch
}
Test-Case 'serial reuse after the package probe stops an open-existing launch' {
  Reset-FakeLauncher
  $script:afterPackageProbe = { $script:avdNames['emulator-5556'] = 'Replacement_AVD' }
  Assert-Throws { Invoke-FakeLauncher }
  Assert-NoUpdate
  Assert-NoAppLaunch
}
Test-Case 'serial reuse after force-stop stops before starting the app on another AVD' {
  Reset-FakeLauncher
  $script:OpenOnly = $false
  $script:afterForceStop = { $script:avdNames['emulator-5556'] = 'Replacement_AVD' }
  Assert-Throws { Invoke-FakeLauncher }
  Assert-Equal 1 @($script:commands | Where-Object { $_ -ceq "-s emulator-5556 shell am force-stop $testPackage" }).Count
  Assert-NoAppLaunch
}

Write-Output "$script:passed launcher tests passed; $script:failed failed (fake bridge/processes only)."
if ($script:failed) { exit 1 }
