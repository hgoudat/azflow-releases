# Verifies a downloaded private Windows build before it can be published.
# Every check must pass; any failure throws and nothing is published.
param(
  [Parameter(Mandatory)] [string] $Staging,
  [Parameter(Mandatory)] [string] $Tag
)
$ErrorActionPreference = 'Stop'
# The validated FAJWAH LLC PublicTrust profile (Azure Artifact Signing).
$Signer = 'CN=FAJWAH LLC, O=FAJWAH LLC, L=Lees Summit, S=Missouri, C=US'

function Get-Sha256([string] $Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

$sums = Join-Path $Staging 'SHA256SUMS'
$manifestPath = Join-Path $Staging 'release.json'
if (-not (Test-Path $sums) -or -not (Test-Path $manifestPath)) { throw 'SHA256SUMS or release.json is missing.' }

# Exactly the files SHA256SUMS lists, each with its listed hash.
$listed = @{}
foreach ($line in Get-Content $sums) {
  if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$') { throw "Malformed SHA256SUMS line: $line" }
  $listed[$Matches[2]] = $Matches[1]
}
$present = Get-ChildItem $Staging -File | Where-Object Name -ne 'SHA256SUMS' | ForEach-Object Name
if (@(Compare-Object @($listed.Keys) @($present)).Count) { throw 'Files do not match SHA256SUMS.' }
foreach ($name in $listed.Keys) {
  if ((Get-Sha256 (Join-Path $Staging $name)) -ne $listed[$name]) { throw "Checksum mismatch: $name" }
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($manifest.tag -ne $Tag -or "v$($manifest.version)" -ne $Tag) { throw "release.json is for $($manifest.tag), not $Tag." }
if ($manifest.signer -ne $Signer) { throw "release.json names an unexpected signer: $($manifest.signer)" }

# Each archive: its manifest hash, then every executable inside signed, timestamped and runnable.
$extract = Join-Path $env:RUNNER_TEMP 'azflow-verify'
foreach ($file in $manifest.files) {
  $archive = Join-Path $Staging $file.name
  if ((Get-Sha256 $archive) -ne $file.sha256) { throw "release.json hash mismatch: $($file.name)" }
  Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive -LiteralPath $archive -DestinationPath $extract
  $inside = Get-ChildItem $extract -File -Recurse
  if ($inside.Count -ne @($file.contains.PSObject.Properties).Count) { throw "Unexpected contents in $($file.name)" }
  foreach ($entry in $file.contains.PSObject.Properties) {
    $path = Join-Path $extract $entry.Name
    if ((Get-Sha256 $path) -ne $entry.Value) { throw "Hash mismatch for $($entry.Name) in $($file.name)" }
    $s = Get-AuthenticodeSignature -LiteralPath $path
    if ($s.Status -ne 'Valid' -or -not $s.TimeStamperCertificate -or $s.SignerCertificate.Subject -ne $Signer) {
      throw "Unexpected signature on $($entry.Name): $($s.Status) $($s.SignerCertificate.Subject)"
    }
    & $path --version
    if ($LASTEXITCODE -ne 0) { throw "$($entry.Name) does not start." }
    Write-Output "$($entry.Name) in $($file.name): signed by $($s.SignerCertificate.Subject) ($($s.SignerCertificate.Thumbprint))"
  }
}
Write-Output "Verified $Tag."
