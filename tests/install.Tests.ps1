$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'install.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('my-skills-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$checks = 0
function Assert-True($Condition, $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Fails([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-True ($null -ne $caught -and $caught.ToString() -match $Pattern) "Expected error matching $Pattern; got $caught"
}
function Write-Utf8($Path, $Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Fixture($Label, [switch]$MissingSkill, [switch]$Traversal, [switch]$LinkedSkill) {
    $root = Join-Path $testRoot $Label
    $cache = Join-Path $root 'cache'
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    $source = Join-Path $root 'source'
    Write-Utf8 (Join-Path $source 'root/LICENSE') 'fixture license'
    if (-not $MissingSkill) { Write-Utf8 (Join-Path $source 'root/skills/companion/SKILL.md') "---`nname: companion`ndescription: fixture`n---`nfixture" }
    Write-Utf8 (Join-Path $source 'root/skills/companion/assets/example.txt') 'resource'
    $ref = '1111111111111111111111111111111111111111'
    $zipPath = Join-Path $cache "fixture-$ref.zip"
    [IO.Compression.ZipFile]::CreateFromDirectory($source, $zipPath)
    $zip = [IO.Compression.ZipFile]::Open($zipPath, 'Update')
    try {
        $link = $zip.CreateEntry('root/unrelated-link')
        $link.ExternalAttributes = -1577123840
        if ($Traversal) { $zip.CreateEntry('../escaped.txt') | Out-Null }
        if ($LinkedSkill) {
            $selectedLink = $zip.CreateEntry('root/skills/companion/link')
            $selectedLink.ExternalAttributes = -1577123840
        }
    } finally { $zip.Dispose() }
    $manifest = @{
        schemaVersion = 1
        sources = @(@{ id='fixture'; repo='example/fixture'; ref=$ref; sha256=(Get-FileHash $zipPath -Algorithm SHA256).Hash })
        skills = @(@{ name='companion'; source='fixture'; path='skills/companion'; licensePath='LICENSE' })
    }
    $manifestPath = Join-Path $root 'lock.json'
    Write-Utf8 $manifestPath ($manifest | ConvertTo-Json -Depth 10)
    return @{ Root=$root; Cache=$cache; Manifest=$manifestPath; Zip=$zipPath }
}
try {
    $fixture = New-Fixture 'clean'
    $dest = Join-Path $fixture.Root 'installed'
    Install-DesignSuite -Destination $dest -ManifestPath $fixture.Manifest -ArchiveDirectory $fixture.Cache -Offline -WhatIf | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $dest)) 'Preview created the destination'
    $result = @(Install-DesignSuite -Destination $dest -ManifestPath $fixture.Manifest -ArchiveDirectory $fixture.Cache -Offline)
    Assert-True (@($result | Where-Object Status -eq 'Installed').Count -eq 2) 'Expected main skill and fixture companion'
    Assert-True (Test-Path (Join-Path $dest 'companion/assets/example.txt')) 'Supporting resources missing'
    Assert-True (([IO.File]::ReadAllText((Join-Path $dest 'companion/LICENSE'))) -eq 'fixture license') 'Root license not preserved'
    Write-Utf8 (Join-Path $dest 'companion/keep.txt') 'user changes'
    $again = @(Install-DesignSuite -Destination $dest -ManifestPath $fixture.Manifest -ArchiveDirectory (Join-Path $fixture.Root 'absent-cache') -Offline)
    Assert-True (@($again | Where-Object Status -eq 'Skipped').Count -eq 2) 'Repeat installation did not skip existing skills'
    Assert-True (([IO.File]::ReadAllText((Join-Path $dest 'companion/keep.txt'))) -eq 'user changes') 'Existing skill was overwritten'

    Push-Location -LiteralPath $fixture.Root
    try {
        Install-DesignSuite -Destination './relative-installed' -ManifestPath $fixture.Manifest -ArchiveDirectory $fixture.Cache -Offline | Out-Null
    } finally { Pop-Location }
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Root 'relative-installed/companion/SKILL.md')) 'Relative destination ignored the current PowerShell location'

    $tampered = New-Fixture 'tampered'
    [IO.File]::AppendAllText($tampered.Zip, 'changed')
    $target = Join-Path $tampered.Root 'installed'
    Assert-Fails { Install-DesignSuite -Destination $target -ManifestPath $tampered.Manifest -ArchiveDirectory $tampered.Cache -Offline } 'checksum'
    Assert-True (-not (Test-Path $target)) 'Checksum failure wrote to target'

    $missing = New-Fixture 'missing' -MissingSkill
    $target = Join-Path $missing.Root 'installed'
    Assert-Fails { Install-DesignSuite -Destination $target -ManifestPath $missing.Manifest -ArchiveDirectory $missing.Cache -Offline } 'SKILL.md'
    Assert-True (-not (Test-Path $target)) 'Missing skill wrote to target'

    $traversal = New-Fixture 'traversal' -Traversal
    $target = Join-Path $traversal.Root 'installed'
    Assert-Fails { Install-DesignSuite -Destination $target -ManifestPath $traversal.Manifest -ArchiveDirectory $traversal.Cache -Offline } 'archive path'
    Assert-True (-not (Test-Path $target)) 'Unsafe archive wrote to target'

    $linked = New-Fixture 'linked-skill' -LinkedSkill
    $target = Join-Path $linked.Root 'installed'
    Assert-Fails { Install-DesignSuite -Destination $target -ManifestPath $linked.Manifest -ArchiveDirectory $linked.Cache -Offline } 'Symbolic link in selected'
    Assert-True (-not (Test-Path $target)) 'Selected symbolic link wrote to target'

    $collision = New-Fixture 'collision'
    $target = Join-Path $collision.Root 'installed'
    Write-Utf8 (Join-Path $target 'companion') 'existing file'
    Assert-Fails { Install-DesignSuite -Destination $target -ManifestPath $collision.Manifest -ArchiveDirectory $collision.Cache -Offline } 'not a directory'
    Assert-True (-not (Test-Path (Join-Path $target 'visual-art-director'))) 'Collision partially installed main skill'

    $invalid = New-Fixture 'invalid-path'
    $manifest = Get-Content $invalid.Manifest -Raw | ConvertFrom-Json
    $manifest.skills[0].path = '../outside'
    Write-Utf8 $invalid.Manifest ($manifest | ConvertTo-Json -Depth 10)
    Assert-Fails { Install-DesignSuite -Destination (Join-Path $invalid.Root 'installed') -ManifestPath $invalid.Manifest -Offline } 'relative path'
    Write-Output "PASS: $checks assertions (preview, resources, licenses, repeat install, no overwrite, checksum, missing skill, traversal, collision, invalid manifest)."
} finally {
    $fullTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullTestRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $fullTestRoot -Leaf) -notlike 'my-skills-tests-*') { throw 'Unsafe test cleanup target' }
    Remove-Item -LiteralPath $fullTestRoot -Recurse -Force
}
