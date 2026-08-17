# ROADMAP-W20 — konsolidierte Planner-Welle (W19/W5, 3./4. August)

Die seit W17 eingeplante **Ideen-Planner-Welle** ist gelaufen: 6 Planner-Agents
(Fable 5 Max thinking) haben je Bereich 10-14 priorisierte, am Code und an den
Design-Docs **verifizierte** Ideen geliefert — zusammen **76 Ideen**
(17 S / 40 M / 19 L). Dieses Dokument ist die konsolidierte Roadmap; die
Bereichs-Kapitel darunter enthalten alle Ideen im Original (Was / Warum mit
Quelle / Wie-Skizze / Risiko / Beweis).

Wichtige Ist-Korrekturen aus der Recherche (STATUS.md ist stellenweise älter
als der Code): InstantGooby/Snap und GOOBERANDO-3-Restaurants sind seit
W13B/C FERTIG; CEILING-Layer, Layout-Presets, Garage, Bücher-Abnutzung
existieren; die E13-P1-Server-Befunde (Crash-Durability, GoobyPal-Zustelllücke)
sind gefixt. Offen sind stattdessen die unten priorisierten Punkte.

## Top 10 (bereichsübergreifend, Spielerwert pro Aufwand)

| # | Idee | Größe | Bereich |
|---|---|---|---|
| 1 | Rang-Aufstiegs-Moment + Stations-Visuals (McGooby) | S | DLC |
| 2 | Veil-Ziel-Karten-Fix (DLC-Bibliothek lädt unter „Trautes Heim"-Karte; erledigt das G6-Paket „DLC-Ladebildschirme") | S | Technik |
| 3 | Erinnerungs-Horizont 2.0 (Soul kennt W18/W19-Features: DLCs, Entdecker-Karte, Geist-Rekorde, Mitbringsel) | S | Home/Soul |
| 4 | Arcade-Kacheln erzählen Fortschritt (Sterne aus beaten/best, Kategorien-Reihen, Quest-Chips) | S | Minigames |
| 5 | Freunde-Geister für Arcade-Rekorde (W19-Geist-Kurven über das Ranch-Geister-REST-Muster teilen) | M | Sozial×Minigames |
| 6 | Vollbild-Stadtkarte + Ziel-GPS-Pfeil (GODOT-PLAN §6; W19-Karten-Muster wiederverwenden) | M | Stadt |
| 7 | GOOBERANDO-Fahrer-Sichtung in der 3D-Stadt (E-city §5.2; fahrer_sim-Position existiert) | M | Stadt |
| 8 | Tages-Rätsel mit Streak-Kalender (deterministisch, 1 Versuch/Tag, Goldens unangetastet) | M | Minigames |
| 9 | „Als Nächstes"-Ziel-Karte + Erfolgs-Ketten (Progressions-Sichtbarkeit) | M | Meta |
| 10 | Stadt-Reveal-Messung + Time-Slicing nach dem Ranch-W19-Muster (welt_aufbau_takt) | M | Technik |

**Große Brocken danach (L):** McGooby-Team (Mitarbeiter mit Gag-Verträgen +
Ausbau, Doc §5/§6) · Goo-und-Bye-Team (Bipsi & Co. + Offline-Kasse §6.1) ·
GvZ-Coop (USER-WISHES §G) · GOOBY-Wochenpass · Tages-Anker-Duo
Herbert/Tagebuch (Home/Soul).

**Querschnitts-Regeln für alle Umsetzungs-Wellen:** Web-Paritäts-Goldens sind
unantastbar; geteilte Framework-/Ort-Dateien nur additiv-chirurgisch; Zeit/RNG
IMMER injiziert; transaktionale Käufe; Overlay-Dirigent respektieren
(CanvasLayer-Falle!); jede Idee braucht Wächter + wo sinnvoll Playtest-Flow.

---

# Bereich: Zuhause + Gooby (Soul)

# Roadmap-Ideen: Zuhause + Gooby selbst (Planner-Welle, W19+)

Bereich: Haus/Räume/Baumodus/Garten, Pflege-Loop, Soul-System, Kühlschrank/Speisen,
Haus-Events. Basis: UserFeedback.md (komplett), STATUS.md, D-house.md, F-gooby.md,
GODOT-PLAN.md §6 (D-/F-Backlog) + Code-Stichproben in `GOOBY-GODOT/scripts/home/`,
`scripts/soul/`, `scripts/events/`, `scripts/logic/`, `content/soul|events|books/`.

**Ehrliches Ist-Bild (verifiziert im Code, Stand `cursor/gooby-godot-loop-d1d8`):**
Der Bereich ist KEIN Rohbau — Baumodus inkl. CEILING-Layer/Presets/Garage, Pflege
(Sleep/Health-Zustandsmaschine, Zahnbürsten-Bruch, PflegeRunner mit Gähnen/Niesen/
Augenringen), Kühlschrank 2.0 (44 Speisen, Fütter-Regie), Soul (träge Laune,
5 Absichten, ~9 Erinnerungs-Typen, 12 Gesprächs-Einstiege, 50 Pack-Items,
12 inszenierte Gefühle) und 14 Haus-Events existieren vollständig und getestet.
Echte Lücken: Keller/Etage/Balkon (§D43), Laufband (§F75) + PC/GOBBULL (§F76)
nirgends im Code, kein Kochen, Herbert nicht persistent, Soul kennt die
W18/W19-Features (DLCs, Entdecker-Karte, Geister-Rekorde, Mitbringsel) noch nicht.

Verteilung: **3× S, 7× M, 3× L** — sortiert nach Spielerwert pro Aufwand.

---

## 1. Erinnerungs-Horizont 2.0 — Gooby kennt dein GANZES Spiel [S]

- **Was:** `SoulMemories` liefert heute ~9 Kandidaten-Typen (Rekord, Urlaub, Kitzeln,
  Ernte, Streak, Park, Spielzeit, 2 Vorlieben). Neue Kandidaten aus echten Save-Daten
  der letzten Wellen: „Weißt du noch, als der Kühlschrank umgekippt ist?“ (überstandene
  Events aus dem Event-Log), „Dein Laden hat schon N Kunden gehabt!“ (Goobye-Umsatz),
  „Die Schneekugel aus {Ziel} steht immer noch da!“ (Mitbringsel), Ranch-Fundorte
  („16/16! DU hast ALLES gefunden!“), „Geist geschlagen“-Momente. Dazu 4–6 neue kleine
  Wünsche (`WUNSCH_IDS` hat nur 4): „Ich will mal ALLE 16 Orte sehen“, „Einmal im
  Laden einkaufen, wo DU der Chef bist!“.
- **Warum:** Der meistwiederholte User-Wunsch ist Seele („Das Spiel hat keine Seele“,
  „Die Seele des Spiels fehlt“ — UserFeedback, 2× als eigener Punkt; Fix damals:
  Erinnerungen aus echten Erlebnissen). Die W18/W19-Brocken (DLCs, Entdecker-Karte,
  Geister, Mitbringsel) sind für Goobys Gedächtnis unsichtbar — genau das erzeugt
  wieder das „einzelne Spiele statt EIN Spiel“-Gefühl (UserFeedback 1.8.).
- **Wie (Skizze):** Nur `scripts/soul/soul_memories.gd` (neue `_add_*`-Statics, alles
  PURE, State wird hereingereicht) + `strings/de/soul_lines.json`/EN + ggf. 1–2 neue
  `erinnerung`-Items in `content/soul/data/soul.json`. Keine neuen Save-Felder
  (liest `dlc.goobye.*`, `ranch.karte.*`, `minigames.geister.*`, `soul.surpriseAt`).
  Komplett headless.
- **Risiko:** Gering. Einzige Falle: Save-Pfade der neuen Slices exakt treffen
  (Slice-Registry prüfen, nicht raten); String-Paritäts-Wächter (25 962 Checks)
  verlangt DE+EN synchron.
- **Beweis:** Unit-Wächter nach Muster der bestehenden Soul-Tests: Save-Fixture mit
  DLC-/Karten-/Geist-Daten → `candidates()` enthält genau die erwarteten IDs, ohne
  Daten KEINE Erinnerung (Kern-Versprechen der Datei); Cooldown-Determinismus über
  gepinnte `now_ms`/`roll`. Kein Playtest-Flow nötig.

## 2. Gesprächs-Welle 2 — Antwort-Chips zu dem, was WIRKLICH passiert [S]

- **Was:** `gespraeche.json` hat 12 Einstiege (Tageszeiten, Wetter, gefreut/
  eingeschnappt, Jubiläum, Erinnerung, vermisst). Neue Welle: 10–14 kontextuelle
  Mini-Dialoge — nach einem gelösten Haus-Event („Das mit dem Klopapier… erzählen wir
  NIEMANDEM?“ → Chips „Niemandem!“ / „Ich hab Fotos.“), nach Minispiel-Rekord, nach
  überstandener Krankheit, nach dem ersten DLC-Arbeitstag, beim Lieblingsessen, nach
  dem Wochenmarkt-Abrechnen. Antworten stupsen wie bisher die Laune und hinterlassen
  Mini-Einträge im Soul-Slice.
- **Warum:** Die Antwort-Chips waren ein W14-Liebling („du kannst Gooby antworten und
  er reagiert“) und sind seither nicht gewachsen. Gespräche, die sich auf echte
  Erlebnisse beziehen, sind der billigste ACNH-Moment im ganzen Spiel (UserFeedback
  „echte Gefühle wie bei Animal Crossing“).
- **Wie (Skizze):** Fast nur Daten: `content/soul/data/gespraeche.json` + Strings
  DE/EN. Code-Anteil klein: `gooby_gespraech.gd` dockt heute an `stoss_gruss` an —
  2–3 neue Moment-Ids (Event-gelöst, Rekord, genesen) müssen den Hook durchreichen
  (`seele_runner.gd`, `event_runner.gd` je 1 Zeile Signal-Glue). Baum-Navigation
  bleibt pur/testbar, Overlay-Dirigent-Prio 40 bleibt.
- **Risiko:** Gering–mittel: `seele_runner.gd` ist geteilter Hotspot paralleler
  Wellen (Merge-Konflikte); Frequenzbremse beachten, sonst quatscht Gooby nach jedem
  Event (Tagesdeckel der SoulFeelings-Bremse wiederverwenden).
- **Beweis:** Unit-Wächter: Baum-Navigation je neuem Gespräch (Chips → Follow-up →
  Ende nach `MAX_EBENEN`), Moment-Id-Routing deterministisch mit gepinntem roll.
  Playtest-Stichprobe: bestehender `flow_home_basis` + 1 Schritt „Event lösen →
  Chips erscheinen über dem Dirigenten, HUD bleibt tappbar“ (die W19-Layer-Falle
  ist dokumentiert — genau dafür gibt es den Abend-Prompt-Wächter als Vorlage).

## 3. Eigenleben-Nachschub: 8 neue Überraschungs- und Idle-Akte [S]

- **Was:** `soul.json` hat nur 4 `ueberraschung`- und 6 `idle`-Items — wer täglich
  spielt, kennt nach einer Woche alles. Nachschub: Gooby stapelt Bücher zu einem Turm
  und balanciert, macht „Ohren-Yoga“, versteckt sich im Karton und kichert, sortiert
  den Kühlschrank nach Farbe, malt mit Wachsmalstift auf einem Zettel, übt Winken vor
  dem Spiegel, beobachtet die Fenster-Diorama-Autos und kommentiert sie.
- **Warum:** UserFeedback-Diagnose zum Seele-Fix: „Unsinn machen, wenn man nicht
  hinsieht“ — der Mechanismus existiert (Idle-Akte mit Cooldown-Rotation im
  SeeleRunner), nur der Vorrat ist klein. Mehr Varianz = das „lebendiges Haustier“-
  Gefühl pro Session, ohne neue Systeme.
- **Wie (Skizze):** `content/soul/data/soul.json` (neue Items mit Band-Gates: Bücher-
  Turm nur bei guter Laune, Karton-Verstecken bei jeder), Strings DE/EN; für 2–3 Akte
  kleine Prop-Setups nach `event_props.gd`-Muster (Karton, Zettel liegen schon als
  Assets im Repo). Keine Save-Felder, Zufall läuft über die bestehenden
  Runner-Overrides.
- **Risiko:** Gering. Props müssen nach dem Akt sauber abgebaut werden (die
  W18-Lektion vom Wurm-Event: Event-UI überlebte den Raumwechsel — Abbruch-Pfad
  mittesten). Auf iPhone/llvmpipe keine neuen Partikel-Orgien.
- **Beweis:** Bestehende Soul-Pack-Wächter erweitern (jedes Item braucht gültige
  Felder/Strings — der 50-Effekte-Validitäts-Stil), Cooldown-Rotation deterministisch;
  Playtest: `flow_home_basis`-Variante mit Zeitraffer, Screenshot je neuem Akt.

## 4. Goobys Tagebuch — das Gedächtnis zum Anfassen [M]

- **Was:** Ein Tagebuch (neues Möbel oder fest auf dem Nachttisch): jeden Tag „malt“
  Gooby genau einen Eintrag aus echten Save-Ereignissen — Wachsmalstift-Look, 1 Skizze
  (Icon-Kombination aus vorhandenen Assets) + 1 krakeliger Satz („Heute 3 Möhren
  geerntet. Ich habe EINE probiert. Okay zwei.“). Spieler blättert rückwärts durch
  die Woche; besondere Tage (Geburtstag, Rekord, Event überstanden) bekommen Sticker
  im Eintrag.
- **Warum:** Direkte Verlängerung des Seele-Fixes („Erinnerungen aus echten
  Erlebnissen“, UserFeedback) ins Sichtbare — Erinnerungen sind bisher nur flüchtige
  Sprüche. Dopamin-Schleife: abends nachschauen, was Gooby über den Tag denkt =
  täglicher Wiederkehr-Grund (User: „Dopamin“, „Liebe zum Detail“).
- **Wie (Skizze):** Neu: `scripts/soul/tagebuch_logic.gd` (PURE: Save-Slice →
  Eintrags-Kandidaten → deterministische Wahl per Tages-Seed; Reuse der
  `SoulMemories`-Digger), `scripts/home/interactables/tagebuch.gd` (Buch-UI nach
  `story_time.gd`-Muster), eigener Save-Slice `tagebuch` (W1d-Registry, Ring aus
  max. 14 Einträgen à {tag, ereignis_id, args} — klein halten). Strings DE/EN.
- **Risiko:** Mittel: Eintrags-Erzeugung muss beim Tageswechsel exakt einmal laufen
  (Ticker-Anbindung; Zeitzonen-Falle ist im Repo dokumentiert — Schnupfen-Wetter-Bug
  W16). UI-Layering über den Dirigenten, sonst nächste CanvasLayer-Falle.
- **Beweis:** Unit-Wächter: gleiche Save-Fixture + gleicher Tag ⇒ bit-gleicher
  Eintrag; 14-Tage-Ring rolliert korrekt; kein Eintrag ohne echtes Ereignis.
  Playtest-Flow `flow_home_tagebuch`: Tag simulieren (Dev-Zeit-Offset existiert im
  Werkzeugkasten) → füttern/ernten → Tag wechseln → Buch öffnen → Screenshot des
  Eintrags, quer + hochkant.

## 5. Herbert wird sesshaft — der Wurm-Freund zieht ins Beet [M]

- **Was:** Nach dem ersten `wurm_freund`-Event zieht Herbert dauerhaft in eine
  Beet-Ecke des Gartens (kleines Erdloch-Prop mit Schild „HERBERT“). Täglich
  besuchbar: Gooby legt sich bäuchlings daneben, „unterhält“ sich (Herbert sagt
  nichts — Running Gag), gelegentlich hat Herbert etwas „ausgegraben“ (1 Material,
  1 Münze, ganz selten ein Geheim-Sticker). Beim Gießen des Beets freut sich Gooby
  stellvertretend. Bei Regen schaut Herbert raus; im Urlaub „hütet“ Herbert das Haus
  (eine Zeile in der Heimkehr-Karte).
- **Warum:** Herbert ist der heimliche Star der Events (im Auftrag namentlich
  genannt; W18-Playtest hat das Event extra repariert). Ein NPC-Freund mit
  Dauerpräsenz füllt genau die User-Lücke „keine leeren Orte / lebendige Orte“ für
  den Garten und vertieft „lebendiges Haustier“ um eine Beziehung, die GOOBY selbst
  führt (nicht der Spieler).
- **Wie (Skizze):** `scripts/home/garden/herbert.gd` (Prop + Tap-Interactable nach
  `interactables_host`-Muster), Save-Felder additiv im Garten-Slice
  (`herbert: {seit, besuche, letzterFund}`), Fund-Logik PURE + deterministisch
  (Tages-Seed wie Tagesangebote), 10–12 Gooby-Lines DE/EN, Anbindung an
  `soul_memories` („Herbert wohnt jetzt seit N Tagen hier!“) und ans
  `wurm_freund`-Event (Erst-Trigger setzt `seit`).
- **Risiko:** Mittel: Garten-Szene ist geteilt (Streu/Deko/Grid — Platz für das Loch
  fest reservieren wie Tür-Freihaltezonen, sonst baut jemand Herbert zu → Regel:
  Zelle gilt als `blocked`). Balancing der Funde klein halten (kein zweiter
  Belohnungs-Kanal, der die Ökonomie-Wächter bricht).
- **Beweis:** Unit-Wächter: Erst-Event setzt Herbert, Funde deterministisch pro Tag,
  blockierte Zelle bleibt unbebaubar (Baumodus-Kollisionstest erweitern);
  Playtest-Flow `flow_garten_herbert`: Event lösen → Garten → Besuch + Fund →
  Screenshot, beide Formate.

## 6. Haus-Events Welle 2 — sechs neue Mini-Action-Momente [M]

- **Was:** Sechs neue Events in der bestehenden Engine: **Versteckspiel** (Gooby ist
  „weg“, 3 mögliche Spots pro Raum, Ohren gucken raus), **Kissenburg** (er hat alle
  Kissen zu einer Burg gestapelt und verteidigt sie — Option: mitspielen oder
  aufräumen; verknüpft mit dem vorhandenen `sup_turm`-Überraschungs-Wunsch),
  **Staubmops** (unterm Sofa wohnt ein Staubball „mit Augen“ — wegsaugen oder
  adoptieren), **Verkleidungskiste** (Gooby trägt heimlich ein besessenes Cosmetic
  falsch herum), **Badewannen-Flotte** (Quietscheenten-Armada blockiert das Bad),
  **Mitternachts-Radio** (er tanzt nachts leise vor dem IKEA-Radio — erwischen wie
  Nutella-Nacht).
- **Warum:** USER-WISHES §F79 sagt wörtlich „MEHR solche Mini-Action-Events
  erfinden“; die 14 bestehenden sind seit W13 statisch. Events sind der stärkste
  „lebendiges Haustier“-Beweis pro Session und die Engine (`event_runner`,
  `event_props`, Buffs, Fail-Texte) trägt neue Defs fast gratis.
- **Wie (Skizze):** `content/events/data/events.json` (+6 Defs, diesmal MIT
  `trigger.window`, z. B. Mitternachts-Radio nachts), je Event ein
  `szene_setup`-Hook (Muster `mumie_szene.gd`/`gewitter_szene.gd`), Strings DE/EN.
  Verkleidungs-Event liest `cosmetics.owned` (nur besessene Items — Ehrlichkeits-
  Regel wie bei Erinnerungen). Keine neuen Save-Felder außer Event-Cooldowns
  (existieren generisch).
- **Risiko:** Mittel: jedes Event braucht den sauberen Abbruch-/Raumwechsel-Pfad
  (dokumentierte W18-Falle); Radio-Event nur wenn Radio-Möbel platziert (Gate wie
  GOB.TY); Fenster-Trigger dürfen den Determinismus der Event-Wahl nicht brechen
  (Zeit kommt aus `gs.clock`, Tests pinnen sie).
- **Beweis:** `test_events_engine/runner`-Erweiterung: jede neue Def valide,
  Trigger-Fenster respektiert, Auflösung + Buff + Fail-Pfad deterministisch;
  Playtest-Flow `flow_home_events_welle2`: 2 Events per Dev-Werkzeugkasten auslösen
  (Events-Tab existiert), lösen, Screenshot der Auflösungs-Momente.

## 7. Suppentag — Krankenpflege, die sich wie Kümmern anfühlt [M]

- **Was:** Krankheit ist heute mechanisch korrekt (healthy→queasy→sick, Medizin,
  Tierarzt), aber transaktional. Neu: kranker Gooby liegt eingemummelt im Bett
  (Decke + Wärmflasche-Props), Fieber-Check als Mini-Geste (Thermometer 3 s halten),
  Suppe ans Bett bringen (jede warme Speise wird am Bett zur „Suppe“ — sichtbar
  verkürzte `recoverMin`), 1×/Krankheit „Vorlesen hilft“ (Geschichten-Stunde-Reuse
  mit Husten-Unterbrechern). Beim Gesundwerden: Aufsteh-Moment mit zerzaustem Fell
  + dankbarer Zeile, die sich später als Erinnerung meldet.
- **Warum:** Pflege-Loop = Kern von „virtuelles Haustier“; der User misst das Spiel
  an ACNH-Wärme („echte Gefühle“) und an Liebe zum Detail. Krankheit ist der
  emotionalste Pflege-Moment und aktuell der am wenigsten inszenierte (PflegeRunner
  macht nur Niesen/Tempo/Blässe).
- **Wie (Skizze):** `pflege_runner.gd` (Bett-Modus-Inszenierung), `health.gd` bleibt
  die pure Wahrheit — nur additiv `pflege_bonus_min` auf `recoverMin` (PURE,
  gedeckelt, damit Krankheit nie Strafe/Farmen wird), `kuehlschrank.gd`/FuetterRegie
  bekommt den „ans Bett bringen“-Zweig, 8–10 Lines DE/EN, 2 kleine Props
  (Wärmflasche, Thermometer — Blender-Pipeline vorhanden). Save: keine neuen
  Slices, Felder additiv im health-Slice.
- **Risiko:** Mittel: `health.gd` ist Web-paritäts-getestet — Bonus strikt additiv
  halten, Default-Verhalten bit-gleich (Golden-Wächter!). FuetterRegie ist frisch
  poliert (W14) — Doppel-Tap-/Busy-Guards nicht aufweichen.
- **Beweis:** Unit-Wächter: Web-Paritäts-Goldens unverändert grün, Bonus deckelt,
  Genesung deterministisch; Playtest-Flow `flow_home_suppentag`: per Dev-Tools krank
  schalten → Bett-Szene → Suppe → Genesungs-Moment als Video/Screenshots.

## 8. Der Kühlschrank lebt — Einkaufszettel + Reste-Tage [M]

- **Was:** Geht der Vorrat zur Neige, hängt ein Wachsmal-Einkaufszettel am
  Kühlschrank (Gooby hat ihn „geschrieben“: 3 Wunsch-Speisen, davon 1 Quatsch-Eintrag
  wie „NUTELLA (das große)“). Tap → REHWEI-Route mit vorbefülltem Korb. Ist GENAU
  eine Zutaten-Sorte übrig, gibt es den „Reste-Tag“-Gag (Gooby: „Heute gibt es
  Möhre. Morgen auch. Übermorgen… rate mal.“). Nach dem Einkauf räumt Gooby sichtbar
  mit ein (trägt eine Speise, legt sie falsch ab, korrigiert sich).
- **Warum:** Verzahnt Pflege-Loop und Stadt-Loop zu „EIN Spiel“ (der zentrale
  1.8.-Kritikpunkt) und gibt dem Kühlschrank 2.0 (W14-Liebling) eine Fortsetzung.
  Der leere Kühlschrank hat heute nur einen Leerzustand — der Zettel macht daraus
  einen Handlungs-Anstoß mit Charme statt UI-Hinweis.
- **Wie (Skizze):** `scripts/home/fuettern/einkaufszettel_logic.gd` (PURE:
  Vorrats-Slice → Zettel-Inhalt, deterministisch per Tages-Seed),
  Zettel-Prop + Tap am Kühlschrank (`kuehlschrank.gd`), Übergabe an die bestehende
  REHWEI-Route (SceneRouter-Route existiert im Leerzustand bereits), `soul_intent`
  bekommt die Variante „hungrig vor LEEREM Kühlschrank“ (traurig davorstehen statt
  hinlaufen). Save: nichts Neues (liest `inventory.food`).
- **Risiko:** Gering–mittel: Szenen-übergreifender Handoff (Korb-Vorbefüllung muss
  bei Abbruch der Fahrt sauber verfallen — Transaktions-Muster der Kauf-Bugfixes
  W13/W18 nutzen). Kein Nag-Loop: Zettel max. 1×/Tag.
- **Beweis:** Unit-Wächter: Zettel-Inhalt deterministisch, erscheint nur unter
  Schwelle, Korb-Handoff transaktional (rot-vor-grün: Abbruch frisst nichts);
  Playtest-Flow: Vorrat leeren (Dev-Tools) → Zettel → REHWEI → zurück → Einräum-
  Moment, quer + hochkant.

## 9. Gute-Nacht-Routine — das Abendritual als Bogen [M]

- **Was:** Der „Kuschelabend?“-Prompt (existiert) wird zum kleinen Ritual-Bogen:
  Annehmen startet eine 60–90-s-Kette — Vorhänge/Rollos schließen (1 Tap je
  Fenster), Nachtlicht an (Lampen-Reuse), optional Geschichten-Stunde, dann
  Zudeck-Moment mit ruhiger Kamera. Wer das Ritual an mehreren Abenden macht,
  bekommt einen sichtbaren, ehrlichen Effekt: Gooby schläft schneller ein
  (weniger `needed_words`) und wacht mit besserer Laune auf — als Zeile erklärt,
  nie als Zahlen-Buff-UI.
- **Warum:** Das Morgen-Ritual (W18) war ein Volltreffer gegen Popup-Stau UND für
  die Wärme; abends endet der Tag heute abrupt. Tages-Rahmung (Morgen + Abend) ist
  DAS ACNH-Strukturgefühl, das der User sucht; dockt an F §3.2 Geschichten-Stunde
  und die vorhandene Sleep-Logik an.
- **Wie (Skizze):** `scripts/home/sleep/abend_ritual.gd` (Kette als Cutscene-Runner-
  Schritte, skippbar, Reduced-Motion-Kurzfassung), Anbindung an den Overlay-
  Dirigenten (Prio hinter Pflicht-Overlays), `story_books.gd::needed_words` bekommt
  einen additiven, gedeckelten Ritual-Faktor, Save additiv im story-/soul-Slice
  (`ritualStreak`). Strings DE/EN.
- **Risiko:** Mittel: Schlaf-/Ticker-Logik ist Web-paritäts-sensibel — Effekt nur
  auf `needed_words`/Morgen-Laune-Stoß legen, NICHT auf die Sleep-Zustandsmaschine.
  Dirigent-Reihenfolge abends testen (Gespräch Prio 40 vs. Ritual).
- **Beweis:** Unit-Wächter: Streak-Zählung über Tagesgrenzen (gepinnte Uhr),
  Deckel greift, Skip lässt Save unverändert; Playtest-Flow `flow_home_abend`:
  Abend simulieren → Ritual komplett → Einschlafen → Morgen-Gruß, als Video.

## 10. Hobby-Ecke: Laufband-Gag + GOBBULL-Zocken [M]

- **Was:** Zwei explizit gewünschte, nie gebaute Gag-Möbel: **Laufband** (IKEA-Kauf;
  Tap-Alternating-Minigame, das absichtlich unschaffbar wird — Gooby fliegt nach
  max. ~20 s theatralisch ab, Highscore „Sekunden bis zum Abflug“, Sticker bei 15 s,
  KEINE Stat-Wirkung) und **PC + GOBBULL-Konsole** (kaufen; „Zocken lassen“ →
  Gooby sitzt 1–2 h Realzeit am PC, Bildschirm-Glow, Sieg-/Niederlagen-Gags,
  +Spaß über Zeit, jederzeit abbrechbar mit „EIN Level noch!!“).
- **Warum:** USER-WISHES §F75 + §F76 wörtlich, F-gooby.md §3.2 hat das fertige
  Design, GODOT-PLAN §6 F-M3 listet beide als offen — im Code existiert nichts
  (verifiziert: kein `laufband`/`GOBBULL`-Treffer). Beide geben Möbeln Persönlichkeit
  („fast alles anpassbar“ + Gooby-Comedy) und dem IKEA-Katalog zwei Ziel-Käufe.
- **Wie (Skizze):** 2 Interactables nach `fernseher.gd`-Muster
  (`scripts/home/interactables/laufband.gd`, `pc_gobbull.gd`), Katalog-Einträge in
  `furniture_catalog.json`, Laufband-Minigame als Overlay (Tap-Mash-Overlay
  existiert als Muster: `tap_mash_overlay.gd`), Zock-Session als reine
  Save-Funktion der Uhr (GOOBERANDO-/Großmarkt-Fahrer-Muster). Neue Posen: `sit` +
  vorhandene Clips reichen für V1 (P2-Clips `treadmill_run`/`pc_gaming` als Kür,
  Blender-Pipeline vorhanden). Save: additiv (`hobby: {laufbandBest, zockBis}`).
- **Risiko:** Mittel: 1–2-h-Realzeit-Session muss App-Neustart überleben (reine
  Uhr-Funktion, kein Timer — das Muster ist im Repo etabliert); Laufband-Schwierig-
  keitskurve auf Touch kalibrieren (90-ms-Fenster aus F §3.2 auf echtem Gerät
  prüfen — llvmpipe-Input-Timing weicht ab, im Flow großzügiger asserten).
- **Beweis:** Unit-Wächter: Zock-Ertrag als pure Uhr-Funktion (vor/nach Neustart
  bit-gleich), Laufband-Abflug garantiert terminiert, Sticker-Trigger; Playtest-Flow
  `flow_home_hobby`: kaufen → platzieren → Laufband-Runde + Abflug-Video → PC-Session
  starten/abbrechen.

## 11. Keller, 2. Etage, Balkon — das Haus wächst WIRKLICH [L]

- **Was:** Drei kaufbare Erweiterungen nach D §4.1: Keller (düster-gemütlich, ideal
  für Hobby-/Werkraum), 2. Etage (großer freier Raum, Himmel-Fenster) und Balkon
  (outdoor, Wetter sichtbar, nur Outdoor-Möbel). Kauf löst das Bau-Overlay aus
  (Gerüst + Staub + „Tada!“), danach stehen Treppen-/Tür-Portale im Flur; alle
  Räume voll baubar mit dem bestehenden Grid.
- **Warum:** USER-WISHES §D43 wörtlich („Haus mit Geld upgraden: Keller, 2. Etage,
  Balkon“) — der größte unerfüllte D-Backlog-Punkt (GODOT-PLAN D-M3, verifiziert:
  `rooms.json` hat nur 4 Innenräume + Garten). Für Langzeit-Motivation ist ein
  wachsendes Haus DER Münz-Sink und ACNH-Kernfantasie; der Baumodus ist reif genug,
  dass neue Räume fast reine Daten sind.
- **Wie (Skizze):** `scripts/home/data/rooms.json` (+3 Einträge mit `price`,
  `portal`, `outdoor`-Flag), `room_defs.gd`/`home_entry.gd` (Kauf-Gate +
  unlockedRooms), Treppen-Portale über die bestehende Tür-Logik (`door_logic.gd`,
  Portal-Zellen in `GridData.blocked`), Balkon braucht Skybox/Wetter-Anbindung
  (Reuse `soul_wetter` + Garten-Wetter-FX), Bau-Overlay nach
  `home_build_anim.gd`-Muster, 2 Blender-Assets (Treppe rauf/runter, Geländer —
  D §9 #10). Save: `home.unlockedRooms` additiv, Migration unnötig (Default = alt).
- **Risiko:** Hoch(st) in diesem Katalog: Raum-Graph/Navigation, Kamera-Framing je
  Raumhöhe, Decken-Fade im Dachgeschoss, Fenster-Diorama „sky“-Vista neu; geteilte
  Hotspots `home_entry.gd`/`room_defs.gd`. iPhone-Speicher: Räume lazy laden wie
  bisher (Raum = Szene). Preis-Balance gegen die Ökonomie-Wächter.
- **Beweis:** Unit-Wächter: Kauf transaktional (rot-vor-grün nach dem Ranch-Kauf-
  Bug-Muster!), Portal-Zellen blockiert, Grid je neuem Raum valide, Orientierungs-
  Audit über die neuen Szenen (0 Befunde); Playtest-Flow `flow_home_ausbau`: Keller
  kaufen → Bau-Overlay → runtergehen → Möbel platzieren → Balkon-Wetter-Screenshot,
  quer + hochkant.

## 12. Kochen mit Gooby — die Küche wird zur Bühne [L]

- **Was:** 8–10 Rezepte (Pfannkuchen, Möhrensuppe, Obstsalat, Kekse …) aus
  Garten-Ernte + REHWEI-Zutaten, zubereitet in 2–3 taktilen Mini-Schritten am Herd
  (rühren = Kreis-Geste, wenden = Timing-Tap, schnippeln = Wisch-Rhythmus — die
  McGooby-Stationen-Interaktionen liefern das erprobte Muster). Gooby hilft, nascht
  zwischendurch (erwischen = Kicher-Moment), gekochte Gerichte sind bessere Speisen
  (mehr Sättigung/Fun als Rohzutaten) und können Lieblingsessen werden; Mehl-Unfall-
  Event bekommt rückwirkend Sinn („Ich wollte dir Pfannkuchen machen“).
- **Warum:** Größte inhaltliche Lücke im Speisen-Loop (verifiziert: kein Kochen im
  Code; Ernte hat nur Markt/Füttern als Senke). Verbindet Garten → Küche → Füttern
  zu einer Kette („wie EIN Spiel“), und taktile ASMR-Interaktionen sind beim User
  nachweislich beliebt (Kisten-Drag-ASMR, Patty-Wenden — beides gefeiert).
- **Wie (Skizze):** `scripts/home/kochen/` (Rezept-Katalog JSON im Pack-Format,
  `kochen_logic.gd` PURE: Zutaten-Check/Verbrauch/Ergebnis; `kochen_regie.gd` für
  die Schritt-Inszenierung nach FuetterRegie-Muster), Herd/Küchenzeile als
  Interactable, neue Speise-Ids additiv in `food_catalog.gd` + GLB-Vorschauen
  (Kenney-Food-Assets größtenteils vorhanden), Erinnerungs-/Gesprächs-Anbindung
  („Wir haben zusammen gekocht!“). Save: `inventory.food` reicht; optional
  `kochen.gelernt` für Rezept-Freischaltung über REHWEI-Rezeptkarten.
- **Risiko:** Hoch: Balancing gegen Ökonomie/Sättigung (gekocht darf Füttern nicht
  trivialisieren — Junk-/Gewichts-Logik respektieren); Gesten-Minigames brauchen
  echte InputEvent-Tests (Muster existiert: Kisten-Drag wurde mit echten
  InputEventMouse getestet); Scope-Falle Rezept-Flut — hart bei ~10 deckeln.
- **Beweis:** Unit-Wächter: Rezept-Transaktion atomar (Zutaten weg ⇔ Gericht da),
  Stat-Werte in Bandbreiten, Web-Stat-Keys unverändert; Bot-Zertifizierung der
  Gesten-Schritte auf geteiltem GoobyRng-Strom (McGooby-Muster); Playtest-Flow
  `flow_home_kochen`: ernten → kochen (alle Gesten) → füttern → Video.

## 13. Gooby träumt — kleine Traum-Vignetten beim Schlafen [L]

- **Was:** Schläft Gooby, zeigt gelegentlich (max. 1×/Nacht, nur wenn der Spieler
  zuschaut) eine Gedankenblase eine 10–15-s-Traum-Vignette: weichgezeichnete
  Mini-Szene aus einer ECHTEN Erinnerung (Urlaubsziel, Rekord-Spiel, Herbert,
  Lieblingsessen als Riesen-Möhre) mit Traum-Logik-Gags (Gooby fliegt, die Möhre
  spricht Gebrabbel rückwärts). Alpträume gibt es nur nach Gewitter-Tagen — sanft,
  mit Zudeck-Trost-Interaktion.
- **Warum:** Kombiniert die zwei stärksten User-Themen — Seele (Erinnerungen) und
  Liebe zum Detail — an einem Ort, der heute tot ist: Zuschauen beim Schlafen hat
  null Inhalt. Belohnt genau das ACNH-Verhalten „einfach mal hinsehen“ (Dopamin
  ohne Grind).
- **Wie (Skizze):** `scripts/home/sleep/traum_regie.gd` (Vignetten als
  SubViewport-Bühne in der Gedankenblase — GOB.TY-`tv_stage.gd` liefert das
  SubViewport-Muster; Kandidaten-Wahl deterministisch aus `SoulMemories.candidates`
  + Tages-Seed), 5–6 Vignetten-Setups aus vorhandenen Assets/Posen, Save additiv
  (`soul.traumGesehenAt` für die Frequenzbremse). Reduced Motion: Standbild-Blase.
- **Risiko:** Mittel–hoch: SubViewport-Kosten auf iPhone (nur rendern, wenn Blase
  sichtbar; llvmpipe-Perf-Wächter nach dem W19-Budget-Muster); Scope-Falle
  Vignetten-Anzahl (bei 5–6 deckeln, Rest als Pack-Nachschub); nachts-Fenster
  respektiert die Uhr deterministisch.
- **Beweis:** Unit-Wächter: Traum-Wahl deterministisch + Frequenzbremse, keine
  Vignette ohne echte Erinnerungs-Grundlage; Playtest-Flow `flow_home_traum`:
  Einschlafen erzwingen (Dev-Zeit) → Blase erscheint → Video der Vignette; Perf-Probe
  Frame-Budget mit/ohne Blase.

---

## Bewusst NICHT vorgeschlagen

- **Dynamic Island / Widgets / alles mit nativen Extensions** — dokumentiert
  zurückgestellt (UserFeedback `[-]`, Sideload-Grenze).
- **Echte Push-Events bei geschlossener App** — natives Notification-Plugin fehlt
  (STATUS.md „Bekannte Lücken“); alle Ideen oben funktionieren rein In-App.
- **PhysicalBone-Ragdoll** — F §5 nennt Fake-Tumble als 90 %-Lösung; Tuning-Risiko
  auf iPhone zu hoch für den Mehrwert.

# Bereich: Stadt + Orte + Reise

# Planner-Welle — Bereich: Stadt + Orte + Reise

Stand: W19, Branch `cursor/gooby-godot-loop-d1d8`. Quellen: UserFeedback.md (komplett),
docs/godot-rewrite/STATUS.md, E-city.md, GODOT-PLAN.md §6/E, Code-Stichproben
`GOOBY-GODOT/scripts/city/**` (orte/, travel/, urlaub/, delivery/, phone/, ambience/, markt/).

## Ehrliches Ist-Bild (damit niemand Doppeltes plant)

**Existiert und ist solide:** 15×12-Stadt mit Distrikten (`city_map.json`), Tagesrhythmus
(`city_rhythmus.gd`, injizierte Uhr), Ampel-Loop-Verkehr (`city_verkehr.gd`), Fußgänger,
Licht/Grün/Kulisse; 12 betretbare Orte + Raumstation (über space-Urlaub); Ambient-Leben in
ALLEN Orten (`ambience/ort_leben.gd`) + 5 benannte Stammkunden (`stammkunden.gd`, W18/J3);
GOOBERANDO-Vollausbau mit 3 Restaurants, Warenkorb und deterministischer Fahrer-Sim auf dem
road_graph (`delivery/fahrer_sim.gd` — aber nur als Punkt auf der App-Minikarte!); Taxi +
Guber inkl. Surge-Gag; Urlaub komplett (9 Ziele, Besuchs-Szenen mit Aktivitäten, Postkarten,
souvenirCoins, GOOBY-FREE-24h-Fenster, Erholungs-Boost, Heimkehr-Moment seit W19); Fotomodus
mit Werkzeugen (Pose/Emotion/Rahmen) + Selfie; InstantGooby-Feed; Minimap-Kachel im Fahr-HUD;
Parken (Pad-Fix W18). **InstantGooby/Snap und „GOOBERANDO mehrere Restaurants" sind KEINE
offenen Backlog-Punkte mehr — W13B/C hat sie geliefert** (STATUS.md ist dort älter als der Code).

**Dokumentiert offen / dünn:** Vollbild-Stadtkarte + Ziel-GPS-Pfeil (GODOT-PLAN §6 Z. 592),
Fahrer-Van-Sichtung in der 3D-Stadt (E-city §5.2, wörtlich designt, nie gebaut),
Wander-Agenten-Traffic + Ambient-Audio-Distrikte (Z. 597 / E §1.5), Guber-Cutscene-Fahrzeug
(Z. 593), Hupe-Knopf (E §1.4). Gefühls-Lücken: Ort-Betreten ist ein Sofort-Wipe (kein
Ankommens-Moment), Autohaus/Post sind Kauf-einmal-Orte ohne Rückkehr-Anlass, die Stadt kennt
außer Samstag-Markt keine Wochen-Anlässe, und die Stadt weiß nichts von Goobys Urlaub.

---

## 1. Vollbild-Stadtkarte + Ziel-GPS-Pfeil [M]

- **Was:** Tap auf die Minimap-Kachel öffnet eine Vollbild-Stadtkarte (alle Ort-Pins mit
  Offen/Zu-Status, „Dahin!"-Knopf). Danach führt ein 3D-Pfeil überm Auto plus dezente
  Breadcrumb-Punkte auf der Straße den A\*-Weg zum Ziel; abschaltbar in den Einstellungen.
- **Warum:** Wörtlich dokumentierte Restlücke: GODOT-PLAN §6 Z. 592 „Ziel-GPS-Pfeil und
  Vollbild-Karte fehlen" (E-city §1.3). Die 15×12-Stadt ist bewusst groß — neue Spieler
  verfahren sich; die Ranch hat seit W19 ihre Entdecker-Karte, die Stadt zieht mit fertigem
  Muster nach. UserFeedback-Geschmack: nichts darf sich wie eine Dev-Demo anfühlen — dazu
  gehört, dass man die Stadt souverän navigiert.
- **Wie (Skizze):** Neues `city/ui/stadtkarte_sheet.gd` (PanelSheet, Muster
  Ranch-Entdecker-Karte); Pins aus `OrtKatalog`/`CityMap` (eine Quelle der Wahrheit,
  Katalog-Drift-Regel E §8.5); Offen-Status über `OrtKatalog.ist_offen_an()` mit injizierter
  Uhr (`GameState.clock`). „Dahin!" setzt additiv `city.gps_ziel` (CityState-Slice); ein
  eigener Baustein `city/ui/gps_pfeil.gd` liest `CityRoadGraph.pfad()` (pur) und rendert
  Pfeil + Breadcrumbs.
- **Risiko:** `drive_hud.gd`/`city_scene.gd` sind geteilte Hotspots vieler Wellen — Pfeil als
  eigener Baustein andocken. CanvasLayer-Falle (W19-Funde: Karten rutschten unters HUD →
  Layer-40-Regel); Karten-Pin-Resize-Race (W19-Fund der Ranch-Karte) als Wächter übernehmen;
  Sheet reiht sich beim Overlay-Dirigenten ein.
- **Beweis:** Wächter `test_city_stadtkarte`: Pins == `betretbare_ids()`, GPS-Pfad
  deterministisch, Pin-Positionen nach Resize stabil (rot-vor-grün). Playtest-Flow
  `flow_stadtkarte_gps`: Karte öffnen → REHWEI-Pin → „Dahin!" → Pfeil sichtbar → ankommen →
  Pfeil erlischt; quer + hochkant.

## 2. GOOBERANDO-Fahrer-Sichtung in der 3D-Stadt [M]

- **Was:** Läuft eine Bestellung, fährt der orange delivery-Van WIRKLICH durch die Stadt —
  an exakt der deterministischen Position der Fahrer-Sim. Man kann dem eigenen Essen
  entgegenfahren; beim Vorbeifahren hupt der Van freundlich, einmaliger Sichtungs-Spruch.
- **Warum:** E-city §5.2 wörtlich: „Fährt der Spieler selbst durch die Stadt, spawnt
  zusätzlich ein echter car-kit/delivery-Van an derselben Graph-Position (Sichtung des
  eigenen Essens = Highlight!)" — designt, nie gebaut (heute nur Punkt auf der App-Karte).
  Genau der „Systeme greifen ineinander"-Moment gegen das „einzelne Spiele statt EIN
  Gooby-Spiel"-Gefühl (UserFeedback 1.8.).
- **Wie (Skizze):** Neuer Baustein `city/delivery/van_sichtung.gd`: liest den
  GooberandoLogic-Slice (`bestelltAt`/`fertigAt`/`restaurantId` — alles Timestamps im Save)
  und stellt `kenney delivery.glb` auf `GooberandoFahrerSim.status(route, …, now_ms)` —
  Position ist bereits eine reine Funktion der injizierten Uhr, null neuer Zufall. Save nur
  additiv: `city.flags.van_gesehen` (Erste-Male-Spruch). Hup-Sample = vorhandenes
  `city_hupe`.
- **Risiko:** `city_scene.gd` ist 733 Zeilen (max-file-lines!) — zwingend eigener Baustein.
  Van ohne harten Collider bzw. mit 70-%-Forgiving-Hitbox wie Traffic (kein neues
  Verkeil-Risiko); Performance minimal (1 Mesh, kein MultiMesh nötig).
- **Beweis:** Unit-Wächter: gleiche `now_ms` ⇒ Van-Transform == `fahrer_sim.status()`-Punkt
  (bit-deterministisch), kein Van bei `state == idle`. Flow: bestellen → selbst losfahren →
  Begegnungs-Screenshot → daheim Übergabe + Trinkgeld (Anschluss an bestehende
  GOOBERANDO-Wächter).

## 3. Post-Botengänge: „Bringst du das rüber?" [M]

- **Was:** Die Postbotin vergibt 1 deterministischen Tages-Botengang: ein Päckchen zu einem
  benannten Stammkunden bringen — z. B. „Für Frau Rosine, die ist vormittags bei REHWEI".
  Abgabe nur, wenn die Figur wirklich anwesend ist (ihr Stunden-Fenster!). Belohnung Münzen,
  Sammelzähler, selten Sticker.
- **Warum:** „Anlässe zurückzukommen": Die Post ist nach dem Briefkasten-Check auserzählt,
  und die J3-Stammkunden sind bisher reine Deko — hier bekommen sie Funktion und man lernt
  ihre Tagesroutinen als SPIELWISSEN. Zahlt direkt auf „Orte sollen LEBEN" und den
  ACNH-Dorf-Charakter der festen Karte (E §1.1 „Spieler sollen die Stadt AUSWENDIG lernen").
- **Wie (Skizze):** Pures `city/orte/botengang_logic.gd`: Auftrag = f(UTC-Tagesindex) über
  `Stammkunden.KATALOG` × Stunden-Fenster (Muster POW-Tagesangebote/Souvenir-Spot). Save
  additiv `city.botengang = {tag, zielId, status}`. Abgabe-Hook in `OrtLeben` (dort spawnen
  die Stammkunden; Anwesenheit über die injizierte Stunde, `stunde_override` existiert).
  Strings DE führend + EN-Parität.
- **Risiko:** Ort-Szenen sind geteilte Dateien (OrtLeben läuft in allen 12 Orten) — Hook als
  optionale Konfig, kein Fork. Zeitzonen-Falle (W16-Schnupfen-Bug!): UTC-Tagesindex wie beim
  Souvenir-Spot. Fairness: verpasstes Fenster lässt den Auftrag abends ehrlich verfallen,
  kein Streak, kein Malus.
- **Beweis:** Wächter: Determinismus (gleicher Tag ⇒ gleicher Auftrag), Fenster-Logik über
  injizierte Stunden, Abgabe bucht GENAU einmal (Transaktions-Muster der W13-Kauf-Fixes).
  Flow: Post → Auftrag annehmen → Zeit-Override auf 10 Uhr → REHWEI → Übergabe-Karte.

## 4. Hupe! [S]

- **Was:** Kleiner HONK-Knopf im Fahr-HUD: Fußgänger-Goobys hüpfen erschrocken bzw. winken,
  Ambient-Autos hupen zurück. Reiner Charme.
- **Warum:** E-city §1.4 wörtlich designt („Reiner Charme, 20 Zeilen") und nie gebaut — nur
  die Near-Miss-Hupe existiert. Billigster „Liebe zum Detail"-Punkt des Bereichs
  (UserFeedback: „…ohne Liebe zum Detail" war die Kern-Kritik).
- **Wie (Skizze):** Knopf in `drive_hud.gd` (Daumenzone) → Signal; Hüpf-Reaktion im Radius in
  `city_fussgaenger.gd` (reine Tween-Zahlen, pur testbar); Sound = vorhandenes
  `city_hupe`-Sample über die Audio-Grammatik; Cooldown ~1,5 s gegen Spam. Kein Save-Feld,
  kein Zufall.
- **Risiko:** HUD-Knopfdichte hochkant (44-pt-Tippflächen, UI-Wache 4 Formate);
  Reduced-Motion = Winken statt Hüpfen.
- **Beweis:** Unit: Reaktions-Radius + Cooldown pur. Flow: neben Fußgänger hupen →
  Hüpf-Screenshot; UI-Wache bleibt 0 Befunde.

## 5. „Na, wieder da?" — die Stadt reagiert auf die Heimkehr [S]

- **Was:** 24–48 h nach einer Urlaubs-Heimkehr erwähnen Stammkunden und Ort-NPCs das
  Reiseziel namentlich („Wie war's am Glitzermeer? Rollo will da auch mal hin!"); der
  Flughafen-Schalter gratuliert zum n-ten Stempel.
- **Warum:** Die W19-Heimkehr-Momente enden an der Haustür — die Stadt weiß nichts davon.
  ACNH-Wärme heißt: die Welt erinnert sich. Verstärkt den dokumentierten „Urlaub braucht
  NUTZEN/Echo"-Faden (E-city §3.3) mit reinen Strings + einer Bedingung.
- **Wie (Skizze):** Pure Bedingung über die VORHANDENEN vacation-Latches
  (`heimkehrAt`/`heimkehrZiel` aus `heimkehr_logik.gd`) + injizierte Uhr — kein neues
  Save-Feld (Fenster = `now − heimkehrAt < 48 h`). `OrtLeben`-Spruchauswahl bekommt eine
  Kontext-Domain (`stammkunde_<id>.heimkehr.<ziel>` mit generischem Fallback); Zielname aus
  `travel.ziel.*`.
- **Risiko:** Spruch-Takt nicht spammen (dezenter `STAMM_SPRUCH_ALLE_S`-Takt bleibt Owner);
  DE/EN-Paritäts-Gate (String-Parität läuft ohnehin über alles).
- **Beweis:** Unit: Fenster-/Fallback-Logik pur (kein Urlaub ⇒ normale Sprüche; Fenster zu ⇒
  normale Sprüche). Flow-Erweiterung von `flow_w19_heimkehr`: nach der Übergabe-Karte in
  REHWEI den Heimkehr-Spruch fangen.

## 6. Guber fühlt sich endlich premium [S]

- **Was:** Guber bekommt sein dokumentiertes eigenes Fahrzeug (schwarzer `sedan-sports`) in
  der Fahrt-Sequenz plus 2–3 vornehme Fahrer-Zeilen („Stilles Wasser oder … stilles
  Wasser?"). Das Taxi bleibt gelb.
- **Warum:** GODOT-PLAN §6 Z. 593 nennt „Surge-Gag + eigenes Cutscene-Fahrzeug
  (sedan-sports) fehlen" — der Surge-Gag ist inzwischen da (`fahrdienst.gd`), das Fahrzeug
  nicht. Ein teurerer Dienst, der identisch aussieht, ist exakt das Dev-Demo-Gefühl, das der
  User nicht will.
- **Wie (Skizze):** Fahrzeug-Mesh als Parameter der Fahr-Sequenz (Dienst-Id → CarDef/GLB;
  `sedan-sports` liegt im car-kit), Karosserie-Tint schwarz; Fahrer-Zeilen in
  `phone.guber.*` DE+EN. Kein Save-Feld.
- **Risiko:** Die Fahrt-/Reise-Sequenz (`reise_cutscene.gd`) wird von Taxi/Urlaub geteilt —
  Fahrzeugwahl strikt als Parameter, Timing-Goldens unangetastet.
- **Beweis:** Unit: `fahrzeug_fuer(dienst)` pur (taxi ⇒ taxi.glb, guber ⇒ sedan-sports).
  Flow: Guber rufen (Dev-Zeit-Override für Surge-Fenster gleich mit) → Screenshot schwarzer
  Wagen + Surge-Zeile.

## 7. Stadt-Wochenanlässe: „Was ist heute los?" [M]

- **Was:** 3–4 wiederkehrende Wochentags-Anlässe machen jeden Stadtbesuch anders: Mittwoch
  Eiswagen am Funkelpark-Tor, Freitag Foodtruck an der Brunnen-Plaza, Sonntag
  Straßenmusiker-Gooby; Samstag bleibt der Markt. Ein dezenter Chip „Heute: Eiswagen 🍦"
  beim Stadt-Betreten (und auf der Stadtkarte aus Idee 1).
- **Warum:** Auftrag „Tages-/Wochen-Anlässe + Anlässe zurückzukommen". Der
  Wochenmarkt-Samstag beweist seit W18, dass Wochen-Rhythmus trägt (er wurde erst durch den
  Öffnungszeiten-Fix erlebbar) — aber er ist der EINZIGE Anlass. Ein Wochen-Kalender gibt der
  ohnehin injizierten Uhr Spielwert und macht die Stadt zum Dorf mit Gewohnheiten.
- **Wie (Skizze):** Pures `city/city_anlaesse.gd`: Wochentag → Anlass (Muster
  `CityRhythmus`, Uhr injiziert); Requisiten (Eiswagen = car-kit-Van + Schirm, Musiker =
  Gooby-Mesh + Noten-Partikel) über das `ort_requisiten`-Muster als reine Uhr-Funktion in
  einem eigenen Kulissen-Baustein; Mini-Interaktion (Eis kaufen = FoodCatalog-Id, Economy
  additiv). Save nur `city.anlass_gesehen.<key>`-Latch für den Erste-Male-Spruch.
- **Risiko:** `city_scene.gd`/`city_kulisse.gd` sind geteilt → eigener Baustein;
  Draw-Call-Budget der Stadt (1–2 Props je Anlass, weit unter Budget); Öffnungs-
  Prompt-Verträge (GOOBY-FREE/„geschlossen") nicht anfassen.
- **Beweis:** Unit: Kalender-Mapping über alle 7 Wochentage pur, Kauf-Transaktion. Flow:
  Zeit-Override Mittwoch → Eiswagen da, Eis kaufen; Donnerstag → weg (rot-vor-grün auf das
  Verschwinden).

## 8. Foto-Aufträge: „Motiv des Tages" [M]

- **Was:** Die Kamera-App stellt täglich 1 deterministisches Motiv („Der Kreisverkehr bei
  Nacht", „Ein Stammkunde", „Dein Auto vorm Autohaus"). Erfüllt = Münzen + Motiv-Sammelleiste
  mit Sticker-Meilensteinen (10/25). Gibt dem Fotomodus einen Loop und Orten Foto-Gründe.
- **Warum:** POW-Kamera + Fotomodus-Werkzeuge sind „gekauft und vergessen" — es gibt keinen
  Grund, sie draußen zu benutzen. Verbindet Orte × Tageszeiten × Fahren zu einem
  Sammelziel; passt zur Erste-Male-Philosophie von E-city §2.1 und USER §E61 (Kamera von
  POW!).
- **Wie (Skizze):** Pures `city/phone/foto_auftrag.gd`: Motiv = f(UTC-Tagesindex) aus einem
  Katalog; Erfüllungs-Prüfung über die VORHANDENEN Foto-Metadaten (`FotoWerkzeuge`
  schreibt Metadaten; additiv erweitern um Szene/Ort-Id + Tagesphase aus
  `CityRhythmus.phase(injizierte Uhr)`) — bewusst KEINE Pixel-Analyse. Save additiv
  `city.fotoAuftrag = {tag, erledigt}` + Gesamtzähler.
- **Risiko:** Metadaten-Vertrag mit Galerie/Album (Galerie bleibt Owner, Schema nur additiv —
  Alt-Fotos ohne Felder zählen ehrlich nicht); Motiv-Katalog muss ohne GPU prüfbar bleiben
  (Metadaten-Matcher, auf llvmpipe voll testbar — der Bildinhalt selbst wird nicht
  behauptet).
- **Beweis:** Unit: Determinismus + Matcher rot-vor-grün (falsche Tagesphase/falscher Ort ⇒
  nicht erfüllt). Flow: Auftrag lesen → Ort anfahren → Foto schießen → „Erledigt!"-Beat +
  Münzflug.

## 9. Klang-Distrikte + Ortsschild-Chips [M]

- **Was:** Die Distrikte (Zentrum/Gewerbe/Wohnen/Park/Flughafen-Zubringer) bekommen eigene
  Ambient-Betten mit weichem Crossfade beim Überfahren der Grenze, plus einen 2-s-Chip
  („Wohnviertel") beim Einfahren. Nachts dämpft der Tagesrhythmus die Betten.
- **Warum:** Dokumentiert: E-city §1.5 „Ambient-Audio: Distrikt-Crossfade" + GODOT-PLAN §6
  Z. 597 (M3 „Ambient-Audio-Distrikte"). W18 hat Klangbetten für die ORTE etabliert — die
  Stadt selbst klingt überall gleich. Hörbare Distrikt-Identität macht die 15×12-Karte
  größer, ohne ein Polygon zu ändern.
- **Wie (Skizze):** `city/ambience/distrikt_klang.gd`: Distrikt = f(Tile) aus dem
  VORHANDENEN `distrikte`-Block der `city_map.json`; 4 kurze CC0-Loops nach dem
  W18-Synthese-Muster; Crossfade-Kurve als pure Zahlenfunktion; Chip über den vorhandenen
  Toast-/Banner-Baustein. Kein Save-Feld; Tageszeit-Dämpfung über `CityRhythmus`
  (injizierte Uhr).
- **Risiko:** Ducking-Vertrag (Gooby-Sprache duckt Betten — W18-Regel übernehmen); maximal
  2 aktive AudioStreamPlayer beim Crossfade (iPhone-Audio-Budget); Chip darf HUD/Overlays
  nicht überlagern (Anker-Zonen-Regel W14).
- **Beweis:** Unit: Tile→Distrikt-Mapping (jede Straßenzelle genau 1 Distrikt) +
  Crossfade-Kurve pur. Flow: Fahrt Zentrum→Wohnviertel mit Audio-Log-Wächter — aktives Bett
  wechselt genau einmal, Chip erscheint genau einmal.

## 10. Auto-Liebe: Staub + Blechberts Waschstraße [M]

- **Was:** Das eigene Auto wird über gefahrene Strecke dezent staubig (ein
  Material-Parameter); beim Autohaus eröffnet Blechberts Waschstraße (8 Münzen): kurze
  ASMR-Schaum-Sequenz, danach glänzt der Lack und Gooby bekommt 1 Tag lang einen „Frisch
  gewaschen!"-Spruch.
- **Warum:** Autohaus ist ein Kauf-einmal-Ort ohne Rückkehr-Anlass, dabei ist Fahren DIE
  Kernbewegung der Stadt. Ein sichtbarer Pflege-Loop ist purer „Liebe zum Detail"-Geschmack
  (UserFeedback-Kernkritik) und macht die Auto-Identität (CarDefs, Farbwahl) fühlbar.
- **Wie (Skizze):** Save additiv `city.autos.<id>.staub_m` (Meter-Akkumulator im
  car_controller-Schritt — reine Addition, deterministisch aus Bewegung, keine OS-Zeit);
  Staub-Intensität = clamp(m/Schwelle). Waschstraße als `ort_requisiten`-Ausbau in
  `autohaus.gd` + Sheet-Knopf; Sequenz = Tweens + Partikel, Reduced-Motion = harter Schnitt.
  Wasch-Buchung transaktional (erst prüfen, dann buchen — W13-Kauf-Bug-Muster).
- **Risiko:** Auto-Meshes/CarDefs sind mit den Fahr-Minispielen geteilt (§G-Contract!) —
  Staub-Tint NUR in der Stadt-Instanz anwenden, Minispiel-Goldens bleiben bit-gleich;
  Shader-Kosten = 1 Parameter auf bestehendem Material (llvmpipe-unkritisch).
- **Beweis:** Unit: Staub-Kurve pur; Wasch-Transaktion rot-vor-grün (Pleite ⇒ kein Abzug,
  kein Reset). Flow: 2 Runden fahren → Staubwert steigt → waschen → Vorher/Nachher-
  Screenshots + Save-Beweis.

## 11. Ankommen inszeniert: Einparken + Aussteigen [L]

- **Was:** Ort betreten wird ein Mikro-Moment statt Sofort-Wipe: das Auto gleitet sichtbar
  aufs Park-Pad, Gooby steigt aus (Tür-Klack) und tapst zur Ladentür — DANN der Wipe.
  Rückweg spiegelverkehrt (das Auto steht ja laut Save noch am Pad). Tap = Skip;
  Reduced-Motion = heutiges Verhalten.
- **Warum:** DER „EIN-Spiel"-Hebel des Bereichs: UserFeedback 1.8. nennt Übergänge explizit
  als Grund für das „einzelne Spiele statt EIN Gooby-Spiel"-Gefühl, und W15 hat es fürs Haus
  vorgemacht („Kamera fährt DURCH die Tür"). Orte, an denen man ANKOMMT, fühlen sich wie
  Orte an — nicht wie Menüs.
- **Wie (Skizze):** `city/ort_ankunft.gd` als Sequenz-Baustein VOR `SceneRouter.goto`
  (Muster `reise_cutscene.gd`: AnimationPlayer/Tweens, deterministisch, skippbar);
  Pad-Position aus dem `parken`-Block der `city_map.json` (existiert, W18-Collider-Fix);
  der Energie-/Geschlossen-Prompt-Vertrag bleibt unangetastet VOR der Sequenz. Kein
  Save-Feld.
- **Risiko:** Router-Vertrag ist der heikelste des Bereichs (W19-Fund: `_busy`-Guard
  schluckte Taps) — die Sequenz muss den Router genau einmal reservieren/freigeben,
  rot-vor-grün gegen Doppel-goto. 12 Ort-Eingänge = geteilte Daten, KEIN Szenen-Fork.
  Bestehende Ort-Flows erwarten Sofort-Routing → Skip-Pfad im Harness. iPhone: nichts Neues
  wird geladen, nur Kamera + Tweens.
- **Beweis:** Wächter: Sequenz-Timing pur + Genau-einmal-Routing + Skip springt bit-gleich
  in den Endzustand. Alle bestehenden Ort-/Stadt-Flows als Regressionsnetz; neuer Flow
  quer + hochkant inkl. Skip-Pfad und Rückweg.

## 12. Raumstation GOOB-1, Welle B: der Weltraumspaziergang [L]

- **Was:** Die Station bekommt einen zweiten Raum: Luftschleuse → EVA-Pfad außen am Rumpf
  (Magnet-Schuhe = langsames Tap-to-Move, die Erde zieht im Panorama vorbei), ein
  Erd-Teleskop mit täglicher deterministischer Sichtung („Heute gut zu sehen: die Ranch!")
  und ein Sternenstaub-Souvenir; der Stations-Gooby vergibt eine kleine
  Checklisten-Aufgabe.
- **Warum:** Der Auftrag nennt den Raumstations-Ausbau explizit; die Station ist heute ein
  1-Raum-Ort (2 Arcade-Terminals, Snack-Automat, Foto-Spot) und damit dünner als ihr
  Auftritt als space-Reiseziel. Die Teleskop-Sichtung ist ein täglicher Rückkehr-Anlass für
  das teuerste Reiseziel — Urlaubs-Nutzen-Faden aus E-city §3.3 weitergesponnen.
- **Wie (Skizze):** `raumstation.gd` erweitert (Raum 2 als Kind-Szene, Route unverändert);
  Sichtung = f(UTC-Tagesindex) pur (Muster POW-Tagesangebote); Souvenir über den
  vorhandenen Souvenir-Spot-Pfad (`UrlaubsAktivitaeten`, inventory additiv); Low-G-Hop-
  Parameter wiederverwenden. Save additiv `vacation.goob1 = {sichtungTag, checkliste}`.
- **Risiko:** `raumstation.gd` enthält den Arcade-Routen-Trick (temporäre
  `register_route`-Umleitung!) — die Raum-2-Navigation darf den Rückweg-Vertrag nicht
  brechen (eigener Wächter). Sternen-Sky-Shader-Zweitinstanz auf iPhone prüfen; das
  EVA-Panorama ist auf llvmpipe nur strukturell prüfbar — visuelle Abnahme ehrlich als
  offen deklarieren.
- **Beweis:** Unit: Sichtungs-Determinismus, Checklisten-Zustand, Route-Restore-Wächter
  (rot-vor-grün: Terminal-Start aus Raum 2 → zurück in die Station, nie in die Arcade).
  Flow: space-Fixture → Station → EVA → Teleskop → Souvenir → Rückflug.

## 13. Traffic 2.0: Wander-Agenten statt Loops [L]

- **Was:** Der Ambient-Verkehr fährt frei auf dem `road_graph` — an jeder Kreuzung eine
  erlaubte Zufalls-Abbiegung (Rechtsverkehr, Spur-Offset), Menge folgt der
  Tagesrhythmus-Kurve; die geauthorten `traffic_loops` entfallen. Dazu 2–3 Ziel-Routen für
  Fußgänger (der Zeitungs-Gooby geht morgens WIRKLICH zur Post).
- **Warum:** Doppelt dokumentiert: E-city §1.5 (Design „Wander-Agenten … null
  Loop-Authoring") + GODOT-PLAN §6 Z. 597 („Traffic-Vollausbau"). Autos, die erkennbar im
  Kreis fahren, sind das größte verbliebene Dev-Demo-Signal der Stadt; erst Wander-Verkehr
  macht Kreisel und Straßen-Lattice als Layout erlebbar.
- **Wie (Skizze):** Pures `city/traffic/wander_agent.gd` mit Schrittfunktion (Knoten,
  seeded GoobyRng-Strom, Ampel-/Abstands-Regeln aus `CityVerkehr` wiederverwendet) —
  Position = f(Seed, Zeitschritte), damit headless beweisbar. `city_scene` tauscht die
  Loop-Follower gegen Agenten; Menge aus `CityRhythmus` (injizierte Uhr). Kein Save-Feld
  (Ambient). Near-Miss-/Hupen-Verträge (70-%-Hitbox) ziehen mit um.
- **Risiko:** Größtes Perf-Risiko des Bereichs (llvmpipe-CI UND iPhone): Agenten-Zahl
  gedeckelt wie heute (3–9 je Tageszeit), gebündelter Schritt ohne Physik-Bodys,
  Perf-Wächter nach dem W19-Ranch-Budget-Muster. RNG-Verbrauchs-Drift kann Goldens
  benachbarter Systeme treffen → eigener RNG-Strom mit eigenem Salz. Geteilte Datei
  `city_scene.gd` → Umbau als Baustein-Tausch.
- **Beweis:** Unit: Schrittfunktions-Invarianten über 10k Schritte (nie Geisterfahrer, nie
  Rot-Durchfahrt, Mindestabstand hält), Determinismus (Seed ⇒ identische Trajektorie);
  Perf-Wächter (Frame-Budget); Flow: 2-Minuten-Stadtfahrt ohne Anomalie, quer + hochkant,
  Near-Miss-Funken feuern weiterhin.

---

## Prioritäts-Begründung (ehrlich)

1–3 zuerst: die Stadtkarte ist die dokumentierte Nutzbarkeits-Lücke der großen Karte, die
Van-Sichtung ist das am längsten designte „Systeme-greifen-ineinander"-Highlight mit fast
fertiger Logik, und die Botengänge geben den W18-Stammkunden endlich Spielfunktion — alle
drei headless voll beweisbar. 4–6 sind die billigen Liebe-zum-Detail-Gewinne (zwei davon
wörtlich dokumentierte Rest-Lücken). 7–10 bauen Rückkehr-Anlässe und Sinnes-Identität aus.
11–13 sind die großen Gefühls-/Struktur-Brocken: 11 attackiert das Dev-Demo-Gefühl am
Übergang selbst (aber am Router-Vertrag = vorsichtig), 12 und 13 sind lohnende, aber
invasive Ausbauten (Routen-Trick bzw. Perf-Risiko). Bewusst NICHT dabei: Live Activities /
signierte iOS-Extensions (dokumentiert zurückgestellt, Sideload kann das nicht).

# Bereich: Minispiele + Arcade

# GOOBY Ideen-Planner — Bereich Minispiele + Arcade (W19, Welle I)

Ist-Bild-Quellen (komplett gelesen): `UserFeedback.md`, `docs/godot-rewrite/G-minigames.md`,
`docs/godot-rewrite/EVAL-DOPAMIN-SOUND-FEEL.md`; Code-Stichproben:
`GOOBY-GODOT/scripts/minigames/` (Host 996 Z., `minigame_award.gd` als DER eine
Payout-Pfad, `arcade_spotlight.gd`, `geist_rekord.gd`, `modifier_engine.gd`,
`arcade_screen.gd`, `results.gd`, `pregame.gd`, `minigame_registry.gd`),
`content/stickers/data/stickers.json` (144 Sticker, Seite `arcadeStars` nur 6),
`content/quests/data/quests.json` (Quest-Typen `spiel_punkte`/`spiele_gesamt`/
`spiele_verschieden` existieren), `GOOBY-SERVER/src/` (friends/gobnommp/gvzmp/
boardgames — KEIN Geist-/Score-Modul), `tests/expected/*.json` (Web-Paritäts-
Goldens), `scripts/audio/music_registry.gd` (nur 7 `game:`-Kontexte für 38 Spiele).

**Was ist dünn (ehrliche Diagnose):**

1. **Wiederkommen-Anlässe:** Es gibt genau EINEN Tagesanker (Spotlight +50 %,
   W19) und einen Selbst-Vergleich (Geist, lokal). Kein Wochen-Rhythmus, kein
   sozialer Vergleich, kein Streak. EVAL-Befund dazu wörtlich: „alles im
   Minigame-Results, fast nichts außerhalb" — zwischen den Runden gibt es
   keinen Grund, MORGEN wieder in die Arcade zu kommen.
2. **Meta-Fortschritt unsichtbar:** `legacy.best/bestByDiff/beaten` existieren
   im Save, aber die Arcade-Kachel zeigt NICHTS davon. 38 identische Kacheln =
   Wand statt Sammlung. Sticker-Seite `arcadeStars` hat nur 6 von 144 Stickern.
3. **Modifier-Engine feuert nur Einzel-Events** (6 Typen, 1 Paar, 45 min) —
   die Engine ist fertig gebaut, aber ihr Überraschungs-Potenzial (Kombis,
   seltene Momente) liegt brach.
4. **Framework-Qualität:** Der im Design-Doc §1.1 explizit angelegte
   „Ende-Screenshot fürs Results-Panel/Fotoalbum" (der SubViewport wurde u. a.
   DAFÜR gewählt) wurde nie gebaut. 30+ Spiele teilen einen Musik-Track
   (EVAL S9, nur teilweise abgearbeitet: 7 `game:`-Kontexte).
5. **Multiplayer-Lücke im Alltag:** GvZ-PvP/GOB-NOM-Coop brauchen zwei Geräte
   + Server. Es gibt KEIN Spiel für „Freund sitzt daneben auf dem Sofa".

Priorisierung: Spielerwert pro Aufwand, Wiederkommen-Anlässe zuerst.
Verteilung: **3× S, 6× M, 3× L** (12 Ideen).

---

## 1. Tages-Rätsel mit Streak-Kalender [M]

- **Was:** Jeden Tag EIN „Rätsel des Tages": deterministischer Tages-Seed auf
  eines der Puzzle-Spiele (Rotation über `pipeFlow`, `memoryMatch`,
  `purblePlace`, `goobySays`), EIN gewerteter Versuch pro Tag (danach frei
  üben, ungewertet), Streak-Zähler mit Kalender-Blatt in der Arcade
  („🔥 5 Tage in Folge!"), Meilenstein-Sticker bei 7/30 Tagen.
- **Warum:** Wordle-Prinzip = der stärkste bekannte Tages-Anker überhaupt, und
  er kostet KEIN neues Spiel. EVAL §1.2: AC liefert Belohnungen im
  60–90-s-Takt und große Anlässe alle 5–10 min — GOOBY fehlt der
  *kalendarische* Anlass. Der User bestellt seit W17 explizit
  Wiederkommen-Anlässe (UserFeedback „Welle I: 30+ Ideen-Planner …
  konsolidiert zur Roadmap" nach den Retention-Paketen Spotlight/Geist).
  Spotlight belohnt „irgendein Spiel spielen"; das Rätsel belohnt
  „JEDEN Tag da sein" — komplementär, nicht redundant.
- **Wie (Skizze):** Neue pure Klasse `arcade_tagesraetsel.gd` nach dem
  1:1-Vorbild `arcade_spotlight.gd` (Anker-Tag + `_mix`-Avalanche, Uhr IMMER
  injiziert als `Clock.local_day()`). Seed-Override läuft über den bereits
  existierenden `ctx.params`-Weg (`seed-Override (Tests)`, G-minigames §1.2) —
  der Host kann das schon, kein Host-Umbau. Save: additive v5-Keys
  `minigames.raetsel = {day, done, streak, bestStreak}` (Muster
  `spotlightBonusDay`, überlebt `merge_defaults`). Arcade: eigene Banner-Karte
  über dem Grid (Muster Spotlight-Puls-Rahmen). Auszahlung als fester
  Bonus über `Economy.award(reason "raetsel")` gegen ein eigenes Mini-Ledger —
  NICHT durch `MinigameAward.award()` fädeln, damit die Golden-Pfade
  unangetastet bleiben.
- **Risiko:** Die Puzzle-Logiken sind bit-zertifiziert
  (`tests/expected/pipeFlow.json` …) — der Tages-Seed darf nur ÜBER den
  vorhandenen Seed-Parameter injiziert werden, nie in die Logic-Dateien
  fassen. Ein-Versuch-Gate muss App-Kill-sicher sein (Marker VOR Rundenstart
  schreiben, Erstattung bei Abbruch nach Modifier-`refund`-Muster). Streak
  über Zeitzonen: dieselbe Mittags-Trick-Tagesnummer wie
  `ArcadeSpotlight._tag_nummer` verwenden.
- **Beweis:** Unit-Wächter: Determinismus (gleicher Tag ⇒ gleiches Spiel +
  Seed auf allen Geräten), Rotation nie 2× dasselbe Spiel nacheinander,
  Ein-Versuch-Gate inkl. Abbruch-Erstattung, Streak-Fortschreibung über
  Tages-/DST-Kanten. Dauerhafter Playtest-Flow `flow_raetsel_streak`
  (Muster `flow_w19_spotlight`, 2 simulierte Tage, quer + hochkant).
  Goldens + Leak-Gate 38/38 unverändert grün.

## 2. Arcade-Kacheln erzählen Fortschritt: Sterne, Kategorien-Reihen, Quest-Chips [S]

- **Was:** Das Arcade-Grid wird von „38 gleiche Kacheln" zu „meine Sammlung":
  (a) pro Kachel bis zu 3 Mini-Sterne aus VORHANDENEN Save-Daten (gespielt /
  Ziel geschlagen (`legacy.beaten`) / Endlos frei), (b) Kategorien-Reihen mit
  Überschrift statt einer Wand (Klassiker · Flink & Sportlich · Fahren ·
  Rätsel · Groß-Spiele · Ranch), (c) „Zuletzt gespielt"-Reihe oben, (d) ein
  Quest-Chip auf der Kachel, wenn eine offene Tages-Quest
  (`quests.json`-Typ `spiel_punkte`) genau dieses Spiel verlangt.
- **Warum:** UserFeedback (1.8., wörtlich): alles fühlt sich „wie einzelne
  Spiele statt EIN Gooby-Spiel an" — die Arcade ist der Ort, wo die 38 Spiele
  als EIN Besitz erlebbar werden. Die Daten existieren alle schon
  (`minigame_award.gd` schreibt best/beaten seit W1d; Tages-Quests
  referenzieren Spiele bereits) — es fehlt NUR die Sichtbarkeit. Der
  Quest-Chip beantwortet zudem täglich „was spiele ich heute?" mit einem
  zweiten Anlass neben dem Spotlight.
- **Wie (Skizze):** Ausschließlich `arcade_screen.gd` + eine neue pure
  Helferdatei `arcade_kachel_status.gd` (liest defensiv aus dem Save-Slice,
  Muster `GeistRekord.rekord_von`). Kategorie je Spiel als neues optionales
  Manifest-Feld `kategorie` in `games/<id>/game.json` (die Registry ist
  dafür GEBAUT: „Content-Packs können später Spiele nachliefern",
  `minigame_registry.gd` §W6) — fehlende Kategorie fällt auf „Klassiker"
  zurück. Badge-Overlay nach dem Muster `_add_modifier_badge`/
  `_add_spotlight_markierung` (MOUSE_FILTER_IGNORE, Kachel-Tap bleibt
  unberührt).
- **Risiko:** Klein und lokal — `arcade_screen.gd` ist KEINE geteilte
  Framework-Datei der 38 Spiele. Einzige echte Gefahren: Touch-Wisch-Scroll
  des Grids (W18-Fix „Buttons geben Drags ab Deadzone ab" nicht kaputt
  machen) und Hochkant-Umbruch der Kategorie-Reihen (UI-Wache 4 Formate).
- **Beweis:** UI-Wächter über beide Formate (Kacheln + Reihen-Header in der
  Inhaltsspalte, keine Überlappung mit Spotlight-/Modifier-Badges),
  Unit-Test der Stern-Ableitung aus Fixture-Saves (`v4_midgame.json`),
  bestehender Arcade-Playtest-Flow erweitert um „Quest-Chip sichtbar →
  Spiel starten → Chip weg nach Erfüllung".

## 3. Wochen-Challenge: „Diese Woche zählt nur DIESE Runde" [M]

- **Was:** Jede Kalenderwoche EINE feste Challenge, auf allen Geräten
  identisch: Spiel + Schwierigkeit + fester Seed + genau EIN Modifier
  (z. B. „KW 32: teaParty · Schwer · Turbo"). Beliebig viele Versuche, der
  beste zählt; Wochen-Karte in der Arcade zeigt persönliche Bestmarke +
  3 Belohnungsstufen (Bronze/Silber/Gold-Münzpakete + 1 Sticker bei Gold);
  Sonntag-Abend-Countdown „Noch 4 h!".
- **Warum:** Der Spotlight dreht täglich, aber eine Woche ist der natürliche
  Rhythmus für „ich verbessere MICH an derselben Aufgabe" — genau das
  Geist-Rekord-Gefühl (W19, „KEINE Produkt-Befunde" im Playtest, das Feature
  trägt), nur mit gemeinsamem Ziel statt eigener Kurve. Prüfung gegen
  Ist-Stand: Es gibt KEINEN Wochen-Anlass im ganzen Minispiel-Bereich
  (nur Ranch-`comp_liga` hat Ansätze, arcade-fremd). Feste Seeds machen
  Ergebnisse vergleichbar → Vorstufe für Freunde-Vergleich (Idee 4).
- **Wie (Skizze):** `arcade_wochenchallenge.gd` (pur): KW-Nummer aus der
  injizierten Uhr → deterministische Wahl aus Pool spielbarer Spiele ×
  freigeschalteter Modifier-Typen (Reihenfolge-stabil wie
  `ModifierEngine.eligible_pairs`). Start läuft als normaler Host-Launch mit
  `params = {mode: "wochenchallenge", seed: …, modifier: launch_params(…)}` —
  der Host kennt Modifier-Params schon (FERTIG-1-Pfad). Wochen-Bestwert als
  additiver Key `minigames.wochenChallenge = {week, best, stufe}`.
  Belohnungsstufen zahlen über `Economy.award(reason "wochenchallenge")`,
  NICHT über den Award-Pfad — `minigame_award.gd` bleibt byte-gleich.
- **Risiko:** Die Modifier-Engine hat einen PERSISTIERTEN Seed-Stream —
  die Challenge darf ihn NICHT anfassen (eigene Seed-Ableitung aus der
  KW-Nummer, kein `state.modifiers`-Zugriff). Score-Vergleichbarkeit setzt
  voraus, dass der feste Seed wirklich alle RNG-Züge des Spiels speist
  (bei den 30 zertifizierten Ports garantiert das GoobyRng-Design; GvZ/
  GOB NOM/Ranch-Spiele erst nach Einzelprüfung in den Pool). Kein
  Energie-Doppelabzug: Challenge-Runde = normale Runde, nur die Wertung
  ist zusätzlich.
- **Beweis:** Determinismus-Wächter (KW ⇒ identisches Tripel auf 2
  simulierten Geräten), Stufen-Vergabe-Wächter (rot-vor-grün: Gold ohne
  Score unmöglich), Golden-Suite + `test_mg3_*`-Nachbarn unverändert,
  Playtest-Flow: Challenge 2× spielen, zweiter besserer Lauf ersetzt
  Bestmarke, Stufen-Karte aktualisiert, Wochenwechsel setzt zurück.

## 4. Freunde-Geister: der Bestlauf deiner Freunde spielt mit [M]

- **Was:** Die W19-Geist-Kurve (≤ 1 KB JSON pro Spiel) wird über den Server
  mit Freunden geteilt: Im Pregame wählbar „Gegen wen? Mein Geist /
  <Freund>"; der Live-Chip zeigt dann ±Delta gegen den Freund-Bestlauf, die
  Results-Karte feiert „Du hast Lenas Geist geschlagen!" mit eigenem Beat.
  Offline/kein Server: Auswahl zeigt freundlich nur den eigenen Geist.
- **Warum:** Der Geist-Rekord ist gebaut und bewährt (W19-Playtest 45/45),
  aber rein solo. Der Server hat bereits Freunde (`friends.js`),
  Brettspiele und 3 MP-Module — es fehlt nur ein Mini-Modul für
  Score-Kurven. Asynchroner Wettbewerb ist der billigste soziale
  Wiederkommen-Anlass: kein Lockstep, keine Latenz, funktioniert mit
  1 Freund. Direkt anschlussfähig an Idee 3 (Wochen-Challenge-Geister).
- **Wie (Skizze):** Server: `geister.js` nach dem `mail.js`-Muster
  (Upload beim neuen Bestlauf: `{gameId, score, schritt_sec, dauer_sec,
  kurve}` mit Größen-Deckel MAX_STUETZEN=160 serverseitig validiert;
  Abruf: Kurven der Freundesliste pro Spiel, Quota wie Mail). Client:
  `GeistRekord` kann fremde Referenzen SCHON laden (`starte(referenz)` ist
  referenz-agnostisch, `ist_gueltig` validiert defensiv) — es braucht nur
  den Pregame-Picker + einen Sync-Service nach `presence.gd`-Muster
  (Outbox-tauglich, offline-first). Chip-Farbe unterscheidet eigenen
  (violett) vs. Freund-Geist (teal) — lesbares HUD, W17-Regel.
- **Risiko:** Cheat-Schutz nur als Plausibilitäts-Klemme (Score ≤ SCORE_MAX,
  Kurve monoton-plausibel) — ehrlich dokumentieren, dass Client-Werte
  vertrauensbasiert sind (Freundeskreis, kein globales Leaderboard).
  Netz-Ausfall darf den Rundenstart NIE blockieren (Panel-„Offline"-Muster
  aus GvZ-PvP W17). `geist_rekord.gd` selbst bleibt unangetastet (geteilte
  Datei aller 38 Spiele!) — nur Aufrufer ändern sich.
- **Beweis:** Node-Tests fürs Servermodul (Quota, Validierung,
  Freunde-Sichtbarkeit — Muster gobnommp-Tests), Godot-Unit-Wächter für
  den Picker-Fallback ohne Netz, End-zu-End: 2 Testkonten, A lädt Bestlauf
  hoch, B sieht A-Geist im Pregame, schlägt ihn, Results-Zeile erscheint —
  als dauerhafter Flow mit lokalem Testserver (Muster GOB-NOM-Coop-Tests).

## 5. Foto-Momente: das Polaroid am Rundenende [S]

- **Was:** Im Host-`win_moment` (den seit W18 JEDE Runde hat) wird das
  SubViewport-Bild eingefroren und als schräg gedrehtes Polaroid mit
  Spielname + Score + Datum auf die Results-Karte gelegt; Knopf „In die
  Galerie" speichert es ins vorhandene Galerie-System (Quelle „Arcade").
  Rekord-Runden bekommen einen Gold-Rahmen.
- **Warum:** G-minigames §1.1 nennt als SubViewport-Grund (c) wörtlich:
  „Ende-Screenshot fürs Results-Panel/Fotoalbum" — die Architektur wartet
  seit M1 darauf, gebaut wurde es nie (Code-Prüfung: kein
  `get_texture`-Aufruf im Host). Der User will Dopamin + „Ein-Spiel-Gefühl":
  Das Polaroid verbindet die Minispiele mit dem Haustier-Kern (Galerie,
  Fotomodus, Snap-a-Gooby existieren) und macht Rekorde teilbar/erinnerbar
  statt flüchtig. Eine Nadel-Impuls-Belohnung (EVAL §1.2) bekommt ein
  bleibendes Artefakt.
- **Wie (Skizze):** Im Host GENAU EIN neuer Hook direkt beim
  Auto-`win_moment` (der END_MOMENT_GRACE_MS-Pfad existiert):
  `GameSlot`-SubViewport → `get_texture().get_image()`, auf ~512 px lange
  Kante skaliert (iPhone-Speicher), als PNG in den Galerie-Speicher.
  Polaroid-Widget als NEUE Datei `results_polaroid.gd`, die `results.gd`
  nur additiv einhängt (eine Zeile im Rows-Aufbau, hinter Feature-Check
  „Bild vorhanden?"). Reduced-Motion: Polaroid steht statisch statt
  einzudrehen.
- **Risiko:** `minigame_host.gd` und `results.gd` sind heilige geteilte
  Dateien — deshalb: 1 Hook-Zeile im Host (fail-safe: jeder Fehler beim
  Grabben wird geschluckt, Runde endet normal weiter), Rest in neuen
  Dateien. GPU-Readback kostet einmalig ~1 Frame — im ohnehin
  zeitlupen-gefüllten win_moment unkritisch, aber auf A12 real messen.
  Galerie-Quota beachten (nicht jede Runde speichern — nur auf Knopfdruck,
  Rekorde optional automatisch).
- **Beweis:** Unit-Wächter: Headless-Runde erzeugt Bild ≤ Budget-Größe,
  Fehlerpfad (Textur null) lässt Results intakt; Leak-Gate 38/38 (Image-
  Referenzen!); Playtest-Flow: Runde spielen → Polaroid sichtbar →
  speichern → in Galerie wiederfinden, quer + hochkant, Screenshot-Beweis.

## 6. Modifier-Mutationen: seltene Doppel-Events [M]

- **Was:** Alle ~5–8 Events rollt der Scheduler statt eines Einzel-Modifiers
  eine „MUTATION": zwei kombinierbare Typen zünden zusammen unter neuem
  Namen, Farbe und Banner („GOLDRAUSCH = Doppelgold + Turbo",
  „FEDERREGEN = Federleicht + Münzregen", „GLÜCKSSCHUB = Glückspilz +
  Lernrausch" — 6–8 kuratierte Paare, keine freie Kombinatorik). Arcade-
  Badge pulsiert zweifarbig, Pregame erklärt beide Wirkungen.
- **Warum:** Die Engine ist das am saubersten gebaute Überraschungssystem
  im Spiel (deterministischer Stream, Anti-Farm-Ledger, Refund) — aber
  nach ein paar Tagen kennt man alle 6 Typen. Variable Belohnung braucht
  seltene Ausreißer nach oben (EVAL-Dopamin-Logik: die Kurve braucht
  Spitzen AUSSERHALB des Results-Clusters). Mutationen recyceln 100 % der
  vorhandenen Wirkungs-Mechanik (`launch_params` ist schon ein flaches
  Zahlen-Dictionary) für einen neuen „Woah"-Moment.
- **Wie (Skizze):** In `modifier_engine.gd` additiv: kuratierte
  `MUTATIONEN`-Tabelle (Paar → name_key/color/icon), im `_roll_event` EIN
  zusätzlicher Seed-Zug NACH den bestehenden Zügen (Paar-Index, Kadenz,
  DANN Mutations-Roll — bestehende Streams bleiben für alte Saves
  vorwärtskompatibel, weil der Zusatz-Zug nur die Zukunft betrifft).
  `launch_params` merged die zweite Wirkung; `current.type` bleibt EIN
  String (`"mut:goldrausch"`), damit `normalize_slice` alte Saves nie
  verwirft (Mutations-Typen in TYPES registrieren). Award-Pfad: coin_mult ×
  xp_mult wirken schon heute unabhängig — Anti-Farm bleibt, weil ALLE
  Überschüsse gegen dasselbe 150-c-Ledger laufen (kein neuer Reason nötig).
- **Risiko:** `modifier_engine.gd` ist geteilt und deterministisch — die
  Roll-Reihenfolge (`TYPE_IDS`, 2 Seed-Züge) ist VERTRAGSBESTANDTEIL:
  neue Züge strikt ANHÄNGEN, nie umsortieren; Wächter-Test, der die alten
  Roll-Ergebnisse für fixe Seeds einfriert (Golden im Repo). Balance:
  Doppel-Wirkung ist durchs Ledger gedeckelt, aber XP×2×1,5-Pfade gegen
  Level-Kurve durchrechnen. UI-Banner zweifarbig in beiden Formaten testen.
- **Beweis:** Rot-vor-grün: Golden-Test der bisherigen Event-Sequenz für
  Seeds 1..50 VOR der Änderung committen, danach beweisen, dass sich
  Bestands-Rolls nicht verschieben; Mutations-Frequenz-Test (erwartete
  Rate über 1000 simulierte Events); Award-Ledger-Wächter (Cap greift);
  Playtest-Flow mit Dev-`force_event` einer Mutation → Pregame-Banner →
  Results zeigt beide Wirkungszeilen.

## 7. Arcade-Album: Bronze/Silber/Gold je Spiel + Sammel-Meta [M]

- **Was:** Jedes der 38 Spiele bekommt eine Medaille: Bronze = Ziel
  geschlagen (`beaten.normal`), Silber = Schwer-Ziel (`beaten.hard`),
  Gold = Geist-Rekord über Schwellwert ODER Endlos-Meilenstein. Medaillen
  sichtbar auf Kachel (Idee 2 liefert den Platz) + neue Album-Doppelseite
  „Arcade-Medaillen" mit Zähler „n/38 Bronze · m/38 Silber …"; Sammel-
  Belohnungen bei 10/25/38 Bronze (Münzen, Sticker, 1 exklusive
  Garderoben-Kappe „Arcade-Champion").
- **Warum:** UserFeedback-Geschichte: „Alle Spiele sind grauen Haft" →
  38 Spiele wurden poliert und bit-zertifiziert — aber es gibt KEIN Ziel,
  das über „ein Spiel gut spielen" hinausgeht. `beaten` wird seit W1d
  geschrieben und nirgends gefeiert (dasselbe tote-Reservoir-Muster wie
  EVAL D2 bei den Stickern, das dort P0 war). Komplettisten-Meta =
  wochenlange Wiederkommen-Anlässe aus VORHANDENEN Daten.
- **Wie (Skizze):** Pure Ableitung `arcade_medaillen.gd` (Save-Slice rein,
  Medaillen-Dictionary raus — kein neuer Save-Key für Medaillen selbst,
  nur für abgeholte Sammel-Belohnungen: additiv
  `minigames.medaillenClaims`). Album: neue Seite nach dem Muster der
  Sammlungs-Sets (W13: 4 Sets sichtbar + befüllt). Vergabe-Feier über den
  globalen Sticker-Unlock-Service (seit EVAL-D2-Fix vorhanden): Medaille
  neu → Toast + Konfetti. Belohnungs-Buchung über
  `Economy.award(reason "medaillen")`, einmalig via Claims-Marker.
- **Risiko:** KEIN Schreibzugriff in den Award-Pfad nötig (reine Ableitung
  beim Lesen) — damit bleiben Goldens sicher. Gefahr ist eher Balance
  (Gold-Schwellen pro Spiel ehrlich erreichbar? Endlos ist erst ab
  `beaten.hard && level ≥ 10` offen — Gold darf nicht doppelt gaten) und
  Alt-Saves: Spieler mit vollem `beaten` bekommen beim Update 38 Toasts
  auf einmal → Erst-Sync still verbuchen, nur NEUE Medaillen feiern.
- **Beweis:** Unit-Wächter der Ableitung über Fixture-Saves (leer /
  midgame / maxed — `v4_maxed.json` existiert), Erst-Sync-ohne-Toast-Test
  (rot-vor-grün), Claims-Einmaligkeit, UI-Wache Album-Seite 4 Formate,
  Playtest-Flow: Ziel schlagen → Medaillen-Toast → Album zeigt Zähler.

## 8. Arcade-Cup: Mini-Turnier über 3 Spiele [M]

- **Was:** Ein „Cup" = 3 Spiele hintereinander (deterministisch pro Woche
  gewürfelt, z. B. bunnyHop → veggieChop → miniGolf), Punkte werden
  normalisiert summiert (Score ÷ Spiel-Ziel), zwischen den Läufen KEINE
  Arcade-Rückkehr sondern eine Podiums-Zwischenkarte („1/3 geschafft!"),
  am Ende Siegerehrung mit Konfetti + Cup-Bestwert. Einstieg über eine
  eigene Cup-Kachel in der Arcade.
- **Warum:** Direkt aus dem User-Denkanstoß („Turnier-Modus über 3
  Spiele?") — und er füllt eine echte Lücke: Die Session-Dramaturgie
  endet heute immer nach 1 Runde (Results → Arcade). Ein Cup erzeugt
  einen 5–8-min-Bogen mit steigender Spannung — das „Ein-Spiel-Gefühl"
  auf Session-Ebene. Normalisierung über die vorhandenen `target`-Werte
  der Registry macht die Summe fair, ohne ein einziges Spiel anzufassen.
- **Wie (Skizze):** NEUER Koordinator `arcade_cup.gd` + Szene
  `cup_zwischenkarte.tscn` OBERHALB des Hosts: Er startet den Host 3× mit
  normalen Launch-Payloads und fängt das Results-Signal ab (der Host hat
  saubere `again/back/home`-Signal-Grenzen — der Cup ersetzt nur die
  Navigation danach, Muster „Endless-Lock"-Sonderpfade). Wertung liest
  das Award-Breakdown NUR (score), zahlt Cup-Bonus separat über
  `Economy.award(reason "cup")`. Cup-Zusammensetzung deterministisch aus
  KW-Seed (Wiederverwendung `arcade_wochenchallenge`-Ableitung, Idee 3).
- **Risiko:** Der Host ist die heiligste Datei (996 Z., 38 Spiele dran) —
  Design-Regel: Host wird NICHT modifiziert, der Cup ist reiner Aufrufer.
  Energie: 3 Runden = 3× 8 Energie ist ehrlich, aber im Pregame der
  Cup-Kachel klar ausweisen (kein versteckter Abzug — die 5
  Kauf-Bug-Lektionen aus W13). Abbruch mitten im Cup: Zwischenstand
  verwerfen, gezahlte Runden-Rewards bleiben (kein Rollback-Zoo).
- **Beweis:** Unit: Normalisierungs-Mathe (Ziel-relativer Score, Klemmen),
  Determinismus der Wochen-Zusammensetzung, Abbruch-Semantik.
  Playtest-Flow: kompletten Cup quer + hochkant spielen, Zwischenkarten +
  Siegerehrung screenshotten; Leak-Gate (3 Host-Zyklen nacheinander =
  guter Stresstest, den es so noch nicht gibt).

## 9. Klang-Identität: 6 Familien-Tracks + Sieges-Stinger pro Kategorie [S]

- **Was:** Statt „30+ Spiele teilen EINEN Arcade-Track": 6 neue Loops nach
  Spiel-Familie (Flink/Timing, Fahren, Rätsel, Sport, Defense/GvZ-Umfeld,
  Ranch) über die vorhandene `game:`-Kontext-Mechanik zugeordnet, dazu je
  Familie ein 2-s-Sieges-Stinger, der VOR der Results-Fanfare spielt.
  Loop-Nähte der neuen Tracks von Anfang an mit LOOPSTART-Tags.
- **Warum:** EVAL S9 wörtlich: „30 von 37 spielbaren Games teilen den
  einen Arcade-Track" — Stand heute sind erst 7 `game:`-Kontexte gemappt
  (Code-Prüfung `music_registry.gd`). Der User-Anspruch „jedes Spiel …
  poliert" + „Ein-Spiel-Gefühl" ist auch ein AUDIO-Anspruch: Familien-
  Identität ist der 20-%-Aufwand für 80 % der Wirkung gegenüber 38
  Einzeltracks. EVAL S2 (Loop-Nähte bis 95 dB) mahnt, es diesmal von
  Anfang an richtig zu machen.
- **Wie (Skizze):** Nur Content + Registry: 6 Loops synthetisieren
  (die W18-Klangbetten wurden bereits erfolgreich „selbst synthetisiert" —
  Pipeline existiert), Einträge in `music_registry.gd` mit korrekt
  normalisiertem `gain_trim` (EVAL-S1-Regeln: eff. Peak ≤ −1 dBFS),
  Zuordnung Spiel → Familie über das `kategorie`-Manifest-Feld aus Idee 2
  (eine Quelle für UI UND Audio). Stinger über den vorhandenen
  FeelSfx-Kontrakt, Familie als Parameter.
- **Risiko:** Kein Spiel-Code ändert sich — Risiko ist rein ästhetisch
  (Tracks müssen zur Pastell-AC-Stimmung passen; gegen `EVAL`-Spektral-
  Werkzeug `analyze_audio.py` prüfen: Zentroid, >4-kHz-Anteil, Clipping).
  Musik-Wechsel zwischen Arcade-Grid und Spiel darf nicht hart springen
  (Crossfade 1,5 s existiert).
- **Beweis:** Audio-Analyse-Lauf über die 6 neuen Dateien (Peak/Loudness/
  Loop-Naht-Differenz < 6 dB — der W-Runden-Standard), Registry-Wächter
  „jedes spielbare Spiel hat einen game:-Kontext ODER eine Familie",
  Movie-Maker-Aufnahme MIT TON eines Famlien-Durchlaufs als Hör-Beleg
  (EVAL-Methodik wiederverwenden).

## 10. GvZ „Überlebens-Garten": Endlos-Wellen nach der Kampagne [L]

- **Was:** Nach Kampagnen-Sieg (L15) schaltet GvZ einen Endlos-Modus frei:
  unendliche, prozedural eskalierende Wellen auf einem Remix-Feld,
  zwischen den Wellen 15-s-Umbau-Fenster, Score = überstandene Wellen +
  Stil-Boni; Geist-Rekord-Chip zeigt die eigene Bestwellen-Marke,
  Bestwert füttert `endlessBest` (der Award-Endlos-Pfad existiert).
- **Warum:** GvZ ist das erklärte Flaggschiff (G-minigames §4) und hat als
  einziges „großes" Spiel NULL Wiederspielwert nach der Kampagne
  (`supports_endless: false` in der Registry; PvP braucht einen Freund
  online). PvZ-Survival ist das Genre-Vorbild mit bewiesener Langzeit-
  Bindung. Die 20-Hz-Fixed-Tick-Logik (`gvz_logic.gd`, §4.1) ist
  deterministisch — prozedurale Wellen aus GoobyRng sind bot-testbar wie
  alles andere.
- **Wie (Skizze):** Wellen-Generator als pure Funktion in NEUER Datei
  `gvz_endlos_wellen.gd` (Budget-Kurve: Matsch-Punkte pro Welle steigen
  geometrisch, Einkauf aus der Zombie-Kostentabelle §4.5 — dieselben
  Balance-JSONs, kein neues Tuning-Universum). `gvz_game.gd` bekommt den
  Modus über `ctx.difficulty == "endless"` (der Pregame-Endlos-Toggle
  existiert framework-seitig schon); Registry-Flag auf `true` +
  Freischalt-Gate „Kampagne durch" statt des Standard-Endlos-Locks.
  Coin-Auszahlung: Endlos-Pauschale (ENDLESS_FLAT_COINS) — Ökonomie
  bleibt automatisch sicher.
- **Risiko:** GvZ-Dateien sind groß (gvz_game 888 Z., Bot 987 Z.) und
  die Kampagnen-Level sind durch Bot-Zertifizierung + Sticker-Zähler
  (gvzNutella …) abgesichert — der Endlos-Pfad muss STRIKT additiv sein
  (eigener Wellen-Feed statt `levels/*.json`-Umbau). Performance: lange
  Sessions akkumulieren Pool-Objekte → Leak-Gate wird hier ernst.
  Difficulty-Ramp braucht Bot-Iterationen (Monotonie-Test: Bot stirbt
  in erwartbarem Wellen-Fenster).
- **Beweis:** Bot-Zertifizierung des Endlos-Modus (Seeds 1..50: Wellen-
  Median im Zielband, Monotonie über die Wellen-Nummer), Kampagnen-
  Goldens/Tests byte-gleich, Leak-Gate nach 30-Wellen-Botlauf,
  Playtest-Flow: Freischaltung erst nach L15, 5 Wellen spielen,
  endlessBest + Geist-Chip live.

## 11. GOB-NOM-Werkstatt: Level-Editor ins Spiel + Level-Codes teilen [L]

- **Was:** Der existierende GOB-NOM-Level-Editor (W15, bisher NUR im
  Godot-Editor via `@tool`) wird als „Werkstatt" spielbar: Elemente aus
  dem Baukasten (§5.2) auf dem iPhone platzieren, Solver-Check erzwingt
  Lösbarkeit vor dem Speichern, eigene Level als kompakter Level-Code
  (Base64 des Level-JSON) teilbar über die vorhandene Post/Codes-Schiene;
  „Werkstatt-Regal" zeigt eigene + empfangene Level.
- **Warum:** UGC ist die stärkste Langzeit-Bindung, die ein Minispiel-
  Bereich haben kann — und GOB NOM ist der EINZIGE Kandidat, bei dem 80 %
  schon existieren: Level sind JSON-Daten (`gobnom/levels/*.json`,
  Content-Pack-Design §5.4 „neue Level-Packs ohne IPA"), ein Editor + ein
  Solver (`gobnom_solver.gd`) sind gebaut. Der User liebt GOB NOM
  (explizites Wunsch-Spiel) und die Post-/Freunde-Infrastruktur (W13)
  wartet auf mehr Inhalte-Arten.
- **Wie (Skizze):** Editor-UI als eigene Szene über dem bestehenden
  `editor/`-Code (Touch-Anpassung: Element-Palette in der Daumenzone,
  Drag-Platzierung — Kisten-Drag-ASMR-Muster aus W19). Speicherung:
  additiver Save-Bereich `gobnom.werkstatt` (eigene Level, gedeckelt
  z. B. 24). Teilen: Level-JSON → komprimierter Code über die
  Mail-/Geschenk-Schiene (`mail.js` kann Payloads; Solver-Check läuft
  beim EMPFÄNGER erneut — nie ungeprüfte Level laden). Gewertete Coins
  gibt es NUR für Erst-Klärungen fremder Level mit fester Pauschale
  (Anti-Farm: eigener Reason + Tages-Ledger).
- **Risiko:** Der größte Brocken der Liste: Touch-Editor-UX ist
  Handarbeit, Solver-Laufzeit auf dem Gerät begrenzen (Budget +
  „zu knifflig zum Prüfen"-Ehrlichkeit), Missbrauchs-Fläche beim Teilen
  (Validierung: Element-Whitelist, Zahlen-Klemmen, Größen-Deckel — dem
  Empfänger darf NIE ein Crash-Level unterkommen; Fuzz-Tests Pflicht).
  Die 15 Kampagnen-Level + deren Fortschritt bleiben komplett getrennt
  (kein gemeinsamer Fortschritts-Slice).
- **Beweis:** Fuzz-Wächter (1000 zufällig mutierte Level-Codes → Loader
  wirft nie, lehnt sauber ab), Solver-Budget-Test, Round-Trip-Golden
  (Level → Code → Level bit-gleich), Playtest-Flow: Level bauen →
  Solver-Häkchen → Code an Testkonto B → B spielt es durch, quer +
  hochkant; Kampagnen-Regression unverändert.

## 12. Neues Spiel „Möhren-Rutsche" — das Sofa-Duell (1 Gerät, 2 Daumen) [L]

- **Was:** Das erste LOKALE 2-Spieler-Spiel: iPhone quer auf den Tisch,
  jeder Spieler bedient eine Bildschirmhälfte (Spiegel-Layout), 90
  Sekunden Möhren-Kanonen-Duell — fallende Möhren per Tap in die eigene
  Kiste lenken, Golden-Möhre stiehlt Punkte vom Gegner, 3D-Bühne mit
  Gooby als jubelndem Schiedsrichter in der Mitte. Solo-Modus gegen
  Bot-Gooby, damit die Kachel nie „tot" ist (und Difficulty/Bot-
  Zertifizierung normal funktionieren).
- **Warum:** Ehrliche Lücken-Analyse des 38er-Mix: Timing, Catch, Defense,
  Physik, Rhythmus, Puzzle, Fahren, Runner, Brettspiele — alles da; was
  FEHLT, ist „zeig es einem Freund, der neben dir sitzt". Alle
  Mehrspieler-Wege (GvZ-PvP, GOB-NOM-Coop, Ranch-MP, Brettspiele) brauchen
  zwei Geräte + Server. Ein Sofa-Duell ist der beste „Zeig-Moment" für
  ein Sideload-Spiel, das der User Freunden vorführt — und Godot-Touch
  kann Multi-Touch-Zonen nativ (Input-Gate-Muster existiert in
  GOB-NOM-Coop §5.4: „Touch-Position → Spielerzuordnung").
- **Wie (Skizze):** Regulärer neuer Spiel-Ordner
  `games/moehren_rutsche/` + `game.json`-Manifest (die Registry ist
  genau dafür gebaut — NULL Framework-Änderung). Logik als pure
  `_logic.gd` mit GoobyRng (Bot-zertifizierbar, Difficulty easy/normal/
  hard fürs Solo). Duell-Wertung: Coins aus dem SIEGER-Score über den
  normalen Award-Pfad (eine Runde, ein Award — kein Doppel-Payout).
  Intro-Beat nach W17-Grammatik, HUD spiegelsymmetrisch, JuiceKit-Effekte
  je Hälfte örtlich begrenzt.
- **Risiko:** Neues Spiel = Handarbeit an Szene/Assets (das war schon in
  G-minigames §R6 der ehrliche Kostentreiber). Multi-Touch-Fairness auf
  iPhone (Palm-Rejection, gleichzeitige Taps) früh auf Gerät testen.
  KEIN Web-Golden existiert (Neubau) → stattdessen eigene
  Bot-Zertifizierung als Regressions-Anker von Tag 1 (das W15-Muster
  „30 von 38 bit-zertifiziert" fortschreiben). Leak-Gate erweitert sich
  automatisch auf 39 Spiele.
- **Beweis:** Bot-vs-Bot-Simulation über Seeds (Fairness: Gewinnrate
  ~50 % bei gleich starken Bots, rot-vor-grün gegen Seiten-Bias),
  3D-Pflicht-Test (Kamera+Licht+Geometrie — der bestehende Wächter),
  Playtest-Flow mit ZWEI synthetischen Touch-Strömen gleichzeitig,
  Duell-Video quer als Demo-Artefakt.

---

## Ehrliche Priorisierungs-Begründung (Kurzform)

1–2 zuerst, weil sie aus VORHANDENEN Daten/Mustern tägliche Anlässe bauen
(Spielerwert riesig, Aufwand klein bis mittel, Framework unangetastet).
3–4 bauen den Wochen-/Sozial-Rhythmus darüber (4 hängt als einzige Idee am
Server — deshalb hinter 3). 5 ist der billigste „Ein-Spiel-Gefühl"-Gewinn
mit fertig wartender Architektur. 6–8 vertiefen Systeme, die schon
funktionieren (Modifier, beaten-Daten, Session-Dramaturgie). 9 ist reiner
Content mit klarer EVAL-Grundlage. 10–12 sind die L-Brocken in absteigender
Sicherheit: 10 remixt bestehende GvZ-Balance-Daten, 11 hebt einen fertigen
Editor auf Touch, 12 ist ein ehrlicher Neubau und steht deshalb zuletzt —
er füllt aber die einzige echte Genre-Lücke des 38er-Mix.

Querschnitts-Regeln für ALLE Umsetzungen: Web-Paritäts-Goldens
(`tests/expected/*.json`) sind unantastbar; `minigame_host.gd` /
`minigame_award.gd` / `geist_rekord.gd` / `modifier_engine.gd` sind geteilte
Dateien aller 38 Spiele — Änderungen dort nur additiv, fail-safe und mit
rot-vor-grün-Wächter; jede Zeit-/Zufallsquelle injiziert (Clock/GoobyRng);
jeder neue Save-Key additiv (merge_defaults-Muster); Leak-Gate bleibt über
alle Spiele dicht.

# Bereich: Die 3 DLCs

# GOOBY-Roadmap — Bereich: Die 3 DLCs (RANCH · GOO UND BYE · MCGOOBY)

Planner-Welle (W19+), Branch `cursor/gooby-godot-loop-d1d8`. 12 priorisierte Ideen
(3 S · 6 M · 3 L; je 3 pro DLC + 3 Synergien). Ist-Bild aus `UserFeedback.md` (komplett),
`docs/godot-rewrite/DLC-GOO-UND-BYE.md`, `DLC-MCGOOBY.md`, `RANCH-DLC-IDEAS-1/3/4.md`
und Code-Stichproben (`scripts/ranch/**`, `scripts/dlc/goobye/**`, `scripts/dlc/mcgooby/**`).

**Ehrlicher Ist-Stand (Code-verifiziert):**

- **RANCH** ist der reifste DLC: Zucht komplett nach IDEAS-3 Kap. 4 (`horse_breeding.gd`),
  Liga ohne Abstieg (`comp/comp_liga.gd`), 43 Quests im Pack (`content/ranch_quests`),
  NPC-Freundschaften (`npc/rnpc_*`), Hufingen (`dorf/`), Entdecker-Karte + Fundorte (W19,
  `welt/ranch_entdecker_karte.gd`), MP-Besuch/Ausritt/Leaderboard (`mp/rmp_*`).
  W19-Abschlussbericht nennt KEINE Ranch-Restarbeit.
- **GOO UND BYE**: deterministischer Markttag (`goobye_markttag.gd` — Los-Blöcke VORAB
  gezogen, Preis wirkt nur auf Vergleiche), Laden-Level 1–5 als reine Zustandsprüfung
  (`goobye_level.gd`), Großmarkt-Fahrt/Lieferwagen/Kühl/Tagesangebot (Welle B/C). Es
  FEHLEN: Mitarbeiter (§5), Offline-Kasse (§2.2), Attraktivität (§6.5), Sonderwünsche
  (§6.4), Events (§8), Grid-Laden-Bau (§3), MP (§9). W19-Rest: Drag-Flow-Playtest +
  „Nachschub-Knopf vs. Fahrt“-Balance.
- **MCGOOBY**: alle 4 Stationen + 10 Rezepte + Laden-Rang (`mcgooby_fortschritt.gd`,
  Leiter im Menü-Pack), Kauf-Gate + Demo. Es FEHLEN: Mitarbeiter (§5 — `rg Mitarbeiter
  scripts/dlc/mcgooby/` = 0 Treffer), Ausbau (§6.1-Freischaltungen), Kunden-Geduld/VIPs
  (§4), Tages-Special (§3.3), Tageskasse (§2.3.6), Events (§7). W19-Rest: Mitarbeiter/
  Ausbau (§5/§6) + Rang-Aufstiegs-Moment + Stations-Visuals.
- Das Event-Kontext-Tor (`scripts/events/random_events.gd`) kennt bisher NUR `"ranch"` —
  beide Läden haben noch keine Random-Events, obwohl beide Design-Docs je 5 definieren.

---

## 1. McGooby-Team: Mitarbeiter mit Gag-Verträgen + Ausbau-Stufen [L] (MCGOOBY)

- **Was:** Die 5 Angestellten aus §5 (Grill-Gino, Fritten-Frida, Shake-Salvatore,
  Kassen-Kassandra; Drive-In-Danny erst mit Drive-In) per Aushang am Schwarzen Brett
  einstellen; ein eingeteilter Mitarbeiter **automatisiert seine Station im Rush** mit
  Stat-abhängiger Qualität (Ginos Sorgfalt 2 = gelegentlich „Röstaroma“), Stats wachsen
  durch gemeinsame Schichten, Pausentag-Knopf, kein Feuern. Dazu die ersten sichtbaren
  **Ausbau-Stufen** (§6.1): 2. Fritteuse = echte Doppel-Korb-Jonglage, Terrasse/Deko als
  Gastraum-Politur — gated am bestehenden Laden-Rang (`McGoobyKatalog.raenge()`).
- **Warum:** Wörtlich benannte W19-Restarbeit („Mitarbeiter/Ausbau §5/§6“) und der in
  UserFeedback W19 angekündigte „volle Fortschritt nach Kauf: Mitarbeiter/Ausbau/Sterne“.
  Mitarbeiter sind DER Sog-Hebel: Wer nur 2 Stationen mag, gibt 2 ab — die Jonglage
  bleibt real, weil Timer tab-übergreifend weiterlaufen (Welle-C-Fundament nutzt das).
- **Wie (Skizze):** Pure `team_logic.gd` neben `schicht_logic.gd` (Stations-Automatik =
  deterministische Bot-Aktion auf dem geteilten GoobyRng-Strom, exakt wie die
  Bot-Zertifizierung); Save additiv `mcgooby.team {id: {stats, schicht, pausentag}}` in
  `mcgooby_state.gd` (normalize-Self-Heal); Team-Daten + Gehälter + Ausbau-Kosten ins
  Menü-Pack (`mcgooby_katalog.gd`-Balance-Domain, Muster `raenge()`); Aushang-Sheet als
  eigene Datei (CI max-file-lines! `schicht_scene.gd` steht bei 964 Zeilen — neue UI
  NICHT dort hineinquetschen, Muster `schicht_ui_teile.gd`-Split).
- **Risiko:** Determinismus-Vertrag der Schicht — die Automatik darf den RNG-Verbrauch
  der `bestell_folge` NICHT verschieben (Welle-C-Regel: alte Goldens bleiben gültig);
  Mitarbeiter-Kauf/Gehalt transaktional (Gehalt NUR an Tagen mit gespielter Schicht,
  §5.3 — kein schleichender Konto-Abfluss); Balance-Kippe „Automatik trivialisiert den
  Rush“ → Automatik-Qualität < Spieler-Perfekt (nie „Perfekt!“-Callout vom Bot).
- **Beweis:** Rot-vor-grün-Wächter: gleiche Seed-Schicht mit/ohne Mitarbeiter =
  identische Bestellfolge (Bit-Vergleich); Gehalt-Wächter (kein Abzug ohne Session);
  Golden „Automatik-Station liefert nie Perfekt“; Flow `flow_w20_mcgooby_team`
  (einstellen → Schicht mit 2 automatisierten Stationen → Ende-Karte zeigt Team) in
  quer + hochkant, Exit 0.

## 2. Goo-und-Bye-Team: Bipsi & Co. + Offline-Kasse [L] (GOOBYE)

- **Was:** Das Mitarbeiter-Quartett aus §5.1 — Kassen-Gooby **Bipsi** (pennt zwischen
  Kunden ein, scannt im Halbschlaf fehlerfrei), Regal-Gooby **Stapel-Stefan**
  (Überschuss wird zu Dosentürmen), Lager-Gooby **Loretta** (übernimmt
  Großmarkt-Fahrten!), Berater **Herr Freundlich**. Mit mindestens 1 eingeteiltem
  Mitarbeiter öffnet die **Offline-Kasse** (§2.2: 30 % der Live-Rate, max 8 h Sim) —
  „Willkommen zurück, die Kasse hat gesummt“.
- **Warum:** Der größte offene Block der Design-Doc-Welle B (§10.5) und der stärkste
  Täglich-zurückkommen-Loop des Ladens: Offline-Ertrag + Wiedersehens-Karte holt
  zurück, ohne zu bestrafen. Loretta beantwortet nebenbei die W19-Balance-Frage
  „Nachschub-Knopf vs. Fahrt“ mit einer dritten, warmen Option (Fahrt delegieren).
- **Wie (Skizze):** Pure `goobye_team.gd` + `goobye_offline_kasse.gd` (exakt das
  `ranch_offline.gd`-Zeitmuster: Timestamp-Diff, Deckel, injizierte Uhr); Offline-Umsatz
  = GoobyeMarkttag-Tagesplan des VERPASSTEN Tages × 0,3 (der deterministische Tagesplan
  existiert schon — §6.1 nennt das ausdrücklich als Zweck!); Save additiv
  `dlc.goobye.team` + `dlc.goobye.kasse.offlineStandAt` in `goobye_state.gd`;
  Loretta-Fahrt = bestehende `goobye_transport.gd`-Funktion mit `fahrerTyp: "loretta"`;
  Zahlen (Gehälter 20–40, Offline-Rate/Deckel) in die Balance-Domain
  (`goobye_katalog.gd`-Muster `_balance()`). Stefan-Türme als reine Deko in
  `laden_bausteine.gd`/`laden_leben.gd` — NICHT in `laden_scene.gd` (gdlint-1000-Kante,
  dort bereits dokumentiert).
- **Risiko:** Determinismus-Vertrag `GoobyeMarkttag` ist heilig — Offline-Kasse darf
  nur den FERTIGEN Tagesplan ablesen, nie eigene Lose ziehen (sonst kippen die
  Golden-Tests und der spätere Freunde-Sync §9.1); Zeitsprung-Kanten (Zeitzonen,
  Uhr zurückgestellt) → nur monotone Timestamp-Diffs, Muster ranch_offline;
  Münz-Inflation → 30 %/8 h-Deckel als Pack-Daten live nachsteuerbar (§10.6-Risiko 3).
- **Beweis:** Golden-Wächter „Seed + Sortiment + 8 h weg = exakt erwarteter
  Offline-Bon“ (Zeitsprung-Fälle: vor/zurück/DST); Wächter „ohne Mitarbeiter keine
  Offline-Münzen“; Flow `flow_w20_goobye_team` (einstellen → App-„Neustart“ mit
  Uhr-Offset → Wiedersehens-Karte → Kassenstand transaktional korrekt), beide Formate.

## 3. McGooby Rang-Aufstiegs-Moment + Stations-Visuals [S] (MCGOOBY)

- **Was:** Beim Laden-Rang-Aufstieg (★→★★ …) ein echter Feier-Beat statt stiller
  Zahl: Freeze-Frame, Konfetti, Stern hängt sichtbar über der Tür, Onkel-warme
  Glückwunsch-Karte (Muster `ranch/gameplay/levelup_feier.gd`). Dazu die W19-Rest-Politur
  der Stations-Visuals (Fritteusen-Blubber-Stufen, Shake-Flausch-Krone sichtbar statt
  nur Balken).
- **Warum:** Wörtliche W19-Restarbeit; der Rang existiert (`mcgooby_fortschritt.gd`)
  und wird ehrlich angezeigt, aber der AUFSTIEG hat keinen Dopamin-Moment — genau die
  Lücke, die der User seit W14 („Polish/Feeling“) immer wieder benennt.
- **Wie (Skizze):** `mcgooby_fortschritt.gd` liefert schon `sterne(gs)` pur — der
  Schicht-Ende-Pfad (`schicht_scene.gd`/`abrechnung_logic.gd`) vergleicht Rang
  vorher/nachher und reiht die Feier-Karte beim Overlay-Dirigenten ein (W19-Lehre:
  CanvasLayer-Falle, Karte lag schon mal UNTER dem HUD!); Visuals in
  `schicht_ui_teile.gd`; keine neuen Save-Felder nötig (Rang ist Zustandsprüfung).
- **Risiko:** Overlay-Reihenfolge (Dirigent-Prio wie Heimkehr-Karte W19/W3);
  Datei-Budgets (CI max-file-lines am `schicht_scene`-Split respektieren). Klein.
- **Beweis:** Wächter „Aufstieg feuert genau einmal pro Stufe“ (rot-vor-grün: Feier
  doppelt bei erneutem Laden = rot); bestehender Flow `flow_w19_mcgooby_vier_stationen`
  bleibt grün; kurzer Zusatz-Flow-Schritt mit Rang-Sprung per präpariertem Slice.

## 4. Goobye „Nachschub vs. Fahrt“: Nachschub wird Notlieferung [S] (GOOBYE)

- **Was:** Die W19-Balance-Frage entscheiden: der Welle-A-Nachschub-Knopf
  (`laden_scene.gd` `_zeige_nachschub`) bleibt als **Notlieferung** (§4.1.3) —
  sofort im Regal, aber Einkauf +50 %, geliefert per GOOBERANDO-Fahrer-Kulisse mit
  Kistenstapel; die Großmarkt-Fahrt bleibt der günstige Normalweg (EK 60 %).
  Dazu den W19-Rest „Drag-Flow-Playtest“ als DAUERHAFTEN Wächter-Flow.
- **Warum:** W19-Restarbeit wörtlich; ohne Preis-Differenz entwertet der bequeme
  Knopf die komplette Welle-B-Fahrt (Kofferraum, Lieferwagen, Level-5-Story) —
  die Design-Doc hat die Antwort schon (§4.1: „Anti-Frust-Knopf, +50 %“).
- **Wie (Skizze):** Reine Daten + ein Faktor: `goobye_katalog.gd` bekommt
  `gooundbye.notlieferung_faktor` (Balance-Domain, Default 1.5), `_nachschub_kaufen`
  rechnet damit; Hinweis-Zeile im Sheet („Sofort, aber teurer — die Fahrt lohnt!“);
  GOOBERANDO-Kulisse optional als 2. Schritt (Fahrer-Sim existiert). Drag-Flow:
  `flow_w19_goobye_lieferwagen` um einen Fehlwurf-/Rückfeder-Schritt mit echten
  InputEventMouse-Events erweitern (Welle C hat das Testmuster schon).
- **Risiko:** Transaktionaler Kauf (erst prüfen, dann buchen — die W13-Lambda-Falle
  „Geld weg ohne Leistung“ ist dokumentierte Projekt-Wunde); Preis-Anzeige ehrlich
  (ausgegraut bei Münzmangel, W18-DLC-Hub-Lehre). Sehr klein.
- **Beweis:** Wächter „Notlieferung kostet exakt Faktor × EK und bucht atomar“
  (rot-vor-grün mit Münzmangel-Fall); Monotonie-Wächter des Markttags unverändert;
  erweiterter Lieferwagen-Flow beide Formate Exit 0.

## 5. Synergie-Matrix §4.5: Der Geschwister-Handschlag [M] (SYNERGIE)

- **Was:** Besitzt man BEIDE Läden, kauft McGooby seine Zutaten jeden Morgen sichtbar
  bei Goo und Bye ein (Warenkorb-Abholer an der Ladentür, +Umsatz für den Markt,
  −Einkaufskosten für den Imbiss, beide Boni klein & gedeckelt) — und die
  Goo-und-Bye-Tiefkühltruhe führt das **„GoobyMac-Fertiggericht“** (Verpackungs-Parodie
  mit Ohren-Bögen). Kein Zwang: beide DLCs bleiben solo vollständig.
- **Warum:** Explizit die vom User gewünschte Synergie-Matrix (GOO-UND-BYE-Doc §4.5.1,
  MCGOOBY §1.5-Vertrag „Synergien statt Überschneidungen“); macht den Besitz beider
  DLCs zu EINEM Gooby-Spiel statt zwei Inseln — exakt die „fühlt sich wie einzelne
  Spiele an“-Kritik vom 1.8.
- **Wie (Skizze):** Pure `dlc_synergie.gd`: deterministische Morgen-Buchung als reine
  Funktion der Uhr (Tag-Key) + beider Slices (`dlc.goobye.umsatz` + `mcgooby.besitz`),
  Deckel als Balance-Daten (z. B. +10–20 ᴳ/Tag Markt-Umsatz, −10 % Zutaten-Anteil der
  Schicht-Abrechnung in `abrechnung_logic.gd`); Abholer-Kulisse als OrtLeben-Figur im
  `laden_leben.gd`-Muster (NICHT in die 1000-Zeilen-Szene); Fertiggericht = 1 Zeile im
  Goobye-Sortiment-Pack mit `benoetigt_dlc: "mcgooby"`.
- **Risiko:** Doppel-Buchungs-Kante (App-Neustart am selben Morgen → Tag-Key-Guard im
  Save, `dlc.goobye.synergie.tag`); Determinismus: die Buchung darf den
  Markttag-RNG-Strom nicht berühren (nur Umsatz-Zettel-Addition NACH dem Plan);
  Balance-Inflation → beide Boni gedeckelt + im Pack nachsteuerbar.
- **Beweis:** Wächter „gleicher Tag bucht genau einmal“ (rot-vor-grün: zweimal
  `tick()` = ein Eintrag), „ohne McGooby-Besitz keine Buchung + kein Fertiggericht
  gelistet“; Golden: Markttag-Plan bit-identisch mit/ohne Synergie; Flow: beide DLCs
  kaufen → Morgen-Abholer sichtbar → Kassensturz weist Synergie-Zeile aus.

## 6. McGooby Tages-Special + Kunden-Geduld mit VIP-Bürgermeister [M] (MCGOOBY)

- **Was:** Jeden Tag kürt der Laden deterministisch 1 Gericht zum **Tages-Special**
  (§3.3: −20 % Preis, +50 % Bestell-Häufigkeit, „Neu auf der Karte!“-Aushang) und die
  Kunden bekommen die **3-Herzchen-Geduld** (§4.2: 0 ❤ = seufzend Tages-Special zum
  halben Preis, NIE Strafe) plus den ersten VIP: **Bürgermeister-Gooby will den
  Gurken-Deluxe mit exakt 7 Gurken** (zählt laut mit; `siebenGurken`-Erfolg + Sticker).
- **Warum:** Nächster Wellen-Schritt der Design-Doc (W-B-Paket „Kunden-Typen + Geduld
  + VIPs, Specials“); das Tages-Special ist ein Täglich-wiederkommen-Anker (heute
  Möhren-Pommes-Tag!) im bewährten Spotlight-Muster (W19 Arcade-Spotlight, 8 Wächter).
- **Wie (Skizze):** Pure `specials_logic.gd` (Datums-Seed × aktive Karte, GoobyRng,
  nie zweimal dasselbe — 1:1 das Spotlight-Rotations-Muster) + Geduld als Feld im
  Bestell-Ticket der `schicht_logic.gd`; VIP als seltener deterministischer Eintrag
  der `bestell_folge`; Erfolgs-Counter über die bestehende
  `achievements.counters`-Mechanik; Zahlen im Menü-Pack.
- **Risiko:** DER Determinismus-Klassiker: Special/VIP dürfen den RNG-Verbrauch der
  bestehenden Bestellfolge nicht verschieben (Welle-C-Regel; Lösung wie dort: eigene
  Salz-Ströme, alte Goldens bleiben bit-gültig); Geduld darf nie in Bestrafung kippen
  (0-❤-Regel exakt nach §4.2, „Gemütlich“-Schalter friert ein).
- **Beweis:** Golden „Seed → Special-Rotation 30 Tage ohne Doppler“; Golden „alte
  Welle-C-Schicht-Goldens unverändert“; Bot-Zertifizierung mit VIP im Strom; Flow
  `flow_w20_mcgooby_special` (Aushang sichtbar → VIP bedient → 7-Gurken-Zähl-Gag →
  Erfolgs-Toast), quer + hochkant.

## 7. Goobye Sonderwünsche + Attraktivitäts-Blumenkasten [M] (GOOBYE)

- **Was:** Pro Markttag haben 1–3 Kunden ein „?“-Wölkchen (§6.4: „Gibt es das auch in
  Bio?“ / „Könnt ihr Kartoffeln ordern?“ → Notiz am Schwarzen Brett = organischer
  Sortiments-Kompass; erfüllte Wünsche geben Zufriedenheit + selten ein
  Sticker-Tütchen). Daraus speist sich die EINE sichtbare Kennzahl
  **Laden-Attraktivität** (§6.5), angezeigt als **Blumenkasten vor dem Laden**
  (mehr Blüten = mehr Kunden morgen).
- **Warum:** Design-Doc-Welle-B-Rest; die Level-Leiter §7.1 verlangt Attraktivität ab
  L3 als Bedingung — `goobye_level.gd` sagt heute ehrlich „kommt mit ihren Systemen in
  späteren Wellen“. Wünsche + Blumenkasten geben dem Markttag ein Morgen-Ritual
  (Zettel lesen → reagieren → morgen mehr Kunden) = täglicher Rückhol-Loop.
- **Wie (Skizze):** Pure `attraktivitaet_logic.gd` (Sortiments-Breite, Preisniveau,
  erfüllte Wünsche → 0–100, Gewichte im Balance-Pack) + `wuensche_logic.gd`
  (deterministisch aus dem Tages-Seed, eigener Salz-Strom!); Save additiv
  `dlc.goobye.wuensche {offen, erfuellt}` + `attraktivitaet`; Kundenzahl-Input:
  `GoobyeMarkttag.simuliere(...)` bekommt einen Attraktivitäts-Parameter, der NUR
  `kundenzahl` vor dem Losziehen skaliert (Monotonie bleibt beweisbar); Blumenkasten
  als `laden_bausteine.gd`-Requisite; Level-Leiter in `goobye_level.gd` additiv um die
  Attraktivitäts-Schwelle erweitern (Level fällt nie — Werte nur als Zusatz-Bedingung
  für KÜNFTIGE Aufstiege, bestehende Stände behalten ihr Level: Self-Heal-Regel).
- **Risiko:** Determinismus-Vertrag: Attraktivität von GESTERN speist den Plan von
  HEUTE (nie intra-day, sonst Zirkelschluss + Golden-Bruch); Level-Regression bei
  Bestandsspielern ausgeschlossen halten (Level = max(alt, neu)); geteilte Ort-Szene:
  Blumenkasten/Brett in Bausteine-Dateien, nicht in `laden_scene.gd`.
- **Beweis:** Golden „Attraktivität X → Kundenzahl-Kurve exakt“ + Monotonie-Wächter
  (mehr Blüten ⇒ nie weniger Kunden); Wächter „Bestands-Save behält Level nach
  Update“ (rot-vor-grün); Flow: Wunsch erfüllen → Brett-Häkchen → nächster Tag
  sichtbar voller.

## 8. Laden-Events am Kontext-Tor: Krähen, Domino, Frittenfett & Eis-Schmelze [M] (SYNERGIE)

- **Was:** Die Random-Event-Engine (`scripts/events/random_events.gd`, Kontext-Tor)
  um die Kontexte `goobye` + `mcgooby` erweitern: **Krähen-Ladendiebe** auf der
  Obst-Schräge (GOOBYE §8.1), **Regal-Domino** (§8.2, braucht Stefans Türme aus
  Idee 2 — sonst generisches Kisten-Wackeln), **Frittenfett-Alarm** mit
  Seifenblasen-Sprinkler (MCGOOBY §7.1), **Möwen-Überfall** (§7.2) und als Krönung
  die **große Eis-Schmelze** (GOOBYE §8.5): steht die Truhe offen und McGooby ist
  installiert, kauft Shake-Salvatore den Bestand ZUM VOLLEN PREIS auf („Für meine
  Kunst.“) — Events sind Zeitfenster-Gags, NIE Strafen.
- **Warum:** Beide Design-Docs definieren je 5 Events, implementiert ist heute NULL
  (Kontext-Grep: nur `"ranch"`); Events sind die billigste Quelle für „der Laden
  lebt“-Momente und die Eis-Schmelze ist eine geschenkte Cross-DLC-Anekdote (b + c
  Kriterium in einem).
- **Wie (Skizze):** Event-Defs im bestehenden Def-Format (Ranch-Events als Vorlage,
  `ranch/events/ranch_event_host.gd`-Muster für die Inszenierung), Kontext-Gating an
  laufende Markttag-/Schicht-Session; Belohnungen über `ranch_event_rewards.gd`-Muster
  (transaktional); Fail-Texte DE/EN in die Strings-Domains (Paritäts-Test!).
- **Risiko:** Events dürfen die deterministischen Pläne nicht anfassen (Krähen
  „klauen“ nur aus dem Regal-Bestand VOR dem nächsten Plan-Tag; Salvatore-Aufkauf =
  transaktionale Sofort-Buchung außerhalb des Bon-Stroms); Zeitfenster-UI über dem
  Laden-HUD (Overlay-Dirigent, W19-Layer-Lehre); Kontext-Tor sauber — kein
  Ranch-Event darf plötzlich im Laden feuern (Wächter).
- **Beweis:** Wächter je Event (Kontext-Gate, Fenster-Timing per injizierter Uhr,
  Belohnung idempotent); rot-vor-grün „Eis-Schmelze ohne McGooby = Trink-Eis-Pfad,
  mit = Salvatore-Buchung“; Flow mit erzwungenem Event (DEV-Tools „Events sofort
  auslösen“ existiert) in beiden Läden.

## 9. Ranch „Tägliche Hof-Momente“ — 3 rotierende Mini-Aufgaben [S] (RANCH)

- **Was:** Jeden Tag 3 deterministisch rotierende Mini-Aufgaben („Miste Bellas Box
  aus“, „Bring Dr. Möhrchen 2 Äpfel“, „Reite einmal um den See“, „Besuche einen
  Fundort“) als kleine HUD-Karte am Hof — Pferde-XP + Gold, BEWUSST ohne Streak,
  ohne Verfall, ohne Malus (IDEAS-1 C5: „SSO-Chores ohne SSO-Druck“).
- **Warum:** Die Ranch hat als einziger DLC KEINEN benannten Tages-Anker (Quests sind
  Kapitel, Liga ist Wochenrhythmus) — C5 ist der im Ideen-Doc priorisierte
  Rückhol-Loop (Kriterium b) und der billigste (S), weil alle Ziel-Systeme existieren
  (Pflege, Reiten, Fundorte, NPC-Geschenke).
- **Wie (Skizze):** Pure Aufgaben-Roller `ranch_hof_momente.gd` (Tag-Seed →
  3 Aufgaben aus Katalog-Pool, Pool als Pack-Daten in `content/ranch/`); Erfüllung
  liest BESTEHENDE Zähler (horse_care-Aktionen, ride-Telemetrie, Entdeckungen) statt
  neue Hooks zu bohren; Save additiv `ranch.hofMomente {tag, erledigt[]}` im
  `ranch_play_slices.gd`-Muster; HUD-Karte im Hof-Cluster (`ranch_hof_scene.gd`).
- **Risiko:** Klein. Tages-Rollover-Kante (bondTag-String-Muster wiederverwenden);
  Belohnung transaktional + einmal pro Tag (Guard im Save); nicht als Pflicht
  inszenieren (kein Badge-Alarm — H6-Regel „nie Schuld-FOMO“).
- **Beweis:** Golden „Tag-Seed → Aufgaben-Trio 30 Tage ohne Doppler“; Wächter
  „doppeltes Erfüllen bucht einmal“; Flow: Hof betreten → Karte → 1 Aufgabe erledigen
  → Häkchen + Münzflug, beide Formate.

## 10. „Vom Ranch-Stand“: Hof-Erzeugnisse ins Goo-und-Bye-Regal [M] (SYNERGIE)

- **Was:** Ranch-Besitzer liefern Milch/Eier/Äpfel vom Hof (Sammel-Einkommen D4 —
  Glitzer-Einsammeln existiert) als **„Vom Ranch-Stand“-Ecke** mit Heu-Deko ins
  Goo und Bye (GOO-UND-BYE-Doc §4.5.3): Selbstkosten ~0, +10 % Hof-Aufschlag,
  begrenzte Tagesmenge. Der Hof bekommt damit erstmals eine WIRTSCHAFTLICHE Senke
  außer dem Direktverkauf.
- **Warum:** Synergie-Matrix-Punkt 3 (User-Kriterium c) und ein Doppel-Loop: Ranch
  täglich besuchen (einsammeln) → Laden täglich öffnen (verkaufen). Verzahnt die
  beiden größten DLCs zu einem Kreislauf, wie es die Stardew-Perspektive (#13 der
  20 Perspektiven) forderte.
- **Wie (Skizze):** Übergabe-Funktion in `goobye_regal.gd`/`goobye_state.gd` (Lager
  additiv, Waren-IDs sind ohnehin geteilt — `rehwei_sortiment`-IDs, §4.1); Quelle:
  Ranch-Sammelstand (`ranch_tiere.gd`-Hooks / `dorf_wirtschaft.gd`-Waren) mit
  Tagesdeckel als Balance-Daten; Regal-Ecke als Bausteine-Requisite mit
  `benoetigt_dlc: "ranch"`; Preis-Aufschlag über die bestehende Faktor-Mechanik
  (`goobye_preis.gd`).
- **Risiko:** Transaktionale Übergabe (Ware darf beim App-Abbruch weder doppelt noch
  weg sein — atomarer Move im selben update-Block, Muster Lieferwagen-Kauf);
  Determinismus: Hof-Ware ist nur BESTAND, ändert nie den Kundenplan-RNG;
  Balance-Inflation über Tagesdeckel im Pack.
- **Beweis:** Wächter „Move ist atomar“ (rot-vor-grün: Abbruch zwischen Abbuchung und
  Gutschrift unmöglich), „ohne Ranch-DLC keine Ecke“; Golden: Markttag mit
  Ranch-Ware = normale Bon-Mechanik; Flow: Ranch einsammeln → Laden → Ecke füllen →
  Kunde kauft Hof-Milch.

## 11. Ranch Regen-Buddelstellen + Schatzkarten auf der Entdecker-Karte [M] (RANCH)

- **Was:** Nach Regen glitzern 2–3 **Buddelstellen** im Tal (IDEAS-1 B6); ausgebuddelt
  werden kleine Schätze (Gold, Deko, selten eine **Schatzkarten-Hälfte**, die als
  neuer „?“-Pin auf der W19-Entdecker-Karte erscheint und zu einer vergrabenen Truhe
  an einem der 16 Fundorte führt). Wetter öffnet Gameplay statt zu sperren (H1-Regel).
- **Warum:** Der natürliche Folgeschritt der frisch gelandeten Entdecker-Karte
  (W19: Pins, Nebel, Detail-Karten — die Infrastruktur wartet auf mehr Inhalt) und
  beantwortet die dokumentierte Genre-Kritik „exploration lacks incentives“
  (IDEAS-1 §2.2-6). Regen-Kopplung macht Wetter zum Rückkehr-Anlass (b).
- **Wie (Skizze):** Buddelstellen als deterministische Spawns (Regen-Ende-Timestamp
  + Zonen-Seed → Positionen; `ranch/wetter/`-Zustand existiert) über das
  `ranch_fundorte_bau.gd`-/`ranch_entdeckungen.gd`-Muster; Schatzkarten-Pins additiv
  in `ranch_karte.json`-Datenformat + `ranch_entdecker_karte.gd`; Belohnungen über
  `ranch_event_rewards.gd`-Muster; Save additiv `ranch.schaetze` im Slices-Muster.
- **Risiko:** Welt-Performance — W19 hat den Ranch-Aufbau gerade mühsam auf 1,9 s
  gebracht (Time-Slicing, Streu-Cache): Buddelstellen müssen in den gestreamten
  Deko-Pfad (welt_aufbau_takt-Schritte mit eigenem RNG-Salz, „Reihenfolge ändert
  keine Positionen“-Vertrag!) statt in die Reveal-Essenz; Karten-Pin-Resize-Race
  (W19-Bug 5 — Wächter existiert, mitziehen).
- **Beweis:** Perf-Wächter: Reveal-Budget unverändert (die 8 neuen W19-Perf-Wächter
  bleiben grün); Golden „Regen-Seed → Buddelstellen-Positionen bit-stabil“; Wächter
  „Truhe bucht einmal“; Flow: Regen per DEV-Wetter → buddeln → Karten-Pin NEU-Badge →
  Truhe heben, quer + hochkant.

## 12. Ranch Freunde-Deckhengst: Zucht wird sozial [L] (RANCH)

- **Was:** Beim Ranch-Besuch (rmp existiert) den **Deckhengst eines Freundes** für die
  eigene Zucht anfragen (IDEAS-3 Kap. 4.1: Freund bekommt 10 % der Deckgebühr als
  Geschenk-Gold); der Stammbaum zeigt das Freundes-Pferd mit Porträt + Namen
  („Papa: Donnerkeks von Miras Hof“). Async über Server-Nachricht, kein Live-Zwang;
  offline weiter NPC-Deckhengste.
- **Warum:** Zucht ist komplett gebaut (`horse_breeding.gd` inkl. Glitzer-Gen,
  Stammbaum-Panel) und der stärkste Langzeit-Loop der Ranch — der Freundes-Pfad ist
  der im Ideen-Doc vorgesehene nächste Schritt und der wärmste Zeig-Moment
  („in MEINEM Fohlen steckt DEIN Pferd“). W19 ließ die Ranch bewusst ohne Rest —
  das hier ist der ehrliche nächste große Brocken.
- **Wie (Skizze):** Async-Muster statt Live: Anfrage als Server-Nachricht
  (GOOBY-SERVER Mail-/`goobypal.js`-Pending-ACK-Muster — idempotente Zustellung ist
  dort vorgezeichnet), Antwort liefert einen **Zucht-Snapshot** des Hengstes (Gene,
  Stats, Porträt-Seed) — die Vererbung rechnet dann rein lokal deterministisch
  (`horse_breeding.gd` unverändert!); Gebühren-Split idempotent per `rewardId`
  (IDEAS-4 §2.2-Ledger-Regel); UI im `rmp_besuch_panel.gd`-Umfeld.
- **Risiko:** Der größte Brocken der Liste: Doppel-Buchung der Deckgebühr
  (idempotenter Ledger Pflicht), Snapshot-Veralterung (Hengst wurde umtrainiert →
  Snapshot friert beim Accept ein, dokumentiert im Stammbaum), Offline-Konflikte
  (Anfrage läuft ab statt zu hängen, 48-h-TTL); Anti-Excel-Verträge aus Kap. 4.5
  gelten weiter (max 2 Trächtigkeiten, kein Pferde-Handel — NUR Gene reisen, nie
  Besitz: kein Scam-Vektor, F4-Regel).
- **Beweis:** Server-Tests: Anfrage/Accept/Ablauf + Gebühren-Idempotenz (doppeltes
  ACK = eine Buchung); Godot-Golden: Snapshot → Fohlen-Vererbung bit-identisch zu
  lokalem Elternpaar mit gleichen Genen; Offline-Wächter (Anfrage ohne Netz =
  freundlicher Chip, I2-Regel); Flow über 2 Instanzen (Playtest-Harness):
  anfragen → annehmen → Fohlen mit Freundes-Stammbaum.

---

## Prioritäts-Begründung (ehrlich, kurz)

1–4 räumen die **benannten W19-Restarbeiten** ab (McGooby-Team/Ausbau, Rang-Moment,
Goobye-Balance) — sie sind versprochen, design-fertig und entblocken die Läden-Roadmaps.
5–8 sind die **Sog- und Synergie-Schicht** (Handschlag, Special, Attraktivität, Events):
tägliche Anker + „EIN Spiel“-Gefühl, alle auf existierenden deterministischen Fundamenten.
9–11 geben der **Ranch** ihren fehlenden Tages-Anker und füttern die frische
Entdecker-Karte, bewusst hinter den Läden (Ranch hatte keine Restarbeit und ist am
reifsten). 12 ist der größte Einzelbrocken (Server + Ledger) und steht deshalb hinten,
obwohl er emotional der stärkste ist.

| Prio | Idee | Größe | DLC |
|---|---|---|---|
| 1 | McGooby Mitarbeiter + Ausbau | L | MCGOOBY |
| 2 | Goobye Mitarbeiter + Offline-Kasse | L | GOOBYE |
| 3 | Rang-Aufstiegs-Moment + Stations-Visuals | S | MCGOOBY |
| 4 | Nachschub wird Notlieferung + Drag-Wächter | S | GOOBYE |
| 5 | Geschwister-Handschlag (§4.5.1) | M | SYNERGIE |
| 6 | Tages-Special + VIP-Bürgermeister | M | MCGOOBY |
| 7 | Sonderwünsche + Attraktivitäts-Blumenkasten | M | GOOBYE |
| 8 | Laden-Events am Kontext-Tor | M | SYNERGIE |
| 9 | Tägliche Hof-Momente | S | RANCH |
| 10 | „Vom Ranch-Stand“-Regal-Ecke | M | SYNERGIE |
| 11 | Regen-Buddelstellen × Entdecker-Karte | M | RANCH |
| 12 | Freunde-Deckhengst | L | RANCH |

Zählung: **12 Ideen** — S: 3 (Prio 3, 4, 9) · M: 6 (5, 6, 7, 8, 10, 11) · L: 3 (1, 2, 12).
Verteilung: MCGOOBY 3 · GOOBYE 3 · RANCH 3 · SYNERGIE 3 (jede Synergie zahlt zusätzlich
auf 1–2 der drei DLCs ein). Alle 12 sind headless beweisbar (pure Logik + Wächter +
flow_*-Playtests); nichts erfordert GPU-Sichtprüfung als primären Beweis.

# Bereich: Sozial + Multiplayer + Server

# GOOBY Ideen-Planner — Sozial + Multiplayer + Server (W19-Planner-Welle)

Stand: Branch `cursor/gooby-godot-loop-d1d8`, 4.8. — NUR Analyse, kein Code geändert.

## Ist-Bild (ehrlich, gegen Code/Docs geprüft)

**Server (`GOOBY-SERVER/`, 22 Module / ~5100 LOC, 23 Test-Dateien, node:test auf Port 0):**
express+ws in EINEM Prozess, JSON-File-Storage, TOFU-`deviceSecret`, FriendCodes,
Token-Bucket-Limits. Feature-Stand: Freunde/Presence, GoobyPal (Pending+ACK,
E13-P1-2 **gefixt**; Crash-Durability via `flushNow` vor ok, E13-P1-1 **gefixt**,
`durability.test.js`), Online-Codes, Admin-Events (Push+Pull), Spielzeit-Analytics,
Besuche (Haus-Snapshot-REST + POS-Relay + Besuchs-Log), Schach + Schiffe versenken
(Turn-Relay, 120-s-Rejoin, Tomate), Post/Mail (Briefe/Fotos/Geschenke, Quota 20/Tag,
Postfach-Cap 50, idempotente clientId) + InstantGooby-Feed (Möhren-Likes),
GOB-NOM-Coop (Lockstep + Rejoin-Replay + Desync-Wächter), GvZ-PvP (Lockstep, kein
Rejoin, Reward Pending+ACK), Ranch-MP (`ranchmp.js`, 1029 LOC: besuch/ausritt/
rennen/fangen/parcours, Freundes-Bestenlisten, **Geister-Ablage mit PUT+GET-REST**),
Account-Umzug (Move-Codes), Bans, Webpanel (10 Seiten inkl. pal/spiele/ranch/players).

**Client:** `net_client.gd` + persistente Outbox (`outbox.gd`, upsert/dedupe),
Freunde-App im Telefon + FriendsScreen + SocialScreen (Besuchen/Schiffe/GoobyPal
pro Freund), Besuchs-Szene (beide Goobys, Raumwechsel, Host-Bauen mit Warnung,
Couch-Schlaf `couch_logic.gd`, Coop-Fahrt mit synchronem Radio), Brettspiel-Szenen
(inkl. Schach-KI), GvZ-PvP-Lockstep-Client, GOB-NOM-Coop-Client, RMP-Hub/Lobby/
Leaderboard/Ghost-Encoder (`comp_ghost.gd`, 10 Hz binär). **NEU seit W19:**
`geist_rekord.gd` — Score-über-Zeit-Kurven ALLER 38 Arcade-Spiele, 1 Hz,
≤160 Stützstellen, <1 KB JSON, bisher NUR lokal (`minigames.geist.<gameId>`).

**Updates:** Data-only-PCK-Packs über GitHub-Release-Tag `updates` am PRIVATEN Repo
→ Client braucht pro Gerät einen fine-grained PAT (docs/UPDATES.md §6a). Der
Repo-Umzug W16 hat schon einmal ALLE Schlüssel invalidiert (Doku-Warnkasten §6a) —
Token-Verteilung an Freunde ist der größte reale Reibungspunkt des Kanals.
Boot-Guard/Safe-Mode/Stale-Cleanup sind laut E12 kernmechanisch PASS.

**Was ist dünn:** (a) Fast alle MP-Features verlangen, dass beide GLEICHZEITIG
online sind (Besuch, Brettspiele, GvZ, GOB-NOM, Ranch-Matches) — in einem kleinen
Sideload-Freundeskreis ist das der seltene Fall; asynchrone Loops gibt es nur
Post/InstantGooby/Pal. (b) Beim Freund kann man wenig TUN (laufen, Emotes, Couch,
Coop-Fahrt — kein gemeinsames Spielen/Andenken). (c) Die W19-Geist-Kurven sind
lokal gefangen, obwohl `ranchmp.js` das Server-Muster (PUT/GET/Prune) fertig
vorlebt. (d) GvZ-Coop (USER-WISHES §G: „einer obere drei, einer untere drei
Reihen“) existiert nicht übers Netz — nur PvP. (e) Update-Kanal: Token-Frust.

**Leitplanke Sideload-Realität:** 2–6 Spieler, selbst gehosteter AMP-Server, kein
Matchmaking, Cheat-Schutz ist Fehlerabwehr statt Anti-Cheat (ranchmp-„unranked“-
Philosophie). Asynchron schlägt synchron.

---

## 1. Freunde-Geister für Arcade-Rekorde [M] (BEIDES)

- **Was:** Die W19-Geist-Kurven (Score-über-Zeit, <1 KB/Spiel) werden pro Spiel
  als „bester Lauf“ zum Server hochgeladen; im Pregame wählt man „Geist: Mein
  Bestlauf / Lena / Timo“ — der Live-±Delta-Chip (existiert!) läuft dann gegen
  den Freundes-Geist. Asynchron: niemand muss gleichzeitig online sein.
- **Warum (Quelle):** Planner-Auftrag nennt es explizit („Geist-Kurven existieren
  seit W19 client-seitig!“); `geist_rekord.gd` + Geist-Chip + „Geist
  geschlagen!“-Beat sind fertig (UserFeedback W19 Welle 1); `ranchmp.js`
  §Geister-Ablage (PUT/GET/Prune, `hatGhost`-Flag) ist die 1:1-Servervorlage.
  Höchster Spaß pro Aufwand im ganzen Bereich.
- **Wie (Skizze):** Server: neues Modul `arcadeghosts.js` (1 Zeile in
  `modules.js`), REST `PUT /api/ghost/arcade/:gameId` (Body
  `{wert:int, schritt:float, kurve:[int ≤160]}`, `restAuth`, best-only pro
  Spieler+Spiel, inline in Collection `arcadeghosts` — kein Blob nötig bei <1 KB)
  + `GET /api/ghost/arcade/:gameId/:friendCode` (`areFriends`-Gate) +
  `GET /api/ghost/arcade/:gameId` (Liste `{friendCode, wert, at}` aller Freunde).
  Client: nach neuem Bestlauf Outbox-`upsert(kind="arcade_ghost", id=gameId)`
  (nur der neueste Stand fliegt beim Reconnect raus — exakt das
  Analytics-Heartbeat-Muster in `outbox.gd`); Pregame-Chip lädt Freundes-Liste
  lazy (RMP-REST-Muster `rmp_rest.gd`), Kurve wird nach Download in
  `user://ghostcache/` gelegt → offline nochmal fahrbar.
- **Risiko:** Alte Clients: rein additive REST-Routen + optionales
  WELCOME-Feature-Flag → null Bruch. Quota: Server klemmt `kurve.length ≤ 160`,
  Werte 0..9 999 999 (Client-Konstanten spiegeln), pro Spieler+Spiel genau EIN
  Eintrag → 38 Spiele × 6 Spieler ≈ 250 KB Gesamtobergrenze. Score-Fälschung
  unter Freunden: akzeptiert (ranchmp-Philosophie, kein Anti-Cheat).
- **Beweis:** Node: `arcadeghosts.test.js` nach `ranchmp.test.js`-Muster
  (`twoFriends`-Fixture: PUT→GET, best-only-Ersetzung, Nicht-Freund → 403,
  Überlänge → 400, Crash-Durability nach `durability.test.js`-Muster). Client:
  `test_geist_rekord`-Erweiterung (Serialisierung↔Kurve bit-identisch,
  Chip-Quelle „Freund“ deterministisch). 2 Instanzen headless: server-seitig
  reichen zwei `WsClient`+`fetch`-Identitäten im node:test; client-seitig
  FakeLink-Rig wie `test_gvz_netz.gd` (Upload-Payload abfangen, Download
  einspeisen, Chip-Delta prüfen).

## 2. Anklopfen + „Komm vorbei!“-Einladung [S] (BEIDES)

- **Was:** Zwei winzige Sozial-Gesten in der Freunde-App: **Winken** (Freund
  bekommt Toast + Gooby-Reaktions-Emote) und **Einladen** (heute geht nur
  Gast→Host `VISIT_REQUEST`; der Host kann niemanden zu sich HOLEN).
- **Warum (Quelle):** SocialScreen/Freunde-App (W17 G5 f) haben Online-Punkte,
  aber keinen Anlass-Stifter — im kleinen Freundeskreis ist „ich bin da, komm
  rüber!“ der häufigste echte Use-Case. `visits.js` hat den kompletten
  Freigabe-Lifecycle schon, es fehlt nur die umgekehrte Initiative.
- **Wie (Skizze):** Server: `WINK {target}` → Push `WINKED {from}` (nur Freunde,
  Bucket 10/h wie `FRIEND_REQUEST`; Ziel offline → `OFFLINE_TARGET`, bewusst
  NICHT gepuffert — Doc C §5: Flüchtiges nie in die Outbox). `VISIT_INVITE
  {target}` → Push `VISIT_INVITED {from}`; Annahme löst serverseitig denselben
  Pfad wie `VISIT_REQUEST`+`VISIT_ACCEPT` aus (Freigabe-Map + `VISIT_READY` an
  beide) — kein neuer Lifecycle, nur neuer Eingang. WELCOME-`features` um
  `"wink"` erweitern; Client blendet Knöpfe nur bei Feature ein.
- **Risiko:** Alte Clients ignorieren unbekannte Push-Typen (Envelope-Vertrag
  §1.1 additive Evolution) — aber Feature-Gate verhindert, dass ein neuer Client
  einem alten Server Winks schickt (`UNKNOWN_TYPE`-Fehler wäre hässlich).
  Spam: Rate-Limit + „max 1 offene Einladung pro Paar“ (Invite-TTL-Muster aus
  `gvzmp.js`, 30 s).
- **Beweis:** Node: Test in `visits.test.js`/neu (Wink Freund↔Nichtfreund,
  Rate-Limit greift, Invite→READY-Fluss beider Seiten mit zwei `WsClient`s).
  Client: FakeLink-Push → Signal → Toast/Emote-Wächter; UI-Audit-Screens der
  Freunde-App laufen ohnehin in der 34-Screens-Wache mit.

## 3. Update-Mirror auf dem GOOBY-SERVER — tokenlose Updates für Freunde [M] (BEIDES)

- **Was:** Der Freundes-Server spiegelt `manifest.json` + Pack-Assets aus dem
  privaten GitHub-Repo; Clients, die den Server kennen, brauchen KEINEN eigenen
  GitHub-PAT mehr. GitHub bleibt Fallback.
- **Warum (Quelle):** docs/UPDATES.md §6a: jeder Freund braucht einen
  fine-grained PAT, per DM verteilt, beim W16-Repo-Umzug wurden ALLE ungültig
  (dokumentierter Warnkasten). B-updates.md §3 Option C benennt den
  Server-Mirror bereits als legitimen „Mirror #2“. Ein selbst gehosteter Server
  existiert sowieso — die Reibung ist rein historisch.
- **Wie (Skizze):** Server: Modul `updatesmirror.js`: ENV `GOOBY_GH_TOKEN`
  (EIN Token, nur auf dem Server), Hintergrund-Refresh der Release-Assets vom
  Tag `updates` in `data/updates-cache/` (ETag/Release-Id-Vergleich, kein Cron —
  lazy bei Anfrage + Min-Intervall), Routen `GET /api/updates/manifest` und
  `GET /api/updates/pack/:file` mit `restAuth` (nur bekannte Geräte — der Port
  darf kein anonymer Proxy ins Privat-Repo sein). Client: `config`-Pack-Feld
  `update_mirror_url`; `update_service.gd` probiert Mirror zuerst (bzw. immer,
  wenn kein Token gesetzt), Fallback GitHub-API; sha256-Verifikation der Packs
  bleibt unverändert client-seitig.
- **Risiko:** Vertrauensanker verschiebt sich ehrlich: wer den Mirror
  kontrolliert, kontrolliert Manifest+Hashes — beim selbst gehosteten
  Freundes-Server ist das derselbe Admin wie beim Repo (akzeptabel; optionale
  V2-Härtung = Manifest-Signatur aus B-doc §7). Traffic: Packs können zweistellige
  MB haben → Cache auf Platte + `Content-Length`, AMP-Instanz-Disk beachten.
  Alte Clients: unberührt (neuer Weg ist opt-in via config-Pack — und das
  config-Pack erreicht sie ja gerade NOCH über den alten Token-Weg; Erstverteilung
  für Token-lose neue Geräte: Mirror-URL steckt im eingebackenen config-Pack der
  nächsten IPA).
- **Beweis:** Node: Tests mit Fake-GitHub (lokaler `http.createServer` als
  Releases-API-Stub, Token-Header-Assertion, Cache-Hit ohne zweiten
  Upstream-Call, `restAuth`-Abweisung anonym). Client: E12-Eval-Muster —
  `godot --headless` + Update-Eval-Skript gegen echten `GOOBY-SERVER` auf
  Port 0 mit Fake-GitHub dahinter (komplette Kette Manifest→PCK→sha256→
  `installed.json`). Wächter: `update_service`-Unit-Test „Mirror zuerst,
  GitHub-Fallback bei 503“.

## 4. Brettspiele als Brief-Partien (asynchrones Schach/Schiffe) [M] (BEIDES)

- **Was:** Schach + Schiffe versenken zusätzlich als Korrespondenz-Modus: ein
  Zug pro Sitzung reicht, der Gegner zieht, wann er das nächste Mal spielt.
  Züge werden wie GoobyPal-Gutschriften zugestellt (pending + ACK).
- **Warum (Quelle):** `boardgames.js` verlangt heute beide online (Room +
  120-s-Rejoin) — im Sideload-Freundeskreis der Engpass schlechthin. Die
  Spiel-Logiken sind pure und deterministisch replaybar (`chess_logic.gd`,
  `battleship_logic.gd`), das Zustell-Muster (persistiert VOR ok, Client-ACK,
  Dedupe) existiert dreifach (Pal/GvZ/RMP).
- **Wie (Skizze):** Server: `corrgames.js`: Collection `corrgames`
  `{id, game, players:[a,b], moves:[{n,by,move,at}], turn, lastMoveAt}`;
  Nachrichten `CORR_START {target, game}`, `CORR_MOVE {id, n, move, clientId}`
  (Dedupe über `n`+`clientId`, Turn-Ownership-Check wie `boardgames.js`),
  Zustellung als Pending → `WELCOME.corrPending` + Push `CORR_MOVED`, ACK
  `CORR_ACK`. Caps: max 5 offene Partien pro Paar, Verfall nach 30 Tagen ohne
  Zug (lazy Prune, `ctx.clock`). Client: Brettspiel-Szenen bekommen
  „Brief-Partie“-Einstieg (Board-Zustand = Replay der `moves` durch die pure
  Logik); eigener Zug geht in die Outbox (`kind="corr_move"`, idempotent) —
  man kann also sogar OFFLINE ziehen, der Zug reist beim nächsten Connect.
  Ungelesen-Kapsel am Social-Screen („Lena hat gezogen!“).
- **Risiko:** Protokoll rein additiv (neue Typen, alte Clients unberührt;
  Feature-Flag im WELCOME). Outbox-Retry darf keinen Doppelzug erzeugen →
  `clientId`-Fenster wie `mail.js` (`CLIENT_ID_CAP`). Schach-Legalität bleibt
  client-seitig (Doc-C-§10-Entscheidung, Freundeskreis). Quota: moves-Array
  gedeckelt (Schach ≤ 300 Züge, Schiffe ≤ 200 Schüsse) → Partie sonst remis.
- **Beweis:** Node: `corrgames.test.js` (Zug an Offline-Gegner → Pending →
  Reconnect-Zustellung; Crash direkt nach ok → Zug überlebt
  [`durability.test.js`-Muster]; Turn-Fremdzug → Fehler; Dedupe). Client:
  pure-Logic-Replay-Tests (Zugfolge → identisches Brett auf beiden Seiten,
  zwei Logik-Instanzen im selben Headless-Test — hier braucht es KEIN
  Echtzeit-Rig, das ist der Charme des Modus). Playtest-Flow: Zug offline in
  die Outbox → Server-Start → Zustellung.

## 5. Gästebuch im Haus (asynchrones Besuchs-Andenken) [M] (BEIDES)

- **Was:** Nach einem Besuch kann sich der Gast mit 1 Zeile + Emote ins
  Gästebuch des Hosts eintragen; das Buch liegt im Flur (und ist beim nächsten
  Besuch für alle lesbar). Besuche hinterlassen damit endlich eine Spur.
- **Warum (Quelle):** Planner-Frage „was KANN man beim Freund eigentlich tun?“
  — heute verpufft jeder Besuch folgenlos. `visits.js` führt bereits ein
  Besuchs-Log (`visitsLogData`, wer/wann/wie lange) — die Server-Wahrheit
  „war wirklich da“ existiert schon als Gate.
- **Wie (Skizze):** Server: `GUESTBOOK_WRITE {host, text ≤120, emote}` — nur
  gültig, wenn der Absender laut Log in den letzten 24 h beim Host war (oder
  Freigabe noch aktiv); Collection `guestbook` `{host: [{from, text, emote,
  at}]}`, Cap 20 pro Haus (ältester fliegt), Steuerzeichen-/Längenfilter wie
  `PROFILE_UPDATE`. Abruf `GET /api/guestbook/:code` (friend-gated) + Feld
  `guestbookNew` im WELCOME für den Host. Client: Beim `VISIT_END` fragt ein
  Sheet „Ins Gästebuch eintragen?“ (Offline nie relevant — man IST online im
  Besuch); Host sieht NEU-Badge am Flur-Objekt; Einträge mit warmem
  Papier-Look (Brief-UI-Bausteine aus `mail_sheet.gd` wiederverwenden).
- **Risiko:** User-Content im Freundeskreis (gleiches Risikoprofil wie Mail —
  Länge+Filter reichen). Quota: 1 Eintrag pro Besuch (Server zählt gegen den
  Log-Eintrag). Alte Clients: additiv; ein alter Host sieht Einträge schlicht
  nicht (kein Bruch).
- **Beweis:** Node: Eintrag ohne Besuch → `NOT_VISITED`; Cap-Rotation;
  Nicht-Freund-GET → 403; zwei `WsClient`s spielen Besuch+Eintrag durch
  (Visit-Lifecycle-Fixture existiert in `visits.test.js`). Client:
  Sheet-Wächter + FakeLink; UI-Wache fürs neue Sheet in beiden Formaten.

## 6. Urlaubs-Postkarten an Freunde [S] (CLIENT)

- **Was:** Beim Reise-Antritt wählt man bis zu 3 Freunde — sie bekommen
  automatisch eine Postkarte („Grüße aus Bergen! — Herr Flauschig“) mit
  Urlaubs-Motiv als normalen Brief ins Postfach.
- **Warum (Quelle):** Reise-System + Mitbring-Momente (W19 Welle 1) und der
  komplette Mail-Pfad inkl. Foto (REST, Outbox, Dedupe) existieren — die Idee
  ist fast reine Verdrahtung und füttert die asynchrone Loop „Post kriegen
  macht Freude“ (W13B) mit regelmäßigem Anlass.
- **Wie (Skizze):** Client-only über `NetMail.send_mail`: Text deterministisch
  aus Ziel + Gooby-Nick + 1 Zufallsspruch (GoobyRng, seeded), Foto = fertiges
  Urlaubs-Szenen-Rendering (Galerie-/Urlaubs-Besuchs-Assets aus W15
  wiederverwenden, auf ≤1280 px wie der bestehende Foto-Pfad); Versand beim
  Abflug in die Outbox (kind `mail` — reist auch, wenn man beim Abflug offline
  war). Optional 1 Server-Zeile: Meta-Feld `postcard:true` für ein
  Briefmarken-Icon beim Empfänger; alte Empfänger-Clients rendern es als
  normalen Brief (degradiert sauber).
- **Risiko:** Quota-Ehrlichkeit: 3 Karten = 3 der 20 Tages-Briefe des Senders
  (bewusst, verhindert Spam strukturell). Kein Protokoll-Bruch (Server
  ignoriert/behält unbekannte Meta-Felder — vorher in `mail.js` prüfen, ob
  Meta durchgereicht wird; sonst die 1-Zeilen-Whitelist).
- **Beweis:** Client: Unit (deterministische Textwahl, Outbox-Eintrag beim
  Offline-Abflug, max 3), Flow-Test Reise→Postkarte. Node: nur falls
  Meta-Feld — Assertion, dass `postcard` beim Empfänger ankommt. End-zu-End:
  echter Server auf Port 0, Empfänger als skripteter `WsClient` (Muster
  `mail.test.js`), Godot-Client headless als Sender.

## 7. Freundes-Wochenliga in der Arcade [M] (BEIDES)

- **Was:** Jede Woche EIN Liga-Spiel (server-bestimmt, deterministisch
  rotierend); alle Bestwerte der Woche landen in einer Freundes-Tabelle,
  sonntags gibt es eine kleine Sieger-Ehrung (Event-Push + Krönchen-Chip).
- **Warum (Quelle):** Arcade-Spotlight (täglich, lokal) + Geist-Rekorde (W19)
  zeigen: asynchrone Vergleichs-Loops tragen. Ranch hat Freundes-Bestenlisten
  längst (`ranchmp.js` Leaderboard-REST) — die Arcade (38 Spiele!) hat nichts
  davon. Wochen-Takt passt zu Gelegenheits-Freundesgruppen besser als Live-PvP.
- **Wie (Skizze):** Server: `arcadeliga.js`: Wochen-Key in `GOOBY_TZ`
  (ISO-Woche, `dayKey`-Muster in `config.js` erweitern), Spiel der Woche =
  Hash(WochenKey) über die Spiele-Liste (Server ist die Quelle → alle sehen
  dasselbe; Liste kommt vom Client-Katalog, Server prüft nur String-Format);
  `POST /api/liga/score {gameId, score, clientId}` (nur aktuelles Liga-Spiel,
  best-only, `restAuth`), `GET /api/liga` → `{gameId, weekKey, entries:[...]}`
  über `friendCodesOf`. Wochenwechsel: Vorwochen-Sieger als Admin-Event-artiger
  Pull (`events.js`-Pending-Muster) an alle Teilnehmer. Client: Banner auf der
  Arcade-Kachel (Spotlight-Optik wiederverwenden), Tabelle im Freunde-Screen,
  Score-Upload per Outbox-upsert (Woche als Id — nur der beste Stand reist).
- **Risiko:** Zeitzonen-/Wochengrenzfehler (das Schnupfen-Wetter-Déjà-vu aus
  W16!) → Wochenlogik NUR serverseitig + `ctx.clock`-injiziert testen. Alte
  Clients: sehen kein Banner, tauchen einfach nicht in der Tabelle auf (ok).
  Quota trivial (1 Zahl/Spieler/Woche).
- **Beweis:** Node: Rollover-Test mit gestellter Uhr (Score von Montag zählt
  nicht mehr für Vorwoche), best-only, Fremde ausgeschlossen,
  Crash-Durability des Wochen-Siegs. Client: Banner-Determinismus-Wächter +
  FakeLink-Tabelle; 2-Spieler-Szenario komplett im node:test (zwei
  Identitäten posten, GET zeigt beide sortiert).

## 8. GvZ-Coop übers Netz („einer oben, einer unten“) [L] (BEIDES)

- **Was:** Der explizit gewünschte GvZ-Coop-Modus als Netz-Feature: beide
  verteidigen gemeinsam gegen Kampagnen-Wellen, Spieler A gehört die obere,
  Spieler B die untere Reihenhälfte, geteilte Nutella-Ökonomie.
- **Warum (Quelle):** USER-WISHES §G wörtlich („Coop-Modus 15 Level — einer
  obere drei, einer untere drei Reihen“); Doc C §3.8 plant ihn; umgesetzt ist
  nur PvP (`gvzmp.js` + `pvp_netz/`-Client, `rg coop` in `games/gvz/` = leer).
  Die gesamte Lockstep-Infrastruktur (Seed-Handshake, Input-Relay,
  Desync-Hash, Ergebnis-Pending) existiert doppelt als Kopiervorlage.
- **Wie (Skizze):** Server: `gvzmp.js` um `mode:"coop"` + `level`-Handshake
  erweitern (GOBNOM_LEVEL-Muster: beide bestätigen dasselbe Level →
  `GVZ_START {seed, level}`); Seiten heißen `oben`/`unten` statt
  gooby/zombie; Rest (GP_INPUT/GP_HASH/Result-Pending) identisch. Client: der
  große Brocken — die Kampagnen-Sim (`gvz_logic.gd` + Wellen-Spawns) muss in
  die deterministische Lockstep-Sim (`gvz_pvp_lockstep.gd`) gemappt werden:
  Wellen deterministisch aus Server-Seed, Reihen-Gate im Dispatch
  (`place`/`shovel`/`collect` nur in eigener Hälfte), geteilte
  Nutella-Zähler als Sim-Zustand. Fortschritt: Coop-Siege schreiben einen
  eigenen Slice (`gvz.coop_levels`), nicht die Solo-Kampagne.
- **Risiko:** Der Determinismus der Kampagnenlogik ist DIE Hürde (PvP-Sim
  wurde dafür gebaut, die Kampagne nicht — Float-/Reihenfolge-Fallen); ehrlich
  als Portierung planen, nicht als Flag. Protokoll: `mode`-Feld additiv —
  alter Client, der eine Coop-Einladung nicht versteht, muss sauber ablehnen
  (Server prüft `appVersion`/Feature-Flag aus HELLO und antwortet dem Einlader
  `FRIEND_TOO_OLD` statt kaputtem Match). Session-Länge: Kampagnen-Level
  dauern länger als PvP → Rejoin-Frage neu bewerten (GOB-NOM-Replay-Muster
  übernehmen statt PvP-„kein Rejoin“).
- **Beweis:** Vorbild wörtlich `test_gvz_netz.gd`/`test_w15_gobnom_netz`:
  ZWEI Sim-Instanzen im selben Headless-Prozess, Server-Seed → Input-Relay →
  identischer `state_hash` über N Ticks, Reihen-Gate-Verletzung wird
  verworfen; Node: Mode-/Level-Handshake, Alt-Client-Ablehnung,
  Desync-Abbruch, Result-Idempotenz. Dazu ein dauerhafter Playtest-Flow
  (Einladung→Level→3 Wellen→Sieg) wie die 6 W19-Flows.

## 9. Wichtel-Woche (Geschenk-Round-Robin) [M] (BEIDES)

- **Was:** Der Server verlost wöchentlich einen geheimen Wichtel-Ring unter
  den aktiven Spielern („Du wichtelst diese Woche für Lena 🎁“); geschenkt
  wird über den vorhandenen Post-Geschenk-Pfad, am Wochenende gibt es die
  Auflösung + Dankes-Push.
- **Warum (Quelle):** Planner-Denkrichtung „Geschenk-Round-Robin“;
  Mail-Geschenke inkl. Claim-Einmaligkeit existieren (`mail.js`,
  `MAIL_CLAIM`), Aktivitäts-Wissen (lastSeen) auch. Gibt der kleinen Gruppe
  einen wiederkehrenden Anlass, ohne dass irgendwer gleichzeitig online sein
  muss.
- **Wie (Skizze):** Server: `wichtel.js`: läuft nur, wenn ≥3 Geräte in den
  letzten 14 Tagen online waren (sonst Feature still aus); Ring =
  deterministische Permutation aus Hash(WochenKey + Teilnehmerliste), nie
  Selbstzuordnung; Zuordnung als WELCOME-Feld `wichtel:{target, deadline}` +
  Push; ein Mail-Geschenk an das Ziel in dieser Woche markiert „erfüllt“
  (Hook im Mail-Sendepfad, meta `wichtel:true` optional). Auflösung Sonntag:
  Pull-Event „Dein Wichtel war Timo!“ (+ kleiner Sticker über den
  Codes-/Reward-Pfad). Panel: Seite mit Ring + Erfüllungs-Status, Knopf
  „Runde neu würfeln“. Client: Karte in der Freunde-App + Shortcut in den
  Post-Schalter.
- **Risiko:** Kleine Gruppen: bei 3 Spielern ist der Ring schnell erratbar —
  egal, der Witz ist das Ritual. Nachzügler mitten in der Woche → erst
  nächste Runde (deterministisch bleiben!). Alte Clients: bekommen weiterhin
  normale Geschenke, sehen nur die Wichtel-Karte nicht (additiv). Quota:
  nutzt bestehende Mail-Limits.
- **Beweis:** Node: Permutation deterministisch + selbstfrei über viele
  Teilnehmer-Mengen (Property-Test-Stil), Erfüllungs-Erkennung, <3 Spieler →
  aus, Wochen-Rollover mit `ctx.clock`. Client: FakeLink-Karte + Wächter,
  dass die Karte ohne WELCOME-Feld nie rendert.

## 10. Foto-Pinnwand als Möbel (InstantGooby an der Wand) [M] (BEIDES)

- **Was:** Neues Möbel „Pinnwand“: bis zu 6 InstantGooby-Posts (eigene und
  von Freunden) anpinnen; Besucher sehen die echte, bestückte Pinnwand im
  Haus — der Foto-Feed bekommt einen Ort in der Welt.
- **Warum (Quelle):** Planner-Denkrichtung „Foto-Pinnwand“; InstantGooby-Feed
  + Blob-Lazy-Load existieren (`mail.js` W13C, `GET /api/mail/blob/:id`),
  Haus-Snapshots reisen sowieso zu Besuchern. Macht Besuche persönlicher,
  komplett asynchron.
- **Wie (Skizze):** Client: FurnitureCatalog-Eintrag + Pin-Sheet (Feed-Grid,
  Auswahl → Save speichert nur `{blobId, from, caption}` je Slot); Bilder
  lazy laden + `user://pinncache/` (offline zeigt Cache, sonst
  Platzhalter-Polaroid). Besucher: Pinnwand-Slots stecken im normalen
  Haus-Snapshot → Gast lädt Blobs selbst nach. Server: ACL-Erweiterung
  nötig — heute darf nur der EMPFÄNGER eines Posts den Blob laden; ein
  Besucher ist Freund des Hosts, aber evtl. nicht des Foto-Autors. Lösung:
  `PIN_REGISTER {blobId}` — der Host (legitimer Empfänger) registriert den
  Blob als „öffentlich für meine Besucher“; `blob/:id`-Route prüft zusätzlich
  diese Freigabe-Map (Collection `pins`, Cap 6/Host, Prune beim Abpinnen).
- **Risiko:** Genau diese ACL ist der heikle Teil (Fotos = User-Content;
  niemals global öffnen, nur Host-Freigabe + `areFriends(host, besucher)`).
  Blob-Lebensdauer: Feed-Ringpuffer (FEED_CAP 30) und Mail-Prune löschen
  Blobs — Pins müssen Blobs am Leben halten (Refcount im Prune) ODER ehrlich
  „Foto verblasst“ zeigen; Refcount ist die saubere Wahl. Alte Clients:
  sehen ein leeres Möbel (Snapshot-Felder unbekannt → ignoriert, Best-Effort-
  Muster von `BUILD_DELTA`).
- **Beweis:** Node: ACL-Matrix (Autor/Empfänger/Host-Besucher/Fremder ×
  vor/nach PIN_REGISTER), Prune-Refcount-Test (gepinnter Blob überlebt
  Feed-Rotation). Client: Pin-Sheet-Wächter, Snapshot-Roundtrip
  (Host pinnt → Gast-Instanz rendert Slot-Metadaten), UI-Wache beide Formate.

## 11. Besuchs-Aktivitäten: Brettspiel-Tisch + gemeinsames Angeln [L] (BEIDES)

- **Was:** Beim Freund echte Dinge TUN: (a) Brettspiel-Tisch als Möbel — im
  Besuch antippen startet Schach/Schiffe mit dem Anwesenden und kehrt danach
  in den Besuch zurück; (b) gemeinsames Angeln am Garten-Teich des Hosts mit
  sichtbaren Fängen + Jubel des anderen; (c) Host-Gooby gemeinsam füttern/
  streicheln (Gast löst Emote+Herz aus, Stat-Wirkung bleibt beim Host).
- **Warum (Quelle):** Planner-Kernfrage „was KANN man beim Freund eigentlich
  tun?“ — heute: laufen, Emotes, Couch, Coop-Fahrt. Die gesamte Infrastruktur
  ist da: `BOARD_INVITE`-Flow komplett, `rooms.js` relayt UNBEKANNTE kinds
  unverändert (im Code von `couch_logic.gd` explizit als geprüft vermerkt) —
  (b) und (c) brauchen also NULL Server-Änderung.
- **Wie (Skizze):** (a) Client-Routing ist die Arbeit: Besuchs-Session halten
  (visit-Room NICHT verlassen), Board-Szene als Overlay-Route, nach
  `BOARD_END` zurück in die Besuchs-Szene an die alte Position (Rooms sind
  serverseitig unabhängig — parallel Mitglied sein geht heute schon).
  (b) `ROOM_MSG kind:FISH {phase:"wurf"|"biss"|"fang", fischId}` — rein
  visuell, Fang-Gutschrift nur lokal beim Angler; (c) `kind:CARE
  {aktion:"streicheln"|"fuettern"}` — Host-Client wendet Stat-Wirkung an
  (Host ist Autorität über seinen Gooby, konsistent mit Haus-Autorität).
- **Risiko:** Szenen-Routing/Zustands-Wiederherstellung ist die eigentliche
  Komplexität (SceneRouter-`_busy`-Falle aus W19 ist dokumentiert!). Alter
  Peer kennt neue kinds nicht → er sieht die Aktion einfach nicht; für den
  Tisch: `BOARD_INVITE` versteht auch ein alter Client (bestehender Typ) —
  nur der Rücksprung in den Besuch fehlt ihm, er landet im Social-Screen
  (degradiert akzeptabel, im Sheet ankündigen). Kein Geld/Item über
  ROOM_MSG (Doc-C-Regel bleibt gewahrt).
- **Beweis:** Node: nur Relay-Smoke (unbekanntes kind kommt durch — existiert
  quasi schon). Client: `visit_logic`-artige pure Tests für FISH/CARE-Payloads
  + Parser-Robustheit; Zwei-Logik-Instanzen im Headless-Test (Muster
  `test_gvz_netz`: FakeLink-Paar relayt kinds hin und her); dauerhafter
  Playtest-Flow Besuch→Tisch→Schiffe→Rückkehr→Angeln, beide Formate.

## 12. Server-Pflege-Paket: Panel-Backup, /api/status, AMP-Runbook [S] (SERVER)

- **Was:** (a) Panel-Knopf „Backup herunterladen“ (ein JSON-Bundle aller
  Collections + Blob-Index), (b) unauthentifiziertes `GET /api/status`
  `{version, proto:{min,max}, features}` für die Client-Kompat-Anzeige,
  (c) README-Runbook: Server-UPDATE auf AMP (Dateien ersetzen ohne `data/`),
  Restore-Probe, Log-Rotation.
- **Warum (Quelle):** README deckt Erst-Deploy gut ab, aber Update-/Restore-
  Prozeduren fehlen (Backup = „Ordner sichern“ setzt SFTP-Zugriff voraus —
  im AMP-Alltag ist ein Panel-Download praktischer). E13-P3 zeigte zudem
  Diagnose-Kleinkram; ein Status-Endpoint macht künftige Protokoll-Sprünge
  („Server-Update nötig“) im Client sauber anzeigbar, BEVOR sie passieren.
- **Wie (Skizze):** (a) `GET /panel/backup.json` (Session-geschützt):
  Collections synchron ge-flusht + als ein JSON gestreamt; Blobs bewusst NUR
  als Index (Fotos können groß sein — Hinweis im Panel „Vollbackup = data/
  sichern“). Kein zip nötig → keine native Dependency (AMP-Regel!).
  (b) `status`-Route in `server.js` neben `/health`, Client zeigt in
  Einstellungen→Mehrspieler „Server v1.4 · Protokoll 1“ und warnt bei
  künftigem `proto.max < CLIENT_PROTO`. (c) Doku-Abschnitte im README.
- **Risiko:** Backup-Download enthält Spieler-Daten (Hashes, Briefe-Index) —
  bleibt hinter Panel-Login; kein CORS, wie gehabt. `/api/status` leakt nur
  Unkritisches (keine Spielerzahlen-Details — `clients` steht eh in
  `/health`). Alte Clients: ignorieren alles (additiv).
- **Beweis:** Node: `panel_pages.test.js`-Muster (Backup nur mit Session,
  Bundle enthält alle registrierten Collections, Restore-Roundtrip in temp-
  `DATA_DIR` bootet und beantwortet HELLO), Status-Schema-Assertion. Client:
  Settings-Anzeige-Wächter mit FakeLink.

## 13. Ranch-Gemeinschaftsprojekt: die Freundes-Scheune [L] (BEIDES)

- **Was:** Ein server-verwaltetes Langzeit-Bauprojekt (Gemeinschaftsscheune /
  Festplatz an der Ranch): Freunde spenden über Tage/Wochen Material (asynchron,
  jeder wann er will), alle sehen den wachsenden Bau, die Fertigstellung
  feiert ein gemeinsames Fest-Event + exklusiven Sticker.
- **Warum (Quelle):** Ranch-MP ist heute rein synchron (Matches/Besuch); die
  Denkrichtung „asynchrone Sozial-Loops“ fehlt der Ranch komplett. Bausteine
  existieren: RMP-Meta-REST (`rmp_ranch_meta.gd`), Events-Push/Pull für die
  Fest-Ansage, Codes-/Reward-Pfad für den Sticker, Balance-Zahlen könnten ins
  `balance`-Pack (Update ohne IPA).
- **Wie (Skizze):** Server: `projekt.js`: Collection
  `{projektId, stufe 0..3, beitraege:{friendCode:{holz,steine,...}},
  zielProStufe}`; `POST /api/projekt/beitrag {materialien, clientId}`
  (idempotent, `restAuth`, nur Freundeskreis = alle bekannten Geräte des
  Servers — der Server IST die Gruppe); Stufen-Übergang → Event an alle
  (Pull-fähig für Offline-Spieler). Client: Bauplatz-Zone auf der Ranch
  rendert Stufe (additive Szene, `ort_requisiten`-Muster aus W19); Spenden-
  Sheet zieht Material aus dem lokalen Inventar VOR dem Senden ab
  (offline-first-Ökonomie-Regel aus Doc C §3.7) und schickt den Beitrag über
  die Outbox; RMP-Hub zeigt Fortschritt + „Timo hat 20 Holz gespendet!“-Ticker.
- **Risiko:** Ökonomie-Abzug vor Server-Bestätigung: bei endgültiger
  Ablehnung MUSS zurückgebucht werden (das `mail_bounced`-Rückbuchungs-Muster
  aus `net_mail.gd` wörtlich übernehmen). Zustands-Autorität: Server hält NUR
  den Projekt-Stand, das Rendering bleibt Client (kein Snapshot-Zwang).
  Balance (wie viel Material pro Stufe) unbedingt ins `balance`-Pack — sonst
  braucht jede Korrektur eine IPA. Alte Clients: sehen den Bauplatz nicht
  (additive Zone), kein Bruch.
- **Beweis:** Node: Beitrag idempotent (clientId-Retry), Stufen-Übergang
  genau einmal + Event-Zustellung an Offline-Gerät (Pull), Crash-Durability
  des Beitrags. Client: Spenden-Sheet-Wächter (Abzug/Rückbuchung),
  Stufen-Rendering-Snapshot-Tests; 2 Spieler headless: zwei `WsClient`s
  spenden im node:test, Godot-Instanz rendert Stufe aus GET-Antwort.

---

## Ehrliche Priorisierungs-Notiz

Reihenfolge folgt (Nutzen für 2–6 Sideload-Freunde) × (Wiederverwendung
existierender Muster) ÷ (Risiko). Die Plätze 1–7 sind bewusst asynchron-lastig
bzw. Reibungs-Killer — das ist die Lücke des sonst starken synchronen Stacks.
GvZ-Coop (Platz 8) ist trotz L hoch einsortiert, weil es ein WÖRTLICHER
User-Wunsch ist (USER-WISHES §G) und die zweite Hälfte des bereits gebauten
PvP; sein Determinismus-Risiko ist der einzige Grund, warum es nicht Top-5 ist.
Foto-Pinnwand (10) hängt an der Blob-ACL-Frage, die Plätze 11/13 sind die
teuersten Client-Brocken. Nichts auf dieser Liste braucht Matchmaking, Skalierung
oder fremde Infrastruktur — alles läuft auf dem einen AMP-Node-Prozess weiter.

# Bereich: Meta-Progression + Technik

# GOOBY-Roadmap — Bereich META-PROGRESSION + TECHNIK/QUALITÄT (Planner-Welle, W19+)

Ist-Bild-Quellen (alle gelesen/verifiziert am Code, Branch `cursor/gooby-godot-loop-d1d8`):
`UserFeedback.md` (komplett), `docs/godot-rewrite/STATUS.md`, `EVAL-VOLLSTAENDIGKEIT.md`,
`H-ui-content.md`, `E1-boot.md`, `E4-perf.md`, `E14-offline.md`, `AUDIO-GRAMMATIK.md`,
Code-Stichproben (`scripts/ui/`, `scripts/state/`, `scripts/audio/`, `scripts/core/`,
`tests/run_tests.gd`, `tests/tools/playtest_harness.gd` + 56 Playtest-Flows, `tools/ci/`).

Kontext-Fakten, auf denen die Priorisierung beruht:

- Meta-Systeme sind BREIT vorhanden (Profil/PASS mit Abschluss-Karte, 44 Erfolge mit
  Fortschrittsbalken, Tagesquests Pool 24, Tagesbonus-Streak, Album 144 Sticker +
  4 Sammlungssets seit W13 sichtbar, Codes, Galerie mit Export, Radio/News, Onboarding-Tour).
  Was fehlt, ist die VERKLAMMERUNG: kein Ort sagt dem Spieler „das mache ich als Nächstes“,
  und die Systeme feiern getrennt statt gemeinsam.
- Technik: Save-Kern ist stark (atomar, 3 Backups, tmp-Recovery — `save_manager.gd` verifiziert),
  aber der Recovery-Hinweis ist seit W14 unverdrahtet (STATUS.md „Bekannte Lücken“, am Code
  bestätigt: `state_loaded(fresh, recovered)` hat keinen Toast-Konsumenten). Die Playtest-
  Infrastruktur ist exzellent (Harness + 56 Flows), läuft aber nur wellenweise von Hand —
  kein Coverage-Bild, kein Dauer-Gate. Ranch-Reveal wurde in W19 von 14,7 s auf 1,9 s gebracht
  (`welt_aufbau_takt.gd` als wiederverwendbares Muster); die Stadt ist der nächste Kandidat
  (E4: Stadt-Übersicht 238–280 Draw Calls, `city_bau.gd` baut synchron).
- W19-Beobachtungen (aus den Berichten übernommen, am Code nachgeprüft):
  (a) `tests/run_tests.gd` parst KEINE CLI-Args — unbekannte Argumente verpuffen still
  (W1a-frozen → nur dokumentieren, nicht ändern);
  (b) „Trautes Heim“-Veil-Karte auf dem Weg zur DLC-Bibliothek: `loading_veil.gd`
  kennt als Trip-Ziele nur `ikea` + `city*` (`TRIP_ZIELE`/`TRIP_PRAEFIXE`), alles andere
  (dlc, ranch-Kurzreisen, park) fällt auf den Home-Modus mit Heim-Artwork zurück;
  (c) einmaliger „Invalid polygon“-Fehler: Wipe forensisch entlastet (2001×9 Fälle,
  0 Degenerationen), Quelle unbekannt → `--verbose`-Stacktrace-Standard empfohlen.

Aufwandsskala: **S** = lokal, 1 Paket · **M** = ein System / mehrere Dateien · **L** = mehrere
Systeme + Content + Integrationsrisiko. Priorität = Spielerwert bzw. Qualitätshebel pro Aufwand.

---

## 1. „Als Nächstes“-Ziel-Karte + Erfolgs-Ketten [M] (META)

- **Was:** EIN sichtbarer „Das mache ich als Nächstes“-Anker: eine kompakte Karte im
  Profil-Kopf + optionaler HUD-Chip, die aus den vorhandenen Systemen das jeweils
  NÄCHSTE greifbare Ziel kürt (fast fertiger Erfolg, fast volle Album-Seite, offene
  Tagesquest, nächstes DLC-/Level-Gate, Sammlungsset kurz vor Abschluss). Dazu
  Erfolgs-KETTEN im Erfolgs-Screen: verwandte Erfolge (10 Fische → 50 Fische →
  Angel-Ass) als sichtbare Leiter mit „Nächstes Ziel“-Pfeil, und der Unlock-Toast
  nennt sofort das Folgeziel.
- **Warum:** Alle Zutaten existieren, aber nichts beantwortet die Spieler-Frage
  „was jetzt?“. Quelle: EVAL-VOLLSTAENDIGKEIT („roter Faden“ bejaht, aber nur über
  Tagesquests/Streak als Leitplanken), Planner-Auftrag „Progressions-Sichtbarkeit“;
  `achievements_screen.gd` zeigt heute Fortschritt pro Zeile, aber keine Ketten und
  kein globales Nächstes-Ziel (am Code verifiziert). `abschluss_logic.gd` liefert
  bereits einen Gesamt-Prozentwert — die Brücke vom Prozent zur konkreten Handlung fehlt.
- **Wie (Skizze):** Pure Logik `naechstes_ziel_logic.gd` (Save-State rein → sortierte
  Kandidatenliste raus; Scoring = Fortschrittsnähe × Belohnungswert, deterministisch,
  headless testbar). Erfolgs-Ketten als `chain`-Feld im 44er-Katalog (additive Daten,
  IDs unangetastet). UI: Profil-Karte nach AcCard-Muster, Toast-Erweiterung im RewardHub.
- **Risiko:** Kein neues Save-Feld nötig (nur Ableitung) → gering. Gefahr der
  Bevormundung: Karte ist Vorschlag, kein Quest-Zwang; max. 1 HUD-Chip (Overlay-Dirigent
  respektieren, W19-Layer-Lektionen).
- **Beweis:** Unit-Tests über Fixture-Saves (leer/mittel/fast fertig → erwartete
  Kandidaten); Playtest-Flow „Profil öffnen → Nächstes-Ziel-Karte tippen → landet im
  richtigen Screen“ quer+hochkant als Dauerwächter.

## 2. Veil-Ziel-Karten-Fix: richtige Reise-Karte für DLC/Ranch/Park [S] (TECHNIK)

- **Was:** Die Szenenwechsel-Karte zeigt fürs Ziel das richtige Artwork/Titel:
  DLC-Bibliothek + DLC-Läden („Goo und Bye“, McGooby), Funkelpark und Ranch-Kurzziele
  werden „trip“ (bzw. bekommen eigene Ziel-Cover), statt als „Trautes Heim“ mit
  Heim-Artwork zu laden.
- **Warum:** W19-Beobachtung (falsches Ziel-Artwork auf dem Weg zur DLC-Bibliothek), am
  Code bestätigt: `loading_veil.gd` `modus_fuer_ziel()` kennt nur `TRIP_ZIELE=["ikea"]`
  + Präfix `city` — alles andere fällt auf „home“ zurück. Deckt sich mit dem seit W17
  wartenden G6-Paket „DLC-Ladebildschirme“ (UserFeedback, Warteschlange Wellen J+).
- **Wie (Skizze):** Ziel→Karten-Registry statt der zwei Konstanten: kleine Tabelle
  `{ziel_praefix: {modus, titel_key, cover_pfad}}` (dlc, park, goobye, mcgooby, ranch-
  Kurzreisen; Fallback bleibt exakt heutiges Verhalten). 2–3 Ziel-Cover im Alt-Web-
  Kartenlook (Assets existieren teils als DLC-Coverarts aus W14).
- **Risiko:** Sehr gering — reine Anzeige-Weiche; `test_ui_veil.gd` pinnt das
  Home-Verhalten bereits, neue Fälle kommen dazu. Lange-Reise-Regel (RanchLoadingScreen)
  nicht anfassen.
- **Beweis:** Erweiterter `test_ui_veil.gd` (je Ziel: erwarteter Modus/Titel/Cover);
  Playtest-Screenshot der DLC-Reise vorher („Trautes Heim“) vs. nachher (DLC-Karte).

## 3. Stadt-Reveal: Messung + Time-Slicing nach dem Ranch-Muster [M] (TECHNIK)

- **Was:** Dieselbe Kur, die in W19 den Ranch-Reveal von 14,7 s auf 1,9 s kalt gebracht
  hat, für die Stadt: erst Phasen-Messung des Stadt-Aufbaus (`city_bau.gd`: Boden/
  Straßen/Fassaden/Kulisse/Ampeln + Verkehr/Fußgänger aus `city_scene.gd`), dann — nur
  wo die Messung es rechtfertigt — Essenz-vor-Reveal + Rest-Streaming über
  `welt_aufbau_takt.gd` (30-ms-Scheiben, injizierbare Zeitquelle, existiert schon).
- **Warum:** Muster + Werkzeug sind seit W19 da und bewiesen (Commit 222aa184:
  Phasen-Messung → Slicing → 8 Perf-Wächter). Die Stadt ist der schwerste verbliebene
  Einstieg: E4-perf maß 482–520 Nodes / 238–280 Draw Calls in der Übersicht, und der
  SceneRouter-Hard-Timeout (10 s, `scene_router.gd` verifiziert) ist genau die Falle,
  die bei der Ranch auf schwacher Hardware JEDEN Eintritt traf. Quelle: W19-Bericht
  („Ranch-Welt-Time-Slicing als Muster für andere schwere Szenen — Stadt?“) + E4.
- **Wie (Skizze):** (1) Wegwerf-Phasenmessung wie beim Ranch-Paket (Zeit je Bau-Schritt
  ins Log); (2) falls Reveal-Budget gerissen: Essenz = Boden/Straßen/Fassaden im
  Spawn-Radius + Licht + HUD, Kulissen-MultiMeshes/Kleinteile/Verkehr streamen nach
  Spawn-Nähe sortiert nach; (3) Bit-Identitäts-Wächter (Stadt-Struktur vorher/nachher
  gleich — Node-Zahl + deterministische Positionen), Budget-Test analog den 8
  Ranch-Wächtern.
- **Risiko:** Mittel — Verkehr/Fußgänger/Ampeln hängen an Bau-Ergebnissen
  (`colliders`, `ampel_lookup`); Streaming darf Gameplay-Kollisionen nicht nachliefern
  (Kollisions-Essenz gehört VOR den Reveal). Ehrlich: wenn die Messung zeigt, dass die
  Stadt schon unter Budget liegt, endet das Paket als Messbericht + Wächter (auch wertvoll).
- **Beweis:** Messung vorher/nachher (reveal-ms kalt/warm wie beim Ranch-Commit),
  0 Hard-Timeout-Treffer im `lauf.log` eines Stadt-Playtest-Flows, Draw-Call-Zähler
  E4-Methodik vorher/nachher.

## 4. Flow-Coverage-Report + Nightly-Flow-Gate (+ Runner-Doku) [M] (TECHNIK)

- **Was:** Die 56 Playtest-Flows werden von der Hand-Welle zur Dauer-Instanz:
  ein Sammel-Runner (`tools/ci/run_all_playtests.sh`) fährt alle Flows parallel
  (bestehende Isolation nutzen), sammelt Exit-Codes + Schritt-FAILs und erzeugt einen
  **Coverage-Report**: welche Router-Routen/Screens/Minispiele von mindestens einem
  Flow besucht werden vs. Register (SceneRouter-Routen, Minigame-Registry) — die
  „weißen Flecken“-Liste ist das eigentliche Produkt. Dazu: alle Flow-Läufe standardmäßig
  mit `--verbose`, damit Einmal-Fehler wie „Invalid polygon“ (W19, Wipe entlastet,
  Quelle unbekannt) beim nächsten Auftreten einen Stacktrace hinterlassen. PLUS reine
  Doku-Pflicht: `tests/run_tests.gd` ignoriert unbekannte CLI-Args still — W1a-frozen,
  also NICHT ändern, sondern im Datei-Kopf + `tools/ci/README.md` dokumentieren
  („Filter gibt es nur über `tests/tools/run_subset.gd`“).
- **Warum:** Preflight kennt die Flows nicht (verifiziert: `preflight.sh` ruft nur die
  zwei Unit-Runner + Boot-Smoke), Flows laufen nur, wenn eine Welle daran denkt —
  Regressionsschutz hängt an Disziplin statt Infrastruktur. Quelle: Planner-Auftrag
  („Flow-Coverage-Report“), W19-Beobachtungen (a)+(c), Harness-Doku (Kopf von
  `playtest_harness.gd` beschreibt Parallel-Betrieb bereits).
- **Wie (Skizze):** Runner-Skript (Shell) + kleiner GDScript-Auswerter, der die
  report.md-Dateien + Router-Routen-Dump zu EINEM `coverage.md` verdichtet (Tabelle
  Route × Flow × Status). Kein CI-Zwang für jeden Push (llvmpipe-Laufzeit!) —
  als Nightly/vor-Release-Gate und als Ein-Kommando-Werkzeug für Wellen.
- **Risiko:** Gering-mittel: Laufzeit (56 Flows × ~2–10 min llvmpipe) → Parallelität
  + „nur geänderte Bereiche“-Filter; Flaky-Flows verwässern das Gate → Pflicht/
  auffällig-Flag existiert schon pro Schritt.
- **Beweis:** Erster Coverage-Report mit ehrlicher Lücken-Liste (erwartbar: Settings-
  Unterseiten, Codes, Galerie-Export, einzelne Minispiele); danach messbar steigende
  Abdeckung pro Welle. Vorher/nachher: „Flows gelaufen in W19: 6 neue per Hand“ vs.
  „alle 56 automatisch mit einem Kommando + Report“.

## 5. Save-Vertrauen sichtbar machen: Recovery-Hinweis + Outbox-Härtung [S] (TECHNIK)

- **Was:** (a) Der seit W14 dokumentiert unverdrahtete Recovery-Hinweis wird verdrahtet:
  bootet das Spiel aus Backup/tmp (`state_loaded(fresh, recovered=true)`), sagt ein
  warmer Toast „Spielstand aus Sicherung wiederhergestellt“ (String
  `system.recovered_backup` existiert). (b) Die Netz-Outbox bekommt die gleiche Würde
  wie der Save: bei Parse-Fehler nicht mehr stillschweigend leer starten
  (`outbox.gd`: „kaputt — starte leer“, verifiziert), sondern `.corrupt`-Sicherung +
  1-Generationen-Backup nach Save-Manager-Muster.
- **Warum:** STATUS.md listet den Toast explizit als bekannte Lücke („String + Signal
  existieren, kein Konsument“ — am Code bestätigt: nur `reward_flug.gd` konsumiert
  `state_loaded`, für Baselines); E14-offline P2-2 benennt den Outbox-Datenverlust.
  Save-Robustheit ist stark — aber unsichtbar; Vertrauen entsteht, wenn Rettung
  sichtbar ist.
- **Wie (Skizze):** Konsument im HomeEntry/Boot-Pfad (nach Overlay-Dirigent-Regeln
  einreihen, W19-Lektion: nie roh über Overlays legen); Outbox: `_load()`-Fehlerpfad
  um corrupt-Kopie + bak-Versuch erweitern (~30 Zeilen, Testmuster aus
  `test_net_outbox.gd` erweitern).
- **Risiko:** Minimal; einzig Toast-Timing beim Erststart (fresh=true zeigt natürlich
  nichts).
- **Beweis:** Unit-Test: korrupter Save + gültiges bak1 → Boot + Toast-Eintrag in der
  Queue; korrupte Outbox → Einträge aus bak wiederhergestellt statt 0. Screenshot des
  Toasts im Playtest.

## 6. Wochen-Album-Seite: „Deine Woche mit Gooby“ [M] (META)

- **Was:** Jeden Sonntag (bzw. auf Abruf im Album) komponiert sich eine Wochen-Seite
  automatisch: bestes Foto der Woche (Galerie), neue Sticker, geschlagene Rekorde/
  Geister, Quest-/Bonus-Streak, 1 „Moment der Woche“ (Soul-Erinnerung) — als
  teilbare Karte im Alt-Web-Kartenlook, exportierbar über den bestehenden Foto-Export.
- **Warum:** Planner-Auftrag nennt die Wochen-Album-Seite als Verklammerungs-Kandidat;
  ALLE Zulieferer existieren bereits (Galerie mit Export, Recap-System
  `scripts/recap/` mit Historie, Sticker-Unlock-Zeitstempel, daily-Streak,
  Geister-Rekorde seit W19) — es fehlt nur der Sammler. Zahlt direkt auf „EIN
  Gooby-Spiel statt einzelner Features“ ein (User-Feedback 1.8.).
- **Wie (Skizze):** Pure `wochen_seite_logic.gd` (Save-State + Galerie-Index +
  Recap-Historie rein → Seiten-Modell raus, deterministisch je Kalenderwoche);
  Album-Tab „Wochen“ nach Chip-Leisten-Muster; Export über den vorhandenen
  Galerie-Export-Pfad.
- **Risiko:** Leere Wochen (nichts passiert) → ehrlicher Leerzustand mit Gag
  („Diese Woche: hauptsächlich geflauscht.“); Zeitzonen-/Wochen-Grenzfälle über die
  vorhandene Lokaltag-Logik (Tagesbonus) lösen, nicht neu erfinden.
- **Beweis:** Unit-Tests mit Fixture-Wochen (voll/leer/nur-Fotos); Playtest-Flow
  Album → Wochen-Seite → Export, Screenshot der komponierten Karte.

## 7. Sammlungs-Vitrine im Haus [M] (META)

- **Was:** Ein baubares Möbel „Vitrine“ (IKEA), das die 4 Sammlungssets
  (Fische/Gemüse/Sehenswürdigkeiten/Leckereien) als echte 3D-Miniaturen im Raum
  ausstellt — gefüllte Slots zeigen das Sammelstück, leere einen Platzhalter;
  Tap öffnet die Set-Ansicht im Album. Komplettierte Sets bekommen ein kleines
  Vitrinen-Licht.
- **Warum:** Die Sets sind seit W13 im Album sichtbar UND komplettierbar (W15: alle 4),
  aber im Spielraum unsichtbar — Sammeln zahlt nicht aufs Haus ein. Der Planner-Auftrag
  nennt die Vitrine explizit; das Souvenirregal (Postkarten/EVAL Zeile 40) beweist
  das Muster bereits für Reisen.
- **Wie (Skizze):** Möbel-Katalog-Eintrag + `vitrine.gd` als Interactable nach
  Souvenirregal-Muster; Miniaturen aus vorhandenen Assets (Fisch-/Gemüse-/Speisen-GLBs
  existieren im Katalog); Befüllung ist reine Save-Funktion (`collections.entries`).
- **Risiko:** Asset-Lücken bei einzelnen Sammelstücken → Fallback-Miniatur (Sticker-
  Bild auf Kärtchen); Draw-Calls im Raum (E4: Räume 30–63 Calls, Puffer vorhanden;
  Miniaturen als EIN MultiMesh je Vitrine).
- **Beweis:** Unit-Test Befüllung aus Fixture-Save; Orientierungs-Audit 0 Befunde;
  Vorher/Nachher-Screenshot Wohnzimmer + Draw-Call-Zählung nach E4-Methodik.

## 8. Tagesquest-Pool auf Web-Parität+ und neue Inhalte verquesten [S] (META)

- **Was:** Quest-Pool von 24 auf 28+ (Web-Parität und darüber): die fehlenden 4
  Web-Quests prüfen/portieren und NEUE Quests für die seit W17 gelandeten Inhalte
  ergänzen (McGooby-Schicht, Goobye-Ladentag, Ranch-Entdecker-Pin, Spotlight-Runde,
  Geist schlagen) — Tagesquests bleiben so der Verteiler, der Spieler in die neuen
  Systeme schickt.
- **Warum:** EVAL Zeile 24: „Pool 24 Quests (Web: 28)“ — am Content verifiziert
  (`content/quests/data/quests.json`: 24 items). Die W17–W19-Inhalte (2 DLCs,
  Spotlight, Geister, Karte) tauchen im Tagesloop nicht auf; genau dafür ist der
  Quest-Katalog deklarativ gebaut.
- **Wie (Skizze):** Reine Datenarbeit + ggf. 2–3 neue Counter-Hooks (Quest-Engine
  wertet Save-Zähler aus; McGooby/Goobye führen ihre Zähler schon für Erfolge/Level).
  DLC-Quests nur würfeln, wenn DLC gekauft (Katalog-Gate-Feld).
- **Risiko:** Gering; einzig Pool-Balance (DLC-Besitzer vs. nicht) → Gate-Feld + Test,
  dass Nicht-Besitzer nie DLC-Quests ziehen.
- **Beweis:** `test_rest2_quest_engine.gd`-Erweiterung (Pool-Größe, Gate-Regel,
  deterministischer Tages-Roll mit/ohne DLC); DE/EN-Paritäts-Check läuft automatisch mit.

## 9. Barrierefreiheits-Gate: Textgrößen-, Reduced-Motion- und Haptik-Audit [M] (TECHNIK)

- **Was:** Barrierefreiheit von „Einstellung existiert“ zu „Einstellung ist bewiesen“:
  (a) der W1c-UI-Audit läuft zusätzlich mit maximaler UI-Skalierung (130 %) über die
  34+ Screens und wertet Clipping/Overflow als Befund (die Wortabschneide-Klasse
  Bugs aus dem 1.8.-Feedback strukturell verhindern); (b) ein Tripwire-Test nach dem
  Muster des Timer-Lambda-Wächters scannt neue Tween-/Partikel-Stellen auf fehlende
  Reduced-Motion-Weichen; (c) Haptik-Grammatik-Wache (`test_w16_sound_haptik.gd`)
  wächst auf die W17–W19-Screens (DLC-Läden, Karte, Spotlight).
- **Warum:** Reduced Motion, Haptik-Stärke (W16 F11) und UI-Skalierung existieren
  zentral (`app_settings.gd` verifiziert), aber nur der Standard-Zustand wird
  flächig geprüft — die 130-%-Wrap-Probleme waren laut H-Doc genau der alte
  Web-Fehler („Wrap-Chaos bei uiScale 130“). Quelle: Auftragsbereich + H-ui-content
  §1.3 + AUDIO-GRAMMATIK (Wache wächst „wellenweise“ — das ist der nächste Schritt).
- **Wie (Skizze):** UI-Audit-Parameter `ui_scale=1.3` als zusätzlicher Durchgang
  (Screens × Formate × 2); Reduced-Motion-Tripwire als Quelltext-Scan mit Allowlist
  (bewährtes Muster aus `test_rest5_bugfixes.gd`); Haptik-Scan-Liste erweitern.
- **Risiko:** Erstlauf findet echte Befunde (gewollt!) → als eigene Fix-Liste
  einplanen statt das Gate aufzuweichen; Scan-False-Positives über Allowlist.
- **Beweis:** Audit-Zahlen vorher/nachher („Screens × Formate × Skalen = 0 Befunde“);
  je ein Vorher/Nachher-Screenshot eines 130-%-Fundes.

## 10. Audio-Feinschliff: Klangbetten für DLC/Park + Kontext-Lücken schließen [M] (TECHNIK)

- **Was:** Das W18-Klangbett-System auf die neuen Welten ausdehnen: eigene Betten-Ebenen
  für die DLC-Läden (Kühltheken-Summen + Kassen-Raumton im Goobye-Laden,
  Grill-/Fritteusen-Brutzelbett bei McGooby), Funkelpark-Fahrgeschäft-Ferne, sowie die
  Ort→Bett-Tabelle für alle Ziele vervollständigen, die heute stumm durchrutschen.
  Dazu der seit W17 wartende „Audio-Feel“-Posten aus der G6-Warteschlange.
- **Warum:** `klangbett.gd` verifiziert: `ORT_BETTEN` kennt Heim/Stadt/3 Orte/IKEA/
  Arcade — die DLC-Ziele (die inhaltlich größten Neubauten seit W17) haben KEIN
  eigenes Bett und laufen über den Laden-Fallback oder behalten das alte Bett.
  Quelle: UserFeedback (G6-Warteschlange „Audio-Feel“), AUDIO-GRAMMATIK (Pegel-/
  Manifest-Regeln machen das Paket risikoarm).
- **Wie (Skizze):** 3–4 neue CC0-Loops über die bestehende Synthese-Pipeline
  (`tools/audio/gen_klangbetten.py`), Ebenen in `EBENEN_IDS` + Tabelleneinträge;
  Pegel nach Grammatik (eff. ≈ −34…−36 dBFS), `ef2_manifest.py` + `test_ef2_audio_levels`
  halten die Mischung; Ducking/Takt-Mathe bleibt unberührt (pur + getestet).
- **Risiko:** Gering — additiv; einzige Falle: DLC-Szenen mit eigener Foley
  (Kassen-Piep aus OrtLeben) nicht doppeln → Abgrenzungsregeln stehen im Klangbett-Kopf.
- **Beweis:** `test_j5_klangbett.gd`-Erweiterung (Ziel→Bett-Erwartung je DLC-Route,
  Pegel-Manifest grün); Playtest-`debug_dump()`-Beweis, dass beim Laden-Betreten das
  richtige Bett fährt (Muster existiert).

## 11. GOOBY-Wochenpass: 7-Tage-Ziele als Klammer über allem [L] (META)

- **Was:** Eine leichte Wochen-Progression im GOOBY-PASS: 5–7 Wochenziele
  (deterministisch gerollt, z. B. „3 verschiedene Minispiele“, „2 Ranch-Zonen
  besuchen“, „1 Gericht bei McGooby perfekt“), die auf eine Wochen-Belohnungsleiste
  einzahlen (Münzen → seltener Sticker → 1 exklusives Cosmetic pro Monat).
  KEIN Kauf-Pass, kein FOMO-Druck: verpasste Wochen verfallen ohne Strafe,
  die Leiste ist klein (3 Stufen).
- **Warum:** Tagesbonus + Tagesquests takten den Tag, aber zwischen Tag und
  Langzeit-Abschluss-Karte (Level 40 / 100 %) klafft die Wochen-Ebene — genau die
  Lücke, die der Planner-Auftrag mit „Meta-Loops die alles verklammern“ meint.
  Verzahnt sich mit Idee 1 (Nächstes-Ziel) und Idee 6 (Wochen-Album-Seite: der
  Pass-Abschluss ist ihr Höhepunkt).
- **Wie (Skizze):** Neuer Save-Slice `weekly` (additive Migration nach bestehendem
  Muster), Roll-Logik als pure Funktion (Kalenderwoche + Seed → Ziele; Quest-Engine-
  Vokabular wiederverwenden: counter/special/event), PASS-Seite im Profil,
  Belohnung über RewardHub + Overlay-Dirigent.
- **Risiko:** Größtes Paket des Bereichs: Balance (Ziele müssen in ~30 min Wochenspiel
  schaffbar sein), Zeit-Kantenfälle (Uhr zurückstellen — Fuzz-Muster aus dem
  Save-Fuzzer nutzen), Gefahr der Verpflichtungs-Optik → Texte warm halten,
  Standard-Zustand ist „nettes Extra“.
- **Beweis:** Deterministische Roll-Tests (Woche+Seed → Ziele, DLC-Gates),
  Zeitreise-Fuzz (30 Tage offline, Wochenwechsel mitten in Session), Playtest-Flow
  „Woche erfüllen → Leiste claimen“ mit Save-Beweis.

## 12. Screenshot-Diff-Wache: Golden-Screens gegen Layout-Regressionen [L] (TECHNIK)

- **Was:** Für die wichtigsten ~20 Screens (HUD, Tagesquests-Blatt, Album, Profil,
  DLC-Hub, Veil-Karten, Results …) werden Golden-Screenshots im Leitformat (quer +
  hochkant) eingefroren; ein Diff-Werkzeug vergleicht neue Läufe perzeptuell
  (Toleranz-Masken für animierte Zonen) und schlägt bei strukturellen Abweichungen
  an — die Klasse „Karte liegt UNTER dem HUD“ / „Chip offscreen“ (5 der 8
  W19-Playtest-Funde!) würde automatisch gefangen statt erspielt.
- **Warum:** Der geometrische UI-Audit prüft Anker/Überlappungs-REGELN, aber nicht
  das gerenderte Ergebnis; die W19-Funde (Layer-Fallen, Kritzelschild hinter Chips,
  Pins neben Fundorten) waren alle im Pixel sichtbar. Quelle: Planner-Auftrag
  („Screenshot-Diff-Wache“), UserFeedback W19 Welle 2/3.
- **Wie (Skizze):** Screenshot-Fahrer existiert (Harness/Audit machen es längst);
  neu sind (a) stabile Szenen-Präparation (fester Seed, feste Uhr, Animationen
  eingefroren — Muster `stunde_override` im Veil), (b) Diff-Skript (Python,
  Block-SSIM + Masken-PNGs), (c) Golden-Verwaltung mit bewusstem „Golden erneuern“-
  Kommando im Werkzeug.
- **Risiko:** Hoch auf llvmpipe: Font-Rendering/Dither-Rauschen → Toleranzen und
  Masken nötig, sonst Flake-Hölle; Goldens veralten bei gewollten Redesigns →
  Erneuern muss EIN Befehl sein, sonst umgeht es jede Welle. Ehrlich: als
  Nightly-/Wellen-Werkzeug einführen, NICHT als Push-Gate, bis die Flake-Rate
  bewiesen niedrig ist.
- **Beweis:** Rot-vor-grün: einen der gefixten W19-Layer-Bugs künstlich
  reaktivieren → Diff schlägt an; danach 5 Läufe in Folge ohne False-Positive
  (Flake-Messung als Abnahmekriterium).

## 13. iPhone-Referenz-Profiling + Perf-Trend-Budget [L] (TECHNIK)

- **Was:** Das seit STATUS.md offene „echtes iPhone-Profiling“ endlich strukturieren:
  (a) ein eingebautes, abschaltbares Telemetrie-Panel (Boot-Phasen-Zeiten aus dem
  vorhandenen BootPhasen-System, Reveal-Zeiten je Route, FPS-Perzentile je Szene)
  schreibt einen `perf_report.json` in die Galerie-/Export-Ecke, den der User mit
  zwei Taps teilen kann; (b) headless ein Perf-Trend-Gate: die E4-Zähler
  (Draw Calls/Tris/Materials je Kernszene) als Budgets-Test, damit Draw-Call-Risse
  wie GvZ (866 vs. 250, E4) nie wieder unbemerkt wachsen.
- **Warum:** Alle bisherigen Zahlen sind llvmpipe-Proxys (E4 sagt das selbst:
  „FPS-Spalte NICHT iPhone-aussagekräftig“); die einzige echte Gerätequelle ist der
  User mit Sideload-.ipa — dem muss das Spiel die Messung abnehmen. STATUS.md listet
  Geräte-Profiling als User-Action-Lücke; W15 baute bereits HDR-Auto-Downgrade,
  ohne je echte Gerätekurven gesehen zu haben.
- **Wie (Skizze):** `perf_probe.gd`/`perf_overlay.gd` (existieren in `scripts/dev/`)
  zu einem Session-Rekorder erweitern (Ring-Puffer, kein Dauer-I/O); Export über den
  bestehenden Foto-Export-Pfad (Zip/JSON); headless: E4-Messtreiber als
  wiederholbaren Test mit Budget-Asserts aus `A-engine.md` §7 einchecken.
- **Risiko:** Geräte-Schleife braucht den User (ehrlich: ohne seine Reports bleibt
  Teil (a) ungenutzt) → Teil (b) liefert unabhängig davon Wert; Telemetrie darf
  selbst nichts kosten (nur bei aktivem Schalter sammeln).
- **Beweis:** Teil (b): Budget-Test rot bei künstlichem Material-Leak (rot-vor-grün),
  Trend-Tabelle je Kernszene im CI-Artefakt. Teil (a): perf_report.json einer
  llvmpipe-Session als Formatbeweis + Doku-Abschnitt „So schickst du mir eine
  Perf-Messung vom iPhone“ in UserFeedback/IOS-BUILD.

---

## Verteilung + ehrliche Priorisierungslogik

| Größe | Ideen |
|---|---|
| S (3) | 2 Veil-Karten · 5 Recovery/Outbox · 8 Quest-Parität |
| M (7) | 1 Nächstes-Ziel · 3 Stadt-Reveal · 4 Flow-Coverage · 6 Wochen-Album · 7 Vitrine · 9 A11y-Gate · 10 Klangbetten |
| L (3) | 11 Wochenpass · 12 Screenshot-Diff · 13 iPhone-Profiling |

Priorisierung: vorne steht, was mit wenig Aufwand sichtbaren Spielerwert oder
dauerhafte Qualitätssicherung kauft (1–5); Mitte = Verklammerungs- und Fleiß-Pakete
mit klarem Muster (6–10); hinten die großen Brocken, die sich auf die vorderen
stützen (11 braucht 1+6, 12/13 brauchen stabile Messgrundlagen). Bewusst NICHT
aufgenommen: run_tests.gd-Umbau (W1a-frozen — nur Doku, in Idee 4 enthalten) und
ein weiterer „Invalid polygon“-Jagdversuch (Wipe entlastet, ohne Repro kein
sinnvolles Paket — der `--verbose`-Standard in Idee 4 ist die richtige Falle).
