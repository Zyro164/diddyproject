# RESTORE.md — runbook

Two questions this answers: *how do I rebuild this box?* and *how do I check a restore actually
worked?* If you are an AI agent, read `AGENTS.md` first — it is the contract; this file is the detail.

## 0. Prerequisites on the new machine

Ubuntu (same major version as `inventory/system.txt`), a user with sudo, and network.

```bash
sudo apt update && sudo apt install -y git curl zstd gnupg jq python3
```

## 1. Get the snapshot

```bash
git clone https://github.com/Zyro164/diddyproject.git ~/restore
cd ~/restore
./scripts/restore.sh verify      # every committed file vs .sha256sums — must pass
./scripts/restore.sh plan        # sizes and what is missing from git
```

## 2. Rebuild, level by level

```bash
./scripts/restore.sh packages                 # L2 — do this first, later levels assume the binaries
./scripts/restore.sh packages --pinned        #   exact recorded versions instead of current
./scripts/restore.sh home                     # L1 — dotfiles, configs, recorded /etc files
./scripts/restore.sh project ~/work/diddyproject   # L3 — the working project
```

`home` never destroys anything silently: a conflicting file is copied to `<name>.pre-restore` first.

## 3. Encrypted levels (L4/L5)

You need the passphrase (`/config/backups/.bk.pass` on the original box, or the password-manager copy)
and the Release assets.

```bash
TAG=$(gh release list --repo Zyro164/diddyproject --limit 1 --json tagName -q '.[0].tagName')
gh release download "$TAG" --repo Zyro164/diddyproject --dir ./assets
cd assets && sha256sum -c *.sha256 && cd ..

./scripts/restore.sh secrets  ./assets/secrets-*.tar.zst.gpg    # keys, tokens, /etc/shadow
./scripts/restore.sh userdata ./assets/userdata-*.tar.zst.gpg   # browser/app state, unique media
```

Both extract to a temp dir, apply, and clean up. Nothing decrypted is left in the repo.

## 4. Prove it worked

| check | expected |
|---|---|
| `./scripts/restore.sh verify` | all committed files match |
| `diff -r home/ ~ ` (spot-check a few subtrees) | identical |
| `sha256sum -c` on any asset you downloaded | OK |
| `dpkg -l \| awk '/^ii/{print $2}' \| sort` vs `inventory/packages.txt` | same set (unless `--pinned` was skipped) |
| `gh auth status` after L4 | logged in as the recorded account |
| `brave-browser --version`, `picom --version`, `python3 -V` | match `inventory/packages.txt` |
| desktop session | `inventory/services.txt` autostart + `inventory/host-config.txt` keyboard/apt sources |
| any bulk file you refetched | sha256 equals `inventory/bulk.txt` |

## 5. When things go wrong

| symptom | cause | fix |
|---|---|---|
| `sha256sum -c` fails on clone | partial clone / LFS-less transfer | re-clone; never restore from a failing clone |
| `apt-get install` cannot find a pinned version | archive moved on | rerun without `--pinned`, then compare versions |
| `gpg: decryption failed: Bad session key` | wrong passphrase | use the exact `.bk.pass` contents, no trailing newline issues |
| `/etc` files not applied | no passwordless sudo | run `sudo -v` first, then rerun `restore.sh home` |
| browser profile restored but no session | cookies are bound to a different machine/time | log in again; the profile is data, not a licence |
| disk full during L5 | bundle expands ~3–4× | need ≥10 GB free before L5 |
| need a whole filesystem image instead | this repo is a *diff-style* backup | use the `desktop-*-whole-system` assets in `Zyro164/sandbox-backup` releases |

## 6. Refreshing the snapshot (source machine)

```bash
cd /config/diddyproject
./scripts/capture.sh                      # inventory/, home/, secrets index
./scripts/bundle.sh all                   # secrets + userdata → release assets
./scripts/manifest.sh                     # MANIFEST.json + .sha256sums
git add -A && git commit -m "backup: $(date -u +%FT%TZ)" && git push
```
