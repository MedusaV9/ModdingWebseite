# G8-IDEEN — HOME/HAUS + GOOBY-SEELE (Ideen-Planner IP-1, Welle I)

Bereich: Haus/Räume/Garten-Anschluss + Goobys Innenleben (Emotionen, Laune,
Erinnerungen, Dialoge, Idle-Verhalten, Tagesrhythmus).
Basis: Stand nach Welle **G7 „Spielgefühl"** (`git log` bis `ec242ee3`), gelesene
Quellen: `UserFeedback.md` (komplett), `docs/godot-rewrite/D-house.md`, `F-gooby.md`,
Code-Streifzug durch `GOOBY-GODOT/scripts/soul/*`, `scripts/home/*`,
`content/soul/data/soul.json`, `strings/de/soul_lines.json`.

**Was der User liebt (aus UserFeedback.md destilliert):** Liebe zum Detail,
Treue zur alten Web-Version, Dopamin-Momente (Konfetti, Zähl-Animationen,
Rekord-Feiern), warme deutsche Texte mit Gooby-Witz, „EIN Spiel"-Gefühl statt
Feature-Sammlung, Läden/Orte die LEBEN. Kritisiert wurde: Dev-Demo-Gefühl,
leere Orte, UI-Details die abreißen. → Alle Ideen unten zahlen auf „das Haus
ist ein Zuhause und Gooby ist ein Mitbewohner" ein — keine neuen Systeme um
der Systeme willen, sondern Sichtbarkeit + Rituale + Überraschung auf dem,
was schon da und getestet ist.

---

## TOP-3-EMPFEHLUNG

**1. Platz — Idee 1 „Morgen- & Abend-Ritual":** Der stärkste Hebel fürs
Tamagotchi-Herz. ACNH lebt von Tages-Ankern („einmal am Tag passiert etwas
Besonderes"), und GOOBY hat bereits ALLE Bausteine dafür gebaut aber nie
verknotet: `wake_morning`-Cutscene, Bett-Panel, Tagesbonus, Tagesquests,
`SoulService`-Grüße, `HomeLicht`-Tageszeit. Ein inszenierter Morgen-Moment +
eine Gute-Nacht-Miniroutine machen aus „App öffnen" ein „nach Hause kommen"
— täglicher Dopamin-Loop, null neues Balancing-Risiko.

**2. Platz — Idee 2 „Stimmungs-Herz im HUD":** SEELE-2 hat eine träge,
durchdachte Laune (0..100, Bänder, färbt Gesicht/Ohren/Stimme) — aber der
User kann sie nur erahnen. Ein kleines Herz am „Wo ist mein Gooby?"-Chip +
ein warmes „So geht's Gooby"-Blatt macht das komplette Innenleben ERST
sichtbar und damit die ganze bisherige Seelen-Arbeit erlebbar. Kleinster
Aufwand der Top-3, sofort spürbar, macht auch Playtests lesbarer.

**3. Platz — Idee 3 „Andenken-Regal":** Erinnerungen (`SoulMemories` baut sie
aus ECHTEN Save-Daten) werden physisch: ein Regal, auf dem Muschel, Pokal,
Streak-Kerze von selbst erscheinen. Das ist Liebe zum Detail + sanfte
Home-Progression + Foto-Motiv in einem — und es macht den Kern-Claim des
Spiels („Gooby erinnert sich an euch") zum Möbelstück.

---

## Priorisierte Ideenliste

### 1. Morgen- & Abend-Ritual — der Tag bekommt Klammern
**Aufwand: M · Impact: 5 · Risiko: niedrig**

Morgens (erster Hausbesuch des Tages, bzw. nach `wokeUp`-Ticker): kurze,
skippbare Inszenierung statt loser Einzelteile — Vorhang-/Licht-Sweep
(`HomeLicht`-Lerp von Nacht auf Morgenprofil), Gooby streckt sich
(`wake_up`-Clip läuft schon im `PflegeRunner`), watschelt ans Fenster, EIN
Satz Tagesausblick, der ECHTE Daten mischt: heutiges Wetter (`SoulWetter`
ist pro Tag deterministisch!), offener Wunsch („Heute vielleicht…
Funkelpark?") oder eine Tagesquest. Danach öffnet sich der Tagesbonus als
Teil der Szene statt als Schleier davor (behebt nebenbei den
Playtest-Befund „unsichtbarer Tagesbonus-Schleier schluckt Taps"). Abends
(ab ~20 Uhr, `SoulIntent.absicht_muede` feuert ohnehin): Gooby initiiert die
Routine sichtbar — er löscht auf dem Weg zum Bett selbst eine Lampe
(`lampen_schalter.gd` existiert), das Bett-Panel (`bett.gd`) bekommt oben
eine Mini-Tagesbilanz („Heute: 2× gefüttert, 1 Rekord, 14 Streichler" aus
`achievements.counters`/`soul.foodGiven`), und die Gute-Nacht-Zeile
(`alltag_gutenacht`-Def existiert) bezieht sich auf das Highlight des Tages.
Code-Anker: `scripts/home/sleep/pflege_runner.gd` (wake-Inszenierung),
`scripts/home/interactables/bett.gd`, `scripts/soul/soul_service.gd`
(`decide_enter` Prioritätsstufe „Ritual"), `scripts/home/home_licht.gd`.
Risiko: Reihenfolge-Konflikte mit Onboarding/Tagesbonus-Overlays — das
Overlay-Stau-Thema aus dem Playtest-Report zuerst fixen.

### 2. Stimmungs-Herz im HUD + „So geht's Gooby"-Blatt
**Aufwand: S–M · Impact: 5 · Risiko: sehr niedrig**

Ein kleines pulsierendes Herz (Farbe nach `SoulMood.band()`: mint=selig,
creme=zufrieden, grau-blau=miesepetrig) sitzt am „Wo ist mein Gooby?"-Chip
bzw. an der Status-Leiste. Tap → PanelSheet „So geht's {gooby}" mit dem
Band als warmem Satz plus dem WARUM: der dominante Stats-Treiber wird
benannt („Sein Bauch knurrt ein bisschen" bei niedrigem Hunger-Stat,
Ableitung aus `Stats.mood`-Inputs), dazu der aktuelle Wunsch (falls offen)
und die letzte gezeigte Erinnerung. Wichtig: KEINE nackten Zahlen/Balken für
die Laune — nur Worte und das Gesicht (Web-Treue: die Stats-Pillen bleiben
wie sie sind, die Laune bleibt Gefühl statt Meter). Der Moment, in dem die
Laune das Band wechselt, bekommt einen Mikro-Moment (Herz hüpft + leiser
Ton), damit Pflege sich sofort lohnt. Code-Anker: `scripts/ui/hud.gd` +
`hud_status_sheet.gd` (Sheet-System aus G7-P53 wiederverwenden),
`scripts/soul/soul_mood.gd` (`band`, `ausdruck`), `SeeleRunner.wert()`.
Risiko: HUD-Platz im Leitformat 2868×1320 — an die G7-HUD-Dynamik
(`hud_sichtbarkeit.gd`) anschließen, damit das Herz im Baumodus mit weggleitet.

### 3. Andenken-Regal — Erinnerungen zum Anfassen
**Aufwand: M · Impact: 5 · Risiko: niedrig**

Ein neues Möbel „Erinnerungs-Regal" (FurnitureCatalog, `mandatorySlot` nein,
günstig oder Onboarding-Geschenk): auf seinen 3–5 Plätzen erscheinen
AUTOMATISCH kleine Trophäen, sobald die zugehörige Erinnerung real wird —
Muschel nach dem ersten Urlaub (`vacation.visited`), Mini-Pokal beim ersten
Minispiel-Rekord (`minigames.legacy.best`), Kerze ab 7-Tage-Streak
(`daily.streak`), Gießkännchen ab 10 Ernten, Funkelpark-Schneekugel. Tap auf
ein Andenken → Gooby watschelt hin und erzählt die passende Zeile aus dem
VORHANDENEN Erinnerungs-System (`SoulMemories.candidates` liefert exakt
diese Ids schon heute). Neue Andenken ploppen mit Hammer-Puff + Funkeln ein
und Gooby entdeckt sie beim nächsten Idle („OH! Das kenn ich!"). Das ist
sichtbare Progression im Home-Bereich ohne neues Grind-System — es füllt
sich durchs normale Spielen. Code-Anker: `scripts/soul/soul_memories.gd`
(Kandidaten-Ids 1:1 als Trophäen-Trigger), `scripts/home/furniture_catalog.gd`
+ `furniture_node.gd` (SURFACE-Mini-Grid), `scripts/home/gooby_reactions.gd`
(Idle-Akt „Andenken angucken"). Risiko: braucht 5–8 kleine Props (Blender-
Pipeline nach F-Doc-Muster, prozedural machbar).

### 4. Fenster-Momente — das Diorama lebt nach Uhrzeit
**Aufwand: M · Impact: 4 · Risiko: niedrig**

Das `StreetDiorama` hat Autos und Wetter-FX — jetzt bekommt es einen
Tagesplan mit Mini-Ereignissen, deterministisch pro Tag (Seed-Muster von
`SoulWetter`/`ort_leben.gd` übernehmen): morgens um 9 hält das Postauto
(Alwin-Prinzip: verlässliche Figuren schaffen Bindung — `car-kit` hat
`delivery.glb`), nachmittags schlendern 2 Nachbar-Goobys vorbei (Silhouetten
nach `ikea_schaufenster.gd`-Muster, spottbillig), abends gehen nacheinander
warme Fenster in den Nachbarhäusern an, nachts fällt selten (~10 %
der Nächte, 1×) eine Sternschnuppe. Gooby reagiert darauf über das
VORHANDENE Idle-System (`idle_fenster` existiert): er winkt dem Postauto,
und bei der Sternschnuppe ruft er dich („SCHNELL! Wünsch dir was!") — Tap
aufs Fenster in 10 s = gemeinsamer Wunsch-Moment, der in `soul.wunsch`
einzahlt. Code-Anker: `scripts/home/street_diorama.gd` (`stunde_override`
für Tests existiert bereits!), `scripts/home/garten_diorama.gd`,
`content/soul/data/soul.json` (neue `ueberraschung`-Defs). Risiko: Draw-Call-
Budget der Dioramen im Blick behalten (geteilte Materialien wie in G7-P55).

### 5. Mitbewohner-Spuren — Gooby war hier
**Aufwand: M · Impact: 4 · Risiko: niedrig**

Kommt man nach Abwesenheit (>2 h, `SoulTriggers.absence_kind` liefert das
Gate) nach Hause, erzählt der Raum, was Gooby getrieben hat: 1–2 kleine
Spuren-Props an deterministischen Plätzen — verrutschtes Kissen auf dem
Sofa, aufgeschlagenes Buch auf dem Teppich, schief liegende Zahnbürste,
Keks-Krümelspur Richtung Kühlschrank. Tap auf eine Spur → Gooby „gesteht"
mit einer frischen Line („Das Kissen war zuerst schief. Es hat angefangen.")
und die Spur räumt sich mit Mini-Puff weg (+1 Münze Fund-Chance, dockt an
den vorhandenen 90-s-Mini-Fund an). Die Spur ist konsistent mit seiner
gebuchten Abwesenheits-Story: `idle_wandern`/„Wo ist mein Gooby?" erzählt ja
schon, WAS er tat — dieselbe Kategorie bestimmt den Prop. Nie mehr als 2
Spuren, nie Pflicht (kein Putz-Zwang, nur Charme). Code-Anker:
`scripts/events/event_props.gd` (Prop-Spawning existiert für Events),
`scripts/home/gooby_reactions.gd` (`_luecke_vor_besuch` im `SeeleRunner`),
`strings/de/soul_lines.json` (neue Kategorie `spuren.*`). Risiko: Props
dürfen NavMesh/Baumodus nicht blockieren → als reine Deko-Layer ohne
Grid-Belegung spawnen.

### 6. Foto-Reflex — „Schnapp mich!"-Momente
**Aufwand: M · Impact: 4 · Risiko: mittel**

Wenn ein starkes inszeniertes Gefühl läuft (FEEL-AC prio ≥ 2: Stolz nach
Rekord, Verliebtheit beim Lieblingsessen, Kissenturm-Überraschung), blendet
für ~6 s ein kleiner Kamera-Chip ein („Foto-Moment!"). Tap → Kamera-App
öffnet bereits auf Gooby gerahmt (die Kamera-App existiert im IGohbie,
`scripts/city/phone/kamera_app.gd`), das Gefühl FRIERT für die Aufnahme
nicht ein, sondern läuft weiter — echte Momentaufnahme. Das Foto landet mit
Moment-Stempel („Erster Rekord-Stolz", Datum) in der Galerie; eine kleine
Sammel-Seite „Gefühls-Album" (12 Emotionen als Silhouetten-Slots) gibt
sanftes Sammelziel und macht die 12 FEEL-AC-Emotionen zum Content. Kein
Zwang, kein Timer-Stress: verpasst = kommt wieder. Code-Anker:
`scripts/soul/seele_runner.gd` (`melde_gefuehl` gibt die Emotion zurück),
`GoobyFeelings.gefuehl_beendet`-Signal, `scripts/ui/galerie/galerie_logic.gd`.
Risiko: Kamera-App-Kontextwechsel (Telefon-Shell) muss schnell genug sein,
sonst ist der Moment vorbei — ggf. Schnell-Foto ohne Telefon-Umweg als
Fallback (ein Tap = Schnappschuss).

### 7. Wunschzettel am Kühlschrank + Wunsch-Ausbau
**Aufwand: S–M · Impact: 4 · Risiko: sehr niedrig**

Goobys kleine Wünsche (SEELE-2: „Ich wollte schon immer mal…") sind aktuell
nur 4 Ids und leben nur in Sprechblasen — leicht zu verpassen. Sobald ein
Wunsch gefasst ist, hängt ein Zettel-Magnet am Kühlschrank (der Kühlschrank
ist eh Pflichtmöbel + täglicher Anlaufpunkt): krakelige Kinder-Zeichnung des
Wunsches, Tap → Gooby erklärt ihn nochmal. Bei Erfüllung wird der Zettel
feierlich abgehakt (Stempel-Sound, Konfetti — der `wunsch_erfuellt`-Moment
feuert schon heute SICHER) und wandert als Mini-Andenken ins Regal (Synergie
mit Idee 3). Dazu den Pool von 4 auf ~10 Wünsche erweitern, alle gegen echte
Save-Daten prüfbar nach dem Muster von `wunsch_offen()`: „mal Pfannkuchen
essen" (`soul.foodGiven`), „eine Girlande überm Sofa" (`home`-Items),
„einmal GOB.TY bis zum Ende gucken", „einen Schneemann" (Winter+Garten),
„10 Bälle fangen" (`ball_logic`-Zähler). Code-Anker:
`scripts/soul/soul_memories.gd` (`WUNSCH_IDS`, `wunsch_offen`,
`offene_wuensche`), `scripts/home/interactables/kuehlschrank.gd`,
`content/soul/data/soul.json`. Risiko: praktisch keins — reine Daten +
ein Prop; Texte müssen liebevoll werden (der eigentliche Aufwand).

### 8. Goldene Stunde & Nacht-Stille — Tageszeit zum Fühlen
**Aufwand: S–M · Impact: 4 · Risiko: niedrig**

`HomeLicht` lerpt schon nach Uhrzeit, aber es gibt keine MOMENTE. Neu: zur
goldenen Stunde (Wetter klar, ~1 h vor Sonnenuntergang) flutet einmalig
warmes Licht durchs Fenster — sichtbarer Lichtkegel mit Staub-Partikeln
(GPUParticles, billig), und Gooby setzt sich über einen neuen Idle-Akt in
den Lichtfleck („Ich park mich mal strategisch in den Lichtfleck" — die
Zeile EXISTIERT schon in `soul_lines.json`, sie braucht nur ihre Bühne!).
Nachts (23–6 Uhr) schaltet das Haus in Stille: Gebrabbel wird leiser/tiefer
(`GoobyVoice.set_stimmung`-Muster um Flüster-Faktor ergänzen), das Radio
dimmt, Möbel-Emissive (TV-Standby, Lampen) werden zu Glimmen, und die
Grüße flüstern („Pssst… die Möbel schlafen schon" existiert). Das macht
JEDE Tageszeit zu einem eigenen Zuhause-Gefühl — Foto-würdig obendrein
(Synergie mit Idee 6). Code-Anker: `scripts/home/home_licht.gd`,
`content/soul/data/soul.json` (neuer `idle_lichtfleck` mit
`braucht`-Bedingung), `scripts/character/gooby_voice.gd`. Risiko:
Lichtkegel-Ästhetik im Mobile-Budget (ein Quad mit additivem Shader reicht).

### 9. Traum-Blasen — der Schlaf erzählt
**Aufwand: M · Impact: 3–4 · Risiko: niedrig**

Wenn Gooby schläft (Nickerchen oder Nacht, `PflegeRunner` posiert ihn
schon), steigen alle ~20 s kleine Traumblasen auf: Icon-Vignetten aus
ECHTEN Erlebnissen des Tages — heute geangelt → Fisch, Rekord → Pokal,
Lieblingsessen → Nutella-Glas, nichts Besonderes → Möhren-Klassiker. Die
Quelle ist dieselbe Kandidaten-Liste wie bei Erinnerungen
(`SoulMemories.candidates` + Tages-Counter), es entsteht also nie ein
erfundener Traum. Selten (5 %) ein Quatsch-Traum (fliegendes Sofa), der beim
lauten Träumen (`sup_traum` existiert) eine neue Zeile bekommt. Beim
sanften Wecken erzählt er den letzten Traum („Du warst auch da! Du warst
ein Keks.") — Anschluss an die vorhandene Weck-Logik im Bett-Panel. Macht
das Schlafen (bisher toter Zustand) zum Hingucker und belohnt das
Abend-Ritual (Idee 1). Code-Anker: `scripts/home/sleep/pflege_runner.gd`
(`_sleep_posed`), `scripts/soul/soul_memories.gd`,
`scripts/home/interactables/bett.gd` (Wecken). Risiko: Icon-Assets für
~10 Traummotive (klein, als Billboard-Sprites lösbar).

### 10. Beziehungs-Buch — „Unser Buch"
**Aufwand: M · Impact: 4 · Risiko: niedrig**

`SoulTriggers.beziehung_stufe` (bekannt → vertraut → beste Freunde) und
`anniversary_milestone` färben heute schon Texte — aber der Spieler sieht
die Beziehung nirgends. Neu: ein Buch-Prop im Wohnzimmer (oder IGohbie-App):
„Unser Buch" — automatisch geschriebene, illustrierte Seiten für echte
Meilensteine mit Datum: erster Tag (aus `firstMetAt`), erste Fütterung,
erstes Foto, jeder Jubiläums-Tag, jeder erfüllte Wunsch, Geburtstage. Jede
neue Seite = Stempel-Moment mit Sound (Dopamin nach Reisepass-2.0-Muster,
das der User liebt). Die Beziehungsstufe steht vorn als Widmung („Für meinen
besten Freund {name}" ab Stufe 3) — Vorfreude auf die nächste Stufe
inklusive („Seite 12 ist noch zugeklebt…"). Code-Anker:
`scripts/soul/soul_state.gd` (`celebrated`, `wunschErfuellt`,
`totalMoments` — alles liegt schon im Save!), `scripts/soul/soul_triggers.gd`,
UI nach `story_books.gd`-Muster (Buch-Layout existiert für die
Geschichten-Stunde). Risiko: Illustrationen — mit Sticker-Assets +
Layout-Vignetten lösbar, keine neuen Zeichnungen nötig.

### 11. Gooby-Geburtstag & Feiertage als HAUS-Feste
**Aufwand: M · Impact: 4 · Risiko: mittel**

`ritual_geburtstag_gooby`, `ritual_weihnachten` & Co. sind heute eine
Sprechblase + Konfetti — die Rituale verdienen Bühnenbild. Am Gooby-
Geburtstag (aus `birthday_from_ms(firstMetAt)`) ist das Wohnzimmer beim
ersten Betreten DEKORIERT: 1–2 Girlanden spannen sich automatisch (das
komplette Girlanden-System `deko/girlande.gd` + Catenary-Logik existiert!),
ein Kuchen-Prop steht auf dem Tisch, ein Geschenk-Karton wartet (Tap →
kleiner Sticker/Münzen + der Karton bleibt als Spiel-Karton, Anschluss an
den `karton_gooby`-Event-Gag). Heiligabend analog mit Lichterkette +
warmem Licht-Preset, erster Schnee mit Frost-Rand am Fenster-Diorama. Alles
despawnt am Folgetag von selbst (Tages-Gate über `celebrated` existiert).
Der Spieler-Geburtstag spiegelt das Fest — Gooby hat dann eine schiefe
selbstgebastelte Girlande („Ich hab sie SELBST gebastelt. Man sieht's,
oder?"). Code-Anker: `scripts/soul/soul_service.gd` (`_decide_ritual` liefert
das Gate), `scripts/home/deko/girlande.gd`, `scripts/events/event_props.gd`.
Risiko: Deko darf Baumodus/Save nicht verschmutzen → als flüchtige
Event-Props, nie ins `home`-Slice schreiben.

### 12. Lieblingsplatz sichtbar + Möbel-Meinungen
**Aufwand: S · Impact: 3 · Risiko: sehr niedrig**

Der Soul-Slice hat `favFurniture` und den Idle-Akt `idle_lieblingsplatz`
(braucht `hat_fav`) — aber wie ein Möbel zum Liebling WIRD, ist unsichtbar.
Neu: Nutzung zählt (worauf er bei Idles sitzt/döst), ab Schwelle „erklärt"
er ein Möbel öffentlich zum Lieblingsplatz (kleiner Moment: er tätschelt
es, Herz-Partikel, „Das ist jetzt MEIN Platz. Du darfst trotzdem drauf.").
Sitzt er dort, schweben gelegentlich 1–2 Mini-Herzen (dezent!). Beim
Umstellen im Baumodus kommentiert er das Möbel („Oh! Umzug für meinen
Platz?" — Anschluss an den vorhandenen Bau-Zuschauer-Kommentar), beim
VERKAUFEN des Lieblingsplatzes gibt es einen einmaligen Abschieds-Gag statt
Strafe („Leb wohl, Platz. Wir hatten was.") und ein neuer Liebling wird
gewählt. Code-Anker: `scripts/soul/soul_state.gd` (`favFurniture`),
`content/soul/data/soul.json` (`idle_lieblingsplatz`),
`scripts/home/gooby_reactions.gd` (Idle-Ziele), Baumodus-Hooks in
`scripts/home/build_mode/`. Risiko: keins nennenswert — reiner Charme-Layer.

### 13. Heimkomm-Echos — Gooby erzählt vom Ausflug
**Aufwand: S · Impact: 3 · Risiko: sehr niedrig**

Nach Rückkehr ins Wohnzimmer aus Stadt/Arcade/Minispiel bezieht sich Gooby
1× auf das gerade Erlebte („Mein Bauch dreht sich noch vom Kreisel…
nochmal!" nach dem Kreisel-Spiel, „Der Kassen-Gooby bei REHWEI war nett.
Er piept schön." nach dem Einkauf). Der Mechanismus existiert komplett:
`SeeleRunner.kommentar_global(kategorie)` + `SoulLinien`-Anti-Wiederholung +
Frequenzbremse — es fehlen nur die Abfahrts-Hooks (der `SceneRouter` weiß,
woher man kommt) und ~8 neue Line-Kategorien (`heimkehr.arcade`,
`heimkehr.stadt`, `heimkehr.markt`, `heimkehr.urlaub`…). Verstärkt das
„EIN Spiel"-Gefühl aus G7-P56 auf der erzählerischen Ebene: die Orte hängen
zusammen, WEIL Gooby sie zusammen erlebt. Code-Anker:
`scripts/core/scene_router.gd` (History kennt die Herkunft),
`scripts/soul/seele_runner.gd` (`kommentar_global`),
`strings/de/soul_lines.json`. Risiko: keins — bei Bremsen-Konflikt gewinnt
wie immer die vorhandene ambient-Bremse.

### 14. Türklingel-Besuch — ganz seltener Nachbar-Moment
**Aufwand: L · Impact: 4 · Risiko: mittel**

Sehr selten (Überraschungs-Muster, `cooldown_h: 120+`, nur tagsüber)
klingelt es: durchs Fenster-Diorama sieht man einen Nachbar-Gooby an der
Tür (Ambient-Besucher-System `city/ambience/ort_leben.gd` liefert Varianten
+ Wegpunkt-Logik fertig). Gooby rennt aufgeregt hin („BESUCH! Sind meine
Ohren gerade?!"), an der Tür gibt es eine Mini-Vignette ohne neuen Raum:
der Nachbar bringt etwas Kleines (3 Kekse = Essen, eine Blume = Deko-Prop,
einmal Klatsch: „Bei REHWEI gibt's morgen Möhren im Angebot!" = echter
Markt-Hinweis). Kein Menü, keine Verpflichtung — 20 Sekunden Wärme, dann
winkt der Besucher und geht. Später erwähnt Gooby den Besuch als Erinnerung.
Baut auf G7-P55 („Läden lebendig") auf und holt dessen Qualität ins Haus:
das Zuhause liegt in einer NACHBARSCHAFT. Code-Anker:
`city/ambience/ort_leben.gd` (Besucher-Goobys), `scripts/home/door_logic.gd`
+ `street_diorama.gd`, `content/soul/data/soul.json`
(`ueberraschung`-Def). Risiko: größter Baustein der Liste (Tür-Vignette +
Besucher-Spawn im Home-Kontext); Reduced-Motion- und Offline-Pfad simpel
halten (Besuch fällt still aus, wie alle Soul-Momente).

### 15. Regentag-Gemütlichkeit — Wetter färbt das Programm
**Aufwand: S · Impact: 3 · Risiko: sehr niedrig**

Regen/Gewitter/Schnee sind da (deterministischer `SoulWetter`-Tagesplan,
Fenster-FX, Donner-Schreck) — aber das Haus-PROGRAMM ändert sich nicht.
Neu, rein datengetrieben über die vorhandenen Def-Gates: bei Regen bekommen
gemütliche Idles mehr Gewicht (`idle_fenster`, dösen, TV) und zwei neue
Regen-Idles kommen dazu (Regentropfen-Wettgucken am Fenster: „Meiner
gewinnt. Der linke. LOS!"; Kakao-Moment bei Schnee), bei Gewitter sucht er
nach dem Donner-Schreck deine Nähe (walk Richtung Kamera — Muster von
`gruss_annaeherung` existiert), und die Geschichten-Stunde wird von Gooby
selbst vorgeschlagen, wenn es abends regnet (er bringt das Buch). Die
`braucht`-Bedingung im Idle-Def-Schema kann heute nur bool-Flags — um
`"braucht": "regen"` erweitern (eine Zeile in `_idle_requirement_met`).
Code-Anker: `scripts/soul/soul_service.gd` (`pick_idle`,
`_idle_requirement_met`), `content/soul/data/soul.json`,
`scripts/events/story_time.gd`. Risiko: keins — Texte sind der Aufwand.

---

## Übersicht

| # | Idee | Aufwand | Impact | Kern-Anker |
|---|---|---|---|---|
| 1 | Morgen- & Abend-Ritual | M | 5 | `pflege_runner.gd`, `bett.gd`, `soul_service.gd` |
| 2 | Stimmungs-Herz im HUD | S–M | 5 | `hud.gd`, `soul_mood.gd` |
| 3 | Andenken-Regal | M | 5 | `soul_memories.gd`, `furniture_catalog.gd` |
| 4 | Fenster-Momente | M | 4 | `street_diorama.gd` |
| 5 | Mitbewohner-Spuren | M | 4 | `event_props.gd`, `seele_runner.gd` |
| 6 | Foto-Reflex | M | 4 | `seele_runner.gd`, `kamera_app.gd` |
| 7 | Wunschzettel am Kühlschrank | S–M | 4 | `soul_memories.gd`, `kuehlschrank.gd` |
| 8 | Goldene Stunde & Nacht-Stille | S–M | 4 | `home_licht.gd`, `soul.json` |
| 9 | Traum-Blasen | M | 3–4 | `pflege_runner.gd`, `soul_memories.gd` |
| 10 | Beziehungs-Buch | M | 4 | `soul_state.gd`, `story_books.gd` |
| 11 | Geburtstag/Feiertage als Haus-Feste | M | 4 | `soul_service.gd`, `girlande.gd` |
| 12 | Lieblingsplatz sichtbar | S | 3 | `soul_state.gd`, `gooby_reactions.gd` |
| 13 | Heimkomm-Echos | S | 3 | `scene_router.gd`, `seele_runner.gd` |
| 14 | Türklingel-Besuch | L | 4 | `ort_leben.gd`, `door_logic.gd` |
| 15 | Regentag-Gemütlichkeit | S | 3 | `soul_service.gd`, `soul.json` |

**Paket-Empfehlung für eine Umsetzungs-Welle:** Ideen 1+2+7+8 als „Tag &
Innenleben"-Paket (ein gemeinsamer Testlauf über den Tageszyklus), Ideen
3+10 als „Erinnerungs-Paket", 4+5+13+15 als „Zuhause lebt"-Paket. Idee 14
erst nach dem Diorama-Ausbau (4) einplanen.

**Durchgehende Leitplanken (aus dem Bestandscode gelernt, gelten für ALLE
Ideen):** jeder neue Moment läuft durch die vorhandene Frequenzbremse
(`SoulTriggers.ambient_allowed`) — nie zutexten; alle Texte in
`strings/de/*.json` + EN-Parität (Domain-OWNERSHIP eintragen); Zeit/Zufall
IMMER hereinreichen (headless-testbar, Playtest-Harness aus G7-P58 kann
dann jeden Moment nachstellen); Reduced-Motion-Pfad für jede Inszenierung;
keine Strafen, nur Wärme.
