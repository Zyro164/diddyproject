#!/usr/bin/env bash
# fetch-release.sh — download a sandbox-backup release WITHOUT gh (curl + python3 only).
#
#   export GH_TOKEN=github_pat_...            # fine-grained PAT: Contents = Read-only
#   ./fetch-release.sh                         # list releases
#   ./fetch-release.sh backup-20261122T180617Z
#
# Downloads every asset of the tag into ./restore-<tag>/ , rejoins split parts,
# verifies checksums and decrypts (asks for the passphrase).
set -euo pipefail
REPO="${GH_REPO:-Zyro164/sandbox-backup}"
API="https://api.github.com/repos/$REPO"
: "${GH_TOKEN:?set GH_TOKEN to a token with Contents:Read on $REPO}"
H=(-H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json")

say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing: $1"; }
need curl; need python3; need gpg

tag="${1:-}"
if [[ -z "$tag" ]]; then
  say "releases in $REPO"
  curl -sSL "${H[@]}" "$API/releases" |
    python3 -c 'import json,sys; [print(r["tag_name"], "  ", sum(a["size"] for a in r["assets"])//1048576, "MB") for r in json.load(sys.stdin)]'
  exit 0
fi

dir="restore-$tag"; mkdir -p "$dir"; cd "$dir"
say "reading asset list for $tag"
curl -sSL "${H[@]}" "$API/releases/tags/$tag" > release.json
python3 - "$tag" <<'PY'
import json,sys
r=json.load(open('release.json'))
if 'assets' not in r: sys.exit("release not found or no access: "+r.get('message',''))
open('assets.txt','w').write("\n".join(f'{a["name"]}\t{a["url"]}\t{a["size"]}' for a in r["assets"]))
print(f'{len(r["assets"])} assets')
PY
while IFS=$'\t' read -r name url size; do
  printf '  ↓ %-72s %8.1f MB\n' "$name" "$(python3 -c "print($size/1048576)")"
  curl -sSL "${H[@]}" -H "Accept: application/octet-stream" "$url" -o "$name" || die "download failed: $name"
done < assets.txt

# checksum the parts, rejoin, checksum the joined blob, decrypt
if ls *.gpg.part-* >/dev/null 2>&1; then
  [[ -f *.gpg.parts.sha256 ]] && { say "verifying parts"; sha256sum -c *.gpg.parts.sha256; }
  joined="$(basename "$(ls *.gpg.part-* | head -1)" | sed -E 's/\.part-[0-9]+$//')"
  say "re-joining parts → $joined"
  cat "$joined".part-* > "$joined"
fi
enc="$(ls *.tar.zst.gpg 2>/dev/null | head -1)"
[[ -n "$enc" ]] || die "no .tar.zst.gpg found"
[[ -f "$enc.sha256" ]] && { say "verifying $enc"; sha256sum -c "$enc.sha256"; }
say "decrypting (passphrase prompt) → ${enc%.gpg}"
gpg --output "${enc%.gpg}" --decrypt "$enc"
say "done"
printf '  archive: %s\n  next   : ./desktop-backup.sh restore %s/%s\n' "$PWD/${enc%.gpg}" "$PWD" "${enc%.gpg}"
