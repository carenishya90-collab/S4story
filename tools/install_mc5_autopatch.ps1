# Installs the automatic MC5 Python export patch for the current user.
# Run again only if Python 3.7 or its user site-packages were reinstalled.

$ErrorActionPreference = 'Stop'

$target = (& python -c "import site; print(site.getusersitepackages())").Trim()
if (-not $target) {
    throw "Could not determine Python 3.7 user site-packages directory."
}

New-Item -ItemType Directory -Path $target -Force | Out-Null

$sourcePatch = Join-Path $PSScriptRoot 'mc5_autopatch.py'
$sourceHook = Join-Path $PSScriptRoot 'usercustomize.py'
$targetPatch = Join-Path $target 'mc5_autopatch.py'
$targetHook = Join-Path $target 'usercustomize.py'

Copy-Item -LiteralPath $sourcePatch -Destination $targetPatch -Force

if (Test-Path -LiteralPath $targetHook) {
    $hookContent = Get-Content -LiteralPath $targetHook -Raw
    if ($hookContent -notmatch 'mc5_autopatch') {
        Add-Content -LiteralPath $targetHook -Value "`r`ntry:`r`n    import mc5_autopatch  # noqa: F401`r`nexcept Exception:`r`n    pass`r`n" -Encoding UTF8
    }
} else {
    Copy-Item -LiteralPath $sourceHook -Destination $targetHook -Force
}

Write-Host "MC5 autopatch installed to:"
Write-Host "  $target"
Write-Host ""
Write-Host "Test:"
& python -c "import mc5_autopatch; print('mc5_autopatch loaded')"
