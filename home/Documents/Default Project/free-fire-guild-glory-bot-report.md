# The "Free Fire Guild Glory Bot" Phenomenon

**A deep-research report on the automation/boosting market around Garena Free Fire guild glory**

Prepared: 22 November 2026 · Research method: official Garena documentation, vendor sites, public GitHub repositories, community/scam-warning coverage, domain/trust signals.

---

## 1. Executive summary

"Guild Glory Bot" is not a product category Garena has ever shipped. It is a **grey-market label** covering three different things that get sold under one name:

1. **Paid boosting services** — you hand over your Guild ID (and sometimes account credentials); an operator runs a farm of throwaway "guest" accounts that join your guild, generate glory, and are then discarded.
2. **Leaked/reverse-engineered bot code** — Python projects on GitHub that speak Free Fire's TCP protocol directly, bypassing the game client.
3. **Pure scams** — Telegram "bot links", APKs, and "glory generators" that collect money, credentials, or install malware, and deliver nothing.

**Bottom line:** the technical capability is real (the protocol-level bots genuinely exist and roughly work), but the *commercial* claims around it are not credible, and the risk is concentrated on the buyer. You are the guild leader. If Garena acts, it is **your guild that gets its activeness wiped or is permanently disbanded**, and **your account/device that carries the ban** — not the vendor's. Every vendor claim I could test fails an economic sanity check by two to four orders of magnitude.

**Recommendation:** do not buy. If you want glory, the legitimate levers (member activity, guildmate squads, diamond top-ups, event participation) are slower but the only ones that don't put a permanent-ban asset at risk.

---

## 2. What is actually being sold

### 2.1 The three product shapes

| Shape | What you give up | What you get | Reality |
|---|---|---|---|
| **Guild-ID-only service** (e.g. ffglory.in, guildglory.com) | Guild ID, payment via UPI/Telegram | Vendor's guest accounts join your guild and farm | Plausible delivery, implausible volume; guild bears all enforcement risk |
| **Account/credential service** | Login, sometimes OTP | "Your account plays 24/7" | Highest scam surface; credential theft is the standard outcome |
| **"Bot APK / bot link / generator"** | APK install or Telegram auth | "Unlimited glory" | Overwhelmingly fraudulent; malware or data harvesting |

### 2.2 The marketing vocabulary

Vendors converge on an identical script: "4 bots", "OB55 bypass", "zero bans", "24/7 uptime", "auto-refund if 0 glory", region lists (IND/BD/ME/US), and a Telegram handle as the only support channel. The convergence is itself informative — these are resellers of the same underlying leaked toolkit, not independent R&D shops.

Notable self-inflicted tells:

- **guildglory.com** renders "Trusted by **0+** Free Fire players" in its hero section — an unfilled template placeholder on a site asking for money.
- **ffglory.in** claims simultaneously "1.2B+ glory delivered" / "10M+ glory delivered" and "120K+ clans" / "3.1M+ players" across different sections of the same page.
- **ff-glory.xyz** sells "₹100 for 2 lakh glory" — the single most economically absurd offer in the set.

---

## 3. How guild glory actually works (official mechanics)

Garena's Guilds FAQ is the authoritative source, but it is visibly stale (it still states a guild caps at **level 4**, while the live game has gone far past that). Treat the FAQ as correct on *rules of accumulation* and unreliable on *level tables*.

**Glory accrual (FAQ):**
- Glory is awarded at the **end of Classic Squad and Clash Squad matches**, scaled by placement.
- Playing **with guildmates** is explicitly incentivised — roughly **4 glory** per qualifying match.
- There is a **personal daily cap** (documented as **80 glory/day**).
- The **guild's daily glory cap scales with maximum member count**.
- **1 glory per 10 diamonds** can be bought via top-up — this is the only "purchase glory" path Garena sanctions, and it is the benchmark that destroys vendor pricing.
- **Leaving a guild resets personal glory** — which is why boosting services need *their* accounts inside *your* guild, not yours.

**Guild System 2.0 (OB42) changes that matter:**
- Guild **level is dynamic**, driven by **weekly Activity Points**, with a **weekly deduction** to maintain level — a guild that stops producing *falls back down*.
- Settlement runs **Monday 04:00**.
- **Guild Wars** run in Battle Royale with same-guild squads; only the **top 5 match scores** per guild count toward the weekly total.
- Weekly **Guild Glory Titles** are issued from the leaderboard.

**Why this architecture is hostile to bots:** the caps are *per member per day* and *per guild per day*, and the top-5-scores rule means volume alone doesn't scale Guild Wars output. A bot farm can inflate the "matches played" axis but slams into the daily caps on the "glory earned" axis almost immediately.

---

## 4. Technical anatomy of the bots

The public code is consistent across repositories, which tells us it descends from a small number of leaked/cracked bases.

### 4.1 Stack

- **Transport:** raw **TCP sockets** to Garena game servers — no game client, no emulator.
- **Serialisation:** **Protocol Buffers** (`.pb2` modules checked in, often with mangled/obfuscated filenames like `DEcwHisPErMsG_pb2`, `MajoRLoGinrEs_pb2`).
- **Crypto:** **AES-256** with **hard-coded key and IV** committed to the repo. One project ships `main_key: "Yg&tc%DEuh6%Zc^8"`, `main_iv: "6oyZDr22E3ychjM%"`.
- **Auth:** **guest accounts** via `connect.garena.com/oauth/guest/token/grant`, then `MajorLogin` against region endpoints (`loginbp.ggblueshark.com`, `client.ind.freefiremobile.com`).
- **Hosting:** Termux on Android, cheap VPS, or "cloud" — the READMEs assume a phone.

### 4.2 The farm loop

The cycle, reconstructed from `app.py` and `clan_glory_bot.py`:

1. Authenticate 4+ guest accounts (the number matters — squad size).
2. **Auto-join** the target guild by Guild ID.
3. Form a squad, queue **Clash Squad**.
4. Send a **"start match"** packet, then **immediately leave** — the match is never played.
5. Repeat on a short timer (~23 seconds per cycle in the fastest variant).

The exploit is not "winning fast." It is **farming the match-completion credit without playing the match** — a server-trust bug, not a skill or AI achievement. That distinction matters legally and for enforcement: it is precisely the "bug abuse / unauthorised data modification" category Garena's Abuse Policy names.

### 4.3 What the code actually does *besides* glory

This is the part buyers never read. Cloning and grepping two of the more popular repos turned up functionality that has nothing to do with guilds:

- Instagram profile scraping and **mass-like / mass-request** endpoints (`i.instagram.com/api/v1/users/web_profile_info`, a `Likes`/`send_likes` module).
- Third-party "AI chat" endpoints (`aashish-ai-api.vercel.app/ask`).
- A **ban-check API** (`mossa-api.vercel.app/check_banned?player_id=…`).
- **UID collection endpoints** on Azure (`…azurewebsites.net/Uids`, `…/ReQuesT`) that the client posts to.
- Player-info and clan-info scrapers on assorted Vercel deployments.

In other words: the "free" bot is a **frankenstein of copy-pasted modules that phones home to third-party servers with your identifiers**. The presence of a dedicated UID-upload endpoint in a "guild bot" is not an accident of architecture — it is the business model of the free tier. The paid vendors are the same code with the serial numbers filed off.

### 4.4 Repo landscape

| Repository | Signal |
|---|---|
| `subhajit-maji/free-fire-guild-bot-tcp` | ~32★ / 34 forks, claims OB55, README carries an explicit "may violate ToS, use at your own risk" disclaimer — the disclaimer is the honest part |
| `akcreater06-star/Free-Fire-Guild-Glory-bot` | 10★/10 forks, no licence, no description, duplicated tree (`/XR-GLORY`) |
| `baisavitha35-boop/FreeFireClanBot` | Documented "automated Clash Squad exploit", 4 guests, ~200 cycles / 76 min, regions BD/IND/US/ME; hard-coded keys |
| `ISMAILdz13/FreeFireClanBot` (original) | Returns 404 — removed or made private, consistent with takedown or operator exit |

The recurring pattern: **star/fork counts in the tens, created 2026, never licensed, frequently deleted.** This is not a mature software ecosystem; it is a rotating set of throwaway repos.

---

## 5. The market: vendors, pricing, claims

| Vendor | Price points | Volume claim | Notable |
|---|---|---|---|
| **ffglory.in** | ₹95–₹100 starter | "1.2B+" / "10M+" glory; "120K+ clans"; 14 regions | "100% account safe", "zero bans", Guild ID only; ScamAdviser rates trust "fair" (weak positive, not an endorsement) |
| **guildglory.com** | ₹100 basic / ₹200 premium | 4 bots, 8–12h runs | "0-glory auto-refund after 2h"; operator "B25", sister site `b25cheats.fun`; Telegram `@Amit1y`; "Trusted by 0+ players" |
| **ff-glory.xyz** | ₹100 | **2 lakh (200,000) glory** | Claims OB55 bypass; Telegram `@kartik_cheat1` |

All three route payment to **personal UPI handles or Telegram**, issue **no invoice**, and offer **no chargeback path**. None publishes a legal entity, address, or company registration. RDAP/WHOIS lookups for all three domains returned nothing usable (privacy-shielded or registry-blocked), so **ownership cannot be independently verified** — which is itself a finding.

---

## 6. The math that breaks the business model

### 6.1 Against the sanctioned diamond rate

Garena's own conversion is **1 glory per 10 diamonds**.

- 200,000 glory ⇒ **2,000,000 diamonds**.
- At roughly ₹0.8–₹1 per diamond in the Indian store, that is **₹16–20 lakh (~$19,000–24,000)**.
- `ff-glory.xyz` charges **₹100**.

That is a **~4 order-of-magnitude gap**. Either the vendor has found an exploit worth millions per week (in which case they would not be retailing it at ₹100 on a `.xyz` domain), or the glory does not arrive.

### 6.2 Against the caps

Under normal rules, a 4-bot farm running 8 hours:

- 4 bots × ~30 matches/hour × 8h × ~10 glory ≈ **9,600 glory** — before caps.
- The **personal daily cap (80)** and the **guild daily cap (scaled to member count)** bind long before that number is reached.

Exploit cycles raise throughput by skipping the match, but they do not repeal the caps. Delivering 200K glory in a week would require the caps to be effectively non-existent — which contradicts the FAQ and would itself be a bug so severe that Garena would patch it, not tolerate it for months across a dozen vendors.

### 6.3 The refund clause is the tell

"Auto-refund if 0 glory after 2 hours" is carefully constructed: it pays out only in the **total-failure** case. Partial delivery — 3,000 glory instead of 200,000 — triggers no refund, and by then you have paid, your guild has been touched by flagged accounts, and the Telegram handle can block you.

---

## 7. Scam and security patterns

Community coverage (Free Fire Keeda's 2026 guide, creator tests such as "Oz Gaming") converges on a standard playbook:

1. **Fake proof.** Edited leaderboard screenshots, screen-recordings of *someone else's* guild, "before/after" with mismatched UI versions.
2. **Payment fraud.** UPI to a personal handle, then "payment not received, send again", then block. No recourse — UPI transfers are not reversible and there is no merchant dispute process.
3. **Credential/OTP theft.** The "login to activate" step is the whole point; OTP forwarding is the standard mechanism.
4. **Malicious APK.** Sideloaded "bot APK" with SMS/notification access, overlay permissions, or banking trojans.
5. **Data harvesting.** As documented in §4.3, even the "legitimate" free bots exfiltrate UIDs and identifiers to third-party endpoints.
6. **Bait-and-switch to cheats.** Once you are in the Telegram, you are sold "cheats" (aimbot, wallhack) — a category with *guaranteed* permanent bans.
7. **Guild hijack.** If you hand over leader/officer access "to add the bots", the guild itself can be stolen or disbanded.

---

## 8. Garena's rules and enforcement

This is the section that actually decides the question.

**Abuse Policy** explicitly prohibits unauthorised programs, packet/data modification, and bug abuse. Critically, it contains a dedicated **"Coordinated Unfair Play for Guilds"** clause permitting Garena to:

- remove **Guild Activeness** and **Guild War points**,
- **disqualify** the guild from leaderboards,
- and **permanently disband** the guild.

That clause exists *because* of this exact market. It is not theoretical language; it is a targeted sanction written for guild-level automation.

**Anti-Hack FAQ** states:

- **Zero tolerance**; a **permanent ban on the first offence**.
- **Device-level bans**, not just account bans.
- **No appeals**.
- Third-party software is defined to include reverse engineering, decompiling, and defeating encryption — which is a precise description of what these repos do with `.pb2` files and AES keys.
- Garena acknowledges the **guest-account loophole** (guest accounts are disposable, which is why vendors use them) — and the guild-level sanction exists precisely to make the loophole unprofitable.

**Net risk allocation:** the vendor risks a throwaway guest account. You risk a **permanent, non-appealable account and device ban**, plus **total loss of a guild you may have spent years building**. The asymmetry is total.

---

## 9. Risk matrix (for a guild leader)

| Risk | Likelihood | Severity | Notes |
|---|---|---|---|
| Money lost, no/partial delivery | High | Medium | No chargeback, Telegram-only support |
| Guild activeness wiped / leaderboard DQ | Medium–High | High | Explicitly enumerated sanction |
| Guild permanently disbanded | Medium | Critical | Explicitly enumerated sanction |
| Your account banned (permanent, no appeal) | Medium | Critical | If you ever log in from a flagged device/IP cluster |
| Device ban | Low–Medium | Critical | Affects all accounts on the handset |
| Credential/OTP theft | Medium (credential tier) | Critical | Standard outcome of "login to activate" |
| Malware from APK | Medium (APK tier) | High | Sideloaded, unvetted |
| Data harvesting of UIDs/identifiers | High | Low–Medium | Confirmed in repo code |
| Guild theft via officer access | Low–Medium | High | "Add the bots as officers" |

---

## 10. Legitimate alternatives

If the goal is glory and guild level, the sanctioned levers are unglamorous but compounding:

1. **Fill the roster.** The guild daily glory cap scales with **maximum member count** — recruiting is literally a glory multiplier.
2. **Squad with guildmates.** The ~4-glory guildmate bonus is the single highest-leverage behaviour; organise fixed squads rather than solo queues.
3. **Play Clash Squad for volume.** Short matches, consistent placement credit.
4. **Protect the weekly reset.** Guild level now decays without weekly Activity Points; a dead week costs you a level, and re-levelling costs more than maintaining.
5. **Guild Wars discipline.** Only the **top 5 scores** count — concentrate your strongest squads rather than spreading thin.
6. **Diamond top-up, sparingly.** 1 glory / 10 diamonds is the *only* sanctioned purchase path; use it as a benchmark, not a strategy (it is deliberately expensive).
7. **Events and dog-tag windows.** Time-limited guild tournaments aggregate member dog tags; a coordinated push during the window outperforms passive play.
8. **Recruit, don't buy.** Merging with another active guild is the fastest legitimate route to a high-level roster.

---

## 11. How to evaluate any "guild glory" offer

A five-minute checklist that filters essentially all of them:

1. **Is there a legal entity?** Company name, registration number, address, GST/VAT. None of the reviewed vendors has one.
2. **Is payment reversible?** Card/PayPal with buyer protection = arguable. UPI to a personal handle = no.
3. **Does the claim survive arithmetic?** Compare glory promised against 1 glory / 10 diamonds and against the 80/day personal cap.
4. **Do they want credentials or OTP?** Instant disqualification.
5. **Do they want officer/leader access?** Instant disqualification.
6. **Is proof independently verifiable?** A live guild ID you can inspect in-game beats any screenshot.
7. **Is there a refund path that covers partial delivery?** "0 glory only" is a red flag, not a guarantee.
8. **Domain age and history.** New `.xyz`/`.in` domains with no archive history and privacy-shielded WHOIS are disposables.

---

## 12. Confidence and open questions

**High confidence:** no official bot exists; the protocol bots are real and exploit match-credit, not skill; Garena's Abuse Policy contains a guild-specific sanction including permanent disbandment; the economics of the advertised volumes do not work; the public repos contain unrelated data-harvesting and spam modules.

**Medium confidence:** the exact current daily caps (FAQ says 80/day and a member-scaled guild cap, but the FAQ is stale on levels); the precise per-match glory values post-OB42; whether Garena is currently running guild-level enforcement sweeps at scale (the policy exists; public evidence of mass disbandment is anecdotal).

**Low confidence / unverified:** vendor ownership and revenue; whether any vendor has ever delivered a large order; the true current OB version the repos target (claims range OB54–OB55).

**What would change the conclusion:** a vendor publishing a legal entity, a verifiable live guild with audited glory deltas over 30 days, and a card-based refundable payment path — plus Garena explicitly licensing third-party guild analytics. None of that exists today.

---

## 13. Sources

- Garena Free Fire Help Center — **Guilds FAQ** (glory rules, caps, diamond conversion): `ffsupport.garena.com` → Guilds FAQ
- Garena Free Fire Help Center — **Abuse Policy** (incl. "Coordinated Unfair Play for Guilds")
- Garena Free Fire Help Center — **Anti-Hack FAQ** (permanent bans, device bans, no appeals)
- Garena Free Fire Help Center — **Game Security FAQ**
- Garena Free Fire — **OB42 patch notes, Guild System 2.0** (dynamic levels, weekly settlement, Guild Wars top-5 rule)
- `https://github.com/subhajit-maji/free-fire-guild-bot-tcp`
- `https://github.com/akcreater06-star/Free-Fire-Guild-Glory-bot`
- `https://github.com/baisavitha35-boop/FreeFireClanBot`
- `https://ffglory.in`
- `https://guildglory.com`
- `https://ff-glory.xyz`
- Free Fire Keeda — *"Guild Glory Bot Free Fire, Is It Real or a Scam? (2026 Guide)"*: `https://freefirekeeda.co.in/guide/guild-glory-bot`
- ScamAdviser trust reports for the three vendor domains (ffglory.in rated "fair"; all three flag as low-history/yellow)
- Community creator tests (e.g. "Oz Gaming") reporting non-delivery

*Vendor figures are quoted as claims, not facts. Prices and claims were captured in November 2026 and change frequently.*
