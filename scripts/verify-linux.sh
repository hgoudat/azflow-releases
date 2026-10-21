#!/usr/bin/env bash
# Verifies a downloaded private Linux build before it can be published.
# Every check must pass; any failure exits non-zero and nothing is published.
#   verify-linux.sh cli     <staging> <tag>   azflow-linux-cli-<tag>: SHA256SUMS-linux,
#                                             release-linux.json and the tar.gz holding azflow-cli.
#   verify-linux.sh desktop <staging> <tag>   azflow-linux-desktop-<tag>: SHA256SUMS-linux-desktop,
#                                             release-linux-desktop.json, a valid .deb and an
#                                             AppImage ELF (an updater .sig may sit beside it).
# Linux files are not code-signed; nothing is executed here.
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }
sha() { sha256sum -- "$1" | cut -d' ' -f1; }

[[ $# -eq 3 ]] || fail "Usage: verify-linux.sh cli|desktop <staging> <tag>"
kind=$1 dir=$2 tag=$3
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Not a version tag: $tag"
version=${tag#v}
case $kind in
  cli) sums=SHA256SUMS-linux manifest=release-linux.json platform=linux
       expected=(azflow-cli-linux-x64.tar.gz) ;;
  desktop) sums=SHA256SUMS-linux-desktop manifest=release-linux-desktop.json platform=linux-desktop
           expected=(Azflow-AI-linux-x64.AppImage azflow-ai-linux-amd64.deb) ;;
  *) fail "Unknown kind: $kind" ;;
esac
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
  if [[ $kind == desktop && $name == *.AppImage.sig && -n ${listed[${name%.sig}]+x} ]]; then
    # A Tauri updater signature: base64 of a minisign signature. Its key is checked by the app.
    decoded=$(base64 -d < "$path" 2>/dev/null) || fail "$name is not base64."
    [[ $decoded == 'untrusted comment:'* ]] || fail "$name is not an updater signature."
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

if [[ $kind == cli ]]; then
  archive=$dir/azflow-cli-linux-x64.tar.gz
  [[ $(tar -tzf "$archive") == azflow-cli ]] || fail "azflow-cli-linux-x64.tar.gz must hold only azflow-cli."
  [[ $(jq -r '.files[0].contains | keys | join(" ")' "$dir/$manifest") == azflow-cli ]] \
    || fail "$manifest must list azflow-cli as the archive's only content."
  extract=$(mktemp -d)
  tar -xzf "$archive" -C "$extract" azflow-cli
  [[ $(sha "$extract/azflow-cli") == "$(jq -r '.files[0].contains["azflow-cli"]' "$dir/$manifest")" ]] \
    || fail "Hash mismatch for azflow-cli in azflow-cli-linux-x64.tar.gz"
  is_elf "$extract/azflow-cli" || fail "azflow-cli is not an ELF executable."
  echo "Verified Linux CLI $tag."
  exit 0
fi

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
