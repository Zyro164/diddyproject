# secrets/ — index only, no secret bytes

This directory deliberately contains **no secret material**. It documents what was captured into
the encrypted Release asset `secrets-<stamp>.tar.zst.gpg`.

## Why encryption instead of plaintext

The bundle holds live credentials: SSH and GPG key material, the GitHub CLI OAuth token, the app's
account/signing keys, `/etc/shadow` password hashes, and a copy of the shell history. Committing
those to git — even a private repo — means one bad collaborator, one leaked token, one repo
converted to public, and everything is exposed forever in the object history. So: AES-256, one
asset, one passphrase.

## Where the passphrase lives

`/config/backups/.bk.pass` on the source machine (mode 600), generated with `openssl rand -base64 32`.
It is the only copy. Put it in a password manager now; without it the assets are noise.

```bash
# show it once, to copy into your password manager
cat /config/backups/.bk.pass
```

## Decrypt and inspect

```bash
gh release download <tag> --repo Zyro164/diddyproject --dir ./assets
cd assets && sha256sum -c *.sha256
gpg --decrypt secrets-<stamp>.tar.zst.gpg | zstd -dc | tar -tvf - | less   # look, don't write
./scripts/restore.sh secrets ./secrets-<stamp>.tar.zst.gpg                # actually apply
```

## What is inside (see `secrets.manifest.txt` for the live list)

| path | why it is secret |
|---|---|
| `~/.ssh/` | key material and known hosts |
| `~/.gnupg/` | private keys |
| `~/.config/gh/hosts.yml` | the `gho_…` OAuth token |
| `~/ssl/cert.key` | TLS private key |
| `~/.deepai-code/userdata/secrets/` | app signing keys, account blobs, OAuth salts |
| `~/.deepai-code/userdata/account-clients/sessions.sqlite` | login sessions |
| `~/.config/deepai-code-v2/Local Storage/` | bearer tokens in browser storage |
| `/etc/shadow`, `/etc/gshadow` | password hashes (root-owned, restored with sudo) |
| `/etc/ssl/private/` | TLS private keys incl. the snakeoil key (kept out of git since 2026-11-23T02:09Z) |
| `rootfs/bash_history` | full shell history (git only gets a redacted copy) |

## Rules

* Never write decrypted material into this repo; `scripts/restore.sh` extracts to `mktemp -d` and
  deletes it afterwards.
* Rotate the GH token (`gh auth refresh`) after restoring onto an untrusted machine.
* To re-key: generate a new passphrase, repack with `scripts/bundle.sh`, delete the old asset.
