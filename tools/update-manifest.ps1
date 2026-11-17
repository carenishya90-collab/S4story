param(
    [Parameter(Mandatory = $true)]
    [string]$BaseZip,

    [Parameter(Mandatory = $true)]
    [string]$PatchRoot,

    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

if (!$RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$manifestPath = Join-Path $RepoRoot "manifest\localization-manifest.json"
if (!(Test-Path -LiteralPath $BaseZip)) { throw "Base ZIP not found: $BaseZip" }
if (!(Test-Path -LiteralPath $PatchRoot)) { throw "Patch root not found: $PatchRoot" }
if (!(Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mc5-manifest-" + [Guid]::NewGuid().ToString("N"))
$baseExtract = Join-Path $stageRoot "base"
$files = New-Object System.Collections.Generic.List[object]

try {
    New-Item -ItemType Directory -Force -Path $baseExtract | Out-Null
    Write-Host "Extracting base release..."
    Expand-Archive -LiteralPath $BaseZip -DestinationPath $baseExtract -Force

    $skipPattern = '\.original$|\.before_|\.zip$|\.log$|\.tmp$|\.bak$'
    $allPatchFiles = Get-ChildItem -LiteralPath $PatchRoot -Recurse -File | Where-Object {
        $_.Name -notmatch $skipPattern
    }

    foreach ($file in $allPatchFiles) {
        $relative = $file.FullName.Substring($PatchRoot.Length + 1)
        if ($relative -match '^Presets_Backup' -or $relative -eq 'README-RU.txt') {
            continue
        }
        $basePath = Join-Path $baseExtract $relative

        if (!(Test-Path -LiteralPath $basePath)) {
            Write-Warning "Extra file (not in base release): $relative"
            continue
        }

        $patchHash = Get-Sha256 $file.FullName
        $baseHash = Get-Sha256 $basePath
        if ($patchHash -ne $baseHash) {
            $files.Add([pscustomobject]@{
                path = $relative.Replace("\", "/")
                size = $file.Length
                sha256 = $patchHash
            })
        }
    }

    $baseHash = Get-Sha256 $BaseZip
    $manifest.baseRelease.size = (Get-Item -LiteralPath $BaseZip).Length
    $manifest.baseRelease.sha256 = $baseHash
    $manifest.modifiedFileCount = $files.Count
    $manifest.files = @($files | Sort-Object path)

    $json = $manifest | ConvertTo-Json -Depth 20
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifestPath, $json, $encoding)

    Write-Host "Updated $manifestPath"
    Write-Host "Modified files: $($files.Count)"
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
