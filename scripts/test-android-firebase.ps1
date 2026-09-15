$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-firebase.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('after-you-firebase-' + [Guid]::NewGuid().ToString('N'))
$repoFixture = Join-Path $fixture 'source'
$privateFixture = Join-Path $fixture 'private'
$checks = 0
function Assert-True([bool]$Value, [string]$Message) {
    $script:checks++
    if (!$Value) { throw $Message }
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
}
function Write-SyntheticAar([string]$Path, [hashtable]$Values) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $zip.CreateEntry('res/values/values.xml')
        $writer = New-Object IO.StreamWriter($entry.Open())
        try {
            $text = '<resources>'
            foreach ($name in $Values.Keys) { $text += '<string name="' + $name + '">' + $Values[$name] + '</string>' }
            $writer.Write($text + '</resources>')
        } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
}
try {
    New-Item -ItemType Directory -Path $repoFixture, $privateFixture -Force | Out-Null
    $expected = @{google_app_id='1:123456789012:android:0123456789abcdef'; google_api_key=('AIza' + ('x' * 35)); gcm_defaultSenderId='123456789012'; project_id='synthetic-project'}
    $config = @{project_info=@{project_number=$expected.gcm_defaultSenderId;project_id=$expected.project_id};client=@(@{client_info=@{mobilesdk_app_id=$expected.google_app_id;android_client_info=@{package_name='com.aamirazeez.afteryou'}};api_key=@(@{current_key=$expected.google_api_key})})}
    $configPath = Join-Path $privateFixture 'google-services.json'
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath
    Assert-True ((Get-AndroidFirebaseResources -Repository $repoFixture).Count -eq 0) 'Default build should be unconfigured.'
    $read = Get-AndroidFirebaseResources -Repository $repoFixture -ConfigPath $configPath
    Assert-True ($read.Count -eq 4 -and $read.google_app_id -ceq $expected.google_app_id) 'Valid private public config was not accepted.'
    Assert-Rejected { Get-AndroidFirebaseResources -Repository $repoFixture -ConfigPath 'google-services.json' } 'Relative config accepted.'
    $sourceConfig = Join-Path $repoFixture 'google-services.json'
    Copy-Item -LiteralPath $configPath -Destination $sourceConfig
    Assert-Rejected { Get-AndroidFirebaseResources -Repository $repoFixture -ConfigPath $sourceConfig } 'Source-contained config accepted.'
    $config.client[0].client_info.android_client_info.package_name = 'wrong.package'
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath
    Assert-Rejected { Get-AndroidFirebaseResources -Repository $repoFixture -ConfigPath $configPath } 'Mismatched Android client accepted.'
    $configuredAar = Join-Path $fixture 'configured.aar'
    $emptyAar = Join-Path $fixture 'empty.aar'
    Write-SyntheticAar $configuredAar $expected
    Write-SyntheticAar $emptyAar @{}
    Assert-AndroidFirebaseAar -Path $configuredAar -Expected $expected
    Assert-True $true 'Configured AAR rejected.'
    Assert-AndroidFirebaseAar -Path $emptyAar -Expected @{}
    Assert-True $true 'Unconfigured AAR rejected.'
    Assert-Rejected { Assert-AndroidFirebaseAar -Path $configuredAar -Expected @{} } 'Stale configured AAR accepted.'
    Assert-Rejected { Assert-AndroidFirebaseAar -Path $emptyAar -Expected $expected } 'Missing AAR config accepted.'
    $dump = ''
    foreach ($name in $expected.Keys) { $dump += "    resource 0x7f010001 com.aamirazeez.afteryou:string/${name}: t=0x03`n      (string8) `"$($expected[$name])`"`n" }
    Assert-AndroidFirebaseApkResources -ResourceDump $dump -Expected $expected
    Assert-True $true 'Configured APK resource dump rejected.'
    Assert-AndroidFirebaseApkResources -ResourceDump '' -Expected @{}
    Assert-True $true 'Unconfigured APK dump rejected.'
    Assert-Rejected { Assert-AndroidFirebaseApkResources -ResourceDump $dump -Expected @{} } 'Stale configured APK accepted.'
    Assert-Rejected { Assert-AndroidFirebaseApkResources -ResourceDump '' -Expected $expected } 'Missing configured APK values accepted.'
    Assert-Rejected { Assert-AndroidFirebaseApkResources -ResourceDump ($dump + $dump) -Expected $expected } 'Duplicate APK values accepted.'
    Assert-Rejected { Assert-AndroidFirebaseApkResources -ResourceDump ($dump.Replace('synthetic-project','other-project')) -Expected $expected } 'Mismatched APK values accepted.'
    Write-Output "Android Firebase artifact checks: $checks passed."
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (!$resolved.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar) -or ![IO.Path]::GetFileName($resolved).StartsWith('after-you-firebase-')) { throw 'Unsafe fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
