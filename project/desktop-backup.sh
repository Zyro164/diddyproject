#!/usr/bin/env bash
# desktop-backup.sh — full "copy" of an Ubuntu cloud-desktop sandbox (home + settings + packages)
# and a one-command restore for a fresh sandbox / plain Ubuntu desktop.
#
#   ./desktop-backup.sh backup                 # settings + files (no caches/downloads)  ~fast
#   ./desktop-backup.sh backup --full          # literally everything (caches, flatpak, .debs)
#   ./desktop-backup.sh backup --whole-system  # complete rootfs clone
#   ./desktop-backup.sh list                   # show archives
#   ./desktop-backup.sh verify <archive>       # check integrity + preview contents
#   ./desktop-backup.sh restore <archive>                # data only, into $HOME (portable)
#   ./desktop-backup.sh restore <archive> --with-system  # + /etc /opt /usr/local (needs sudo)
#   ./desktop-backup.sh restore <archive> --with-system --install-packages
#   ./desktop-backup.sh restore <archive> --rootfs       # restore a --whole-system clone
#
# Exit codes: 0 ok, 1 error, 2 usage.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${BACKUP_DIR:-/config/backups}"
HOME_DIR="${HOME:-/config}"
USER_NAME="$(id -un)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# volatile / never-restore paths
VOLATILE_ETC=(machine-id hostname hosts resolv.conf ld.so.cache mtab)
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
have_sudo() { sudo -n true 2>/dev/null; }

# ---------------------------------------------------------------- exclusions
# Default mode keeps *settings* (bookmarks, logins, profiles, keys, dotfiles,
# project files) and drops only things that are caches or re-downloadable.
EXCLUDES=(
  # --- home: pure caches
  './config/.cache'
  './config/.local/share/Trash'
  './config/.local/state'
  './config/.var/app/*/cache'
  # --- browser / electron caches (keep profiles: they hold logins+bookmarks)
  '*/Cache' '*/Cache_Data' '*/Code Cache' '*/GPUCache' '*/GrShaderCache' '*/ShaderCache'
  '*/DawnCache' '*/DawnGraphiteCache' '*/GraphiteDawnCache' '*/CacheStorage'
  '*/ScriptCache' '*/blob_storage' '*/Crashpad' '*/crashpad' '*/compile-cache'
  '*/component_crx_cache' '*/extensions_crx_cache' '*/optimization_guide_model_store'
  '*/segmentation_platform' '*/Safe Browsing' '*/Safe Browsing Network'
  '*/Service Worker/CacheStorage' '*/Service Worker/ScriptCache'
  '*/AutofillStates' '*/PKIMetadata' '*/SSLErrorAssistant'
  # --- crash dumps / temp
  './config/core' './config/*/core' './config/.deepai-code/*/core'
  '*.core' '*.crash' '*/tmp/*' '*/.Trash-*'
  # --- re-downloadable binaries & vendor payloads
  './config/Downloads'
  './config/.deepai-code/tools' './config/.deepai-code/caches'
  './config/.local/share/flatpak'
  './config/.config/ai.opencode.desktop/cli'
  './config/.config/ai.opencode.desktop/compile-cache'
  # --- volatile system files
  './etc/machine-id' './etc/hostname' './etc/hosts' './etc/resolv.conf'
  './etc/mtab' './etc/ld.so.cache' './etc/ssh/ssh_host_*' './etc/ssl/certs/ca-certificates.crt'
  './var/lib/dbus/machine-id' './var/log/*' './var/cache/*' './var/tmp/*'
)
FULL_EXCLUDES=(
  './config/core' './config/*/core' '*.core' '*/.Trash-*' '*/Crashpad' '*/crashpad'
  './etc/machine-id' './etc/hostname' './etc/hosts' './etc/resolv.conf' './etc/mtab'
  './etc/ld.so.cache' './etc/ssh/ssh_host_*' './var/lib/dbus/machine-id'
  './var/log/*' './var/cache/*' './var/tmp/*' '*/tmp/*'
)
# whole-rootfs clone: everything the image has, minus runtime pseudo-filesystems
WHOLE_EXCLUDES=(
  './proc' './sys' './dev' './run' './tmp' './mnt' './media' './boot'
  './var/tmp' './var/cache' './var/log' './var/lib/containerd'
  './etc/machine-id' './etc/hostname' './etc/hosts' './etc/resolv.conf' './etc/mtab'
  './etc/ld.so.cache' './etc/ssh/ssh_host_*' './var/lib/dbus/machine-id'
  './config/core' './config/*/core' '*.core' '*/.Trash-*'
)

# ---------------------------------------------------------------- inventory
collect_meta() {  # $1 = staging dir
  local m="$1/meta"
  mkdir -p "$m"
  {
    echo "stamp=$STAMP"
    echo "host=$(hostname)"
    echo "user=$USER_NAME (uid=$(id -u), gid=$(id -g))"
    echo "home=$HOME_DIR"
    echo "kernel=$(uname -srm)"
    echo "virt=$(systemd-detect-virt 2>/dev/null || echo unknown)"
    echo "image_guess=$(ls -d /lsiopy /docker-mods /init 2>/dev/null | tr '\n' ' ')"
    echo "desktop=$(ls /usr/share/xsessions 2>/dev/null | tr '\n' ' ')"
    echo "display=${DISPLAY:-none}"
  } > "$m/inventory.txt"
  cp -a /etc/os-release "$m/os-release" 2>/dev/null || true
  lscpu > "$m/lscpu.txt" 2>/dev/null || true
  free -h > "$m/mem.txt" 2>/dev/null || true
  df -h > "$m/disk.txt" 2>/dev/null || true
  # package state
  dpkg --get-selections > "$m/dpkg-selections.txt" 2>/dev/null || true
  apt-mark showmanual   > "$m/apt-manual.txt" 2>/dev/null || true
  ls -1 /etc/apt/sources.list.d 2>/dev/null > "$m/apt-sources.txt" || true
  # python state (system + lsiopy if present)
  python3 -m pip freeze 2>/dev/null > "$m/pip-freeze.txt" || true
  [ -x /lsiopy/bin/pip3 ] && /lsiopy/bin/pip3 freeze 2>/dev/null > "$m/pip-freeze-lsiopy.txt" || true
  # services / autostart / scheduled
  systemctl list-unit-files --state=enabled --no-pager 2>/dev/null > "$m/systemd-enabled.txt" || true
  ls -1 /etc/s6-overlay/s6-rc.d 2>/dev/null > "$m/s6-services.txt" || true
  crontab -l 2>/dev/null > "$m/crontab.txt" || true
  sudo -n crontab -l > "$m/crontab-root.txt" 2>/dev/null || true
  ls -1 "${HOME_DIR}/.config/autostart" 2>/dev/null > "$m/autostart.txt" || true
  # extras a plain Ubuntu needs to re-create the experience
  [ -x /lsiopy/bin/python3 ] && echo "/lsiopy present" >> "$m/inventory.txt"
  du -sh "$HOME_DIR" > "$m/home-size.txt" 2>/dev/null || true
}

# ---------------------------------------------------------------- backup
cmd_backup() {
  local full=0 whole=0
  for arg in "$@"; do
    case "$arg" in
      --full)         full=1 ;;
      --whole-system) whole=1 ;;
      -*) die "unknown flag: $arg" ;;
    esac
  done
  need tar; need zstd
  mkdir -p "$DEST_DIR"

  local stage; stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' RETURN
  say "collecting manifests"
  collect_meta "$stage"

  local mode="settings"; local -a excl=("${EXCLUDES[@]}")
  local -a paths=() p
  if (( whole )); then
    mode="whole-system"; excl=("${WHOLE_EXCLUDES[@]}"); paths=("./")
  elif (( full )); then
    mode="full"; excl=("${FULL_EXCLUDES[@]}"); full=1
  fi
  local out="$DEST_DIR/desktop-${USER_NAME}-${STAMP}-${mode}.tar.zst"

  # build exclusion args
  local -a xargs_tar=(); local e
  for e in "${excl[@]}"; do xargs_tar+=("--exclude=$e"); done

  # never archive our own output (archive lives under /config by default)
  local rel_dest="${DEST_DIR#/}"
  xargs_tar+=("--exclude=./${rel_dest}")

  # only include paths that actually exist on this box
  if (( ! whole )); then
    for p in ./config ./etc ./opt ./usr/local ./var/lib/flatpak ./var/spool/cron; do
      [[ -e "/${p#./}" ]] && paths+=("$p")
    done
  fi

  say "archiving ($mode) → $out  (paths: ${paths[*]})"
  local SUDO=""; { (( $(id -u) == 0 )) || have_sudo || die "backup needs root/sudo to read /etc"; }
  (( $(id -u) == 0 )) || SUDO="sudo -n"
  set +e
  $SUDO tar --numeric-owner \
      "${xargs_tar[@]}" \
      --warning=no-file-changed --warning=no-file-ignored \
      -C / -cf - "${paths[@]}" \
      -C "$stage" meta 2>"$stage/tar.err" \
    | zstd -q -T0 -"${LEVEL:-12}" --long=24 -o "$out"
  local -a pr=("${PIPESTATUS[@]}")
  set -e
  # tar rc 1 == "some files differ" (live desktop), which is expected and fine
  if (( pr[0] > 1 )) || (( ${pr[1]:-0} != 0 )); then
    tail -20 "$stage/tar.err" >&2; die "archive failed (tar rc=${pr[0]}, zstd rc=${pr[1]:-?})"
  fi
  grep -v -e 'file changed as we read it' -e 'socket ignored' -e 'file removed before we read it' \
       -e 'Cannot stat' "$stage/tar.err" 2>/dev/null | head -5 >&2 || true
  if (( $(id -u) == 0 )); then chown "$(id -u):$(id -g)" "$out" 2>/dev/null || true; fi
  if (( $(id -u) != 0 )) && have_sudo; then sudo -n chown "$(id -u):$(id -g)" "$out" 2>/dev/null || true; fi

  ( cd "$(dirname "$out")" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256" )
  cat > "$out.manifest.txt" <<EOF
archive   : $out
sha256    : $(cut -d' ' -f1 "$out.sha256")
created   : $STAMP
mode      : $mode
user/home : $USER_NAME / $HOME_DIR
size      : $(du -h "$out" | cut -f1)
restore   : $(basename "${BASH_SOURCE[0]}") restore $(basename "$out")
notes     : $( ((whole)) && echo "complete rootfs clone: /usr /opt /etc /config + all packages applied to the overlay" || { ((full)) && echo "includes caches, Downloads, flatpak, vendor tools" || echo "settings/files only; caches+Downloads+flatpak+vendor tool binaries excluded"; } )
EOF
  ok "wrote $out ($(du -h "$out" | cut -f1))"
  ok "manifest: $out.manifest.txt"
}

# ---------------------------------------------------------------- helpers
latest_archive() { ls -1t "$DEST_DIR"/desktop-*.tar.zst 2>/dev/null | head -1; }
resolve_archive() {
  local a="${1:-}"
  if [[ -z "$a" ]]; then a="$(latest_archive)"; [[ -n "$a" ]] || die "no archive in $DEST_DIR"; fi
  [[ -f "$a" ]] || a="$DEST_DIR/$a"
  [[ -f "$a" ]] || die "archive not found: $a"
  printf '%s\n' "$a"
}

cmd_list() {
  [[ -d "$DEST_DIR" ]] || { say "no archives yet in $DEST_DIR"; return 0; }
  ls -lh "$DEST_DIR"/desktop-*.tar.zst 2>/dev/null || say "no archives in $DEST_DIR"
}

cmd_verify() {
  need tar; need zstd
  local a; a="$(resolve_archive "${1:-}")"
  say "verifying $a"
  if [[ -f "$a.sha256" ]]; then
    ( cd "$(dirname "$a")" && sha256sum -c "$(basename "$a").sha256" ) && ok "checksum matches"
  fi
  say "top-level entries"
  zstd -dc "$a" | tar -tf - 2>/dev/null | awk -F/ '{print $2"/"$3}' | sort -u | head -30
  say "totals"
  printf '  entries: %s\n' "$(zstd -dc "$a" | tar -tf - 2>/dev/null | wc -l)"
  [[ -f "$a.manifest.txt" ]] && sed 's/^/  /' "$a.manifest.txt"
}

# ---------------------------------------------------------------- restore
cmd_restore() {
  need tar; need zstd
  local a="" with_system=0 install_pkgs=0 rootfs=0
  local SUDO=""; (( $(id -u) == 0 )) && SUDO="" || SUDO="sudo -n"
  for arg in "$@"; do
    case "$arg" in
      --with-system)      with_system=1 ;;
      --install-packages) install_pkgs=1; with_system=1 ;;
      --rootfs)           rootfs=1; with_system=1 ;;
      -*) die "unknown flag: $arg" ;;
      *)  a="$arg" ;;
    esac
  done
  a="$(resolve_archive "$a")"

  # ---- 0. whole-rootfs clone: lay it back over / inside a fresh container
  if (( rootfs )); then
    (( $(id -u) == 0 )) || have_sudo || die "--rootfs needs root"
    say "restoring whole rootfs from $a onto / (this overwrites /usr /opt /etc)"
    zstd -dc "$a" | $SUDO tar -xf - -C / --numeric-owner \
        --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
        --exclude='./etc/machine-id' --exclude='./etc/hostname' --exclude='./etc/hosts' \
        --exclude='./etc/resolv.conf'
    $SUDO ldconfig 2>/dev/null || true
    ok "rootfs restored — restart the container/desktop session"
    return 0
  fi

  local stage; stage="$(mktemp -d /tmp/restore.XXXXXX)"
  say "extracting $a"
  zstd -dc "$a" | tar -xf - -C "$stage" --numeric-owner \
      --exclude='./etc/machine-id' --exclude='./etc/hostname' --exclude='./etc/hosts' \
      --exclude='./etc/resolv.conf' --exclude='./etc/ld.so.cache'

  # ---- 1. home (always)
  if [[ -d "$stage/config" ]]; then
    say "restoring home → $HOME_DIR"
    shopt -s dotglob nullglob
    for item in "$stage/config"/*; do
      cp -a "$item" "$HOME_DIR"/ 2>/dev/null || say "  skipped $(basename "$item") (busy)"
    done
    shopt -u dotglob nullglob
    if [[ "$(id -u)" == 0 ]]; then chown -R "$(id -u):$(id -g)" "$HOME_DIR"; 
    elif have_sudo; then sudo -n chown -R "$(id -u):$(id -g)" "$HOME_DIR" 2>/dev/null || true; fi
    ok "home restored"
  fi

  # ---- 2. system (opt-in)
  if (( with_system )); then
    (( $(id -u) == 0 )) || have_sudo || die "--with-system needs root/sudo"
    local SUDO="sudo -n"; (( $(id -u) == 0 )) && SUDO=""
    if (( install_pkgs )) && [[ -f "$stage/meta/apt-manual.txt" ]]; then
      say "reinstalling apt packages ($(wc -l < "$stage/meta/apt-manual.txt") manually-installed)"
      $SUDO apt-get update -qq || true
      xargs -a "$stage/meta/apt-manual.txt" $SUDO apt-get install -y --no-install-recommends || say "  some packages failed (see above)"
      ok "apt pass done"
    fi
    for d in etc opt usr/local var/lib/flatpak var/spool/cron; do
      [[ -d "$stage/$d" ]] || continue
      say "restoring /$d"
      $SUDO mkdir -p "/$d"
      case "$d" in
        etc) $SUDO cp -a "$stage/etc/." /etc/ 2>/dev/null || say "  partial /etc restore" ;;
        *)   $SUDO cp -a "$stage/$d/." "/$d/" 2>/dev/null || say "  partial /$d restore" ;;
      esac
    done
    [[ -f "$stage/meta/pip-freeze.txt" ]] && say "python deps: pip install -r <(extracted meta/pip-freeze.txt) (run manually if needed)"
    (( install_pkgs )) && { $SUDO ldconfig 2>/dev/null || true; }
    ok "system restore done"
  fi

  # ---- 3. guidance
  cat <<EOF

Restored. Manual follow-ups (fresh sandbox only):
  • log out / restart the desktop session so XFCE + app configs reload
  • if packages were skipped:  xargs -a <meta>/apt-manual.txt sudo apt-get install -y
  • flatpak apps:              flatpak install --from /var/lib/flatpak (or re-add remotes)
  • vendor binaries were excluded unless you used --full (e.g. ~/.deepai-code/tools)
  • staging kept at $stage (delete when happy: rm -rf $stage)
EOF
}

usage() {
  cat <<'USAGE'
desktop-backup.sh — full "copy" of an Ubuntu cloud-desktop sandbox (home + settings + packages)
and a one-command restore for a fresh sandbox / plain Ubuntu desktop.

  ./desktop-backup.sh backup                    # settings + files, no caches/Downloads (~1 min, small)
  ./desktop-backup.sh backup --full             # + caches, Downloads, flatpak, vendor binaries
  ./desktop-backup.sh backup --whole-system     # complete rootfs clone (/usr /opt /etc /config)
  ./desktop-backup.sh list                      # show archives
  ./desktop-backup.sh verify [archive]          # checksum + content preview (default: newest)
  ./desktop-backup.sh restore [archive]                 # data only, into $HOME (portable)
  ./desktop-backup.sh restore [archive] --with-system   # + /etc /opt /usr/local
  ./desktop-backup.sh restore [archive] --with-system --install-packages
  ./desktop-backup.sh restore [archive] --rootfs        # lay a --whole-system clone back onto /

Env: BACKUP_DIR (default /config/backups), LEVEL (zstd level, default 12)
Exit codes: 0 ok, 1 error, 2 usage
USAGE
  exit 2
}

case "${1:-}" in
  backup)  shift; cmd_backup  "$@" ;;
  list)    shift; cmd_list    "$@" ;;
  verify)  shift; cmd_verify  "$@" ;;
  restore) shift; cmd_restore "$@" ;;
  -h|--help|"") usage ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
