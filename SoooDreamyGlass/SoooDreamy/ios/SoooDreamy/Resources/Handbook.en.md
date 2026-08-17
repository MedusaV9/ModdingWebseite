<!-- anchor:setup -->
# Setup

Start the Node 20 server, open `/api/health`, and pair both iPhones by couple code or QR. When pairing, each person receives a recovery key (iCloud Keychain + one-time display). Public addresses need HTTPS/WSS; private HTTP is available only with `ALLOW_HTTP_PRIVATE_LAN=1`.

**Reconnect:** After a phone switch or reinstall, the third tab, “Reconnect”, gets your seat back — history, stats, and badges stay. If the key is still in the iCloud keychain, ONE tap is enough. Otherwise “Scan a QR code”: the server operator issues a login QR in the admin panel, or your partner shows the replace-code QR in the Bureau under Safeguard & keys → “Love locked out?”. As a last resort “Type it in”: couple code plus key or replace code (single use, valid 15 minutes). Expired sessions heal quietly by themselves.

**Server & admin panel:** The admin panel runs inside the server process (`/admin`); the password appears freshly in the console banner on every server start. What matters for you as a couple is the “Login QR” tab: one scan with the app or the iOS camera and the phone re-attaches to its seat — redeemable for 30 minutes, no further input.

Sign the unsigned IPA with AltStore, SideStore, or Sideloadly; ESign/KSign sign directly on the iPhone without a computer — then co-sign both bundle ids (app + widget extension), and without an App-Groups-capable certificate take the Lite IPA (in depth: `docs/SIDELOAD-ESIGN.md`). Free Apple IDs normally expire after seven days.

<!-- anchor:home -->
# Mailbox

Partner status, heartbeat, touches, the daily question, and streak stay at the top; the duty light in the header mirrors both energy levels. Below, the mailbox sorts rituals, waiting game turns, and moments into delivery rounds — new rounds arrive quietly staggered (can be turned off in the Bureau under “Stage the delivery rounds”). Groups can be pinned, collapsed, or hidden locally; urgent partner state remains visible.

**Rituals:** check-in, hug, energy light, Need button, day memo, Repair Conversation, Consideration Radar, 3 Good Things, and countdown calendars. Calendar payloads stay locked by server time for the recipient only; opened calendars remain archived. Consideration hints are Vault-encrypted and XP-free. Repair Conversation is a conversation tool, not therapy.

**If something is missing:** check the connection, expand the group, and choose Retry. Loaded content stays visible offline.

<!-- anchor:chat -->
# Writing Desk

Text, photos, voice notes, reactions, pins, love letters, and “Open when…” seals. The seal press at the desk bundles the three send-off ceremonies: time post, time capsule, and countdown calendar. The writing desk pages older history and keeps new messages at a stable anchor. Prepared text waits offline in an outbox scoped to the current server profile.

**Privacy:** Vault content does not belong in ordinary chat messages. Sealed letters are a reveal ritual, not end-to-end encryption.

**If sending stalls:** check the server address and wait for the outbox acknowledgement. Media is not queued offline.

<!-- anchor:play -->
# Game Table

The card cabinet sorts the catalog into three drawers (daily, async, and live/party games); the game book keeps tournament, hall of fame, and replays as chapter lines. “Your turn” stays first. Tournaments use the full retained server history plus Wordle. Replay adapters show actual state; unknown future types are never invented.

Games include Wordle/Duel, Quiz, This or That, Would You Rather, Truth or Dare, 36 Questions, Emoji Riddle, Battleship, Kniffel, Pictionary, Connect Four, Photo Memory, Categories, and Two Truths.

**If a move is rejected:** the server owns actor, phase, and order. Reload the view; never resend the same move blindly.

<!-- anchor:us -->
# Archive

The cabinet front sorts everything into six drawers: **Albums** (gallery, videos, photo of the day, moments, story, year review), **Planning drawer** (shared lists, bucket list, week plan), **Valuables drawer** (coupons, goals), **Chronicle** (journal, year in numbers, soundtrack, canvas, monthly magazine, week review, needs history), **Storage drawer** (time capsules, countdown calendars), and **Vault drawer** (Vault). A drawer opens in place — its rows glide out. The search above the cabinet filters every section by title; the cabinet remembers the drawer you left open.

The monthly magazine shares highlights and stats as an image set. Backups export local profiles/settings in encrypted form; couple content stays on the self-hosted server. Time capsules unlock only at the server deadline.

**If media is missing:** check the server media directory, permissions, and storage. Vault data needs the same PIN/key on both devices.

<!-- anchor:settings -->
# Bureau & Settings

The Bureau works in six quiet sections: **Our bureau** (profile, couple, pairing code), **Delivery service** (notifications, “Stage the delivery rounds”, custom daily questions), **Branches & districts** (server switching, devices, migration), **Workshop** (language, sounds, haptics, season theme with northern/southern hemisphere, Widget Studio, Live Activities, icons, personalization), **Safeguard & keys** (App Lock, the recovery key — view, copy, rotate —, the replace code for a locked-out sweetheart, iCloud/backup), and **Operations log** (connection doctor, handbook, About/credits, rewatch the bureau’s founding).

Sideloaded widgets need a co-signed App Group. Remote push and iCloud need matching Apple entitlements; local reminders do not. Free Apple IDs normally expire after seven days.

**Help:** for connection errors, check `/api/health`, HTTPS/Tailscale, port, and firewall. A new phone reconnects via “Reconnect” and your key — the history stays. made by Sonic0810.
