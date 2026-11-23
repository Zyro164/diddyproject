/* Static search index — one entry per section. */
window.SEARCH_INDEX = [
  { p: "index.html", h: "verdict", page: "Overview", t: "What this actually is", d: "A 6,190-account dump, a 30-thread invite bot, a guest-account farm, and Telegram exfiltration.", k: "verdict summary spam farm toolkit native" },
  { p: "index.html", h: "findings", page: "Overview", t: "Headline findings", d: "Credential dump, non-Garena token host, burned keys, Telegram exfil, overlay, self-signed APK.", k: "findings critical credential host overlay signature" },
  { p: "index.html", h: "architecture", page: "Overview", t: "Architecture", d: "Four UI units feed Api, Proto and Store, which reach Garena, the game socket and Telegram.", k: "architecture diagram MainActivity Api Proto Store BubbleService" },
  { p: "index.html", h: "explore", page: "Overview", t: "Explore the teardown", d: "Jump to the payload, protocol, spam loop, farm, detection or source map.", k: "explore pages navigation" },
  { p: "index.html", h: "timeline", page: "Overview", t: "Timeline", d: "The account dump was created in 46 minutes; the signing certificate is dated the same day.", k: "timeline 2026-08-04 certificate dump" },
  { p: "index.html", h: "handling", page: "Overview", t: "Handling the sample", d: "The records are live authentication material. Do not import or replay them.", k: "handling safety credentials report" },

  { p: "payload.html", h: "summary", page: "Payload", t: "At a glance", d: "6,190 unique UIDs, all region BD, created in a 46-minute window.", k: "payload summary accounts 6190 BD" },
  { p: "payload.html", h: "schema", page: "Payload", t: "Record schema", d: "UID, password, account ID, item, region and a signed JWT per record.", k: "schema json uid password account_id jwt_token item" },
  { p: "payload.html", h: "distribution", page: "Payload", t: "What is inside", d: "6,186 records share item 801047001; four use 905000065. Every password carries the operator marker.", k: "distribution item 801047001 905000065 password W8SOJIB" },
  { p: "payload.html", h: "claims", page: "Payload", t: "Token claims", d: "JWTs declare region BD, emulator true, client 1.126.8 and platform 1.", k: "jwt claims token emulator region client_version" },
  { p: "payload.html", h: "handling", page: "Payload", t: "Handling the dump", d: "Possession of the APK is possession of the dump. Treat every embedded account as compromised.", k: "handling compromised do not use" },

  { p: "protocol.html", h: "handshake", page: "Protocol", t: "Five-stage handshake", d: "Grant, MajorLogin, GetLoginData, auth blob, raw TCP invite.", k: "protocol handshake login grant majorlogin getlogindata authhex invite" },
  { p: "protocol.html", h: "fields", page: "Protocol", t: "Field maps", d: "MajorLogin request and response field numbers, including account ID and session IV.", k: "fields majorlogin protobuf field map 22 23 29 jar" },
  { p: "protocol.html", h: "authhex", page: "Protocol", t: "The auth blob", d: "A hex-framed account ID, timestamp and AES-encrypted JWT written to the game socket.", k: "authhex auth blob 0115 aes jwt socket" },
  { p: "protocol.html", h: "invite", page: "Protocol", t: "Invite path", d: "Friend requests over HTTPS; duo/squad invites over raw TCP after the handshake.", k: "invite friend request RequestAddingFriend duo squad groupmode" },
  { p: "protocol.html", h: "framing", page: "Protocol", t: "Packet framing", d: "Packet type, five hex length characters, then AES over the protobuf body.", k: "framing packet length aes protobuf" },

  { p: "spam.html", h: "model", page: "Spam", t: "Worker model", d: "Thirty threads, a shuffled account queue, and a 40–120 ms delay between actions.", k: "spam workers 30 queue thread delay" },
  { p: "spam.html", h: "loop", page: "Spam", t: "The loop", d: "Log in, choose an action, publish counters, repeat.", k: "loop spamloop code pseudocode" },
  { p: "spam.html", h: "modes", page: "Spam", t: "Modes", d: "Auto random, friend request, duo invite, squad invite.", k: "modes auto friend duo squad groupmode" },
  { p: "spam.html", h: "overlay", page: "Spam", t: "Overlay", d: "A foreground service draws a bubble and UID panel over the game.", k: "overlay bubble service clipboard SYSTEM_ALERT_WINDOW" },
  { p: "spam.html", h: "impact", page: "Spam", t: "Impact", d: "Notification and request flooding, not a game-state change.", k: "impact flooding notifications" },

  { p: "farm.html", h: "pipeline", page: "Farm", t: "Farm pipeline", d: "Register, token, major-register, login, persist, upload.", k: "farm pipeline generator register token telegram" },
  { p: "farm.html", h: "register", page: "Farm", t: "Registration", d: "Signed guest registration followed by token grant and MajorRegister.", k: "register guest hmac signature MajorRegister xor" },
  { p: "farm.html", h: "storage", page: "Farm", t: "Storage and exfiltration", d: "GenAccount.txt on external storage, then Telegram sendDocument.", k: "storage GenAccount.txt telegram sendDocument bot token" },
  { p: "farm.html", h: "recon", page: "Farm", t: "Nickname lookup", d: "Three top-up APIs queried in parallel with an operator bearer JWT.", k: "recon nickname lookup rrrtopup egytopup ucghor" },
  { p: "farm.html", h: "welcome", page: "Farm", t: "First-run popup", d: "A branded dialog pushes the operator Telegram channel.", k: "welcome popup telegram W8Teams" },

  { p: "detection.html", h: "weaknesses", page: "Detection", t: "Weaknesses", d: "Credential egress, static crypto, burned tokens, broad storage, overlay, self-signing.", k: "weaknesses security crypto storage overlay" },
  { p: "detection.html", h: "critical", page: "Detection", t: "The critical finding", d: "Account UID and password are sent to a non-Garena token host.", k: "critical token host credential harvesting" },
  { p: "detection.html", h: "iocs", page: "Detection", t: "Indicators", d: "Package, hashes, cert subject, hosts, artifacts and preference keys.", k: "iocs indicators hashes package domains hosts" },
  { p: "detection.html", h: "response", page: "Detection", t: "If it is installed", d: "Remove permissions, uninstall, rotate passwords, revoke sessions, report.", k: "response incident uninstall rotate revoke report" },
  { p: "detection.html", h: "hunting", page: "Detection", t: "Hunting", d: "Inventory alerts, permission combinations, DNS and Telegram uploads.", k: "hunting detection dns telegram permission" },

  { p: "source.html", h: "map", page: "Source", t: "Source map", d: "Seven app-specific files and their roles, plus the generated resource class.", k: "source map files MainActivity Api Proto Store" },
  { p: "source.html", h: "skeleton", page: "Source", t: "Class skeleton", d: "The Api surface and AccInfo data class recovered from the APK.", k: "skeleton api accinfo kotlin class" },
  { p: "source.html", h: "preserved", page: "Source", t: "What survived decompilation", d: "Field numbers, control flow and protocol constants are readable; names are partly synthetic.", k: "decompile jadx preserved names lines" },
  { p: "source.html", h: "limits", page: "Source", t: "Decompiler notes", d: "Eighty-nine method-level errors across libraries; the app package decompiled cleanly.", k: "limits jadx errors 89" },

  { p: "method.html", h: "method", page: "Method", t: "How this was produced", d: "Hashes, manifest and signature decode, JADX decompile, static JSON parsing.", k: "method sha256 apktool jadx rea" },
  { p: "method.html", h: "notdone", page: "Method", t: "What was not done", d: "No execution, no emulator, no network calls, no login attempts.", k: "not done execution dynamic network login" },
  { p: "method.html", h: "reproduce", page: "Method", t: "Reproduce the read", d: "Hash the sample, decode resources, decompile, inspect the asset.", k: "reproduce commands sha256sum apktool jadx" },
  { p: "method.html", h: "redaction", page: "Method", t: "Redaction policy", d: "No JWTs, passwords, UIDs, account IDs, keys or operator tokens are published.", k: "redaction secrets policy" },
  { p: "method.html", h: "legal", page: "Method", t: "Educational use", d: "Defensive analysis and protocol education only; no runnable spammer.", k: "legal educational terms authorization" }
];
