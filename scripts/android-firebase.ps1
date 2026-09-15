# Firebase configuration is optional. These helpers never print its values.
function Get-AndroidFirebaseResources {
    param([string]$Repository, [string]$ConfigPath = '')
    if (!$ConfigPath) { return @{} }
    if (![IO.Path]::IsPathRooted($ConfigPath)) { throw 'FirebaseConfigPath must be an absolute private file path.' }
    $rootPath = [IO.Path]::GetFullPath($Repository).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath($ConfigPath)
    if ($fullPath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $fullPath -eq $rootPath) {
        throw 'Firebase Android configuration must stay outside the source repository.'
    }
    $ancestor = $fullPath
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Firebase configuration path must not traverse a reparse point.' }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    try {
        $file = Get-Item -LiteralPath $fullPath
        if ($file.PSIsContainer -or $file.Length -lt 1 -or $file.Length -gt 1048576) { throw 'Invalid file.' }
        $config = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
        $clients = @($config.client | Where-Object { $_.client_info.android_client_info.package_name -ceq 'com.aamirazeez.afteryou' })
        if ($clients.Count -ne 1) { throw 'Invalid client.' }
        $client = $clients[0]
        $keys = @($client.api_key)
        if ($keys.Count -ne 1) { throw 'Invalid keys.' }
        $values = @{
            google_app_id = [string]$client.client_info.mobilesdk_app_id
            google_api_key = [string]$keys[0].current_key
            gcm_defaultSenderId = [string]$config.project_info.project_number
            project_id = [string]$config.project_info.project_id
        }
        if ($values.google_app_id -cnotmatch '^1:[0-9]{6,20}:android:[A-Fa-f0-9]{16,64}$' -or
            $values.google_api_key -cnotmatch '^AIza[A-Za-z0-9_-]{35}$' -or
            $values.gcm_defaultSenderId -cnotmatch '^[0-9]{6,20}$' -or
            $values.project_id -cnotmatch '^[a-z][a-z0-9-]{4,62}$' -or
            $values.google_app_id.Split(':')[1] -cne $values.gcm_defaultSenderId) { throw 'Invalid values.' }
        return $values
    } catch { throw 'Invalid private Firebase Android configuration; values are withheld.' }
}

function Assert-AndroidFirebaseAar {
    param([string]$Path, [hashtable]$Expected)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    $names = @('google_app_id', 'google_api_key', 'gcm_defaultSenderId', 'project_id')
    $found = @{}
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notmatch '^res/values[^/]*/[^/]+\.xml$') { continue }
            $stream = $entry.Open()
            try {
                $xml = New-Object Xml.XmlDocument
                $xml.XmlResolver = $null
                $xml.Load($stream)
                foreach ($node in $xml.SelectNodes('/resources/string')) {
                    $name = $node.GetAttribute('name')
                    if ($name -cnotin $names) { continue }
                    if ($found.ContainsKey($name)) { throw 'Duplicate Firebase Android resource in AAR.' }
                    $found[$name] = $node.InnerText
                }
            } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    if ($found.Count -ne $Expected.Count) { throw 'Unexpected Firebase Android resource presence in AAR.' }
    foreach ($name in $Expected.Keys) {
        if (!$found.ContainsKey($name) -or $found[$name] -cne $Expected[$name]) { throw 'Firebase Android AAR resources do not match the explicit build configuration.' }
    }
}

function Assert-AndroidFirebaseApkResources {
    param([string]$ResourceDump, [hashtable]$Expected)
    foreach ($name in @('google_app_id', 'google_api_key', 'gcm_defaultSenderId', 'project_id')) {
        $pattern = '(?m)^\s+resource 0x[0-9a-fA-F]+ [^\r\n ]+:string/' + [regex]::Escape($name) + ':([^\r\n]*)\r?\n([^\r\n]*)'
        $matchesForName = [regex]::Matches($ResourceDump, $pattern)
        if (!$Expected.ContainsKey($name)) {
            if ($matchesForName.Count -ne 0) { throw 'Unconfigured APK contains stale Firebase Android resources.' }
            continue
        }
        if ($matchesForName.Count -ne 1) { throw 'Configured APK is missing a unique Firebase Android resource.' }
        $value = [regex]::Match($matchesForName[0].Groups[2].Value, '^\s+\(string(?:8|16)\) "([^"\r\n]*)"\s*$')
        if (!$value.Success -or $value.Groups[1].Value -cne $Expected[$name]) { throw 'Firebase Android APK resources do not match the explicit build configuration.' }
    }
}
