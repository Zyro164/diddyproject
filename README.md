# diddyproject — full machine backup

A snapshot of an Ubuntu cloud-desktop workspace, packaged so that **another machine (or another
AI) can rebuild it byte-for-byte**. Everything is either committed here in plain text, or
fingerprinted here and carried as an encrypted Release asset.

| | |
|---|---|
| snapshot taken | see `MANIFEST.json → snapshot.generated_at` |
| source machine | see `inventory/system.txt` |
| git remote | `github.com/Zyro164/diddyproject` (private) |
| encrypted assets | Releases tab of this repo |

## Start here

| file | for |
|---|---|
| `AGENTS.md` | **read this first if you are an AI** — the restore contract, levels, and rules |
| `RESTORE.md` | step-by-step human runbook |
| `MANIFEST.json` | machine-readable index: every file, size, sha256, and where it lives |
| `inventory/` | machine facts, package lists, services, `/etc` snapshot, change report |
| `home/` | dotfiles and configs from `$HOME` (secrets and bulk data removed) |
| `project/` | the original working project (scripts, generated HTML pages, a `.deb`) |
| `secrets/` | index of secret-bearing paths — **contents are encrypted, never committed** |
| `scripts/` | `capture.sh` (refresh), `bundle.sh` (encrypt + upload), `restore.sh` (apply) |

## What is where (and why)

1. **Plain text → git.** Dotfiles, configs, scripts, sources, package lists, `/etc` contents,
   checksums. Small, diffable, and readable by any agent without a passphrase.
2. **Secrets → encrypted Release asset.** SSH/GPG material, `gh` token, app signing keys,
   `/etc/shadow`, browser profiles, agent/collab state. AES-256 (gpg symmetric), uploaded with
   `scripts/bundle.sh`, decryptable only with the passphrase.
3. **Big binaries → manifest only.** Installers (`*.deb`, AppImage, the `gh` static binary) are
   public and re-downloadable; `inventory/bulk.txt` records their sha256 so a refetched copy can
   be proven identical.
4. **Anything over 100 MB cannot live in git.** Git rejects individual files >100 MB. That is why
   Release assets exist here, and why `inventory/bulk.txt` matters.

## Restore in one line

```bash
git clone https://github.com/Zyro164/diddyproject.git && cd diddyproject
./scripts/restore.sh verify          # check every committed file against MANIFEST.json
./scripts/restore.sh home            # apply dotfiles/configs into $HOME
./scripts/restore.sh packages        # reinstall the recorded package set
./scripts/restore.sh secret <bundle> # decrypt an asset with the passphrase, then apply
```

## Refresh this backup (on the source machine)

```bash
cd /config/diddyproject
./scripts/capture.sh          # re-scan the box → inventory/, home/, secrets/*.manifest.txt
./scripts/bundle.sh all       # repack + upload encrypted assets
./scripts/manifest.sh         # regenerate MANIFEST.json + .sha256sums
git add -A && git commit -m "backup: $(date -u +%FT%TZ)" && git push
```

## Honest limits

* Secret material is only as recoverable as the passphrase in `/config/backups/.bk.pass`
  (or your password-manager copy). No passphrase, no secrets — that is the point of the encryption.
* Browser profiles are captured **without** caches; open tabs survive, cached blobs do not.
* `core` dumps are excluded (huge, and they leak memory contents). Their sha256 is in
  `project/core.sha256` and the dump itself is a Release asset if it ever existed.
* A 5 GB whole-system image from an earlier run lives in the separate
  `Zyro164/sandbox-backup` repo, not here. `RESTORE.md` explains when to reach for it.
