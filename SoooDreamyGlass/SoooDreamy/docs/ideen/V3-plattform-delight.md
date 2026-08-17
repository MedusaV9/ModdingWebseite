# 💡 Ideen-Sammlung V3 — Lens „Plattform, Personalisierung & Delight"

> Ideen-Agent 3/3 für SoooDreamy 3.0 → 4.0 → 5.0. Fokus: iOS-Plattform-Magie,
> Personalisierung und Mikro-Delight. Stand: 2026-08-08, Basis = 2.0.0
> (8 Widgets alle Größen + interaktiv, konfigurierbare Live Activities,
> BGRefresh, Liquid-Glass-Design, prozedurales Icon, Videos, iCloud-Fallbacks,
> Spicy Vault, Haptik-Studio).

## 📏 Sideload-Baseline (gilt für alle Machbarkeits-Angaben)

Die App wird als **unsigniertes IPA** verteilt und via AltStore/SideStore/
Sideloadly mit freier Apple-ID signiert. Das heißt ehrlich:

- ❌ **Kein Remote-Push (APNs)** — freie Provisioning-Profile bekommen kein
  `aps-environment`. Alles, was „Partner löst sofort etwas auf meinem
  gesperrten Gerät aus" braucht, geht nur über: App offen (WebSocket),
  BGAppRefresh (opportunistisch) oder „beim nächsten App-Öffnen".
- ❌ **Keine iCloud-Entitlements** (CloudKit/Drive) — 2.0 erkennt das bereits
  zur Laufzeit und degradiert.
- ❌ **Keine watchOS-Installation** über AltStore/SideStore/Sideloadly —
  Recherche-Ergebnis unten bei Idee 7.
- ✅ **App Groups** signieren AltStore/SideStore mit → Widgets, Controls,
  Live Activities, interaktive AppIntents funktionieren.
- ✅ **Kein Entitlement nötig** für: Alternate Icons, App Shortcuts/Siri
  (AppIntents), CoreSpotlight, StandBy, Control-Center-Controls (iOS 18),
  lokale Notifications (inkl. Watch-Mirroring!), Vision/VisionKit,
  CoreHaptics, SceneKit/SpriteKit.
- ⚠️ **Repo-Politik:** keine Binärdateien — alle Assets (Icon-Varianten,
  Notification-Sounds, Abzeichen) müssen prozedural generierbar sein
  (wie `GenerateIcon.swift` heute). Das ist bei jeder Idee mitgedacht.

**Legende:** Aufwand S/M/L · Score = Delight-Faktor 1–10.

---

## A. iOS-Plattform-Magie

### 1. 🎁 App-Icon-Geschenke — Alternate Icons, vom Partner schaltbar

**Konzept:** Ein Set prozedural gerenderter Icon-Varianten (Paar-Gradient,
Saisons, Retro, Neon, Minimal-Mono). Der Clou: Der Partner kann dir ein Icon
**schenken** — beim nächsten App-Öffnen erscheint eine Auspack-Zeremonie und
das Icon wird (mit deinem Segen) umgeschaltet. Dein Home Screen wird zur
Liebeserklärung.
**Machbarkeit (Sideload):** ✅ Voll. `setAlternateIconName` braucht kein
Entitlement; Varianten rendert `GenerateIcon.swift` in CI als PNGs ins Bundle
(`CFBundleAlternateIcons`). Ehrliche Grenzen: iOS zeigt beim Wechsel einen
System-Alert, und der Wechsel geht nur bei App im Vordergrund — deshalb die
Inszenierung als „Geschenk beim Öffnen" statt Fern-Umschaltung. Server braucht
nur ein Mini-Relay-Event (`icon_gift`).
**Aufwand:** M · **Score:** 9

### 2. 🍂 Saisonale App-Icons (automatischer Vorschlag)

**Konzept:** Zum Saisonwechsel (Herbst, Winter, Frühling, Sommer, Jahrestag)
schlägt die App beim ersten Öffnen der Saison die passende Icon-Variante vor
— ein Tap, umgestylt. Am Jahrestag gibt es ein exklusives Gold-Icon nur für
diesen Tag.
**Machbarkeit (Sideload):** ✅ Voll (gleiche Technik wie Idee 1). „Automatisch"
heißt ehrlich: Vorschlag beim App-Start, kein stiller Hintergrund-Wechsel
(iOS erlaubt das nicht).
**Aufwand:** S (wenn Idee 1 gebaut ist) · **Score:** 7

### 3. 🎛 Controls-Familie: Kontrollzentrum, Lock Screen & Action Button (iOS 18)

**Konzept:** `ControlWidget`-Buttons: „Herzklopfen senden 💓", „Ich denk an
dich 💭" (Toggle mit Zustand), „Date-Night starten 🌙". Sie landen im
Kontrollzentrum, ersetzen auf Wunsch die Taschenlampe auf dem Sperrbildschirm
und liegen auf dem **Action Button** — Liebe senden, ohne die App zu öffnen.
**Machbarkeit (Sideload):** ✅ Voll. Controls leben in der bestehenden
Widget-Extension, brauchen kein spezielles Entitlement (nur die App Group, die
schon signiert wird). Braucht iOS-18-SDK in CI (Xcode 16 auf macos-Runner ✓)
mit `#available(iOS 18)`-Guard — Deployment-Target bleibt 17. Gotcha aus der
Recherche: Der AppIntent muss Member beider Targets sein. Netzwerk läuft wie
beim heutigen Send-Love-Widget im AppIntent.
**Aufwand:** M · **Score:** 9

### 4. 🗣 App Shortcuts 2.0 — Siri-Phrasen & Automationen

**Konzept:** `AppShortcutsProvider` mit natürlichen Phrasen: „Hey Siri, schick
einen Kuss mit SoooDreamy", „…wie geht's meinem Schatz?" (gesprochene
Antwort: Stimmung + zuletzt gesehen), „…starte unser Wordle". Parameter =
Berührungsart. Dazu Kurzbefehle-Actions für **persönliche Automationen**:
„Wenn ich zuhause ankomme → Herzklopfen", „Wecker aus → Morgen-Check-in".
**Machbarkeit (Sideload):** ✅ Voll. AppIntents/App Shortcuts brauchen kein
Entitlement, Siri führt sie lokal aus; die App hat die Basis (2 Intents)
schon. Automationen legt der User selbst in der Kurzbefehle-App an — die App
liefert nur saubere Actions + eine Galerie mit Anleitungs-Deep-Links.
**Aufwand:** M · **Score:** 8

### 5. 🔍 Spotlight-Integration

**Konzept:** Momente, Bucket-List-Einträge, Alben, Brief-Titel und Songs
landen (opt-in) im CoreSpotlight-Index: „Jahrestag" in die iPhone-Suche tippen
→ Countdown-Karte, direkt in die App springen. App Shortcuts erscheinen
zusätzlich als Top-Treffer.
**Machbarkeit (Sideload):** ✅ Voll, kein Entitlement. Harte Regel: Vault- und
Chat-Inhalte werden **nie** indexiert (Privatsphäre), Schalter in den
Einstellungen, Index wird bei App-Sperre-Aktivierung geleert.
**Aufwand:** M · **Score:** 6

### 6. 🕯 StandBy-Nachtlicht

**Konzept:** Ein StandBy-optimiertes Widget-Design fürs Nachtkästchen: große
ruhige Typo, Partner-Schlafstatus („Gute Nacht ☾ seit 23:12" aus dem
Check-in), sanft pulsierendes Herz. Im Night Mode (Rot-Tönung) wechselt es auf
kontrastarme Glut-Optik — die App schläft sichtbar **mit euch**.
**Machbarkeit (Sideload):** ✅ Voll. StandBy zeigt systemSmall-Widgets — die
gibt es schon; nötig ist nur Design-Feinschliff (`widgetRenderingMode`/
Luminanz-Erkennung, vordatierte Timeline für die Puls-Animation). Kein neues
Entitlement.
**Aufwand:** S–M · **Score:** 7

### 7. ⌚️ Apple-Watch-Companion — Recherche-Ergebnis (ehrlich)

**Konzept:** „Herzklopfen vom Handgelenk": Watch-App mit Komplikation,
Herzklopfen-Senden per Digital-Crown-Druck, Haptik-Empfang am Puls.
**Machbarkeit (Sideload):** ❌ **Für die IPA-Distribution nicht machbar.**
Recherche (Aug 2026): AltStore, SideStore und Sideloadly installieren
ausschließlich auf iOS/iPadOS — watchOS-Apps lassen sich **nur** über direktes
Xcode-Deployment aufs gekoppelte iPhone+Watch-Paar bringen (freie Apple-ID
reicht, aber: Mac nötig, 7-Tage-Resign, pro Gerät manuell). Realistische
Strategie: Watch-Target als **optionales** XcodeGen-Target für
Selber-Bauer dokumentieren (CI packt es nicht in die IPA), die Masse bedient
Idee 8.
**Aufwand:** L · **Score:** 6 (traumhaft, aber Nische wegen Distribution)

### 8. 📳 Watch-Präsenz ohne Watch-App (Notification-Mirroring)

**Konzept:** iOS spiegelt **lokale** Notifications automatisch auf die
gekoppelte Apple Watch (wenn das iPhone gesperrt ist) — inklusive Wrist-Tap.
SoooDreamy nutzt das: Berührungen, die per WebSocket/BGRefresh ankommen,
werden als liebevoll formatierte lokale Notification zugestellt → der Tap am
Handgelenk ist echt, ganz ohne Watch-App.
**Machbarkeit (Sideload):** ✅ Funktioniert, mit ehrlicher Grenze: ohne Push
entstehen die Notifications nur, solange die App läuft oder ein
BGRefresh-Fenster erwischt — verpasste Berührungen kommen als „nachgeholte"
Zusammenfassung beim nächsten Lauf. Kein Entitlement nötig.
**Aufwand:** S · **Score:** 7

### 9. 🌙 Live-Activity „Date-Night-Modus"

**Konzept:** Abends aktiviert ihr den Date-Night-Modus: eine Live Activity
zählt mit Phasen zum Date runter — Vorfreude ✨ → Fertigmachen 💄 → Unterwegs
🚗 → Date 💞 — mit segmentiertem Fortschrittsbalken und Phasen-Emoji in der
Dynamic Island. Beide Partner sehen dieselbe Choreografie.
**Machbarkeit (Sideload):** ✅ Gut, mit bekannter LA-Grenze: Countdown-Texte
und Fortschritt (`Text(timerInterval:)`, `ProgressView(timerInterval:)`)
animieren systemseitig weiter; **Phasen-Labels** wechseln aber nur, wenn die
App aktualisiert — gelöst per „Weiter"-Button in der Activity
(`LiveActivityIntent` läuft im App-Prozess und weckt die App im Hintergrund)
plus Update beim App-Öffnen. Phasen-Zeiten werden beim Start festgelegt, der
Server synct den Startschuss zum Partner.
**Aufwand:** M · **Score:** 9

### 10. 🏝 Dynamic-Island-Spiel „Herz-Pingpong"

**Konzept:** Während „Couple Pulse" läuft, wird die expandierte Island zum
Mini-Spielfeld: Herz-Button tippen → Puls fliegt zum Partner, der schlägt
zurück — ein Rally-Zähler zählt, wie lange ihr den Ball in der Luft haltet
(über Stunden/Tage). Länge der Rally = gemeinsames Kunststück.
**Machbarkeit (Sideload):** ✅ Machbar mit ehrlichem Timing: Der eigene Tap
(AppIntent-Button, wie im Send-Love-Widget) darf im geweckten App-Prozess ans
Server-Relay posten. Der Partner sieht den Puls erst, wenn seine Seite aktiv
wird (App/Widget/BGRefresh) — deshalb bewusst als **träges** Pingpong über den
Tag designen, nicht als Echtzeit-Duell. Zustand: 1 Mini-Endpoint oder
`games`-Relay.
**Aufwand:** M · **Score:** 8

### 11. 🖥 iPad-Layout & Zweitgeräte

**Konzept:** `TARGETED_DEVICE_FAMILY 1,2` + `NavigationSplitView`: Chat links,
Inhalt rechts; Canvas und Galerie glänzen auf dem großen Screen (Stift-Support
fürs Kritzeln!). Dasselbe Paar auf iPhone **und** iPad — der Server kann das
heute schon (Token ist geräteunabhängig), es fehlt nur der bequeme
Übertragungsweg (→ Idee 35).
**Machbarkeit (Sideload):** ✅ Voll — AltStore/SideStore laufen auf iPadOS.
Aufwand steckt im Re-Layout aller ~15 Screens + Regression auf iPhone;
ExtraLarge-Widgets existieren schon.
**Aufwand:** L · **Score:** 8

### 12. 🔔 Eigene Notification-Sounds aus der Sound-Engine

**Konzept:** Die synthetisierten 2.0-Sounds (Glas-Glocke, Herzschlag, Vibe)
auch für Notification-Banner: „Herzklopfen klingt anders als Chat" — schon am
Ton hörst du, **was** dein Schatz geschickt hat.
**Machbarkeit (Sideload):** ✅ Voll. Lokale Notifications akzeptieren
Custom-Sounds als `.caf` im Bundle; die rendert ein Build-Script in CI aus der
bestehenden Synthese (Repo bleibt binärfrei). Grenze wie immer: Notifications
entstehen nur lokal (App läuft/BGRefresh).
**Aufwand:** S–M · **Score:** 6

---

## B. Personalisierung

### 13. 🎨 Paar-Farbschema „Eure Farben"

**Konzept:** Die beiden Member-Farben (existieren im Datenmodell!) werden zur
App-Identität: Der Verlauf aus *deiner* und *seiner/ihrer* Farbe zieht sich
durch Akzente, Chat-Bubbles, das 3D-Herz, Widgets — und als Icon-Variante
(Idee 1) bis auf den Home Screen. Ändert ein Partner seine Farbe, rekombiniert
sich die App live bei beiden.
**Machbarkeit (Sideload):** ✅ Voll — reine Client-Arbeit auf vorhandenen
Daten, Widget-Themes lesen die Farben aus dem App-Group-Snapshot.
**Aufwand:** S–M · **Score:** 8

### 14. 🍁 Saison-Themes & Skins

**Konzept:** Das Liquid-Glass-Design bekommt eine Theme-Ebene: Herbst (warme
Bernstein-Töne, Blätter), Winter-Wunderland (Frost-Kanten auf den
Glas-Karten!), Kirschblüte, Sommernacht, Spooky Oktober. Automatisch zur
Saison oder manuell — inklusive passender Widget-Skins und Icon-Vorschlag
(Idee 2).
**Machbarkeit (Sideload):** ✅ Voll — Erweiterung des Design-Systems
(Hintergrund-Blobs, Partikel-Farben, Karten-Dekor sind zentralisiert). Kein
Server nötig; „gemeinsames Theme" optional als 1 Settings-Sync-Feld.
**Aufwand:** M · **Score:** 8

### 15. ❄️ Jahreszeiten-Partikel im Dashboard

**Konzept:** Dezente, physikalisch schöne Partikel-Layer: fallende Blätter im
Herbst, Schnee im Winter (bleibt kurz auf Karten-Kanten „liegen"),
Kirschblüten im Frühling, Glühwürmchen in Sommernächten. Reagieren zart auf
Scroll/Gyro — Mikro-Delight bei jedem Öffnen.
**Machbarkeit (Sideload):** ✅ Voll — SpriteKit/`TimelineView`+Canvas, alles
prozedural. Akku-Regeln: pausiert bei Low Power Mode & im Hintergrund,
abschaltbar; Partikel-Dichte an ProMotion/Gerät anpassen.
**Aufwand:** S · **Score:** 8

### 16. 🎶 Sound-Themes

**Konzept:** Die Synthese-Engine bekommt Presets, die alle App-Sounds
umfärben: „Spieluhr" (zarte Glocken), „8-Bit-Arcade" (Chiptune-Bleeps),
„Regentag" (Lofi, weiche Filter), „Synthwave" (Sägezahn + Chorus). Gleiche
Events, komplett anderer Charakter — und weiterhin null Audio-Dateien.
**Machbarkeit (Sideload):** ✅ Voll — die 2.0-Engine ist parametrisch
(Hüllkurven, Spektren, Effekte), Themes = Parametersätze. Sync als
Einstellungs-Feld, jeder darf aber sein eigenes Theme hören.
**Aufwand:** M · **Score:** 7

### 17. 💬 Kosenamen-System

**Konzept:** Jeder hinterlegt, wie die App ihn/sie anreden soll („Schnuffel",
„Captain", „mon amour") — und die App benutzt es **überall**: „Guten Morgen,
Schnuffel ☀️", Notifications („Schnuffel denkt an dich"), Widgets,
Vollbild-Momente, Level-Up-Urkunden. Winzig, aber jedes Mal ein Lächeln.
**Machbarkeit (Sideload):** ✅ Trivial machbar — 1 Feld am Member (`PATCH
/api/me`), Interpolation in L10n-Strings (DE/EN-Grammatik beachten).
**Aufwand:** S · **Score:** 8

### 18. 🕯 Paar-Monogramm & Wachssiegel

**Konzept:** Aus euren Initialen + Jahrestag generiert die App ein
verschlungenes Monogramm — als Wachssiegel auf versiegelten Briefen (bricht
beim Öffnen!), Wasserzeichen im Jahresrückblick, Stempel auf Coupons und
optional als Mono-Icon-Variante. Euer gemeinsames „Wappen".
**Machbarkeit (Sideload):** ✅ Voll — prozedurale Vektor-Generierung
(Core Graphics/SwiftUI-Paths), deterministisch aus Paar-Daten, kein Asset.
**Aufwand:** S–M · **Score:** 7

### 19. 📸 Polaroid-Rahmen fürs Foto-Widget

**Konzept:** Das Foto-Widget (und Foto des Tages) bekommt Rahmen-Stile:
Polaroid mit handschriftlicher Caption + Datums-Stempel, Filmstreifen
(3 Fotos), Scrapbook mit Klebeband-Ecken, Passbild-Automat (4er-Streifen).
Der Home Screen wird zur Pinnwand eurer Beziehung.
**Machbarkeit (Sideload):** ✅ Voll — reine Widget-Renderings, Auswahl über die
bestehende `AppIntentConfiguration` + Widget-Studio-Vorschau. Handschrift-Font
prozedural/Systemfont-Variation, keine Font-Binärdatei nötig.
**Aufwand:** S–M · **Score:** 8

### 20. ✒️ Handschrift-Briefpapier

**Konzept:** Liebesbriefe wählen ein Briefpapier (Pergament, Sternenhimmel,
Kariert mit Kaffeefleck) und werden beim Öffnen mit einer
Tinten-Schreib-Animation „live geschrieben" enthüllt — Zeile für Zeile, mit
Feder-Kratz-Sound aus der Engine.
**Machbarkeit (Sideload):** ✅ Voll — Texturen prozedural (Noise-Gradienten),
Animation via `TextRenderer`/zeichenweisem Reveal; Papier-Wahl als Feld am
Brief (abwärtskompatibel `null`).
**Aufwand:** M · **Score:** 7

### 21. 🖼 Widget-Auto-Skins (saisonal)

**Konzept:** Opt-in im Widget-Studio: Widgets ziehen automatisch das aktuelle
Saison-Theme (Idee 14) an — Schnee-Kante im Dezember, Blüten im April. Der
Home Screen lebt mit dem Jahr mit, ohne dass man je ins Studio muss.
**Machbarkeit (Sideload):** ✅ Voll — Datum-abhängige Theme-Auflösung im
Widget-Prozess selbst, kein Refresh-Problem (Saison ändert sich langsam).
**Aufwand:** S · **Score:** 6

### 22. 🏷 Sticker-Werkstatt (Subject-Lift aus euren Fotos)

**Konzept:** Aus Galerie-Fotos stanzt die App Personen/Motive frei (wie
iMessage-Sticker): Foto wählen → Subjekt wird on-device freigestellt →
weiße Outline + Schatten → Sticker in eurer gemeinsamen Bibliothek, im Chat
verschickbar und auf Fotos klebbar. Eure Insider-Memes, aus euren Momenten.
**Machbarkeit (Sideload):** ✅ Voll — `VNGenerateForegroundInstanceMaskRequest`
(Vision, iOS 17) läuft on-device ohne Entitlement; Sticker = transparente
PNGs über die vorhandene Foto-Pipeline (neuer `kind` oder eigenes
`/api/stickers`).
**Aufwand:** L · **Score:** 9

### 23. 🧩 Dashboard-Layout-Editor

**Konzept:** Karten auf dem Dashboard per Drag & Drop anordnen, ein-/
ausblenden, pinnen — Nachteulen schieben den Gutenacht-Check-in nach oben,
Spieler das Wordle. Jeder personalisiert seine Sicht, ohne dem Partner
reinzufunken.
**Machbarkeit (Sideload):** ✅ Voll — lokale Präferenz (App Group, damit
Widget-Deep-Links konsistent bleiben), kein Server.
**Aufwand:** M · **Score:** 6

### 24. 🌌 Lock-Screen-Wallpaper-Generator

**Konzept:** Die App rendert euer Paar-Wallpaper: Lieblingsfoto mit
Tiefen-Layout-sicherem Beschnitt, Countdown zum nächsten Moment, Monogramm,
Paar-Gradient — in die Fotobibliothek exportiert, mit Mini-Anleitung zum
Einrichten (inkl. passender Lock-Screen-Widgets als Kombi-Vorschlag).
**Machbarkeit (Sideload):** ✅ Export voll machbar (`PHPhotoLibrary`, Add-only-
Permission existiert). Ehrlich: Eine API zum **automatischen Setzen** des
Wallpapers gibt es nicht — es bleibt ein 2-Tap-Manual-Schritt.
**Aufwand:** S–M · **Score:** 7

---

## C. Delight & Gamification

### 25. 🏆 Beziehungs-Level-System „Zusammen-Level"

**Konzept:** Die Gamification-Schicht über allem: XP für gemeinsame Aktionen
(beide eingecheckt, Tagesfrage beantwortet, Spiel beendet, Foto des Tages,
Streak-Tage, Brief geöffnet …), Level mit liebevollen Titeln („Frisch
verliebt" → „Turteltauben" → „Eingespieltes Team" → „Seelenverwandte" →
„Legendäres Duo"), Level-Up als Vollbild-Zeremonie mit Konfetti +
Haptik-Fanfare. Level & XP-Ring auf Dashboard und als Widget. Wichtig:
belohnt **gemeinsames** Handeln (XP-Bonus, wenn beide am selben Tag aktiv
waren), nie Druck (kein XP-Verlust).
**Machbarkeit (Sideload):** ✅ Voll — der Server hat alle Events schon; XP
wird deterministisch aus vorhandenen Daten aggregiert (Muster: yearreview),
d. h. rückwirkend fair für Bestandspaare. Neuer Endpoint `GET /api/level` +
WS-Event; Anti-Cheat unkritisch (eigener Server, eigene Ehre).
**Aufwand:** L · **Score:** 10

### 26. 🎖 Abzeichen-Sammlung (Achievements)

**Konzept:** Sammelbare Glas-Medaillen im „Trophäen-Regal": „100 Küsse",
„30-Tage-Serie", „Nachteulen" (Chat nach Mitternacht), „Frühaufsteher-Duo",
„Weltenbummler" (10 Date-Ideen erledigt), „Picasso-Paar" (50 Canvas-Werke),
geheime Abzeichen (werden erst bei Freischaltung enthüllt 👀). Jedes Abzeichen
prozedural gerendert im Liquid-Glass-Stil, teilbar in den Chat.
**Machbarkeit (Sideload):** ✅ Voll — gleiche Daten-Aggregation wie Idee 25
(idealerweise zusammen bauen), Freischalt-Moment mit Delight-Engine
(Idee 27). Kein Push nötig: Prüfung bei App-Start/Events.
**Aufwand:** M · **Score:** 9

### 27. ✨ Delight-Engine (zentrale Mikro-Feier-Schicht)

**Konzept:** Ein zentrales System entscheidet: „Das hier ist ein Moment!" —
runde Zähler (500. Nachricht!), Streak-Meilensteine, Feiertage, erster
Schnee-Tag im Winter-Theme — und feuert eine konsistente Feier-Choreografie
(Partikel-Burst + Haptik-Motiv + Sound-Sting, in 3 Intensitäten). Statt
verstreuter Einzel-Konfettis eine kuratierte Delight-Sprache.
**Machbarkeit (Sideload):** ✅ Voll — reines Client-Refactoring + Regelwerk;
injizierte Clock für Testbarkeit. Macht alle künftigen Delight-Ideen billiger.
**Aufwand:** M · **Score:** 8

### 28. 🥚 Geheime Gesten & Easter Eggs

**Konzept:** Mit dem Finger ein Herz aufs Dashboard malen → Herzregen + auto-
Herzklopfen an den Schatz. Das 3D-Herz lange halten → es flüstert euren
Kosenamen (Synthese). An Feiertagen versteckt sich ein Mini-Emoji im UI —
wer es findet, darf es dem Partner „zuwerfen". Entdecker-Freude statt Feature-
Liste.
**Machbarkeit (Sideload):** ✅ Voll — Gesten-Erkennung (Herz-Shape-Matching
ist mit Pfad-Sampling gut lösbar), alles lokal + vorhandene Touch-API.
**Aufwand:** S · **Score:** 8

### 29. 🎆 Jahrestags-Feuerwerk

**Konzept:** Am Jahrestag (und zu Mitternacht, wenn die App offen ist)
übernimmt ein Vollbild-Feuerwerk mit Haptik-Choreografie (jede Rakete ein
anderes Haptik-Muster!) und den Jahres-Zahlen als Sternenbild. Monatstage
bekommen die Mini-Version — die 2.0-Monatstag-Feier wird zum Ereignis.
**Machbarkeit (Sideload):** ✅ Voll — SpriteKit-Partikel + CoreHaptics-Sync,
Datum-getriggert (injizierte Clock, testbar). Kein Server nötig.
**Aufwand:** S · **Score:** 8

### 30. 💥 Chat-Sende-Effekte

**Konzept:** Nachrichten „mit Effekt senden": Herzregen, Feuerwerk, Slam,
oder **unsichtbare Tinte** — der Partner rubbelt die Nachricht mit dem Finger
frei (perfekt für Überraschungen). Effekt spielt beim Empfänger einmalig
vollbild ab, danach dezentes Badge an der Bubble.
**Machbarkeit (Sideload):** ✅ Voll — 1 Feld `effect` an der Message
(abwärtskompatibel `null`), Effekte über die Delight-Engine; Empfang live via
WS oder beim Öffnen (Badge „ungespielter Effekt").
**Aufwand:** M · **Score:** 8

### 31. 🫀 Haptik-Duett (synchron auf beiden Geräten)

**Konzept:** Ihr startet gemeinsam ein Muster aus eurer Haptik-Bibliothek —
der Server zählt 3-2-1 und **beide iPhones vibrieren im selben Moment
dasselbe Gefühl**. Als Ritual inszeniert (Einladung → Partner tritt bei →
Countdown → Duett), z. B. als „Gute-Nacht-Herzschlag" in der Fernbeziehung.
**Machbarkeit (Sideload):** ✅ Machbar — beide Apps müssen offen sein (ehrlich:
ohne Push kein Aufwecken; die Einladung kommt via WS/beim Öffnen).
Synchronität: Clock-Offset-Schätzung über WS-Roundtrips (NTP-light, ±30 ms
reicht für Haptik), Start-Timestamp vom Server. AHAP-Abspielen ist identisch
deterministisch.
**Aufwand:** M · **Score:** 9

### 32. 💓 Live-Herzschlag-Streaming

**Konzept:** Du hältst den Finger aufs 3D-Herz und tippst deinen Rhythmus —
der Partner **fühlt ihn in Echtzeit** am anderen Ende (wie Apple-Watch-
Digital-Touch, aber iPhone-zu-iPhone). Der Bildschirm des Empfängers pulsiert
synchron mit. Das intimste Feature der App.
**Machbarkeit (Sideload):** ✅ Machbar, wenn beide online sind — Tap-Events
als leichtgewichtige WS-Messages (das Kritzel-Canvas streamt heute schon
Punkte in Echtzeit, gleiche Infrastruktur!), Empfänger spielt transiente
CoreHaptics-Events mit Jitter-Puffer (~150 ms). LAN/Tailscale-Latenz ist gut
genug; bei schlechter Leitung ehrlicher Fallback auf „Muster senden".
**Aufwand:** M · **Score:** 9

### 33. ⛅️ Beziehungs-Wetter

**Konzept:** Aus beiden Stimmungen destilliert das Dashboard ein „Wetter":
beide 🥰 = Sonnenschein mit Regenbogen; einer 😢 = sanfter Regen — und die App
schlägt vor, den „Schirm aufzuspannen" (Umarmung/Check-in senden). Empathie-
Nudge als Wetterbericht, nie als Vorwurf.
**Machbarkeit (Sideload):** ✅ Voll — reine Client-Ableitung aus vorhandenen
Mood-Daten, Wetter-Rendering teilt sich Partikel-Technik mit Idee 15.
**Aufwand:** S · **Score:** 7

---

## D. Onboarding, Umzug & Fundament

### 34. 🪄 Onboarding-Magie: die „Erste-Woche-Quest"

**Konzept:** Neue Paare bekommen nach dem Pairing (mit „Partner ist
beigetreten!!"-Konfetti-Moment) einen liebevollen 7-Schritte-Pfad: erstes
Herzklopfen, erste Tagesfrage, erstes Foto, erstes Kritzel-Kunstwerk … Jeder
Schritt feiert (Delight-Engine), am Ende steht die erste Urkunde + erstes
Level-Up (Idee 25). Verwandelt Feature-Überforderung in eine Entdeckungsreise.
**Machbarkeit (Sideload):** ✅ Voll — Fortschritt aus vorhandenen Server-Daten
ableitbar (kein neuer State nötig), Quest-Karte auf dem Dashboard, für
Bestandspaare automatisch übersprungen.
**Aufwand:** M · **Score:** 8

### 35. 📦 Umzugs- & Backup-Assistent

**Konzept:** „Neues iPhone?"-Flow: Das alte Gerät zeigt einen QR mit
**kurzlebigem Transfer-Code**, das neue scannt → Server-Verbindungen,
Kopplung und Einstellungen sind drüben; danach Checkliste (Widgets neu
anlegen, Vault-PIN eingeben — E2E-Schlüssel wandert bewusst NICHT mit).
Ergänzt den bestehenden Datei-Export zu einem runden Sicherheitsnetz — gerade
weil iCloud-Backup auf Sideload meist wegfällt.
**Machbarkeit (Sideload):** ✅ Voll — genau dafür gedacht. Server: Transfer-
Code-Endpoint (10 min gültig, einmalig, gibt Token+Settings-Blob heraus) statt
Roh-Token im QR. 7-Tage-Resign-Realität macht diesen Flow doppelt wertvoll.
**Aufwand:** M · **Score:** 7

### 36. ⏳ Zeitkapsel-Briefe

**Konzept:** Ein Brief, der erst an Datum X aufgeht — „Öffne mich an unserem
Jahrestag" / „…in einem Jahr". Bis dahin zeigt er ein tickendes Countdown-
Siegel (und ein Widget kann mitzählen); am Stichtag bricht das Siegel mit der
großen Enthüllungs-Zeremonie. Vorfreude als Feature.
**Machbarkeit (Sideload):** ✅ Voll — Erweiterung der versiegelten Briefe um
`unlockAt`; der **Server** hält den Inhalt bis zum Stichtag zurück (kein
Client-Schummeln). Erinnerung als lokale Notification.
**Aufwand:** M · **Score:** 9

---

## 🥇 Top-10 für 3.0 (priorisiert)

Kriterien: Delight-Faktor × Sideload-Tauglichkeit × Synergie untereinander.
Die Reihenfolge ist eine Bau-Empfehlung (27 vor 25/26, weil Fundament).

| # | Idee | Aufwand | Score | Warum jetzt |
|---|------|---------|-------|-------------|
| 1 | **27 · Delight-Engine** | M | 8 | Fundament — macht alle folgenden Feier-Momente konsistent & billig |
| 2 | **25 · Beziehungs-Level-System** | L | 10 | Das 3.0-Flaggschiff: Gamification-Schicht über allem, rückwirkend fair aus Server-Daten |
| 3 | **26 · Abzeichen-Sammlung** | M | 9 | Zwilling des Level-Systems, gleiche Aggregation — zusammen bauen |
| 4 | **1 · App-Icon-Geschenke** | M | 9 | Sichtbarste Personalisierung überhaupt (Home Screen!), voll sideload-fähig |
| 5 | **3 · Controls-Familie (iOS 18)** | M | 9 | Herzklopfen vom Kontrollzentrum/Action Button — Plattform-Magie ohne Entitlement-Risiko |
| 6 | **31+32 · Haptik-Duett & Live-Herzschlag** | M | 9 | Baut direkt aufs 2.0-Haptik-Studio & Canvas-Realtime auf — das intimste Feature |
| 7 | **9 · Date-Night-Live-Activity** | M | 9 | Nutzt die 2.0-LA-Infrastruktur, LiveActivityIntent-Trick umgeht die Push-Grenze elegant |
| 8 | **14+15 · Saison-Themes + Partikel** | M | 8 | Die App lebt mit dem Jahr; Partikel-Layer füttert auch Idee 29/33 |
| 9 | **19 · Polaroid-Foto-Widgets** | S–M | 8 | Kleiner Aufwand, großer Home-Screen-Effekt; Widget-Studio existiert schon |
| 10 | **34 · Onboarding-Quest** | M | 8 | Neue Paare erleben 3.0 als Reise statt Feature-Wand; nutzt Level-System als Finale |

**Ausblick 4.0:** 4 (Siri/Automationen), 30 (Sende-Effekte), 36 (Zeitkapsel),
17 (Kosenamen), 28 (Easter Eggs), 6 (StandBy-Nachtlicht), 13 (Paar-Farben),
35 (Umzugs-Assistent).
**Ausblick 5.0:** 11 (iPad, L), 22 (Sticker-Werkstatt, L), 16 (Sound-Themes),
5 (Spotlight), 24 (Wallpaper), 7/8 (Watch-Pfad — 8 zuerst, 7 nur als
dokumentiertes Selbstbau-Target).
