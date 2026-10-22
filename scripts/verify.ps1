# Verifies a downloaded private Windows desktop build before it can be published.
# Every check must pass; any failure throws and nothing is published.
# Checks azflow-windows-desktop-<tag>: SHA256SUMS-windows-desktop, release-windows-desktop.json
# and the signed, timestamped NSIS installer (never executed). An updater signature
# <installer>.sig may sit beside it.
param(
  [Parameter(Mandatory)] [string] $Staging,
  [Parameter(Mandatory)] [string] $Tag
)
$ErrorActionPreference = 'Stop'
# The validated FAJWAH LLC PublicTrust profile (Azure Artifact Signing).
$Signer = 'CN=FAJWAH LLC, O=FAJWAH LLC, L=Lees Summit, S=Missouri, C=US'

function Get-Sha256([string] $Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

function Assert-Signed([string] $Path, [string] $Label) {
  $s = Get-AuthenticodeSignature -LiteralPath $Path
  if ($s.Status -ne 'Valid' -or -not $s.TimeStamperCertificate -or $s.SignerCertificate.Subject -ne $Signer) {
    throw "Unexpected signature on ${Label}: $($s.Status) $($s.SignerCertificate.Subject)"
  }
  Write-Output "${Label}: signed by $($s.SignerCertificate.Subject) ($($s.SignerCertificate.Thumbprint))"
}

# A Tauri updater signature: base64 of a minisign signature. Its key is checked by the app.
function Assert-UpdaterSignature([string] $Path) {
  $text = (Get-Content -LiteralPath $Path -Raw).Trim()
  try { $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($text)) } catch { throw "$Path is not base64." }
  if (-not $decoded.StartsWith('untrusted comment:')) { throw "$Path is not an updater signature." }
}

$sumsName = 'SHA256SUMS-windows-desktop'
$manifestName = 'release-windows-desktop.json'
$sums = Join-Path $Staging $sumsName
$manifestPath = Join-Path $Staging $manifestName
if (-not (Test-Path $sums) -or -not (Test-Path $manifestPath)) { throw "$sumsName or $manifestName is missing." }

# Exactly the files the checksum list names, each with its listed hash (plus an optional
# updater signature for the installer, which is made after the checksums).
$listed = @{}
foreach ($line in Get-Content $sums) {
  if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$') { throw "Malformed $sumsName line: $line" }
  $listed[$Matches[2]] = $Matches[1]
}
$present = @()
foreach ($name in (Get-ChildItem $Staging -File | Where-Object Name -ne $sumsName | ForEach-Object Name)) {
  if ($name -like '*.exe.sig' -and $listed.ContainsKey($name.Substring(0, $name.Length - 4))) {
    Assert-UpdaterSignature (Join-Path $Staging $name)
    continue
  }
  $present += $name
}
if (@(Get-ChildItem $Staging -Directory).Count) { throw "Unexpected folders in $Staging." }
if (@(Compare-Object @($listed.Keys) @($present)).Count) { throw "Files do not match $sumsName." }
foreach ($name in $listed.Keys) {
  if ((Get-Sha256 (Join-Path $Staging $name)) -ne $listed[$name]) { throw "Checksum mismatch: $name" }
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($manifest.tag -ne $Tag -or "v$($manifest.version)" -ne $Tag) { throw "$manifestName is for $($manifest.tag), not $Tag." }
if ($manifest.signer -ne $Signer) { throw "$manifestName names an unexpected signer: $($manifest.signer)" }
if ($manifest.platform -ne 'win32-desktop') { throw "$manifestName is for $($manifest.platform), not win32-desktop." }
if (@($manifest.files).Count -eq 0) { throw "$manifestName lists no files." }
if (@(Compare-Object @($manifest.files.name) @($listed.Keys | Where-Object { $_ -ne $manifestName })).Count) {
  throw "$manifestName and $sumsName list different files."
}

# The installer is itself the signed file: its manifest `contains` names only itself.
# It is never run here.
foreach ($file in $manifest.files) {
  $installer = Join-Path $Staging $file.name
  if ($file.name -notlike '*.exe' -or -not $listed.ContainsKey($file.name)) { throw "Unexpected installer entry: $($file.name)" }
  if ((Get-Sha256 $installer) -ne $file.sha256) { throw "$manifestName hash mismatch: $($file.name)" }
  $contains = @($file.contains.PSObject.Properties)
  if ($contains.Count -ne 1 -or $contains[0].Name -ne $file.name -or $contains[0].Value -ne $file.sha256) {
    throw "$manifestName must list $($file.name) as its own signed content."
  }
  Assert-Signed $installer $file.name
}
Write-Output "Verified Windows desktop $Tag."
