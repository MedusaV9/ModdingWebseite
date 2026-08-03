# G8-PTDLC — Playtest „Welle B beider DLCs: Goobye-Großmarkt/Preise/Backstation + McGooby-Vollmodus" (W18/R3)

- **Agent:** PT-DLC · **Branch:** `cursor/bubble-shield-loop` · **Datum:** 2.8.
- **Bereich:** Die FRISCHEN Welle-B-Inhalte beider DLCs, gespielt wie ein
  echter (skeptischer) Spieler: (a) Großmarkt-Rundfahrt komplett mit
  Staffel-Rabatt/Tagesangebot/Kofferraum/Budget, (b) Preis-Schieber →
  Markttag-Reaktion + Trend-Banner, (c) McGooby-Kauf-Gate (Probeschicht →
  Angebot → Level-/Münz-Gate → Kauf) + volle Schicht mit Fritteuse/Salz,
  Getränken/Sprudel und Bühne, (d) Backstation + Alwin-Streak über 3
  Markttage. Geld und Lager wurden in JEDEM Schritt mit EIGENER
  Doc-Mathe nachgerechnet (nicht mit den Spiel-Statics) — Abweichung = rot.
- **Methode:** 4 neue Flows `tests/tools/playtest_flows/flow_ptdlc_*.gd`
  spielen das ECHTE Spiel (main.tscn, frisches `user://`, komplettes
  Onboarding, Kauf über den DLC-Hub wie ein Spieler). Ausführung strikt
  unter `flock -w 7200 /tmp/gooby_godot_global.lock tools/ci/run_playtest.sh
  <flow>`; Leitformat quer 2868x1320 + Hochformat-Stichprobe 1320x2868
  (Flows a, b, c). Seeds + Goldwerte stammen aus der Offline-Seedsuche
  `flow_ptdlc_seedsuche.gd` (rechnet mit den ECHTEN Statics; Aufruf im
  Datei-Kopf) — die Läufe sind dadurch voll deterministisch.

## Lauf-Übersicht (finale Läufe unter `/tmp/gooby-godot/artifacts/PLAYTEST/`)

| Flow | Lauf | Ergebnis |
| --- | --- | --- |
| `flow_ptdlc_grossmarkt` (a) | `ptdlc_a2` | **90/90 OK** — Staffel 57 exakt, Angebot 63 exakt, Kofferraum-Deckel, Budget-Klemme, Kauf −63, Lager 32→44, Regal-Sim 34==34, Markttag Seed 7 (40 ᴳ, 3 Kunden), Feierabend +40 exakt |
| `flow_ptdlc_preise` (b) | `ptdlc_b1` | **76/76 OK** — Trend-Banner == echter Trend (Gemüse ★), Faktor 1,00→1,30 im Save, Lust-Texte wechseln, gleicher Seed 2× gespielt: Möhren 3→2, Umsatz 37→36, beide Tage == Goldwerte |
| `flow_ptdlc_mcgooby_voll` (c) | `ptdlc_c2` | **87/87 OK** — Probeschicht-Kasse 60 P/19 ᴳ exakt, Level-Gate-Zeile + disabled, Broke-Kauf ohne Abbuchung, Kauf −3000 exakt, volle Schicht 89 P: Grill-Tap, Sprudel-Gag ×2, „zu früh"-Callout ohne Wertung, Salz +4, Bühne +6 (2. Tipp wirkungslos), Kasse 22+13=35 exakt |
| `flow_ptdlc_backstation` (d) | `ptdlc_d1` | **105/105 OK** — „Backen (9)" == eigene Kosten, 3 Chargen (Brot 5→14, je −9 exakt), Deckel-Toast ohne Abbuchung, Duft-Bonus messbar (Tag 2: +13 ᴳ), Alwin-Sonderwunsch (2 Möhren), Streak 1→2→3, Belohnung +12 exakt mitgebucht |
| `flow_ptdlc_grossmarkt` 1320x2868 | `ptdlc_a3_hoch` | 89 OK / **1 FAIL** = Befund **D1** (Slot 0 halb außerhalb des Bildschirms, Regal 29 statt 34) |
| `flow_ptdlc_preise` 1320x2868 | `ptdlc_b2_hoch` | 69 OK / 7 FAIL — **alle 7 dieselbe Wurzel D1** (Slot-Taps rutschen um einen Slot, Brot fehlt → Goldwerte verfehlt; Preis-Sheet selbst voll funktionsfähig) |
| `flow_ptdlc_mcgooby_voll` 1320x2868 | `ptdlc_c3_hoch` | **87/87 OK** — kompletter Kauf-Weg + volle Schicht auch hochkant grün |

Iterations-Läufe (Flow-Fehler, keine Spiel-Bugs): `ptdlc_a1` (Erwartung
„Kasse: 500" — real 550, s. Einordnung I3), `ptdlc_c1` (erfundener
Sheet-Titel „McGoobys Goldener Deal" — real „Dein eigener Laden!";
Broke-Check gegen 700 statt 719 nach Probe-Lohn).

**Bilanz: 7 Läufe, 603 grüne Schritte, >60 exakte Geld-/Lager-/
Plan-Nachrechnungen — 0 Geld-Fehler im Spiel.** Alle 8 FAILs der
Hochformat-Läufe haben EINE Wurzel (D1).

## Befunde nach Schweregrad

### D1 — MITTEL (nur Hochformat): Regal-Slot 0 hängt halb außerhalb des linken Bildschirmrands — nicht (sauber) antippbar, Einräumen bricht

- **Repro:** Beliebigen Goobye-Laden hochkant (1320x2868) öffnen, Phase
  „Einräumen": Der „+"-Knopf des ERSTEN Slots ist nur zur Hälfte sichtbar
  (Mittelpunkt außerhalb). Harness-Taps auf die Knopfmitte gehen ins
  Leere; ein Spieler-Daumen trifft bestenfalls die rechte Knopfhälfte.
  Folge im Lauf `ptdlc_a3_hoch`: nach 5 Slot-Taps nur 29 statt 34 Stück
  im Regal (×6/×8/×8/×7, Slot 0 leer); in `ptdlc_b2_hoch` rutschen alle
  Füllungen um einen Slot (Brot kommt nie ins Regal) und der Markttag
  verfehlt die Goldwerte (27 statt 37 ᴳ) — der Tag selbst bleibt in sich
  konsistent, es fehlt schlicht die Ware.
- **Screenshots:** `ptdlc_a3_hoch/077_slot_0_fuellen.png` (halber Knopf am
  Rand), `ptdlc_a3_hoch/081_slot_4_fuellen.png` (×6/×8/×8/×7, Slot 0 leer),
  `ptdlc_b2_hoch/039_slot_0_apfel_FAIL.png`.
- **Fix-Verdacht:** `laden_scene.gd::_layout_slots()` legt die Knöpfe per
  `_cam.unproject_position(...)` auf die 3D-Anker, OHNE in den sichtbaren
  Bereich zu klemmen. Hochkant zeigt die Kamera einen schmaleren
  Ausschnitt → der linkeste Anker landet bei x<0. Klemmen auf
  Insets/Viewport (Muster `ScreenShell`) ODER Kamera-Framing hochkant so
  wählen, dass `REGAL_BREITE` horizontal hineinpasst.
- Quer (Leitformat) ist NICHT betroffen: `ptdlc_a2` füllt 34/34 exakt.

### D2 — NIEDRIG (Polish, quer + hoch): Großmarkt-Rampe — Palettenliste schwebt „nackt" über der 3D-Szene

Drei zusammenhängende Schönheitsfehler auf demselben Screen
(`grossmarkt_scene.gd`, Rampen-Phase):

1. **Kein Panel hinter der Liste:** Die Waren-Zeilen liegen direkt über
   Himmel/Lieferwagen/Straße/Wiese. Der grüne Van steht mitten HINTER den
   Steppern (das „−" von Brot sitzt hochkant exakt auf dem dunklen
   Vorderrad — wirkt wie ein zweiter, dunkler Knopf), und die kleinen
   grauen Sub-Zeilen („Zeile: 57 · Staffel!", „Heute im Rampen-Angebot!")
   verlieren auf dem grauen Straßenband deutlich Kontrast.
2. **Zeilen scrollen unter die transparente Kopfzone:** Beim Rollen
   schiebt sich die oberste Waren-Zeile sichtbar UNTER die
   „Rampen-Angebot …"-Headline (quer `047`: „Möhre · 3" halb überdeckt;
   quer `053`: ein Stepper-Paar lugt hinter der Headline hervor). Dasselbe
   Muster im Preis-Sheet: die Trend-Zeile scrollt unter den Titel
   „Preise am Regal" (`ptdlc_b1/062_gemuese_hochgezogen.png`).
3. **Scrollbar-Strich durch die Plus-Spalte:** Der dunkle
   VScrollBar-Strich läuft exakt durch die „+"-Knöpfe (quer UND hoch);
   hochkant stößt zusätzlich die Headline „… −15 %" an den rechten Rand.
- **Screenshots:** `ptdlc_a2/047_staffel_tag_da.png`,
  `ptdlc_a2/053_angebot_plus_2.png`, `ptdlc_a3_hoch/047_staffel_tag_da.png`.
- **Fix-Verdacht:** Halbtransparentes Panel/Backdrop hinter Liste +
  Kopf (Muster Preis-Sheet-Karte), `clip_contents`/Top-Margin unter der
  Headline, Scrollbar-Inset bzw. schmalere Content-Breite; Headline
  hochkant per `autowrap`/kleinerem Font.
- Funktional ist ALLES korrekt (jeder Betrag exakt nachgerechnet) — es
  geht nur um Lesbarkeit/Wertigkeit des am dichtesten beschrifteten
  Screens der Welle B.

### D3 — NIEDRIG (nur Hochformat): McGooby-Angebots-Sheet reserviert fast die volle Bildhöhe — riesige Leerfläche unter dem Inhalt

- **Repro:** Probeschicht hochkant beenden → „Angebot ansehen". Titel,
  Text, Preis, Gate-Zeile und Knöpfe füllen nur das obere ~Sechstel des
  Sheets; darunter ~70 % leeres Weiß bis fast zur Unterkante. Quer hüllt
  sich dasselbe Sheet eng um den Inhalt (vgl. `ptdlc_c2/039…`).
- **Screenshot:** `ptdlc_c3_hoch/039_angebot_oeffnen_gate1.png`.
- **Fix-Verdacht:** Sheet-Höhe content-hugging statt fester
  Höhen-Ratio in `mcgooby_offer.gd`/Sheet-Baustein.
- **Dazu (Typo, beide Formate):** Die Gate-Zeile („Kaufen geht ab Level
  14 …") ist das WICHTIGSTE Element des Sheets, steht aber im kleinsten
  Schriftgrad wie Kleingedrucktes. Und auf der Demo-Feierabend-Karte
  bricht der Hinweis „… könnte DIR gehören …" so um, dass das „…" allein
  in der Zeile hängt (`ptdlc_c2/038_angebot_block_da.png`).

### D4 — NIEDRIG (Design/UX): Backofen-Deckel und Duft kleben am ECHTEN Kalendertag, nicht am Markttag — Toast „morgen backt er wieder" führt in die Irre

- **Beobachtung (Lauf `ptdlc_d1`):** `GoobyeBackofen` zählt Chargen pro
  `tag_key` = Kalenderdatum (`laden_scene.gd::_tag_key()`). Wer wie im
  Test (und wie ein Kind am Wochenende) MEHRERE Markttage in einer
  Sitzung spielt, teilt sich die 3 Chargen über ALLE diese Tage: Tag 1
  zwei Chargen, Tag 2 nur noch eine, Tag 3 gar keine — der Toast sagt
  dabei „Der Ofen hat für heute Feierabend — morgen backt er wieder",
  obwohl der nächste MARKTTAG Sekunden später beginnt. Umgekehrt bleibt
  der Duft-Bonus an Folge-Markttagen desselben Datums GRATIS aktiv
  (einmal backen, ganze Sitzung duften — Tag 3 hatte Duft ohne Charge).
- **Screenshot:** `ptdlc_d1/066_deckel_vierte_charge.png`.
- **Geld/Logik sauber:** Deckel bucht NICHTS ab (Münzen+Lager geprüft),
  Kosten 9 exakt, Duft-Wirkung selbst korrekt verdrahtet (s. u.).
- **Fix-Verdacht:** Markttag-Zähler statt Datum als `tag_key` injizieren
  (die Uhr wird bereits hereingereicht — Aufrufstellen in
  `laden_scene.gd` Z. 209/439), Toast-Text auf „für diesen Markttag".
  Falls das Datum GEWOLLT ist (Anti-Grind), Toast-Text entsprechend
  ehrlich machen („für heute" → „bis morgen früh") und den Duft beim
  Markttag-Wechsel neu bewerten.

### Einordnungen ohne Befund (I1–I4) — sahen erst nach Bugs aus

- **I1 „Kassensturz zeigt 16 statt 40":** Die große Zahl auf der
  Kassensturz-/Einräumen-Karte ist ein `UiMotion.count_to`-Hochzähler —
  Screenshots erwischen Zwischenstände (`ptdlc_a2/085…`: 16 auf dem Weg
  zu 40; `ptdlc_a2/070…`: 11 auf dem Weg zu 12 Kisten). Endwerte exakt.
- **I2 „Alwin sagt nur ‚Onkel'":** `AcBubble` tippt per
  Buchstaben-Typewriter in eine für den VOLLEN Text vorvermessene Blase
  (`ptdlc_d1/052…`, `096…`) — Standbild-Artefakt, kein Textverlust.
- **I3 „Kasse: 550 statt 500":** Beim Münz-Cheat über 1000 feuert das
  `coins1000`-Achievement (+50, Auto-Award der Achievements-Engine).
  Für Playtests heißt das: Kassen-Anzeigen nie gegen feste Summen
  prüfen (Flows rechnen jetzt dynamisch); für Spieler ist es korrektes
  Verhalten.
- **I4 „Qualität angepasst"-Toast** in mehreren Screenshots = die
  Auto-Grafikstufe unter llvmpipe (Software-GL), kein DLC-Thema. Er
  überdeckt hochkant kurz die Kassen-Zeile (`ptdlc_a3_hoch/047…`) —
  verschwindet von selbst.

## Geld-Exaktheit (eigene Nachrechnung, alles grün)

- **Großmarkt:** Brot EK 6 (= 60 % von 10) ×10 = 60, Staffel −5 % → **57**
  == SummeZeile; Rampen-Angebot Eigenmarke −15 % (Hoppel-Pops → 3/Stück)
  → Korb **63**; Kauf: 500−63=**437** ᴳ + Lager JE WARE exakt +Korb;
  Ankunftszeile „12 Kisten für 63 Münzen" wortgleich. Kofferraum hart bei
  24/24 („Mehr passt nicht…"), Budget-Klemme blockt OHNE Abbuchung
  („Dafür reichen die Münzen gerade nicht.", Menge bleibt 10).
- **Markttage (6 Stück über a/b/d):** Jeder Tagesplan in sich stimmig
  (Bon-Summen == Umsatz, Bons == Kundenzahl), Kassensturz-Karte ==
  Plan (Umsatz/Kunden/Artikel), Regal-Rest == Bestand−Verkauf,
  Feierabend bucht EXAKT den Karten-Umsatz (437→477 usw.).
- **Preis-Schieber:** Faktor-Raster 0,05, Save exakt 1,300; Möhre 5→7
  (Marge 2→4 angezeigt); gleicher Seed: Möhren-Absatz 3→2, Umsatz 37→36 —
  teurer = weniger Griffe, Trend-Banner deckt sich mit dem
  Plan-Trend (Gemüse ★). Goldwert-Abgleich beider Tage grün.
- **McGooby:** Probeschicht 60 P → Basis 15 (60÷4) + Trinkgeld 4
  (2×1,1→2 + 2×1,2→2) = **19** ᴳ aufs Konto; Vollschicht 89 P → Basis 22
  + Trinkgeld 13 (2+2+3 Combo + Bühne 6) = **35** ᴳ, Ende-Karte
  (Salz 1/Bühne 6/Münzen 35) deckungsgleich; Kauf-Gates: Level-Gate
  disabled+Klartext, Broke-Kauf 719→719 (KEINE Abbuchung), Kauf exakt
  −3000. Bühne strikt 1×/Schicht (2. Tipp ändert nichts).
- **Backstation:** Kosten 9 = 6×0,5×3 im Knopf UND je Charge abgebucht;
  Brot 5→8→11→14; Deckel nach Charge 3 ohne Buchung; Alwin-Streak-
  Belohnung +12 landet zusammen mit Tag-3-Umsatz 29 als exakt +41.
- **Duft-Bonus messbar:** kontrafaktische Messung (gleicher Seed, Plan
  MIT vs. OHNE `duft_gruppe`): Tag 2 kauft der Kunde das 13-ᴳ-Brot NUR
  mit Duft (34 vs. 21 ᴳ) — der Bonus wirkt und lohnt sich sogar bei
  +30 % Brotpreis. An Tagen mit wenig Kundschaft (Seeds 4/3) ändert er
  nichts — er ist eine Griff-CHANCE, kein Garant. Fühlt sich richtig an.

## Sound-Hinweise

Headless läuft der Dummy-Audiotreiber — hörbar prüfen geht nicht, aber
die Cues sind an allen Welle-B-Momenten verdrahtet (Code-Sichtung):
Großmarkt `ui_buy`/`ui_coins`/warenspezifisches `ui_chip`
(`ton_fuer`), Fehlerfälle `ui_error`; Schicht `mg_good`/`mg_perfect`/
`mg_spill`, Salz/Getränke-Ticks, Bühne `ranch_fanfare`+`ranch_menge_jubel`,
Kassen `ui_coins`; Alwin-Belohnung `ui_coins` + Haptik. Keine
Audio-Fehlzeilen in 7 Lauf-Logs.

## Spielgefühl-Urteil

**Der Goobye-Loop trägt.** Großmarkt → Einräumen → Markttag → Kassensturz
hat einen runden Rhythmus; Staffel- und Rampen-Rabatt geben der Einkaufsliste
eine echte kleine Denksport-Note („lohnt die 10er-Palette?"), und dass
JEDER Cent nachrechenbar stimmt, macht das Management-Versprechen
glaubwürdig. Die Hochzähl-Kassen und Alwins Blase geben dem Feierabend
Wärme. **Wo es hakt:** Die Rampe ist der unaufgeräumteste Screen der Welle
(D2) — genau dort, wo der Spieler am meisten liest. Der Preis-Schieber
reagiert spürbar richtig (teurer = liegenlassen), aber bei 2–3 Kunden pro
Tag ist das Feedback verrauscht — ein kleiner „Verkäufe gestern"-Vergleich
je Gruppe im Sheet würde die Ursache-Wirkung-Schleife schließen. Die
Backstation ist ein feiner Mini-Ritus (backen → duftet → Brot geht weg),
nur der Tages-Begriff (D4) passt nicht zum Sitzungs-Spielstil von Kindern.
**McGooby-Vollmodus macht sofort Spaß:** Probeschicht als ehrliche Demo,
das Kauf-Gate erklärt sich in Klartext, und die volle Schicht hat mit
Salz-Moment, Sprudel-Gag („Es sprudelt!") und Bühnen-Einlage genau die
alberne Dichte, die der Grill allein noch nicht hatte. Dass „zu früh
loslassen" nur einen liebevollen Callout und KEINE Strafe gibt, ist
genau richtig fürs Zielpublikum. Wunsch: Nach dem Kauf startet die volle
Schicht sofort in place — ein kurzer „Der Laden gehört DIR!"-Beat
(Konfetti/Schild-Wechsel) würde den 3000-ᴳ-Moment feiern.

## Dateiliste (Dateihoheit PT-DLC)

- `GOOBY-GODOT/tests/tools/playtest_flows/flow_ptdlc_basis.gd` (+ `.uid`) —
  gemeinsamer Unterbau: Goobye-Kauf-Weg, EIGENE Doc-Mathe (EK 60 %,
  Staffel −5 %, Rampe −15 %, Backkosten, McGooby-Abrechnung), Laden-Tag-
  und Alwin-Helfer.
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_ptdlc_grossmarkt.gd` (+ `.uid`) — Flow (a).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_ptdlc_preise.gd` (+ `.uid`) — Flow (b).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_ptdlc_mcgooby_voll.gd` (+ `.uid`) — Flow (c).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_ptdlc_backstation.gd` (+ `.uid`) — Flow (d).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_ptdlc_seedsuche.gd` (+ `.uid`) —
  Offline-Seed-/Goldwert-Suche (kein Harness-Flow; nutzt die ECHTEN Statics).
- `docs/playtest/G8-PTDLC-welle-b.md` — dieser Report.

`gdformat`/`gdlint` grün auf allen sechs Flow-Dateien; Import unter flock
gelaufen, `.uid`-Dateien liegen bei. Spiel-Code unangetastet (Report only).

## Screenshot-Pfade (Auswahl, alle unter `/tmp/gooby-godot/artifacts/PLAYTEST/`)

- **Großmarkt quer:** `ptdlc_a2/047_staffel_tag_da.png` (Staffel-Tag +
  D2), `ptdlc_a2/053_angebot_plus_2.png` (Rampen-Angebot ×2),
  `ptdlc_a2/060_trunk_deckel_toast.png`, `ptdlc_a2/065_budget_toast.png`,
  `ptdlc_a2/070_kauf_nachgerechnet.png` (Einräumen-Karte),
  `ptdlc_a2/085_markttag_durch.png` (Kassensturz, I1).
- **Hochformat-Belege D1:** `ptdlc_a3_hoch/077_slot_0_fuellen.png`,
  `ptdlc_a3_hoch/081_slot_4_fuellen.png`,
  `ptdlc_b2_hoch/039_slot_0_apfel_FAIL.png`.
- **Preis-Schieber:** `ptdlc_b1/045_trend_banner_geprueft.png`,
  `ptdlc_b1/062_gemuese_hochgezogen.png` (+30 %, „Mutig!"),
  `ptdlc_b2_hoch/045_trend_banner_geprueft.png` (Sheet hochkant, sauber).
- **McGooby:** `ptdlc_c2/038_angebot_block_da.png` (Demo-Feierabend),
  `ptdlc_c2/039_angebot_oeffnen_gate1.png` (Level-Gate),
  `ptdlc_c2/046_kauf_zu_arm.png` (Münz-Gate),
  `ptdlc_c2/059_buehne_trinkgeld_callout.png` (+6 Trinkgeld-Regen),
  `ptdlc_c2/065_voll_aufgabe_05.png` (Fritteuse), `ptdlc_c2/067_voll_aufgabe_07.png`
  (Glitzersalz), `ptdlc_c2/085_voll_ende_zeilen.png` (Ende-Karte 35 ᴳ),
  `ptdlc_c3_hoch/039_angebot_oeffnen_gate1.png` (D3),
  `ptdlc_c3_hoch/067_voll_aufgabe_07.png` (Schicht hochkant, sauber).
- **Backstation/Alwin:** `ptdlc_d1/044_duft_aktiv.png` („Backen (9)"),
  `ptdlc_d1/052_tag1_alwin_spruch.png` (I2), `ptdlc_d1/066_deckel_vierte_charge.png`
  (D4), `ptdlc_d1/084_tag2_sonderwunsch_bon.png`,
  `ptdlc_d1/096_tag3_belohnung_toast.png` (Streak-3-Belohnung +12).
