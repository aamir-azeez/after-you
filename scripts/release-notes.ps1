# Prints a version's release notes from game/content/changelog.json, the same file
# the app shows under Settings > What's new.
#
#   ./scripts/release-notes.ps1                       # this version, GitHub text
#   ./scripts/release-notes.ps1 -Channel play         # paragraphs for Google Play builds
#   ./scripts/release-notes.ps1 -Sha256 <apk sha256>  # GitHub release body with its footer
#
# The version defaults to application/config/version in game/project.godot. With
# -Sha256 the GitHub text ends with the version, version code and APK checksum.
# Google Play's own "What's new" field is shorter (500 characters) and is written
# separately; -Channel play only lists what Play builds show in the app.
[CmdletBinding()]
param(
    [string]$Version = '',
    [ValidateSet('github', 'play', 'app_store')][string]$Channel = 'github',
    [string]$Sha256 = '',
    [int]$VersionCode = 0,
    [string]$OutFile = '',
    [string]$Repository = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'

function Get-ProjectVersion([string]$Repository) {
    $project = Get-Content -LiteralPath (Join-Path $Repository 'game/project.godot') -Encoding utf8
    foreach ($line in $project) {
        if ($line -match '^config/version="([^"]+)"$') { return $Matches[1] }
    }
    throw 'game/project.godot has no config/version.'
}

function Get-AndroidVersionCode([string]$Repository, [string]$Version) {
    $preset = Get-Content -LiteralPath (Join-Path $Repository 'game/export_presets.cfg') -Encoding utf8
    $android = $false
    $code = 0
    $name = ''
    foreach ($line in $preset) {
        if ($line -match '^\[preset\.\d+\]$') { $android = $false }
        if ($line -eq 'platform="Android"') { $android = $true }
        if ($android -and $line -match '^version/code=(\d+)$') { $code = [int]$Matches[1] }
        if ($android -and $line -match '^version/name="([^"]+)"$') { $name = $Matches[1] }
    }
    if ($name -ne $Version -or $code -le 0) {
        throw "The Android preset is $name ($code), not $Version. Pass -VersionCode for an older version."
    }
    return $code
}

# The paragraphs one build shows for a version, in order. App Store builds use a
# paragraph's ios_text when it has one, and skip it when that text is empty.
function Get-ReleaseParagraphs([string]$Repository, [string]$Version, [string]$Channel) {
    $path = Join-Path $Repository 'game/content/changelog.json'
    $data = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    if ($data.schema_version -ne 1) { throw "Unknown changelog schema in $path." }
    $entry = @($data.entries | Where-Object { $_.version -ceq $Version })
    if ($entry.Count -ne 1) { throw "game/content/changelog.json has no entry for $Version. Add it in the version bump commit." }
    $result = [Collections.Generic.List[string]]::new()
    foreach ($paragraph in $entry[0].paragraphs) {
        if ($null -ne $paragraph.channels -and @($paragraph.channels) -notcontains $Channel) { continue }
        $text = [string]$paragraph.text
        if ($Channel -eq 'app_store' -and $paragraph.PSObject.Properties.Name -contains 'ios_text') { $text = [string]$paragraph.ios_text }
        if ($text.Length -gt 0) { $result.Add($text) }
    }
    if ($result.Count -eq 0) { throw "The $Version entry has no paragraphs for $Channel." }
    return , $result.ToArray()
}

function Get-ReleaseNotes([string]$Repository, [string]$Version, [string]$Channel, [string]$Sha256, [int]$VersionCode) {
    if (!$Version) { $Version = Get-ProjectVersion $Repository }
    $body = (Get-ReleaseParagraphs $Repository $Version $Channel) -join "`n`n"
    if ($Sha256) {
        if ($Channel -ne 'github') { throw 'Only the GitHub release text carries the APK footer.' }
        if ($Sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Pass the APK SHA-256 as 64 lowercase hex characters.' }
        if ($VersionCode -le 0) { $VersionCode = Get-AndroidVersionCode $Repository $Version }
        $body += "`n`nVersion: $Version ($VersionCode).`nAPK: RevenueCat Test Store.`nSHA-256: $Sha256"
    }
    return $body
}

if ($MyInvocation.InvocationName -ne '.') {
    $notes = Get-ReleaseNotes $Repository $Version $Channel $Sha256 $VersionCode
    if ($OutFile) {
        [IO.File]::WriteAllText($OutFile, $notes + "`n", [Text.UTF8Encoding]::new($false))
    } else {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $notes
    }
}
