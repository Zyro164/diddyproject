#!/usr/bin/env bash
# restore.sh — apply this snapshot to a machine.
#
#   ./scripts/restore.sh verify                 # L0: sha256 of every committed file
#   ./scripts/restore.sh home                   # L1: dotfiles + configs + /etc files
#   ./scripts/restore.sh packages [--pinned]    # L2: reinstall recorded packages
#   ./scripts/restore.sh project [dest]         # L3: the working project tree
#   ./scripts/restore.sh secrets  <bundle.gpg>  # L4: keys, tokens, shadow (needs passphrase)
#   ./scripts/restore.sh userdata <bundle.gpg>  # L5: browser/app state, unique media
#   ./scripts/restore.sh assets [dir]           # download + verify the encrypted release assets
#   ./scripts/restore.sh plan                   # L?: print what would be done, change nothing
#
# Requires: git, jq (or python3), zstd, gnupg, sudo for /etc and packages.
set -eu
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME_DIR:-$HOME}"
PASSFILE="${PASSFILE:-$HOME_DIR/.backup-pass}"
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m  !!\033[0m %s\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

cmd_verify() {
  say "verifying committed files against .sha256sums"
  cd "$REPO_DIR"
  [[ -f .sha256sums ]] || die ".sha256sums missing (run scripts/manifest.sh)"
  if sha256sum -c .sha256sums --quiet; then
    ok "all $(wc -l < .sha256sums) committed files match"
  else
    die "checksum mismatch — the clone is damaged or modified; re-clone before restoring"
  fi
  [[ -f MANIFEST.json ]] && ok "MANIFEST.json present ($(du -h MANIFEST.json | cut -f1))"
}

copy_home() {
  local src="$REPO_DIR/home"
  [[ -d "$src" ]] || die "home/ missing"
  say "L1: applying dotfiles into $HOME_DIR (existing files saved as *.pre-restore)"
  ( cd "$src" && find . -type f -print0 ) | while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    case "$rel" in
      .bash_history.redacted) continue ;;
      *) ;;
    esac
    local dst="$HOME_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" ]] && ! cmp -s "$src/$rel" "$dst"; then cp -a "$dst" "$dst.pre-restore"; fi
    cp -a "$src/$rel" "$dst"
  done
  [[ -f "$src/.bash_history.redacted" ]] && \
    cp -a "$src/.bash_history.redacted" "$HOME_DIR/.bash_history.restored-redacted"
  ok "dotfiles applied"
  # packed directories (thousands of small files, e.g. icon themes) live in assets/
  if [[ -f "$REPO_DIR/inventory/bulk-dirs.txt" ]]; then
    while IFS= read -r line; do
      case "$line" in \#*|"") continue ;; esac
      local rel arc
      rel="$(printf '%s' "$line" | awk '{print $2}')"
      arc="$(printf '%s' "$line" | awk '{print $3}')"
      [[ -f "$REPO_DIR/$arc" ]] || { warn "missing $arc"; continue; }
      mkdir -p "$HOME_DIR/$rel"
      zstd -dc "$REPO_DIR/$arc" | tar -C "$HOME_DIR/$rel" -xf - && ok "unpacked $rel"
    done < "$REPO_DIR/inventory/bulk-dirs.txt"
  fi
  if [[ -d "$REPO_DIR/inventory/etc" ]]; then
    say "L1: applying recorded /etc files (needs sudo)"
    ( cd "$REPO_DIR/inventory/etc" && find . -type f \
        ! -name 'etc-sha256.txt' ! -name 'etc-modified.txt' ! -name 'etc-secret-hashes.txt' -print0 ) \
      | while IFS= read -r -d '' rel; do
          rel="${rel#./}"
          local dst="/$rel"
          sudo -n mkdir -p "$(dirname "$dst")" 2>/dev/null || warn "no sudo, skipped /$rel"
          sudo -n cp -a "$REPO_DIR/inventory/$rel" "$dst" 2>/dev/null && ok "/$rel" || warn "skipped /$rel"
        done
  fi
}

cmd_packages() {
  local pinned=0; [[ "${1:-}" == "--pinned" ]] && pinned=1
  local pk="$REPO_DIR/inventory/packages.txt"
  [[ -f "$pk" ]] || die "inventory/packages.txt missing"
  say "L2: reinstalling packages (this takes a while)"
  local tmp; tmp="$(mktemp -d)"
  sed -n '/^# apt-mark showmanual/,/^# snap/p' "$pk" | grep -vE '^#|^$' > "$tmp/manual.txt"
  sed -n '/^# dpkg (ii only)/,/^# apt-mark/p' "$pk" | grep -vE '^#|^$' | awk -F'\t' '{print $1}' > "$tmp/all.txt"
  say "updating apt"
  sudo -n apt-get update -qq || die "apt-get update failed"
  if (( pinned )); then
    sed -n '/^# dpkg (ii only)/,/^# apt-mark/p' "$pk" | grep -vE '^#|^$' \
      | awk -F'\t' '{print $1"="$2}' > "$tmp/pinned.txt"
    say "installing $(wc -l < "$tmp/pinned.txt") packages at their recorded versions"
    sudo -n xargs -a "$tmp/pinned.txt" apt-get install -y --allow-downgrades || \
      warn "some pinned versions are gone from the archive; rerun without --pinned"
  else
    say "installing $(wc -l < "$tmp/manual.txt") explicitly-installed packages"
    sudo -n xargs -a "$tmp/manual.txt" apt-get install -y
  fi
  if grep -q '^# flatpak' "$pk"; then
    local apps; apps="$(sed -n '/^# flatpak/,/^# appimages/p' "$pk" | grep -vE '^#|^$' | awk '{print $1}')"
    [[ -n "$apps" ]] && { command -v flatpak >/dev/null && \
      say "flatpak: installing $apps" && xargs -a <(printf '%s\n' "$apps") flatpak install -y flathub || \
      warn "flatpak unavailable, skipped"; }
  fi
  rm -rf "$tmp"
  ok "packages done — compare with: dpkg -l | awk '/^ii/{print \$2}' | sort"
}

cmd_project() {
  local dest="${1:-$HOME_DIR/work/diddyproject}"
  local src="$REPO_DIR/project"
  [[ -d "$src" ]] || die "project/ missing"
  say "L3: restoring project tree → $dest"
  mkdir -p "$dest" && cp -a "$src/." "$dest/"
  chmod +x "$dest"/*.sh 2>/dev/null || true
  ok "$(find "$dest" -type f | wc -l) files in $dest"
  warn "installers (*.deb, AppImage) are not committed — see inventory/download-hints.md"
}

decrypt_bundle() { # <bundle.gpg> <outdir>
  local b="$1" out="$2" pass="${PASS:-}"
  [[ -f "$b" ]] || die "bundle not found: $b"
  if [[ -f "$b.sha256" ]]; then
    say "checking $(basename "$b")"
    ( cd "$(dirname "$b")" && sha256sum -c "$(basename "$b").sha256" --quiet ) || die "bundle checksum mismatch"
    ok "sha256 verified"
  fi
  mkdir -p "$out"
  say "decrypting $(basename "$b") → $out"
  local args=(--batch --yes --quiet --decrypt)
  if [[ -n "$pass" ]]; then args+=(--passphrase "$pass")
  elif [[ -s "$PASSFILE" ]]; then args+=(--passphrase-file "$PASSFILE")
  else warn "no passphrase file at $PASSFILE — gpg will prompt"; fi
  gpg "${args[@]}" "$b" | zstd -dc | tar -C "$out" -xf -
  ok "$(find "$out" -type f | wc -l) files extracted"
}

cmd_secrets() {
  local b="${1:-}"; [[ -n "$b" ]] || die "usage: restore.sh secrets <bundle.gpg>"
  local out; out="$(mktemp -d)"
  decrypt_bundle "$b" "$out"
  say "L4: installing secret material"
  local h="$out/config"   # bundled with $HOME paths preserved as ./config/...
  if [[ -d "$h" ]]; then
    for d in .ssh .gnupg .config/gh ssl .deepai-code/userdata/secrets .deepai-code/userdata/account-clients; do
      [[ -e "$h/$d" ]] || continue
      mkdir -p "$HOME_DIR/$(dirname "$d")"
      cp -a "$h/$d" "$HOME_DIR/$(dirname "$d")/" && ok "~/$d"
    done
  fi
  if [[ -d "$out/etc" ]]; then
    for f in shadow gshadow; do
      [[ -f "$out/etc/$f" ]] || continue
      sudo -n cp -a "$out/etc/$f" "/etc/$f" && sudo -n chown root:shadow "/etc/$f" && \
        sudo -n chmod 640 "/etc/$f" && ok "/etc/$f"
    done
    [[ -f "$out/etc/security/opasswd" ]] && \
      sudo -n mkdir -p /etc/security && \
      sudo -n cp -a "$out/etc/security/opasswd" /etc/security/opasswd && ok /etc/security/opasswd
    if [[ -d "$out/etc/ssl/private" && -n "$(ls -A "$out/etc/ssl/private" 2>/dev/null)" ]]; then
      sudo -n mkdir -p /etc/ssl/private
      sudo -n cp -a "$out/etc/ssl/private/." /etc/ssl/private/ && ok /etc/ssl/private
    fi
  fi
  [[ -f "$out/rootfs/bash_history" ]] && cp -a "$out/rootfs/bash_history" "$HOME_DIR/.bash_history" && ok "~/.bash_history"
  chmod 700 "$HOME_DIR/.ssh" "$HOME_DIR/.gnupg" 2>/dev/null || true
  rm -rf "$out"
  ok "secrets applied — verify: gh auth status, ssh-add -l"
}

cmd_userdata() {
  local b="${1:-}"; [[ -n "$b" ]] || die "usage: restore.sh userdata <bundle.gpg>"
  local out; out="$(mktemp -d)"
  decrypt_bundle "$b" "$out"
  say "L5: restoring browser/app state"
  [[ -d "$out/config" ]] && { cp -a "$out/config/." "$HOME_DIR/" && ok "~/.config + ~/.local/share + ~/.deepai-code"; }
  if [[ -d "$out/rootfs/bulk" ]]; then
    ( cd "$out/rootfs/bulk" && find . -type f -print0 ) | while IFS= read -r -d '' rel; do
      mkdir -p "$HOME_DIR/$(dirname "${rel#./}")"
      cp -a "$out/rootfs/bulk/${rel#./}" "$HOME_DIR/${rel#./}" && ok "~/${rel#./}"
    done
  fi
  rm -rf "$out"
  ok "userdata applied"
}

cmd_assets() { # download the newest release's encrypted bundles next to this repo
  command -v gh >/dev/null || die "gh CLI required (or download the Release assets manually)"
  local dir="${1:-$REPO_DIR/../assets-remote}"
  local tag; tag="$(gh release list --repo Zyro164/diddyproject --limit 1 --json tagName -q '.[0].tagName')"
  [[ -n "$tag" ]] || die "no release found on Zyro164/diddyproject"
  say "downloading assets of $tag → $dir"
  mkdir -p "$dir"
  gh release download "$tag" --repo Zyro164/diddyproject --dir "$dir" --clobber
  ( cd "$dir" && sha256sum -c *.sha256 ) && ok "assets verified"
  ls -lh "$dir"
}

cmd_plan() {
  say "snapshot: $(grep -m1 generated_at "$REPO_DIR/MANIFEST.json" 2>/dev/null | tr -d ' ",' | cut -d: -f2- || echo unknown)"
  printf '  home/      %s files, %s\n' "$(find "$REPO_DIR/home" -type f 2>/dev/null | wc -l)" "$(du -sh "$REPO_DIR/home" 2>/dev/null | cut -f1)"
  printf '  inventory/ %s files, %s\n' "$(find "$REPO_DIR/inventory" -type f 2>/dev/null | wc -l)" "$(du -sh "$REPO_DIR/inventory" 2>/dev/null | cut -f1)"
  printf '  project/   %s files, %s\n' "$(find "$REPO_DIR/project" -type f 2>/dev/null | wc -l)" "$(du -sh "$REPO_DIR/project" 2>/dev/null | cut -f1)"
  printf '  bulk (not in git): %s entries\n' "$(grep -vc '^#' "$REPO_DIR/inventory/bulk.txt" 2>/dev/null || echo 0)"
  printf '  release assets required: secrets-*.tar.zst.gpg, userdata-*.tar.zst.gpg (+ passphrase)\n'
}

case "${1:-}" in
  verify)   shift; cmd_verify   "$@" ;;
  home)     shift; copy_home    "$@" ;;
  packages) shift; cmd_packages "$@" ;;
  project)  shift; cmd_project  "$@" ;;
  secrets)  shift; cmd_secrets  "$@" ;;
  userdata) shift; cmd_userdata "$@" ;;
  assets)   shift; cmd_assets   "$@" ;;
  plan)     shift; cmd_plan     "$@" ;;
  *) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
