# build_sidecar.ps1
# Builds pdf_service.py into a single standalone exe using PyInstaller.
# Output: pdf_service.exe  (placed in CT-Hub build output folder)
#
# Requirements: pip install pyinstaller pdfplumber flask
# Run from the repo root or from CT-Hub/pdf_service/.

param(
    [string]$OutDir = "$PSScriptRoot\..\..\CT-Hub\bin\Debug\net8.0-windows"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceDir = "$PSScriptRoot"
$script     = "$serviceDir\pdf_service.py"

Write-Host "Building pdf_service.exe ..."

pyinstaller `
    --onefile `
    --name pdf_service `
    --distpath "$OutDir" `
    --workpath "$serviceDir\_build_tmp" `
    --specpath "$serviceDir\_build_tmp" `
    --noconfirm `
    "$script"

if ($LASTEXITCODE -ne 0) {
    Write-Error "PyInstaller failed (exit $LASTEXITCODE)."
    exit $LASTEXITCODE
}

Write-Host "Done. Output: $OutDir\pdf_service.exe"
