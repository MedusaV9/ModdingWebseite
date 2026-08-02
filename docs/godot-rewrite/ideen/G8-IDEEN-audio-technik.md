# G8-IDEEN — AUDIO/MUSIK/HAPTIK + TECHNIK/PERFORMANCE + MULTIPLAYER-INFRA (Ideen-Planner IP-6, Welle I)

**Bereich:** Adaptive Audio-Systeme, Musik-Design, Stimm-/ASMR-Momente, Haptik-Choreografien,
Technik (Ladezeit/Speicher/Batterie/Save-Robustheit auf echtem iPhone) und
Multiplayer-Infrastruktur (GOOBY-SERVER, Besuche, asynchrone Überraschungen, Server-Events).
**Quellen (nur gelesen, nichts geändert):** `UserFeedback.md` (komplett),
`docs/godot-rewrite/AUDIO-GRAMMATIK.md`, `E4-perf.md`, `E13-server.md`, `E14-offline.md`
(Verweis), `EVAL-DOPAMIN-SOUND-FEEL.md`, `STATUS.md`, Code-Streifzug durch
`GOOBY-GODOT/assets/audio/**`, `assets/music/**`, `scripts/audio/**`, `scripts/character/
gooby_voice.gd`, `scripts/ui/components/haptics.gd`, `scripts/state/**`, `scripts/net/**`,
`scripts/social/**`, `scripts/platform/quality_service.gd`, `GOOBY-SERVER/src/**` + `test/**`,
`git log -30`.

**Abgrenzung (WICHTIG, nicht doppeln):**

1. **Ein IMPL-AUDIO-Worker setzt parallel die Audio-Grammatik-Lücken um** (SFX-Vervollständigung,
   Raum-Reverb, Mix-Wache). Alle Ideen hier gehen bewusst DARÜBER hinaus (adaptive Systeme,
   Musik-Design, besondere Momente). Zwei Koordinationspunkte sind markiert: Idee 5 (Ducking —
   Laufzeit-Mix, die Mix-WACHE sollte die Duck-Pegel mittesten) und Idee 10/11 (setzen auf der
   Bus-/Reverb-Architektur des Workers AUF, bauen sie nicht selbst).
2. **IP-2 P15 „Kassen-Melodie“** deckt die Kassen-Töne der Läden ab — Idee 11 (Ort-Klangidentitäten)
   klammert Kassen-Piepser deshalb explizit AUS und liefert die Ambience-/Signatur-Ebene darunter.
3. **IP-1 Idee 8 „Goldene Stunde & Nacht-Stille“** liefert Szenen-MOMENTE im Haus — Idee 1 hier
   liefert das systemische Musik-Fundament dazu (dieselbe Uhr, andere Ebene; zusammen einplanen).
4. **Während dieser Lieferung sind drei weitere Welle-I-Dateien gelandet**
   (`G8-IDEEN-ui-juice.md`, `G8-IDEEN-progression.md`, `G8-IDEEN-minispiele-arcade.md`) — vier
   Berührungspunkte sind KEINE Dubletten, sondern Merge-Kandidaten und in den Ideen 2/5/6/9
   explizit als solche markiert: Ducking (J13 = UI-Blätter-Konsument, hier = Stimme/Stinger),
   Haptik-Partituren (J6 = UI-Muster, hier = Momente + Amplituden-Dimension), Geschenk-Pfad
   (Progression Nr. 3 = Post-Ökonomie, hier = Garten-Bühne), Wochen-Challenge (A4 = offline-
   deterministische Basis, hier = Server-Aufsatz mit Freundes-Bestenliste).

Aufwand **S/M/L** (Umfang/Risiko/betroffene Systeme, keine Kalenderzeit), Impact **1–5**,
Risiko ehrlich mit Gegenmittel.

---

## TOP-3 (Begründung)

**🥇 Idee 1 „Der Tag hat einen Soundtrack“ — adaptive Heim-Musik mit Stems.** Das Haus ist
die meistbewohnte Szene des Spiels, und seine Musik ist heute EIN statischer Loop pro Raum
(`music_registry.gd`: 1 Track je Kontext, einzig `sleeping` schaltet um). Ein Stem-Layer-System
(Godot 4.4 bringt `AudioStreamSynchronized` fertig mit) macht aus „Musik läuft“ ein „das Zuhause
KLINGT nach Tageszeit und Tätigkeit“ — morgens licht, mittags voll, abends warm, nachts nur
Bett + Pad; Baumodus blendet die Bastel-Percussion ein. Kein anderes Audio-Feature zahlt so
dauerhaft auf das Ein-Spiel-Gefühl und die AC-Referenz ein (dort ist stündliche Musik DAS
Identitätsmerkmal). Der Fallback-Pfad (Tageszeit-Varianten nach dem vorhandenen
awake/sleeping-Muster) hält das Risiko klein.

**🥈 Idee 2 „Das Garten-Geschenk“ — asynchrone Freundes-Überraschung.** Der wörtliche
Auftrags-Wunsch, und die Infrastruktur liegt zu ~80 % bereit: Freunde + Push/WELCOME-Pull
(`events.js`-Muster), einmalige Geschenk-Gutschrift (`claim_gift`-Pfad in `net_mail.gd`/`mail.js`),
Ack+Dedupe gegen die E13-P1-2-Zustelllücke (`server_events.gd`), Prop-Spawning (`event_props.gd`).
Neu ist „nur“ die Bühne: das Geschenk liegt PHYSISCH im Garten statt abstrakt im Briefkasten.
Asynchrone Wärme („jemand hat an dich gedacht, während du weg warst“) ist der stärkste
Multiplayer-Hebel für ein Tamagotchi-Spiel — stärker als jedes Live-Feature, weil er ohne
Verabredung funktioniert.

**🥉 Idee 3 „Echte iPhone-Zahlen“ — Geräte-Telemetrie + Panel-Seite.** JEDE Technik-Frage des
Auftrags (Ladezeit? Speicher? Batterie? lohnt Metal-Tuning?) ist heute unbeantwortbar, weil die
CI auf llvmpipe misst und `E4-perf.md` selbst warnt: „FPS-Spalte NICHT iPhone-aussagekräftig“.
Der Client hat bereits eine idempotente Analytics-Pipeline mit Outbox (`analytics.gd`,
Batch-Dedupe serverseitig bewiesen in E13) — Boot-Phasen-Dauern (`boot_phasen.gd` liefert echte
Phasen), FPS-Histogramme, Speicher-Peaks und Raumwechsel-Zeiten vom echten iPhone 17 Pro Max
kosten einen Batch-Felderweiterung + eine Webpanel-Seite. Danach sind Ideen 13–16 datengetrieben
statt geraten — und der llvmpipe-vs-Metal-Streit ist beendet: CI wacht über
renderer-unabhängige Budgets (Draw Calls/Tris/Materials, E4-Disziplin), das Gerät liefert die
Wahrheit über Zeit und FPS.

---

## Priorisierte Ideenliste

### 1. „Der Tag hat einen Soundtrack“ — adaptive Heim-Musik (Stems je Tageszeit/Aktivität)
**Aufwand: L · Impact: 5 · Risiko: mittel**

Für die Heim-Kontexte (`room:living/kitchen/garden` …) wird der eine Loop durch ein
Stem-Paket ersetzt: 3–4 sample-synchrone Spuren (Bett/Pad, Melodie, Percussion, Glitzer) in
EINEM `AudioStreamSynchronized`-Stream, deren Lautstärken der `MusicDirector` fährt. Die
Mischung ist eine pure Funktion `stem_mix(stunde, aktivitaet)` (testbar wie `SoulWetter`):
Morgen = Bett+Melodie hell, Tag = voll, goldene Stunde = warm ohne Percussion (Anschluss an
IP-1 Idee 8), Nacht/`sleeping` = nur Bett+Pad (ersetzt den separaten Schlaf-Track-Umschnitt);
Aktivitäts-Overlays docken an Bestands-Signale an — Baumodus (+Bastel-Percussion via
`push_context`-Muster), Besuch (+1 Layer), Regen (Melodie leiser, Pad wärmer, `SoulWetter` ist
deterministisch). Code-Anker: `scripts/audio/music_director.gd` (`_apply`, `resolve_track`,
`push_context`), `scripts/audio/music_registry.gd` (`track_for(context, sleeping)` → um
`tageszeit`/Stem-Deskriptor erweitern; das awake/sleeping-Paar `room-pixie-puddle-*` beweist
das Varianten-Muster schon heute), Zeit-Injektion wie `SoulWetter`/`street_diorama.gd`
(`stunde_override` existiert). Risiko ehrlich: die 51 Bestands-Tracks existieren nur als
fertige Mixe — Stems müssen NEU generiert werden (gleiche Pipeline wie damals bzw.
`tools/audio`-Synthese); Gegenmittel ist der abgespeckte Fallback OHNE neue Assets:
4 Tageszeit-VARIANTEN pro Heim-Track als normale Crossfades (Muster existiert) plus
Bus-Feinfärbung (nachts −3 dB + sanfter Lowpass). Loop-Punkte/Loudness laufen durch die
bestehende EF-2-Straße (`tools/audio/ef2_music_master.py`), die Mix-Wache des IMPL-AUDIO-Workers
wacht mit.

### 2. „Das Garten-Geschenk“ — Freund hinterlässt eine Überraschung im Garten
**Aufwand: M · Impact: 5 · Risiko: niedrig–mittel**

In der Freunde-App (`friends_app.gd`) gibt es neben „Besuchen“ neu „Überraschung verstecken“:
kleines Geschenk (Speise/Deko-Samen/Sticker-Tütchen + 100-Zeichen-Notiz) wandert an den Server;
beim Empfänger liegt beim nächsten Garten-Besuch ein eingepacktes Päckchen an einem
deterministischen Platz (Seed aus Geschenk-Id — kein Sync-Problem), Gooby entdeckt es zuerst
und rennt aufgeregt hin („Da liegt was! Da liegt WAS!“). Auspacken = Konfetti + Notiz-Karte +
Gutschrift über den EINEN Geld-/Inventar-Pfad; danach erwähnt Gooby den Absender als Erinnerung
(`SoulMemories`-Kandidat). Server: neues Modul `geschenke.js` streng nach `goobypal.js`/`mail.js`
(Tageslimit, `claim`-EINMALIG vor Erfolgsantwort synchron geflusht — Lehre aus E13 P1-1 —,
Pending in `WELCOME`, Zustellung NUR mit Client-Ack nach `server_events.gd`-Muster gegen die
E13-P1-2-Lücke, Tests nach `test/goobypal.test.js`-Vorlage). Client-Anker:
`scripts/net/net_mail.gd` (claim-Muster), `scripts/net/server_events.gd` (Ack+Dedupe),
`scripts/events/event_props.gd` + `scripts/home/garden/garden_host.gd`/`garden_world.gd`
(Prop + Spawn), `scripts/net/outbox.gd` (offline-first Senden). Risiko: Item-Gutschrift muss
idempotent bleiben (rewardId-Muster aus `gvzmp.js` übernehmen); Geschenk-Ökonomie klein halten
(nur billige Items, kein Münz-Transfer — der existiert schon als GoobyPal).
**Merge-Hinweis:** `G8-IDEEN-progression.md` Nr. 3 (Wunschliste/Dankespost/Schenker-Herzen)
nutzt DENSELBEN Geschenk-Pfad — Nr. 3 liefert die Post-Ökonomie und Belohnungs-Schleife, diese
Idee die Zustell-BÜHNE (physisch im Garten, Entdeck-Moment). Ein gemeinsames Server-Fundament
bauen, zwei Erlebnisse drandocken; nicht zweimal `geschenke.js` erfinden.

### 3. „Echte iPhone-Zahlen“ — Geräte-Telemetrie + „Geräte“-Panel-Seite
**Aufwand: M · Impact: 5 · Risiko: niedrig**

Der Analytics-Batch (`scripts/net/analytics.gd`, Heartbeat + idempotenter Flush existieren)
bekommt einen kompakten `perf`-Block: Boot-Phasen-Dauern in ms (die PHASEN in
`scripts/boot/boot_phasen.gd` sind ECHT — nur Zeitstempel mitschreiben), Dauer bis zum ersten
Wohnzimmer-Frame, Median/95p der Raumwechsel (`scene_router.gd` misst Reisen ohnehin),
FPS-Histogramm-Buckets (60/45/30/<30, gesampelt 1×/s), Speicher-Peak
(`OS.get_static_memory_usage` + `RenderingServer.get_rendering_info`-VRAM wie
`perf_overlay.gd::snapshot()`), Gerätemodell (`OS.get_model_name()`), Grafik-Preset +
Notbremsen-Auslösungen (`quality_service.gd::quality_reduced`). Server: `analytics.js` nimmt die
Felder additiv an (Schema-tolerant ist es schon), das Webpanel (fail-closed, 6 Seiten) bekommt
Seite 7 „Geräte“ mit Boot-Zeiten/FPS je Modell. Damit ist die Auftrags-Frage „llvmpipe-CI vs.
Metal — was lohnt?“ beantwortbar: llvmpipe bleibt Budget-Wächter für Draw Calls/Tris/Mats
(renderer-unabhängig, E4-Methodik), Zeiten/FPS kommen vom Gerät — jede Optimierung aus Idee
13/14/16 bekommt Vorher/Nachher-Belege frei Haus. Risiko: praktisch keins — reine Zusatzfelder
im bestehenden idempotenten Batch (E13-bewiesen); Datenschutz sauber: nur Technik-Metriken,
keine Inhalte, gleiche Opt-Struktur wie Sessions heute.

### 4. Lieblingslied-System — Gooby hat SEIN Lied (und du kannst es verschenken)
**Aufwand: M · Impact: 5 · Risiko: niedrig**

Die Spieler-Likes existieren (`radio.likes`, `scripts/ui/radio/radio_logic.gd`) — jetzt bekommt
GOOBY Geschmack: ein additiver `radio.plays`-Zähler pro Track plus eine pure Wahl-Funktion
(Seed aus `firstMetAt` × meistgehörte Kategorie) kürt deterministisch SEIN Lieblingslied; läuft
es (Signal `track_changed` in `music_director.gd`), wackeln die Ohren, ein Tanz-Idle startet,
Herz-Emote, „DAS! Das ist meins!“ — und selten wünscht er es sich aktiv („Spielst du… das mit
den Möhren?“ → 1-Tap-Abspielen über `radio_play`, Laune-Boost, Anschluss an das
`wunsch_offen()`-Muster in `soul_memories.gd`). Im Radio-Sheet trägt sein Lied ein kleines
Gooby-Gesicht neben dem Spieler-Herz (`radio_sheet.gd`/`now_playing_chip.gd` — „Was läuft?“-
Ticker existiert). Verschenkbar als **Mixtape**: 3 Lieblingslieder + Widmung als Geschenk über
den Mail-Gift-Pfad (`net_mail.gd`, `claim_gift` einmalig) — beim Freund spielt das Mixtape als
temporärer Pseudo-Sender (Muster `BORDMUSIK_STATION`, Level-Schranken respektiert
`radio_queue_for` automatisch). Risiko: niedrig — Zähler additiv (`merge_defaults` konserviert),
Reaktionen laufen durch die vorhandene Frequenzbremse (`SoulTriggers.ambient_allowed`).

### 5. Mix-Momente — Ducking-API für Stimme & Belohnungen
**Aufwand: S · Impact: 4 · Risiko: sehr niedrig**

EVAL-1 S8 ist weiter offen: Results-Fanfare, Level-Up-Stinger und Gebrabbel kämpfen ungeduckt
gegen das Musikbett. Neu am `MusicDirector`: `duck(db := -6.0, attack_ms := 80, hold_ms := 1500,
release_ms := 600)` — ein Tween auf dem Music-Bus-Volume (Muster `_fade_volume` existiert),
gestapelt sicher (Zähler statt bool). Auto-Verdrahtung an genau DREI Stellen: `GoobyVoice.sagt()`
duckt leicht (−4 dB, solange `ist_am_reden()` — Stimme wird endlich immer verständlich, der
größte ASMR-Klarheitsgewinn überhaupt), `play_stinger()` duckt sich sein Bett selbst (−6 dB),
Results-/Rekord-Moment im `minigame_host.gd` (−6 dB für die Zähl-Animation). Code-Anker:
`scripts/audio/music_director.gd`, `scripts/character/gooby_voice.gd` (`_talking`-Flag +
`fertig`-Signal), `scripts/minigames/minigame_host.gd`. **Koordination/Merge:** (a) die Mix-Wache des
IMPL-AUDIO-Workers sollte die Duck-Pegel mittesten (6–10-dB-Abstand-Test existiert bereits als
Vorbild in `test_ef2_audio_levels.gd`); (b) `G8-IDEEN-ui-juice.md` J13 schlägt dieselbe
Referenzzähler-`duck()`-API für PanelSheet-Öffnen vor — EINE API bauen, ZWEI Konsumenten-Sets
verdrahten (J13: UI-Blätter −2,5 dB; hier: Stimme −4 dB, Stinger/Results −6 dB). Risiko: keins
nennenswert; Reduced-Motion irrelevant, headless degradiert wie alle Tweens im MusicDirector.

### 6. Haptik-Partituren — Choreografien für Schlüsselmomente
**Aufwand: S–M · Impact: 4 · Risiko: niedrig**

`Haptics` kann heute drei Gesten (tap/success/warn, `scripts/ui/components/haptics.gd`) — für
MOMENTE braucht es Partituren: eine pure Tabelle `PARTITUREN: id → Array[{ms, amp, pause_ms}]`
plus `Haptics.partitur(id)`, abgespielt über `Input.vibrate_handheld(ms, amplitude)` (Godot 4.4
unterstützt Amplitude auf iOS/Android; ehrlich bleiben: auf iOS erst im signierten Build
spürbar, Doku-Hinweis im Code existiert schon). Startsatz: `levelup_treppe` (3 steigende Pulse
10/14/18 ms, amp 0.4→0.8), `rekord_trommelwirbel` (8 Mikroticks accelerando + 1 satter Schlag,
synchron zur `game_record`-Fanfare), `sticker_selten` (tick-tick-…-BUMM zum Gold-Glitzer),
`muenzregen` (Zufalls-Mikroticks parallel zu den Münz-Partikeln der Results),
`gute_nacht` (2 weiche lange Pulse beim Zubettbringen), `countdown_go` (3 Ticks + GO-Puls exakt
auf `mg_go`). Die Stärke-Stufen und das Gate laufen unverändert durch `plan()`/`is_enabled()`
(dezent/normal/stark-Faktoren wirken auf ms UND amp); Partituren sind pure Arrays → Tests wie
`Haptics.plan` heute. Verdrahtung NUR an Moment-Call-Sites gemäß AUDIO-GRAMMATIK („Zusatz-Haptik
nur an Momenten“ — der Absatz bekommt die Partitur-Liste als erlaubte Erweiterung). Risiko:
Über-Vibrieren nervt — harte Regel: max. 1 Partitur pro Moment-Cluster, Results-Cluster bündelt.
**Merge-Hinweis:** `G8-IDEEN-ui-juice.md` J6 beschreibt dieselbe Partitur-Engine mit
UI-Presets (einrast, zaehl_tick, konfetti_prasseln) — EIN gemeinsamer Baustein; das Delta
dieser Idee sind die Moment-Presets oben plus die **Amplituden-Dimension**
(`vibrate_handheld(ms, amplitude)`), die J6 noch nicht nutzt.

### 7. Gooby-Stimm-Momente — Summen, Mitsingen, Ständchen
**Aufwand: M · Impact: 4–5 · Risiko: niedrig**

Die Gebrabbel-Engine (`gooby_voice.gd`) kann Melodie-Bögen (`MELODIEN`, `melodie_bogen`) — ihr
fehlt nur der GESANG: neu `summt(melodie: Array[float])` — 8–16 Pitch-Steps auf der weichsten
Silbe, halbes Tempo, −10 dB, Mund fast zu (eigenes `silbe`-Signal-Flag fürs Rig). Dazu eine
kleine Melodie-Tabelle je Musik-Track-Familie (deterministisch aus der Track-Id gehasht — klingt
IMMER gleich „sein Lied für dieses Lied“, keine neuen Audio-Assets). Momente: beim Lieblingslied
(Idee 4) summt er MIT; in der Badewanne summt er vor sich hin (Anschluss `klo_dusche.gd`-Pflege);
beim Kochen/Warten Wartesummen; am Spieler-Geburtstag ein schiefes Ständchen (bewusst 1 Step
daneben — „Ich hab EXTRA geübt!“, Anschluss `ritual_geburtstag`-Defs in `content/soul/data/
soul.json`); nachts wird jedes Summen zum Flüster-Brummen (Stimmungs-Modulation
`SoulMood.stimme` existiert). Code-Anker: `scripts/character/gooby_voice.gd` (+`summt`),
`scripts/character/gooby_rig.gd` (`babble_pulse`-Lipsync), `scripts/soul/soul_service.gd`
(Idle-/Ritual-Defs), `scripts/audio/music_director.gd` (`current_track_id`). Risiko: niedrig —
kein neues Asset, aber Feintuning nötig, damit Summen nie mit Sprech-Gebrabbel kollidiert
(`_token`-Abbruchmechanik existiert genau dafür).

### 8. Schnurr-Herzschlag — der Audio+Haptik-ASMR-Moment
**Aufwand: S · Impact: 4 · Risiko: niedrig**

Beim anhaltenden Streicheln (Streichel-Pfad `gooby_reactions.gd::handle_tap` mit Pitch-Treppe
existiert) beginnt Gooby nach ~4 s zu SCHNURREN: leiser Brumm-Loop (neues kleines Asset aus der
`tools/audio`-Synthese-Straße, ~55 Hz mit Vibrato, −30 dB eff.) über
`AudioDirector.start_loop/stop_loop` (API existiert), dazu pulst die Haptik als weicher
Herzschlag (2 Low-amp-Pulse ~1,1 Hz, Partitur-Loop aus Idee 6). Hört man auf, klingt das
Schnurren 2 s aus; schläft er dabei ein, wird der Puls langsamer (0,8 Hz) — DER
Tamagotchi-Bindungsmoment schlechthin, und er kostet fast nichts. Zusätzlich als Mini-Ableger:
danceParty pulst auf PERFEKT-Treffern im Takt (Beat-Grid + Latenz-Ausgleich existieren in
`dance_timing.gd`/`dance_calibration.gd` — Haptik ist dort ehrlicher als Sound, weil sie die
Audio-Latenz nicht doppelt). Code-Anker: `scripts/home/gooby_reactions.gd`,
`scripts/audio/audio_director.gd`, `scripts/ui/components/haptics.gd`,
`scripts/minigames/games/dance_party/dance_party.gd`. Risiko: Mix-Disziplin (Schnurren ist
Dauerton — durch die EF-2-Pegelstraße + Mix-Wache schicken).

### 9. Wochen-Challenge-SERVER — Freundes-Bestenliste + Live-Ops-Aufsatz
**Aufwand: L · Impact: 5 · Risiko: mittel**

**Bewusst als AUFSATZ auf `G8-IDEEN-minispiele-arcade.md` A4 geschnitten, nicht als
Konkurrenz-System:** A4 liefert den offline-deterministischen Turnierplan (ISO-Wochen-Hash →
Kabinette + Aufgaben, kein Server nötig) — diese Idee ergänzt die SERVER-Dimension, die A4
bewusst auslässt: (a) eine **Freundes-Bestenliste** pro Turnierwoche — der Score des
Wochen-Kabinetts geht offline-first über die Outbox an ein neues Modul `challenge.js`
(idempotent per weekId+friendCode, nur Bestwert zählt; Vorlagen: `ranchmp.js`-Ghost-Leaderboards
+ `gvzmp.js`-Reward-Idempotenz + der `arcduell.js`-Zuschnitt aus A3 — dritte Kopie desselben
geprüften Musters), Anzeige NUR Freunde (kein Global-Toxic, Friends/Presence existieren);
(b) ein **Live-Ops-Override**: der Server darf per SERVER_EVENT (`events.js` +
`server_events.gd` mit Ack/Dedupe) die Wochen-Challenge übersteuern — Sonder-Seed,
Sonder-Modifier (die Modifier-Engine `scripts/minigames/modifier_engine.gd` wirkt via Framework
auf alle 38 Spiele), Themen-Woche ohne App-Update; offline degradiert exakt auf das
A4-Verhalten (E14-Vertrag). `GoobyRng` ist bit-genau deterministisch — gleicher Seed = faire
Liste. Code-Anker: `scripts/net/server_events.gd`, `scripts/minigames/pregame.gd` +
`minigame_host.gd` (`receive_params` nimmt `seed` schon entgegen), `GOOBY-SERVER/src/events.js`/
`ranchmp.js`, `scripts/net/outbox.gd`. Risiko: Score-Plausibilität (Cheat) — Gegenmittel:
Kappen pro Spiel (Golden-Tests kennen plausible Maxima), Friends-only-Anzeige; E13-P1-1
beachten (Bestwert vor Erfolgsantwort flushen).

### 10. ASMR-Haus-Schicht — Möbel bekommen eine leise Stimme
**Aufwand: M · Impact: 4 · Risiko: niedrig–mittel**

Eine dünne, deklarative Foley-Schicht ÜBER der Reverb-Arbeit des IMPL-AUDIO-Workers: der
Möbel-Katalog (`scripts/home/data/furniture_catalog.json`) bekommt ein optionales
`klang`-Feld (Loop-Id + Pegel + Radius), ein kleiner `HausFoley`-Knoten spawnt pro Raum maximal
4 `AudioStreamPlayer3D` an den nächstgelegenen klingenden Möbeln (Positional!): Kühlschrank
brummt zart (50-Hz-Loop + seltenes Kompressor-Klacken; beim Öffnen duckt er sich —
`kuehlschrank.gd` existiert als Interactable), Wanduhr tickt (nachts leiser), Aquarium blubbert,
Kamin knistert. Dazu der Wetter-Anschluss: Regen ans FENSTER als eigenes Nah-Detail
(Tropfen-Ticks am Fenster-Diorama, drinnen tiefpass-gefiltert über die Worker-Bus-Architektur —
`wetter_fx.gd` hat die Loop-Player schon, es fehlt die Drinnen-Perspektive) und Grillen im
Garten-Abend. Alles quality-gated (`quality_service.gd::particle_factor`-Muster) und
RM-neutral. Code-Anker: `scripts/world/wetter_fx.gd` (`_baue_loops`), `furniture_catalog.json`,
`scripts/home/room_base.gd`, `tools/audio/ef2_gen_sfx.py` (Loop-Synthese + Pegelstraße).
Risiko: Dauerton-Mix wird schnell matschig — harte Regeln (max 4 Quellen, Summe ≤ −24 dB eff.,
Mix-Wache erweitern); Abstimmung mit dem Worker-Zuschnitt nötig (er baut die Busse, wir die
Quellen).

### 11. Ort-Klangidentitäten — jeder Ort hat einen Klang-Steckbrief
**Aufwand: M · Impact: 4 · Risiko: niedrig**

Analog zur `_leben_konfig()` aus G7-P55 bekommt jeder Stadt-Ort einen deklarativen
`klang_steckbrief()`: Ambience-Bett (1 Loop), 2–3 Signatur-One-Shots auf Ereignisse des Ortes
und den Musik-Kontext. Beispiele: Flughafen = Flap-Board-Klackern (`flap_board.gd`-Flips
klingen!), Boarding-Gong, ferne Triebwerke; Goobytheke = Wartezimmer-Stille mit Papier-Rascheln
+ Niesen (Anschluss IP-2 P1-Requisiten); Funkelpark = ferner Kirmes-Walzer + Coaster-Rattern,
das beim Näherkommen lauter wird; Raumstation GOOB-1 = Brummen + Funk-Piepser; McGooby =
Grill-Sizzle-Bett + Fritten-Timer. Musik: heute teilen sich alle Orte `shop`/`vet`/`city` —
`MusicRegistry.EXTRA_CONTEXT_TRACKS` um 2–3 Schlüssel-Orte erweitern (Funkelpark! Flughafen!),
der Rest differenziert über Ambience statt neuer Tracks (billig). AUSGEKLAMMERT: Kassen-Töne
(IP-2 P15) und Hall-Presets (Reverb-Worker) — dieser Steckbrief referenziert beide nur.
Code-Anker: `scripts/city/ort_scene.gd` (Hook neben `_leben_konfig`),
`scripts/city/ambience/ort_leben.gd`, `scripts/audio/music_registry.gd`,
`scripts/audio/audio_director.gd` (`start_loop`). Risiko: niedrig — pro Ort 1 Loop-Player,
Budget-neutral; Loop-Assets über die Synthese-Straße bzw. CC0-Quellen (Pegel-/Lizenz-Straße
existiert: `ASSET-CREDITS.md`, EF-2).

### 12. Save-Sicherheitsnetz komplett — Recovery sichtbar, Koffer automatisch, Server-Kopie
**Aufwand: M · Impact: 4 · Risiko: niedrig**

Der SaveManager ist stark (atomar, 3 Backups, `.tmp`-Crash-Fenster-Recovery — `save_manager.gd`),
aber drei Lücken bleiben: (a) **Recovery ist stumm** — der Hinweis-Toast beim Boot ist laut
STATUS.md weiter unverdrahtet (String + `state_loaded`-Signal existieren, kein Konsument):
verdrahten, mit warmem Text („Puh — dein Spielstand war knittrig, das Backup von gestern ist
eingesprungen.“) und `recovered`-Quote in die Telemetrie (Idee 3); (b) **Auto-Umzugskoffer**:
wöchentlich ein Export über den vorhandenen Umzugskoffer-Codec in einen `user://backups`-Ring
(3 Stück) + Settings-Knopf „Koffer sichern/teilen“ (`umzug_sheet.gd` existiert; iOS-seitig
Files-App-Sichtbarkeit via Export-Option prüfen — dann kommt man auch OHNE funktionierende App
an den Koffer); (c) **Server-Koffer (opt-in)**: 1 komprimierter Blob pro Account nach dem
`houses`-Muster (`visits.js::housesData`, rev-Bump, Größendeckel) — Gerät verloren ≠ Gooby
verloren. WICHTIG serverseitig: vor der Erfolgsantwort synchron flushen (E13 P1-1 gilt für
genau solche bestätigten Mutationen). Code-Anker: `scripts/state/save_manager.gd`,
`scripts/state/game_state.gd` (`state_loaded`), `scripts/ui/settings/umzug_sheet.gd`,
`GOOBY-SERVER/src/visits.js` (Blob-Muster) + `storage.js`. Risiko: niedrig — alles additiv;
einzig der Server-Koffer braucht ein Quota-/Größen-Limit (256-KB-Muster übernehmen,
Save komprimiert deutlich kleiner).

### 13. Batterie-Ruhemodus — 30 fps, wenn nichts passiert
**Aufwand: M · Impact: 4 · Risiko: mittel**

Ein Tamagotchi lebt von langen, ruhigen Sessions — Dauer-60-fps (plus 120-Hz-Displays) sind
dafür Akku-Verschwendung. Neu im `PerfGovernor` (`quality_service.gd`): ein **Ruhe-Zustand** —
nach ~20 s ohne Input in ruhigen Szenen (Home-Idle, Menüs, Radio-Hören) sinkt `Engine.max_fps`
auf 30, Partikel-Faktor auf 0.5, Diorama-/Ambient-Tickraten halbieren sich; der ERSTE Touch
schaltet sofort zurück (Input-Hook zuerst, dann Drossel — nie andersherum, sonst fühlt sich der
erste Tap zäh an). Minispiele, Baumodus, Cutscenes und Besuche bleiben IMMER voll; dazu
`DisplayServer.screen_set_keep_on` nur noch in Minispielen/Kino statt global (prüfen), und eine
Settings-Zeile „Akku-Schoner: auto/aus“ neben den Grafik-Presets. Wirkungs-Beleg kommt über
Idee 3 (Session-Länge/FPS-Histogramm je Modell; Godot exponiert keinen Batteriestand — ehrlich:
die mAh-Messung bleibt manuell am Gerät). Code-Anker: `scripts/platform/quality_service.gd`
(PerfGovernor, `particle_factor`), `scripts/core/scene_router.gd` (Szenen-Klasse „ruhig“),
`scripts/home/gooby_reactions.gd` (Idle-Uhr existiert). Risiko: der 30↔60-Umschaltmoment darf
nie in einer Animation sichtbar ruckeln — Gegenmittel: nur in ruhigen Szenen drosseln,
Übergang an einem Idle-Frame, Playtest-Harness-Flow (G7-P58) als Wächter.

### 14. Ladezeit-Feinschliff am Gerät — Warmup hinter dem Boot-Cover
**Aufwand: M · Impact: 3–4 · Risiko: niedrig**

ERST messen (Idee 3), DANN die drei bekannten Kandidaten in Budget-Reihenfolge: (a)
**Shader-/Pipeline-Warmup**: der Mobile-Renderer (project.godot: `rendering_method="mobile"`,
auf iOS via Metal) kompiliert Pipelines beim ersten Draw — hinter dem Boot-Cover einen
unsichtbaren Warmup-Frame mit den Kern-Materialien rendern (Muster: die „vorgewärmte Musik“ aus
G2f), Godot-4.4-Pipeline-Cache-/Ubershader-Einstellungen prüfen und im Telemetrie-Vergleich
bewerten; (b) **Erstreise-Preloads**: der threaded Home-Warmup existiert (`boot_phasen.gd`
„welt“) — dasselbe Muster für die ERSTE City-/Arcade-Reise im Leerlauf nach dem Boot
(`scene_router.gd`-Preload-Pfad des DOOR_TRAVEL); (c) **Paket-Hygiene**: PCK ~25 MB ist
vorbildlich (E4 §2), die .ipa ~189 MB ist fast nur Template-Binary — Export-Preset auf
abwählbare Module prüfen (kleinere .ipa = schnellerer AltStore-Refresh alle 7 Tage, echter
Sideload-Schmerzpunkt). Jede Maßnahme NUR mit Vorher/Nachher-Zahlen vom echten Gerät (Idee 3),
llvmpipe-Boot-Proxys (E4 §4: ~2,3 s) bleiben Regressions-Wächter, nie Erfolgsbeweis.
Code-Anker: `scripts/boot/main.gd` + `boot_phasen.gd`, `scripts/core/scene_router.gd`,
`.github/workflows/gooby-godot.yml` (Export-Preset). Risiko: niedrig — alles additiv und
messbar; einzige Falle ist Warmup-Arbeit VOR dem ersten Pixel (dann fühlt sich der Boot
langsamer an — Warmup gehört HINTER den ersten Cover-Frame, der Balken ist ehrlich und bleibt es).

### 15. Besuchs-Programm — gemeinsames Foto, Gieß-Hilfe, Gästebuch
**Aufwand: M · Impact: 4 · Risiko: niedrig–mittel**

Besuche (Live-Visits mit Positions-Relay + Couch-Coop existieren, `visit_scene.gd`/
`visit_manager.gd`) haben heute kein „gemeinsam etwas TUN“ außer Fahren. Drei kleine Programme:
(a) **Erinnerungsfoto**: ein Foto-Spot im Wohnzimmer — beide Goobys posieren (Emote-Sync über
den bestehenden visit:-Room-Relay), Snapshot über den Foto-Pfad (`snap_a_gooby.gd`), landet bei
BEIDEN in der Galerie mit Besuchs-Stempel; (b) **Gieß-Hilfe**: der Gast darf 1×/Tag die
Garten-Beete des Hosts gießen (BUILD_DELTA-artiges Relay-Flag, Persistenz beim Host —
Wachstums-Bonus klein halten), Gooby des Hosts bedankt sich beim nächsten Besuch; (c)
**Gästebuch**: nach Besuchsende darf der Gast einen 100-Zeichen-Eintrag + Sticker-Stempel
hinterlassen — serverseitig gedeckelt (Cap 20, `visits.js` hat das Log-Muster samt
VISIT_LOG_CAP schon), angezeigt als Buch-Prop im Flur (Buch-UI-Muster `story_books.gd`).
Code-Anker: `scripts/social/visit_scene.gd` (Relay + Rollen), `scripts/social/snap_a_gooby.gd`,
`GOOBY-SERVER/src/visits.js` (+`rooms.js`-Relay), `scripts/home/garden/garden_state.gd`.
Risiko: Schreib-Rechte sauber halten (Gast schreibt NIE direkt in den Host-Save — alles über
Host-bestätigte Deltas, Muster existiert im Bau-Relay); Gästebuch-Texte durch den vorhandenen
Text-Filter der Mail-Strecke schicken.

### 16. Server-Saison-Momente — kleine globale Ereignisse für alle
**Aufwand: S–M (nach Framework-M) · Impact: 4 · Risiko: niedrig**

Die SERVER_EVENT-Strecke (Push + WELCOME-Pull + Ack, `events.js`/`server_events.gd`) wird heute
kaum inhaltlich bespielt — ein kleines Client-Framework `saison_flags.gd` (Event-Typ →
Content-Flag mit Ablaufzeit, offline degradiert still nach E14-Vertrag) macht liebevolle
Mini-Events per Server-Knopfdruck möglich, OHNE App-Update: **Sternschnuppen-Nacht** (heute
Abend fallen bei ALLEN Sternschnuppen im Fenster-Diorama — Anschluss an IP-1 Idee 4, aus
„selten zufällig“ wird „heute gemeinsam“), **Kürbis-Woche** (Stadt-Deko-Flag + REHWEI-Aktion,
Anschluss IP-2 P9-Saison-Layer), **Doppel-Herz-Sonntag** (Streicheln gibt doppelte Herz-Partikel
— rein kosmetisch, KEINE Economy-Verdopplung ohne Balance-Check). Das Webpanel bekommt eine
„Event planen“-Zeile (Events-Seite existiert). Code-Anker: `scripts/net/server_events.gd`
(`event_received`), `GOOBY-SERVER/src/events.js` + `webpanel/`, `scripts/home/street_diorama.gd`,
`scripts/city/city_bau.gd`-Deko-Pfad. Risiko: niedrig — Flags sind additiv und verfallen; einzig
Zeitzonen sauber über die Server-Zeit definieren (Events tragen `expiresAt`, Client rechnet nie
selbst Kalender).

---

## Übersicht

| # | Idee | Bereich | Aufwand | Impact | Risiko |
|---|---|---|---|---|---|
| 1 | Adaptive Heim-Musik (Stems je Tageszeit/Aktivität) | Audio | L | 5 | mittel |
| 2 | Garten-Geschenk (asynchrone Freundes-Überraschung) | MP | M | 5 | niedrig–mittel |
| 3 | iPhone-Telemetrie + „Geräte“-Panel | Technik | M | 5 | niedrig |
| 4 | Lieblingslied-System + Mixtape-Geschenk | Audio/MP | M | 5 | niedrig |
| 5 | Ducking-API (Stimme/Stinger/Results) | Audio | S | 4 | sehr niedrig |
| 6 | Haptik-Partituren für Schlüsselmomente | Haptik | S–M | 4 | niedrig |
| 7 | Gooby-Stimm-Momente (Summen/Ständchen) | Audio | M | 4–5 | niedrig |
| 8 | Schnurr-Herzschlag (Audio+Haptik-ASMR) | Audio/Haptik | S | 4 | niedrig |
| 9 | Wochen-Challenge-Server (Bestenliste + Live-Ops, Aufsatz auf A4) | MP | L | 5 | mittel |
| 10 | ASMR-Haus-Schicht (Möbel-Foley, Regen ans Fenster) | Audio | M | 4 | niedrig–mittel |
| 11 | Ort-Klangidentitäten (Klang-Steckbriefe) | Audio | M | 4 | niedrig |
| 12 | Save-Sicherheitsnetz (Toast/Auto-Koffer/Server-Kopie) | Technik | M | 4 | niedrig |
| 13 | Batterie-Ruhemodus (adaptive 30 fps) | Technik | M | 4 | mittel |
| 14 | Ladezeit-Feinschliff (Warmup/Preload/Paket) | Technik | M | 3–4 | niedrig |
| 15 | Besuchs-Programm (Foto/Gießen/Gästebuch) | MP | M | 4 | niedrig–mittel |
| 16 | Server-Saison-Momente (Sternschnuppen-Nacht …) | MP | S–M | 4 | niedrig |

## Paket- und Reihenfolge-Hinweise für den Konsolidierer (Welle J+)

- **Sofort-ROI-Paket „Klang-Momente“:** 5 + 8 + 6 (+7) — klein, testbar, sofort fühlbar;
  Zuschnitt von 5 VOR Start mit dem IMPL-AUDIO-Worker abstimmen (Mix-Wache) und mit
  `G8-IDEEN-ui-juice.md` J13/J6 zu je EINEM Baustein verschmelzen (Duck-API, Partitur-Engine).
- **Musik-Paket:** 1 (+4) — 4 ist unabhängig startbar (nur Zähler + Reaktionen), 1 braucht die
  Stem-/Varianten-Entscheidung zuerst (Asset-Frage klären, Fallback einpreisen).
- **MP-Paket A (async zuerst):** 2 → 15 → 16; 2 teilt sich das Server-Fundament mit
  `G8-IDEEN-progression.md` Nr. 3 (ein Geschenk-Modul, zwei Erlebnisse). 9 separat (größter
  Server-Anteil) und NACH `G8-IDEEN-minispiele-arcade.md` A4 einplanen (9 ist dessen
  Server-Aufsatz). Alle Server-Module erben die E13-Lektionen: bestätigte Mutation ⇒
  synchroner Flush, Zustellung ⇒ nur mit Client-Ack.
- **Technik-Reihenfolge zwingend:** 3 VOR 13/14 (erst messen, dann drehen); 12 ist unabhängig
  und jederzeit landbar.
- **Durchgehende Leitplanken:** alle neuen Sounds durch die EF-2-Pegelstraße
  (`tools/audio/ef2_manifest.py`, Peak ≤ −1 dBFS, Effekt-Ebene ~−22 dBFS eff.); alle neuen
  Momente RM-gated und durch die Frequenzbremse (`SoulTriggers.ambient_allowed`); Strings
  DE führend + EN-Parität mit Domain-OWNERSHIP; Zeit/Zufall immer injizierbar (headless- und
  Playtest-Harness-testbar, G7-P58); Haptik respektiert Stufe + „aus“ über `Haptics.is_enabled`.
