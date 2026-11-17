param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [switch]$SkipXml
)

$ErrorActionPreference = "Stop"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Add-Problem([string]$Message) {
    $script:problems.Add($Message) | Out-Null
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

$problems = New-Object System.Collections.Generic.List[string]
$releaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path

if (!(Test-Path -LiteralPath $releaseDir)) { throw "Release folder not found: $ReleaseDir" }
if (!(Test-Path -LiteralPath $ManifestPath)) { throw "Manifest not found: $ManifestPath" }

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$requiredFiles = @(
    "Constructor5.exe",
    "Constructor5.exe.config",
    "Constructor5.Base.dll",
    "Constructor5.Base.dll.config",
    "Constructor5.UI.dll",
    "Constructor5.Elements.dll",
    "Version.txt",
    "README-RU.txt",
    "NOTICE.txt",
    "CHANGELOG.txt",
    "BUILD_INFO.txt",
    "checksums.sha256"
)

$requiredDirs = @("Presets", "SimData", "TuningActions", "Icons", "Images", "Python Installer")

foreach ($name in $requiredFiles) {
    if (!(Test-Path -LiteralPath (Join-Path $releaseDir $name))) {
        Add-Problem "Required file missing: $name"
    }
}

foreach ($name in $requiredDirs) {
    if (!(Test-Path -LiteralPath (Join-Path $releaseDir $name) -PathType Container)) {
        Add-Problem "Required folder missing: $name"
    }
}

Write-Host "Checking for development artifacts..."
$forbidden = Get-ChildItem -LiteralPath $releaseDir -Recurse -File | Where-Object {
    $_.Name -match '\.original$' -or
    $_.Name -match '\.before_' -or
    $_.Name -match '^Presets_Backup' -or
    $_.Name -match '\.zip$' -or
    $_.Name -match '\.log$' -or
    $_.Name -match '\.tmp$' -or
    $_.Name -match '\.bak$' -or
    $_.Name -match '\.suo$' -or
    $_.Name -match '\.user$'
}
foreach ($file in $forbidden) {
    Add-Problem "Forbidden file in release: $($file.FullName.Substring($releaseDir.Length + 1))"
}

Write-Host "Checking manifest files..."
foreach ($entry in $manifest.files) {
    $relative = $entry.path.Replace("/", "\")
    $path = Join-Path $releaseDir $relative
    if (!(Test-Path -LiteralPath $path)) {
        Add-Problem "Manifest file missing: $($entry.path)"
        continue
    }
    $actual = Get-Sha256 $path
    if ($actual -ne $entry.sha256.ToLowerInvariant()) {
        Add-Problem "SHA256 mismatch: $($entry.path)"
    }
}

Write-Host "Checking checksums.sha256..."
$checksumPath = Join-Path $releaseDir "checksums.sha256"
if (Test-Path -LiteralPath $checksumPath) {
    $checksumCount = 0
    foreach ($line in Get-Content -LiteralPath $checksumPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\s{2,}', 2
        if ($parts.Count -ne 2) {
            Add-Problem "Bad checksum line: $line"
            continue
        }
        $expected = $parts[0].ToLowerInvariant()
        $relative = $parts[1].Replace("/", "\")
        $path = Join-Path $releaseDir $relative
        if (!(Test-Path -LiteralPath $path)) {
            Add-Problem "Checksum file missing: $relative"
            continue
        }
        $actual = Get-Sha256 $path
        if ($actual -ne $expected) {
            Add-Problem "Checksum mismatch: $relative"
        }
        $checksumCount++
    }
    if ($checksumCount -lt 1) {
        Add-Problem "checksums.sha256 is empty"
    }
}

Write-Host "Checking for local paths in text files..."
$textPattern = '\.(txt|md|json|xml|config|ps1|csproj|sln)$'
$localPathPatterns = @(
    'C:\\Users\\User',
    'C:\\Users\\[^\\]+\\AppData\\Local\\Temp\\opencode',
    'Downloads\\Mod-Constructor-v5\.0-beta\.15\.1-RU'
)
$textFiles = Get-ChildItem -LiteralPath $releaseDir -Recurse -File | Where-Object { $_.Name -match $textPattern }
foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { continue }
    foreach ($pattern in $localPathPatterns) {
        if ($content -match $pattern) {
            Add-Problem "Local path found in $($file.FullName.Substring($releaseDir.Length + 1)): $pattern"
        }
    }
}

if (!$SkipXml) {
    Write-Host "Parsing Presets XML..."
    $xmlCount = 0
    $xmlErrors = 0
    Get-ChildItem -LiteralPath (Join-Path $releaseDir "Presets") -Recurse -File -Filter *.xml | ForEach-Object {
        $xmlCount++
        try {
            $doc = New-Object System.Xml.XmlDocument
            $doc.Load($_.FullName)
        }
        catch {
            $xmlErrors++
            Add-Problem "XML parse error: $($_.FullName.Substring($releaseDir.Length + 1)): $($_.Exception.Message)"
        }
    }
    Write-Host "Presets XML checked: $xmlCount, errors: $xmlErrors"
}

$modifiedCount = (Get-ChildItem -LiteralPath $releaseDir -Recurse -File | Measure-Object).Count
Write-Host ""
Write-Host "Release files: $modifiedCount"
Write-Host "Problems: $($problems.Count)"

if ($problems.Count -gt 0) {
    Write-Host "RELEASE CHECK FAILED" -ForegroundColor Red
    exit 1
}

Write-Host "RELEASE CHECK PASSED" -ForegroundColor Green
