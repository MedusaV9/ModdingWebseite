# MASTERPLAN — Monkey Money Party-Abend-App

> Stand: Audit + Welle 1 (Branch `cursor/monkey-money-82d4`). Grundlage: kompletter
> Code-Audit (Server-Engine, alle 27 Minispiel-Plugins, Clients, Content-Loader,
> Doku in `docs/`, `UserFeedback.md` inkl. Eval-Welle 1 mit 1 JA / 9 NEIN).

---

## 1. Architektur-Zusammenfassung (Ist)

```
MonkeyMoney/
├─ shared/            reine, beidseitig importierbare Logik (JSON-serialisierbar)
│  ├─ settings.ts     MatchSettings + MODUS_BLAUPAUSEN (quick/klassik/marathon)
│  ├─ money.ts        FRAGE_WERTE (100/250/500/1000), FRAGE_TIMER_MS, Speed-Bonus
│  ├─ economy.ts      Streak-/Rückenwind-Faktoren, W_final, Dispo, AT-Umrechnung
│  ├─ pacing.ts       ★ NEU (Welle 1): zentrale Pacing-Config aller Phasen-Timer
│  ├─ balance.ts      ★ NEU (Welle 1): Economy-Tabelle aller Rewards/Preise
│  └─ minigames/*.meta.ts   27 Meta-Module (IDs, Namen, Formate, Konstanten)
├─ server/
│  ├─ core/           HTTP + socket.io, Kommando-Parsing (gm-commands, sockets)
│  ├─ rooms/          Raum-Verwaltung, Sessions, gmPin, startMatch (Fragen-Pick)
│  ├─ engine/         pure State-Machine: flow.ts (Phasen), plan.ts (Match-Plan,
│  │                  Fragenwahl, Kategorie-Optionen), economy, joker, rad, auto-gm
│  ├─ minigames/      27 Server-Plugins (init/reduce/tick/viewFor/scores/outcomes)
│  └─ content-loader/ Fragen-/Song-Packs, pickQuestions (Filter + Dedupe)
├─ client/
│  ├─ screen/         TV/iPad-Ansicht (lit-html), Lobby zeigt Join-Code (+ GM-PIN)
│  ├─ player/         Handy-Ansicht, minigame-Renderer aus client/shared/minigames
│  ├─ gm/             Show-Master-Cockpit (PIN-Auth, flow.next = Universal-Weiter)
│  └─ shared/         Transport (socket.io + standalone-WebSocket für iPad-Modus)
├─ ios/               WKWebView-Wrapper (iPad = Screen ODER Standalone-Server)
├─ tools/bots/        E2E-Bots (Vollmatch-Simulation)
└─ docs/              TECH-SPEC, GAME-DESIGN, ARCHITEKTUR, CONTENT-PLAN
```

**Kernprinzipien:** Engine ist eine pure Reducer-State-Machine (`EngineState`
JSON-serialisierbar, Timer NUR serverseitig, RNG injiziert via `ctx.rng`).
Minispiele sind Plugins mit festem Vertrag (`meta`, `init`, `reduce`, `tick`,
`viewFor`, `isFinished`, `scores`, optional `outcomes`). Alle Clients rendern
role-basierte Views (`viewFor(role)`) — Leak-Schutz by design. Standalone-iPad
läuft über `client/shared/standalone-transport.ts` (WebSocket-Emulation des
socket.io-Protokolls) — jede neue Client→Server-Message muss dort mitgezogen
werden.

---

## 2. Ist-Analyse aller 27 Minispiele

Legende Pacing-Befund: 🔴 zu schnell (Eval-kritisch) · 🟡 grenzwertig · 🟢 ok.

| #   | Minispiel (ID)                                                  | Flow (Kurz)                                                                                | Balance                                        | Pacing                            | Befund / Bugs                                                                                                           |
| --- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------- | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 1   | **Bananen-Basics** (`bananen-basics`)                           | MC-4-Opener, alle simultan, Streak-Bauer, R1 verlustfrei                                   | Grundwerte 100–250 + Speed-Bonus               | 🔴 Auflösung 6 s, Timer 15 s easy | Auflösung zu kurz um Erklärung zu lesen                                                                                 |
| 2   | **Stopp die Kokosnuss-Uhr** (`kokosnuss-uhr`)                   | Countdown-Sack schrumpft in 50-MM-Ticks, stoppen = kassieren wenn richtig                  | Sack-Mathe deterministisch, Tick 50 MM         | 🟡                                | Client-Formel = Server-Formel (gut); Stress-Format                                                                      |
| 3   | **Der Bananen-Tresor** (`bananen-tresor`)                       | Schätzfrage per Slider, Nähe-Ranking, Festwert-Auszahlung                                  | Festwerte ok                                   | 🟡 20 s Timer                     | solide; Slider am Handy fummelig (UI-Welle 2)                                                                           |
| 4   | **Affenleiter** (`affenleiter`)                                 | Sortier-Frage (dragList), Streak nur bei Komplett-Richtig                                  | ok                                             | 🟡 30 s Timer                     | dragList am Handy klein (UI-Welle 2)                                                                                    |
| 5   | **Pixel-Dschungel** (`pixel-dschungel`)                         | Bild wird stufenweise scharf, Wert verfällt je Stufe (Jackpot-Treppe)                      | Treppe dokumentiert                            | 🔴 Stufe alle 3 s                 | Stufentakt zu hektisch → Pacing-Config                                                                                  |
| 6   | **Die Stinkbanane** (`stinkbanane`)                             | Pass-the-Bomb: richtig = weitergeben, falsch = behalten; verdeckter Zufalls-Zünder 45–75 s | Explosions-Malus fix                           | 🔴 **Eval-kritisch**              | „Affen-Bomben-Spiel": KEIN Cooldown nach falscher Antwort — sofort nächste Frage = Panik. ★ Welle 1: Cooldown eingebaut |
| 7   | **Der Taschendieb-Affe** (`taschendieb`)                        | schnellste richtige Antwort klaut (Fotofinish 50 ms), geheime Opferwahl, Cutscene          | Klau-Betrag geregelt                           | 🟡 Opferwahl 8 s, Cutscene 6 s    | ok, aber Verlierer-Frust (Balance-Welle 3: Klau-Kappe)                                                                  |
| 8   | **Die Affenbank** (`affenbank`)                                 | Schnellfeuer-Kette, Team-Pott 50→1.600, „BANK!"-Verrat                                     | Pott-Kappe 1.600                               | 🔴 10-s-Takt, Quick-Kette 45 s    | Takt für Party-Publikum zu schnell → Pacing-Config                                                                      |
| 9   | **Alles oder Banane** (`alles-oder-banane`)                     | geheime Wette auf eigene Antwort, Reveal vor Frage, ±Einsatz                               | exakt ±Einsatz, keine Streak/Speed             | 🟡                                | solide; Einsatz-UI am Handy überladen (UI-Welle 2)                                                                      |
| 10  | **Das große Lianen-Finale** (`lianen-finale`)                   | Lianenlänge = normierter Kontostand, ±W_final pro Finalfrage                               | Formel §3.5 hält exakt                         | 🟢                                | solide                                                                                                                  |
| 11  | **Vier Lianen** (`vier-lianen`)                                 | MC-4-Referenzformat, volle Joker-Hooks                                                     | Standard                                       | 🔴                                | Frage am Handy in `*-frage-klein` (klein+ausgegraut), Auflösung/Erklärung NUR am TV ★ Welle 1 gefixt                    |
| 12  | **Monkey Market** (`monkey-market`)                             | 10 Bank-Chips auf 4 Falltüren verteilen, richtige Tür ×2, Mut-Bonus +25 %                  | Bank-Chips = mild                              | 🟡 Handels-Fenster                | gut designtes Geld-Format                                                                                               |
| 13  | **Bananen-Börse** (`bananen-boerse`)                            | 20 s Parkett in vier 5-s-Kurs-Blöcken, Quote sinkt mit Herde, Verkauf −25 % Spread         | Quoten-Formel ok                               | 🔴 5-s-Blöcke                     | Block-Takt zu schnell zum Verstehen → Pacing-Config + Erklärkarte länger                                                |
| 14  | **Bananen-Bluff** (`bananen-bluff`)                             | Verkünder sieht Lösung, verkündet Wahrheit/Bluff, Rest stimmt ab; ±W/2-Transfers           | nullsummig                                     | 🟢                                | solide; Onboarding nötig (Welle 2 Tooltips)                                                                             |
| 15  | **Affen-Auktion** (`affen-auktion`)                             | 20-s-Auktion im 25er-Raster, Anti-Sniping +5 s, Sieger antwortet exklusiv                  | Gebots-Limit 100–1.000, nullsummige Verteilung | 🟡                                | komplex — Erklärkarte braucht mehr Zeit (Pacing-Config)                                                                 |
| 16  | **Duell am Lianensteg** (`lianensteg-duell`)                    | Letzter fordert heraus (Feiglings-Schutz), 1v1-Buzzer, Zuschauer wetten 50 MM pari-mutuel  | exakt nullsummig                               | 🟢                                | Wett-System sauber                                                                                                      |
| 17  | **Der Goldene Affe** (`goldener-affe`)                          | 3-Stufen-Finale: Money-Drop (50 % Konto), Schätz-Showdown, Buzzer-Best-of-3                | Einsatz 50 % Konto, Gratis-Einsatz < 200       | 🟡 Drop 30 s                      | Einsatz 50 % Konto ist der größte Einzel-Swing im Spiel (Balance-Welle 3 prüfen)                                        |
| 18  | **Risiko-Leiter** (`risiko-leiter`)                             | 8-Stufen-Leiter 100→3.000, weiterklettern/absichern, Sicherheitsstufe 400                  | Leiter dokumentiert                            | 🟢                                | Klassiker funktioniert                                                                                                  |
| 19  | **Bananen-Boxkampf** (`bananen-boxkampf`)                       | 1v1, richtige Antwort = Schlag (HP-Abzug), K.O. oder Punktsieg nach 8 Fragen, Wetten       | HP nach Frage-Wert                             | 🟡                                | Buzzer-Fairness via Median-RTT ok                                                                                       |
| 20  | **Die große Bananen-Tortenschlacht** (`bananen-tortenschlacht`) | richtig = Torte werfen, 3 Torten = raus, Letzter gewinnt Topf 1.500                        | Topf 1.500 MM fix                              | 🟡                                | Survival-Design bewusst ohne Frage-Money                                                                                |
| 21  | **Konter-Quiz** (`konter-quiz`)                                 | freundliches 1v1, 8 leichte Fragen à ~8 s, Buzz = Antwort                                  | +150/Konter 150, nie an Bank zahlen            | 🔴 ~8 s pro Frage                 | Takt zu schnell → Pacing-Config                                                                                         |
| 22  | **Einer gegen alle** (`einer-gegen-alle`)                       | Führender vs. Mengen-Mehrheit, 6 Fragen, anonyme Balken                                    | 400/150/200 MM Matrix                          | 🟢                                | Leak-Wache sauber implementiert                                                                                         |
| 23  | **Der Blitz-DJ** (`song-snippet`)                               | 0,1 s Song → Buzzer, Eskalation 0,2/0,3/0,5/1/5 s, Wert verfällt je Stufe                  | Start 2×Grundwert, Strafe 50                   | 🔴 Rate-Fenster 8 s, Lauer 4 s    | hektischstes Format der Show → Pacing-Config                                                                            |
| 24  | **Rückwärts-Banane** (`song-rueckwaerts`)                       | Intro rückwärts, alle raten aus 4, Auflösung spielt vorwärts                               | MC-Standard + Speed                            | 🟡 24 s Timer                     | Aha-Moment gut                                                                                                          |
| 25  | **Stummfilm-Studio** (`musikvideo-raten`)                       | 3 s stummer Clip, Rettungsstufe mit Ton für halben Wert                                    | halber Wert Stufe 2                            | 🟡                                | braucht Song-Pack mit video3s                                                                                           |
| 26  | **Das 7-Buchstaben-Telegramm** (`buchstaben-telegramm`)         | Beschreiber tippt NUR Buchstaben, Rater wählt aus 4; Match-Budget 60 Zeichen               | +250 je Partner                                | 🟢                                | Koop-Perle; Budget-Anzeige aufs Handy (Welle 2)                                                                         |
| 27  | **Wer singt's?** (`wer-singts`)                                 | Song-Titel + Jahr auf Platten-Karte, Interpret aus 4, Ära/Genre-Distraktoren               | WS_WERT + Speed                                | 🟢                                | eingebauter 60+-Pool ok                                                                                                 |

### Querschnitts-Befunde (aus Eval-Welle 1: 1 JA / 9 NEIN)

1. **GM-PIN offen auf dem TV** — `client/screen/views.ts` rendert `view.gmPin`
   permanent in der Lobby. Jeder Gast konnte Show-Master werden. ★ Welle 1.
2. **Kein Spielen ohne GameMaster** — `flow.next` existiert nur als GM-Kommando;
   der Screen hat keine Start-/Skip-Buttons. Auto-GM überbrückt zwar Timer,
   aber Match-Start und Phasen-Skip brauchten das GM-Cockpit. ★ Welle 1.
3. **Fragen-Wiederholungen über Matches** — `room.startMatch` ruft
   `pickQuestions` OHNE `usedQuestionIds` aus früheren Matches auf: zweites
   Match des Abends = teils dieselben Fragen. ★ Welle 1 (Abend-Gedächtnis).
4. **Kategorie-Votes ignoriert** — `plan.waehleFrage` degradiert bei knappem
   Vorrat zuerst die Kategorie weg (Schwierigkeit vor Kategorie priorisiert),
   und `kategorieOptionen` bietet Kategorien an, für die es gar keine Fragen
   der Slot-Schwierigkeit mehr gibt. ★ Welle 1.
5. **Pacing global zu schnell** — Phasen-Timer hart in `server/engine/types.ts`
   (Auflösung 6 s, Zwischenstand 5 s, Kategorie-Wahl 12 s …) + pro Minispiel
   verstreute Konstanten. Kein zentraler Ort, kein „Gemütlich"-Modus. ★ Welle 1.
6. **Fragen zu klein am Handy** — Frage in `*-frage-klein`-Klassen (klein,
   `muted`), Antwort-Buttons dominieren. ★ Welle 1.
7. **„Erklärung auf TV"** — Player-View blendet in der Auflösung nur einen
   Verweis auf den Screen ein, obwohl `aufloesung.erklaerung`/`correctIndex`
   im View-Payload vorhanden sind. ★ Welle 1.
8. **Fragen zu schwer** — Slot-Pools (KONFLIKT = hard, RISIKO = hard/ultrahard)
   treffen Casual-Publikum zu hart; kein globaler Schwierigkeits-Regler.
   → Welle 2 (Settings `schwierigkeitsProfil: entspannt|standard|hardcore`).
9. **Workflows unter `MonkeyMoney/.github/` laufen nicht** — GitHub Actions
   liest nur Root-`.github/`. ★ Welle 1: Root-Workflow
   `.github/workflows/monkey-money.yml` (branch-scoped, unsignierte IPA nach
   dem Muster `build-ios-soodreamy.yml`).

---

## 3. Economy-Ist (konsolidiert; Quelle jetzt `shared/balance.ts`)

| Bereich                | Konstante                  | Wert                                         |
| ---------------------- | -------------------------- | -------------------------------------------- |
| Frage-Grundwerte       | easy/medium/hard/ultrahard | 100 / 250 / 500 / 1.000 MM                   |
| Frage-Timer            | easy/medium/hard/ultrahard | 15 / 15 / 20 / 25 s (Basis, × Pacing-Faktor) |
| Affenbank-Pott         | Kette                      | 50→100→200→400→800→1.600 (Kappe)             |
| Einer gegen alle       | Solo/Beide/Team            | 400 / 150 / 200 MM                           |
| Konter-Quiz            | richtig/Konter             | 150 / 150 MM                                 |
| Telegramm              | Erfolg je Partner          | 250 MM                                       |
| Tortenschlacht         | Topf                       | 1.500 MM                                     |
| Blitz-DJ               | Start/Falsch-Buzz          | 2×Grundwert / −50 MM                         |
| Wetten (Steg/Boxkampf) | Einsatz                    | 50 MM, pari-mutuel nullsummig                |
| Risiko-Leiter          | Stufen                     | 100→200→400→700→1.100→1.600→2.200→3.000      |
| Kokosnuss-Uhr          | Sack-Tick                  | 50 MM                                        |
| Dispo/Mitleid          | `economy.ts`               | DISPO_LIMIT, MITLEIDS_BANANE (unverändert)   |

**Kunden-Befund „500M vs 100M, Shop 50M":** Die Spanne easy 100 ↔ ultrahard
1.000 ist gewollt (Progression), aber Sonder-Formate (Goldener Affe 50 % Konto,
Tortenschlacht-Topf 1.500) sprengen die Kurve relativ zum AT-Shop (Preise um
50 AT). Ziel-Kurve Welle 3: alle Sonder-Payouts als Vielfache des
Slot-Grundwerts W ausdrücken (bereits bei Bluff W/2, Börse W/2, Market W/10 der
Fall) + AT-Umrechnung (`atFuerEndstand`) gegen die neuen Maxima kalibrieren.

---

## 4. Wellenplan

### ✅ Welle 1 — Quick-Wins (DIESER Branch, umgesetzt)

1. **`MASTERPLAN.md`** (dieses Dokument).
2. **`shared/pacing.ts`** — zentrale Pacing-Config: alle Phasen-Timer an einem
   Ort, globaler `PACING_FAKTOR` (Default 1,5 = „ruhiger Vibe"), deutlich
   längere Auflösung (6→12 s), Zwischenstand (5→9 s), Kategorie-Wahl (12→18 s),
   Erklärkarte (12→16 s), plus `ANTWORT_COOLDOWN_MS` nach falschen Antworten.
   `server/engine/types.ts` re-exportiert daraus (keine Callsite-Änderungen).
3. **Stinkbanane-Cooldown** — nach falscher Antwort friert die Banane
   `SB_COOLDOWN_MS` (4 s) ein: Zünder pausiert, Halter sieht „Durchatmen…",
   dann erst die nächste Frage.
4. **Fragen-Dedupe (Abend-Gedächtnis)** — Raum merkt sich benutzte Fragen-IDs
   über Matches hinweg (`abendFragenIds`, LRU-gedeckelt); `startMatch` übergibt
   sie an `pickQuestions`.
5. **Kategorie-Vote-Fix** — `waehleFrage`-Degradationskette hält die Kategorie
   länger als die Schwierigkeit; `kategorieOptionen` bietet nur Kategorien mit
   tatsächlich vorhandenen Fragen der Slot-Schwierigkeit an.
6. **Handy-Lesbarkeit** — globale CSS-Regel für `*-frage-klein` (größer, nicht
   mehr muted); Auflösung am Handy zeigt richtige Antwort + Erklärung.
7. **PIN-Reveal + GM-Link** — Lobby versteckt die PIN hinter „🎩 Show-Master…"
   (Tipp zum Aufdecken) und zeigt dort den GM-Link.
8. **Start/Skip ohne GameMaster** — Screen bekommt Start-Button (Lobby) und
   Weiter/Skip-Button (In-Match), neues `screen.next`-Kommando (auch im
   Standalone-Transport).
9. **`shared/balance.ts`** — Economy-Tabelle als Single Source of Truth +
   Invarianten-Test (Werte konsistent, Rundungs-Raster, Nullsummen-Formate).
10. **Root-Workflow `.github/workflows/monkey-money.yml`** — branch-scoped auf
    `cursor/monkey-money-82d4`: Lint + Tests + Web-Build + unsignierte IPA
    (macOS-Runner, Muster `build-ios-soodreamy.yml`).
11. **Verifikation** — `npm test` (Server) + Bots-Vollmatch (kompletter
    Quiz-Durchlauf) mit gesichertem Log.

### Welle 2 — UX, Onboarding, Verbindung

- **Schwierigkeits-Profil** in `MatchSettings` (`entspannt|standard|hardcore`):
  mappt Slot-Pools um (KONFLIKT easy/medium im Entspannt-Profil), Anteil
  ultrahard global gedeckelt.
- **Handy-Interface entrümpeln**: eine Aktion pro Screen, Sekundäres in
  ausklappbare Leiste; Profil-Laden robust (Retry + Skeleton statt Spinner).
- **iPad-Layout dynamisch**: Videos/Fragen skalieren mit Viewport, Chat
  kollabierbar; Stage-Manager-taugliche Breakpoints.
- **Onboarding/Tooltips**: Erste-Schritte-Overlay je Rolle, „Was ist das?"-Info
  auf Erklärkarten (nutzt vorhandene `tutorialVideos`-Infrastruktur).
- **Host-Button in der App**: Custom-Settings-Sheet (Modus, Pacing-Profil,
  Schwierigkeit, Joker, Musik) direkt vom iPad, ohne GM-Cockpit.
- **Tunnel ohne Hotspot**: `cloudflared` Quick-Tunnel als opt-in
  (`npm run tunnel` bzw. Server-Flag `--tunnel`), QR-Code mit öffentlicher URL
  auf dem Screen; Fallback lokale IP.
- **Geld-Gewinn-Präsentation**: Count-Up-Animation + Münzregen auf Screen,
  haptisches Feedback am Handy.
- **Echte Sounds**: CC0/CC-BY-Pakete (kenney.nl UI/Coins, opengameart Jingles,
  pixabay Ambience) statt synthetischer WebAudio-Bleeps; `assets/AUDIO-LICENSES.md`
  mit Quelle+Lizenz je Datei; `LICENSING.md` (Root) für Agentur-Song-Einkauf,
  CC-Songs als Platzhalter markiert.

### Welle 3 — Balance-Kurve, Cosmetics, Meta

- **Economy-Kurve v2**: alle Sonder-Payouts als W-Vielfache normieren; Klau-
  und Drop-Kappen (Taschendieb, Goldener Affe) relativ zum Median-Konto; AT-
  Umrechnung + AllTime-Shop-Preisleiter (Common 50 → Legendary 2.000 AT).
- **Cosmetic-AllTime-Shop fertig**: Kauf-Flow, Besitz-Sync, Vorschau im Match.
- **Char-Auswahl v2**: Grid mit Live-Vorschau, Color-Wheel + Hex-Eingabe,
  freischaltbare Effekte (Glow, Trail, Konfetti) als AT-Items.
- **Evals**: 2. Eval-Runde mit echtem Spielen (Bots + Menschen), Messpunkte:
  Fragen-Wiederholungsrate, Vote-Treffer-Quote, empfundenes Tempo.

### Welle 4 — Neue „Monkey Edition"-Spiele (eigene Namen/Regeln, markenrechtlich sauber)

Alle als neue Plugin-Familie `boardgames/` (eigener Engine-Modus „Brettspiel-
Abend" neben der Quiz-Show), Pass-and-Play am iPad UND Handys als Controller,
3D-Optik via CSS-3D/Canvas wo sinnvoll:

| Arbeitstitel                  | Inspiration    | Kern-Twist (eigene Regeln)                                                                          |
| ----------------------------- | -------------- | --------------------------------------------------------------------------------------------------- |
| **Schattendschungel**         | Werwolf-artig  | Rollen = Dschungeltiere; Tag/Nacht über Screen-Ambience; Bananen-Bestechung als eigenes Element     |
| **Bananen-Stapel**            | Uno-artig      | Farb-/Zahlkarten als Bananenstauden; „Affenalarm"-Karte dreht Spielrichtung UND Kontostände-Anzeige |
| **Insel der Affen**           | Catan-artig    | Hex-Insel, Ressourcen Bananen/Holz/Kokos; Handel über die bestehende Monkey-Market-Mechanik         |
| **Ärger im Urwald**           | MädN-artig     | Würfeln via Handy-Shake; Rauswurf füttert das Mitleids-Bananen-System                               |
| **Monkey Boulevard**          | Monopoly-artig | Felder = Minispiel-Trigger (Quiz-Integration!); MM-Währung durchgängig                              |
| **Tempel des Goldenen Affen** | EIGENES Spiel  | Koop-Dungeon: Team klettert Tempel-Ebenen, Fallen = Mini-Quizzes, Verräter-Mechanik ab 5 Spielern   |

Technische Basis dafür: Plugin-Vertrag erweitern um `boardState`
(persistenter Spielbrett-Zustand über Runden), Pass-and-Play-Rolle im
Standalone-Transport, 3D-Layer im Screen-Client.

---

## 5. Test-/Verifikations-Strategie (jede Welle)

1. `npm test` (Vitest: Engine, Economy, Content-Loader, Balance-Invarianten).
2. Bots-Vollmatch (`tools/bots`): komplettes Match quick+klassik, Log als
   Artefakt sichern.
3. Manuelle Evals: Server lokal, 1 Screen + 2+ Handys, Checkliste aus
   `UserFeedback.md` (Eval-Welle) erneut durchspielen.
4. CI: Root-Workflow baut Lint+Test+Web+IPA auf jedem Push des Branches.
