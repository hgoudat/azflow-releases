# Azflow releases

Signed Azflow downloads. Each release's files are built and signed in a private repository,
then verified again here and published only after the owner approves them.

## Windows

- `azflow-cli-<version>-windows-x64.zip` — the Azflow command-line tool (`azflow-cli.exe`).
  The desktop app for Windows will be added here when it is ready.
- Executables are signed by **FAJWAH LLC** through Azure Artifact Signing, with a timestamp.
- `SHA256SUMS` lists every file's SHA-256; `release.json` records the version, source commit
  and the hash of each executable inside each zip.

Check a download in PowerShell:

```powershell
(Get-FileHash .\azflow-cli-<version>-windows-x64.zip -Algorithm SHA256).Hash
Get-AuthenticodeSignature .\azflow-cli.exe | Format-List Status, SignerCertificate
```

## How a release is published

1. A version tag in the private repository runs **Windows signed release**: build, sign,
   verify the signature, and keep the files as a private artifact.
2. **Publish Windows release** here takes that run's ID, downloads the files, and checks the
   checksums, the manifest, the signer and timestamp, and that each executable starts.
3. The owner approves the `azflow-release` environment; the files are then attached to a
   GitHub release. A published release is never replaced with different files.
