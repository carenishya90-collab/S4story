param(
    [Parameter(Mandatory = $true)]
    [string]$BaseZip,

    [Parameter(Mandatory = $true)]
    [string]$PatchRoot,

    [string]$RepoRoot,

    [string]$OutputDir,

    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (!$RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (!$OutputDir) {
    $OutputDir = Join-Path $RepoRoot "dist"
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8NoBom([string]$Path, [string[]]$Lines) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

$manifestPath = Join-Path $RepoRoot "manifest\localization-manifest.json"
$packagingDir = Join-Path $RepoRoot "packaging"

if (!(Test-Path -LiteralPath $BaseZip)) { throw "Base ZIP not found: $BaseZip" }
if (!(Test-Path -LiteralPath $PatchRoot)) { throw "Patch root not found: $PatchRoot" }
if (!(Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
if (!(Test-Path -LiteralPath $packagingDir)) { throw "Packaging folder not found: $packagingDir" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$releaseName = "Mod-Constructor-v5.0-beta.15.1-RU"
$releaseZipName = "$releaseName.zip"

$baseHash = Get-Sha256 $BaseZip
if ($manifest.baseRelease.sha256 -and $baseHash -ne $manifest.baseRelease.sha256.ToLowerInvariant()) {
    throw "Base ZIP SHA256 mismatch. Expected $($manifest.baseRelease.sha256), got $baseHash"
}

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mc5-release-" + [Guid]::NewGuid().ToString("N"))
$baseExtract = Join-Path $stageRoot "base"
$releaseDir = Join-Path $stageRoot $releaseName

try {
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $baseExtract | Out-Null

    Write-Host "Extracting base release..."
    Expand-Archive -LiteralPath $BaseZip -DestinationPath $baseExtract -Force

    Move-Item -LiteralPath $baseExtract -Destination $releaseDir

    Write-Host "Copying $($manifest.modifiedFileCount) localized files..."
    $copied = 0
    foreach ($entry in $manifest.files) {
        $relative = $entry.path.Replace("/", "\")
        $src = Join-Path $PatchRoot $relative
        $dst = Join-Path $releaseDir $relative

        if (!(Test-Path -LiteralPath $src)) {
            throw "Localized file missing: $src"
        }

        $actual = Get-Sha256 $src
        if ($actual -ne $entry.sha256.ToLowerInvariant()) {
            throw "SHA256 mismatch for $($entry.path). Expected $($entry.sha256), got $actual"
        }

        $parent = Split-Path -Parent $dst
        if (!(Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }

        Copy-Item -LiteralPath $src -Destination $dst -Force
        $copied++
    }

    Write-Host "Copying release documentation..."
    Get-ChildItem -LiteralPath $packagingDir -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $releaseDir $_.Name) -Force
    }

    Write-Host "Writing BUILD_INFO.txt..."
    $buildInfo = New-Object System.Collections.Generic.List[string]
    $buildInfo.Add("The Sims 4 Mod Constructor V5 - Russian build")
    $buildInfo.Add("================================================")
    $buildInfo.Add("")
    $buildInfo.Add("Release:            $($manifest.release)")
    $buildInfo.Add("Prepared:           $($manifest.preparedAt)")
    $buildInfo.Add("Base release:       $($manifest.baseRelease.name)")
    $buildInfo.Add("Base release URL:   $($manifest.baseRelease.url)")
    $buildInfo.Add("Base release SHA256:$($manifest.baseRelease.sha256)")
    $buildInfo.Add("Upstream repo:      $($manifest.upstream.repository)")
    $buildInfo.Add("Upstream commit:    $($manifest.upstream.commit)")
    $buildInfo.Add("Upstream date:      $($manifest.upstream.commitDate)")
    $buildInfo.Add("Version.txt:        $($manifest.upstream.versionFile)")
    $buildInfo.Add("Modified files:     $($manifest.modifiedFileCount)")
    $buildInfo.Add("")
    $buildInfo.Add("This is a binary localization of the official release, not a full source build.")
    $buildInfo.Add("See NOTICE.txt and docs/SOURCE.md in the repository for details.")
    $buildInfo.Add("")
    $buildInfo.Add("Modified files and SHA256:")
    foreach ($entry in $manifest.files) {
        $buildInfo.Add("$($entry.sha256)  $($entry.path)")
    }
    Write-Utf8NoBom (Join-Path $releaseDir "BUILD_INFO.txt") $buildInfo.ToArray()

    Write-Host "Writing checksums.sha256..."
    $checksumPath = Join-Path $releaseDir "checksums.sha256"
    $checksumLines = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $releaseDir -Recurse -File |
        Where-Object { $_.Name -ne "checksums.sha256" } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($releaseDir.Length + 1).Replace("\", "/")
            $checksumLines.Add("$(Get-Sha256 $_.FullName)  $relative")
        }
    Write-Utf8NoBom $checksumPath $checksumLines.ToArray()

    if (!(Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    }

    $zipPath = Join-Path $OutputDir $releaseZipName
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Write-Host "Creating ZIP with forward-slash entry names..."
    $makeZip = Join-Path $RepoRoot "tools\make-zip.py"
    if (!(Test-Path -LiteralPath $makeZip)) { throw "make-zip.py not found: $makeZip" }
    & $Python $makeZip $releaseDir $zipPath
    if ($LASTEXITCODE -ne 0) { throw "make-zip.py failed with exit code $LASTEXITCODE" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipCheck = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $badEntries = @($zipCheck.Entries | Where-Object { $_.FullName -like "*\*" })
        if ($badEntries.Count -gt 0) {
            throw "ZIP contains backslash entry names: $($badEntries[0].FullName)"
        }
        $entryCount = $zipCheck.Entries.Count
    }
    finally {
        $zipCheck.Dispose()
    }

    $zipHash = Get-Sha256 $zipPath
    Write-Host ""
    Write-Host "Done."
    Write-Host "Release folder: $releaseDir"
    Write-Host "ZIP:            $zipPath"
    Write-Host "ZIP entries:    $entryCount"
    Write-Host "ZIP SHA256:     $zipHash"
    Write-Host "Files copied:   $copied"
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
