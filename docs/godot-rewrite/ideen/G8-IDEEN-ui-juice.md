# G8-IDEEN — UI/UX + JUICE (Ideen-Planner IP-4, Welle I)

**Bereich:** UI/UX + JUICE (Animationen, Übergänge, Haptik, Mikro-Feedback,
Dopamin) + iPhone-Leitformat 2868×1320 quer.
**Quellen:** `UserFeedback.md` (komplett), G7-Commits (`952e0d68` P50
HUD-Dynamik, `2378c86d` P53 Sheet-System, `d94ed031` P56 Ein-Spiel-Gefühl,
`12d94ee0` P57 Leitformat), Playtest-Reports `docs/playtest/G8-PT2` + `G8-PT4`,
Code-Streifzug durch `GOOBY-GODOT/themes/*` (`tokens.gd`, `theme_service.gd`),
`scripts/ui/*` (`hud.gd`, `hud_sichtbarkeit.gd`, `hud_label_fit.gd`,
`panel_sheet.gd`, `squish_button.gd`, `widgets/ui_motion.gd`,
`components/haptics.gd`, `toast_queue.gd`), `scripts/core/loading_veil*.gd`,
`scripts/fx/*` (`moment_regie.gd`, `post_fx.gd`), `scripts/minigames/juice_kit.gd`,
`docs/godot-rewrite/AUDIO-GRAMMATIK.md`. Nur gelesen, nichts geändert.
Keine Doppelung mit den Lieferungen von IP-1 (Home/Seele) und IP-2
(Stadt/Läden/DLC) — dieser Katalog bleibt auf der UI-SCHICHT selbst.

**Woran sich jede Idee messen muss (das Auge des Users):** Er hat die
Squish-Kurven der alten Web-Version wörtlich eingefordert (Press 0.94 +
Feder-Overshoot — heute geeicht in `AcTokens.PRESS_SCALE`/`SQUISH_OVERSHOOT`),
er liebt Zähl-Animationen, Konfetti-Grammatik, Reisepass-Stempel-Momente, und
sein G7-Wunsch war „dynamisches UI mit Animationen" (P50: HUD gleitet weg —
umgesetzt und im Playtest verifiziert). Der NÄCHSTE Level heißt: nicht mehr
nur „Elemente weichen", sondern **Elemente reisen, antworten und belohnen** —
und das Leitformat 2868×1320 quer hat noch zwei strukturelle Baustellen
(HUD-Labels: PT4-B4; Overlay-Stapel: PT4-B7), auf denen Ideen unten aufbauen.

Aufwand **S/M/L** (Umfang/Invasivität, nie Kalenderzeit), Impact **1–5**,
Risiko ehrlich mit Gegenmittel.

---

## TOP-3 (Begründung)

**🥇 J1 „Beute-Flug-Dreiklang" — Münzen fliegen wirklich (Visual + Arpeggio +
Haptik-Ticken).** Der größte Dopamin-Hebel pro Zeile Code: Belohnungen werden
heute GEBUCHT (Toast + `count_to`), aber sie REISEN nicht. Ein universeller
Reward-Flug-Layer von der Quelle in die HUD-Münz-Pille — synchron mit
Pitch-Treppen-Ticks und Mikro-Haptik — zahlt auf JEDEN Screen gleichzeitig ein
(Quest-Claim, Kassensturz, mg_results, Tagesbonus, Käufe). Genau die Sorte
Alt-Web-Liebe, die der User seit W13 einfordert, und alle Bausteine
(`UiMotion.count_to`, `JuiceKit.coin_rain`, Audio-Pitch-Grammatik 0.9–1.6,
`Haptics.plan`) existieren — es fehlt nur die Verbindung.

**🥈 J2 „Icon-Bühne + Namensschilder" — der STRUKTURELLE Fix für die
Querformat-HUD-Labels (PT4-B4).** Der Playtest beweist: im Leitformat bleiben
nach StyleBox-Innenrändern ~18 px Textbreite — da scheitert selbst der
P50-Autoshrink (`HudLabelFit.MIN_PX = 8`), „Garderobe" braucht ~45 px. Kein
Tuning heilt das: **Label IN einer quadratischen Mini-Kachel skaliert nicht.**
Die Wurzellösung trennt Icon (immer) von Beschriftung (auf Abruf als
Frost-Chip) — und macht aus der Not einen Juice-Moment (Namensschild-Parade).
Pflichtthema laut Auftrag, mittlerer Aufwand, löst das P50-Versprechen „nie
mehr abgeschnitten" endgültig ein.

**🥉 J3 „Hero-Morph-Übergänge" — Elemente reisen zwischen Screens.** Das
„magisch"-Gefühl schlechthin (iOS-App-Öffnen, ACNH-Menüs): das Arcade-Cover
fliegt aus dem Grid und WIRD das Pregame-Cover, die Quest-Kachel morpht zum
Blatt-Titel. G7-P56 hat Übergänge VEREINHEITLICHT (Wipe überall) — der
nächste Level ist KONTINUITÄT: das Auge behält ein Objekt, der Kontext wechselt
darunter. Ein kleiner Ghost-Layer genügt, beginnend mit zwei In-Screen-Fällen
ganz ohne Router-Risiko.

---

## Die priorisierte Liste (J1–J14)

### J1 — Beute-Flug-Dreiklang: Münzen/XP fliegen, klingen und ticken

Ein universeller Reward-Flug-Layer (neu `scripts/fx/beute_flug.gd`,
CanvasLayer über allem): Münz-/XP-/Item-Sprites starten an der globalen Rect
der Quelle (Kauf-Knopf, Quest-„Abholen", Kassensturz-Karte, Tagesbonus-Popup),
fliegen in gestaffelten Bogen-Bahnen (Quad-Bezier mit leichtem Überschwung,
5–9 Stück je nach Betrag) zur HUD-Münz-Pille, die pro Ankunft `UiMotion.bounce`
macht — und ERST mit den Ankünften zählt `count_to` hoch. `count_to`
(`scripts/ui/widgets/ui_motion.gd`) bekommt zentral die Sound-Haptik-Kopplung:
pro Zähl-Schritt ein leises `ui_tick` mit steigender Tonhöhe (Pitch-Reihe
0.9→1.6, AUDIO-GRAMMATIK-konform „semantische Steigerungsreihe"; der
45-ms-Debounce des AudioDirector drosselt von selbst) plus ein 3-ms-Mikro-Puls
(J6-Partitur `zaehl_tick`), Abschluss = `ui_coins` + `Haptics.success()`.
Andock-Punkte: `hud.gd` bekommt eine kleine Ziel-API (`coin_ziel_rect()`,
`level_ziel_rect()`), Aufrufer sind `quest_service.gd`,
`minigames/results.gd`/`minigame_award.gd`, `daily_bonus_popup.gd` und die
Kauf-/Kassensturz-Flows. Reduced Motion: kein Flug, aber Arpeggio + Zählen
bleiben (Sound/Haptik sind keine Motion — Bestandsregel aus
`squish_button.gd`).
**Aufwand:** M · **Impact:** 5 · **Risiko:** niedrig — additiver Layer,
keine Logik-Änderung; einziger Wachpunkt ist Tick-Spam bei großen Beträgen
(Gegenmittel: Ticks an Flug-Ankünfte statt an jeden Zähl-Frame koppeln,
max. ~10 Ticks pro Feier).

### J2 — Icon-Bühne + Namensschilder: der Struktur-Fix fürs Querformat-HUD (PT4-B4)

Die Cockpit-Kacheln (`hud.gd::_fit_landscape_column` dampft sie im Leitformat
auf Touch-Floor-Größe ein) werden im Querformat ICON-ONLY — die Label-Zeile in
der Kachel entfällt ersatzlos, das Icon wächst auf die freie Fläche (bessere
Erkennbarkeit statt „Garde…"-Krümel). Die Beschriftung wandert in ein
**Namensschild**: ein Frost-Pill-Chip (`AcTokens.FROST`, Muster
StatusCapsuleMini), der LINKS neben der Kachel aufpoppt — (a) als
„Namensschild-Parade" beim ersten Querformat-Layout einer Session gleiten alle
Schilder gestaffelt heraus, stehen ~1,5 s und gleiten zurück (lernbar, purer
Juice-Moment, `UiMotion.stagger_in`-Muster), (b) bei Long-Press auf einer
Kachel (Synergie J5), (c) dauerhaft solange der Coachmark/Guide auf die Spalte
zeigt (`hud.gd::_position_coachmark` kennt die Geometrie schon). Als
deterministisches Sicherheitsnetz für Formate, in denen selbst Icon-only eng
wird, bekommt `HudLabelFit` einen Kurzform-Pfad: gepflegte `hud.<id>.kurz`-Keys
in den Strings (DE/EN) statt blindem Ellipsis — nie mehr abgeschnittene Wörter,
sondern bewusste Kurzformen („Quests" → „Quest" ist KEINE, „Garderobe" →
„Mode" ist eine). Hochkant-Dock bleibt unverändert (Labels passen dort, Beleg
PT4-Verifikation #1).
**Aufwand:** M · **Impact:** 5 · **Risiko:** niedrig–mittel —
Erst-Nutzer-Verständlichkeit von Icon-only (Gegenmittel: Parade + Long-Press +
Coachmark-Integration); `test_g7_hud_dynamik` und die FB3-UiScale-Wache müssen
mitgezogen werden (Assert: im Leitformat existiert KEIN Ellipsis-Fallback mehr).

### J3 — Hero-Morph-Übergänge: Elemente reisen zwischen Screens

Ein kleiner Ghost-Layer (neu `scripts/fx/morph_layer.gd`, CanvasLayer):
Snapshot/Duplikat des Quell-Controls tweent von dessen globaler Rect zur
Ziel-Rect (TRANS_BACK/EASE_OUT, `DUR_SHEET`), das echte Ziel blendet erst bei
Ankunft ein. Startfälle OHNE Router-Beteiligung: (1) Arcade-Grid → Pregame —
das Cover der getippten Karte fliegt in die Pregame-Cover-Zone
(`arcade_screen.gd` und `pregame.gd::_cover` kennen beide Rects; der Rest des
Pregame-Blatts federt wie gehabt auf); (2) HUD-Kachel → Blatt —
`panel_sheet.gd::open()` bekommt einen optionalen `quelle: Control`-Parameter:
das Blatt wächst sichtbar AUS der Quest-/Garderobe-Kachel heraus (Scale+Move
statt nur Slide-up), der Titel übernimmt das Kachel-Icon als Mini-Stempel.
Später (Stufe 2): Shop-Karte → Detail-Header im IKEA-Katalog. Reduced Motion:
kein Ghost, heutiger Schnitt bleibt (RM-Vertrag von P53 unangetastet).
**Aufwand:** M · **Impact:** 5 · **Risiko:** mittel — Timing mit
parallelem Layout (Gegenmittel: Ghost lebt max. `DUR_SHEET`, bei
`size_changed` während des Flugs sofort ans Ziel springen); Router-Übergänge
mit Veil bewusst NICHT in Stufe 1.

### J4 — Overlay-Dirigent: Momente treten NACHEINANDER auf (PT4-B7)

Der Playtest-Beleg zeigt drei Lagen gleichzeitig nach dem Onboarding
(Tagesbonus ÜBER Guide-Tour ÜBER Erklärkarte) plus Erfolgs-Toasts MITTEN im
Editor. Die strukturelle Antwort: eine zentrale Auftritts-Bühne
(neu `scripts/ui/moment_buehne.gd`, pure Queue-Logik nach
`toast_queue.gd`-Muster: FIFO + Dedupe + Prioritäten + „Bühne frei?"-Gate).
Tagesbonus, Guide-Tour, Coachmarks, Erfolgs-Toasts und Level-Up-Feiern melden
ihre Auftritte an statt sich selbst zu mounten; es spielt immer genau EINER,
mit Auftritt-Grammatik (Vorgänger geht per `UiMotion.fade_out` sauber ab,
Nachfolger `slide_up_in` — 150 ms Atempause dazwischen). Erfolgs-Toasts, die
während Onboarding/Cutscene/Minispiel anfallen, werden GEPUFFERT und kommen im
freien Spiel („Übrigens: Sticker verdient!" — fühlt sich wie ein Nachschlag
an statt wie Störfeuer). Anker: `daily_bonus_popup.gd`,
`onboarding_flow.gd` (Guide-Tour), `achievements_service.gd` (Toast-Trigger),
`hud.gd`-Coachmark; Beleg `flow_pt4_onboarding_094135_32254/013+015`.
**Aufwand:** M · **Impact:** 5 (der ERSTE Spielmoment eines neuen Spielers) ·
**Risiko:** mittel — mehrere Call-Sites mit Eigenleben (Gegenmittel:
schrittweise einführen — erst das Onboarding-Fenster, dann global; die
PT4-Onboarding-Flow-Sonden existieren schon als Regressions-Wache).

### J5 — Gesten-Arbiter + Kanten-Wisch-Zurück + Long-Press-Peek (PT4-B3-Wurzel)

PT4-B3 beweist das strukturelle Loch: Interactables/Türen feuern beim PRESS
(`interactables_host.gd::make_tap_area`, `door_transition.gd` Z. 340–351) —
ein Kamera-Pan, der auf einer Tür startet, öffnet den Raum-Dialog. Statt drei
Einzel-Fixes EIN zentraler Gesten-Arbiter (neu
`scripts/core/gesten_arbiter.gd`, pure Zustandsmaschine: Press → Slop-Fenster
→ Tap/Pan/Long-Press/Edge-Swipe-Entscheidung; dieselbe Schwellen-Semantik wie
`PanelSheet.SWIPE_CLAIM` — Wiedererkennung statt Neuerfindung). Darauf bauen
zwei Gesten-Shortcuts: **Kanten-Wisch von links = zurück** — der Screen zieht
dabei sichtbar mit dem Finger mit (Fortschritts-Vorschau nach dem
Blatt-Zug-Muster), Loslassen über der Schwelle ruft `SceneRouter.back()`
(Flüchtige-Ziele-Logik aus dem G7-Blocker-Fix greift automatisch); und
**Long-Press auf HUD-Kacheln = Quick-Peek**: das J2-Namensschild erscheint
plus 1–3 Schnell-Aktionen (Garderobe → letzte 3 Outfits, Füttern →
Lieblingsessen; erweiterbar, Start nur mit dem Namensschild ist schon wertvoll).
**Aufwand:** M–L · **Impact:** 4–5 · **Risiko:** mittel — Gesten-Konflikte
mit Kamera-Pan/Sheet-Zug sind GENAU die Existenzberechtigung des Arbiters;
Gegenmittel: pure Logik headless testen + die PT4-Media-Flow-Sonde (B3) als
End-zu-End-Beweis.

### J6 — Haptik-Partituren: von drei Impulsen zur Choreografie

`Haptics.plan()` (`scripts/ui/components/haptics.gd`, heute tap/success/warn)
wird zur Partitur: Rückgabe wird eine Schritt-Liste `[{pause_ms, dauer_ms}]`,
neue benannte Muster: `tada` (kurz-kurz-LANG — Rekord/Level-Up),
`zaehl_tick` (3 ms, gekoppelt an J1-Flug-Ankünfte), `einrast` (8 ms exakt
beim Überschreiten der Sheet-Schließ-Schwelle in `panel_sheet.gd` —
der Finger SPÜRT den Snap-Punkt, wie ein physischer Schalter),
`konfetti_prasseln` (5 zufällig gestreute Mikro-Pulse unter der
Konfetti-Grammatik), `wende_perfekt` (McGooby-Patty, doppelt kurz). Die
Stärke-Stufen (`LEVEL_FACTORS` dezent/normal/stark) skalieren weiter zentral,
`plan()` bleibt pur und headless-testbar (Tests prüfen Partituren, nicht
Vibration). Ehrlichkeit wie im Datei-Kopf dokumentiert: `vibrate_handheld`
wirkt auf iOS erst im signierten Build, Desktop = No-op — die Partitur-API ist
zugleich der saubere Andockpunkt, falls später CoreHaptics nativ kommt.
**Aufwand:** S–M · **Impact:** 4 · **Risiko:** niedrig — reine Erweiterung
eines puren Bausteins; Wachpunkt Doppel-Haptik (Regel bleibt: Partituren NUR
an Momenten, nie zusätzlich zum automatischen SquishButton-Tap).

### J7 — Sheet-Physik: Feder-Solver, Overdrag-Gummi + Gooby-Peek

Der P53-Zug ist 1:1-linear und das Snapback ein Tween — gut, aber die letzten
10 % Magie fehlen: (a) Loslassen übergibt die ECHTE Fingergeschwindigkeit
(`panel_sheet.gd::_zug_tempo` wird heute nur für die Schwellen-Entscheidung
genutzt) an eine kritisch gedämpfte Feder (neu pure `feder_logic.gd`:
Position+Velocity-Integrator, headless testbar) — kein Geschwindigkeits-Sprung
mehr zwischen Hand und Animation; (b) Ziehen ÜBER die Ruhelage nach oben =
Gummi-Widerstand (sqrt-Dämpfung wie iOS-Overscroll) statt hartem Stopp;
(c) der Charme-Gag: ab ~24 px Overdrag lugen Goobys Ohren hinter der
Blattkante hervor (Mini-Sprite hinterm Sheet-Chrome, 1× pro Sitzung, mit
Gebrabbel-Piep) — Neugier wird belohnt, kein Feature verpasst wer es nie
sieht. Reduced Motion: direkter Zug bleibt (P53-Vertrag: direkte Manipulation
ist keine Animation), Feder/Gag entfallen.
**Aufwand:** M · **Impact:** 4 · **Risiko:** niedrig — rein präsentational
über dem getesteten P53-Verhalten; `test_g7_sheets` erweitert die
Snapback-Fälle um Feder-Endlagen.

### J8 — Kontext-HUD: der situative Slot + Stat-Flüstern (PT2-B9/PT4-B6-Wurzel)

Das HUD kann seit P50 WEICHEN — jetzt lernt es ANBIETEN. Ein situativer
Kachel-Slot (feste Position in `HudButtonOrder`, damit nichts springt) zeigt
kontextabhängig die JETZT sinnvollste Aktion: „Abholen!" wenn eine
Quest-Belohnung wartet (ersetzt die „Was nun?"-Hinweiskarte, die laut PT2-B9/
PT4-B6 über Telefon und Bau-UI hängt, AN DER WURZEL: der Hinweis wird
HUD-Bürger und gleitet mit der P50-Dynamik statt als Fremd-Overlay zu
schweben), abends „Schlafen", bei wartendem Tagesbonus der Geschenk-Chip.
Wechsel-Disziplin gegen Unruhe: max. ein Tausch pro 10 s, nie während einer
Eingabe, immer mit Mini-Pop (`UiMotion.pop_in`). Dazu **Stat-Flüstern**: fällt
ein Stat unter 25 %, pulst seine Pille sanft (Scale 1.04 im 2-s-Atem, RM:
statischer Farbkern) und feuert EINMAL eine Mikro-Haptik — kein Alarm-Rot,
Gooby-Ton statt Tamagotchi-Panik. Anker: `hud.gd` (Kachel-Slots,
`refresh_hint`-Gate existiert), `hud_sichtbarkeit.gd` (Slot gleitet mit),
`quest_service.gd`-Signale, `daily_bonus.gd`.
**Aufwand:** M · **Impact:** 4 · **Risiko:** mittel — Vorhersagbarkeit
(Kinder-UX: Knöpfe sollen bleiben wo sie sind; Gegenmittel: EIN fester Slot,
nie die Bestands-Kacheln umsortieren, Coachmark beim ersten Auftritt).

### J9 — Quer-Bühne: Side-Sheets — Gooby bleibt im Bild

Im Leitformat 2868×1320 deckt das zentrierte Bottom-Sheet die Bildmitte —
und damit Gooby, den emotionalen Anker des Spiels. Neu: `PanelSheetLayout`
(die Geometrie ist bereits pure!) bekommt eine QUER-Variante **SEITE**: das
Blatt dockt rechts an (Breite ~38–42 % Canvas, volle Safe-Area-Höhe, Slide-in
von rechts, Wisch-nach-RECHTS schließt — Griff wandert an die linke
Blattkante), die Home-Kamera schiebt ihren Fokus sanft nach links
(Fokus-Offset-API am Kamera-Rig), sodass Gooby sichtbar bleibt und aufs Blatt
REAGIEREN kann (neugieriger Blick — Anschluss an das vorhandene
Blickführungs-System, ohne neue Seele-Logik). Hochkant bleibt alles beim
Bottom-Sheet; Call-Sites bleiben unverändert (`open()` entscheidet nach
Orientierung). Das löst nebenbei die Familie „Kaufknopf unterm Falz quer"
(PT2-B6-Muster) strukturell mit: seitliche Blätter haben volle Höhe und einen
natürlichen Sticky-Footer.
**Aufwand:** M–L · **Impact:** 4–5 (DER Leitformat-Wurf) · **Risiko:**
mittel — horizontale Wisch-Zweige in `panel_sheet.gd` + die 34-Screens-Wache
über 6 Formate müssen mitziehen (Gegenmittel: Variante hinter einer
Layout-Weiche, Screen-für-Screen aktivieren, Quest-Blatt als Pilot).

### J10 — Reduced Motion mit Liebe: Ersatz-Grammatik statt Hard-Cut

Heute heißt RM oft „nichts": `UiMotion.sparkle()` returnt leer, `pop_in`
springt, Konfetti entfällt — funktional korrekt, emotional eine Bestrafung.
Neu: eine definierte **Ersatz-Grammatik** in `ui_motion.gd` (EIN Ort, alle
profitieren): Bewegung → Crossfade (Opacity-Fades sind vestibulär
unkritisch), `sparkle` → kurzes stilles Aufleuchten (Gold-Modulate-Blitz,
200 ms, ortsfest), Squish → sanfter Highlight-Puls der StyleBox statt Scale,
Konfetti → gerahmtes Feier-Standbild das ausblendet; Haptik + Sound bleiben
volle Feedback-Träger (Bestandsregel „Haptik ist KEINE Motion"). Dazu wird der
globale Bool eine Zweier-Stufe: „Weniger Bewegung" (Fades an, Bewegung aus —
Default wenn das OS RM meldet) und „Keine Animationen" (heutiges Verhalten);
`ThemeService.is_reduced_motion` bleibt als Bool-API erhalten
(abwärtskompatibel, Stufe 2 = true). Anker: `ui_motion.gd` (alle
`reduced()`-Zweige), `squish_button.gd`, `theme_service.gd`,
`juice_kit.gd`-RM-Zweige.
**Aufwand:** S–M · **Impact:** 4 (für Betroffene 5 — und es ist die Sorte
Liebe, die dieses Projekt auszeichnet) · **Risiko:** niedrig–mittel — viele
kleine Stellen, jede trivial; bestehende RM-Tests asserten „sofort" und müssen
auf die Stufen-Semantik gezogen werden.

### J11 — Gooby färbt das UI: Akzent-Personalisierung mit Leitplanken

Goobys Fellfarbe (cosmetics, inkl. Galaxie-Shader-Fell!) färbt DEKORATIVE
UI-Slots: Level-Ring-Füllung (`hud_progress_ring.gd`), aktiver
Kategorie-Chip-Rand, Konfetti-Beimischung (1 von 4 Farben), Veil-Blüten-Tint
(`loading_veil_wipe.gd`), Sheet-Griff-Pill. Struktur statt Wildwuchs — die
Token-Doktrin („AcTokens ist die EINZIGE Farbquelle") bleibt wahr, indem die
Ableitung selbst ein Token-Helfer wird: `AcTokens.akzent_von(fell: Color)`
klemmt Sättigung/Helligkeit in den AC-Pastellkorridor und prüft den
Kontrast-Floor gegen PAPER (Muster `lip_color()`-Nachbar), `ThemeService`
cached das Ergebnis und nur eine dokumentierte SLOT-WHITELIST darf es nutzen —
Text, Flächen, Stat-Farben bleiben unberührt (farbfehlsichtig-sicher, weil
rein dekorativ). Der Moment, in dem man Gooby umfärbt und das UI „mitzieht",
ist ein Personalisierungs-Dopamin, das kein anderes Feature liefert: MEIN
Gooby = MEIN Spiel.
**Aufwand:** M · **Impact:** 4 · **Risiko:** mittel — Geschmack/Kontrast
(Gegenmittel: Korridor-Klemmung + Whitelist + ein Screenshot-Sweep über die
Fellfarben-Palette in der FB3-Wache); Galaxie-Fell braucht eine definierte
Fallback-Farbe.

### J12 — Lade-Momente 2.0: tippbarer Sticker + wissende Tipps (inkl. PT2-B5)

Der Veil ist schon liebevoll (Petal-Wipe, Karten-Modi, Tipps) — jetzt wird er
interaktiv und schlau: (a) der hüpfende Motiv-Sticker
(`loading_veil_sticker.gd`) wird tippbar — jeder Tap ein Squish + `ui_tick`
in Pitch-Treppe, beim 5. Tap ein Mini-Konfetti (Crash-Bandicoot-Prinzip:
Ladezeit wird Spielzeug; Input geht sonst ohnehin ins Leere); (b) die
rotierenden Tipps werden WISSEND: ein purer `tipp_kurator.gd` filtert den
Pool gegen den Save — „Du hast noch nie geangelt — der See wartet!" nur
solange die Fisch-Sammlung leer ist, erledigte Tipps fliegen raus, Features
der letzten Pack-Version herein (Tipps werden sanfte Quest-Köder statt
Static); (c) die fehlende `dlc_hub`-Veil-Karte (PT2-B5: Hub-Reise zeigt
„Trautes Heim") bekommt ihren eigenen Eintrag in
`loading_veil.gd::_apply_variant` gleich mit. Reduced Motion: Sticker tippbar
ohne Squish (nur Ton), Tipps unverändert.
**Aufwand:** S–M · **Impact:** 3–4 · **Risiko:** sehr niedrig — der Veil ist
von den Szenen entkoppelt; Tap-Handling darf den `covered/revealed`-Vertrag
nicht berühren (reiner Overlay-Input).

### J13 — Audio-Bühne: Musik duckt, wenn das UI spricht

Blätter/Modals bekommen akustische Tiefenstaffelung: `PanelSheet.open()` senkt
die Musik um ~2,5 dB (150-ms-Ramp), `close()` hebt sie zurück — EIN
Anschlusspunkt für ALLE Blätter (AUDIO-GRAMMATIK-Regel „Öffnen/Schließen
klingt nur über PanelSheet" bekommt ihr Ducking-Pendant); das Blatt fühlt sich
„nah" an, der Raum dahinter „weiter weg". Dazu koppelt der Runterwisch die
Dim-Aufhellung an die Rückkehr des Pegels (Zug-Anteil → Ramp-Fortschritt —
man HÖRT das Blatt gehen, bevor es weg ist). Neu in
`music_director.gd`: eine kleine `duck(db, ramp_s)`-Referenzzähler-API (zwei
Blätter übereinander ducken nicht doppelt — Zähler-Muster aus
`hud_sichtbarkeit.gd` übernehmen). Der Pegel-Wächter (Musik 6–10 dB unter
Sfx) misst den GEDUCKTEN Zustand mit.
**Aufwand:** S · **Impact:** 3–4 · **Risiko:** niedrig — additiv; Wachpunkt
ist nur der bestehende Pegel-Abstands-Test (Duck-Zustand explizit
mit-testen).

### J14 — Telefon-Case + Klingelton: das IGohbie wird MEINS

Das Telefon (G7-P52 poliert) bekommt eine Personalisierungs-Ebene:
Garderobe-Kategorie „Telefon" mit Cases (Pastell-Farben, Muster — und
Sticker-SLOTS: erspielte Album-Sticker aufs Case kleben, endlich ein NUTZEN
für die Sammlung über das Album hinaus), dazu 3 Benachrichtigungs-Jingles
(bestehende SfxMap-Ids in Pitch-Varianten, keine neuen Dateien) und wählbare
Öffnungs-Animation (Pop/Slide/Flip, RM: sofort). Kauf über den EINEN
Geld-Pfad (`Economy.award`-Gegenstück), Persistenz im cosmetics-Slice,
`phone_shell.gd` zeichnet Case + Sticker als Rahmen-Layer. Klein, aber es
verzahnt drei Bestandssysteme (Garderobe, Album, Telefon) zu einem
Personalisierungs-Loop — Ein-Spiel-Gefühl auf der Meta-Ebene.
**Aufwand:** S–M · **Impact:** 3 · **Risiko:** sehr niedrig — reine
Daten + ein Render-Layer; Sticker-Slots brauchen eine Deckelung (3), damit
das Case kein Wimmelbild wird.

---

## Übersicht

| # | Idee | Aufwand | Impact | Risiko | Playtest-Bezug |
|---|---|---|---|---|---|
| J1 | Beute-Flug-Dreiklang (Flug + Arpeggio + Haptik) | M | 5 | niedrig | — |
| J2 | Icon-Bühne + Namensschilder (Quer-HUD) | M | 5 | niedrig–mittel | PT4-B4 |
| J3 | Hero-Morph-Übergänge | M | 5 | mittel | — |
| J4 | Overlay-Dirigent | M | 5 | mittel | PT4-B7 |
| J5 | Gesten-Arbiter + Kanten-Wisch + Long-Press | M–L | 4–5 | mittel | PT4-B3 |
| J6 | Haptik-Partituren | S–M | 4 | niedrig | — |
| J7 | Sheet-Physik + Gooby-Peek | M | 4 | niedrig | — |
| J8 | Kontext-HUD + Stat-Flüstern | M | 4 | mittel | PT2-B9, PT4-B6 |
| J9 | Side-Sheets im Querformat | M–L | 4–5 | mittel | PT2-B6 (Muster) |
| J10 | Reduced Motion mit Liebe | S–M | 4 | niedrig–mittel | — |
| J11 | Gooby färbt das UI | M | 4 | mittel | — |
| J12 | Lade-Momente 2.0 | S–M | 3–4 | sehr niedrig | PT2-B5 |
| J13 | Audio-Bühne (Musik-Ducking) | S | 3–4 | niedrig | — |
| J14 | Telefon-Case + Klingelton | S–M | 3 | sehr niedrig | — |

## Paket- und Abhängigkeits-Hinweise für den Konsolidierer (Welle J+)

- **„Dopamin-Kern"-Paket:** J1 + J6 + J13 teilen die Feedback-Anker
  (`count_to`, `panel_sheet.gd`, Haptik-Partitur) — zusammen umsetzen, ein
  gemeinsamer Testlauf über Quest-Claim/Kauf/Results deckt alle drei.
- **„Leitformat-Struktur"-Paket:** J2 + J8 arbeiten beide in
  `hud.gd`/`hud_sichtbarkeit.gd` (Datei steht bei 947/1000 Zeilen —
  Namensschild/Slot-Logik als EIGENE Helfer-Dateien nach dem
  `hud_label_fit.gd`-Muster anlegen!); J9 danach, weil Side-Sheets die
  HUD-Weichen-Richtungen mitbestimmen.
- **J5 vor J3-Stufe-2:** Router-gebundene Morphs brauchen den Arbiter nicht,
  aber der Kanten-Wisch-Zurück und Hero-Morphs konkurrieren um dieselben
  Übergangs-Momente — Reihenfolge klären.
- **J4 zuerst schneiden, wo es brennt:** das Onboarding-Fenster (PT4-B7) ist
  der messbare Pilot; die PT4-Flows haben die Sonden schon eingebaut.
- **Golden-/Wachen-Vorsicht:** J2 (kein Ellipsis mehr), J10 (RM-Semantik) und
  J13 (Pegel-Wächter) ändern Erwartungen bestehender Tests — Verträge bewusst
  mitziehen, nie stillschweigend.
- **Durchgehende Leitplanken:** alle Motion neu IMMER über
  `UiMotion`/`AcTokens`-Tokens (DUR_POP/DUR_SHEET, TRANS_BACK/EASE_OUT — die
  Web-Feder, die der User eingefordert hat); jede Idee braucht ihren
  Reduced-Motion-Zweig ab Tag 1 (J10 definiert die Grammatik dafür); Sounds
  NUR über bestehende SfxMap-Ids + Pitch-Regeln der AUDIO-GRAMMATIK; Haptik
  nie doppelt (SquishButton-Tap ist automatisch); alles headless testbar
  halten (pure Logik-Dateien nach `hud_label_fit.gd`/`toast_queue.gd`-Vorbild),
  damit das Playtest-Harness aus G7-P58 jeden Moment nachstellen kann.
