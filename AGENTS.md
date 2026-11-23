# AGENTS.md — restore contract

You are an AI agent asked to recreate, on a new machine, the workspace this repo snapshots.
Follow this file literally. Do not improvise file contents: every file is either committed in
this repo or recoverable from a Release asset, and every one has a sha256.

## 0. Ground rules

1. **Read before you write.** `MANIFEST.json` is authoritative. If a file is not in it, it is not
   part of this snapshot — do not invent it.
2. **Never fabricate contents.** If something is missing (a secret, a large binary), say so and
   stop for that item. A placeholder file is worse than a reported gap.
3. **Restore in levels.** Each level is independently useful. Stop at the level you were asked for.
4. **Verify with sha256, not by eye.** `./scripts/restore.sh verify` must pass before you claim success.
5. **Never commit secrets back.** `secrets/` holds an index only. Do not decrypt into the repo tree,
   and never `git add` decrypted material.
6. **Do not overwrite existing user data** on the target machine without an explicit instruction.
   Back up to `*.pre-restore` first (the scripts do this).

## 1. Levels

| level | command | what it does | needs |
|---|---|---|---|
| L0 verify | `./scripts/restore.sh verify` | recompute sha256 of every committed file | nothing |
| L1 dotfiles | `./scripts/restore.sh home` | copies `home/` into `$HOME`, then `inventory/etc/` into `/etc` | nothing |
| L2 packages | `./scripts/restore.sh packages` | reinstalls the dpkg/apt/flatpak/snap set | sudo, network |
| L3 project | `./scripts/restore.sh project` | restores `project/` (the working code) to a target dir | nothing |
| L4 secrets | `./scripts/restore.sh secrets <file.gpg>` | decrypts + applies keys, tokens, `/etc/shadow` | passphrase |
| L5 userdata | `./scripts/restore.sh userdata <file.gpg>` | decrypts + applies browser/app state, unique media | passphrase |

L4/L5 need the encrypted assets from the **Releases** tab and the passphrase that the owner keeps
outside this repo. Without either, report which level is blocked and continue with L0–L3.

## 2. What the data means

* `home/` mirrors `$HOME` with these exclusions, in order of importance:
  * secrets (`~/.ssh`, `~/.gnupg`, `~/.config/gh`, `~/ssl`, app signing keys) → L4
  * browser profiles and app databases → L5
  * caches (`~/.cache`, `Cache/`, `Code Cache/`, `GPUCache/`, `Service Worker/`) → not backed up
  * package payloads and their contents (`~/.local/share/flatpak`, `squashfs-root/`) → reinstall
  * anything >8 MB → `inventory/bulk.txt`, carried by L5 or refetched
* `inventory/etc/` holds `/etc` files that differ from the base image, captured with `sudo` and
  mirrored at the same relative paths. `inventory/etc-sha256.txt` is its checksum list.
  `inventory/etc-secret-hashes.txt` records the hashes of `shadow`/`gshadow` (contents are in L4).
* `inventory/recent-changes.txt` answers "what was actually touched on that box" — mtimes, sizes,
  paths — and is the fastest way to understand what a human did there.
* `inventory/packages.txt` is both a human list and a reinstall input. Prefer `apt-mark showmanual`
  + the explicit version list over `apt install` of everything dpkg ever recorded.

## 3. Order of operations on a fresh Ubuntu box

```bash
sudo apt update && sudo apt install -y git curl zstd gnupg jq
git clone https://github.com/Zyro164/diddyproject.git ~/restore && cd ~/restore
./scripts/restore.sh verify                 # L0 — proves the clone is intact
./scripts/restore.sh packages               # L2 first: later levels expect the binaries
./scripts/restore.sh home                   # L1
./scripts/restore.sh project ~/work/diddyproject   # L3
# L4/L5 only when the owner provides the passphrase:
./scripts/restore.sh secrets  ./secrets-*.tar.zst.gpg
./scripts/restore.sh userdata ./userdata-*.tar.zst.gpg
```

Then verify the desktop session: `inventory/services.txt` (autostart, desktop entries) and
`inventory/host-config.txt` (apt sources, `/etc/environment`, keyboard, hosts).

## 4. Reporting

Report per level: `restored / skipped / failed` with counts, the sha256 mismatches (if any), and
the exact list of items that needed the passphrase or a re-download. If you had to deviate from
`MANIFEST.json`, say what and why. Do not report success for a level you did not run.

## 5. Refreshing this snapshot (on the source machine)

```bash
./scripts/capture.sh && ./scripts/bundle.sh all && ./scripts/manifest.sh
git add -A && git commit -m "backup: $(date -u +%FT%TZ)" && git push
```
