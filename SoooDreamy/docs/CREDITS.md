# Credits & Lizenzen

<!-- Audio-Sektion generiert aus sound_credits.json —
     bash ios/scripts/generate_credits_md.sh — nicht von Hand editieren. -->

## Audio

SoooDreamy klingt hybrid: Die prozedurale Synthese
(`ios/SoooDreamy/Core/SoundEngine.swift`) bleibt das Herz und der ewige
Fallback jedes Cues — zusätzlich tragen ausgewählte Cues gebündelte
CC0-Aufnahmen (`Resources/Sounds/cue_<id>.caf`, 13 Dateien), die den
Klängen echtes Material geben (Papier, Wachs, Glas, Wasser, Würfel). Fehlt
eine Datei oder lässt sie sich nicht dekodieren, greift still die Synthese —
kein Cue hängt je von einer Datei ab.

Alle Quellen, Lizenzen und Laufzeit-Gains stehen in
`ios/SoooDreamy/Resources/Sounds/sound_credits.json` (Schema samt
SHA-256-Beleg der Rohdatei). Ein LogicTest erzwingt: Lizenz auf der
Allowlist (CC0-1.0, CC-BY-3.0/4.0, Pixabay), CC-BY nur mit vollständiger
Attribution, ≤120 KB pro Cue, ≤1.5 MB gesamt, keine Waisen-Dateien.
Das Credits-Panel in den Einstellungen wird aus derselben JSON generiert.

### Gebündelte Aufnahmen

| Cue | Aufnahme | Autor:in | Lizenz | Quelle | Bearbeitung |
| --- | --- | --- | --- | --- | --- |
| `received` | Glass Ping | tix99 | CC0-1.0 | [Quelle](https://freesound.org/s/745014/) | getrimmt (1.1 s), mono, Fades, auf -6 dBTP normalisiert |
| `sealed` | Wax seal | Cerise_Virtuelle | CC0-1.0 | [Quelle](https://freesound.org/s/759526/) | getrimmt (0.9 s), mono, Fades, auf -6 dBTP normalisiert |
| `unseal` | Packaging Paper Tear Short | afleetingspeck | CC0-1.0 | [Quelle](https://freesound.org/s/140461/) | getrimmt, mono, Fades, auf -6 dBTP normalisiert |
| `kiss` | Short kiss | Vospi | CC0-1.0 | [Quelle](https://freesound.org/s/344209/) | getrimmt, mono, Fades, auf -6 dBTP normalisiert |
| `hug` | RPG Audio (cloth3) | Kenney | CC0-1.0 | [Quelle](https://kenney.nl/assets/rpg-audio) | mono, Fades, auf -6 dBTP normalisiert |
| `chime` | Glass Tap | Unicornaphobist | CC0-1.0 | [Quelle](https://freesound.org/s/262958/) | mono, Fades, auf -6 dBTP normalisiert |
| `reveal` | PB Bar Chimes (long) | petebuchwald | CC0-1.0 | [Quelle](https://freesound.org/s/271355/) | Ausschnitt (1.3 s, aufsteigender Sweep), mono, Fades, auf -6 dBTP normalisiert |
| `unlock` | RPG Audio (metalLatch) | Kenney | CC0-1.0 | [Quelle](https://kenney.nl/assets/rpg-audio) | mono, Fades, auf -6 dBTP normalisiert |
| `drop` | Slow Single Water Drop Splash | qubodup | CC0-1.0 | [Quelle](https://freesound.org/s/792932/) | tiefer gepitcht (x0.85), mono, Fades, auf -6 dBTP normalisiert |
| `dice` | Casino Audio (die-throw-2) | Kenney | CC0-1.0 | [Quelle](https://kenney.nl/assets/casino-audio) | mono, Fades, auf -6 dBTP normalisiert |
| `chip` | Casino Audio (chip-lay-2) | Kenney | CC0-1.0 | [Quelle](https://kenney.nl/assets/casino-audio) | mono, Fades, auf -6 dBTP normalisiert |
| `splash` | WaterSplash | Ryanz-Official | CC0-1.0 | [Quelle](https://freesound.org/s/646568/) | getrimmt (0.9 s), mono, Fades, auf -6 dBTP normalisiert |
| `hit` | Impact Sounds (impactSoft_heavy_001) | Kenney | CC0-1.0 | [Quelle](https://kenney.nl/assets/impact-sounds) | mono, Fades, auf -6 dBTP normalisiert |

Verarbeitung: `ios/scripts/prepare_sounds.sh` (ffmpeg) — Stille-Trim,
5/10-ms-Fades, mono 44.1 kHz, Peak-Normalisierung auf −6 dBTP, Container
CAF/PCM16 (bewusst kein AAC: Encoder-Priming würde die Transienten
anschneiden). Feintuning läuft über das `gain`-Feld im Manifest zur
Laufzeit, nie über Re-Encoding. Die Original-Downloads liegen gitignored in
`tools/sound_sources/`.

### Original-Synthese

Reine Synthese bleiben: `sent`, `heartbeat`, `sparkle`, `vibe`, `pairing`, `click`, `success`, `fanfareSmall`, `fanfareMedium`, `fanfareEpic`, `lose` — plus die 7 `notif_*.wav`
(UNNotificationSound, eigenes Inventar) und alle Hybrid-Synth-Schichten.

### Synthese-Techniken

| Technik | Zweck |
| --- | --- |
| Stereo-Voices mit Cent-Verstimmung (±3–8 Cent L/R) | Wärme & Breite statt sterilem Mono-Sinus |
| Echte Attack/Decay-Hüllkurven | keine Klicks, weiche Einsätze |
| Inharmonische Bell-Partials (1 / 2.0 / 2.99 / 4.16 / 5.43) | glaubwürdige Glas-Glocken statt Piepser |
| Pitch-Glides | Herzschlag-Thumps, Bubble-Pops |
| Animiert gefiltertes Rauschen (auf-/zugehender Low-Pass, dekorrelierte Kanäle) | Luft, Papier, Umarmungs-Whoosh |
| Feedback-Delay über den ganzen Buffer | verträumte Echo-Fahnen |
| Soft-Knee-Sättigung (tanh) statt Hard-Clip | analoger Charakter, keine Verzerrungsartefakte |

Standard-Lautstärken sind bewusst sanft (Momente 0.65, Chat 0.5, Spiele 0.6,
Interface 0.35) und pro Kategorie in den Einstellungen regelbar. Die Engine
läuft als `.ambient` mit `.mixWithOthers`; läuft eigene Musik, verschwinden
Interface-Cues ganz und alles andere duckt ~10 dB.

## App-Icon

Prozedural gerendert im CI durch `ios/scripts/GenerateIcon.swift`
(CoreGraphics) — keine Bild-Assets von Drittanbietern.

## Schriften & Symbole

- System-Font (SF Pro Rounded) und SF Symbols — Bestandteil von iOS,
  Nutzung gemäß Apple-Systemrichtlinien.

## Inhalte

Alle Fragen, Quiz-Items, Date-Ideen, Wordle-Wortlisten und
Wahrheit-oder-Pflicht-Karten in `ios/SoooDreamy/Content/` sind eigens für
dieses Projekt geschrieben.
