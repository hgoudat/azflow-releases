# Azflow AI releases

Signed Azflow AI downloads. Each release's files are built and signed in a private repository,
then verified again here and published only after the owner approves them.

File names carry no version, so `releases/latest/download/<file>` always gives the newest
release. Each release's version is in its title, tag and `release*.json` files.

## macOS

- `Azflow-AI-macos-arm64.dmg` — the Azflow AI desktop app for Apple silicon, macOS 13.5 or
  later. Signed with a Developer ID and notarized by Apple. The `azflow-cli` tool ships inside it.
- `SHA256SUMS-macos` and `release-macos.json` list the DMG's SHA-256 and notarization ID.

## Windows

- `azflow-cli-windows-x64.zip` — the Azflow command-line tool (`azflow-cli.exe`).
  The desktop app for Windows will be added here when it is ready.
- Executables are signed by **FAJWAH LLC** through Azure Artifact Signing, with a timestamp.
- `SHA256SUMS` lists every file's SHA-256; `release.json` records the version, source commit
  and the hash of each executable inside each zip.

Check a download in PowerShell:

```powershell
(Get-FileHash .\azflow-cli-windows-x64.zip -Algorithm SHA256).Hash
Get-AuthenticodeSignature .\azflow-cli.exe | Format-List Status, SignerCertificate
```

## Linux

- `azflow-cli-linux-x64.tar.gz` — the Azflow command-line tool. Linux has no common code-signing
  scheme; check it against `SHA256SUMS-linux`. The desktop app will be added when it is ready.

## How a release is published

1. A version tag in the private repository runs **Windows signed release**: build, sign,
   verify the signature, and keep the files as a private artifact. The same run builds the
   Linux CLI.
2. **Publish Windows release** here takes that run's ID, downloads the files, and checks the
   checksums, the manifest, the signer and timestamp, and that each executable starts.
3. The owner approves the `azflow-release` environment; the files are then attached to a
   GitHub release. A published release is never replaced with different files.
4. The notarized macOS DMG and the Linux CLI are then attached to the same release.
