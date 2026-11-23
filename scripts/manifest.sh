#!/usr/bin/env bash
# manifest.sh — fingerprint the repo: MANIFEST.json (machine-readable) + .sha256sums
#
#   ./scripts/manifest.sh
#
# Run this last, after capture.sh / bundle.sh, and before committing.
set -eu
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --------------------------------------------------------------- checksums
# Fingerprint exactly what git tracks, and only regular files: sha256sum cannot
# read a symlink whose target was not restored, and a silently dropped entry is
# worse than an explicit one. Symlinks are recorded (target + hash of target) in
# MANIFEST.json instead, so coverage stays complete without false failures.
git ls-files -s -z \
  | while IFS= read -r -d '' rec; do
      mode="${rec%% *}"; rest="${rec#* }"; path="${rest#*$'\t'}"
      case "$path" in MANIFEST.json|.sha256sums) continue ;; esac
      [[ "$mode" == "120000" ]] && continue          # symlink: see MANIFEST.json
      [[ -f "$path" ]] || continue                    # skip vanished/odd entries
      printf '%s\0' "$path"
    done \
  | xargs -0 -r sha256sum > .sha256sums || true
printf '  ok %s files fingerprinted\n' "$(wc -l < .sha256sums)"

# --------------------------------------------------------------- MANIFEST.json
python3 - "$REPO_DIR" "$TS" "$STAMP" <<'PY'
import hashlib, json, os, platform, subprocess, sys
root, ts, stamp = sys.argv[1], sys.argv[2], sys.argv[3]
os.chdir(root)

def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()

def sh(cmd, default=''):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=20).stdout.strip() or default
    except Exception:
        return default

files, links, missing = [], [], []
for rec in sh('git ls-files -s').splitlines():
    meta, _, path = rec.partition('\t')
    mode = meta.split()[0]
    if path in ('MANIFEST.json', '.sha256sums'):
        continue
    if mode == '120000':                      # symlink: record the target it points at
        target = os.readlink(path) if os.path.islink(path) else '(missing)'
        links.append({'path': path, 'target': target,
                      'target_sha256': hashlib.sha256(target.encode()).hexdigest()})
        continue
    if not os.path.isfile(path):
        missing.append(path)
        continue
    files.append({'path': path, 'size': os.path.getsize(path), 'sha256': sha(path)})

# NOTE: MANIFEST.json and .sha256sums cannot hash themselves; they are covered by
# the git commit id in snapshot.commit and by .sha256sums for everything else.

bulk_dirs = []
if os.path.isfile('inventory/bulk-dirs.txt'):
    for line in open('inventory/bulk-dirs.txt'):
        parts = line.split()
        if len(parts) >= 3 and not line.startswith('#'):
            bulk_dirs.append({'sha256': parts[0], 'restore_to': parts[1], 'archive': parts[2]})

swept = []
if os.path.isfile('inventory/secrets-sweep.txt'):
    swept = [l.strip() for l in open('inventory/secrets-sweep.txt')
             if l.strip() and not l.startswith('#')]

bulk = []
if os.path.isfile('inventory/bulk.txt'):
    for line in open('inventory/bulk.txt'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        if len(parts) >= 4:
            bulk.append({'size': int(parts[0]), 'sha256': parts[1], 'class': parts[2], 'path': parts[3]})

etc_modified = []
if os.path.isfile('inventory/etc-modified.txt'):
    etc_modified = [l.strip() for l in open('inventory/etc-modified.txt') if l.strip()]

os_release = {}
for line in open('/etc/os-release'):
    if '=' in line:
        k, v = line.rstrip('\n').split('=', 1)
        os_release[k] = v.strip('"')

m = {
    'schema': 'diddyproject-backup/1',
    'snapshot': {
        'generated_at': ts,
        'stamp': stamp,
        'repo': sh('git remote get-url origin'),
        'commit': sh('git rev-parse HEAD'),
        'branch': sh('git rev-parse --abbrev-ref HEAD'),
        'hostname': sh('hostname'),
        'user': sh('id -un'),
        'home': sh('sh -c "getent passwd $(id -u) | cut -d: -f6"'),
        'os': os_release.get('PRETTY_NAME'),
        'os_id': os_release.get('ID'),
        'os_version': os_release.get('VERSION_ID'),
        'kernel': platform.release(),
        'arch': platform.machine(),
        'cpu_count': os.cpu_count(),
    },
    'restore_levels': {
        'L0': {'cmd': './scripts/restore.sh verify', 'needs': 'nothing'},
        'L1': {'cmd': './scripts/restore.sh home', 'needs': 'nothing', 'source': 'home/, inventory/etc/'},
        'L2': {'cmd': './scripts/restore.sh packages', 'needs': 'sudo + network', 'source': 'inventory/packages.txt'},
        'L3': {'cmd': './scripts/restore.sh project [dest]', 'needs': 'nothing', 'source': 'project/'},
        'L4': {'cmd': './scripts/restore.sh secrets <asset>', 'needs': 'passphrase', 'source': 'Release asset secrets-*.tar.zst.gpg'},
        'L5': {'cmd': './scripts/restore.sh userdata <asset>', 'needs': 'passphrase', 'source': 'Release asset userdata-*.tar.zst.gpg'},
    },
    'release_assets': {
        'secrets':  {'pattern': 'secrets-<stamp>.tar.zst.gpg',  'cipher': 'gpg AES256/SHA512', 'contents': 'ssh, gnupg, gh token, ssl cert key, app signing keys, /etc/shadow, /etc/gshadow, bash_history'},
        'userdata': {'pattern': 'userdata-<stamp>.tar.zst.gpg', 'cipher': 'gpg AES256/SHA512', 'contents': 'browser profiles (no caches), agent/app state, unique files >8MB'},
    },
    'excluded_by_policy': [
        'core dumps (*/core) — huge, leak process memory',
        'caches: ~/.cache, Cache/, Code Cache/, GPUCache/, Service Worker/, component_crx_cache/',
        'package payloads: ~/.local/share/flatpak, Downloads/squashfs-root',
        'installers and static binaries (see inventory/download-hints.md)',
    ],
    'bulk': bulk,
    'bulk_dirs': bulk_dirs,
    'kept_out_of_git_for_credentials': swept,
    'etc_modified': etc_modified,
    'files': files,
    'symlinks': links,
    'missing_at_capture': missing,
}

json.dump(m, open('MANIFEST.json', 'w'), indent=2)
print(f"  ok MANIFEST.json: {len(files)} files, {len(links)} symlinks, {len(missing)} missing, "
      f"{len(bulk)} bulk entries, {len(etc_modified)} modified /etc files")
PY

printf 'done\n'
