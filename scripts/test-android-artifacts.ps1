$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-artifacts.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('after-you-artifacts-' + [Guid]::NewGuid().ToString('N'))
$repoFixture = Join-Path $fixture 'source'
$privateFixture = Join-Path $fixture 'private'
$checked = 0
function Assert-True([bool]$Value, [string]$Message) {
    if (!$Value) { throw $Message }
    $script:checked++
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
}
try {
    New-Item -ItemType Directory -Path $repoFixture, $privateFixture -Force | Out-Null
    $argsForPath = @{ Repository = $repoFixture; PrivateRoot = $privateFixture; ArtifactName = 'After You - Test Store.apk' }
    $first = Resolve-AndroidCandidatePath @argsForPath
    $second = Resolve-AndroidCandidatePath @argsForPath
    Assert-True ($first -ne $second) 'Repeated builds need distinct output paths.'
    Assert-True ($first.StartsWith((Join-Path $privateFixture 'deliverables/candidates') + [IO.Path]::DirectorySeparatorChar)) 'Default output escaped candidates.'
    Assert-True (!(Test-Path -LiteralPath $first)) 'Path planning must not create an APK.'
    $aliasPath = Join-Path $privateFixture 'deliverables/After You - Test Store.apk'
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($aliasPath)) -Force | Out-Null
    [IO.File]::WriteAllText($aliasPath, 'previous verified build')
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath $aliasPath } 'A build must not overwrite the verified alias.'
    Assert-True ([IO.File]::ReadAllText($aliasPath) -eq 'previous verified build') 'Verified alias changed.'
    $preflightError = ''
    try {
        & (Join-Path $PSScriptRoot 'build-android.ps1') -PrivateRoot $privateFixture -OutputPath $aliasPath -GodotExe (Join-Path $fixture 'missing-godot.exe') | Out-Null
    } catch { $preflightError = $_.Exception.Message }
    Assert-True ($preflightError -like 'Build output must be inside*') 'Build entry point must reject the delivery alias before loading tools or signing keys.'
    Assert-True (!(Test-Path -LiteralPath (Join-Path $privateFixture 'signing'))) 'Rejected build touched the signing directory.'
    $custom = Join-Path $privateFixture 'deliverables/candidates/review/My build.apk'
    Assert-True ((Resolve-AndroidCandidatePath @argsForPath -OutputPath $custom) -eq [IO.Path]::GetFullPath($custom)) 'Explicit candidate path changed.'
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($custom)) -Force | Out-Null
    [IO.File]::WriteAllText($custom + '.sha256', 'existing receipt')
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath $custom } 'Existing checksum must prevent accidental reuse.'
    [IO.File]::WriteAllText($custom, 'incomplete export')
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath $custom } 'Failed exports must not be overwritten.'
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath (Join-Path $privateFixture 'deliverables/candidates/../../escape.apk') } 'Traversal escaped candidates.'
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath (Join-Path $privateFixture 'deliverables/candidates-other/new.apk') } 'Sibling prefix passed containment.'
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath (Join-Path $privateFixture 'deliverables/candidates/new.txt') } 'Non-APK output accepted.'
    Assert-Rejected { Resolve-AndroidCandidatePath -Repository $repoFixture -PrivateRoot (Join-Path $repoFixture 'private') -ArtifactName 'app.apk' } 'Private signing directory accepted inside source.'
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath (Join-Path $repoFixture 'app.apk') } 'Output accepted inside source.'
    $blocker = Join-Path $privateFixture 'deliverables/candidates/file-parent'
    [IO.File]::WriteAllText($blocker, 'not a directory')
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath (Join-Path $blocker 'app.apk') } 'File ancestor accepted.'
    if ($env:OS -eq 'Windows_NT') {
        $junction = Join-Path $privateFixture 'deliverables/candidates/redirect'
        New-Item -ItemType Junction -Path $junction -Target $repoFixture | Out-Null
        try {
            Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath (Join-Path $junction 'app.apk') } 'Junction output accepted.'
        } finally {
            # Remove only the link, never recurse through its source target.
            [IO.Directory]::Delete($junction)
        }
    }
    Write-Output "Android candidate path checks passed: $checked"
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($resolvedFixture.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar) -and [IO.Path]::GetFileName($resolvedFixture).StartsWith('after-you-artifacts-')) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    } else { throw 'Refusing to clean an unexpected test directory.' }
}
