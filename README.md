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
- `Azflow-AI-macos-arm64.app.tar.gz` and its `.sig` are what the app downloads when it updates itself.

## Updates

From 0.4.0 the desktop app updates itself. `latest.json` on the newest release lists each
platform's update file and its signature; the app accepts only files signed with the key built
into it. It is attached last, after every other file of the release.

## Windows

- `Azflow-AI-windows-x64-setup.exe` — the Azflow AI desktop app installer (per-user, no
  administrator rights needed). The installer and every executable inside it are signed.
  The `azflow-cli` tool ships inside it and is added to your `PATH`.
- Everything is signed by **FAJWAH LLC** through Azure Artifact Signing, with a timestamp.
- `SHA256SUMS-windows-desktop` and `release-windows-desktop.json` cover the installer. A `.sig`
  next to the installer is the in-app updater's signature.

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
- `SHA256SUMS-linux-desktop` lists the files' SHA-256 hashes, and `SHA256SUMS-linux-desktop.asc`
  signs that list with the **Azflow AI Releases** key ([keys/azflow-archive-keyring.asc](keys/azflow-archive-keyring.asc)),
  fingerprint `06E7 46E2 5616 5BC1 B6CF  4970 E052 B1E9 667A 82A0`. A `.sig` next to the AppImage
  is the in-app updater's signature.

Check a download:

```bash
gpg --import azflow-archive-keyring.asc
gpg --verify SHA256SUMS-linux-desktop.asc SHA256SUMS-linux-desktop
sha256sum -c --ignore-missing SHA256SUMS-linux-desktop
```

## Verifying downloads

Every release carries a `SHA256SUMS-<platform>` file listing each download's SHA-256 hash.

- **macOS:** the app is notarized by Apple; macOS checks it when you open it. To compare the hash:
  `shasum -a 256 -c --ignore-missing SHA256SUMS-macos`.
- **Windows:** the installer is signed by FAJWAH LLC (commands under [Windows](#windows)).
- **Linux:** check the signed checksum list, then the files (commands under [Linux](#linux)).

## How a release is published

1. The release's "What's new" goes in `notes/vX.Y.Z.md` here; the release page is that text plus a
   standard downloads and verification section. Publishing stops if the file is missing.
2. A version tag in the private repository runs **Release**. One run builds and signs the
   Windows desktop installer, builds the Linux desktop packages, and keeps each as a private
   artifact.
3. **Publish release** here takes that run's ID and checks that the run succeeded and holds
   both sets for one tag.
4. Each set is downloaded and verified again here, nothing is rebuilt and no installer is run:
   - Windows: checksums, `release-windows-desktop.json` names this version, and the installer's
     FAJWAH LLC signature and timestamp.
   - Linux: checksums and manifests for this version, the checksum list's signature by the
     pinned Azflow AI Releases key, the `.deb` is a valid amd64 Debian package of this version,
     and the AppImage is an AppImage (ELF) file.
5. The owner approves the `azflow-release` environment; all verified files are then attached
   to one GitHub release, `vX.Y.Z`. Published files are immutable: if the release already
   exists, every file it already has must be byte-identical, and only missing files are added.
6. The notarized macOS DMG, the macOS update file and its `.sig`, `SHA256SUMS-macos` and
   `release-macos.json` are then attached to the same release from the Mac, and `latest.json` last.
