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
