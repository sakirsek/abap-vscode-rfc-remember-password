#requires -Version 5.1
<#
.SYNOPSIS
  Adds optional RFC password persistence ("Remember me") on top of the native
  RFC logon in SAP's "ABAP Development Tools for VS Code" extension (1.0.1+).

.DESCRIPTION
  Pure text surgery on two files inside the installed extension:
    dist/_bundle/extension.js  and  package.json
  It touches NO jar, decompiles nothing, and needs no JDK/Java. The exact
  find/replace payloads live in patch/payloads.json next to this script.

  Safety (mirrors the companion abap-vscode-rfc-logon project):
    - Guard: refuses to run if the marker command id is already present
      (so a second run is a no-op, never a double patch).
    - Asserts every find anchor occurs EXACTLY once before writing anything.
    - On ANY mismatch it changes nothing (safe stop).
    - No backups, no revert. Undo = reinstall/update the extension.

.PARAMETER ExtensionDir
  Optional explicit path to the extension root (the folder that contains
  package.json and dist/). If omitted, the newest installed
  sapse.adt-vscode-* under %USERPROFILE%\.vscode\extensions is used.

.EXAMPLE
  ./patch.ps1
.EXAMPLE
  ./patch.ps1 -ExtensionDir "C:\path\to\sapse.adt-vscode-1.0.1-win32-x64"
#>
[CmdletBinding()]
param(
  [string]$ExtensionDir
)

$ErrorActionPreference = 'Stop'

function Count-Occurrences([string]$haystack, [string]$needle) {
  if ([string]::IsNullOrEmpty($needle)) { return 0 }
  $count = 0; $i = 0
  while (($i = $haystack.IndexOf($needle, $i, [System.StringComparison]::Ordinal)) -ge 0) {
    $count++; $i += $needle.Length
  }
  return $count
}

function Resolve-ExtensionDir([string]$explicit) {
  if ($explicit) {
    if (-not (Test-Path -LiteralPath $explicit -PathType Container)) {
      throw "ExtensionDir not found: $explicit"
    }
    return (Resolve-Path -LiteralPath $explicit).Path
  }
  $base = Join-Path $env:USERPROFILE '.vscode\extensions'
  if (-not (Test-Path -LiteralPath $base)) { throw "VS Code extensions folder not found: $base" }
  $cands = Get-ChildItem -LiteralPath $base -Directory -Filter 'sapse.adt-vscode-*' |
           Sort-Object Name -Descending
  if (-not $cands -or $cands.Count -eq 0) {
    throw "No installed 'sapse.adt-vscode-*' extension found under $base"
  }
  return $cands[0].FullName
}

$enc = [System.Text.Encoding]::GetEncoding('iso-8859-1')

# Load payloads (next to this script).
$payloadPath = Join-Path $PSScriptRoot 'patch\payloads.json'
if (-not (Test-Path -LiteralPath $payloadPath)) { throw "payloads.json not found at $payloadPath" }
$spec = Get-Content -LiteralPath $payloadPath -Raw -Encoding UTF8 | ConvertFrom-Json

$root   = Resolve-ExtensionDir $ExtensionDir
$extjs  = Join-Path $root ($spec.extjsRelPath -replace '/','\')
$pkg    = Join-Path $root ($spec.pkgRelPath   -replace '/','\')

Write-Host "Extension root : $root"
Write-Host "Target (js)    : $extjs"
Write-Host "Target (json)  : $pkg"
Write-Host ''

foreach ($p in @($extjs, $pkg)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Target file missing: $p" }
}

$extText = [System.IO.File]::ReadAllText($extjs, $enc)
$pkgText = [System.IO.File]::ReadAllText($pkg,   $enc)

# Guard: already patched?
$marker = [string]$spec.guardMarker
if ((Count-Occurrences $extText $marker) -gt 0 -or (Count-Occurrences $pkgText $marker) -gt 0) {
  Write-Host "Already patched (found marker '$marker'). Nothing to do." -ForegroundColor Yellow
  Write-Host "To undo, reinstall or update the extension." -ForegroundColor Yellow
  exit 0
}

# Verify every anchor occurs exactly once BEFORE writing anything.
$errors = @()
foreach ($pl in $spec.payloads) {
  $target = if ($pl.target -eq 'extjs') { $extText } elseif ($pl.target -eq 'pkgjson') { $pkgText } else { $null }
  if ($null -eq $target) { $errors += "payload '$($pl.name)': unknown target '$($pl.target)'"; continue }
  $n = Count-Occurrences $target $pl.find
  if ($n -ne 1) {
    $errors += "payload '$($pl.name)' [$($pl.target)]: anchor occurs $n time(s), expected exactly 1"
  }
}
if ($errors.Count -gt 0) {
  Write-Host "Safe stop: anchor verification failed. NOTHING was changed." -ForegroundColor Red
  foreach ($e in $errors) { Write-Host "  - $e" -ForegroundColor Red }
  Write-Host "The installed extension version may differ from what this patch targets." -ForegroundColor Red
  exit 1
}

# Apply (in memory).
foreach ($pl in $spec.payloads) {
  if ($pl.target -eq 'extjs')   { $extText = $extText.Replace([string]$pl.find, [string]$pl.replace) }
  if ($pl.target -eq 'pkgjson') { $pkgText = $pkgText.Replace([string]$pl.find, [string]$pl.replace) }
}

# Sanity: marker must now be present in both files.
if ((Count-Occurrences $extText $marker) -lt 1 -or (Count-Occurrences $pkgText $marker) -lt 1) {
  Write-Host "Safe stop: post-apply sanity check failed. NOTHING was written." -ForegroundColor Red
  exit 1
}

# Write back (latin1, no BOM).
[System.IO.File]::WriteAllText($extjs, $extText, $enc)
[System.IO.File]::WriteAllText($pkg,   $pkgText, $enc)

Write-Host "Patched successfully." -ForegroundColor Green
Write-Host "Reload VS Code (Developer: Reload Window) to load the patched extension."
Write-Host "Logon once; after it succeeds you will be asked whether to remember the password."
