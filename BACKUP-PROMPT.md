# BACKUP-PROMPT.md — the reusable prompt

Copy the block below into a fresh agent session whenever you want this machine backed up again.
It is written to be unambiguous about *searching*, *classifying*, and *verifying*, and to produce a
repo that a different machine and a different AI can restore from without asking anything.

---

```
TASK: Back up this entire machine to GitHub so another machine — and another AI — can rebuild it
exactly. Execute now, no questions. Do not stop at "I can't"; use every fallback available and
report what you could not get.

STEP 1 — DISCOVER (search the whole VM, do not assume)
  a. Map the machine: distro/version, kernel, arch, user(s), sudo rights, disk, CPU/RAM, network,
     package manager(s), desktop environment, running services, cron, autostart.
  b. Inventory $HOME exhaustively (hidden files included). For every path record: size, mtime,
     sha256, owner, mode. Do not skip anything silently; anything you exclude must be listed with
     a reason.
  c. Find what was actually MODIFIED: files under $HOME and /etc newer than the image/base date;
     newly installed vs. base packages (dpkg -l, apt-mark showmanual, snap, flatpak); custom
     scripts, desktop entries, themes, shell history, browser profiles, app data, vhosts, certs.
     Produce a "recent changes" report sorted by time and a "largest consumers" report by size.
  d. Classify every path into exactly one bucket:
       TEXT-CONFIG   small, diffable, no credentials        → commit to git
       SECRET        keys, tokens, cookies, password hashes → encrypt, upload, never commit
       BULK-UNIQUE   user data too big for git (>8MB)       → encrypt, upload, hash in git
       BULK-PUBLIC   installers/AppImages/static binaries   → do NOT upload; record sha256 + URL
       REGENERABLE   caches, node_modules, flatpak payloads → do NOT back up; record the rule
  e. Write down the exact reason for every exclusion, in the repo, in one file.

STEP 2 — REPO
  a. Use an existing repo whose name equals this folder's name; if it exists, update it.
     Otherwise create a NEW PRIVATE repo of that name. Never push to a public repo.
     If the folder is not a git repo, `git init`, set the remote, commit, push.
  b. Layout: README.md (what/how), AGENTS.md (restore contract for an AI), RESTORE.md (runbook),
     MANIFEST.json (every file: path/size/sha256 + restore levels), inventory/ (facts, packages,
     services, /etc snapshot, change report), home/ (dotfiles), project/ (working code),
     secrets/ (index only), assets/ (packed collections), scripts/ (capture/bundle/manifest/restore).
  c. Respect limits: a single git file over 100 MB will be rejected — encrypt and attach it to a
     Release (2 GB per asset, split if larger) or record it as BULK-PUBLIC. Keep the repo lean.
  d. Never commit credentials. Encrypt them (gpg AES-256, passphrase file at mode 600 outside the
     repo), upload as release assets, commit only an index of what is inside.
  e. Make everything reproducible: scripts that re-capture, re-bundle, re-manifest, and restore.

STEP 3 — VERIFY (no unverified claims)
  a. `sha256sum -c` on every committed file; round-trip decrypt each encrypted bundle and count
     its entries; compare each uploaded asset's remote size with the local file.
  b. Confirm the remote branch head equals local HEAD, and that the repo is private.
  c. Confirm no secret pattern (gho_/ghp_/sk-/PRIVATE KEY/cookies/password hashes) is present in
     the committed tree. Grep for it; fix it if found.
  d. Print a final report: levels restorable, what needs the passphrase, what needs re-downloading,
     what was deliberately excluded and why, plus the exact clone/restore commands.
```
