# Public configuration and release preflight. Never print configuration values/passwords.
function Assert-AndroidPrivateFile {
    param([string]$Repository, [string]$Path, [string]$Label)
    if (![IO.Path]::IsPathRooted($Path)) { throw "$Label needs an absolute private path." }
    $resolved = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($Repository).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($resolved -eq $root -or $resolved.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "$Label must be outside source." }
    if (!(Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label file is missing." }
    $ancestor = $resolved
    while ($ancestor) {
        if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$Label must not traverse a reparse point." }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $resolved
}

function Get-AndroidBuildConfig {
    param([string]$Repository, [string]$ConfigPath = '', [string]$Configuration, [string]$ExportFormat)
    $path = Join-Path $Repository 'game/app_config.json'
    if ($ConfigPath) { $path = Assert-AndroidPrivateFile $Repository $ConfigPath 'AppConfigPath' }
    try {
        $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $names = @($config.PSObject.Properties.Name | Sort-Object)
        $expected = @('api_base_url', 'entitlement_id', 'purchase_mode', 'revenuecat_public_key')
        if (($names -join ',') -cne ($expected -join ',')) { throw 'Invalid fields.' }
        foreach ($name in $expected) { if ($config.$name -isnot [string]) { throw 'Invalid type.' } }
        if ($config.api_base_url -cnotmatch '^https://[a-z0-9.-]+(?::443)?$') { throw 'Invalid endpoint.' }
        $mode = $config.purchase_mode
        $key = $config.revenuecat_public_key
        if (($mode -ceq 'test_store' -and $config.entitlement_id -ceq 'full_journey' -and $key -cmatch '^test_[A-Za-z0-9_-]{7,251}$') -or
            ($mode -ceq 'google_play' -and $config.entitlement_id -ceq 'full_journey_play' -and $key -cmatch '^goog_[A-Za-z0-9_-]{7,251}$')) { }
        else { throw 'Invalid store configuration.' }
    } catch { throw 'Invalid app configuration; values are withheld.' }
    if ($Configuration -eq 'Release' -and $config.purchase_mode -cne 'google_play') { throw 'Release requires the Google Play configuration, never Test Store.' }
    if ($ExportFormat -eq 'AAB' -and ($Configuration -ne 'Release' -or !$ConfigPath)) { throw 'AAB requires Release and an explicit private AppConfigPath.' }
    return $config
}

function Assert-AndroidReleaseSigning {
    param([string]$Repository, [string]$KeyPath, [string]$PasswordPath, [string]$Alias, [string]$ExpectedSha256)
    if (!$KeyPath -or !$PasswordPath -or $Alias -cnotmatch '^[A-Za-z0-9_.-]{1,128}$' -or $ExpectedSha256 -cnotmatch '^[a-fA-F0-9]{64}$') {
        throw 'Release requires an existing SigningKeyPath, SigningPasswordPath (DPAPI), SigningAlias and ExpectedSignerSha256. No release key is generated.'
    }
    Assert-AndroidPrivateFile $Repository $KeyPath 'SigningKeyPath' | Out-Null
    Assert-AndroidPrivateFile $Repository $PasswordPath 'SigningPasswordPath' | Out-Null
}

function Assert-AndroidBundletool {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine 'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29') {
        throw 'Provide the official bundletool-all-1.18.3.jar with the documented SHA-256.'
    }
}

function Assert-AndroidPackagedConfig {
    param([string]$ArchivePath, $Expected)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries = @($archive.Entries | Where-Object { $_.FullName -match '(^|/)assets/app_config\.json$' })
        if ($entries.Count -ne 1) { throw 'Export needs one unambiguous packaged app configuration.' }
        $reader = [IO.StreamReader]::new($entries[0].Open())
        try { $actual = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        $names = @($Expected.PSObject.Properties.Name | Sort-Object)
        if ((@($actual.PSObject.Properties.Name | Sort-Object) -join ',') -cne ($names -join ',')) { throw 'Packaged app configuration fields differ.' }
        foreach ($name in $names) {
            if ($actual.$name -isnot [string] -or $actual.$name -cne $Expected.$name) { throw 'Packaged app configuration differs from the requested build.' }
        }
    } finally { $archive.Dispose() }
}

function Export-AndroidBundleVerificationApk {
    param([string]$Bundle, [string]$BundletoolJar, [string]$JdkPath, [string]$BuildTools, [string]$KeyPath, [string]$Alias, [string]$ExpectedSha256)
    $java = Join-Path $JdkPath 'bin/java.exe'
    $jarReport = (& (Join-Path $JdkPath 'bin/jarsigner.exe') '-J-Duser.language=en' -verify -strict $Bundle 2>&1) -join "`n"
    # A publisher certificate is self-signed (strict exit bit 4); unsigned entries
    # and all other verification failures are rejected independently.
    if ($LASTEXITCODE -notin @(0, 4) -or $jarReport -notmatch 'jar verified') { throw 'AAB JAR signature verification failed.' }
    $certificate = (& (Join-Path $JdkPath 'bin/keytool.exe') '-J-Duser.language=en' -printcert -jarfile $Bundle) -join "`n"
    $digest = [regex]::Match($certificate, 'SHA256:\s*([0-9A-Fa-f:]{95})').Groups[1].Value.Replace(':', '')
    if ($LASTEXITCODE -ne 0 -or $digest -ine $ExpectedSha256) { throw 'AAB signer does not match the selected certificate.' }
    $validation = (& $java -jar $BundletoolJar validate "--bundle=$Bundle" 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Bundle validation failed.' }
    $config = (& $java -jar $BundletoolJar dump config "--bundle=$Bundle") -join "`n"
    if ($LASTEXITCODE -ne 0 -or $config -notmatch 'PAGE_ALIGNMENT_16K') { throw 'Bundle does not request 16 KB native library alignment.' }
    $directory = $Bundle + '.verification'
    if (Test-Path -LiteralPath $directory) { throw 'Bundle verification directory already exists.' }
    New-Item -ItemType Directory -Path $directory | Out-Null
    [IO.File]::WriteAllText((Join-Path $directory 'bundle-validation.txt'), $validation)
    [IO.File]::WriteAllText((Join-Path $directory 'bundle-config.json'), $config)
    # No signing password is passed to bundletool. Its generated inspection APK is
    # re-signed explicitly with apksigner's environment-password support below.
    $apks = Join-Path $directory 'universal.apks'
    & $java -jar $BundletoolJar build-apks "--bundle=$Bundle" "--output=$apks" --mode=universal | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Bundle APK generation failed.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($apks)
    $rawApk = Join-Path $directory 'universal-generated.apk'
    try {
        $entry = $archive.GetEntry('universal.apk')
        if ($null -eq $entry) { throw 'Bundletool did not produce a universal APK.' }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $rawApk, $false)
    } finally { $archive.Dispose() }
    $apk = Join-Path $directory 'universal-signed.apk'
    & (Join-Path $BuildTools 'apksigner.bat') sign --ks $KeyPath --ks-key-alias $Alias --ks-pass env:AFTERYOU_KEY_PASSWORD --key-pass env:AFTERYOU_KEY_PASSWORD --out $apk $rawApk | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Verification APK signing failed.' }
    return $apk
}
