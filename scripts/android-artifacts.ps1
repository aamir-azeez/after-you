Set-StrictMode -Version Latest

function Resolve-AndroidCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$PrivateRoot,
        [Parameter(Mandatory)][string]$ArtifactName,
        [string]$OutputPath = ''
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
    if ([IO.Path]::GetExtension($resolved) -ne '.apk') { throw 'Build output must be an APK file.' }
    foreach ($path in @($resolved, ($resolved + '.sha256'))) {
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
