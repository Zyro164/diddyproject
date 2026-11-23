# BACKUP-PROMPT.md — the fixed, full prompt

Copy everything inside the block into a fresh agent session. It is the version of the original
prompt that survived contact with reality: every "gotcha" below is something that actually broke
during a real run of this backup, and the instruction exists to stop it happening again.

---

```
ROLE
You are backing up this entire machine to GitHub so another machine — and another AI — can rebuild
it exactly: same files, same bytes, same package versions, same desktop state. Execute now, without
asking questions. Never end a step with "I can't" when a fallback exists; use the fallback and
report it. Before claiming a step succeeded, run the check that proves it.

STEP 1 — DISCOVER (search the whole VM; assume nothing)
  a. Machine: distro + version, kernel, arch, users and sudo rights, disk/RAM/CPU, network,
     package managers (dpkg/apt, snap, flatpak, AppImage), desktop environment, running services,
     cron, XDG autostart, listening ports, installed GUI apps.
  b. Inventory $HOME exhaustively including dotfiles. For every path record size, mtime, sha256,
     owner, mode. Nothing may be skipped silently — every exclusion is written down with a reason.
  c. Find what was actually MODIFIED (this is the point of the exercise, not a side quest):
       - files under $HOME and /etc newer than the image/base date,
       - packages installed beyond the base image (dpkg -l, apt-mark showmanual, snap list,
         flatpak list),
       - themes, icon sets, wallpapers, fonts, shell history, custom scripts, desktop entries,
       - app state: browsers, editors, agent/chat databases, wallets, cert stores,
       - /etc: sources.list*, environment, hosts, keyboard, sudoers.d, nginx, systemd/init units.
     Produce two reports: recent-changes.txt (sorted by time) and largest-consumers.txt (by size).
  d. Diff /etc against a clean base of the same release; copy every differing file to inventory/etc/
     at the same relative path, plus inventory/etc-sha256.txt.

STEP 2 — CLASSIFY every path into exactly one bucket, and write the reason in the repo
  TEXT-CONFIG  small, diffable, no credentials             → commit to git
  SECRET       keys, tokens, cookies, password hashes,
               session DBs, NSS key DBs, shell history    → encrypt, upload, NEVER commit
  BULK-UNIQUE  personal data too big for git (>8 MB)       → encrypt, upload, hash stays in git
  BULK-PUBLIC  installers, AppImages, static binaries      → do NOT upload; sha256 + source URL in git
  REGENERABLE  caches, node_modules, flatpak payloads,
               core dumps                                 → do NOT back up; document the rule

STEP 3 — REPO
  a. If the folder is already a git repo with a remote, push to it. If a repo with the same name
     exists on the account, update it; otherwise create a NEW PRIVATE repo. Never a public one.
     Not a repo yet? git init, add the remote, commit, push.
  b. Layout:
       README.md          what this is, what is where, and why
       AGENTS.md          restore contract written for an AI (levels, rules, order of operations)
       RESTORE.md         human runbook + failure table
       MANIFEST.json      every path: size, sha256, type, plus restore levels and provenance
       .sha256sums        flat checksum list for `sha256sum -c`
       inventory/         system facts, packages, services, /etc snapshot, change reports
       home/              dotfiles and configs (secrets, caches and bulk removed)
       project/           the working code tree
       assets/            packed directories that would otherwise flood git
       secrets/           index ONLY — names, sizes, hashes; never contents
       scripts/           capture / bundle / manifest / restore, all re-runnable
  c. Hard limits: a single file >100 MB is rejected by git. Encrypt it and attach it to a Release
     (2 GB per asset, split into parts if larger) or downgrade it to BULK-PUBLIC. Keep the repo lean
     enough to clone in seconds.

STEP 4 — SECRETS
  a. Encrypt with gpg --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512, passphrase stored
     mode 600 OUTSIDE the repo (e.g. ~/.backup-pass). Upload as Release assets.
  b. Pack in tiers so a small tier can always succeed: secrets-*.tar.zst.gpg (keys, tokens, shadow,
     certs, history) and userdata-*.tar.zst.gpg (browser profiles without caches, app state, unique
     media). Publish each with a .sha256 next to it.
  c. Commit only an index (secrets/secrets.manifest.txt) plus the asset names/sizes/sha256
     (inventory/release-assets.txt) so a restore knows what to ask for.
  d. Report where the passphrase lives, and say plainly that losing it makes those assets useless.

STEP 5 — GOTCHAS THAT BREAK THIS JOB (all observed in practice; handle each explicitly)
  1. Secrets leak through the back door. Plaintext cookies, `Cookies-journal`, `Login Data`,
     `Local Storage/`, `Trust Tokens`, `key4.db` (NSS), `*.pem`/`*.key`, app `.sqlite`/`.db` session
     stores, and an unredacted `.bash_history` are all credentials. Exclude them from the text tree,
     commit a redacted history instead, and then GREP the staged tree for
     `gho_|ghp_|sk-|PRIVATE KEY|access_token` before committing. Fix it if found.
  2. Checksums of untracked files. Build .sha256sums from `git ls-files -s`, never from `find`.
     A file listed but not committed (gitignored, >100 MB, or ignored by a broad `*.deb` rule) makes
     `sha256sum -c` fail on a fresh clone and invalidates the whole backup's credibility.
  3. Symlinks break sha256sum. `sha256sum` follows symlinks; dangling ones error out and their
     entries vanish from the list, so coverage looks complete while 190 files are unverified.
     Hash regular files only; record each symlink's target (plus a hash of the target string) in
     MANIFEST.json as type=symlink.
  4. Stale checksums. Any edit after the manifest is generated desynchronises it. Regenerate last,
     and add a pre-commit hook that reruns the manifest and re-stages it so it cannot drift.
  5. SIGPIPE kills capture scripts. `set -o pipefail` plus `| head -400` aborts the run mid-way with
     exit 141 and half the inventory missing. Drop pipefail in capture paths, or guard every such
     pipeline with `|| true`.
  6. Thousands of tiny files. Icon themes and similar collections blow up the object count and make
     every future diff slow. Pack any directory over ~2000 files (or >500 files and >20 MB) into
     assets/<name>.tar.zst, deepest-first, record its sha256 + restore path in inventory/bulk-dirs.txt,
     and keep the archive name from starting with a dot.
  7. Whole-profile tarballs are a trap. Packing an entire `.local` buries the few interesting files;
     pack leaves, and verify the packed tree restores back to the same paths.
  8. Root-owned files vanish from archives. `tar` run as the normal user silently skips unreadable
     staged files (/etc/shadow). Copy with sudo, `chown -R $(id -u):$(id -g)` the staging dir, then
     pack — and always round-trip: decrypt, list entries, count them.
  9. Caches masquerading as state. `Cache/`, `Code Cache/`, `GPUCache/`, `Service Worker/`,
     `component_crx_cache/`, `Crashpad/` are not user data; exclude them and say so.
 10. Live apps. Close or snapshot-proof running apps before copying their databases (SQLite WAL);
     note in the report what was running during capture.
 11. Regenerable output is not a backup. Renamed/moved project files, `.deb`s you `apt-get download`,
     and AppImages belong in a manifest with a URL — not in the git history.
 12. Claiming success from local state only. The only proof is a FRESH CLONE of the remote:
     clone to /tmp, run the verify command there, confirm remote HEAD == local HEAD, confirm the
     repo is private, and confirm every Release asset's remote size matches the local file.

STEP 6 — VERIFY (run all of it; paste real output)
  a. `sha256sum -c` on the fresh clone: 100% match, no "FAILED open or read", no warnings.
  b. Round-trip each encrypted bundle: decrypt, `tar -t`, count entries; compare remote asset sizes.
  c. Secret grep over the committed tree: clean.
  d. Idempotence: re-run the capture+manifest scripts and confirm the diff is empty or trivial.

STEP 7 — REPORT
  Per restore level: restored / skipped / failed with counts. Then:
  - what needs the passphrase, and where the passphrase is,
  - what needs re-downloading (with URLs + sha256),
  - every deliberate exclusion and its reason,
  - any deviation from this brief and why,
  - the exact clone + restore commands, copy-pasteable.
  Do not report a level as restored if you did not run it.

RESTORE CONTRACT TO SHIP (this is what makes the repo usable by another AI)
  L0 verify    ./scripts/restore.sh verify                  needs nothing
  L1 dotfiles  ./scripts/restore.sh home                    copies home/ → $HOME, inventory/etc/ → /etc
  L2 packages  ./scripts/restore.sh packages [--pinned]     sudo + network
  L3 project   ./scripts/restore.sh project <dest>          nothing
  L4 secrets   ./scripts/restore.sh secrets <asset>         passphrase
  L5 userdata  ./scripts/restore.sh userdata <asset>        passphrase
  Rules for the restoring agent: read MANIFEST.json before writing anything, never fabricate a
  missing file, back up to *.pre-restore instead of overwriting, decrypt into mktemp only, and
  never commit decrypted material back.
```
