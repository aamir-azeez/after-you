$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-optimization.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('after-you-optimization-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    $gradle = "plugins { id 'com.android.application' }`nandroid { buildTypes { debug {} release {} } }`n"
    [IO.File]::WriteAllText((Join-Path $fixture 'build.gradle'), $gradle)
    [IO.File]::WriteAllText((Join-Path $fixture 'gradle.properties'), "android.useAndroidX=true`nandroid.enableR8.fullMode=false`n")
    Enable-AndroidReleaseOptimization -Repository $repo -AndroidBuild $fixture
    $once = Get-Content -LiteralPath (Join-Path $fixture 'build.gradle') -Raw
    Enable-AndroidReleaseOptimization -Repository $repo -AndroidBuild $fixture
    $twice = Get-Content -LiteralPath (Join-Path $fixture 'build.gradle') -Raw
    if ($once -cne $twice -or !$twice.StartsWith($gradle)) { throw 'Repeated optimization setup changed the template.' }
    $properties = Get-Content -LiteralPath (Join-Path $fixture 'gradle.properties') -Raw
    if ($properties -match 'android.enableR8.fullMode' -or $properties -notmatch 'android.useAndroidX=true') { throw 'Invalid full-mode migration.' }
    foreach ($name in @('after-you-optimization.gradle','after-you-release.pro','res/raw/after_you_keep.xml')) {
        if (!(Test-Path -LiteralPath (Join-Path $fixture $name))) { throw "Missing release configuration: $name" }
    }
    [IO.File]::WriteAllText((Join-Path $fixture 'build.gradle'), "plugins { id 'com.android.library' }`n")
    $rejected = $false
    try { Enable-AndroidReleaseOptimization -Repository $repo -AndroidBuild $fixture } catch { $rejected = $true }
    if (!$rejected) { throw 'Library template incorrectly accepted as an application.' }
    Write-Output 'Release optimization setup: template preserved, repeatable, and rejects non-app projects.'
} finally {
    $resolved = (Resolve-Path -LiteralPath $fixture).Path
    $parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ((Split-Path -Parent $resolved) -ne $parent -or (Split-Path -Leaf $resolved) -notlike 'after-you-optimization-*') { throw 'Unexpected fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
