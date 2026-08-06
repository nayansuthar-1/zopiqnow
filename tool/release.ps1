# One command from "the change is committed" to "it is on Play".
#
#   pwsh tool/release.ps1 customer internal
#   pwsh tool/release.ps1 customer production
#
# Bumps the versionCode, builds the release bundle, uploads it, and commits the
# bump. In that order, and the order is the point: the version bump is committed
# only after Play has accepted the upload, so a failed build never leaves a
# versionCode burnt in git that no bundle on Play ever used.

param(
  [Parameter(Mandatory = $true)][ValidateSet('customer', 'vendor', 'rider')][string]$App,
  [Parameter(Mandatory = $true)][ValidateSet('internal', 'alpha', 'beta', 'production')][string]$Track,
  # Skip the upload — build and bump only. For checking a release build compiles
  # without spending a versionCode on Play.
  [switch]$NoUpload
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $repo "apps/$App/pubspec.yaml"

# Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a **BOM**, and a
# BOM at the top of pubspec.yaml is three bytes of rubbish in front of the first
# key. Written through .NET instead, which takes an encoding that has no BOM.
function Write-Pubspec([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText(
    $Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

# --- 1. Bump the versionCode -------------------------------------------------
# `version: 1.0.0+7` — the part after the + is what Play calls versionCode, and
# it must be higher than every code ever uploaded. The name before it is left
# alone: what a release is *called* is a decision, not an increment.
$content = Get-Content $pubspec -Raw
if ($content -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  throw "Could not read a 'version: x.y.z+n' line from $pubspec"
}
$name = $Matches[1]
$oldCode = [int]$Matches[2]
$newCode = $oldCode + 1

Write-Host "$App`: versionCode $oldCode -> $newCode (version $name)" -ForegroundColor Cyan
$content = $content -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $name+$newCode"
Write-Pubspec $pubspec $content

# --- 2. Build ----------------------------------------------------------------
Push-Location (Join-Path $repo "apps/$App")
try {
  Write-Host 'Building release bundle...' -ForegroundColor Cyan
  flutter build appbundle --release
  if ($LASTEXITCODE -ne 0) {
    # Put the version back. A failed build has not used this code, and leaving
    # it bumped means the next attempt silently skips a number.
    $content = $content -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $name+$oldCode"
    Write-Pubspec $pubspec $content
    throw 'Build failed. versionCode restored.'
  }
}
finally { Pop-Location }

if ($NoUpload) {
  Write-Host "Built. Not uploaded (-NoUpload)." -ForegroundColor Yellow
  exit 0
}

# --- 3. Upload ---------------------------------------------------------------
# The service-account path lives in .env, which is untracked. This repo is
# public; the key is upload access to the app.
$envFile = Join-Path $repo '.env'
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$') {
      [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim('"'))
    }
  }
}

Write-Host 'Uploading to Play...' -ForegroundColor Cyan
node (Join-Path $repo 'tool/play_upload.mjs') $App $Track
if ($LASTEXITCODE -ne 0) { throw 'Upload failed. The version bump is NOT committed.' }

# --- 4. Record it ------------------------------------------------------------
Push-Location $repo
try {
  git add "apps/$App/pubspec.yaml"
  git commit -m "chore($App): release $name+$newCode to $Track"
  git push
}
finally { Pop-Location }

Write-Host "Done. $App $name+$newCode is in review for $Track." -ForegroundColor Green
