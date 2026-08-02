# ASSET-CREDITS — Lizenz-Nachweis der 3D-/Audio-Fremd-Assets

Alle hier gelisteten Modelle sind **CC0 1.0 Universal (Public Domain)** —
keine Namensnennung nötig, wir nennen die Autor:innen trotzdem gern.
Jeder Asset-Ordner trägt zusätzlich eine `License-*.txt` direkt neben den
Dateien. Konvertierungen (FBX/OBJ/Blend → GLB, Skalierung in Meter, Y-up,
Boden-Origin, Palette-Tints auf `tools/blender/props/props_stil.py`) laufen
über Blender headless — die Modelle bleiben CC0.

## Neu beschafft in W17 (Worker ASSET-SOURCE)

Auftrag aus `UserFeedback.md` §1: „nutze/downloade dir endlich mal mehr
Modelle aber nur wenn der Stil zu unserem Spiel passt!!" — 60 kuratierte
Low-Poly-Modelle, stil-geprüft (Flat-Colors, Gooby-Palette, ACNH-Proportionen).

### Kenney.nl (Autor: Kenney — kenney.nl, CC0)

| Pack | Dateien im Repo |
| --- | --- |
| Fantasy Town Kit 2.0 | `GOOBY-GODOT/assets/city/marktstand/` — `stall.glb`, `stall-red.glb`, `stall-green.glb`, `stall-bench.glb`, `cart.glb`, `lantern.glb` |
| Car Kit 3.1 | `GOOBY-GODOT/assets/city/autos2/` — `ambulance.glb`, `firetruck.glb`, `garbage-truck.glb`, `suv-luxury.glb`, `tractor.glb` |

### KayKit (Autor: Kay Lousberg — kaylousberg.itch.io, CC0)

| Pack | Dateien im Repo |
| --- | --- |
| Restaurant Bits 1.0 | `GOOBY-GODOT/assets/city/innen2/` — `crate_ham`, `crate_lettuce`, `crate_onions`, `crate_potatoes`, `fridge_A_decorated`, `fridge_B`, `kitchencounter_straight_A_decorated`, `shelf_papertowel_decorated` (je `.gltf`+`.bin`, Textur `restaurantbits_texture.png`) |
| City Builder Bits 1.0 | `GOOBY-GODOT/assets/city/strassenmoebel/` — `bush`, `dumpster`, `trash_A`, `trash_B` (je `.gltf`+`.bin`, Textur `citybits_texture.png`) |

### Quaternius (Autor: Quaternius — quaternius.com, CC0)

Konvertiert aus Blend/FBX zu GLB mit Palette-Tints (Gooby-Farben aus
`tools/blender/props/props_stil.py`), Höhen in Metern normalisiert.

| Pack | Dateien im Repo |
| --- | --- |
| Ultimate House Interior | `GOOBY-GODOT/assets/city/innen2/` — `regal_gross.glb`, `regal_hoch.glb`, `regal_offen.glb`, `buecherregal.glb`, `kuehlschrank_hoch.glb`, `muelleimer_gruen.glb`, `pflanze_laden_gross.glb`, `pflanze_laden_klein.glb` |
| Street Pack | `GOOBY-GODOT/assets/city/strassenmoebel/` — `ampel_a.glb`, `ampel_b.glb`, `laterne_einzel.glb`, `laterne_doppel.glb`, `schild_stop.glb`, `schild_parkverbot.glb` |
| Farm Buildings | `GOOBY-GODOT/assets/ranch/farm/` — `windmuehle.glb`, `silo.glb`, `huehnerstall.glb`, `brunnen.glb`, `wasserturm.glb` |

### Tiny Treats (Autorin: Tiny Treats — tinytreats.itch.io, CC0)

| Pack | Dateien im Repo |
| --- | --- |
| Homely House | `GOOBY-GODOT/assets/furniture/tt-haus/` — `bench_A`, `boots`, `cobblestones`, `doormat`, `fence_corner`, `fence_straight_long`, `foliage_A`, `gate_single`, `mailbox`, `package` (je `.gltf`+`.bin`, Textur `tiny_treats_texture_1.png`) |
| Fun Playground | `GOOBY-GODOT/assets/furniture/tt-spielplatz/` — `merry_go_round`, `picnic_table`, `sandbox_round_decorated`, `seesaw_small`, `slide_A`, `spring_horse_A`, `swing_A_large`, `tire_pink` (je `.gltf`+`.bin`, Textur `tiny_treats_texture_1.png`) |

## Bereits vorher im Projekt (frühere Worker, ebenfalls CC0)

Kenney-Kits (Food, Furniture, Nature, City Kit Commercial/Roads/Suburban,
Car Kit, Space, Watercraft, Minigolf, Interface Sounds), KayKit Dungeon-
Sortiment, Quaternius Farm-Animals/Farm-Buildings-Teile und Tiny-Treats-Packs
(House Plants, Pleasant Picnic) — je mit `License-*.txt` im Asset-Ordner
(siehe `GOOBY-GODOT/assets/**/License-*.txt`).

## Ehrliche Notiz zu Sketchfab / Unity Asset Store / blockbenchworkshop

- **Unity Asset Store**: Die Standard-EULA („Asset Store Terms") lizenziert
  Assets für die Nutzung *in Unity-Projekten*; eine Weiterverwendung in
  Godot ist rechtlich mindestens grau, oft untersagt. Deshalb bewusst
  **nicht** verwendet — für jede Kategorie existieren CC0-Pendants
  (Kenney/Quaternius/KayKit/Tiny Treats), die wir stattdessen nutzen.
- **Sketchfab**: Downloads erfordern einen Account (auch bei CC-Modellen);
  Account-Anlage mit Wegwerf-Mail verstößt gegen deren ToS. Viele der
  dortigen Low-Poly-Modelle sind zudem CC-BY (Attribution nötig) statt CC0.
  Bewusst **nicht** verwendet.
- **blockbenchworkshop.com**: Kein etablierter CC0-Katalog mit
  Direkt-Downloads; Stil (Minecraft-Voxel) passt überwiegend nicht zur
  ACNH-Rundung des Spiels. **Nicht** verwendet.
- **poly.pizza**: Cloudflare blockt Headless-Downloads in der CI-Umgebung —
  die dort aggregierten Modelle stammen ohnehin größtenteils von
  Quaternius/Kenney, die wir direkt beziehen.

## Audio

Gesamtbestand + G6-Neuzugänge (Worker AUDIO-FEEL, W17). Detail-Nachweise
liegen wie bei den Modellen direkt neben den Dateien; dieser Abschnitt ist
die Übersicht. **Ausnahme-Hinweis:** vier Ranch-Hufschlag-/Galopp-Dateien
sind CC-BY (Namensnennung Pflicht, s. u.) — alles andere ist CC0.

| Bestand | Quelle/Autor | Lizenz | Nachweis im Repo |
| --- | --- | --- | --- |
| UI-/Impact-Samples (`assets/audio/sfx/*.ogg`, `game/`-Rohmaterial) | Kenney — kenney.nl, Packs „Interface Sounds" 1.0 + „Impact Sounds" 1.1 (account-frei) | CC0 | `GOOBY-GODOT/assets/audio/sfx/LICENSE-kenney-cc0.txt` |
| Weiche UI-Familie (`soft/soft_*.ogg`), Pflege-/Reise-Foley (`foley/`), Minigame-Feel (`game/game_*.ogg`) | selbst erzeugt (numpy-Synthese, FIX-4/EF-2/POLISH-A) | CC0 (eigene Erzeugung) | `tools/audio/ef2_gen_sfx.py` (Rezepte im Skript) |
| Gooby-Babble-Silben (`assets/audio/voice/*.wav`) | selbst erzeugt (Formant-Synthese) | CC0 (eigene Erzeugung) | `tools/audio/gen_syllables.py` |
| **NEU G6:** Emotions-Motive (`soft/emo_*.ogg`, 12 Stück) + Welt-/Stations-Momente (`welt/*.ogg`, 10 Stück: city_hupe, city_vogel, laden_glocke, kasse_piep, foto_shutter, licht_schalter, tuer_auf/_zu/_ruettel/_plopp) | selbst erzeugt (numpy-Synthese im soft-/Foley-Rezept) | CC0 (eigene Erzeugung) | `tools/audio/g6_gen_feel_sfx.py` (druckt Pegel-Einmessung; Wache `tests/unit/test_g6_audio_feel.gd`) |
| Musik (`assets/music/**`, 56 Tracks inkl. Radio/Recap/Stinger) | diverse itch.io-/OGA-Autoren (u. a. Dylann Taylor, Tallbeard) | CC0 | `GOOBY-GODOT/assets/music/LICENSES.md` (Quelle+Verifikation je Pack) |
| Ranch-DLC-Audio (`assets/ranch/audio/**`: Hufe, Pferdelaute, Ambience, Turnier, Musik) | opengameart.org + freesound.org (nur direkt herunterladbare, dokumentierte Quellen) | überwiegend CC0; **CC-BY: huf_holz (moodyfingers), huf_stein (Twigy233), huf_galopp_loop (Alan McKinney) u. Bearbeitungen congusbongus** — Namensnennung muss in die Spiel-Credits | `GOOBY-GODOT/assets/ranch/audio/License-audio.md` |

Beschaffungs-Regel für Audio (wie bei den Modellen): kenney.nl ist
account-frei und erste Wahl; freesound nur, wenn die konkrete Datei CC0 ist
und der Download ohne Account funktioniert — sonst prozedural selbst
erzeugen (die tools/audio-Skripte sind dafür da und dokumentieren die
Pegel-Kontrakte gleich mit).
