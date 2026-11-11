#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Destination,
    [string]$ArchiveDirectory,
    [switch]$Offline
)

$script:DesignSuiteRoot = $PSScriptRoot

function Get-SuiteChildPath {
    param([string]$Root, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)|:|^[\\/]') {
        throw "Invalid relative path: $Relative"
    }
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $child = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Invalid relative path: $Relative" }
    return $child
}

function Remove-SuiteScratch {
    param([string]$Path, [string]$Parent, [string]$NamePrefix)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $verified = Get-SuiteChildPath $Parent (Split-Path $fullPath -Leaf)
    if ($fullPath -ne $verified -or (Split-Path $fullPath -Leaf) -notlike "$NamePrefix*") { throw 'Unsafe cleanup target' }
    if (Test-Path -LiteralPath $fullPath) { Remove-Item -LiteralPath $fullPath -Recurse -Force }
}

function Assert-SuiteSkill {
    param([string]$Path, [string]$Name)
    $entry = Join-Path $Path 'SKILL.md'
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "Missing SKILL.md for $Name" }
    $text = [IO.File]::ReadAllText($entry, [Text.Encoding]::UTF8)
    if ($text -notmatch ('(?m)^name:\s*' + [regex]::Escape($Name) + '\s*$')) { throw "SKILL.md name does not match $Name" }
}

function Expand-SuiteArchive {
    param([string]$Archive, [string]$Target, [string[]]$IncludePaths)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $roots = @{}
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name -match '(^|/)\.\.(/|$)|:|^/' -or [string]::IsNullOrWhiteSpace($name)) { throw "Unsafe archive path: $name" }
            $null = Get-SuiteChildPath $Target $name
            $roots[$name.Split('/')[0]] = $true
        }
        if ($roots.Count -ne 1) { throw 'Expected one repository root in archive' }
        $rootName = @($roots.Keys)[0]
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.Length -le ($rootName.Length + 1)) { continue }
            $relative = $name.Substring($rootName.Length + 1).TrimEnd('/')
            $included = $false
            foreach ($includePath in $IncludePaths) {
                if ($relative -eq $includePath -or $relative.StartsWith(($includePath + '/'), [StringComparison]::Ordinal)) { $included = $true; break }
            }
            if (-not $included) { continue }
            if ((($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw "Symbolic link in selected archive path: $name" }
            $filePath = Get-SuiteChildPath $Target $name
            if ($name.EndsWith('/')) { [IO.Directory]::CreateDirectory($filePath) | Out-Null }
            else {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($filePath)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $filePath, $false)
            }
        }
    } finally { $zip.Dispose() }
    return (Get-SuiteChildPath $Target (@($roots.Keys)[0]))
}

function Install-DesignSuite {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Destination,
        [string]$ManifestPath = (Join-Path $script:DesignSuiteRoot 'design-suite.lock.json'),
        [string]$ArchiveDirectory,
        [switch]$Offline
    )
    $ErrorActionPreference = 'Stop'
    $existingRoots = @()
    if ([string]::IsNullOrWhiteSpace($Destination)) {
        $profilePath = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($profilePath)) { throw 'Specify -Destination; user profile could not be found.' }
        $Destination = Join-Path $profilePath '.agents/skills'
        $existingRoots += (Join-Path $profilePath '.codex/skills')
        if ($env:CODEX_HOME) { $existingRoots += (Join-Path $env:CODEX_HOME 'skills') }
    }
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    if ((Test-Path -LiteralPath $Destination) -and -not (Test-Path -LiteralPath $Destination -PathType Container)) { throw 'Destination is not a directory' }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw 'Unsupported manifest schema' }
    $sources = @{}
    foreach ($source in $manifest.sources) {
        if ($source.id -notmatch '^[a-z0-9-]+$' -or $sources.ContainsKey($source.id) -or $source.repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $source.ref -notmatch '^[0-9a-f]{40}$' -or $source.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid source in manifest' }
        $sources[$source.id] = $source
    }
    $skills = @([pscustomobject]@{ name='visual-art-director'; source='local'; path='skills/visual-art-director'; licensePath=$null }) + @($manifest.skills)
    $seen = @{}
    $pending = @()
    foreach ($skill in $skills) {
        if ($skill.name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or $skill.name.Length -gt 64 -or $seen.ContainsKey($skill.name)) { throw 'Invalid or duplicate skill name' }
        $seen[$skill.name] = $true
        if ($skill.source -ne 'local' -and -not $sources.ContainsKey($skill.source)) { throw 'Unknown skill source' }
        $null = Get-SuiteChildPath $script:DesignSuiteRoot $skill.path
        if ($skill.licensePath) { $null = Get-SuiteChildPath $script:DesignSuiteRoot $skill.licensePath }
        $existing = $null
        foreach ($root in (@($Destination) + $existingRoots)) {
            $candidate = Get-SuiteChildPath $root $skill.name
            if (Test-Path -LiteralPath $candidate) {
                if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "$candidate is not a directory" }
                $existing = $candidate
                break
            }
        }
        if ($existing) {
            [pscustomobject]@{ Name=$skill.name; Status='Skipped'; Path=$existing }
        } else { $pending += $skill }
    }
    if ($pending.Count -eq 0) { return }
    if (-not $PSCmdlet.ShouldProcess($Destination, ('Install missing skills: ' + (($pending.name) -join ', ')))) { return }

    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('my-skills-install-' + [guid]::NewGuid().ToString('N'))
    $destinationStage = $null
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    try {
        $sourceRoots = @{ local=$script:DesignSuiteRoot }
        foreach ($sourceId in @($pending.source | Where-Object { $_ -ne 'local' } | Select-Object -Unique)) {
            $source = $sources[$sourceId]
            $archiveName = "$sourceId-$($source.ref).zip"
            $archive = Join-Path $scratch $archiveName
            if ($ArchiveDirectory -and (Test-Path -LiteralPath (Join-Path $ArchiveDirectory $archiveName) -PathType Leaf)) {
                Copy-Item -LiteralPath (Join-Path $ArchiveDirectory $archiveName) -Destination $archive
            } else {
                if ($Offline) { throw "Offline archive missing: $archiveName" }
                for ($attempt = 1; $attempt -le 3; $attempt++) {
                    try {
                        Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$($source.repo)/zip/$($source.ref)" -OutFile $archive -TimeoutSec 45
                        break
                    } catch {
                        if ($attempt -eq 3) { throw }
                        Write-Warning "Download interrupted for $sourceId; retrying ($attempt/3)."
                        Start-Sleep -Seconds $attempt
                    }
                }
            }
            if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $source.sha256) { throw "Archive checksum mismatch: $sourceId" }
            $selectedSkills = @($pending | Where-Object { $_.source -eq $sourceId })
            $includePaths = @($selectedSkills.path) + @($selectedSkills.licensePath | Where-Object { $_ })
            $sourceRoots[$sourceId] = Expand-SuiteArchive $archive (Join-Path $scratch $sourceId) $includePaths
        }
        $readyRoot = Join-Path $scratch 'ready'
        [IO.Directory]::CreateDirectory($readyRoot) | Out-Null
        foreach ($skill in $pending) {
            $sourceRoot = $sourceRoots[$skill.source]
            $sourcePath = Get-SuiteChildPath $sourceRoot $skill.path
            Assert-SuiteSkill $sourcePath $skill.name
            $readyPath = Get-SuiteChildPath $readyRoot $skill.name
            Copy-Item -LiteralPath $sourcePath -Destination $readyPath -Recurse
            if ($skill.licensePath) {
                $license = Get-SuiteChildPath $sourceRoot $skill.licensePath
                if (-not (Test-Path -LiteralPath $license -PathType Leaf)) { throw "License missing for $($skill.name)" }
                $licenseTarget = Join-Path $readyPath (Split-Path $license -Leaf)
                if (-not (Test-Path -LiteralPath $licenseTarget)) { Copy-Item -LiteralPath $license -Destination $licenseTarget }
            }
        }
        # Finish all downloads and validation before touching the destination.
        [IO.Directory]::CreateDirectory($Destination) | Out-Null
        $destinationStage = Get-SuiteChildPath $Destination ('.my-skills-stage-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($destinationStage) | Out-Null
        foreach ($skill in $pending) {
            Copy-Item -LiteralPath (Get-SuiteChildPath $readyRoot $skill.name) -Destination (Get-SuiteChildPath $destinationStage $skill.name) -Recurse
        }
        foreach ($skill in $pending) {
            $target = Get-SuiteChildPath $Destination $skill.name
            if (Test-Path -LiteralPath $target) {
                Write-Warning "Destination appeared during installation; kept unchanged: $target"
                [pscustomobject]@{ Name=$skill.name; Status='Skipped'; Path=$target }
                continue
            }
            [IO.Directory]::Move((Get-SuiteChildPath $destinationStage $skill.name), $target)
            [pscustomobject]@{ Name=$skill.name; Status='Installed'; Path=$target }
        }
    } finally {
        if ($destinationStage) { Remove-SuiteScratch $destinationStage $Destination '.my-skills-stage-' }
        Remove-SuiteScratch $scratch ([IO.Path]::GetTempPath()) 'my-skills-install-'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-DesignSuite @PSBoundParameters
}
