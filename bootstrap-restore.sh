#!/usr/bin/env bash
# bootstrap-restore.sh — restore this sandbox's backup on a BARE Ubuntu box.
# Needs only: bash, curl, gpg, zstd, tar  (no gh, no jq, no python)
#
#   # from the sandbox bridge (encrypted blobs, no auth):
#   curl -fLO http://172.17.0.2:8099/bootstrap-restore.sh
#   ./bootstrap-restore.sh http://172.17.0.2:8099/desktop-abc-20261122T180617Z-settings.tar.zst.gpg
#
#   # or from files you downloaded out of the GitHub release:
#   ./bootstrap-restore.sh ~/Downloads/desktop-abc-...-settings.tar.zst.gpg
#
#   # already-decrypted archive:
#   ./bootstrap-restore.sh ./settings.tar.zst
#
# Flags: --with-system  --install-packages  --rootfs   (passed to desktop-backup.sh logic below)
set -euo pipefail

say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m  ok\033[0m %s\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

src=""; flags=()
for a in "$@"; do
  case "$a" in
    --*) flags+=("$a") ;;
    *)   src="$a" ;;
  esac
done
[[ -n "$src" ]] || die "usage: $0 <url|file> [--with-system] [--install-packages] [--rootfs]"
for t in curl gpg zstd tar; do command -v "$t" >/dev/null || die "missing tool: $t"; done

work="$(mktemp -d "${TMPDIR:-/tmp}/bsrestore.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cd "$work"

# ---------- 1. fetch
if [[ "$src" =~ ^https?:// ]]; then
  f="$(basename "${src%%\?*}")"
  say "downloading $f"
  curl -fL --progress-bar -O "$src" || die "download failed"
else
  [[ -f "$src" ]] || die "no such file: $src"
  f="$(basename "$src")"; cp -f "$src" .
  ok "using local $f"
fi

# ---------- 2. verify if a checksum is reachable
if [[ "$src" =~ ^https?:// ]]; then
  base="${src%/*}"
  if curl -fsL -o "$f.sha256" "$base/$f.sha256" 2>/dev/null; then
    say "verifying sha256"; sha256sum -c "$f.sha256" || die "checksum mismatch"
  fi
fi

# ---------- 3. decrypt (or accept a plain .tar.zst)
case "$f" in
  *.gpg)
    out="${f%.gpg}"
    say "decrypting → $out   (enter the backup passphrase)"
    gpg --output "$out" --decrypt "$f" || die "decryption failed (wrong passphrase?)"
    ;;
  *.tar.zst) out="$f" ;;
  *) die "unexpected file type: $f (expected .gpg or .tar.zst)" ;;
esac

say "archive preview"
zstd -dc "$out" | tar -tf - 2>/dev/null | head -5
printf '  entries: %s\n' "$(zstd -dc "$out" | tar -tf - 2>/dev/null | wc -l)"

# ---------- 4. restore
home="${HOME:-/config}"
rootfs=0; withsys=0; pkgs=0
for a in "${flags[@]:-}"; do
  case "$a" in
    --rootfs) rootfs=1; withsys=1 ;;
    --with-system) withsys=1 ;;
    --install-packages) pkgs=1; withsys=1 ;;
  esac
done
SUDO=""; (( $(id -u) == 0 )) || SUDO="sudo"

if (( rootfs )); then
  say "restoring WHOLE ROOTFS onto / (overwrites /usr /opt /etc)"
  zstd -dc "$out" | $SUDO tar -xf - -C / --numeric-owner \
      --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
      --exclude='./etc/machine-id' --exclude='./etc/hostname' --exclude='./etc/hosts' \
      --exclude='./etc/resolv.conf'
  $SUDO ldconfig 2>/dev/null || true
  ok "done — restart the container / desktop session"
  exit 0
fi

stage="$work/x"; mkdir -p "$stage"
say "extracting"
zstd -dc "$out" | tar -xf - -C "$stage" --numeric-owner \
    --exclude='./etc/machine-id' --exclude='./etc/hostname' --exclude='./etc/hosts' \
    --exclude='./etc/resolv.conf' --exclude='./etc/ld.so.cache'

if [[ -d "$stage/config" ]]; then
  say "restoring home → $home"
  shopt -s dotglob nullglob
  for item in "$stage/config"/*; do
    cp -a "$item" "$home"/ 2>/dev/null || say "  skipped $(basename "$item") (busy)"
  done
  shopt -u dotglob nullglob
  $SUDO chown -R "$(id -u):$(id -g)" "$home" 2>/dev/null || true
  ok "home restored"
fi

if (( withsys )); then
  say "restoring system dirs"
  if (( pkgs )) && [[ -f "$stage/meta/apt-manual.txt" ]]; then
    $SUDO apt-get update -qq || true
    xargs -a "$stage/meta/apt-manual.txt" $SUDO apt-get install -y --no-install-recommends || \
      say "  some packages failed"
  fi
  for d in etc opt usr/local var/lib/flatpak var/spool/cron; do
    [[ -d "$stage/$d" ]] || continue
    say "  /$d"
    $SUDO cp -a "$stage/$d/." "/$d/" 2>/dev/null || say "  partial /$d"
  done
  ok "system restored"
fi

cat <<EOF

Restored. Next:
  • log out/in (or restart the desktop session) so XFCE + apps reload
  • packages skipped?  xargs -a $stage/meta/apt-manual.txt sudo apt-get install -y
  • got the script?    ./desktop-backup.sh restore <archive>   does the same, with flags
EOF
