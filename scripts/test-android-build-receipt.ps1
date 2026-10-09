$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-build-receipt.ps1')

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('after-you-receipt-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $fixture 'source'
$candidate = Join-Path $fixture 'candidate'
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
    New-Item -ItemType Directory -Path (Join-Path $repo 'game'), $candidate -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $repo 'game/project.godot'), 'config/version="0.4.18"' + "`n")
    [IO.File]::WriteAllText((Join-Path $repo 'game/export_presets.cfg'), "version/name=`"0.4.18`"`nversion/code=48`npackage/unique_name=`"com.aamirazeez.afteryou`"`n")
    & git -C $repo init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize Git fixture.' }
    & git -C $repo config user.name 'Receipt Test'
    & git -C $repo config user.email 'receipt-test@example.invalid'
    & git -C $repo add game/project.godot game/export_presets.cfg
    & git -C $repo commit --quiet -m 'receipt fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Could not commit Git fixture.' }

    $source = Get-AndroidBuildSourceIdentity -Repository $repo
    $metadata = Get-AndroidBuildMetadata -Repository $repo
    Assert-Check ($source.commit -match '^[0-9a-f]{40,64}$' -and $source.tree -match '^[0-9a-f]{40,64}$' -and $source.sha256 -match '^[0-9a-f]{64}$') 'Source identity is incomplete.'
    Assert-Check ($metadata.version -ceq '0.4.18' -and $metadata.version_code -eq 48 -and $metadata.package_name -ceq 'com.aamirazeez.afteryou') 'Android release metadata was read incorrectly.'

    $artifact = Join-Path $candidate 'After You.aab'
    $mapping = Join-Path $candidate 'mapping.txt'
    [IO.File]::WriteAllBytes($artifact, [byte[]](1,2,3,4,5))
    [IO.File]::WriteAllText($mapping, 'R8 mapping fixture' + "`n")
    $receiptPath = Write-AndroidReleaseBuildReceipt -ArtifactPath $artifact -MappingPath $mapping `
        -SourceIdentity $source -BuildMetadata $metadata -PurchaseMode 'google_play' `
        -SignerSha256 ('a' * 64)
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    Assert-Check ($receipt.schema_version -eq 1 -and $receipt.source_commit -ceq $source.commit -and $receipt.source_tree -ceq $source.tree -and $receipt.source_sha256 -ceq $source.sha256) 'Receipt does not identify the committed source.'
    Assert-Check ($receipt.version -ceq '0.4.18' -and $receipt.version_code -eq 48 -and $receipt.package_name -ceq 'com.aamirazeez.afteryou' -and $receipt.purchase_mode -ceq 'google_play') 'Receipt omitted Android build identity.'
    Assert-Check ($receipt.signer_sha256 -ceq ('a' * 64) -and $receipt.artifact_sha256 -ceq (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()) 'Receipt signer or artifact digest is incorrect.'
    Assert-Check ($receipt.mapping_file -ceq 'mapping.txt' -and $receipt.mapping_sha256 -ceq (Get-FileHash -LiteralPath $mapping -Algorithm SHA256).Hash.ToLowerInvariant()) 'Receipt mapping identity is incorrect.'
    $receiptText = Get-Content -LiteralPath $receiptPath -Raw
    Assert-Check ($receiptText -match '"verified_utc"\s*:\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z"') 'Receipt verification time is not UTC.'
    Assert-Check ($receiptText -notmatch 'revenuecat_public_key|api_key|password|secret') 'Receipt unexpectedly contains secret/config fields.'
    Reject { Write-AndroidReleaseBuildReceipt -ArtifactPath $artifact -MappingPath $mapping -SourceIdentity $source -BuildMetadata $metadata -PurchaseMode 'google_play' -SignerSha256 ('a' * 64) } 'Receipt overwrite was accepted.'
    Reject { Write-AndroidReleaseBuildReceipt -ArtifactPath $artifact -MappingPath $mapping -SourceIdentity $source -BuildMetadata $metadata -PurchaseMode 'test_store' -SignerSha256 ('a' * 64) } 'Tester-store Release receipt was accepted.'
    Remove-Item -LiteralPath $mapping -Force
    Reject { Write-AndroidReleaseBuildReceipt -ArtifactPath $artifact -MappingPath $mapping -SourceIdentity $source -BuildMetadata $metadata -PurchaseMode 'google_play' -SignerSha256 ('a' * 64) } 'Missing mapping file was accepted.'

    [IO.File]::AppendAllText((Join-Path $repo 'game/project.godot'), '# dirty' + "`n")
    Reject { Get-AndroidBuildSourceIdentity -Repository $repo } 'Dirty source checkout was accepted for a release receipt.'

    $buildScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-android.ps1') -Raw
    Assert-Check ($buildScript.Contains("build/outputs/mapping/release/mapping.txt") -and $buildScript.Contains('Copy-Item -LiteralPath $r8MappingPath -Destination $candidateMapping') -and $buildScript.Contains('Write-AndroidReleaseBuildReceipt')) 'Release build does not retain the Gradle mapping and receipt.'
    Write-Output "Android build receipt checks passed: $checks"
} finally {
    if (Test-Path -LiteralPath $fixture) {
        $resolved = (Resolve-Path -LiteralPath $fixture).Path
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if (!$resolved.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'after-you-receipt-*') {
            throw 'Unexpected fixture cleanup path.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
