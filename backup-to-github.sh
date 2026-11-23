#!/usr/bin/env bash
# backup-to-github.sh — push encrypted sandbox backups to a private GitHub repo.
#
#   ./backup-to-github.sh init           # create the private repo (once) + commit tooling
#   ./backup-to-github.sh push           # encrypt + upload every archive in $BACKUP_DIR
#   ./backup-to-github.sh push <archive> # just one archive
#   ./backup-to-github.sh list           # show releases / assets on GitHub
#   ./backup-to-github.sh restore <tag>  # download + decrypt + verify a release into $PWD/restore
#
# Why encrypted releases instead of plain git?
#   • git hard-limits files to 100 MB; Release assets allow 2 GB each (split if bigger)
#   • Release assets keep the repo small (no history bloat, no LFS quota burn)
#   • the archive holds SSH/GPG keys, cookies and tokens → AES-256 before it leaves the box
set -euo pipefail

GH="${GH:-/config/.local/bin/gh}"
repo_owner="${GH_OWNER:-Zyro164}"
repo_name="${GH_REPO:-sandbox-backup}"
REPO="$repo_owner/$repo_name"
BACKUP_DIR="${BACKUP_DIR:-/config/backups}"
PASSFILE="${PASSFILE:-$BACKUP_DIR/.bk.pass}"
WORK="$BACKUP_DIR/gh"
SPLIT_SIZE="${SPLIT_SIZE:-1900M}"

say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m  ok\033[0m %s\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_gh() {
  [[ -x "$GH" ]] || GH="$(command -v gh)" || die "gh CLI not found"
  "$GH" auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
}

ensure_pass() {
  if [[ ! -s "$PASSFILE" ]]; then
    umask 077
    openssl rand -base64 32 > "$PASSFILE"
    chmod 600 "$PASSFILE"
    printf '\n\033[33m*** new passphrase generated ***\033[0m\n'
    printf 'It is stored at: %s (mode 600)\n' "$PASSFILE"
    printf 'Copy it into your password manager NOW, then delete/keep the file deliberately.\n'
    printf 'Without it the uploaded backups cannot be decrypted.\n\n'
  fi
  chmod 600 "$PASSFILE"
}

# ------------------------------------------------------------------ init
cmd_init() {
  need_gh
  if "$GH" repo view "$REPO" >/dev/null 2>&1; then
    say "repo already exists: $REPO"
  else
    say "creating private repo $REPO"
    "$GH" repo create "$REPO" --private \
      --description "Encrypted backup of an Ubuntu cloud-desktop sandbox (settings, dotfiles, browser profiles, /etc, package manifests)" >/dev/null
    ok "created https://github.com/$REPO"
  fi
  mkdir -p "$WORK"; cd "$WORK"
  [[ -d .git ]] || git init -q
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$REPO.git"
  cat > README.md <<'MD'
# sandbox-backup

Encrypted, versioned snapshots of an Ubuntu cloud-desktop sandbox.
No plaintext secrets are ever committed: archives are **AES-256 (gpg --symmetric)** and
uploaded as **Release assets** (git refuses files >100 MB, Release assets allow 2 GB each).

## Layout

| where | what |
|---|---|
| Release assets | `*.tar.zst.gpg` (+ `.sha256`), split parts `*.part-aa` … if >1.9 GB |
| repo files | this README, `desktop-backup.sh`, `backup-to-github.sh`, `SHASUMS`, `MANIFESTS/` |

## Restore (on any Ubuntu box with network)

```bash
gh release download <tag> --repo <owner>/sandbox-backup --dir ./restore   # or curl the asset URLs
cd restore && cat desktop-*.tar.zst.gpg.part-* > desktop.tar.zst.gpg      # only if split
sha256sum -c *.sha256
gpg --decrypt desktop.tar.zst.gpg > desktop.tar.zst                       # prompts for passphrase
zstd -dc desktop.tar.zst | tar -t | head                                  # inspect
./desktop-backup.sh restore ./desktop.tar.zst                             # data-only into $HOME
./desktop-backup.sh restore ./desktop.tar.zst --with-system --install-packages
```

## Notes

* Keep the passphrase **outside** the sandbox (password manager). Without it nothing decrypts.
* `--rootfs` restores a `--whole-system` clone over `/`; only do that inside a fresh container
  based on the same image.
* GitHub soft-caps repos around 5 GB and each Release asset at 2 GB — this tool splits large
  archives automatically.
MD
  cp -f "$BACKUP_DIR/desktop-backup.sh" . 2>/dev/null || true
  cp -f "${BASH_SOURCE[0]}" . 2>/dev/null || true
  cat > .gitignore <<'EOF'
*.tar.zst
*.gpg
*.part-*
.bk.pass
gh/
EOF
  git add -A
  git -c user.name="$repo_owner" -c user.email="$repo_owner@users.noreply.github.com" \
      commit -qm "tooling: backup + restore scripts" 2>/dev/null || true
  git push -q -u origin main 2>/dev/null || git push -q -u origin HEAD:main
  ok "tooling pushed to https://github.com/$REPO"
}

# ------------------------------------------------------------------ push
cmd_push() {
  need_gh; ensure_pass
  local a="${1:-}"
  if [[ -z "$a" ]]; then
    mapfile -t archives < <(ls -1t "$BACKUP_DIR"/desktop-*.tar.zst 2>/dev/null)
    (( ${#archives[@]} )) || die "no archives in $BACKUP_DIR (run desktop-backup.sh backup first)"
  else
    archives=("$a")
  fi

  for arch in "${archives[@]}"; do
    [[ -f "$arch" ]] || die "not found: $arch"
    local base; base="$(basename "$arch")"
    local gpg="$arch.gpg"
    if [[ ! -f "$gpg" || "$arch" -nt "$gpg" ]]; then
      say "encrypting $base (AES-256)"
      gpg --batch --yes --quiet --passphrase-file "$PASSFILE" \
          --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
          -o "$gpg" "$arch"
      ok "encrypted → $(basename "$gpg") ($(du -h "$gpg" | cut -f1))"
    else
      say "reusing existing $(basename "$gpg")"
    fi
    ( cd "$(dirname "$gpg")" && sha256sum "$(basename "$gpg")" > "$(basename "$gpg").sha256" )

    # split if a single asset would exceed GitHub's 2 GB cap
    local -a assets=("$gpg" "$gpg.sha256")
    rm -f "$gpg".part-*
    if (( $(stat -c%s "$gpg") > 2000000000 )); then
      say "splitting into ${SPLIT_SIZE} parts (Release asset cap is 2 GB)"
      split -b "$SPLIT_SIZE" -d -a 2 "$gpg" "$gpg.part-"
      rm -f "$gpg"   # keep only parts locally
      local parts; parts=$(ls -1 "$gpg".part-* | wc -l)
      ( cd "$(dirname "$gpg")" && sha256sum "$(basename "$gpg")".part-* > "$(basename "$gpg").parts.sha256" )
      assets=("$gpg".part-* "$gpg.sha256" "$gpg.parts.sha256")
      ok "split into $parts parts"
    fi

    local tag="backup-$(echo "$base" | sed -E 's/^desktop-[^-]+-([0-9]{8}T[0-9]{6}Z)-.*/\1/')"
    local notes="$BACKUP_DIR/$(basename "$arch").manifest.txt"
    say "creating release $tag on $REPO"
    if "$GH" release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
      "$GH" release upload "$tag" "${assets[@]}" --repo "$REPO" --clobber
    else
      "$GH" release create "$tag" "${assets[@]}" --repo "$REPO" \
        --title "Backup $tag" --notes-file "$notes" 2>/dev/null \
        || "$GH" release create "$tag" "${assets[@]}" --repo "$REPO" --title "Backup $tag" \
             --notes "Encrypted sandbox backup $base"
    fi
    ok "uploaded → https://github.com/$REPO/releases/tag/$tag"

    # commit the small metadata so the repo history documents every snapshot
    mkdir -p "$WORK/MANIFESTS"; cd "$WORK"
    cp -f "$notes" "MANIFESTS/$base.manifest.txt" 2>/dev/null || true
    [[ -f "$gpg.sha256" ]] && cp -f "$gpg.sha256" "MANIFESTS/" || true
    [[ -f "$gpg.parts.sha256" ]] && cp -f "$gpg.parts.sha256" "MANIFESTS/" || true
    ( cd MANIFESTS && sha256sum *.sha256 > ../SHASUMS 2>/dev/null || true )
    git add -A
    git -c user.name="$repo_owner" -c user.email="$repo_owner@users.noreply.github.com" \
        commit -qm "snapshot: $base" 2>/dev/null || true
    git push -q origin HEAD:main 2>/dev/null || true
    ok "metadata committed"
  done
}

# ------------------------------------------------------------------ list
cmd_list() {
  need_gh
  "$GH" release list --repo "$REPO" 2>/dev/null || die "cannot list (repo missing? run init)"
}

# ------------------------------------------------------------------ restore
cmd_restore() {
  need_gh
  local tag="${1:-}"; [[ -n "$tag" ]] || die "usage: restore <tag>"
  local dir="${PWD}/restore"; mkdir -p "$dir"
  say "downloading $tag"
  "$GH" release download "$tag" --repo "$REPO" --dir "$dir" --clobber
  cd "$dir"
  local enc; enc="$(ls -1 *.tar.zst.gpg 2>/dev/null | head -1)"
  if [[ -z "$enc" ]]; then
    local first; first="$(ls -1 *.gpg.part-* 2>/dev/null | head -1)"
    [[ -n "$first" ]] || die "no encrypted archive in release"
    enc="$(basename "$first" | sed -E 's/\.part-[0-9]+$//')"
    say "re-joining split parts → $enc"
    cat "$enc".part-* > "$enc"
  fi
  [[ -f "$enc.sha256" ]] && sha256sum -c "$enc.sha256" || true
  say "decrypting (passphrase prompt)"
  gpg --output "${enc%.gpg}" --decrypt "$enc"
  ok "ready: $dir/${enc%.gpg}"
  printf '  next: ./desktop-backup.sh restore %s\n' "$dir/${enc%.gpg}"
}

case "${1:-}" in
  init)    shift; cmd_init    "$@" ;;
  push)    shift; cmd_push    "$@" ;;
  list)    shift; cmd_list    "$@" ;;
  restore) shift; cmd_restore "$@" ;;
  *) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
