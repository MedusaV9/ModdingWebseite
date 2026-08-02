# EVAL-1 — Dopamin, Sounddesign, Spielgefühl (Prüfbericht)

Stand: 2026-07-27, Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`), Godot 4.4.1 headless.
Auftrag: unabhängige Bewertung des GANZEN Spiels (nicht nur Minigames) auf
Belohnungsdichte, Klangbild und Spielgefühl — hart, konkret, mit Zahlen.
**Dieser Bericht ändert keinen Spielcode.** Alle Zahlen sind gemessen, nicht geschätzt.

## Methodik (reproduzierbar)

| Werkzeug | Was es misst | Artefakt |
|---|---|---|
| `eval1_dopamin_probe.gd` (SceneTree-Sonde) | Erste-10-Minuten-Flow headless: Boot → Onboarding → Zuhause (75 s Idle) → Streicheln → Bad-Pflege → carrotCatch → Results → Shop. Loggt JEDEN Belohnungsmoment (Coins/XP/Level/Stat+/Partikel) + JEDEN SFX-Abspielzeitpunkt (Poll von `AudioDirector._last_played_msec` + `FeelSfx`) + Musikwechsel mit Zeitstempel | `/tmp/gooby-godot/artifacts/EVAL1/dopamin_run1.log` |
| `eval1_probe2.gd` | Nachmessungen: Dusche korrekt (2-Tap), IKEA via HUD, Tür-Reisezeiten, Idle-Bubble-Zählung | `.../probe2_run.log` |
| `eval1_probe3.gd` | Input-Latenz in Frames (Fenster 1280×720, Touch in Letterbox-Koordinaten), SquishButton-Reaktion | Konsolenlog (unten zitiert) |
| `analyze_audio.py` (ffmpeg + numpy) | ALLE 150 gemappten Audiodateien (71 SFX, 51 Musik, 28 unmapped): Peak/RMS/Loudness dBFS, effektiver Playback-Pegel (inkl. `volume_db`-/`gain_trim`-Anwendung), Spektral-Zentroid, Energie >4 kHz, Attack, End-Klick, Loop-Naht | `.../audio_analysis.csv`, Spektrogramme `.../spektrum_*.png` |
| Movie-Maker-Aufnahme (xvfb, `--write-movie`) | Video MIT TON des Kernflows als Hör-/Sichtbeleg | `.../eval1_flow.mp4` |

---

## 1. Dopamin-Kurve — gemessen

### 1.1 Belohnungs-Timeline des Messlaufs (212 s komprimierter Erstflow)

Der Lauf entspricht inhaltlich den typischen ersten ~10 Minuten (Onboarding auf
~8 s gerafft; ein echter Spieler braucht 60–90 s — die Lücken werden real also
noch LÄNGER).

| t (s) | Phase | Belohnungsmoment | Art | Intensität |
|---|---|---|---|---|
| 0–3.3 | Boot | — | — | — |
| 3.3–11.3 | Onboarding | Abschluss-Konfetti + `mg_win`-Klang (t=9.1) | Konfetti+Fanfare | mittel |
| 11.3 | Home-Ankunft | Musik startet, Begrüßungs-Soul-Moment (`ui_levelup`-Pluck + Bubble) | Lob | klein |
| **11.3–86.3** | **Home-Idle (75 s)** | **NICHTS. 0 Ereignisse, 0 Bubbles, 0 SFX** | — | — |
| 86.3–90 | Streicheln (8 Taps) | 2 leise Pops (`gvz_pop`), 1 Soul-Moment-Pluck. **Kein Coin, kein Stat, kein Partikel** | Lob (mager) | sehr klein |
| 96–107 | Dusche + Zahnputz | Hygiene +15 — **ohne Sound, ohne Partikel, ohne Zahl-Popup** (Lauf 2, t=57.3) | Stat | unsichtbar |
| 123–142 | carrotCatch spielen | 11× Fang (`mg_good` + Combo-Ton steigend), 1× Golden (Partikel + `mg_golden`) | Mikro-Belohnungen | gut! |
| **143.2** | **Results** | **+50 Coins, +15 Spaß, +25 XP GLEICHZEITIG; dann Count-Up (10 Ticks), 3 Sterne, Rekord-Konfetti, Münzregen, `game_record`** | Cluster | groß |
| 168–180 | IKEA-Kauf | −10 Coins, `ui_confirm`. **Kein Kauf-Jingle, kein Partikel, keine Feier** | Ausgabe | keine |
| 182–212 | Final-Idle (30 s) | NICHTS | — | — |

**Zählung:** 9 Belohnungsmomente in 212 s — davon 6 im EINEN Results-Cluster.
**Größte Durststrecken: 131,2 s und 67,4 s** (gemessen, `[EVAL1-SUM]` im Log).
Auf reale 10 Minuten hochgerechnet (Onboarding in Echtzeit, 1–2 Minigame-Runden):
**2–3 Belohnungscluster, dazwischen 2–4 Minuten Leerlauf.**

### 1.2 Benchmark-Vergleich (Animal Crossing / gute Wohlfühlspiele)

AC liefert kleine Belohnungen im **~60–90-Sekunden-Takt** (Nachbar ruft, Fossil,
Balloon, Nook-Meilen-Ping) und große alle 5–10 min. GOOBY liefert aktuell:
**alles im Minigame-Results, fast nichts außerhalb.** Die Kurve ist kein Sägezahn
(gesund), sondern ein Nadel-Impuls pro Minigame-Runde mit Flatline dazwischen.

### 1.3 Dopamin-Befunde

| # | Befund | Wo | Prio | Konkreter Vorschlag |
|---|---|---|---|---|
| D1 | **Füttern existiert nicht.** `hunger` fällt −0,35/min und ist NUR über den Zufalls-Event `mehl_klopfen` (+12, `event_runner.gd:868`) hebbar. Kein Kühlschrank-Interactable, kein Essens-Menü. Veil-Tipp Nr. 1 (`strings/de/veil.json`) verspricht sogar „Kühlschrank checken!“ | `scripts/home/interactables/` (fehlt), `strings/de/veil.json` | **P0** | Kühlschrank-Interactable in der Küche: Tap → 3 Snacks zur Wahl, +25 Hunger, Kau-Sound (3 Nom-Silben, Pitch 0,9/1,0/1,1), Herz-Partikel-Burst (12 Stück), `feeds`-Counter +1 |
| D2 | **Sticker schalten nur bei offenem Album frei.** `StickerUnlocks` wird ausschließlich in `album_screen.gd:497` attached; im normalen Spiel wird NIE evaluiert, nichts gefeiert. 141 Sticker sind ein totes Dopamin-Reservoir | `scripts/ui/album/sticker_unlocks.gd`, `album_screen.gd` | **P0** | Service als Autoload/`home_entry`-Kind attachen; bei Unlock global: Toast mit Sticker-Icon + `ui_sticker`-Pluck + 40er-Konfetti-Burst, 2,5 s |
| D3 | **`feeds`/`washes`-Counter werden nirgends inkrementiert** → Sticker `firstNom` (feeds≥1) und `squeakyClean` (washes≥1) sind UNERREICHBAR; Recap-Zeile „{n}× lecker gefuttert“ bleibt ewig 0 | `finish_shower()` in `klo_dusche.gd` (kein Counter), Füttern fehlt (D1) | **P0** | `washes += 1` in `finish_shower()`; `feeds` mit D1 einführen |
| D4 | **75 s Home-Idle = 0 hörbare/sichtbare Momente** (gemessen: 0 Bubbles, 0 Babble-Frames, 0 SFX in 75 s + 40 s + 30 s Idle über 2 Läufe). Idle-Akte (alle 18–35 s, `gooby_reactions.gd:26`) sind stumme Laufwege; 55 % ohne Text | `gooby_reactions.gd:253` (`_perform_idle`) | **P1** | Jedem Idle-Akt einen leisen Klang geben (Schritte-Tapsen ~−28 dB, Möbel-Plumps); Text-Quote von 45 % auf 70 %; 1×/90 s Mini-Fund: Funken-Partikel am Gooby + `ui_coins`-Pluck, +1 Coin |
| D5 | **Streicheln belohnt nichts.** 8 Taps → nur `petsToday`-Counter (unsichtbar) + gelegentlicher Soul-Text. Kein Stat, kein Herz, kein aufsteigendes Feedback | `gooby_reactions.gd:194` (`handle_tap`) | **P1** | Pro Tap: Squish-Sound (Pitch +0,05/Tap bis +0,4), 3 Herz-Partikel; jeder 10. Pet: +2 Spaß + großes Herz; Kitzel-Stufe: Kicher-Babble |
| D6 | **Pflege-Erfolg ist unsichtbar:** Dusche gibt +20 Hygiene (gemessen +15,1 nach Decay) — ohne Zahl, ohne Glitzer, ohne Klang. Klo/Zähneputzen ebenso | `klo_dusche.gd:105`, `zahnputz.gd` | **P1** | Beim Abschluss: `float_text("+20", Mint)` über dem Gooby, 14 Glitzer-Partikel, Erfolgs-Pluck (`ui_confirm`-Familie, +2 Halbtöne) |
| D7 | **IKEA-Kauf ist ein Nicht-Ereignis:** −10 Coins, `ui_confirm` (gemessen t=68.2, Lauf 2). Kein Kaching, keine Feier, keine Vorfreude auf Lieferung | `ikea_screen.gd:567` | **P1** | `ui_buy` (Kaching, ist gemappt & UNBENUTZT!) + `scale_pop` der Karte (1,12, 200 ms) + 20er-Konfetti in Markenfarbe + Toast „Wird geliefert!“ |
| D8 | **Level-Up im Hauptspiel ist eine Textzeile.** `mg.results.level_up` im Results (`results.gd:123-129`) — kein Stinger, kein Vollbild-Moment. Die Ranch hat mit `levelup_feier.gd` bereits eine fertige Feier; `stinger-levelup.ogg` (6 s) wird nur im Recap benutzt | `results.gd`, `scripts/ranch/gameplay/levelup_feier.gd` | **P1** | Bei `levelsGained > 0`: nach dem Count-Up (t+1,2 s) LevelUp-Overlay (Ranch-Muster): Gold-Titel „Level %d!“, `stinger-levelup`, 110er-Konfetti, Musik 3 s um −6 dB ducken |
| D9 | Onboarding endet stark (Konfetti + `mg_win`), aber die ersten ~60 s danach sind das Loch D4 — der „erste Tag“ hat keine geführten Mini-Ziele („Streichle Gooby“, „Schau in den Kühlschrank“, „Spiel ein Spiel“) mit je +5 Coins | `home_entry.gd` | **P2** | 3-Schritte-Checkliste als HUD-Chip, je Schritt: Haken-Pop + `ui_confirm` + 5 Coins mit Münz-Flug zur HUD |
| D10 | Coin-Zähler im HUD animiert (Count-Up + Wiggle, `hud.gd:377-387`) aber STUMM — `ui_coins` ist gemappt und wird beim echten Coin-Gewinn nie gespielt (nur im seltenen Sofa-Fund-Soul-Moment) | `hud.gd:384` | **P2** | Bei positiver Differenz: `ui_coins` mit Pitch 1,0 + 0,02×log(Δ) |

---

## 2. Sounddesign — gemessen (150 Dateien analysiert)

### 2.1 Mix-Balance: Musik erdrückt die Effekte

| Gruppe | Median eff. Loudness (nach Trim) | Spannweite |
|---|---|---|
| Musik (51 Tracks) | **−13,4 dBFS** | −12,1 … −19,9 |
| SFX (71 Sounds) | **−22,4 dBFS** | −14,9 … −36,2 |

**Die Musik läuft im Schnitt ~9 dB lauter als die Effekte.** Die weichen
FIX-4-UI-Plucks (−17…−18 dB eff.) und erst recht `mg_spill` (−28,8) gehen unter,
sobald Musik spielt. Referenz AC: Musik sitzt 6–10 dB UNTER den Interaktions-Sounds.

### 2.2 Digitales Clipping (hart, hörbar als Knacken/Verzerrung)

- **37 von 51 Musiktracks** haben nach Anwendung ihres `gain_trim` einen
  effektiven Peak **> 0 dBFS** (Spitzenreiter: `location-ikea-quest` **+5,4 dB**,
  `game-sternenhopser` +5,0, `stinger-results` +4,4, `room-pixie-puddle-sleeping`
  +4,4 — ein SCHLAF-Track, der clippt). Quelle: `music_registry.gd` `gain_trim`
  (bis 6,0 = +15,6 dB) auf bereits heiße Dateien.
- **20 SFX-Quelldateien** peaken selbst über 0 dBFS (alle Kenney-Impacts der
  GvZ-/mg-Familie, `mg_combo` +4,0, `ranch_huf_holz` +4,3) — die negativen
  `volume_db`-Trims retten das meist, aber nicht überall (`ranch_fanfare_sieg`
  eff. Peak −1,2 bei 6 s Dauer).

### 2.3 Klangfarben-Ausreißer (Spektralanalyse)

| Sound | Messwert | Problem |
|---|---|---|
| `gvz_collect` (glass_004) | **100 % Energie >4 kHz, Zentroid 7339 Hz** | Grelles Glas-Klirren als Sammel-Sound — nach 10 Sonnen im GvZ-Level schmerzt es (Spektrogramm `spektrum_gvz_collect.png`) |
| `mg_win` (confirmation_003) | 51,7 % >4 kHz bei −3 dB Trim | Sieg-Sound deutlich greller als die weiche soft/-Familie daneben |
| `game_hit` | Ende bei −24,7 dBFS (letzte 5 ms), 148 ms | **Abschneide-Klick** am meistgespielten Sound aller Spiele |
| `mg_spill`/`mg_junk` (−28,8/−25,5 eff.) vs `mg_go` (−15,3) | 13,5 dB Spanne innerhalb einer Familie | Fehler-Feedback fast unhörbar, Start-Sound laut |
| `ranch_huf_trab/galopp`-Loops | −31,4 eff. | Unter Musik (−13) praktisch weg — Hufschlag ist DAS Ranch-Feedback |

### 2.4 Musik-Loops und Kontextwechsel

- **Loop-Nähte:** Kontext-Tracks loopen roh (`AudioStreamOggVorbis.loop = true`,
  `music_director.gd:257`). Gemessene Anfang/Ende-Pegeldifferenz >8 dB bei
  **praktisch allen** Tracks; Extremfälle `game-spielzeugflitzer` 95,5 dB und
  `game-splat-wunderwelt` 84,7 dB = Track endet voll und springt hart in ein
  Fade-in-Intro — alle ~85 s ein hörbarer Bruch.
- **Kontextwechsel funktionieren** (gemessen: living→`room-cloud-hopper…`,
  bathroom→`room-blubberbad`, arcade→`room-pitter-patter-fun`; Crossfade 1,5 s
  greift). ABER: **Onboarding hat KEINE Musik** (erste Ankunft im Spiel = Stille
  + Klick-Plucks, Musik startet erst mit `travel_finished` home/living), und
  **30 von 37 spielbaren Games teilen den einen Arcade-Track** (nur 7 `game:`-
  Kontexte in `music_registry.gd`; GvZ, GobNom, teaParty, carrotCatch … spielen
  alle dieselbe Arcade-Schleife).
- **Kein Ducking:** Results-Fanfare, Level-Up, Rekord-Konfetti kämpfen ungeduckt
  gegen die −13-dB-Musik (kein Sidechain/Duck im `MusicDirector`).

### 2.5 Abdeckung: Was klingt NICHT?

Gemessen im Flow-Log + Code-Audit:

| Interaktion | Ist | Soll |
|---|---|---|
| Pflege (Dusche 10 s, Klo, Zähneputzen) | **komplett stumm** (0 SFX zwischen Tap 1 und Abschluss, `klo_dusche.gd`/`zahnputz.gd` enthalten keinerlei `try_play`) | Wasser-Loop, Zahnbürsten-Schrubben, Spülung, Erfolgs-Pluck |
| Gooby-Streicheln | nur bei Soul-Stufen 3/6 leiser `gvz_pop` | Squish pro Tap mit Pitch-Treppe |
| Erfolgs-Toasts | bewusst stumm (`toast.gd:72` „Erfolgs-Toasts bleiben stumm“); `ui_toast` nur via Soul-Defs | leiser `ui_toast` für positive Toasts |
| HUD-Coin-Änderung | stumm (D10) | `ui_coins` |
| Sticker-Unlock (außerhalb Album) | stumm + unsichtbar (D2) | `ui_sticker` + Toast |
| Gooby-Schritte/Türen im Haus | stumm (Tür-Gag hat Bubble, keinen Klang; `door_knock` ist gemappt aber nur 2× verdrahtet) | Taps-Taps-Schritte, Tür-Quietsch+Knall |
| GoobyVoice-Gebrabbel | klingt — aber auf dem **Master-Bus statt Voice-Bus** (`gooby_voice.gd:44-49` setzt kein `player.bus`); Settings-Regler „Stimme“ ist dafür WIRKUNGSLOS; Silben-WAVs sind mit −8…−14 dBFS RMS die lautesten Sounds im Spiel | `bus = &"Voice"` + −6 dB Trim |
| UI-Buttons (HUD/Arcade/Pregame/Settings/Panels) | gut abgedeckt (ui_click/chip/open/close verdrahtet) | ✓ |
| Minigame-Momente (Hit/Miss/Combo/Countdown/Win/Lose) | gut abgedeckt (FeelSfx-Kontrakt + Tests) | ✓ |

### 2.6 Sound-Befunde

| # | Befund | Wo | Prio | Vorschlag mit Zahlen |
|---|---|---|---|---|
| S1 | Musik ~9 dB zu laut relativ zu SFX; 37 Tracks clippen nach `gain_trim` | `music_registry.gd` (gain_trim), Music-Bus | **P0** | Music-Bus-Default auf **−10 dB** (AppSettings `audio.music` Default 0,45 statt 1,0) ODER alle `gain_trim` so normalisieren, dass eff. Loudness −23 LUFS ≈ −20 dBFS RMS und eff. Peak ≤ −1 dBFS; zusätzlich Limiter-Effekt auf dem Master-Bus (Threshold −1 dB) |
| S2 | Loop-Nähte: alle Kontext-Tracks springen hörbar (bis 95 dB Pegeldifferenz an der Naht) | `music_director.gd:257`, Assets | **P0** | Pro Track Loop-Punkte nach dem Intro setzen (Ogg `LOOPSTART`-Tag, von Godot unterstützt) — Intro einmal, Loop ab Takt 2; für die 5 schlimmsten (spielzeugflitzer, splat, ikea-quest, kichergeister, cloud-hopper) zuerst |
| S3 | GoobyVoice am Voice-Bus vorbei + lauteste Assets des Spiels | `gooby_voice.gd:45` | **P1** | `player.bus = &"Voice"` je Pool-Player; `volume_db = −8.0`; max_polyphony bleibt |
| S4 | `gvz_collect` grell (7,3 kHz Zentroid, 100 % >4 kHz) beim häufigsten GvZ-Event | `sfx_map.gd:78` | **P1** | Ersetzen durch weichen Pluck ~1,2 kHz (soft/-Familie, wie `soft_coins`), Trim −7 dB, Pitch-Jitter 0,06 behalten |
| S5 | `game_hit` endet mit Klick (−24,7 dBFS Restpegel) | `assets/audio/sfx/game/game_hit.ogg` | **P1** | 30-ms-Fade-out auf die Datei rendern (numpy-Tool existiert laut FIX-4-Kommentar) |
| S6 | `mg_win` zu grell für die AC-Ästhetik (51,7 % >4 kHz) | `assets/audio/sfx/confirmation_003.ogg` | **P2** | Tiefpass 5 kHz (−12 dB/Okt) oder Ersatz aus der soft/-Synthese (Dur-Dreiklang-Pluck 660/830/990 Hz, 320 ms) |
| S7 | Fehler-Feedback zu leise: `mg_spill` −28,8/`mg_junk` −25,5 eff. vs Familie −18 | `sfx_map.gd:69-70` | **P2** | Trims von −8 auf **−4 dB** anheben (Ziel eff. −22) |
| S8 | Kein Musik-Ducking bei Belohnungs-Stingern | `music_director.gd` | **P2** | `duck(db=−6, attack=80 ms, hold=1,5 s, release=600 ms)`-API; Aufruf aus Results (`show_results`) und Level-Up |
| S9 | 30/37 Spiele teilen den Arcade-Track; GvZ/GobNom (die zwei User-Wunsch-Spiele!) ohne eigene Musik | `music_registry.gd` (nur 7 game:-Kontexte) | **P2** | Mindestens `game:gvz` (spannungsgeladen, 100 BPM moll) und `game:gobnom` (verspielt) ergänzen |
| S10 | `ui_levelup` wird durch Soul-Grüße entwertet (Begrüßung spielt denselben Pluck wie Level-Up; 6 Soul-Defs nutzen ihn) | `content/soul/data/soul.json` | **P2** | Grüße auf `ui_chip`/eigenen Gruß-Pluck mappen; `ui_levelup` exklusiv für Progression |
| S11 | 9 tote Kenney-Altlasten unter `assets/audio/sfx/` (click_001/003, back_002, open/close_001, confirmation_002, error_004, switch_002, tick_002 — von nichts referenziert) | `assets/audio/sfx/` | P2 | Löschen oder in SfxMap aufnehmen — verhindert versehentliche Wiederverwendung der harten Klicks |

---

## 3. Spielgefühl — gemessen

### 3.1 Messwerte

| Metrik | Messwert | Bewertung |
|---|---|---|
| Input → Spiellogik (carrotCatch `target_x`) | **1 Frame** | ✓ exzellent |
| Input → sichtbare Korb-Bewegung | **2 Frames (~33 ms)** (Lerp-Faktor 14/s, Zeitkonstante ~71 ms) | ✓ sehr gut, fühlt sich „leicht“ an |
| SquishButton down → Scale-Reaktion | **1 Frame** (0,96-Squish, TRANS_BACK zurück) | ✓ |
| Boot → home_entry instanziert | 3,3 s (headless) | ok |
| **Raum→Raum-Tür (Vollveil)** | **908–1051 ms** JEDES Mal (`min_shown_ms=600` + Fades, `scene_router.gd:57`) | ✗ zäh für einen Hausflur |
| HUD-Tap → IKEA benutzbar | **3010 ms** (Doppel-Reise: erst home/living, dann ikea = 2 Veils) | ✗ |
| PLAY → Minigame spielbar | **3210 ms** (Veil ~1,3 s + Countdown 3×0,8 s) | mittel |
| „Nochmal“ → wieder spielbar | erneut voller 3-2-1-Countdown (2,4 s) | ✗ Retry-Friktion |
| report_end → Results sichtbar | **917 ms** bewusste „Atempause“ (`minigame_host.gd:318`) | nur sinnvoll, wenn das Spiel den Moment füllt — s. F3 |
| Countdown-Feedback | 3 Ticks mit Pitch-Treppe (0,9→1,14) + GO | ✓ |
| Portrait-Spiel im Landscape-Fenster | Letterbox nutzt **299 von 1280 px (23 %)**, Rest schwarz | ✗ auf Desktop/iPad karg |

### 3.2 Feel-Befunde

| # | Befund | Wo | Prio | Vorschlag |
|---|---|---|---|---|
| F1 | **Jede Haustür = 1 s Schwarzblende.** bathroom→living 1012 ms, living→kitchen 947 ms gemessen. Das Haus fühlt sich wie 5 Ladescreens an, nicht wie EIN Zuhause. `DOOR_TRAVEL` existiert als Enum (`scene_router.gd:43`), der additive Tür-Modus ist Backlog A | `scene_router.gd`, `home_entry` | **P0** | Raumwechsel im Haus auf DOOR_TRAVEL ohne Veil: Tür-Wipe 250 ms (Kamera-Slide oder Iris), `min_shown_ms` für DOOR auf 0; Ziel <350 ms |
| F2 | **Retry-Friktion:** „Nochmal“ durchläuft den vollen 3-2-1 (2,4 s). Arcade-Spiele leben von schnellen Retries | `minigame_host.gd:269` (`_run_countdown`), `_on_again_pressed` | **P1** | Bei Restart aus Results: nur „GO“ mit 0,5 s + `hit_flash` statt 3-2-1; Erststart behält 3-2-1 |
| F3 | **0,9 s toter Standbild-Moment am Rundenende:** nur 5/37 Spiele rufen `win_moment()` (delivery_rush, harbor_hopper, memory_match, mini_golf, toy_racer) — die anderen 32 frieren nach `report_end` kommentarlos ein, bis Results kommt (gemessen: keinerlei Events in den 917 ms) | alle Games ohne `win_moment`, `minigame_host.gd:318` | **P1** | Host übernimmt: wenn das Spiel bis 100 ms nach `report_end` selbst nichts feiert → automatisch `juice.win_moment()` (Zeitlupe 0,35/420 ms + Goldblitz + 70er-Konfetti); Atempause dann verdient |
| F4 | **Countdown-Wartezeit ist leer:** 2,4 s Zahlen ohne Spielfeld-Bezug; kein „Bereitmach“-Moment (AC-Minigames zeigen Charakter-Idle + aufbauende Musik) | `minigame_host.gd:269` | **P2** | Countdown-Step auf 0,6 s (Gesamt 1,8 s); pro Tick `hit_flash` weiß 40 ms über dem Spielfeld; GO mit `shake(0.15)` |
| F5 | Doppel-Veil zum Shop (HUD→living→ikea, 3,0 s) — HUD-Aktionen aus anderen Räumen zahlen zwei Reisen | `home_entry._on_hud_action` | **P2** | Direkt-Route `ikea` von jedem Raum (ein Veil), Ziel <1,2 s |
| F6 | Letterbox-Balken sind nacktes Schwarz (77 % des Screens bei Portrait-Spiel auf Landscape) | `minigame_host.gd:117-132` | **P2** | Balken mit Theme-Creme (0.98/0.94/0.87) + 8 %-Vignette + Spiel-Logo oben füllen — wie `bg` bereits existiert, nur zieht der SubViewportContainer nicht mit |
| F7 | Dusche: zwischen Tap 1 und Tap 2 vergehen ~10 s ohne jedes Feedback außer Vorhang (kein Wasser-Loop, kein Blubber-Partikel, kein Fortschritt) | `klo_dusche.gd:60-105` | **P1** | Wasser-Loop (−20 dB) + 6 Dampf-Partikel/s + nach 4 s Peek-Gag-Sound; Abschluss s. D6 |
| F8 | Idle-Wandern des Gooby ist stumm und ohne Gewicht (keine Schritte, kein Möbel-Kontakt-Feedback) | `gooby_home.gd:343` (`_step_walk`) | **P2** | Taps-Geräusch pro Schrittzyklus (~−30 dB, Pitch-Jitter 0,1), kleiner Squash 1,04 im Schrittrhythmus |
| F9 | `ui_open`/`ui_close` feuern bei JEDER Veil-Reise (gemessen: jedes Raumwechsel-Paar) — das Panel-Vokabular wird für Reisen zweckentfremdet und nutzt sich ab | Veil/Router-Wiring | **P2** | Reisen bekommen eigenes leises Whoosh-Paar (−14 dB, 250 ms), `ui_open/close` bleiben Panels vorbehalten |
| F10 | Erste-Session-Anomalie: beim allerersten Home-Veil spielt ein `ui_levelup`-Pluck (Soul-Gruß `gruss_vermisst` — „vermisst“ beim ERSTEN Treffen) | `content/soul/data/soul.json` (Gruß-Defs), `gooby_reactions._run_enter` | P2 | Erst-Boot-Gruß auf eigenen Freude-Gruß mappen (`gruss_neu`), `vermisst` erst ab 2. Session (Bedingung `lastSeen > 0`) |

---

## 4. Rangliste — die 25 wirkungsvollsten Verbesserungen

Sortiert nach (Spielerwirkung × Häufigkeit des Moments) / Aufwand. Nummern
referenzieren die Befunde oben.

| Rang | Maßnahme | Befund | Prio |
|---|---|---|---|
| 1 | **Kühlschrank/Füttern bauen** (+25 Hunger, Nom-Sounds, Herz-Burst, `feeds`-Counter) — schließt Kernloop UND macht `firstNom`-Sticker + Recap-Zeile erreichbar | D1+D3 | P0 |
| 2 | **Sticker-Unlocks global auswerten + feiern** (Toast + `ui_sticker` + Konfetti überall, nicht nur im Album) — 141 fertige Belohnungen aktivieren | D2 | P0 |
| 3 | **Musik −10 dB / Peaks ≤ −1 dBFS normalisieren + Master-Limiter** — repariert 37 clippende Tracks und lässt alle Feel-Sounds atmen | S1 | P0 |
| 4 | **Haus-Türen ohne Vollveil** (DOOR_TRAVEL, <350 ms Wipe) — spart ~700 ms pro Raumwechsel, zigmal pro Session | F1 | P0 |
| 5 | **Musik-Loop-Punkte setzen** (LOOPSTART nach Intro; die 5 schlimmsten zuerst) — beendet den hörbaren Bruch alle ~85 s | S2 | P0 |
| 6 | **Home-Idle beleben:** Idle-Akte vertonen, Text-Quote 70 %, Mini-Fund alle 90 s (+1 Coin, Funken) — bricht die gemessene 131-s-Flatline | D4 | P1 |
| 7 | **Pflege fühlbar machen:** Wasser-/Bürsten-Foley + „+20“-Float + Glitzer + `washes`-Counter | D6+F7+D3 | P1 |
| 8 | **Streicheln belohnen:** Squish-Pitch-Treppe, Herz-Partikel, jeder 10. Pet +2 Spaß | D5 | P1 |
| 9 | **Level-Up-Feier im Hauptspiel** (Ranch-`levelup_feier` wiederverwenden, `stinger-levelup`, Musik-Duck) | D8 | P1 |
| 10 | **Retry ohne 3-2-1** („Nochmal“ → GO in 0,5 s) — Minigame-Wiederspielrate ist der größte Dopamin-Hebel im Bestand | F2 | P1 |
| 11 | **Auto-`win_moment()` im Host** für die 32 Spiele ohne Endfeier (füllt die tote 0,9-s-Atempause) | F3 | P1 |
| 12 | GoobyVoice auf Voice-Bus + −8 dB (Settings-Regler funktioniert dann wirklich) | S3 | P1 |
| 13 | `gvz_collect` durch weichen 1,2-kHz-Pluck ersetzen (häufigster GvZ-Sound) | S4 | P1 |
| 14 | IKEA-Kauf feiern (`ui_buy`-Kaching + Karten-Pop + Mini-Konfetti + Liefer-Toast) | D7 | P1 |
| 15 | `game_hit`-Klick wegfaden (30 ms Fade-out) — meistgespielter Sound aller Games | S5 | P1 |
| 16 | HUD-Coin-Zähler vertonen (`ui_coins` bei jedem Zuwachs) | D10 | P1 |
| 17 | Musik-Ducking-API (−6 dB, 80 ms Attack) für Results/Level-Up/Rekord | S8 | P2 |
| 18 | Erster-Tag-Checkliste (3 geführte Mini-Ziele à +5 Coins) gegen das Onboarding-Loch | D9 | P2 |
| 19 | Fehler-Sounds anheben (`mg_spill`/`mg_junk` auf eff. −22 dB) — Fehler müssen fühlbar sein, sonst wirkt Treffen billig | S7 | P2 |
| 20 | Eigene Tracks für `game:gvz` + `game:gobnom` (die zwei explizit gewünschten Spiele) | S9 | P2 |
| 21 | Direkt-Route zum IKEA (ein Veil statt zwei, <1,2 s) | F5 | P2 |
| 22 | Letterbox-Balken thematisieren (Creme + Vignette + Logo statt Schwarz) | F6 | P2 |
| 23 | Countdown 0,6 s/Step + Tick-Flash + GO-Shake | F4 | P2 |
| 24 | Erfolgs-Toasts leise vertonen (`ui_toast`) + `mg_win` entgrellen (Tiefpass 5 kHz) | 2.5+S6 | P2 |
| 25 | Gooby-Schritte im Haus (leises Tapsen + Mini-Squash) — macht das Haustier körperlich | F8 | P2 |

## Anhang: Artefakte

Alle unter `/tmp/gooby-godot/artifacts/EVAL1/`:

- `dopamin_run1.log` — vollständiges Belohnungs-/SFX-Protokoll des Erstflows (Zeitstempel)
- `probe2_run.log` — Nachmessungen (Dusche, IKEA, Türzeiten, Idle-Zählung)
- `audio_analysis.csv` — 150 Dateien × 16 Messwerte (Peak/RMS/Loudness/eff. Pegel/Zentroid/…)
- `spektrum_gvz_collect.png`, `spektrum_mg_win.png`, `spektrum_game_hit.png`, `spektrum_ui_click.png`, `spektrum_home_musik.png` — Spektrogramme
- `eval1_flow.mp4` — Video MIT TON des Kernflows (Onboarding → Home → Streicheln → Dusche → Arcade → carrotCatch → Results → IKEA); man HÖRT die Musik-Dominanz und die stummen Pflege-Momente
- `eval1_dopamin_probe.gd`, `eval1_probe2.gd`, `eval1_probe3.gd`, `eval1_video_probe.gd`, `analyze_audio.py` — Messwerkzeuge (reproduzierbar)
