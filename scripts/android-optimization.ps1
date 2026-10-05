# Apply release-only optimization to the generated Godot Android project.
function Enable-AndroidReleaseOptimization {
    param([string]$Repository, [string]$AndroidBuild)
    $gradlePath = Join-Path $AndroidBuild 'build.gradle'
    $gradle = Get-Content -LiteralPath $gradlePath -Raw
    if ($gradle -notmatch 'com\.android\.application') {
        throw 'Expected the Godot Android application template.'
    }
    $include = "apply from: 'after-you-optimization.gradle'"
    if (!$gradle.Contains($include)) {
        [IO.File]::WriteAllText($gradlePath, $gradle.TrimEnd() + "`n`n$include`n")
    }
    $source = Join-Path $Repository 'native/android-release'
    foreach ($name in @('after-you-optimization.gradle', 'after-you-release.pro')) {
        Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $AndroidBuild $name) -Force
    }
    $raw = Join-Path $AndroidBuild 'res/raw'
    New-Item -ItemType Directory -Path $raw -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'after_you_keep.xml') -Destination (Join-Path $raw 'after_you_keep.xml') -Force
    $propertiesPath = Join-Path $AndroidBuild 'gradle.properties'
    $properties = Get-Content -LiteralPath $propertiesPath -Raw
    # Full mode is R8's default; a stale template override must not disable it.
    $properties = [regex]::Replace($properties, '(?m)^android\.enableR8\.fullMode\s*=.*\r?\n?', '')
    [IO.File]::WriteAllText($propertiesPath, $properties.TrimEnd() + "`n")
}
