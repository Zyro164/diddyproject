#!/usr/bin/env bash
# bundle.sh — pack secret / bulky data into AES-256 archives and upload them as
# GitHub *Release assets* (git refuses files >100 MB, release assets allow 2 GB).
#
#   ./scripts/bundle.sh secrets           # keys, tokens, shadow, certs  (~MB)
#   ./scripts/bundle.sh userdata          # browser profiles, app state, unique media (~GB)
#   ./scripts/bundle.sh upload [tag]      # push every bundle in $OUT as release assets
#   ./scripts/bundle.sh all               # secrets + userdata + upload
#
# Passphrase: $PASSFILE (default /config/backups/.bk.pass). It is NEVER committed.
# Losing it means the bundles are unrecoverable — store a copy in a password manager.
set -eu
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH="${GH:-/config/.local/bin/gh}"
OWNER="${GH_OWNER:-Zyro164}"; NAME="${GH_REPO:-diddyproject}"; SLUG="$OWNER/$NAME"
HOME_DIR="${HOME_DIR:-/config}"
PASSFILE="${PASSFILE:-/config/backups/.bk.pass}"
OUT="${OUT:-/config/backups/bundles}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m  ok\033[0m %s\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_pass() {
  [[ -s "$PASSFILE" ]] || die "missing passphrase file $PASSFILE
generate one with:  umask 077; openssl rand -base64 32 > $PASSFILE"
  chmod 600 "$PASSFILE" 2>/dev/null || true
}

# pack <name> <staging-dir> <path...>
pack() {
  local name="$1" stage="$2"; shift 2
  local tgz="$OUT/$name-$STAMP.tar.zst.gpg"
  say "packing $name → $(basename "$tgz")"
  # staged root-owned files must be readable by the current user, or tar skips them
  sudo -n chown -R "$(id -u):$(id -g)" "$stage" 2>/dev/null || true
  tar -C "$stage" -cf - . 2>/dev/null \
    | zstd -19 -T0 -q -c \
    | gpg --batch --yes --quiet --passphrase-file "$PASSFILE" \
          --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
          -o "$tgz"
  ( cd "$OUT" && sha256sum "$(basename "$tgz")" > "$(basename "$tgz").sha256" )
  ok "$(du -h "$tgz" | cut -f1)  $tgz"
  # keep an index of what went in (names + sizes only, no content)
  local tmpf="$OUT/.verify-$name.tar"
  if gpg --batch --quiet --passphrase-file "$PASSFILE" --decrypt "$tgz" 2>/dev/null \
       | zstd -dc 2>/dev/null > "$tmpf"; then
    tar -tvf "$tmpf" 2>/dev/null | sed 's/^/  /' > "$OUT/$name-$STAMP.filelist.txt" || true
    ok "verified: $(wc -l < "$OUT/$name-$STAMP.filelist.txt") entries readable after decrypt"
  else
    die "bundle failed round-trip decryption: $tgz"
  fi
  rm -f "$tmpf"
  rm -rf "$stage"
}

# copy something into staging, keeping its path relative to /
stage_path() { # <stage> <abs-path>
  local stage="$1" src="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$stage$(dirname "$src")"
  if [[ -d "$src" ]]; then
    sudo -n tar -C "$(dirname "$src")" -cf - "$(basename "$src")" 2>/dev/null | tar -C "$stage$(dirname "$src")" -xf - 2>/dev/null || true
  else
    sudo -n cp -a "$src" "$stage$src" 2>/dev/null || cp -a "$src" "$stage$src" 2>/dev/null || true
  fi
}

cmd_secrets() {
  need_pass
  local stage="$OUT/stage-secrets"
  rm -rf "$stage"; mkdir -p "$stage"
  say "staging secrets"
  for p in "$HOME_DIR/.ssh" "$HOME_DIR/.gnupg" "$HOME_DIR/.config/gh" "$HOME_DIR/ssl" \
           "$HOME_DIR/.deepai-code/userdata/secrets" \
           "$HOME_DIR/.deepai-code/userdata/account-clients" \
           "$HOME_DIR/.local/share/pki" \
           "$HOME_DIR/.config/ai.opencode.desktop/Cookies" \
           "$HOME_DIR/.config/ai.opencode.desktop/Local State" \
           "$HOME_DIR/.config/deepai-code-v2/Local Storage" \
           /etc/ssl/private /etc/shadow /etc/gshadow /etc/security/opasswd; do
    stage_path "$stage" "$p"
  done
  # plain-text history that was redacted in git
  mkdir -p "$stage/rootfs"
  [[ -f "$HOME_DIR/.bash_history" ]] && cp -a "$HOME_DIR/.bash_history" "$stage/rootfs/bash_history" 2>/dev/null || true
  pack "secrets" "$stage"
}

cmd_userdata() {
  need_pass
  local stage="$OUT/stage-userdata"
  rm -rf "$stage"; mkdir -p "$stage"
  say "staging userdata (caches and package payloads excluded)"
  # browser + app profiles, minus caches
  for p in "$HOME_DIR/.config/chromium" "$HOME_DIR/.config/BraveSoftware" \
           "$HOME_DIR/.config/ai.opencode.desktop" \
           "$HOME_DIR/.config/deepai-code-v2" \
           "$HOME_DIR/.local/share/pki" \
           "$HOME_DIR/.deepai-code/userdata" \
           "$HOME_DIR/.local/share/opencode"; do
    [[ -e "$p" ]] || continue
    mkdir -p "$stage$(dirname "$p")"
    tar -C "$(dirname "$p")" -cf - \
        --exclude='Cache' --exclude='Code Cache' --exclude='GPUCache' --exclude='cli' \
        --exclude='Service Worker' --exclude='DawnGraphiteCache' --exclude='DawnWebGPUCache' \
        --exclude='GrShaderCache' --exclude='ShaderCache' --exclude='CacheStorage' \
        --exclude='ScriptCache' --exclude='Crashpad' --exclude='component_crx_cache' \
        --exclude='CertificateRevocation' --exclude='Safe Browsing' \
        --exclude='logs' --exclude='tools' --exclude='chrome-headless-shell' \
        --exclude='Singleton*' --exclude='*.sock' \
        "$(basename "$p")" 2>/dev/null \
      | tar -C "$stage$(dirname "$p")" -xf - 2>/dev/null || true
  done
  # unique files that were pruned out of git because of size
  if [[ -f "$REPO_DIR/inventory/bulk.txt" ]]; then
    mkdir -p "$stage/rootfs/bulk"
    while IFS= read -r line; do
      case "$line" in \#*|"") continue ;; esac
      cls="$(printf '%s' "$line" | awk '{print $3}')"
      rel="$(printf '%s' "$line" | awk '{print $4}')"
      [[ "$cls" == "unique" ]] || continue
      local src="$HOME_DIR/$rel"
      [[ -f "$src" ]] || continue
      mkdir -p "$stage/rootfs/bulk/$(dirname "$rel")"
      cp -a "$src" "$stage/rootfs/bulk/$rel"
    done < "$REPO_DIR/inventory/bulk.txt"
  fi
  pack "userdata" "$stage"
}

cmd_upload() {
  local tag="${1:-backup-$STAMP}"
  local -a assets=()
  for f in "$OUT"/*.tar.zst.gpg "$OUT"/*.sha256; do [[ -f "$f" ]] && assets+=("$f"); done
  (( ${#assets[@]} )) || die "no bundles in $OUT (run: bundle.sh secrets / userdata)"
  say "uploading ${#assets[@]} asset(s) to $SLUG tag=$tag"
  if "$GH" release view "$tag" --repo "$SLUG" >/dev/null 2>&1; then
    "$GH" release upload "$tag" "${assets[@]}" --repo "$SLUG" --clobber
  else
    "$GH" release create "$tag" "${assets[@]}" --repo "$SLUG" \
      --title "Encrypted data bundles $tag" \
      --notes "Encrypted (AES-256/gpg) companion data for the machine snapshot in this repo.
Decrypt with the passphrase from /config/backups/.bk.pass on the original machine
(or your password manager copy). See secrets/README.md and RESTORE.md."
  fi
  ok "https://github.com/$SLUG/releases/tag/$tag"
}

case "${1:-}" in
  secrets)  shift; cmd_secrets  "$@" ;;
  userdata) shift; cmd_userdata "$@" ;;
  upload)   shift; cmd_upload   "$@" ;;
  all)      shift; cmd_secrets; cmd_userdata; cmd_upload "$@" ;;
  *) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
