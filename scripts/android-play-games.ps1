# Play Games Services build checks. The project id is public (it ships in every APK); these helpers
# still never print it. An empty id means Play Games stays off in that build.
function Get-AndroidPlayGamesAppId {
    param([string]$AppId = '')
    if ($AppId -and $AppId -cnotmatch '^[0-9]{6,20}$') { throw 'PlayGamesAppId must be the numeric Play Games Services project id.' }
    return $AppId
}

# Manifest rules, checked on `aapt dump xmltree` output:
# - the APP_ID meta-data is present and points at a resource (the generated game_services_project_id);
# - PlayGamesInitProvider is gone, so the SDK never starts with the process (the game starts it later).
function Assert-AndroidPlayGamesManifest {
    param([string]$ManifestTree)
    $tree = $ManifestTree -replace "`r`n", "`n"
    if ($tree -match 'com\.google\.android\.gms\.games\.provider\.PlayGamesInitProvider') { throw 'APK still starts Play Games with the process (PlayGamesInitProvider present).' }
    $metaPattern = '(?m)^(\s*)E: meta-data[^\n]*\n(?:\1\s+A: [^\n]*\n)*?\1\s+A: android:name\(0x01010003\)="com\.google\.android\.gms\.games\.APP_ID"[^\n]*\n(?:\1\s+A: [^\n]*\n)*?\1\s+A: android:value\(0x01010024\)=@0x[0-9a-fA-F]{8}\s*$'
    $metas = [regex]::Matches($tree, $metaPattern)
    if ($metas.Count -ne 1) { throw 'APK must declare the Play Games APP_ID exactly once, as a resource reference.' }
}

# The generated string resource holds exactly the build's id ("" when unconfigured).
function Assert-AndroidPlayGamesResource {
    param([string]$ResourceDump, [string]$Expected = '')
    $pattern = '(?m)^\s+resource 0x[0-9a-fA-F]+ [^\r\n ]+:string/game_services_project_id:[^\r\n]*\r?\n([^\r\n]*)'
    $found = [regex]::Matches($ResourceDump, $pattern)
    if ($found.Count -ne 1) { throw 'APK is missing a unique Play Games project id resource.' }
    $value = [regex]::Match($found[0].Groups[1].Value, '^\s+\(string(?:8|16)\) "([^"\r\n]*)"\s*$')
    if (!$value.Success -or $value.Groups[1].Value -cne $Expected) { throw 'Play Games project id resource does not match the explicit build configuration.' }
}
