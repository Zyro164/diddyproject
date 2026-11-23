#!/usr/bin/env bash
# capture.sh — re-scan this machine and refresh the backup repo contents.
#
#   ./scripts/capture.sh            # full capture into ./ (the repo root)
#   ./scripts/capture.sh --no-home  # inventory only (skip copying dotfiles)
#
# Output (all inside the repo root):
#   inventory/   machine facts, package lists, /etc snapshot, change report
#   home/        $HOME dotfiles + configs, secrets and bulk data excluded
#   secrets/     *manifest only* (no secret bytes) — bundles are release assets
#
# Secrets never enter git. See secrets/README.md and scripts/secrets-bundle.sh
set -eu   # no pipefail: `| head` would abort the capture with SIGPIPE

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME_DIR:-/config}"
CAPTURE_HOME=1
[[ "${1:-}" == "--no-home" ]] && CAPTURE_HOME=0

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m  ok\033[0m %s\n' "$*"; }

mkdir -p "$REPO"/{inventory,home,secrets}

# ---------------------------------------------------------------- inventory
say "inventory: system facts"
{
  echo "# system snapshot — generated $TS"
  echo
  echo "## os-release"; sed 's/^/  /' /etc/os-release 2>/dev/null || true
  echo "## uname";      uname -a
  echo "## hostname";   hostname 2>/dev/null; hostnamectl 2>/dev/null || true
  echo "## user";       id; echo "HOME=$HOME  SHELL=$SHELL  PATH=$PATH"
  echo "## cpu/mem";    nproc; free -h 2>/dev/null || true
  echo "## disk";       df -h 2>/dev/null || true
  echo "## clock";      date -u
  echo "## locale/timezone"; locale 2>/dev/null | head -5; cat /etc/timezone 2>/dev/null || true
  echo "## gpu/mesa";   (glxinfo -B 2>/dev/null | head -12) || true
  echo "## display";    echo "DISPLAY=${DISPLAY:-} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-} DESKTOP_SESSION=${DESKTOP_SESSION:-}"
  echo "## env (names only, values withheld)"
  env | cut -d= -f1 | sort | sed 's/^/  /'
} > "$REPO/inventory/system.txt"

say "inventory: users and groups"
{ echo "# users"; getent passwd; echo; echo "# groups"; getent group;
  echo; echo "# sudoers"; sudo -n cat /etc/sudoers 2>/dev/null | grep -v '^#' | grep -v '^$' || true;
  echo; echo "# sudoers.d"; sudo -n ls -l /etc/sudoers.d 2>/dev/null || true;
} > "$REPO/inventory/users.txt" 2>&1

say "inventory: packages"
{ echo "# dpkg (ii only)"; dpkg -l 2>/dev/null | awk '/^ii/{print $2"\t"$3}';
  echo; echo "# apt-mark showmanual"; apt-mark showmanual 2>/dev/null | sort;
  echo; echo "# snap"; snap list 2>/dev/null || echo "(snap unavailable)";
  echo; echo "# flatpak"; flatpak list --columns=application,version,origin 2>/dev/null || echo "(flatpak unavailable)";
  echo; echo "# appimages / portable binaries in \$HOME";
  find "$HOME_DIR" -maxdepth 3 -type f \( -name '*.AppImage' -o -name '*.deb' -o -name '*.rpm' \) -printf '%s\t%p\n' 2>/dev/null | sort -rn || true;
} > "$REPO/inventory/packages.txt"

say "inventory: services / autostart / cron"
{ echo "# init.d"; ls /etc/init.d 2>/dev/null;
  echo; echo "# systemd units (if any)"; systemctl list-unit-files 2>/dev/null | head -80 || echo "(no systemd in this container)";
  echo; echo "# enabled services"; systemctl list-units --type=service --state=running --no-pager 2>/dev/null || true;
  echo; echo "# crontabs"; sudo -n ls -l /var/spool/cron/crontabs 2>/dev/null || true;
  for u in $(getent passwd | awk -F: '$3>=1000 && $3<65534{print $1}'); do
    echo "## crontab -l $u"; sudo -n crontab -u "$u" -l 2>/dev/null || echo "(none)";
  done;
  echo; echo "# /etc/cron.*"; ls -R /etc/cron.d /etc/cron.daily /etc/cron.hourly 2>/dev/null || true;
  echo; echo "# XDG autostart"; ls -1 "$HOME_DIR/.config/autostart" 2>/dev/null || echo "(none)";
  echo; echo "# desktop entries installed in ~/.local/share/applications";
  ls -1 "$HOME_DIR/.local/share/applications" 2>/dev/null || true;
} > "$REPO/inventory/services.txt"

say "inventory: package installers / download hints"
cat > "$REPO/inventory/download-hints.md" <<'MD'
# Re-fetchable binaries (class=refetchable in bulk.txt)

These were removed from git because of size. Re-download them instead of restoring bytes.

| artifact | where it came from |
|---|---|
| `brave-browser_*_amd64.deb` | https://github.com/brave/brave-browser/releases (or `sudo apt install brave-browser`) |
| `opencode-desktop-linux-amd64.deb` | https://opencode.ai / the app's release page |
| `DeepAI-Code-*_x86_64.AppImage` | the DeepAI Code release page |
| `.local/bin/gh` | https://github.com/cli/cli/releases/latest (static binary) |
| `picom_*_amd64.deb` | Ubuntu archive: `apt-get download picom` |

If a release asset named `userdata-*.tar.zst.gpg` exists on this repo, unique (non-installer)
files are also archived there — verify with the sha256 in `inventory/bulk.txt`.
MD

say "inventory: /etc snapshot"
mkdir -p "$REPO/inventory/etc"
# files changed since the image base date (2026-01-01 is safely after image build)
sudo -n find /etc -type f -newermt '2026-01-01' 2>/dev/null | sort > "$REPO/inventory/etc-modified.txt"
: > "$REPO/inventory/etc-sha256.txt"
while read -r f; do
  rel="${f#/}"                      # etc/...
  # secrets stay out of git
  case "$f" in
    /etc/shadow|/etc/gshadow|/etc/shadow-|/etc/gshadow-|/etc/security/opasswd) continue ;;
    /etc/ssl/private/*) continue ;;   # TLS keys are SECRET-class: encrypted bundle only
  esac
  if sudo -n test -f "$f" && sudo -n test -r "$f"; then
    mkdir -p "$REPO/inventory/$(dirname "$rel")"
    sudo -n cat "$f" > "$REPO/inventory/$rel" 2>/dev/null || true
    sudo -n sha256sum "$f" 2>/dev/null | sed "s|$f|$rel|" >> "$REPO/inventory/etc-sha256.txt" || true
  fi
done < "$REPO/inventory/etc-modified.txt"
sudo -n sha256sum /etc/shadow /etc/gshadow /etc/security/opasswd 2>/dev/null \
  | sed "s|/etc/|etc/|" > "$REPO/inventory/etc-secret-hashes.txt" || true

say "inventory: change report (what was touched on this box)"
{
  echo "# Files under \$HOME modified in the last 14 days, largest first"
  echo "# (caches, browser profiles and package payloads excluded)"
  find "$HOME_DIR" -xdev -type f -mtime -14 -size +0 \
    -not -path '*/.cache/*' -not -path '*/.git/*' \
    -not -path '*/.config/chromium*' -not -path '*/.config/BraveSoftware/*' \
    -not -path '*/.local/share/flatpak/*' -not -path '*/.local/share/Trash/*' \
    -not -path '*/.deepai-code/tools/*' \
    -printf '%TY-%Tm-%Td %TH:%TM  %10s  %p\n' 2>/dev/null \
    | sort -r | head -400 || true
} > "$REPO/inventory/recent-changes.txt"

say "inventory: home tree"
{
  echo "# path\tsize_bytes\tmtime"
  find "$HOME_DIR" -xdev -mindepth 1 -maxdepth 4 \
    -not -path '*/.cache/*' -not -path '*/.git/*' -not -path '*/.local/share/flatpak/*' \
    -printf '%p\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort
} > "$REPO/inventory/home-tree.txt"

say "inventory: ffmpeg/apt sources + host config that commonly breaks restore"
{ echo "# /etc/apt/sources.list*"; sudo -n cat /etc/apt/sources.list 2>/dev/null; sudo -n find /etc/apt/sources.list.d -type f -exec echo "## {}" \; -exec cat {} \; 2>/dev/null;
  echo; echo "# /etc/environment"; cat /etc/environment 2>/dev/null;
  echo; echo "# /etc/hosts"; cat /etc/hosts 2>/dev/null;
  echo; echo "# /etc/default/keyboard"; cat /etc/default/keyboard 2>/dev/null;
  echo; echo "# installed browser/desktop binaries"; command -v brave-browser chromium google-chrome code opencode 2>/dev/null || true;
} > "$REPO/inventory/host-config.txt"

# ---------------------------------------------------------------- home copy
if (( CAPTURE_HOME )); then
  say "home: copying dotfiles (secrets + bulk excluded)"
  EXCLUDES=(
    --exclude='./.cache'            --exclude='./.local/share/Trash'
    --exclude='./.local/share/flatpak'
    --exclude='./.config/chromium'  --exclude='./.config/chromium-headless'
    --exclude='./.config/BraveSoftware'
    --exclude='./.config/deepai-code-v2/Partitions'
    --exclude='./.config/deepai-code-v2/IndexedDB'
    --exclude='./.config/deepai-code-v2/Code Cache'
    --exclude='./.config/deepai-code-v2/Cache'
    --exclude='./.config/deepai-code-v2/sentry'
    --exclude='./.config/deepai-code-v2/Local Storage'
    --exclude='./.config/ai.opencode.desktop/cli'
    --exclude='./.config/ai.opencode.desktop/Cache'
    --exclude='./.config/ai.opencode.desktop/Code Cache'
    --exclude='./.config/ai.opencode.desktop/GPUCache'
    --exclude='./.config/ai.opencode.desktop/compile-cache'
    --exclude='./.config/ai.opencode.desktop/logs'
    --exclude='./.config/discord/app-*'   --exclude='./.config/discord/1.*'
    --exclude='./.config/discord/logs'    --exclude='./.config/discord/sentry'
    --exclude='./.config/discord/discord_asset_cache'
    --exclude='./.npm'            --exclude='./.openjfx'
    --exclude='./.tlauncher/bin'  --exclude='./.tlauncher/logs'
    --exclude='./.tlauncher/mojang_jre'
    --exclude='./.local/share/opencode'
    --exclude='./.config/sober'     --exclude='./.config/pulse'
    --exclude='./.deepai-code'      --exclude='./.dbus'
    --exclude='./.XDG'              --exclude='./.ICEauthority'
    --exclude='./.sudo_as_admin_successful'
    --exclude='./.ssh'              --exclude='./.gnupg'
    --exclude='./.config/gh'
    --exclude='./ssl'
    --exclude='./core'
    --exclude='./backups'
    --exclude='./diddyproject'
    --exclude='./Downloads/squashfs-root'
    --exclude='*.sock'  --exclude='*.pid'  --exclude='*.lock'  --exclude='*.log'
    --exclude='Singleton*' --exclude='.git'
    # ---- secret-bearing files: they live in the encrypted bundles, never in git
    --exclude='./.bash_history'
    --exclude='Cookies' --exclude='Cookies-journal' --exclude='Trust Tokens*'
    --exclude='Session Storage' --exclude='Local Storage' --exclude='IndexedDB'
    --exclude='Login Data*' --exclude='Web Data*' --exclude='Local State'
    --exclude='Network' --exclude='key4.db' --exclude='cert9.db' --exclude='pkcs11.txt'
    --exclude='*.dmp' --exclude='*.key' --exclude='*.pem'
    --exclude='./.local/share/pki'
    # ---- regenerable caches under any profile (gotcha 9)
    --exclude='DawnGraphiteCache' --exclude='DawnWebGPUCache' --exclude='GPUCache'
    --exclude='GrShaderCache' --exclude='ShaderCache' --exclude='Crashpad'
    --exclude='component_crx_cache' --exclude='GPUPersistentCache'
    --exclude='icon-theme.cache' --exclude='./.local/share/gvfs-metadata'
  )
  ( cd "$HOME_DIR" && tar -cf - "${EXCLUDES[@]}" . 2>/dev/null ) \
    | ( cd "$REPO/home" && tar -xf - 2>/dev/null ) || true
  # app-profile GPU/shader/browser caches are REGENERABLE — never user data. Prune them
  # from the staged tree (older snapshots tracked a few; tar alone cannot delete).
  rm -rf "$REPO"/home/.config/*/Dawn*Cache \
         "$REPO"/home/.config/*/GPUCache \
         "$REPO"/home/.config/*/GrShaderCache \
         "$REPO"/home/.config/*/ShaderCache \
         "$REPO"/home/.config/*/Crashpad \
         "$REPO"/home/.config/*/GPUPersistentCache \
         "$REPO"/home/.config/*/component_crx_cache \
         "$REPO"/home/.config/*/'Cache' \
         "$REPO"/home/.config/*/'Code Cache' \
         "$REPO"/home/.config/*/'Service Worker' \
         "$REPO"/home/.config/*/'Shared Dictionary' \
         "$REPO"/home/.config/*/logs \
         "$REPO"/home/.config/*/sentry \
         "$REPO"/home/.config/*/discord_asset_cache \
         "$REPO"/home/.local/share/gvfs-metadata
  find "$REPO/home" -name 'icon-theme.cache' -delete 2>/dev/null || true
  # never keep empty junk dirs in git
  find "$REPO/home" -type d -empty -delete 2>/dev/null || true

  # ---- size policy: nothing >8 MB stays in git; it is fingerprinted here and
  # ---- carried either by an encrypted release asset (unique data) or re-fetched (binaries).
  say "home: pruning files >8 MB out of git (fingerprinted in inventory/bulk.txt)"
  BULK="$REPO/inventory/bulk.txt"
  {
    echo "# Files too large for git. sha256 lets you prove a refetched/recovered copy is identical."
    echo "# class=refetchable ⇒ public installer, re-download it (URL hint below when known)"
    echo "# class=unique      ⇒ personal data, shipped inside the encrypted userdata bundle"
    echo "# size_bytes  sha256  class  path"
  } > "$BULK"
  while IFS= read -r f; do
    rel="${f#"$REPO/home/"}"
    cls=unique
    case "$rel" in
      *.deb|*.AppImage|*.rpm|*.iso|*.snap|.local/bin/*|*/node_modules/*|*/.git/*) cls=refetchable ;;
    esac
    printf '%s  %s  %s  %s\n' "$(stat -c%s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" "$cls" "$rel" >> "$BULK"
    rm -f "$f"
  done < <(find "$REPO/home" -type f -size +8M -print 2>/dev/null)
  find "$REPO/home" -type d -empty -delete 2>/dev/null || true

  # redacted bash history (secret-looking lines stripped) — full copy is in the secrets bundle
  if [[ -f "$HOME_DIR/.bash_history" ]]; then
    grep -viE '(token|passwd|password|secret|api[_-]?key|gho_|ghp_|sk-|BEGIN [A-Z ]*PRIVATE KEY)' \
      "$HOME_DIR/.bash_history" > "$REPO/home/.bash_history.redacted" || true
  fi
fi

# ---------------------------------------------------------------- safety sweep
say "home: packing huge file collections into single archives"
# Rule: deepest-first; any directory holding more than $PACK_DIR_FILES (default 2000)
# files is packed whole and removed, so icon themes and similar collections stay
# out of git as loose files while the rest of the tree stays diffable.
mkdir -p "$REPO/assets"
: > "$REPO/inventory/bulk-dirs.txt"
PACKED_PREFIXES=""
while IFS= read -r d; do
  [[ -d "$d" ]] || continue
  rel="${d#"$REPO/home/"}"
  skip=0
  for pre in $PACKED_PREFIXES; do
    case "$rel/" in "$pre"/*) skip=1; break ;; esac
  done
  (( skip )) && continue
  n=$(find "$d" -type f 2>/dev/null | wc -l)
  bytes=$(du -sb "$d" 2>/dev/null | cut -f1); bytes=${bytes:-0}
  if (( n > ${PACK_DIR_FILES:-2000} )) || { (( n > 500 )) && (( bytes > 20000000 )); }; then :; else continue; fi
  name="$(printf '%s' "$rel" | sed 's|^\./||' | tr '/' '-' | sed 's|^\.*||')"
  tar -C "$d" -cf - . 2>/dev/null | zstd -19 -T0 -q -c > "$REPO/assets/$name.tar.zst"
  printf '%s  %s  assets/%s.tar.zst\n' \
    "$(sha256sum "$REPO/assets/$name.tar.zst" | cut -d' ' -f1)" "$rel" "$name" \
    >> "$REPO/inventory/bulk-dirs.txt"
  PACKED_PREFIXES="$PACKED_PREFIXES $rel"
  rm -rf "$d"
  ok "$rel ($n files) → assets/$name.tar.zst ($(du -h "$REPO/assets/$name.tar.zst" | cut -f1))"
done < <(find "$REPO/home" -type d -mindepth 1 -print 2>/dev/null \
          | awk -F/ '{print NF"\t"$0}' | sort -rn | cut -f2-)
find "$REPO/home" -type d -empty -delete 2>/dev/null || true

say "home: scanning for anything that still looks like a credential"
{
  echo "# Files kept out of the git tree because they can carry credentials or tokens."
  echo "# Their contents live in the encrypted secrets/userdata release assets."
  find "$REPO/home" -type f \
       -not -path '*/icons/*' -not -path '*/themes/*' \
       \( -iname 'Cookies' -o -iname 'Cookies-journal' -o -iname 'Trust Tokens*' \
       -o -iname 'Login Data*' -o -iname 'Web Data*' -o -iname 'key4.db' -o -iname 'cert9.db' \
       -o -iname '*credential*' -o -iname '*secret*' -o -iname '*token*' \
       -o -iname '*.dmp' -o -iname '*.sqlite' -o -iname '*.sqlite3' -o -iname '*.db' \
       -o -iname '*.ldb' -o -iname '*.key' -o -iname '*.pem' \) -print 2>/dev/null
} > "$REPO/inventory/secrets-sweep.txt"
while IFS= read -r f; do
  case "$f" in \#*|"") continue ;; esac
  rm -f "$f"
done < "$REPO/inventory/secrets-sweep.txt"
find "$REPO/home" -type d -empty -delete 2>/dev/null || true
# the packer must never consume cache dirs even when they cross the file-count rule:
# prune every profile cache class before packing so REGENERABLE data cannot reach git
find "$REPO/home/.config" -maxdepth 2 -type d \( -name 'Cache' -o -name 'Code Cache' \
     -o -name 'GPUCache' -o -name 'Service Worker' -o -name 'Dawn*Cache' \
     -o -name 'GrShaderCache' -o -name 'ShaderCache' -o -name 'Crashpad' \
     -o -name 'GPUPersistentCache' -o -name 'component_crx_cache' \) \
  -exec rm -rf {} + 2>/dev/null || true
find "$REPO/home" -type d -empty -delete 2>/dev/null || true
ok "$(grep -vc '^#' "$REPO/inventory/secrets-sweep.txt" || true) credential-shaped files kept out of git"

# ---------------------------------------------------------------- secrets index
say "secrets: indexing (no contents copied to git)"
{
  echo "# Secret-bearing paths captured into the encrypted bundle."
  echo "# Generated $TS. Contents are NOT in this repo."
  echo "# Size  SHA256  Path"
  for p in "$HOME_DIR/.ssh" "$HOME_DIR/.gnupg" "$HOME_DIR/.config/gh" \
           "$HOME_DIR/ssl" "$HOME_DIR/.deepai-code/userdata" \
           "$HOME_DIR/.config/chromium" "$HOME_DIR/.config/BraveSoftware" \
           "$HOME_DIR/.config/chromium-headless" "$HOME_DIR/.config/deepai-code-v2/Partitions" \
           /etc/shadow /etc/gshadow /etc/ssl/private; do
    [[ -e "$p" ]] || continue
    if [[ -f "$p" ]]; then
      printf '%s\t%s\t%s\n' "$(stat -c%s "$p")" "$(sudo -n sha256sum "$p" 2>/dev/null | cut -d' ' -f1)" "$p"
    else
      printf '%s\t%s\t%s\n' "$(du -sb "$p" 2>/dev/null | cut -f1)" "-" "$p/"
      find "$p" -type f 2>/dev/null | head -50 | sed 's/^/    /'
    fi
  done
} > "$REPO/secrets/secrets.manifest.txt"

say "done: $REPO  (stamp $STAMP)"
