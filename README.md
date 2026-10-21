# Azflow AI releases

Signed Azflow AI downloads. Each release's files are built and signed in a private repository,
then verified again here and published only after the owner approves them.

File names carry no version, so `releases/latest/download/<file>` always gives the newest
release. Each release's version is in its title, tag and `release*.json` files.

## macOS

- `Azflow-AI-macos-arm64.dmg` — the Azflow AI desktop app for Apple silicon, macOS 13.5 or
  later. Signed with a Developer ID and notarized by Apple. The `azflow-cli` tool ships inside it.
- `SHA256SUMS-macos` and `release-macos.json` list the DMG's SHA-256 and notarization ID.
- The DMG is built and notarized on the owner's Mac and attached to the release by hand after
  the release is published; it is not part of the automated publish.

## Windows

- `Azflow-AI-windows-x64-setup.exe` — the Azflow AI desktop app installer (per-user, no
  administrator rights needed). The installer and every executable inside it are signed.
- `azflow-cli-windows-x64.zip` — the Azflow command-line tool (`azflow-cli.exe`) on its own.
- Everything is signed by **FAJWAH LLC** through Azure Artifact Signing, with a timestamp.
- `SHA256SUMS` and `release.json` cover the CLI zip (the manifest records the hash of each
  executable inside it); `SHA256SUMS-windows-desktop` and `release-windows-desktop.json` cover
  the installer. A `.sig` next to the installer is the in-app updater's signature.

Check a download in PowerShell:

```powershell
(Get-FileHash .\Azflow-AI-windows-x64-setup.exe -Algorithm SHA256).Hash
Get-AuthenticodeSignature .\Azflow-AI-windows-x64-setup.exe | Format-List Status, SignerCertificate
```

## Linux

- `Azflow-AI-linux-x64.AppImage` — the Azflow AI desktop app as a single file
  (`chmod +x`, then run it).
- `azflow-ai-linux-amd64.deb` — the same app for Debian 12, Ubuntu 22.04 and later
  (`sudo apt install ./azflow-ai-linux-amd64.deb`).
- `azflow-cli-linux-x64.tar.gz` — the Azflow command-line tool on its own.
- Linux has no common code-signing scheme. Check the desktop files against
  `SHA256SUMS-linux-desktop` and the CLI against `SHA256SUMS-linux`
  (`sha256sum -c --ignore-missing SHA256SUMS-linux-desktop`). A `.sig` next to the AppImage is
  the in-app updater's signature.

## How a release is published

1. A version tag in the private repository runs **Windows signed release**. One run builds and
   signs the Windows CLI and the Windows desktop installer, builds the Linux CLI and the Linux
   desktop packages, and keeps each set as a private artifact.
2. **Publish Windows release** here takes that run's ID and checks that the run succeeded and
   holds every set for one tag. The signed Windows CLI is always required; the desktop sets are
   required too unless `include_desktop` is turned off.
3. Each set is downloaded and verified again here, nothing is rebuilt and no installer is run:
   - Windows CLI: checksums, `release.json`, the FAJWAH LLC signer and timestamp on every
     executable, and that each one starts.
   - Windows desktop: checksums, `release-windows-desktop.json` names this version, and the
     installer's FAJWAH LLC signature and timestamp.
   - Linux: checksums and manifests for this version, the `.deb` is a valid amd64 Debian
     package of this version, and the AppImage is an AppImage (ELF) file.
4. The owner approves the `azflow-release` environment; all verified files are then attached
   to one GitHub release, `vX.Y.Z`. Published files are immutable: if the release already
   exists, every file it already has must be byte-identical, and only missing files are added.
5. The notarized macOS DMG and its `SHA256SUMS-macos` and `release-macos.json` are then
   attached to the same release from the Mac.
