# G8-IDEEN — MINISPIELE + ARCADE (Ideen-Planner IP-3, Welle I)

**Bereich:** die 38 Minispiele, der Arcade-Rahmen (Host/Pregame/Results/Modifier),
Wettbewerbe/Turniere, Multiplayer-Minispiele (GOB-NOM-Coop + GvZ-PvP existieren,
Ranch-MP mit Bestenlisten/Geistern existiert) und die Arcade als ORT/Gefühl.
**Quellen:** `UserFeedback.md` (komplett), `docs/godot-rewrite/G-minigames.md`,
Code-Streifzug durch `GOOBY-GODOT/scripts/minigames/**` (Host-Rahmen G7-P56:
`minigame_host.gd` + `pregame.gd` + `results.gd` + `minigame_registry.gd` +
`modifier_engine.gd` + `minigame_award.gd`), `scripts/ranch/comp/**` (Liga, Bots,
Turniertag, Geister), `scripts/ranch/mp/**` + `GOOBY-SERVER/src/*` (gobnommp,
gvzmp, ranchmp-Leaderboards, mail, boardgames, goobypal), `git log -30`.
Nur gelesen, nichts geändert. Die Parallel-Dokumente `G8-IDEEN-home-seele.md`
und `G8-IDEEN-stadt-laeden-dlc.md` wurden gelesen — nichts hieraus doppelt sie.

**Woran sich jede Idee messen muss (aus UserFeedback destilliert):** Der User
liebt Dopamin-Momente (Rekord-Fanfare, Count-Ups, Konfetti), Multiplayer
(GOB-NOM/GvZ/Ranch-MP waren alles seine Wünsche), Liebe zum Detail und das
„EIN Spiel"-Gefühl. G7-P56 hat den RAHMEN vereinheitlicht (Wipe, Pregame,
Countdown, Pause, Results — Registry-Wache `test_g7_rahmen`) — aber ZWISCHEN
den Runden ist die Arcade noch ein stummes Kachel-Grid: die Kacheln zeigen
null Fortschritt, nichts spannt einen Bogen über die 38 Spiele, kein Rivale
wartet, kein Termin lockt zurück. Der Trailer endet auf „38 Minispiele" —
diese Ideen machen aus der Zahl ein ERLEBNIS.

**Harte Leitplanken aus dem Bestandscode (gelten für ALLE Ideen unten):**
Ökonomie läuft IMMER über den einen Geld-Pfad (`Economy.award` mit Reason +
Tages-Ledger; Minigame-Coins deckelt `MinigameAward.MINIGAME_DAY_CAP = 150`,
Energie-Bremse 8/Runde bleibt unangetastet — §C-SYS11.1/§C6). Kein Spiel
umgeht den Host-Rahmen (Registry-Wache). Determinismus: Zeit/RNG werden
hereingereicht (`GoobyRng`/mulberry32, `clock`-Injektion) — alles headless
testbar, das Playtest-Harness (G7-P58) kann jeden Flow nachspielen.
Reduced-Motion-Pfad für jede Inszenierung. Kein Abstieg, keine Strafen
(Wohlfühl-Grundsatz aus `comp_liga.gd`). Strings DE/EN mit Domain-OWNERSHIP.

---

## Genre-Lücken-Analyse der 38 Spiele (Basis für die Neu-Konzepte)

Bestand nach Spielart geclustert (Registry: 4 feste Einträge + 34
`game.json`-Manifeste in `scripts/minigames/games/*/`):

| Cluster | Spiele |
|---|---|
| Fangen/Timing/Reaktion | teaParty, carrotCatch, veggieChop, goalieGooby, bunnyHop, trampoline, basketBounce, pancakeTower, fishingPond, bubblePop, ghostHunt |
| Runner/Ausweichen/Fahren | runner, shoppingSurf, starHopper, harborHopper, cityDrive, deliveryRush, toyRacer, snailMail, lanternFloat, rocketRescue |
| Denk/Memory/Puzzle | memoryMatch, goobySays, purblePlace, pipeFlow, gobnom |
| Defense/Taktik | gvz, carrotGuard |
| Rhythmus | danceParty |
| Sport/Physik | miniGolf (+ goalieGooby/trampoline/basketBounce oben) |
| Sammeln/Abarbeiten | gardenRush, burgerBuild, hideSeek |
| Ranch-Reiten | ranchHerde, ranchParcours, ranchTonnen, ranchTurnier, ranchZeit |

**Lücke 1 — die Arcade-Ikone fehlt in der Arcade:** kein einziges Spiel mit
Paddle-/Abprall-Physik (Flipper/Breakout-Klasse). Ausgerechnet das Genre, das
„Arcade" DEFINIERT und das dichteste Score-Feuerwerk liefert, ist unbesetzt.
**Lücke 2 — kein Spiel, dessen Belohnung ein DING ist:** alle 38 zahlen
Score/Münzen. Ein Preis-Automat (Greifer), bei dem man ein sichtbares Objekt
GEWINNT, verbindet Spielen mit Sammeln — die Brücke zur Belohnungs-Verzahnung.
**Lücke 3 — null lokales Duell:** sämtliche 38 sind Solo; Multiplayer läuft
ausschließlich über zwei Geräte (Lockstep/Relay). Ein 2-Spieler-Duell an EINEM
Gerät (geteilter Touchscreen) ist die billigste Couch-Multiplayer-Form — und
mit Luft-Hockey zugleich Arcade-authentisch.
(Kleinere unbesetzte Nischen, bewusst NICHT priorisiert: Zieh-und-Schleuder-
Zerstörungsphysik, Falling-Block-Stapelpuzzle — beide gut als spätere
Manifest-Spiele, das W6-Manifest-System macht Neuzugänge parallelisierbar.)

---

## TOP-3 (Begründung)

**🥇 Nr. 1 „Arcade-Sternenbuch":** Die 38 Spiele erzeugen längst
Meta-Daten (`minigames.legacy.beaten/best/bestByDiff/endlessBest`, `plays` —
alles liegt im Save!), aber NICHTS zeigt sie an: die Arcade-Kacheln sind
stumme Cover, der Zähler in der Kopfzeile zählt nur „38 Spiele". Ein
Sternen-Stand je Kachel + ein Sammel-Board mit Meilenstein-Belohnungen macht
aus 38 Einzelspielen EINE Sammlung — Meta-Progression ohne ein einziges neues
Spielsystem, nur Sichtbarkeit auf getesteten Daten. Der direkteste Hebel
gegen „fühlt sich wie einzelne Games an" auf der Arcade-Ebene.

**🥈 Nr. 2 „Rekord-Puls":** Der Rekord ist heute NUR im Results-Screen
erlebbar — dabei kennt der Host in jeder Sekunde Score UND Bestwert
(`_on_game_score` + `MinigameFrameworkLogic.best_for_mode`). Live-Spannung
kurz vor dem Rekord + sofortige Feier beim Überholen ist der größte
Dopamin-Gewinn pro Zeile Code, wirkt zentral in ALLEN 38 Spielen gleichzeitig
(Host-Schicht, kein Spiel wird angefasst) und passt exakt zu dem, was der
User seit W13 einfordert.

**🥉 Nr. 3 „Brief-Duell":** DER Multiplayer-Ausbau mit dem besten
Verhältnis aus Wow und Risiko: asynchrone Score-Duelle an Freunde brauchen
KEIN Live-Matchmaking, weil die komplette Infrastruktur existiert —
deterministische Runden über `run_seed` (Host nimmt den Seed schon als
Router-Param!), Freunde/Postfach/idempotente Claims (`mail.js`,
`gobnommp.js`-Result-Muster). Zwei Spieler, dieselbe Saat, ein Umschlag:
Multiplayer für alle 38 Spiele auf einen Schlag, auch wenn nie beide
gleichzeitig online sind.

---

## Die priorisierte Liste (A1–A15)

### A1 — „Arcade-Sternenbuch": die 38 werden EINE Sammlung
**Aufwand: M · Impact: 5 · Risiko: niedrig**

Jedes Spiel bekommt einen sichtbaren Sammel-Stand aus DATEN, DIE ES SCHON
GIBT: ★ gespielt (`minigames.plays`), ★★ Ziel geschlagen
(`legacy.beaten[id].normal`, Ziel steht als `target` in der Registry), ★★★
Ziel auf Schwer (`beaten[id].hard` — dieselbe Bedingung, die heute schon
Endlos freischaltet). Die Arcade-Kacheln (`arcade_screen.gd::_build_tile`)
tragen die Sterne als kleine Pips unterm Cover plus den Bestwert; die
Zähler-Kapsel der Kopfzeile (`_build_count_capsule`) wird zum
Fortschritts-Zähler („23/114 ★"). Dazu ein Sternenbuch-Sheet (PanelSheet aus
G7-P53) mit Meilenstein-Leiste: 10/25/50/80/114 Sterne schalten je EINE
fühlbare Belohnung frei — ein Arcade-Sticker (neue Einträge auf der
vorhandenen `arcadeStars`-Seite in `content/stickers/data/stickers.json`),
ein Arcade-Automat als Home-Möbel (`furniture_catalog.gd`), ein
Profil-Titel nach Weltengooby-Muster („Arcade-Legende"). Kein neues
Grind-System: das Buch füllt sich rückwirkend beim ersten Öffnen (die Boards
existieren seit W1d) — der „OH, ich hab ja schon 19 Sterne!"-Moment ist
gratis. Code-Anker: `scripts/minigames/arcade_screen.gd`,
`framework_logic.gd::difficulty_slice_of`, `save_schema.gd`
(`minigames.legacy`), `content/stickers/data/stickers.json`.
Risiko: niedrig — reines Lesen + ein Sheet; einzig die Kachel-Dichte im
Leitformat 2868×1320 braucht einen FB3-Audit-Durchlauf.

### A2 — „Rekord-Puls": der Bestwert lebt IN der Runde
**Aufwand: S–M · Impact: 5 · Risiko: sehr niedrig**

Der Host kennt beim Start den Bestwert des gewählten Modus
(`best_for_mode`) und bekommt jeden Score-Tick (`_on_game_score(total,
delta)`) — daraus wird Live-Dramaturgie für ALLE 38 Spiele, ohne ein
einziges Spiel anzufassen: ab 80 % des Bestwerts beginnt die Score-Pill
leise golden zu schimmern (+ ein einmaliger Herzschlag-Sound, Cooldown),
beim ÜBERHOLEN zündet sofort ein „NEUER REKORD!"-Float mit Goldblitz
(`juice.float_text`/`hit_flash` über die G7-Juice-Ebene, die exakt dem
letterboxten Spielfeld folgt) und die Score-Pill bleibt für den Rest der
Runde golden — der Results-Screen feiert danach wie gehabt (kein doppeltes
Konfetti: dieselbe Grace-Logik wie `END_MOMENT_GRACE_MS`). Erstrunden ohne
Bestwert bekommen stattdessen den Ziel-Anker („Ziel: 85" aus
`meta.target`) mit einem Puls beim Erreichen. RM-Pfad: statisches
Gold-Outline statt Schimmer, Sounds bleiben. Code-Anker:
`scripts/minigames/minigame_host.gd` (`_on_game_score`, `_score_label`),
`juice_kit.gd`, `feel_sfx.gd`, `framework_logic.gd::best_for_mode`.
Risiko: praktisch keins — eine Host-Schicht, per `test_g7_rahmen`-Muster
zentral testbar; nur die Reizfrequenz braucht eine Bremse (max. 1
Annäherungs-Puls pro Runde).

### A3 — „Brief-Duell": asynchrone Freund-Herausforderung mit Saat
**Aufwand: L · Impact: 5 · Risiko: mittel**

Nach einer Runde bietet der Results-Screen (nur bei Score > 0) einen vierten
Knopf „Herausfordern!": der eigene Lauf wird als Duell-Umschlag an einen
Freund geschickt — Spiel-Id, Difficulty, `run_seed`, Score. Der Empfänger
sieht den Umschlag im Postfach/Arcade-Banner, hat 3 Tage und BESTE aus 3
Versuchen auf EXAKT derselben Saat (der Host nimmt `seed` schon heute als
Router-Param entgegen — `receive_params`; die Spiele würfeln über
`ctx.rng`/mulberry32, gleiche Saat = gleiche Möhren-Reihenfolge = faires
Duell). Auflösung idempotent nach dem bewährten Muster: Server hält das
Ergebnis pending bis ACK (`gobnommp.js`-Result-Vertrag), Quota wie Mail
(z. B. 5 Duelle/Tag/Sender gegen Spam), Belohnung klein und über den einen
Geld-Pfad (`Economy.award` Reason `duell` gegen ein eigenes Mini-Ledger)
plus Duell-Sticker-Fortschritt auf der vorhandenen `bestFriends`-Seite.
Offline degradiert freundlich wie GvZ-PvP („Offline — Duelle warten auf
dich"). Server-Modul `arcduell.js` nach der gobnommp-Kopiervorlage (Invite/
Accept über Freunde, REST statt Live-Room — es gibt keinen Echtzeit-Anteil).
Code-Anker: `minigame_host.gd::receive_params` (`seed`), `results.gd`
(Knopfreihe), `GOOBY-SERVER/src/mail.js` + `gobnommp.js` (Muster),
`scripts/net/friends_service.gd`, `outbox.gd`. Risiko: mittel — ein neues
Server-Modul samt Tests (aber die dritte Kopie desselben geprüften Musters:
gobnommp → gvzmp → arcduell); Seed-Fairness braucht eine Wache, dass kein
Spiel `randi()` an der ctx-RNG vorbei benutzt (einmaliger Audit-Test über
die Registry).

### A4 — Arcade-Turniertag + Monatsheft (Wochen-Challenge)
**Aufwand: M · Impact: 4–5 · Risiko: niedrig**

Der deterministische Wochenplan der Ranch-Liga
(`comp_liga.gd::turniertag_plan`: Datum + Seed → alle Geräte sehen dasselbe)
wird auf die Arcade übertragen: jede Woche sind 3 Spiele „Turnier-Kabinette"
(Hash der ISO-Woche über den Registry-Pool, wie `DailyQuestEngine.roll_today`
über hash32 des Tages würfelt) mit je einer Wochen-Aufgabe, deren Ziel aus
den vorhandenen Eich-Daten kommt (z. B. 120 % des `target` der Registry —
kein neues Balancing-Orakel). Die Arcade-Kopfzeile bekommt ein
Turnier-Banner mit Restzeit (Badge-Muster von
`arcade_screen.gd::_add_modifier_badge`), erledigte Aufgaben stempeln ein
Monatsheft: 4 Wochen-Stempel = Monats-Belohnung (Sticker + Tickets aus A7).
Bewusst KEIN Season-Pass mit Verfall: das Heft archiviert sich freundlich
(Wohlfühl-Grundsatz — verpasste Wochen kosten nichts, wie die Liga keinen
Abstieg kennt). Synergie: die Turnier-Kabinette sind die natürliche Bühne
für Rivalen-Scores (A5) und Duell-Vorschläge (A3). Code-Anker:
`comp_liga.gd::turniertag_plan` (Muster), `quest_engine.gd` (Tages-Hash +
Baseline-Fortschritt über vorhandene Zähler), `arcade_screen.gd`,
additiver Save-Key `minigames.turnier` (merge_defaults-Muster wie
`minigames.difficulty`). Risiko: niedrig — offline-first, rein
deterministisch; nur die Aufgaben-Ziele je Spiel einmal durchbalancieren
(38 × ein Zahlwert, Golden-Test friert sie ein).

### A5 — Rivalen-Kabinett: Highscore-Rivalen-NPCs
**Aufwand: M · Impact: 4–5 · Risiko: niedrig–mittel**

Die Arcade bekommt ein Fahrerlager nach dem geprüften Bot-Muster der Ranch
(`comp_bots.gd`: ROSTER mit Talent-Band, Lieblings-Disziplin, Persönlichkeit,
deterministisch VOR dem Spielerlauf gewürfelt — nie Gummiband): 6–8 benannte
Arcade-Rivalen („Pixel-Paula", „Turbo-Theobald", und als Crossover-Gag Oma
Waltraud aus der Ranch-Liga, die heimlich Flipper spielt). Jeder Rivale
„mained" 4–6 Spiele und würfelt WÖCHENTLICH (Turnier-Seed aus A4) einen
Score in ein Band relativ zum Spieler-Bestwert seiner Stufe — Stufen
Bronze/Silber/Gold-Rivale steigen mit, wenn man sie schlägt (nur aufwärts).
Sichtbarkeit exakt dort, wo es zieht: das Pregame zeigt unter dem eigenen
Bestwert „Paula diese Woche: 87" (`pregame.gd::_best_label`-Zeile), der
Results-Screen feiert Überholmanöver mit einer eigenen Zeile + Pop
(`results.gd::_add_line`), und der Rekord-Puls (A2) kennt neben dem eigenen
Best auch die Rivalen-Marke. Schlägt man einen Rivalen, „antwortet" er mit
einer kurzen Notiz-Zeile im Sternenbuch (A1) — Charme statt Systemlast.
Code-Anker: `comp_bots.gd` (Muster 1:1), `pregame.gd`, `results.gd`,
additiver Save-Key `minigames.rivalen`, Strings-Domain `mg_rivalen` DE/EN.
Risiko: niedrig–mittel — die Band-Eichung pro Spiel muss fair wirken
(Gegenmittel: Band als Prozent des eigenen Best statt absoluter Scores,
Golden-Tests über 5 Seeds wie bei den Ranch-Bots).

### A6 — GOOBYCADE: die Arcade wird ein betretbarer Ort
**Aufwand: L · Impact: 5 · Risiko: mittel**

Die Arcade existiert nur als UI-Grid — dabei zeigt die Raumstation seit W13B
das komplette Muster für SPIELBARE Automaten im Raum
(`raumstation.gd`: Terminal → `goto(mg_pregame, {game_id})`, plus der
Route-Override-Trick, damit „zurück zur Arcade" wieder IN den Ort führt;
die Flüchtig-Markierung von Pregame/Host aus dem G7-Playtest-Fix greift
zentral). Neuer Stadt-Ort „GOOBYCADE": Neon-Diorama mit Automaten-Reihen
(Kabinette tragen die ECHTEN Cover-Texturen aus `arcade_screen.gd::COVERS`),
das Tages-/Turnier-Kabinett (A4) steht erhöht auf einem Podest mit
Lichterkranz, die Rivalen (A5) stehen physisch an „ihren" Automaten,
Ambient-Besucher-Goobys gucken zu und jubeln über das P55-System
(`city/ambience/ort_leben.gd` — Anschluss laut Docstring ~20 Zeilen), dazu
Jukebox (Radio-Anschluss) und die Preistheke (A7). Wichtig fürs
Ein-Spiel-Gefühl: der HUD-Arcade-Knopf bleibt der Schnellzugriff aufs Grid
(`ArcadeScreen.handle_hud_action` unverändert) — der Ort ist die BÜHNE, das
Grid die Fernbedienung. Code-Anker: `scripts/city/orte/raumstation.gd`
(Terminal-+Route-Muster), `ort_scene.gd`/`ort_leben.gd`,
`scripts/city/data/city_map.json`, `AcWallpaper.for_context("arcade")`
(Farbstimmung wiederverwenden). Risiko: mittel — größter Baustein der
Liste (neuer Ort, 6-Formate-Audit, Draw-Call-Budget mit vielen
Cover-Texturen; Gegenmittel: Kabinett-Mesh geteilt, Cover als ein Atlas).

### A7 — Ticket-Schnur & Preistheke (Belohnungs-Verzahnung)
**Aufwand: M · Impact: 4 · Risiko: niedrig–mittel**

Arcade-Automaten spucken Tickets — GOOBY bekommt das als ZWEITE, bewusst
nicht-monetäre Belohnungsschiene, die die Münz-Ökonomie nicht anfasst:
Tickets gibt es NUR für Leistungs-Momente, die `MinigameAward.award` heute
schon berechnet (`beatTarget` +2, `newBest` +3, `firstToday` +1,
Wochen-Aufgabe aus A4 +5), gedeckelt über ein eigenes Tages-Ledger
(~12/Tag) nach dem `dayCoins`-Muster — nie pro Score, nie tauschbar in
Münzen (Anti-Farm by design). Der Results-Screen lässt sie physisch aus
der Karte schnurren (Count-Up + `coin_rain`-Variante mit Ticket-Sprites),
und an der Preistheke (Sheet im GOOBYCADE bzw. im Sternenbuch) kauft man
ausschließlich Liebhaber-Dinge: Arcade-Möbel fürs Haus (Flipper-Automat!
Anschluss `furniture_catalog.gd`), Garderoben-Kappe, einen Radio-Track,
Sticker-Tütchen (bestehende Rarity-Effekte). Damit bekommen auch
Vielspieler NACH dem 150-c-Tagesdeckel einen Grund für „eine Runde noch" —
der Deckel selbst bleibt unangetastet. Code-Anker:
`minigame_award.gd::award` (+ additive Keys `minigames.tickets*`),
`results.gd`, `juice_kit.gd`, `furniture_catalog.gd`,
`scripts/cosmetics/`. Risiko: niedrig–mittel — die Preisliste braucht
einen Ökonomie-Blick (Gegenmittel: alle Preise in `content/balance/`-Daten,
Golden-Test friert das Ticket-Ledger ein wie das Coin-Ledger).

### A8 — NEUES SPIEL „Gooby-Flipper" (füllt Lücke 1)
**Aufwand: L · Impact: 5 · Risiko: mittel**

Der Flipper ist DIE fehlende Arcade-Ikone (s. Lücken-Analyse) und zugleich
das dichteste Dopamin-Genre: Bumper-Kaskaden, Multiball, Score-Feuerwerk —
alles, was der User liebt, in einem Automaten. Ein Tisch im GOOBY-Humor:
Gooby-Gesichter als Bumper (quietschen in Pitch-Reihen, AUDIO-GRAMMATIK-
konform), Möhren-Rampe, GvZ-Zombie-Drop-Targets als Crossover, Nutella-Glas
als Multiball-Schloss; Portrait-Orientierung (einhändig, Daumen = beide
Flipper über linke/rechte Schirmhälfte), Godot-2D-Physik im 3D-Look der
Bestandsbühnen. Score-reich → `coin_table` nach teaParty-Vorbild eichen,
`target` fürs ★★-System aus A1. Als 39. Manifest-Spiel
(`games/pinball/game.json`) stört es keine bestehende Datei — das
W6-Manifest-System wurde GENAU dafür gebaut, mehrere Agents parallel
liefern zu lassen. Code-Anker: `minigame_base.gd`-Contract + `game.json`,
`juice_kit.gd`, `feel/feel_sfx.gd`, Cover nach `assets/covers/`-Konvention.
Risiko: mittel — Physik-Tuning (Flipper-Impulse) ist echte Feinarbeit;
Gegenmittel: pure `pinball_logic.gd` mit deterministischem Ball-Stepping
(headless-testbar wie alle 38, Golden-Run über festen Seed).

### A9 — NEUES SPIEL „Greifautomat" (füllt Lücke 2)
**Aufwand: M · Impact: 4 · Risiko: niedrig–mittel**

Das erste Spiel, dessen Gewinn ein OBJEKT ist: 3 Griffe pro Runde, Achse 1
antippen (Kran fährt quer), Achse 2 antippen (Tiefe), dann greift die
physisch „gierige" Klaue — Plüsch-Goobys in Fellfarben-Varianten, seltene
Gold-Goobys, Ticket-Röllchen (A7) und Sticker-Tütchen liegen im Haufen.
Pity-Mechanik statt Frust: der dritte Griff bekommt einen Magnet-Boost
(sichtbar als Funkeln — ehrlich kommuniziert, kein dunkles Pattern), und
JEDER Gewinn ist echt: Plüsch-Goobys landen als Mini-Deko im Haus
(SURFACE-Props), Duplikate werden automatisch zu Tickets. Kurze Runden
(~45 s) machen ihn zum perfekten „eine noch"-Automaten im GOOBYCADE (A6),
er funktioniert aber wie jedes Spiel auch im Grid (Manifest-Eintrag,
Host-Rahmen, Energie-Kosten normal). Code-Anker: `game.json`-Manifest,
`minigame_ctx.gd` (`report_end` + Sammlungs-Funde über
`CollectionsLogic.award_report` — der W13-Pfad für organische Funde
existiert), `furniture_catalog.gd` (Plüsch-Props), A7-Ticket-Ledger.
Risiko: niedrig–mittel — Klauen-Physik gutmütig tunen (Gegenmittel:
Greif-Erfolg als pure Funktion aus Griff-Position × Beute-Layout,
deterministisch pro Seed, die Physik ist nur Show darüber).

### A10 — NEUES SPIEL „Luft-Hockey" — 2 Spieler, EIN Gerät (füllt Lücke 3)
**Aufwand: M · Impact: 4–5 · Risiko: niedrig**

Das erste lokale Duell der 38: Querformat, Tisch in der Mitte geteilt, jede
Schirmhälfte gehört einem Daumen (Multitouch — `InputEventScreenTouch` mit
Index-Zuordnung pro Hälfte, kein neues Input-System), Puck-Physik mit
den bewährten Juice-Momenten (Bande = `hit_flash`, Tor = Konfetti-Burst +
Torhupe). Solo spielt man gegen Bot-Persönlichkeiten nach `gvz_bot.gd`-/
`comp_bots.gd`-Muster (Talent-Band, keine Gummiband-KI), zu zweit wird das
iPhone zum Couch-Tisch — Belohnung läuft für den GERÄTEBESITZER normal
über den Award-Pfad, der Gast bekommt den Ruhm (und der „Beste-Freunde"-
Sticker-Zweig auf der vorhandenen `bestFriends`-Seite zählt lokale Duelle).
Erst-zu-7 hält Runden kurz; der Host-Rahmen bleibt unangetastet (Pause,
Results, Energie wie überall). Das füllt die Lokal-Multiplayer-Lücke der
GESAMTEN App mit einem einzigen Manifest-Spiel. Code-Anker:
`game.json` (orientation landscape), `minigame_base.gd`, `gvz_bot.gd`
(Bot-Muster), `content/stickers/data/stickers.json` (bestFriends).
Risiko: niedrig — Physik trivial (Kreis/Kreis), Multitouch ist die einzige
Neuheit (einmalige Wache: zwei synthetische Touch-Streams im Playtest-
Harness, das Eingaben ohnehin synthetisiert).

### A11 — Elfmeter-Duell: goalieGooby wird PvP übers Turn-Relay
**Aufwand: M · Impact: 4 · Risiko: niedrig–mittel**

Der billigste ECHTE Online-PvP-Ausbau, weil er das dritte vorhandene
Netz-Muster nutzt — nicht Lockstep (gobnom/gvz), sondern das
Battleship-Turn-Relay (`boardgames.js`: Server relayt Züge, kennt keine
Regeln, Rejoin + Rematch fertig gelöst): 5 Schuss-Runden, pro Runde
committen BEIDE verdeckt (Schütze: Ecke + Timing-Qualität aus einer
Schuss-Leiste; Keeper: Hechtrichtung), der Server deckt erst auf, wenn
beide Commits da sind (kleine Commit-Reveal-Erweiterung im
boardgames-Vertrag, `GAMES`-Set + ein Kind-Typ), dann spielen beide
Clients die Szene deterministisch ab — goalieGooby hat Torwart-Bühne und
Hecht-Animationen bereits. Async-tauglich: da Züge einzeln reisen, darf
zwischen Runden Zeit vergehen (Brettspiel-Semantik) — das Duell überlebt
einen App-Wechsel. Belohnung nach GOB-NOM-Muster (idempotentes Ergebnis,
Münzen über den einen Pfad). Code-Anker:
`games/goalie_gooby/`, `GOOBY-SERVER/src/boardgames.js` (GAMES-Set,
HISTORY_KINDS), `gobnom_netz_panel.gd` (Einladungs-UI-Kopiervorlage).
Risiko: niedrig–mittel — Commit-Reveal ist neu im Relay (Gegenmittel:
Server-Test nach `test/gvzmp.test.js`-Vorlage, Regeln bleiben im Client).

### A12 — Publikums-Ränge: ein Zuschauer-Kit für die Bühnen
**Aufwand: M · Impact: 4 · Risiko: niedrig–mittel**

GvZ hat eine Crowd (`gvz_stage3d_crowd.gd`), danceParty ein Publikum, die
Ranch-Arena Tribünen — aber 30+ Spiele feiern vor leeren Rängen. Ein
wiederverwendbares Zuschauer-Kit nach den P55-Sparprinzipien (geteilte
Materialien, berechnete Positionen, RM = statisch): 6–10 Mini-Goobys am
Bühnenrand, die auf HOST-Signale reagieren statt auf Spiel-Interna — Welle
bei Score-Sprüngen (`on_score`-Delta), Luftsprung + Konfetti beim
Rekord-Moment (A2 liefert das Event), kollektives „Ohhh" beim
Strike-Teleport. Opt-in pro Spiel über ein Manifest-Flag (`"crowd": true`),
Rollout zuerst auf die 8 bühnigsten Spiele (miniGolf, trampoline,
basketBounce, goalieGooby, pancakeTower, veggieChop, bubblePop, danceParty-
Upgrade). Im GOOBYCADE (A6) stehen dieselben Zuschauer HINTER dem Spieler
am Automaten — ein Kit, zwei Bühnen. Code-Anker: `gvz_stage3d_crowd.gd`
(Extraktions-Kandidat), `game.json`-Flag über `minigame_registry.gd`,
`minigame_host.gd` (Signale `round_finished`/`end_moment_fired` existieren).
Risiko: niedrig–mittel — Perf-Budget der kleinen Bühnen (Gegenmittel:
MultiMesh + ein geteiltes Wackel-Material, Zuschauer sind reine Deko ohne
Physik).

### A13 — Tages-Kabinett: „Heute spielen alle DAS" + Freunde-Tagesliste
**Aufwand: M–L · Impact: 4 · Risiko: mittel**

Jeden Tag ist EIN Spiel das Tages-Kabinett (deterministisch aus
hash32(Datum) über den Registry-Pool — exakt der `roll_today`-Mechanismus
der Tagesquests, alle Spieler sehen dasselbe Spiel) mit einem Tages-Lauf
auf FESTER Tages-Saat: gleiche Saat für alle = ehrlich vergleichbare
Scores. Die Freunde-Bestenliste dazu übernimmt das fertige
Ranch-MP-REST-Muster (`/api/rmp/leaderboard/:kurs` → `/api/arcade/daily`,
Server sortiert, eigene Zeile hervorgehoben —
`rmp_leaderboard_panel.gd` ist die UI-Kopiervorlage inkl.
Offline-Hinweis); offline füllen die Rivalen (A5) die Liste. Der Reiz:
38 Spiele × 365 Tage Rotation zwingt sanft aus der Komfortzone (die
`plays`-Daten zeigen erfahrungsgemäß 3–4 Lieblingsspiele) und gibt dem
Tages-×2-Bonus, den es SCHON gibt (`firstToday`), endlich eine Bühne.
Code-Anker: `quest_engine.gd` (Hash-Muster), `minigame_host.gd` (`seed`),
`rmp_leaderboard_panel.gd` + `GOOBY-SERVER/src/ranchmp.js` (Muster),
`arcade_screen.gd` (Kabinett-Hervorhebung). Risiko: mittel — ein neuer
Server-Endpoint (klein, aber mit Quota/Validierung); Saat-Fairness teilt
sich die Wache mit A3.

### A14 — Gooby-Cup: das 3-Spiele-Turnier mit Siegerehrung
**Aufwand: M–L · Impact: 4 · Risiko: mittel**

Das Format über den Einzelrunden: ein Cup = 3 Spiele in Folge (aus dem
Wochen-Seed von A4 gezogen), gegen 3 Rivalen (A5), deren Ergebnisse VOR dem
Spielerlauf deterministisch simuliert werden — exakt die
`comp_turnier.gd`-Orchestrierung (`bots_simulieren` → Spielerlauf →
Zielreihenfolge → Siegerehrung), nur dass die „Disziplinen" Arcade-Spiele
sind und die Wertung der normalisierte Score (Prozent des `target`, damit
teaParty-85 und gvz-300 vergleichbar sind). Der Cup-Controller hängt sich
an das VORHANDENE `round_finished(breakdown)`-Signal des Hosts und reist
zwischen den Läufen mit dem normalen Wipe — kein neuer Spiel-Rahmen,
nur ein Klammer-Zustand. Podium mit Konfetti-Grammatik + Pokal-Sticker,
Cup-Historie im Sternenbuch (A1). Energie-Regel bleibt ehrlich: 3 Runden
kosten 3× Energie (der Cup ist ein Commitment, kein Farm-Trick).
Code-Anker: `comp_turnier.gd` (Muster), `minigame_host.gd::round_finished`,
`comp_bots.gd`, `results.gd` (Cup-Zwischenstand-Zeile). Risiko: mittel —
der Kette-über-3-Runden-Zustand muss App-Kill-sicher sein (Gegenmittel:
Cup-Zustand als additiver Save-Key, Wiedereinstieg beim nächsten
Arcade-Besuch: „Dein Cup wartet — Spiel 2 von 3!").

### A15 — Sammel-Funde-Ausbau: mehr Spiele füttern die Sammlungen
**Aufwand: S–M · Impact: 3–4 · Risiko: niedrig**

Der organische Fund-Pfad existiert seit W13 (`report_end` →
`CollectionsLogic.award_report`; fishingPond befüllt die Fisch-Sammlung,
Reisen die Sehenswürdigkeiten) — aber nur eine Handvoll Spiele nutzt ihn.
Ausbau als reine Daten-/Callsite-Arbeit: gardenRush lässt selten ein
Gold-Gemüse fürs Gemüse-Set fallen, ghostHunt ein Geister-Andenken,
harborHopper eine Muschel (Urlaubs-Set), cityDrive „entdeckt"
Sehenswürdigkeiten beim Vorbeifahren, burgerBuild schaltet
Leckereien-Einträge frei. Wichtig: Funde sind SELTEN (seeded über
`ctx.rng`, deterministische Testbarkeit), immer Bonus, nie Bedingung — und
der Results-Screen zeigt den Fund mit dem vorhandenen
Sticker-Rarity-Moment. Das verzahnt Arcade-Spielen mit dem Album (das der
User seit W13 komplett halten will: „ALLE 4 Sammlungen komplettierbar")
ohne neue Systeme. Code-Anker: `minigame_host.gd::_award`
(CollectionsLogic-Aufruf existiert), je Spiel der `report_end`-Payload,
`content/`-Sammlungsdaten. Risiko: niedrig — Drop-Raten einmal festlegen
(Golden-Seeds), sonst reine Fleißarbeit.

---

## Übersicht

| # | Idee | Kategorie | Aufwand | Impact | Risiko |
|---|---|---|---|---|---|
| A1 | Arcade-Sternenbuch | Meta-Progression | M | 5 | niedrig |
| A2 | Rekord-Puls im Host | Jubel/Dopamin | S–M | 5 | sehr niedrig |
| A3 | Brief-Duell (async, Saat) | Multiplayer | L | 5 | mittel |
| A4 | Arcade-Turniertag + Monatsheft | Event-Format | M | 4–5 | niedrig |
| A5 | Rivalen-Kabinett (NPC-Highscores) | Meta-Progression | M | 4–5 | niedrig–mittel |
| A6 | GOOBYCADE-Ort | Arcade-Atmosphäre | L | 5 | mittel |
| A7 | Ticket-Schnur & Preistheke | Belohnungs-Verzahnung | M | 4 | niedrig–mittel |
| A8 | NEU: Gooby-Flipper | Neues Spiel (Lücke 1) | L | 5 | mittel |
| A9 | NEU: Greifautomat | Neues Spiel (Lücke 2) | M | 4 | niedrig–mittel |
| A10 | NEU: Luft-Hockey (lokal 2P) | Neues Spiel (Lücke 3) | M | 4–5 | niedrig |
| A11 | Elfmeter-Duell (Turn-Relay-PvP) | Multiplayer | M | 4 | niedrig–mittel |
| A12 | Publikums-Ränge (Zuschauer-Kit) | Jubel/Zuschauer | M | 4 | niedrig–mittel |
| A13 | Tages-Kabinett + Freunde-Tagesliste | Event/Multiplayer | M–L | 4 | mittel |
| A14 | Gooby-Cup (3-Spiele-Turnier) | Turnier-Format | M–L | 4 | mittel |
| A15 | Sammel-Funde-Ausbau | Belohnungs-Verzahnung | S–M | 3–4 | niedrig |

## Abhängigkeits- und Paket-Hinweise für den Konsolidierer (Welle J+)

- **Fundament zuerst:** A1 + A2 sind unabhängig, billig und heben sofort
  ALLE 38 Spiele — ideal als gemeinsames Paket „Arcade-Seele" mit einem
  Testlauf über den Host-Rahmen (`test_g7_rahmen`-Erweiterung).
- **Wochen-Rhythmus-Paket:** A4 → A5 → A14 bauen aufeinander auf (Wochen-
  Seed → Rivalen → Cup); A4 allein ist schon komplett erlebbar.
- **Ort-Paket:** A6 gewinnt massiv durch A7 (Preistheke), A9 (Greifautomat
  als Hallen-Attraktion) und A12 (Zuschauer an den Automaten) — aber A7/A9
  funktionieren auch ohne den Ort (Sheet bzw. Grid-Eintrag), der Ort ist
  KEINE Vorbedingung.
- **Netz-Reihenfolge:** A3 und A13 teilen sich die Saat-Fairness-Wache
  (Audit: kein Spiel würfelt an `ctx.rng` vorbei) — die zuerst bauen.
  A11 ist davon unabhängig (Turn-Relay statt Saat-Vergleich).
- **Neue Spiele parallelisieren:** A8/A9/A10 sind dank `game.json`-
  Manifesten (W6) konfliktfrei parallel baubar — je Agent ein Ordner,
  Cover nach `assets/covers/`-Konvention, Registry-Wache zieht sie
  automatisch in den Rahmen.
- **Ökonomie-Wache überall:** A7-Tickets und alle Duell-/Turnier-Belohnungen
  laufen gegen eigene Tages-Ledger nach dem `dayCoins`-/`modifier`-Muster —
  der 150-c-Deckel und die 8er-Energie bleiben in JEDER Idee unangetastet
  (Golden-Tests einfrieren).
