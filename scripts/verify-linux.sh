#!/usr/bin/env bash
# Verifies a downloaded private Linux build before it can be published.
# Every check must pass; any failure exits non-zero and nothing is published.
#   verify-linux.sh <staging> <tag>   azflow-linux-desktop-<tag>: SHA256SUMS-linux-desktop,
#                                     release-linux-desktop.json, a valid .deb and an
#                                     AppImage ELF (an updater .sig may sit beside it, and
#                                     SHA256SUMS-linux-desktop.asc, which must be a valid
#                                     signature by the key in keys/azflow-archive-keyring.asc).
# Nothing is executed here.
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }
sha() { sha256sum -- "$1" | cut -d' ' -f1; }
# The Azflow AI Releases signing key (keys/azflow-archive-keyring.asc), pinned by fingerprint.
GPG_FINGERPRINT=06E746E256165BC1B6CF4970E052B1E9667A82A0
KEYRING=$(cd "$(dirname "$0")/.." && pwd)/keys/azflow-archive-keyring.asc

[[ $# -eq 2 ]] || fail "Usage: verify-linux.sh <staging> <tag>"
dir=$1 tag=$2
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Not a version tag: $tag"
version=${tag#v}
sums=SHA256SUMS-linux-desktop manifest=release-linux-desktop.json platform=linux-desktop
expected=(Azflow-AI-linux-x64.AppImage azflow-ai-linux-amd64.deb)
[[ -f $dir/$sums && -f $dir/$manifest ]] || fail "$sums or $manifest is missing."

# Exactly the files the checksum list names, each with its listed hash.
declare -A listed=()
while IFS= read -r line || [[ -n $line ]]; do
  [[ $line =~ ^([0-9a-f]{64})\ \ ([A-Za-z0-9._-]+)$ ]] || fail "Malformed $sums line: $line"
  listed[${BASH_REMATCH[2]}]=${BASH_REMATCH[1]}
done < "$dir/$sums"
want=$(printf '%s\n' "${expected[@]}" "$manifest" | sort)
[[ $(printf '%s\n' "${!listed[@]}" | sort) == "$want" ]] || fail "$sums does not list exactly: $(echo $want)"

for path in "$dir"/* "$dir"/.[!.]*; do
  [[ -e $path ]] || continue
  name=${path##*/}
  [[ -f $path && ! -L $path ]] || fail "Unexpected entry in $dir: $name"
  [[ $name == "$sums" || -n ${listed[$name]+x} ]] && continue
  if [[ $name == *.AppImage.sig && -n ${listed[${name%.sig}]+x} ]]; then
    # A Tauri updater signature: base64 of a minisign signature. Its key is checked by the app.
    decoded=$(base64 -d < "$path" 2>/dev/null) || fail "$name is not base64."
    [[ $decoded == 'untrusted comment:'* ]] || fail "$name is not an updater signature."
    continue
  fi
  if [[ $name == "$sums.asc" ]]; then
    home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
    gpg --homedir "$home" --batch --quiet --import "$KEYRING" 2>/dev/null || fail "The signing key could not be read."
    gpg --homedir "$home" --batch --with-colons --list-keys | grep -qx "fpr:::::::::$GPG_FINGERPRINT:" \
      || fail "keys/azflow-archive-keyring.asc is not the pinned signing key."
    status=$(gpg --homedir "$home" --batch --status-fd 1 --verify "$path" "$dir/$sums" 2>/dev/null) \
      || fail "$name is not a valid signature of $sums."
    grep -q "^\[GNUPG:\] VALIDSIG $GPG_FINGERPRINT " <<<"$status" || fail "$name is not signed by $GPG_FINGERPRINT."
    echo "$name: good signature by $GPG_FINGERPRINT"
    continue
  fi
  fail "Not listed in $sums: $name"
done
for name in "${!listed[@]}"; do
  [[ $(sha "$dir/$name") == "${listed[$name]}" ]] || fail "Checksum mismatch: $name"
done

# The manifest is for this tag, unsigned, and its hashes agree with the checksums.
jq -e --arg tag "$tag" --arg version "$version" --arg platform "$platform" \
  '.tag == $tag and .version == $version and .platform == $platform and .signer == null' \
  "$dir/$manifest" >/dev/null || fail "$manifest is not the $platform manifest for $tag."
[[ $(jq -r '.files[].name' "$dir/$manifest" | sort) == "$(printf '%s\n' "${expected[@]}" | sort)" ]] \
  || fail "$manifest does not list exactly: ${expected[*]}"
while IFS=$'\t' read -r name hash; do
  [[ $hash == "${listed[$name]}" ]] || fail "$manifest hash mismatch: $name"
done < <(jq -r '.files[] | [.name, .sha256] | @tsv' "$dir/$manifest")

is_elf() { [[ $(od -An -tx1 -N4 -- "$1" | tr -d ' \n') == 7f454c46 ]]; }

deb=$dir/azflow-ai-linux-amd64.deb
dpkg-deb --info "$deb" >/dev/null || fail "azflow-ai-linux-amd64.deb is not a Debian package."
dpkg-deb --contents "$deb" >/dev/null || fail "azflow-ai-linux-amd64.deb has an unreadable payload."
arch=$(dpkg-deb --field "$deb" Architecture)
debversion=$(dpkg-deb --field "$deb" Version)
[[ $arch == amd64 ]] || fail "azflow-ai-linux-amd64.deb is for $arch, not amd64."
[[ $debversion == "$version" || $debversion == "$version"-* ]] \
  || fail "azflow-ai-linux-amd64.deb is version $debversion, not $version."
echo "azflow-ai-linux-amd64.deb: $(dpkg-deb --field "$deb" Package) $debversion $arch"

appimage=$dir/Azflow-AI-linux-x64.AppImage
is_elf "$appimage" || fail "Azflow-AI-linux-x64.AppImage is not an ELF executable."
# AppImage type 2 magic: "AI" 0x02 at offset 8 of the ELF header.
[[ $(od -An -tx1 -j8 -N3 -- "$appimage" | tr -d ' \n') == 414902 ]] \
  || fail "Azflow-AI-linux-x64.AppImage is not a type 2 AppImage."
echo "Verified Linux desktop $tag."
