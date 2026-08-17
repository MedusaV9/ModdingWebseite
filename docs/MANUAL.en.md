# SoooDreamy Manual

<p align="center">
  <strong>The app for the two of you</strong><br />
  made by Sonic0810
</p>

Manual version: 16.0.0 · Language: English · Voice: warm, direct, and honest

This manual covers installation, server setup, pairing, all five tabs, and unsigned-build limits. Since 4.9, the app links directly into these chapters.

<a id="handbook-setup"></a>
## 1. Quick start

You need:

1. a computer, NAS, Raspberry Pi, or cloud host with Node.js 20 or newer;
2. two iPhones or iPads running iOS/iPadOS 26 or newer (iPad since 12.0; earlier releases ran from iOS 17);
3. the current unsigned IPA from the rolling GitHub release
   `sooodreamy-latest` (`versions/` archives releases 4.1 through 6.0 only);
4. AltStore, SideStore, or Sideloadly to sign and install it.

### Start the server

```bash
git clone https://github.com/MedusaV9/BiggerRepo.git
cd BiggerRepo/SoooDreamy/server
npm ci
npm test
HOST=0.0.0.0 PORT=4321 npm start
```

`npm test` needs no database or external service. Before every success
response, the server durably writes and syncs the change to its write-ahead
journal; JSON segments are downstream compaction. An exclusive data-directory
lock prevents double starts. `GET /api/health` reports segment/media size,
backup protection, and quarantine state.

### Choose a secure address

- Default: HTTP/WS works for the deliberately small private setup, but it is
  unencrypted — keep it on a trusted network.
- `ALLOW_HTTP_PRIVATE_LAN=1` restricts HTTP to loopback/private/Tailscale
  source addresses.
- Publicly: use HTTPS/WSS through Caddy/nginx with
  `TRUST_PROXY=1 REQUIRE_HTTPS=1`.
- Include the port when your proxy is not using standard port 443.

## 2. Install the IPA

The archive contains an unsigned device IPA. iOS accepts it only after a sideloading tool signs the app and its extensions with your profile.

### AltStore

1. Set up AltStore on the iPhone.
2. Open “My Apps” and choose `+`.
3. Select `SoooDreamy-<version>-unsigned.ipa`.
4. Confirm that the app and widget extension were signed together.

### SideStore

1. Set up SideStore with its pairing file and VPN tunnel.
2. Import the IPA into SideStore.
3. Refresh before the signature expires while SideStore is connected.

### Sideloadly

1. Connect the iPhone to the computer by cable or Wi-Fi.
2. Drop the IPA onto Sideloadly, choose the Apple ID, and install.
3. Trust the developer profile on the iPhone if iOS requests it.

### ESign / KSign (no computer)

1. Import a certificate pair (`.p12` + `.mobileprovision`) into ESign or KSign.
2. Download the IPA and import it into the app library.
3. When signing, do **not** let the tool remove the widget extension — both bundle ids (`app.sooodreamy.ios` + `app.sooodreamy.ios.widgets`) must be covered by the profile (wildcard profile).
4. Install and trust the certificate under Settings → General → VPN & Device Management.

Honest 2026 status: the original ESign is no longer maintained (best-known successor: KSign, built on Feather), and free shared certificates get revoked frequently — all apps signed with them then stop opening until re-signed. If your certificate cannot do App Groups, widgets only show placeholders — use the Lite IPA instead ([`SOOODREAMY-LITE.md`](SOOODREAMY-LITE.md)). In depth, with comparison table and troubleshooting: [`SIDELOAD-ESIGN.md`](SIDELOAD-ESIGN.md).

### Honest sideload limits

| Area | Free Apple ID |
|---|---|
| Signature | normally valid for 7 days |
| Active apps | at most 3 sideloaded apps |
| Widgets | work when the tool co-signs the App Group |
| Remote push | usually unavailable; needs a paid profile and APNs server credentials |
| iCloud/CloudKit | entitlements are often removed |
| Local reminders | available after iOS permission |
| File export | available and AES-GCM encrypted |

An expired signature does not automatically delete server data. Install a freshly signed app over the old one with the same bundle identifier. Keep your couple code or a current encrypted backup available.

## 3. Connect the server and pair

The first onboarding page offers **three ways in** — the fastest one deliberately comes first:

1. **“Scan an invitation”:** if your partner already created the couple, this path opens the camera right away. The invitation QR carries the server address AND the couple code in one step — nothing to type, nothing to look up.
2. **“Connect a server”:** the classic path for the first person — enter a server name and complete address, tap “Test connection” (the app shows the reported server version), then create the couple and share the six-character code or QR code.
3. **“See what awaits you”:** look first, decide later — the small tour through the app's idea.

Afterwards both check their name, avatar, and color. The QR code contains the server address and couple code. Share it only over a trusted channel. Session tokens belong in Keychain and are not written to exports.

Since 10.0 a four-page onboarding walks through the app's idea, the server principle, and the safety net before the first server is added. The language can be switched top-left at any time; "Skip" jumps to the last page.

Since 12.0 the onboarding ends with a three-step guide (connect your server → pair up → get going). Anyone who wants to look first taps **“Just look around first”**: demo mode opens the app with a sample couple, no server needed — everything inside is sample content and vanishes without a trace, and the way out (“Connect your own server”) stays visible as a badge. The moment of pairing is a small ceremony now: your two colors melt into one — including when a second device joins.

### The safety net (10.0)

Pairing hands each person a **recovery key** (`rec_…`). It goes into the iCloud keychain automatically and is shown once right after pairing — write it down as well, paper never dies. The server stores only the SHA-256 fingerprint, never the key itself. Anyone paired before 10.0 gets a key quietly on first launch.

That means:

- **Expired session:** the app repairs itself in the background (old token or key as proof). At most you notice a brief "session quietly healed" toast.
- **New phone / reinstall:** pick the third tab, **"Reconnect"**, on the pairing screen. Couple code + key — if the key is in the iCloud keychain, a single tap is enough. History, stats, and badges stay fully intact.
- **Everything lost:** your partner creates a one-time **replace code** (8 characters, valid 15 minutes) under **More → Security & recovery**. It reconnects you to your own slot without a key. Security: all old devices and the replaced slot's old key become invalid in the process.

Under **More → Security & recovery** you can view the key (masked, fully on demand), copy it, and rotate it — rotating invalidates the old key immediately. Honest limit: the iCloud keychain needs a signature with keychain entitlements; bare sideloads store the key locally only — then the piece of paper counts.

### Several devices per person (12.0)

Each person can connect iPhone AND iPad (and more) at the same time — same sign-in, same shared place:

1. On the already-connected device, open **More → Security & recovery → Devices → “Add a device”** and create a **one-time code** (time-limited, redeemable exactly once).
2. On the new device, open SoooDreamy and choose **“I already have a device”** in onboarding: scan the QR, type the code, or open the `sooodreamy://link` deep link — server address and code are already inside.
3. Done — the color-melt ceremony welcomes the device, and a quiet toast appears on your other devices (“New device linked”).

The **device manager** lives in the security area under **More → Security & recovery → Devices**: it lists every seat (“This device” is marked, at most 8 per person) and signs individual devices out — a signed-out device loses access immediately. Your own devices never confuse each other: what you type on the iPad shows on your iPhone as a subtle tick, not as a partner event. Security: a one-time code alone opens nobody else's couple — it is always created on an already-connected device and expires on its own.

<a id="handbook-rejoin"></a>
## 4. Reconnect

For almost every situation there is a way back onto your own seat with history, stats, and badges intact — we help you step by step. Honestly though: every path needs at least one proof (key, partner, or server operator). If all three are truly gone, a fresh pairing is the only way left. Check in this order:

1. **Do nothing:** expired sessions heal themselves — at most you briefly see “🗝️ Session quietly healed — carry on”.
2. **One tap:** if the pairing screen's **“Reconnect”** tab shows the card “Key found in your keychain — just tap “Reconnect”.”, that single tap is all it takes (same device, or a new phone set up from an iCloud/device backup).
3. **Login QR from the admin panel:** the server operator issues a 30-minute single-use QR via “Login QR” → “Generate QR for {name}”. In the app: **“Reconnect” → “Scan a QR code”** — one scan and you're back; replay and expiry are rejected (see chapter 5).
4. **Partner helps:** your partner opens **More → Security & recovery → Safety net → “Love locked out?” → “Create replace code”** and shows the QR (single use, valid 15 minutes). Scan it — done.
5. **All manual:** **“Reconnect” → “Type it in”** → couple code plus the recovery key from your piece of paper; or enable the toggle “I have a replace code from my love” and type the replace code.

Security: the replace code deliberately replaces the locked-out seat's old devices — old sessions and the old key become invalid, and a fresh key is issued afterwards. The full runbook with decision tree, exact screen wording, and error messages: [`RECOVERY.md`](RECOVERY.md).

<a id="handbook-admin"></a>
## 5. Server & admin panel

The admin panel runs inside the server process — nothing extra to start, no second port. On server start the console prints a framed banner with the URL (`http://…/admin`) and a fresh password; it is valid until the next restart and never stored anywhere.

From a user's perspective the **login QR** matters most — the most convenient way back when no key is at hand:

1. The operator logs into the panel and expands your couple.
2. On the **“Login QR”** tab she checks “Server URL inside the QR” (an address your phone can reach) and taps **“Generate QR for {name}”** for the right seat.
3. You scan the QR in the app (**“Reconnect” → “Scan a QR code”**) or straight with the iOS camera — the `sooodreamy://rejoin` link opens SoooDreamy and signs the phone back in with no further input. Alternatively **“Copy deep link”** sends the same link as text.
4. The token is redeemable for 30 minutes; unused tokens simply expire.

Beyond that, the panel can reset invite, recovery, and replace codes per couple, log out individual devices, trigger backups, and show logs — every action lands in the audit log. Secrets appear exactly once and never show up in any log. Operator details: [`ADMIN-PANEL.md`](ADMIN-PANEL.md).

## 6. The five tabs

**The "Paper & Light" look (14.0):** The app lives in a warm room at night — lamplight from ten o'clock, fine ink dust in your two colors. Everything that carries content is paper written in dark ink; the bottom bar is the system's real iOS glass bar and shrinks as you read. Above it sits the **today slip**: your partner's presence and the day's nudge, one tap leads Home.

**The first-launch cinema (14.0):** On the very first open, a lamp click asks for your language (Deutsch/English), then about a minute of cinema introduces the app — real little films, your ink pick, the wax seal. Every chapter can be skipped; under **More → "Rewatch intro"** it plays again anytime. Under Reduce Motion, calm stills tell the same story.

**The post station (14.0):** The touch grid gains two new counters: **Timed post** mails a touch, a pulse, or a note (up to 120 characters) with a delivery time — five minutes to seven days ahead, at most five open per person. Your partner sees nothing until the post is delivered; a note arrives as a sealed envelope whose wax only their own tap breaks. **History** shows the last 30 days of your little mail. For ten minutes after receiving a touch, **"Send back"** returns the same one exactly once — with no cooldown. Also new: **"Proud of you"** and **"Hang in there."**

<a id="handbook-home"></a>
### Home

Partner status, touches, the daily question, rituals, relationship level, and urgent hints.

The daily question and heartbeat remain immediately reachable. A local priority engine then orders three groups:

1. **Rituals & closeness** for an open need, available capsule, or unanswered daily;
2. **Games** when “your turn” sessions are waiting;
3. **Moments** for upcoming dates and flashbacks.

Tap the sliders at the top to pin or hide a group. This choice applies only on this device; urgent server state is never changed by a display preference. A group arrow expands it using a short system animation.

“New in this version” appears once after an update. Each entry links to its tab. The presented-version marker is local and prevents the sheet from repeating on every launch.

**Your week in numbers (7.0):** Under Rituals & closeness, a review sums up every ISO week — messages, touches, games, perfect days, the quote of the week from your daily question game, and the photo of the week. It carries the highlight ritual: each partner shares their moment of the week, and your sweetheart's pick reveals only once both shared. Highlights are open for the current and previous week only; completed weeks additionally show whether both of you read the review. Days follow device-local time; ISO weeks and the tolerant server validation window use UTC.

**Your own daily questions (7.0):** The small plus on the daily question secretly fills a shared question pool. Roughly every third day SoooDreamy asks one of them instead of a pack question — marked with the badge "One of your own questions". Who wrote it is revealed only after both answered. Each partner sees only their own pool questions; freshly added questions become eligible the next day at the earliest, and once asked, a question stays pinned.

**On this day (8.0):** The moments group shows today's memory from exactly X months or years ago — photos and daily questions BOTH of you answered. The pick is deterministic: both phones show the same memory. Long-press shares it to chat. Only the exact calendar day counts; January 31 simply has no February memory. Half-answered questions stay private — even as memories. The matching "On this day" home-screen widget is set up in the Widget Studio.

**Our story (8.0):** In the Us tab, "Our story" opens your milestone time journey — pairing day, anniversary, first message, first photo, first daily answered together, count milestones, and badges, month by month. Honestly though: "firsts" are the oldest entries still stored. Very old messages, touches, and games rotate out of server storage; the story then starts later instead of inventing dates.

**Thinking-of-you pulse (9.0):** The floating 💭 now sends a pulse — a vibration pattern your sweetheart physically feels: three soft knocks ("thinking of you"), one long wave ("good night"), a calm heartbeat, or a swelling hug (long-press picks the pattern). Sending plays the exact pattern that arrives, so you know what they'll feel. If their app was closed, the pulse waits on the server and buzzes on the next open — honestly: a sideloaded app cannot vibrate a closed phone, though the push banner arrives right away. Once felt, you get a quiet receipt ("felt your pulse"). At most one pulse every 30 seconds — so it stays precious.

**Focus & sleep (9.0):** The little mode chip next to your mood gently signals when you can't reply right now — 🎯 focus or 😴 sleep, with an optional note and auto-end (30 minutes to 8 hours, or "until I turn it off"). Your sweetheart sees the mode as a calm pill on your avatar plus a glow — the lock-screen pulse glows with the status too. Messages and pulses still arrive; the mode only removes the expectation of a quick reply. It ends on time by itself — nobody has to remember to switch it off.

**Shared spark (12.0):** Once you have both answered the daily question, your iPhone can build a small follow-up question from both your answers after the reveal — meant as a conversation opener for the evening. It runs through Apple Intelligence right on the device (see “Apple Intelligence” below), is opt-in, and only appears if you allowed it in Settings.

<a id="handbook-chat"></a>
### Chat

Text, photos, voice notes, letters, reactions, stickers, and pins. Sealed “Open when…” letters open only after your deliberate action.

Use the wand to choose one of six sparing send effects or open Sticker Workshop. Doodle strokes deterministically choose a drawn shape and optional short label; there is no photo cutout or AI recognition. An effect can be sent at most once every twelve seconds. Invisible ink reveals only after a deliberate tap.

**Translation & transcripts (12.0):** If your relationship lives in two languages, **long-press** a message and choose **“Translate”** from the menu — the translation renders right below the original, on-device through Apple's Translation framework, nothing goes to a cloud. The same menu hides it again or translates once more. Voice notes gain a transcript via **“Show transcript”** (SpeechAnalyzer, also on-device), cached locally. Both depend on the language packs iOS keeps on the device per language; if one is missing, the app says so honestly instead of guessing.

**Writing helpers with Apple Intelligence (12.0):** In the letter composer, **“Writer's block?”** opens the opening workshop — three suggested openings in the tone of your choice (tender, playful, deep). And **“Say it gently”** rewords a chat draft more softly: your original stays until you deliberately adopt the new wording. Both run in Apple's on-device language model, are opt-in, and never send anything on their own.

<a id="handbook-play"></a>
### Play

Daily and asynchronous games, live games, daily quests, tournaments, and replays. “You’re up” always comes first, followed by Daily, Async, Live together, and Party. Server rules determine valid moves and results.

**Games Wave II:** Word Chain Blitz alternates from the previous final letter and accepts only words in the selected German/English pack. “Our Word” Hangman stores only a SHA-256 commitment, length, and hint before play; the final reveal audits the word and every reported position. Couple Bingo creates a weekly 4×4 board. Tiles cannot be tapped: only real events the server has already validated, such as a completed daily quest or opened calendar door, check the matching micro action. A row, column, or diagonal ends the board and celebrates on both devices.

Open **How to play** for a resumable three-step intro to each of the 26 games. “Practice locally” provides a small solo prompt. Practice remains on-device, sends no game move, and awards no XP or tournament points. Help also sits right AT the table: the **?** button at the top right opens the same three-step intro as a sheet — no detour back through the hub.

**Replay:** Open “Replay & Spectator” from the Play hub. Open sessions carry a Live badge; completed sessions play in server order. The 1×/2×/4× control changes delay only, never move order. A star marks the computed turning point. All 21 server game types have an explicit presentation adapter; an unknown future type is not given an invented interpretation.

**Tournament:** Seasons use the server aggregate across the full retained history (up to 1,000 sessions) plus DE/EN Wordle. A win earns 3 points and a draw earns 1 each; co-op completions count as shared draws. Past months remain on the trophy shelf. Sessions removed before 4.3 cannot be recovered.

**Game tables, spectators & couch mode (12.0):** On iPad (and in wide windows), Connect Four, Kniffel, Bingo, Pictionary, and Battleship become real game tables — Battleship as a duel table with both fleets side by side. If you play across several of your own devices, exactly one holds the input: the others spectate (“Watch only — your iPhone is playing”) and take over via **“Play here”**; sealed moves stay commit-reveal fair, no device sees another's secrets. Wins are celebrated with their own victory motif under a ceremony budget — the big celebration stays reserved for the rare. This-or-That additionally offers couch mode, **“Play on one phone”**: secret picks, pass the phone, shared reveal.

**Board & duel games:** Six classics for the two-player duel, all under “Live together”: **Checkers** (forced captures and jump chains — a started chain must be finished; reaching the far row earns the crown), **Reversi** (enclose and flip; with no legal move you pass), **Dots & Boxes** (draw edges; a closed box is yours and grants an extra turn), **Gomoku** (exactly five in a row wins — six do not count), **Mancala** (sow counter-clockwise; if the last stone lands in your store you go again, in an empty pit of yours it captures the opposite pit), and **Memory Duo** (36 hidden cards; anything revealed once stays visible to both — your shared memory is part of the game, and even the app does not know a card before it is flipped). Pieces wear your avatar colors, whoever invites moves first, the server validates every move, and the decisive move ends the match on both devices. All six become game tables on iPad and appear in Replay, Record, and Season.

<a id="handbook-us"></a>
### Us

Gallery, videos, canvas, moments, lists, coupons, soundtrack, Vault, and your shared rituals.

The complete area covers gallery/albums/favorites, video gallery, doodle canvas with export, moments and recurring dates, bucket list, shared lists, coupons, soundtrack, daily-question journal, Vault, Photo of the Day, love stats, time capsules, countdown calendars, goals, week plan, day memos, monthly magazine, 3 Good Things, and year review. Each tile opens its own archive or editor; editing and deletion follow the ownership rules explained in that screen.

<a id="handbook-settings"></a>
### More / Settings

Profile, couple, server, devices, language, sound, haptics, season theme with northern/southern hemisphere, widgets, Live Activities, backups, and app lock. “About SoooDreamy” shows the version, build, server version, and “made by Sonic0810.”

**Devices (12.0):** In the security area under **More → Security & recovery → Devices** you manage your own device seats: “Add a device” creates the one-time code for your iPad or second phone, the list marks “This device” and signs others out individually (chapter 3 explains the flow). **Apple Intelligence (12.0):** The security card is where you enable the writing helpers — behind a clear consent sheet and with an honest availability status. Everything runs on the device only; off means off.

Under **Your couple → Your colors**, combine your profile colors or choose a preset. The derived accent must retain at least 4.5:1 contrast and is automatically lightened when needed. The palette colors backgrounds and your chat bubbles and is handed to Widget Studio as “Your colors.” Your monogram appears on letters, monthly magazines, and countdown calendars.

Each person can set an optional pet name in their profile. Their sweetheart sees it in personal copy. German and English use complete placeholder-based sentences, never grammar-fragile fragment concatenation.

### SoooDreamy on iPad (12.0)

On iPad every surface gets its own layout instead of an enlarged iPhone view: the dashboard arranges itself as a grid, memories open as a split view with a section sidebar, letters and the journal read in calm columns, and wide windows turn games into real game tables. Split View, Slide Over, and Stage Manager work in all four orientations — when the window gets narrow, the app seamlessly switches to the familiar iPhone layout, and started letters and chat drafts survive the change.

Apple Pencil draws on the doodle canvas with pressure and previews the stroke on hover. A connected keyboard switches tabs with **Cmd+1 through Cmd+5** and sends with **Cmd+Return**; images drag and drop straight into chat and gallery. The widget board gains XL sizes (“Days together” in two columns, the photo widget with a landscape crop). Honest limit: most iPads have no Taptic Engine — touches and pulses are visible there, but not feelable.

### Accessibility

SoooDreamy uses semantic system styles for body copy and moves tight Home rows into a vertical layout at accessibility text sizes. VoiceOver reads each group name and pending count together. With **Differentiate Without Color**, ✓/× supplements online status. With **Reduce Motion**, celebrations become a static, non-flashing glow and particle timelines do not run. Primary interactive targets are at least 44 × 44 points.

The floating **?** above the tab bar opens bundled Markdown help directly for Home, Chat, Play, Us, or Settings. Dates, times, months, numbers, goal values, and durations follow the language selected inside SoooDreamy even when the device language differs. Singular and plural use separate tested forms. A source test blocks plain user copy in `Text("…")`; only the brand and fixed acronyms remain on a reviewed allowlist.

### Widgets, StandBy, and iOS 18 controls

Widget Studio offers three quick styles per widget, or you can configure theme, layout, and data source yourself. Film strips show up to three distinct favorites; Photo Booth draws four frames. A small clock warning means the latest App Group snapshot is older than that widget's natural cadence. Open the app to synchronize safely.

Heartbeat, the Need button, **Thinking of You**, and **Start Date Night** are available for Control Center, the Lock Screen, and the Action Button. Add them from the matching iOS gallery. With sideloading, widgets and controls work only when the app, widget extension, and `group.app.sooodreamy.shared` are signed together.

### Repair, consideration, and 3 Good Things

Open **Home → Rituals & closeness → Repair & consideration** for three deliberately calm tools:

1. **Repair conversation:** One person describes a feeling and the other first mirrors what they heard. Roles then switch; each person contributes one part of the small agreement at the end. The server accepts only the current person and step kind. A ten-minute shared pause blocks both sides until the server deadline. This is a conversation frame, not therapy or a substitute for professional help or safety.
2. **Consideration Radar:** Sharing is always optional. The iPhone encrypts the hint with the shared Vault key; the server stores ciphertext, expiry, and coarse visibility metadata. Only the sender can pause it immediately. There is deliberately no XP, streak, or score. Both devices must have unlocked the Vault with the same shared key to read the text.
3. **3 Good Things:** Each person writes exactly three small bright spots in the evening. Your partner’s entries stay hidden until both of you share, then both lists reveal together. This moment can feed the monthly issue.

### Countdown calendars and event frames

Open **Home → Rituals & closeness → Countdown calendars** to prepare up to 31 doors for your partner. Choose Advent, birthday week, anniversary week, or a custom countdown. The app fills them from bilingual prompt, mini-quest, letter, or game templates and shows a preview before sealing.

The server withholds every payload until its own date. Only the recipient can open a due door. Opened calendars remain a shared archive; only the author can delete an unopened calendar. Server time remains authoritative even if a device clock is changed.

Under **More → Season theme**, select the northern or southern hemisphere. Valentine's Day, Halloween, New Year, and your saved anniversary can suggest an event frame or widget look. Suggestions are never applied without asking. Local reminders work without remote push; a reliable alert while the app is terminated still needs a push-capable signed profile.

The monthly magazine has an export button at the top right. It renders a localized personal image set with highlights and stats for sharing through iOS to Chat or Photos. The export cards do not copy the underlying server photos.

## 7. Privacy and backups

- Shared content lives on your self-hosted server.
- Vault content is end-to-end encrypted; the server sees ciphertext only.
- The exported `.sooodreamy` file is encrypted with a passphrase of at least twelve characters.
- The passphrase is never stored. A backup cannot be recovered without it.
- A new phone reconnects via "Reconnect" with the recovery key — see the "Reconnect" chapter and [`RECOVERY.md`](RECOVERY.md).

Under **More → iCloud & Backup**, choose four export domains independently: server profiles without session tokens, device language/sound/haptics, Widget/Live Activity App Group data, and a light couple snapshot. The `.sooodreamy` file is always AES-GCM encrypted and the passphrase of at least twelve characters is never stored.

Before restore, choose server profiles, device settings, and App Group settings separately. The couple snapshot is evidence-only and is never written back to the couple server. Legacy schema-1 files map to those three local domains plus an optional snapshot; unknown future schemas are rejected. Restored profiles deliberately require fresh pairing on a new device.

### Move a couple to a new server (6.0)

1. On the old server, open **More → Server migration**, enter a passphrase of at least twelve characters, and share the encrypted `.sooodreamy-migration` file.
2. Add the new server to SoooDreamy, create a **fresh couple with no activity** there using your own profile, and leave that server active.
3. Reopen the assistant, choose the file and passphrase, review the source version and short SHA-256 digest, then confirm import.
4. Share the displayed **new** pairing code with your sweetheart. Old-server tokens are never imported.

The API contract transfers logical JSON content and rejects tampered files, unknown schemas, and non-empty destinations. Large photo, video, voice, and Vault binary files deliberately stay outside the mobile JSON file: the server admin copies the media directory using a filesystem-consistent snapshot. Keep the old server unchanged until both logical content and media have been checked.

Built-in hourly backups include media by default. Stop the server before an
external `npm run backup`, migration, or restore; the shared data-directory
lock refuses to race the live server.

## 8. Troubleshooting

### “No connection”

1. Open `<server>/api/health` in a browser on the same network.
2. Check host, scheme, and port.
3. For public reachability, configure HTTPS and `REQUIRE_HTTPS=1`.
4. Check firewall or Tailscale rules.
5. Inspect server logs for a bind error or wrong `DATA_DIR`.

### A widget stays empty

Open the app once, inspect App Group status in Widget Studio, and re-sign the app and widget extension together.

### Push does not arrive while the app is terminated

That is expected for free-signed builds. Use local reminders; full remote push needs a push-capable Apple profile and valid APNs credentials on the server.

### The app no longer starts after seven days

The free signature has probably expired. Sign the IPA again with the same Apple account and reinstall it.

### Loading, offline, and failure states

Server-backed screens distinguish five states: loading, content, empty, offline, and failure. Already loaded content stays visible during a brief connection loss. “Empty” means a successful response with no entries; “offline” means no connection; “failure” means the request failed. For the last two, **Retry** repeats the same safe read operation.

The offline outbox atomically stores chat text, reactions, daily answers, quest checks, and game ratings per server profile, couple, and member. On reconnect it sends FIFO with the same idempotency id and removes only the server-acknowledged entry from its own profile. Killing the app after enqueue does not lose the operation; media still is not queued offline.

WebSocket reconnects use exponential delay with jitter, so two phones do not hit the server in lockstep after a router restart. Large gallery, Vault, widget, and magazine images decode directly to their display budget instead of materializing a camera-resolution bitmap in memory.

### Recovering App Lock

Cancelling Face ID or Touch ID leaves the app quietly locked. After failed recognition, tap again and use the device passcode. If device authentication is unavailable, SoooDreamy links to System Settings. The app never bypasses the lock and cannot reset a device passcode.

## 9. FAQ

**Do we need two servers?**  
No. One server owns the shared couple and both apps connect to it.

**Can the server read our Vault content?**  
No. It stores ciphertext and public key-derivation parameters, not the device key.

**Does SoooDreamy work offline?**  
Cached content and queued chat messages remain available. Synchronizing with your partner requires a connection to the couple server.

**Is the IPA in the App Store?**  
No. The published artifact is unsigned and intended for deliberate sideloading.

## 10. Release evidence

The rolling GitHub release `sooodreamy-latest` is the source for current
16.0.0 IPAs. `versions/` is a reproducible historical archive for releases
4.1 through 6.0; no complete per-version IPA evidence is claimed there for
7.0 through 16.0.

Since 5.4, release evidence includes a complete state inventory: loading, empty, content, offline, and failure are checked for every key surface. An empty screen must never hide a network failure; existing data remains readable beside offline/failure notices, and Retry stays one tap away.

### Dev Cockpit (development)

For local QA only, start with `SOOODREAMY_DEV_COCKPIT=1 npm start` and open `/dev/cockpit`. Its two columns create a couple, send touches, answer the daily question, and perform a game move. Without the flag, the route deliberately returns 404. The cockpit keeps no credentials outside the open page and does not replace device testing.

---

SoooDreamy — made by Sonic0810
