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
    $argsForPath = @{ Repository = $repoFixture; PrivateRoot = $privateFixture; ArtifactName = 'After You - Debug.apk' }
    $first = Resolve-AndroidCandidatePath @argsForPath
    $second = Resolve-AndroidCandidatePath @argsForPath
    Assert-True ($first -ne $second) 'Repeated builds need distinct output paths.'
    Assert-True ($first.StartsWith((Join-Path $privateFixture 'deliverables/candidates') + [IO.Path]::DirectorySeparatorChar)) 'Default output escaped candidates.'
    Assert-True (!(Test-Path -LiteralPath $first)) 'Path planning must not create an APK.'
    $aliasPath = Join-Path $privateFixture 'deliverables/After You - Debug.apk'
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
    $bundle = Join-Path $privateFixture 'deliverables/candidates/play/app.aab'
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath $bundle } 'Default APK build accepted an AAB path.'
    Assert-True ((Resolve-AndroidCandidatePath @argsForPath -OutputPath $bundle -ExportFormat AAB) -eq $bundle) 'Explicit AAB candidate failed.'
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath (Join-Path $privateFixture 'deliverables/candidates/play/app.apk') -ExportFormat AAB } 'AAB build accepted an APK extension.'
    New-Item -ItemType Directory -Path ($bundle + '.verification') -Force | Out-Null
    Assert-Rejected { Resolve-AndroidCandidatePath @argsForPath -OutputPath $bundle -ExportFormat AAB } 'Existing bundle verification evidence accepted for overwrite.'
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
    # Invite-link App Link declaration, checked on synthetic `aapt dump xmltree` output.
    $exported = 'A: android:exported(0x01010010)=(type 0x12)0xffffffff'
    $inviteTree = @"
N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=2)
    E: queries (line=10)
      E: intent (line=11)
        E: data (line=12)
          A: android:scheme(0x01010027)="https" (Raw: "https")
    E: application (line=20)
      E: activity (line=30)
        A: android:name(0x01010003)="com.godot.game.GodotApp" (Raw: "com.godot.game.GodotApp")
        A: android:exported(0x01010010)=(type 0x12)0x0
      E: activity-alias (line=31)
        A: android:name(0x01010003)="com.godot.game.GodotAppLauncher" (Raw: "com.godot.game.GodotAppLauncher")
        $exported
        E: intent-filter (line=32)
          E: action (line=33)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
          E: category (line=34)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
      E: activity (line=40)
        A: android:theme(0x01010000)=@0x01030055
        A: android:name(0x01010003)="com.aamirazeez.afteryou.nativebridge.InviteLinkActivity" (Raw: "com.aamirazeez.afteryou.nativebridge.InviteLinkActivity")
        $exported
        A: android:excludeFromRecents(0x01010017)=(type 0x12)0xffffffff
        A: android:noHistory(0x0101022d)=(type 0x12)0xffffffff
        A: android:taskAffinity(0x01010012)="" (Raw: "")
        E: intent-filter (line=41)
          A: android:autoVerify(0x010104ee)=(type 0x12)0xffffffff
          E: action (line=42)
            A: android:name(0x01010003)="android.intent.action.VIEW" (Raw: "android.intent.action.VIEW")
          E: category (line=43)
            A: android:name(0x01010003)="android.intent.category.DEFAULT" (Raw: "android.intent.category.DEFAULT")
          E: category (line=44)
            A: android:name(0x01010003)="android.intent.category.BROWSABLE" (Raw: "android.intent.category.BROWSABLE")
          E: data (line=45)
            A: android:scheme(0x01010027)="https" (Raw: "https")
            A: android:host(0x01010028)="aamirazeez.com" (Raw: "aamirazeez.com")
            A: android:path(0x0101002a)="/after-you/link" (Raw: "/after-you/link")
          E: data (line=46)
            A: android:scheme(0x01010027)="https" (Raw: "https")
            A: android:host(0x01010028)="aamirazeez.com" (Raw: "aamirazeez.com")
            A: android:path(0x0101002a)="/after-you/link/" (Raw: "/after-you/link/")
      E: activity (line=50)
        A: android:name(0x01010003)="com.aamirazeez.afteryou.nativebridge.NotificationOpenActivity" (Raw: "com.aamirazeez.afteryou.nativebridge.NotificationOpenActivity")
        A: android:excludeFromRecents(0x01010017)=(type 0x12)0xffffffff
        A: android:taskAffinity(0x01010012)="" (Raw: "")
"@
    Assert-AndroidInviteLinkManifest -ManifestTree $inviteTree
    $checked++
    Assert-AndroidInviteLinkManifest -ManifestTree ($inviteTree -replace "`n", "`r`n")
    $checked++
    $affinity = 'A: android:taskAffinity(0x01010012)="" (Raw: "")'
    $brokenTrees = [ordered]@{
        'Missing invite Activity' = $inviteTree.Replace('nativebridge.InviteLinkActivity', 'nativebridge.OtherActivity')
        'Non-exported invite Activity' = $inviteTree.Replace("noHistory(0x0101022d)=(type 0x12)0xffffffff", "noHistory(0x0101022d)=(type 0x12)0xffffffff`n        A: android:exported(0x01010010)=(type 0x12)0x0")
        'Unverified filter' = $inviteTree.Replace('A: android:autoVerify(0x010104ee)=(type 0x12)0xffffffff', 'A: android:autoVerify(0x010104ee)=(type 0x12)0x0')
        # Twelve spaces select the invite filter's data, not the shallower <queries> entry.
        'Plain HTTP' = $inviteTree.Replace('            A: android:scheme(0x01010027)="https" (Raw: "https")', '            A: android:scheme(0x01010027)="http" (Raw: "http")')
        'Other host' = $inviteTree.Replace('"aamirazeez.com" (Raw: "aamirazeez.com")', '"www.aamirazeez.com" (Raw: "www.aamirazeez.com")')
        'Bare app path' = $inviteTree.Replace('"/after-you/link" (Raw: "/after-you/link")', '"/after-you" (Raw: "/after-you")')
        'Prefix path' = $inviteTree.Replace('A: android:path(0x0101002a)="/after-you/link" (Raw', 'A: android:pathPrefix(0x0101002b)="/after-you/link" (Raw')
        'Missing slash path' = $inviteTree.Replace('"/after-you/link/" (Raw: "/after-you/link/")', '"/after-you/link" (Raw: "/after-you/link")')
        'Invite task affinity' = $inviteTree.Remove($inviteTree.IndexOf($affinity), $affinity.Length)
        'Notification task affinity' = $inviteTree.Remove($inviteTree.LastIndexOf($affinity), $affinity.Length)
        'Extra data path' = $inviteTree.Replace('            A: android:path(0x0101002a)="/after-you/link" (Raw: "/after-you/link")', "            A: android:path(0x0101002a)=`"/after-you/link`" (Raw: `"/after-you/link`")`n            A: android:port(0x01010029)=`"8443`" (Raw: `"8443`")")
        'Extra category' = $inviteTree.Replace('android.intent.category.DEFAULT" (Raw', 'android.intent.category.LAUNCHER" (Raw')
        'Second web filter' = $inviteTree.Replace("            A: android:name(0x01010003)=`"android.intent.category.LAUNCHER`" (Raw: `"android.intent.category.LAUNCHER`")", "            A: android:name(0x01010003)=`"android.intent.category.LAUNCHER`" (Raw: `"android.intent.category.LAUNCHER`")`n          E: data (line=35)`n            A: android:scheme(0x01010027)=`"https`" (Raw: `"https`")")
    }
    foreach ($case in $brokenTrees.GetEnumerator()) {
        Assert-True ($case.Value -cne $inviteTree) ('Invite manifest fixture did not change: ' + $case.Key)
        Assert-Rejected { Assert-AndroidInviteLinkManifest -ManifestTree $case.Value } ('Invite manifest check accepted: ' + $case.Key)
    }
    Write-Output "Android candidate path checks passed: $checked"
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($resolvedFixture.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar) -and [IO.Path]::GetFileName($resolvedFixture).StartsWith('after-you-artifacts-')) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    } else { throw 'Refusing to clean an unexpected test directory.' }
}
