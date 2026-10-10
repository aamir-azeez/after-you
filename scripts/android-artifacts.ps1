Set-StrictMode -Version Latest

# Parses `aapt dump xmltree` text into nested elements with decoded attribute values.
function ConvertFrom-AndroidXmlTree {
    param([Parameter(Mandatory)][string]$Tree)
    $root = [pscustomobject]@{ Name = '#root'; Attributes = @{}; Children = [Collections.Generic.List[object]]::new(); Indent = -1 }
    $stack = [Collections.Generic.List[object]]::new()
    $stack.Add($root)
    foreach ($line in ($Tree -split "\r?\n")) {
        $element = [regex]::Match($line, '^(\s*)E: ([\w.-]+)')
        if ($element.Success) {
            $indent = $element.Groups[1].Value.Length
            while ($stack.Count -gt 1 -and $stack[$stack.Count - 1].Indent -ge $indent) { $stack.RemoveAt($stack.Count - 1) }
            $node = [pscustomobject]@{ Name = $element.Groups[2].Value; Attributes = @{}; Children = [Collections.Generic.List[object]]::new(); Indent = $indent }
            $stack[$stack.Count - 1].Children.Add($node)
            $stack.Add($node)
            continue
        }
        $attribute = [regex]::Match($line, '^(\s*)A: (?:[\w-]+:)?([\w-]+)(?:\(0x[0-9a-fA-F]+\))?=(.*)$')
        if (!$attribute.Success -or $stack.Count -lt 2) { continue }
        $raw = $attribute.Groups[3].Value
        $quoted = [regex]::Match($raw, '^"([^"]*)"')
        $boolean = [regex]::Match($raw, '^\(type 0x12\)0x([0-9a-fA-F]+)')
        $value = if ($quoted.Success) { $quoted.Groups[1].Value } elseif ($boolean.Success) { if ([Convert]::ToUInt32($boolean.Groups[1].Value, 16) -ne 0) { 'true' } else { 'false' } } else { $raw.Trim() }
        $stack[$stack.Count - 1].Attributes[$attribute.Groups[2].Value] = $value
    }
    return $root
}

function Get-AndroidXmlElements([object]$Node, [string]$Name) {
    foreach ($child in $Node.Children) {
        if ($child.Name -eq $Name) { $child }
        Get-AndroidXmlElements $child $Name
    }
}

# Invite links: exactly one exported, verified https filter for aamirazeez.com/after-you/link.
function Assert-AndroidInviteLinkManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManifestTree)
    $manifest = ConvertFrom-AndroidXmlTree -Tree $ManifestTree
    $targets = @(Get-AndroidXmlElements $manifest 'activity' | Where-Object { $_.Attributes['name'] -eq 'com.aamirazeez.afteryou.nativebridge.InviteLinkActivity' })
    if ($targets.Count -ne 1) { throw 'APK must declare exactly one invite-link Activity.' }
    $activity = $targets[0]
    if ($activity.Attributes['exported'] -ne 'true') { throw 'The invite-link Activity must be exported for verified App Links.' }
    $filters = @($activity.Children | Where-Object { $_.Name -eq 'intent-filter' })
    if ($filters.Count -ne 1 -or $filters[0].Attributes['autoVerify'] -ne 'true') { throw 'The invite-link Activity needs one autoVerify intent filter.' }
    $filter = $filters[0]
    $actions = @($filter.Children | Where-Object { $_.Name -eq 'action' } | ForEach-Object { $_.Attributes['name'] })
    $categories = @($filter.Children | Where-Object { $_.Name -eq 'category' } | ForEach-Object { $_.Attributes['name'] } | Sort-Object)
    $data = @($filter.Children | Where-Object { $_.Name -eq 'data' })
    if (($actions -join ',') -cne 'android.intent.action.VIEW' -or ($categories -join ',') -cne 'android.intent.category.BROWSABLE,android.intent.category.DEFAULT') {
        throw 'The invite-link filter must be a browsable VIEW filter.'
    }
    # Two exact paths (with and without the trailing slash); no prefix or pattern matching.
    $paths = @($data | ForEach-Object { $_.Attributes['path'] } | Sort-Object)
    $exactData = @($data | Where-Object { $_.Attributes.Count -eq 3 -and $_.Attributes['scheme'] -ceq 'https' -and $_.Attributes['host'] -ceq 'aamirazeez.com' -and $_.Attributes.ContainsKey('path') })
    if ($data.Count -ne 2 -or $exactData.Count -ne 2 -or ($paths -join ',') -cne '/after-you/link,/after-you/link/') {
        throw 'The invite-link filter must match only https://aamirazeez.com/after-you/link.'
    }
    # Trampolines run in their own empty-affinity task so the game's task never roots in them.
    foreach ($name in @('InviteLinkActivity', 'NotificationOpenActivity')) {
        $trampoline = @(Get-AndroidXmlElements $manifest 'activity' | Where-Object { $_.Attributes['name'] -eq ('com.aamirazeez.afteryou.nativebridge.' + $name) })
        if ($trampoline.Count -ne 1 -or !$trampoline[0].Attributes.ContainsKey('taskAffinity') -or $trampoline[0].Attributes['taskAffinity'] -cne '' -or $trampoline[0].Attributes['excludeFromRecents'] -ne 'true') {
            throw "$name must use an empty task affinity and stay out of Recents."
        }
    }
    # Component filters only; <queries> intents describe other apps and are not claims.
    $componentFilters = @(Get-AndroidXmlElements $manifest 'intent-filter')
    $verified = @($componentFilters | Where-Object { $_.Attributes.ContainsKey('autoVerify') })
    $webLinks = @($componentFilters | ForEach-Object { $_.Children } | Where-Object { $_.Name -eq 'data' -and ($_.Attributes['scheme'] -in @('http', 'https') -or $_.Attributes['host'] -like '*aamirazeez.com') })
    if ($verified.Count -ne 1 -or $webLinks.Count -ne 2) { throw 'No other component may claim web links or App Link verification.' }
}

function Resolve-AndroidCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$PrivateRoot,
        [Parameter(Mandatory)][string]$ArtifactName,
        [string]$OutputPath = '',
        [ValidateSet('APK', 'AAB')][string]$ExportFormat = 'APK'
    )
    $repositoryPath = [IO.Path]::GetFullPath($Repository).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $privatePath = [IO.Path]::GetFullPath($PrivateRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($privatePath -eq $repositoryPath -or $privatePath.StartsWith($repositoryPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The signing and delivery directory must be outside the repository.'
    }
    $candidates = Join-Path $privatePath 'deliverables/candidates'
    if (!$OutputPath) {
        $runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $OutputPath = Join-Path (Join-Path $candidates $runId) $ArtifactName
    }
    $resolved = [IO.Path]::GetFullPath($OutputPath)
    if (!$resolved.StartsWith($candidates + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Build output must be inside PrivateRoot/deliverables/candidates. Promote a tested candidate separately.'
    }
    if ([IO.Path]::GetExtension($resolved) -ne ('.' + $ExportFormat.ToLowerInvariant())) { throw "Build output must be an $ExportFormat file." }
    foreach ($path in @($resolved, ($resolved + '.sha256'), ($resolved + '.verification'))) {
        if (Test-Path -LiteralPath $path) { throw 'Candidate output already exists. Choose a new path; existing builds are never overwritten.' }
    }
    # A junction can defeat a lexical containment check, so reject redirected ancestors.
    $ancestor = [IO.Path]::GetDirectoryName($resolved)
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Build output needs ordinary directories, without symbolic links or junctions.'
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $resolved
}
