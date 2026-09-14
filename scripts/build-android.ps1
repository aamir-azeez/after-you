[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [string]$PrivateRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AfterYou-private'),
    [string]$GodotExe = '',
    [string]$JdkPath = '',
    [string]$AndroidSdk = ''
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$game = Join-Path $repo 'game'
$PrivateRoot = [IO.Path]::GetFullPath($PrivateRoot)
if ($PrivateRoot.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $PrivateRoot -eq $repo) {
    throw 'The signing and delivery directory must be outside the repository.'
}
if (!$GodotExe) { $GodotExe = Join-Path $PrivateRoot 'toolchain/godot/Godot_v4.7.2-stable_win64_console.exe' }
if (!$JdkPath) { $JdkPath = Join-Path $PrivateRoot 'toolchain/jdk/jdk-17.0.20.1+1' }
if (!$AndroidSdk) { $AndroidSdk = Join-Path $PrivateRoot 'toolchain/android-sdk' }
foreach ($required in @($GodotExe, "$JdkPath/bin/java.exe", "$JdkPath/bin/keytool.exe", "$AndroidSdk/platform-tools/adb.exe")) {
    if (!(Test-Path -LiteralPath $required)) { throw "Required tool not found: $required" }
}
$version = (& $GodotExe --version | Select-Object -Last 1).Trim()
if (!$version.StartsWith('4.7.2.stable')) { throw 'This build is pinned to Godot 4.7.2 stable.' }
$templateDirectory = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable'
$templateZip = Join-Path $templateDirectory 'android_source.zip'
if (!(Test-Path -LiteralPath $templateZip)) { throw 'Install the matching Godot 4.7.2 Android export templates first.' }

$androidDirectory = Join-Path $game 'android'
$androidBuild = Join-Path $androidDirectory 'build'
New-Item -ItemType Directory -Path $androidDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $androidDirectory '.gitignore'), "*`n")
if (!(Test-Path -LiteralPath "$androidBuild/build.gradle")) {
    New-Item -ItemType Directory -Path $androidBuild -Force | Out-Null
    Expand-Archive -LiteralPath $templateZip -DestinationPath $androidBuild -Force
    [IO.File]::WriteAllText((Join-Path $androidBuild '.gdignore'), '')
    [IO.File]::WriteAllText((Join-Path $androidDirectory '.build_version'), "4.7.2.stable`n")
}
if ((Get-Content -LiteralPath "$androidDirectory/.build_version" -Raw).Trim() -ne '4.7.2.stable') {
    throw 'Existing Android template belongs to another Godot version; move the generated game/android directory aside before rebuilding.'
}

# Keep native-store verification in the same Activity task, and prohibit cleartext network
# traffic. These changes are reapplied after installing a clean Godot Android template.
$manifestPath = Join-Path $androidBuild 'src/main/AndroidManifest.xml'
$manifest = New-Object Xml.XmlDocument
$manifest.PreserveWhitespace = $true
$manifest.Load($manifestPath)
$androidNamespace = 'http://schemas.android.com/apk/res/android'
$application = $manifest.SelectSingleNode('/manifest/application')
if ($null -eq $application) { throw 'Unexpected Android template: application element not found.' }
$application.SetAttribute('usesCleartextTraffic', $androidNamespace, 'false') | Out-Null
$application.SetAttribute('networkSecurityConfig', $androidNamespace, '@xml/after_you_network_security') | Out-Null
$activity = @($application.SelectNodes('activity')) | Where-Object { $_.GetAttribute('name', $androidNamespace) -eq '.GodotApp' }
if ($null -eq $activity) { throw 'Unexpected Android template: GodotApp Activity not found.' }
$activity.SetAttribute('launchMode', $androidNamespace, 'singleTop') | Out-Null
$manifest.Save($manifestPath)
$networkResource = Join-Path $androidBuild 'res/xml'
New-Item -ItemType Directory -Path $networkResource -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $networkResource 'after_you_network_security.xml'), '<?xml version="1.0" encoding="utf-8"?><network-security-config><base-config cleartextTrafficPermitted="false"><trust-anchors><certificates src="system" /></trust-anchors></base-config></network-security-config>')
$gradlePropertiesPath = Join-Path $androidBuild 'gradle.properties'
$gradleProperties = Get-Content -LiteralPath $gradlePropertiesPath -Raw
foreach ($setting in @(@('org.gradle.jvmargs','-Xmx2048m -Dfile.encoding=UTF-8'), @('org.gradle.daemon','false'), @('org.gradle.workers.max','2'), @('org.gradle.parallel','false'))) {
    $line = $setting[0] + '=' + $setting[1]
    $pattern = '(?m)^' + [regex]::Escape($setting[0]) + '=.*$'
    if ([regex]::IsMatch($gradleProperties, $pattern)) { $gradleProperties = [regex]::Replace($gradleProperties, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{param($m) $line}) }
    else { $gradleProperties += "`n$line`n" }
}
[IO.File]::WriteAllText($gradlePropertiesPath, $gradleProperties)

# SDK paths are editor preferences, never machine-specific entries in project.godot.
$editorSettings = Join-Path $env:APPDATA 'Godot/editor_settings-4.7.tres'
if (!(Test-Path -LiteralPath $editorSettings)) {
    & $GodotExe --headless --editor --path $game --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot could not initialize its editor preferences.' }
}
$settings = Get-Content -LiteralPath $editorSettings -Raw
foreach ($setting in @(@('export/android/java_sdk_path', $JdkPath), @('export/android/android_sdk_path', $AndroidSdk))) {
    $line = $setting[0] + ' = "' + $setting[1].Replace('\', '/') + '"'
    $pattern = '(?m)^' + [regex]::Escape($setting[0]) + '\s*=.*$'
    if ([regex]::IsMatch($settings, $pattern)) { $settings = [regex]::Replace($settings, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{param($m) $line}) }
    else { $settings += "`n$line`n" }
}
[IO.File]::WriteAllText($editorSettings, $settings)

$signing = Join-Path $PrivateRoot 'signing'
$delivery = Join-Path $PrivateRoot 'deliverables'
New-Item -ItemType Directory -Path $signing, $delivery -Force | Out-Null
$environmentNames = @('JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','AFTERYOU_KEY_PASSWORD',
    'GODOT_ANDROID_KEYSTORE_DEBUG_PATH','GODOT_ANDROID_KEYSTORE_DEBUG_USER','GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD',
    'GODOT_ANDROID_KEYSTORE_RELEASE_PATH','GODOT_ANDROID_KEYSTORE_RELEASE_USER','GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')
$previous = @{}
foreach ($name in $environmentNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$password = $null
try {
    $env:JAVA_HOME = $JdkPath
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $keyPath = Join-Path $signing ('aamirazeez-after-you-' + $Configuration.ToLowerInvariant() + '.keystore')
    $passwordPath = Join-Path $signing ('aamirazeez-after-you-' + $Configuration.ToLowerInvariant() + '.password.dpapi')
    $alias = 'aamirazeez-after-you-' + $Configuration.ToLowerInvariant()
    if ((Test-Path -LiteralPath $keyPath) -ne (Test-Path -LiteralPath $passwordPath)) {
        throw 'Signing key/password pair is incomplete. Restore the matching private backup; do not silently replace the key.'
    }
    if (!(Test-Path -LiteralPath $keyPath)) {
        $random = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($random) } finally { $rng.Dispose() }
        $password = [BitConverter]::ToString($random).Replace('-', '')
        $env:AFTERYOU_KEY_PASSWORD = $password
        & "$JdkPath/bin/keytool.exe" -genkeypair -keystore $keyPath -storetype PKCS12 -alias $alias -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=After You, O=aamirazeez' -storepass:env AFTERYOU_KEY_PASSWORD -keypass:env AFTERYOU_KEY_PASSWORD 2>&1 | ForEach-Object { Write-Output ($_.ToString().Replace($password, '[redacted]')) }
        if ($LASTEXITCODE -ne 0) { throw 'Signing key creation failed.' }
        ConvertTo-SecureString $password -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath $passwordPath
    } else {
        $secure = (Get-Content -LiteralPath $passwordPath -Raw).Trim() | ConvertTo-SecureString
        $password = [System.Net.NetworkCredential]::new('', $secure).Password
    }
    $prefix = 'GODOT_ANDROID_KEYSTORE_' + $Configuration.ToUpperInvariant()
    [Environment]::SetEnvironmentVariable($prefix + '_PATH', $keyPath, 'Process')
    [Environment]::SetEnvironmentVariable($prefix + '_USER', $alias, 'Process')
    [Environment]::SetEnvironmentVariable($prefix + '_PASSWORD', $password, 'Process')
    Push-Location (Join-Path $repo 'native')
    try {
        & .\gradlew.bat :plugin:packagePlugin --no-daemon --console=plain
        if ($LASTEXITCODE -ne 0) { throw 'Native plugin build failed.' }
    } finally { Pop-Location }
    $importState = [pscustomobject]@{ ScriptError = $false }
    & $GodotExe --headless --editor --path $game --import 2>&1 | ForEach-Object {
        $line = $_.ToString().Replace($password, '[redacted]')
        if ($line -match 'SCRIPT ERROR:|Parse Error:|Failed to load script') { $importState.ScriptError = $true }
        Write-Output $line
    }
    if ($LASTEXITCODE -ne 0 -or $importState.ScriptError) { throw 'Godot project import failed.' }
    $output = Join-Path $delivery ('After You - ' + $Configuration + '.apk')
    $exportMode = if ($Configuration -eq 'Debug') { '--export-debug' } else { '--export-release' }
    $exportState = [pscustomobject]@{ ScriptError = $false }
    & $GodotExe --headless --path $game $exportMode 'Android' $output 2>&1 | ForEach-Object {
        $line = $_.ToString().Replace($password, '[redacted]')
        if ($line -match 'SCRIPT ERROR:|Parse Error:|Failed to load script') { $exportState.ScriptError = $true }
        Write-Output $line
    }
    if ($LASTEXITCODE -ne 0 -or $exportState.ScriptError -or !(Test-Path -LiteralPath $output)) { throw 'Android export failed.' }
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory | Sort-Object Name -Descending | Select-Object -First 1
    $signatureReport = (& (Join-Path $buildTools.FullName 'apksigner.bat') verify --verbose --print-certs $output) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'APK signing verification failed.' }
    $certificateDn = [regex]::Match($signatureReport, '(?m)^Signer #1 certificate DN: (.+)$').Groups[1].Value.Trim()
    if ($certificateDn -notmatch '(^|,\s*)CN=After You(,|$)' -or $certificateDn -notmatch '(^|,\s*)O=aamirazeez(,|$)') { throw 'APK certificate does not match the application publisher.' }
    Write-Output $signatureReport
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($output + '.sha256', "$hash  $([IO.Path]::GetFileName($output))`n")
    Write-Output "Verified APK: $output"
    Write-Output "SHA-256: $hash"
} finally {
    $password = $null
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
