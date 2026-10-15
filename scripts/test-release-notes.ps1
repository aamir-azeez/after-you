$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release-notes.ps1')
$repository = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('after-you-notes-' + [Guid]::NewGuid().ToString('N'))
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
try {
    # The real file: this version has GitHub notes and Play notes, and only the
    # GitHub text names the Test Store.
    $version = Get-ProjectVersion $repository
    $code = Get-AndroidVersionCode $repository $version
    $github = Get-ReleaseNotes $repository '' 'github' '' 0
    $play = Get-ReleaseNotes $repository $version 'play' '' 0
    $store = Get-ReleaseNotes $repository $version 'app_store' '' 0
    Assert-Check ($github.Contains('RevenueCat Test Store')) 'The GitHub text has the Test Store paragraph.'
    Assert-Check (!$play.Contains('Test Store') -and !$play.Contains('tester code')) 'The Play text leaves out the Test Store paragraph.'
    Assert-Check (!$store.Contains('Android') -and !$store.Contains('Google Play') -and !$store.Contains('APK')) 'The App Store text never names Android, Google Play or the APK.'
    Assert-Check ($github.StartsWith(($play -split "`n`n")[0])) 'Both texts start with the same first paragraph.'
    Assert-Check (!$github.Contains("`r") -and !$github.Contains("`n`n`n")) 'Paragraphs are separated by one blank line.'
    $sha = 'ab' * 32
    $body = Get-ReleaseNotes $repository $version 'github' $sha 0
    Assert-Check ($body -ceq ($github + "`n`nVersion: $version ($code).`nAPK: RevenueCat Test Store.`nSHA-256: $sha")) 'The GitHub release body ends with the version, code and checksum.'
    Reject { Get-ReleaseNotes $repository $version 'play' $sha 0 } 'The Play text never gets the APK footer.'
    Reject { Get-ReleaseNotes $repository $version 'github' 'ABC' 0 } 'A malformed checksum is refused.'
    Reject { Get-ReleaseNotes $repository '99.0.0' 'github' '' 0 } 'A version with no entry is refused.'
    # Every paragraph the script prints is a paragraph from the file, in order.
    $data = [IO.File]::ReadAllText((Join-Path $repository 'game/content/changelog.json'), [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    $all = @($data.entries[0].paragraphs | Where-Object { $null -eq $_.channels -or @($_.channels) -contains 'github' } | ForEach-Object { $_.text })
    Assert-Check (($github -split "`n`n") -join '|' -ceq ($all -join '|')) 'The GitHub text is every GitHub paragraph of the newest entry.'

    # A small repository: channels, iOS wording, the version code lookup.
    New-Item -ItemType Directory -Force (Join-Path $fixture 'game/content') | Out-Null
    $sample = @{ schema_version = 1; entries = @(
        @{ version = '1.2.3'; date = '2026-11-01'; paragraphs = @(
            @{ text = 'Both builds.' },
            @{ text = 'Android words.'; ios_text = 'iPhone words.' },
            @{ text = 'Hidden on iOS.'; ios_text = '' },
            @{ text = 'Play only.'; channels = @('play') },
            @{ text = 'GitHub only.'; channels = @('github') }) }) }
    [IO.File]::WriteAllText((Join-Path $fixture 'game/content/changelog.json'), ($sample | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $fixture 'game/project.godot'), "[application]`nconfig/version=`"1.2.3`"`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'game/export_presets.cfg'), "[preset.0]`nplatform=`"Android`"`n[preset.0.options]`nversion/code=77`nversion/name=`"1.2.3`"`n[preset.1]`nplatform=`"iOS`"`n[preset.1.options]`nversion/code=1`n")
    Assert-Check ((Get-ReleaseNotes $fixture '' 'github' '' 0) -ceq "Both builds.`n`nAndroid words.`n`nHidden on iOS.`n`nGitHub only.") 'GitHub keeps its own and shared paragraphs.'
    Assert-Check ((Get-ReleaseNotes $fixture '' 'play' '' 0) -ceq "Both builds.`n`nAndroid words.`n`nHidden on iOS.`n`nPlay only.") 'Play keeps its own and shared paragraphs.'
    Assert-Check ((Get-ReleaseNotes $fixture '' 'app_store' '' 0) -ceq "Both builds.`n`niPhone words.") 'The App Store text uses the iOS wording and drops empty ones.'
    Assert-Check ((Get-ReleaseNotes $fixture '' 'github' $sha 0).EndsWith("Version: 1.2.3 (77).`nAPK: RevenueCat Test Store.`nSHA-256: $sha")) 'The version code comes from the Android preset.'
    Assert-Check ((Get-ReleaseNotes $fixture '1.2.3' 'github' $sha 70).Contains('Version: 1.2.3 (70).')) 'An explicit version code wins.'
    # The command line writes UTF-8 without a byte order mark.
    $out = Join-Path $fixture 'notes.txt'
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'release-notes.ps1') -Repository $fixture -OutFile $out
    $bytes = [IO.File]::ReadAllBytes($out)
    Assert-Check ($bytes.Length -gt 3 -and $bytes[0] -ne 0xEF) 'The notes file has no byte order mark.'
    Assert-Check ([Text.Encoding]::UTF8.GetString($bytes) -ceq "Both builds.`n`nAndroid words.`n`nHidden on iOS.`n`nGitHub only.`n") 'The notes file holds the GitHub text.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
"Release notes checks: $checks passed"
