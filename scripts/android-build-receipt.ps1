Set-StrictMode -Version Latest

function Get-AndroidBuildSourceIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository)

    $repoPath = [IO.Path]::GetFullPath($Repository)
    $status = (& git -C $repoPath status --porcelain --untracked-files=all 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the source checkout.' }
    if ($status) { throw 'Release receipt requires a clean source checkout.' }

    $commit = ((& git -C $repoPath rev-parse HEAD 2>&1) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40,64}$') { throw 'Could not resolve the source commit.' }
    $tree = ((& git -C $repoPath rev-parse 'HEAD^{tree}' 2>&1) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $tree -notmatch '^[0-9a-f]{40,64}$') { throw 'Could not resolve the source tree.' }

    $archivePath = Join-Path ([IO.Path]::GetTempPath()) ('after-you-source-' + [Guid]::NewGuid().ToString('N') + '.tar')
    try {
        & git -C $repoPath archive --format=tar "--output=$archivePath" HEAD
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw 'Could not create the committed source archive for its digest.'
        }
        $sourceHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    } finally {
        if (Test-Path -LiteralPath $archivePath -PathType Leaf) { Remove-Item -LiteralPath $archivePath -Force }
    }

    return [pscustomobject]@{
        commit = $commit
        tree = $tree
        sha256 = $sourceHash
    }
}

function Get-AndroidBuildMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository)

    $game = Join-Path ([IO.Path]::GetFullPath($Repository)) 'game'
    $project = Get-Content -LiteralPath (Join-Path $game 'project.godot') -Raw
    $preset = Get-Content -LiteralPath (Join-Path $game 'export_presets.cfg') -Raw
    $version = [regex]::Match($project, '(?m)^config/version="([^"]+)"').Groups[1].Value
    $exportVersion = [regex]::Match($preset, '(?m)^version/name="([^"]+)"').Groups[1].Value
    $codeText = [regex]::Match($preset, '(?m)^version/code=(\d+)').Groups[1].Value
    $package = [regex]::Match($preset, '(?m)^package/unique_name="([^"]+)"').Groups[1].Value
    if ($version -notmatch '^\d+\.\d+\.\d+$' -or $version -cne $exportVersion -or
        !$codeText -or !$package -or $package -notmatch '^[A-Za-z0-9_.]+$') {
        throw 'Android release metadata is incomplete or inconsistent.'
    }
    return [pscustomobject]@{
        version = $version
        version_code = [int]$codeText
        package_name = $package
    }
}

function Write-AndroidReleaseBuildReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$MappingPath,
        [Parameter(Mandatory)][psobject]$SourceIdentity,
        [Parameter(Mandatory)][psobject]$BuildMetadata,
        [Parameter(Mandatory)][string]$PurchaseMode,
        [Parameter(Mandatory)][string]$SignerSha256
    )

    $artifact = [IO.Path]::GetFullPath($ArtifactPath)
    $mapping = [IO.Path]::GetFullPath($MappingPath)
    if (!(Test-Path -LiteralPath $artifact -PathType Leaf)) { throw 'Release artifact is missing.' }
    if ([IO.Path]::GetExtension($artifact) -notin @('.apk', '.aab')) { throw 'Release artifact must be an APK or AAB.' }
    if (!(Test-Path -LiteralPath $mapping -PathType Leaf) -or (Get-Item -LiteralPath $mapping).Length -lt 1) {
        throw 'The R8 mapping file is missing or empty.'
    }
    if ($SignerSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Release signer SHA-256 is invalid.' }
    if ($PurchaseMode -cne 'google_play') { throw 'Release artifacts must use the Google Play purchase configuration.' }
    if ($SourceIdentity.commit -notmatch '^[0-9a-f]{40,64}$' -or $SourceIdentity.tree -notmatch '^[0-9a-f]{40,64}$' -or
        $SourceIdentity.sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Committed source identity is invalid.' }

    $directory = [IO.Path]::GetDirectoryName($artifact)
    if ([IO.Path]::GetDirectoryName($mapping) -cne $directory) { throw 'The R8 mapping must be retained beside its artifact.' }
    $receiptPath = Join-Path $directory 'artifact-receipt.json'
    if (Test-Path -LiteralPath $receiptPath) { throw 'Artifact receipt already exists; refusing to replace it.' }

    $receipt = [ordered]@{
        schema_version = 1
        source_commit = $SourceIdentity.commit
        source_tree = $SourceIdentity.tree
        source_sha256 = $SourceIdentity.sha256
        version = $BuildMetadata.version
        version_code = [int]$BuildMetadata.version_code
        package_name = $BuildMetadata.package_name
        purchase_mode = $PurchaseMode
        signer_sha256 = $SignerSha256.ToLowerInvariant()
        artifact_file = [IO.Path]::GetFileName($artifact)
        artifact_sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        mapping_file = [IO.Path]::GetFileName($mapping)
        mapping_sha256 = (Get-FileHash -LiteralPath $mapping -Algorithm SHA256).Hash.ToLowerInvariant()
        verified_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    $json = $receipt | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($receiptPath, $json + "`n", [Text.UTF8Encoding]::new($false))
    return $receiptPath
}
