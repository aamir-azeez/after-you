$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-play.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('after-you-play-' + [Guid]::NewGuid().ToString('N'))
$repository = Join-Path $fixture 'source'
$configPath = Join-Path $fixture 'play.json'
$checks = 0
function Assert-Check([bool]$Value, [string]$Message) {
    if (!$Value) { throw $Message }
    $script:checks++
}
function Reject([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Check $rejected $Message
}
function Write-Config($Value) { [IO.File]::WriteAllText($configPath, ($Value | ConvertTo-Json)) }
try {
    New-Item -ItemType Directory -Path (Join-Path $repository 'game') -Force | Out-Null
    $play = @{api_base_url='https://example.invalid'; entitlement_id='full_journey_play'; purchase_mode='google_play'; revenuecat_public_key='goog_synthetic_public_key'}
    Write-Config $play
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $repository 'game/app_config.json')
    $arguments = @{Repository=$repository; ConfigPath=$configPath; Configuration='Release'; ExportFormat='AAB'}
    $accepted = Get-AndroidBuildConfig @arguments
    Assert-Check ($accepted.purchase_mode -ceq 'google_play') 'Valid explicit Play configuration rejected.'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($packaged in @('valid', 'stale', 'duplicate', 'missing')) {
        $archivePath = Join-Path $fixture ($packaged + '.aab')
        $zip = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
        try {
            if ($packaged -ne 'missing') {
                $entry = $zip.CreateEntry('assetPackInstallTime/assets/app_config.json')
                $writer = [IO.StreamWriter]::new($entry.Open())
                try {
                    $value = $play.Clone()
                    if ($packaged -eq 'stale') { $value.purchase_mode = 'test_store' }
                    $writer.Write(($value | ConvertTo-Json))
                } finally { $writer.Dispose() }
                if ($packaged -eq 'duplicate') { $zip.CreateEntry('base/assets/app_config.json') | Out-Null }
            }
        } finally { $zip.Dispose() }
        if ($packaged -eq 'valid') { Assert-AndroidPackagedConfig $archivePath $accepted; $checks++ }
        else { Reject { Assert-AndroidPackagedConfig $archivePath $accepted } 'Invalid packaged configuration accepted.' }
    }
    Reject { Get-AndroidBuildConfig -Repository $repository -Configuration Release -ExportFormat AAB } 'Bundle accepted implicit source configuration.'
    Reject { Get-AndroidBuildConfig -Repository $repository -ConfigPath $configPath -Configuration Debug -ExportFormat AAB } 'Debug bundle accepted.'
    Reject { Get-AndroidBuildConfig -Repository $repository -ConfigPath (Join-Path $repository 'game/app_config.json') -Configuration Release -ExportFormat AAB } 'Private config accepted inside source.'
    foreach ($invalid in @(
        @{purchase_mode='test_store'; revenuecat_public_key='test_synthetic_public_key'},
        @{purchase_mode='google_play'; revenuecat_public_key='test_synthetic_public_key'},
        @{purchase_mode='google_play'; revenuecat_public_key='sk_synthetic_secret_key'},
        @{api_base_url='http://example.invalid'},
        @{entitlement_id='other'},
        @{extra='unexpected'},
        @{purchase_mode=17}
    )) {
        $candidate = $play.Clone()
        foreach ($name in $invalid.Keys) { $candidate[$name] = $invalid[$name] }
        Write-Config $candidate
        Reject { Get-AndroidBuildConfig @arguments } 'Invalid production configuration accepted.'
    }
    [IO.File]::WriteAllText($configPath, '{ malformed synthetic input')
    Reject { Get-AndroidBuildConfig @arguments } 'Malformed JSON accepted.'
    $keyPath = Join-Path $fixture 'existing.keystore'
    $passwordPath = Join-Path $fixture 'existing.password.dpapi'
    [IO.File]::WriteAllText($keyPath, 'synthetic key placeholder')
    [IO.File]::WriteAllText($passwordPath, 'synthetic password placeholder')
    Assert-AndroidReleaseSigning $repository $keyPath $passwordPath 'existing-alias' ('a' * 64)
    $checks++
    Reject { Assert-AndroidReleaseSigning $repository '' '' '' '' } 'Missing signing selection accepted.'
    Reject { Assert-AndroidReleaseSigning $repository $keyPath $passwordPath 'existing-alias' 'not-a-hash' } 'Invalid certificate pin accepted.'
    Reject { Assert-AndroidReleaseSigning $repository (Join-Path $fixture 'absent.key') $passwordPath 'existing-alias' ('a' * 64) } 'Missing existing key accepted.'
    Reject { Assert-AndroidBundletool $keyPath } 'Unpinned bundletool accepted.'
    Write-Output "Android Play preflight checks passed: $checks"
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (!$resolved.StartsWith($temporary + [IO.Path]::DirectorySeparatorChar) -or ![IO.Path]::GetFileName($resolved).StartsWith('after-you-play-')) { throw 'Unexpected test cleanup directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
