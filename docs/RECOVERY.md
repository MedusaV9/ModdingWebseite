# Recovery-Runbook: Wieder verbinden / Recovery runbook: Reconnect

Stand / as of: v11.0. Alle Wege führen auf dieselbe Server-Route
`POST /api/couples/rejoin` (Beweis-Reihenfolge: Recovery-Key → alter Token →
Ersatz-Code). QR-/Deep-Link-Format: [`REJOIN-QR.md`](REJOIN-QR.md) ·
Admin-Panel: [`ADMIN-PANEL.md`](ADMIN-PANEL.md).

Alle UI-Bezeichnungen unten sind die exakten Wortlaute der App (v11.0) —
Deutsch im deutschen Teil, Englisch im englischen Teil.

---

## 🇩🇪 Deutsch

### Entscheidungsbaum

```
Die App wirkt abgemeldet, Handy neu oder App frisch installiert?
│
├─ Läuft die App eigentlich noch? Kürzlich abgelaufene Sitzungen heilen sich —
│  höchstens erscheint kurz „🗝️ Verbindung still erneuert — weiter geht's“.
│  → Nichts zu tun. (Weg 0)
│
├─ Zeigt der Koppel-Bildschirm „Schlüssel im Schlüsselbund gefunden …“?
│  (Gleiches Gerät, oder neues Handy aus iCloud-/Gerätebackup eingerichtet)
│  → Weg 1: Ein Tipp auf „Wieder verbinden“. ✅ der schnellste Weg
│
├─ Kein Schlüssel zur Hand, aber die Server-Betreiberin ist erreichbar?
│  → Weg 2: Login-QR aus dem Admin-Panel scannen.
│
├─ Dein Schatz ist noch verbunden?
│  → Weg 3: „Partner hilft“ — Ersatz-Code als QR vom Handy des Schatzes.
│  → Weg 4: … oder den Ersatz-Code manuell eintippen.
│
└─ Nichts davon? Schlüssel vom Zettel + Paar-Code manuell eintippen
   (Variante von Weg 1, siehe unten) — oder die Server-Betreiberin bitten,
   das Admin-Panel zu öffnen (Weg 2).
```

Alle Wege holen **deinen eigenen Platz** im Paar zurück — Verlauf,
Statistiken und Abzeichen bleiben vollständig erhalten.

### Weg 0: Nichts tun (Sitzung heilt sich selbst)

Läuft nur die Anmeldung ab, repariert die App sich innerhalb der 24-stündigen
Token-Nachfrist im Hintergrund selbst; danach braucht sie den getrennten
Recovery-Key. Du merkst höchstens den kurzen
Hinweis **„🗝️ Verbindung still erneuert — weiter geht's“**. Kein Handeln
nötig.

### Weg 1: Ein-Tap mit dem Schlüssel aus dem iCloud-Schlüsselbund

Funktioniert, wenn die App das Server-Profil noch kennt: auf demselben
Gerät, oder auf einem neuen Handy, das aus einem iCloud-/Gerätebackup
eingerichtet wurde.

1. SoooDreamy öffnen. Der Koppel-Bildschirm startet in diesem Fall von
   selbst im dritten Tab **„Wieder verbinden“** („Willkommen zurück“).
2. Die grüne Karte prüfen: **„Schlüssel im Schlüsselbund gefunden — einfach
   auf „Wieder verbinden“ tippen.“**
3. Unten auf **„Wieder verbinden“** tippen — fertig, du bist wieder drin.

Ehrliche Grenze: Der iCloud-Schlüsselbund braucht eine Signatur mit
Schlüsselbund-Berechtigung; nackte Sideloads speichern den Schlüssel nur
lokal. Nach einer blanken Neuinstallation ohne Backup erscheint der
Schnellweg deshalb oft nicht — dann Weg 2, 3 oder die manuelle Variante.

**Manuelle Variante (Schlüssel vom Zettel):**

1. Auf dem Koppel-Bildschirm den Tab **„Wieder verbinden“** wählen.
2. **„Code eintippen“** antippen.
3. Euren Paar-Code eingeben (Feld „Code, z. B. H4XK9P“).
4. Den Schlüssel in das Feld **„Wiederherstellungs-Schlüssel (rec_…)“**
   eintippen (Groß-/Kleinschreibung ist egal).
5. Auf **„Wieder verbinden“** tippen.

### Weg 2: Login-QR aus dem Admin-Panel

Die Server-Betreiberin erzeugt den QR (Details: [`ADMIN-PANEL.md`](ADMIN-PANEL.md)):

1. Admin-Panel öffnen (`/admin`, Passwort steht im Server-Konsolen-Banner),
   das Paar aufklappen und den Tab **„Login-QR“** wählen.
2. Bei Bedarf **„Server-URL im QR“** anpassen (z. B. LAN-/Tailscale-Adresse,
   die das Handy erreicht).
3. **„QR für {Name} erzeugen“** für den richtigen Platz antippen —
   der Einmal-Nonce ist 30 Minuten einlösbar („Token gültig bis …“).

Auf dem ausgesperrten Handy:

1. SoooDreamy öffnen → Tab **„Wieder verbinden“** → **„QR-Code scannen“**.
2. Den QR vom Admin-Bildschirm scannen. Der QR enthält Server + einen
   zufälligen, fest an diesen Platz gebundenen Einmal-Beweis —
   **ein Scan, wieder drin**, keine weitere Eingabe.
3. Alternativ: Den QR mit der iOS-Kamera-App scannen — der
   `sooodreamy://rejoin`-Link öffnet SoooDreamy direkt. Oder die
   Betreiberin schickt den Link per **„Deep-Link kopieren“**.

Der Nonce ist selbst **kein Bearer-Token**. Nach erfolgreicher Einlösung oder
nach 30 Minuten ist derselbe QR wertlos; ein zweiter Scan wird abgelehnt.

### Weg 3: „Partner hilft“ — Ersatz-Code als QR vom Handy des Schatzes

Auf dem Handy des (noch verbundenen) Schatzes:

1. Tab **„Mehr“** → Karte **„Sicherheit & Wiederherstellung“** → Zeile
   **„Sicherheitsnetz“** öffnen.
2. Im Abschnitt **„Schatz ausgesperrt?“** auf **„Ersatz-Code erzeugen“**
   tippen.
3. Es erscheint ein QR-Code samt Hinweis „Am einfachsten: Dein Schatz
   scannt diesen QR-Code …“ — Server, Paar-Code und Ersatz-Code stecken
   schon drin. Der Code ist einmalig und 15 Minuten gültig
   („Gültig noch … · einmal verwendbar“).

Auf dem ausgesperrten Handy:

1. SoooDreamy öffnen → Tab **„Wieder verbinden“** → **„QR-Code scannen“**
   (oder den QR direkt mit der iOS-Kamera scannen).
2. Den QR vom Handy des Schatzes scannen — ein Scan, wieder verbunden.

Sicherheit: Der Ersatz-Code **ersetzt** deine alten Geräte — alle alten
Sitzungen und dein alter Schlüssel werden ungültig. Danach bekommst du
einen frischen Schlüssel gezeigt. Versehentlich erzeugt? Auf dem
Partner-Handy **„Code zurückziehen“** tippen.

### Weg 4: Ersatz-Code manuell eintippen

Wenn Scannen nicht klappt (z. B. Code am Telefon durchgegeben):

1. Der Schatz erzeugt den Code wie in Weg 3 und liest die 8 Zeichen unter
   dem QR vor.
2. Auf dem ausgesperrten Handy: Tab **„Wieder verbinden“** →
   **„Code eintippen“**.
3. Paar-Code eingeben (Feld „Code, z. B. H4XK9P“).
4. Den Schalter **„Ich habe einen Ersatz-Code von meinem Schatz“**
   aktivieren und den Code in das Feld **„Ersatz-Code“** eintippen.
5. Auf **„Wieder verbinden“** tippen.

### Wenn eine Fehlermeldung erscheint

| Meldung | Bedeutung / nächster Schritt |
| --- | --- |
| „Dieser Schlüssel passt zu keinem von euch beiden“ | Schlüssel vertippt oder inzwischen rotiert → Zettel prüfen; sonst Weg 2 oder 3. |
| „Ersatz-Code unbekannt, abgelaufen oder schon benutzt“ | Die 15 Minuten sind um oder der Code wurde bereits eingelöst → neuen Code erzeugen lassen. |
| „Diese Sitzung wurde ersetzt — bitte deinen Schatz um einen Ersatz-Code“ | Dein Platz wurde per Ersatz-Code neu besetzt; alte Beweise gelten nicht mehr → Weg 3 oder 4. |

### Danach: Schlüssel-Hygiene

Unter **Mehr → Sicherheit & Wiederherstellung → Sicherheitsnetz** kannst du
deinen Schlüssel jederzeit ansehen (**„Schlüssel zeigen“**), kopieren
(**„Schlüssel kopieren“**) und rotieren (**„Neuen Schlüssel erzeugen“** —
der alte wird sofort ungültig). Schreib den neuen Schlüssel auf: Papier
stirbt nie.

---

## 🇬🇧 English

### Decision tree

```
The app looks logged out, new phone, or fresh install?
│
├─ Is the app actually still running? Recently expired sessions heal —
│  at most you briefly see “🗝️ Session quietly healed — carry on”.
│  → Nothing to do. (Path 0)
│
├─ Does the pairing screen show “Key found in your keychain …”?
│  (Same device, or a new phone set up from an iCloud/device backup)
│  → Path 1: one tap on “Reconnect”. ✅ the fastest path
│
├─ No key at hand, but the server operator is reachable?
│  → Path 2: scan a login QR from the admin panel.
│
├─ Is your partner still connected?
│  → Path 3: “partner helps” — replace code as a QR from your partner's phone.
│  → Path 4: … or type the replace code manually.
│
└─ None of that? Type the key from your piece of paper + couple code
   (variant of path 1, below) — or ask the server operator to open the
   admin panel (path 2).
```

Every path re-attaches **your own seat** in the couple — history, stats,
and badges stay fully intact.

### Path 0: Do nothing (sessions heal themselves)

If only the login expires, the app repairs itself during the 24-hour bearer
grace; after that it needs the separate recovery key. At most you notice the brief toast **“🗝️ Session
quietly healed — carry on”**. No action needed.

### Path 1: One tap with the key from the iCloud keychain

Works whenever the app still knows the server profile: on the same device,
or on a new phone set up from an iCloud/device backup.

1. Open SoooDreamy. In this case the pairing screen starts on the third
   tab, **“Reconnect”** (“Welcome back”), by itself.
2. Check the green card: **“Key found in your keychain — just tap
   “Reconnect”.”**
3. Tap **“Reconnect”** at the bottom — done, you're back in.

Honest limit: the iCloud keychain needs a signature with keychain
entitlements; bare sideloads store the key locally only. After a blank
reinstall without a backup the shortcut therefore often doesn't appear —
use path 2, 3, or the manual variant instead.

**Manual variant (key from your piece of paper):**

1. On the pairing screen choose the **“Reconnect”** tab.
2. Tap **“Type it in”**.
3. Enter your couple code (field “Code, e.g. H4XK9P”).
4. Type the key into the **“Recovery key (rec_…)”** field (letter case
   doesn't matter).
5. Tap **“Reconnect”**.

### Path 2: Login QR from the admin panel

The server operator issues the QR (details: [`ADMIN-PANEL.md`](ADMIN-PANEL.md)):

1. Open the admin panel (`/admin`; the password is in the server console
   banner), expand the couple, and pick the **“Login QR”** tab.
2. Adjust **“Server URL inside the QR”** if needed (e.g. a LAN/Tailscale
   address the phone can reach).
3. Tap **“Generate QR for {name}”** for the right seat — the single-use nonce can be
   redeemed for 30 minutes (“Token valid until …”).

On the locked-out phone:

1. Open SoooDreamy → **“Reconnect”** tab → **“Scan a QR code”**.
2. Scan the QR from the admin screen. The QR carries server + a random
   single-use proof fixed to this member seat —
   **one scan and you're back**, no further input.
3. Alternatively: scan the QR with the iOS camera app — the
   `sooodreamy://rejoin` link opens SoooDreamy directly. Or the operator
   sends the link via **“Copy deep link”**.

The nonce itself is **not a bearer token**. After successful redemption or
after 30 minutes, that QR is worthless and a second scan is rejected.

### Path 3: “Partner helps” — replace code as a QR from your partner's phone

On the (still connected) partner's phone:

1. Open the **“More”** tab → **“Security & recovery”** card → the
   **“Safety net”** row.
2. In the **“Love locked out?”** section tap **“Create replace code”**.
3. A QR code appears with the hint “Easiest way: your partner scans this QR
   code …” — server, couple code, and replace code are already inside. The
   code is single-use and valid for 15 minutes (“Valid for … · single
   use”).

On the locked-out phone:

1. Open SoooDreamy → **“Reconnect”** tab → **“Scan a QR code”** (or scan
   the QR straight from the iOS camera).
2. Scan the QR on your partner's phone — one scan, reconnected.

Security: the replace code **replaces** your old devices — all old
sessions and your old key become invalid. Afterwards you are shown a fresh
key. Created by accident? Tap **“Withdraw code”** on the partner's phone.

### Path 4: Type the replace code manually

If scanning isn't possible (e.g. the code is read out over the phone):

1. Your partner creates the code as in path 3 and reads out the 8 characters
   below the QR.
2. On the locked-out phone: **“Reconnect”** tab → **“Type it in”**.
3. Enter the couple code (field “Code, e.g. H4XK9P”).
4. Enable the toggle **“I have a replace code from my love”** and type the
   code into the **“Replace code”** field.
5. Tap **“Reconnect”**.

### If an error message appears

| Message | Meaning / next step |
| --- | --- |
| “This key doesn't match either of you” | Key mistyped or rotated in the meantime → check the paper copy; otherwise path 2 or 3. |
| “Replace code unknown, expired or already used” | The 15 minutes are over or the code was already redeemed → have a new code created. |
| “This session was replaced — ask your partner for a replace code” | Your seat was re-taken via a replace code; old proofs no longer count → path 3 or 4. |

### Afterwards: key hygiene

Under **More → Security & recovery → Safety net** you can view your key at
any time (**“Show key”**), copy it (**“Copy key”**), and rotate it
(**“Create new key”** — the old one becomes invalid immediately). Write the
new key down: paper never dies.
