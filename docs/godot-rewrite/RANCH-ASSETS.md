# RANCH-ASSETS.md — Asset-Inventar + Lizenzen (Gooby Ranch DLC)

Stand: 2026-07-26 (Agent ASSET-SCOUT). Diese Datei ist die **Rechtsgrundlage** fuer
alle Assets unter `GOOBY-GODOT/assets/ranch/`. Jede Zeile: Datei → Quelle → Lizenz →
Zweck → Format. Alle Assets sind per `godot --headless --path GOOBY-GODOT --import`
verifiziert (0 Fehler, Godot 4.4.1).

Lizenz-Kurzlegende:
- **CC0** = Public Domain, keine Namensnennung noetig.
- **CC-BY** = Namensnennung PFLICHT (Credits-Liste am Ende dieser Datei).
- **Eigenbau** = im Repo per Blender-Pipeline generiert (`tools/blender/ranch/`),
  Rechte beim Projekt.

Konventionen: 1 Unit = 1 m, Y-up, Modelle schauen nach **-Z** (Godot-Forward).
Loopende Animationen tragen in den GLBs das `-loop`-Suffix nicht im Namen —
sie wurden als NLA-Tracks mit `-loop`-Suffix exportiert, Godot importiert sie
als `idle`, `schritt`, ... mit gesetztem Loop-Flag.

---

## 1. Selbst gebaute 3D-Modelle (Blender-Pipeline, Eigenbau)

Erzeugt mit `GOOBY-GODOT/tools/blender/ranch/build_ranch.sh` (Blender 4.0.2,
Skripte: `ranch_stil.py`, `build_pferd.py`, `build_tier.py`, `build_props.py`).
Stilreferenz: Gooby-Modell (`tools/blender/gooby_build/`) — rund, pastellig,
grosse Augen, dicke Wangen. Material: eine 16x16-Palette-Textur pro Modell
(die `*_palette.png` neben dem GLB ist im GLB eingebettet, PNG nur Referenz).

| Datei | Zweck | Rig/Anims | Format |
|---|---|---|---|
| `pferd/pferd.glb` | Reit-/Ranch-Pferd, Gooby-Stil | 13 Knochen; idle, schritt, trab, galopp, sprung, fressen, kopfschuetteln, schlafen, blinzeln (+ Augen-zu-Shapekey) | GLB, ~1.42 m Ruecken (kompatibel `RUECKEN_Y` in `ranch_pferd.gd`), 312 KiB |
| `pferd/fohlen.glb` | Fohlen (kleinere Proportionen, groesserer Kopf) | wie Pferd (13 Knochen, 9 Anims) | GLB, ~0.95 m Schulter, 307 KiB |
| `tiere/reh_gooby.glb` | Nachbarschaftstier Reh (mit Punkten) | 10 Knochen; idle, schritt | GLB, ~0.9 m, 141 KiB |
| `tiere/fuchs_gooby.glb` | Nachbarschaftstier Fuchs | 10 Knochen; idle, schritt | GLB, ~0.7 m, 143 KiB |
| `tiere/ente_gooby.glb` | Nachbarschaftstier Ente | 6 Knochen; idle, schritt | GLB, ~0.45 m, 118 KiB |
| `tiere/katze_gooby.glb` | Nachbarschaftstier Katze | 10 Knochen; idle, schritt | GLB, ~0.65 m, 140 KiB |
| `props/sattel.glb` | Sattel (aufsetzbar auf Pferd-Ruecken) | statisch | GLB, ~0.5 m |
| `props/buerste.glb` | Striegelbuerste (Pflege-Minigame) | statisch | GLB, ~0.2 m |
| `props/trog.glb` | Futter-/Wassertrog | statisch | GLB, ~1.0 m |
| `props/heuballen.glb` | Heuballen | statisch | GLB, ~0.9 m |
| `hindernisse/hindernis_a.glb` | Turnier-Hindernis: Stangen-Sprung | statisch | GLB, ~2 m breit |
| `hindernisse/hindernis_b.glb` | Turnier-Hindernis: Mauer | statisch | GLB, ~2 m breit |
| `hindernisse/hindernis_c.glb` | Turnier-Hindernis: Doppel-Oxer | statisch | GLB, ~2 m breit |

Lizenz: Eigenbau (Projekt), keine externen Inhalte.

## 2. Beschaffte 3D-Modelle

### Quaternius — Farm Animals Pack (CC0)

Quelle: https://quaternius.com (Farm Animals Pack). Lizenznote:
`tiere/License-quaternius-farm-animals.txt`. Konvertiert aus den Original-
`.blend`-Dateien (Skalierung auf Zielhoehe, Zentrierung, 180-Grad-Drehung auf
-Z-Forward) via `/tmp`-Konverterskript; Animationen (Idle, Walk, WalkSlow, Run,
Jump, Death) bleiben erhalten. Alle geriggt, je 1 Mesh.

| Datei | Zweck | Format |
|---|---|---|
| `tiere/kuh.glb` | Bauernhoftier Kuh | GLB, ~1.4 m, 28 Knochen |
| `tiere/schwein.glb` | Bauernhoftier Schwein | GLB, ~0.8 m, 24 Knochen |
| `tiere/schaf.glb` | Bauernhoftier Schaf | GLB, ~0.9 m, 24 Knochen |
| `tiere/lama.glb` | Bauernhoftier Lama | GLB, ~1.6 m, 24 Knochen |
| `tiere/mops.glb` | Hund (Mops) | GLB, ~0.5 m, 24 Knochen |
| `tiere/zebra.glb` | Zebra (Bonus/Turnier-Gast) | GLB, ~1.4 m, 28 Knochen |
| `tiere/pferd_lowpoly.glb` | Low-Poly-Pferd (Fallback/NPC-Herde) | GLB, ~1.5 m, 28 Knochen |

### Quaternius — Farm Buildings Pack (CC0)

Quelle: https://quaternius.com (Farm Buildings). Lizenznote:
`gebaeude/License-quaternius-farm-buildings.txt`. Gleiche Konvertierung.

| Datei | Zweck |
|---|---|
| `gebaeude/scheune.glb`, `scheune_gross.glb`, `scheune_klein.glb`, `scheune_offen.glb` | Staelle/Scheunen (Stall-Renovierung Kapitel 1) |
| `gebaeude/huehnerstall.glb` | Huehnerstall |
| `gebaeude/silo.glb`, `silo_haus.glb` | Silos |
| `gebaeude/windmuehle.glb`, `windmuehle_turm.glb` | Windmuehlen |
| `gebaeude/wasserturm.glb`, `brunnen.glb` | Wasserturm, Brunnen |
| `gebaeude/zaun_holz_a.glb`, `zaun_holz_b.glb` | Koppel-Zaeune |

Format: GLB, Massstab 1 Unit = 1 m (Scheune ~6 m hoch), statisch.

### Kenney — Nature Kit (CC0)

Quelle: https://kenney.nl/assets/nature-kit (bereits im Repo unter
`GOOBY/public/assets/kenney/`, fuer die Ranch nach GLB konvertiert/kopiert).
Lizenznote: `natur/License-kenney-nature-kit.txt`.

| Datei | Zweck |
|---|---|
| `natur/tree_default.glb`, `tree_detailed.glb`, `tree_fat.glb`, `tree_oak.glb` | Baeume |
| `natur/rock_largeA.glb`, `rock_smallA.glb`, `stump_round.glb`, `log.glb` | Felsen, Baumstuempfe |
| `natur/grass_large.glb`, `plant_bush.glb`, `plant_bushLarge.glb` | Graeser, Buesche |
| `natur/flower_purpleA.glb`, `flower_redA.glb`, `flower_yellowA.glb` | Blumen |
| `natur/crop_carrot.glb`, `crop_pumpkin.glb`, `crops_cornStageC.glb`, `crops_cornStageD.glb` | Feldfruechte |
| `natur/fence_simple.glb`, `fence_gate.glb` | Deko-Zaun + Gatter |
| `natur/bridge_wood.glb` | Holzbruecke (Bach) |

Format: GLB, statisch, ~0.5-4 m.

## 3. Texturen (Eigenbau, prozedural)

Erzeugt mit `GOOBY-GODOT/tools/blender/ranch/gen_texturen.py` (Python/PIL),
alle **256x256 PNG, nahtlos kachelbar**, Pastell-Palette passend zu
`scripts/ranch/ranch_bau.gd`. Lizenz: Eigenbau.

| Datei | Zweck | Groesse |
|---|---|---|
| `texturen/wiese.png` | Weide/Wiese | 42 KiB |
| `texturen/feldweg.png` | Feldweg/Erde | 46 KiB |
| `texturen/sand.png` | Reitplatz/Sand | 33 KiB |
| `texturen/holz.png` | Stallwaende/Bretter | 46 KiB |
| `texturen/stroh.png` | Stroh/Einstreu | 57 KiB |
| `texturen/wasser.png` | Teich/Bach | 18 KiB |

## 4. Artwork (KI-generiert fuer dieses Projekt)

Generiert im Stil des App-Icons (`AppIcon-512@2x.png`: runder brauner Hase,
Pastell, weiche Verlaeufe). Als WebP (Qualitaet 88) fuer Mobile optimiert,
alle 1536x1024. Lizenz: projektintern generiert (privates Projekt).

| Datei | Zweck | Groesse |
|---|---|---|
| `artwork/key_artwork_gooby_ranch.webp` | Key-Artwork: Gooby + Pferd vor der Ranch im Abendlicht | 150 KiB |
| `artwork/logo_gooby_ranch.webp` | Logo/Schriftzug "GOOBY RANCH" | 207 KiB |
| `artwork/ladebildschirm_stall_buersten.webp` | Ladebildschirm: Striegeln im Stall | 193 KiB |
| `artwork/ladebildschirm_galopp_wiese.webp` | Ladebildschirm: Galopp ueber die Wiese | 122 KiB |
| `artwork/ladebildschirm_nacht_teich.webp` | Ladebildschirm: Nacht am Teich | 177 KiB |
| `artwork/ladebildschirm_turnier_sprung.webp` | Ladebildschirm: Turniersprung | 162 KiB |
| `artwork/kapitel1_stall_flott_machen.webp` | Titelkarte Kapitel 1 "Stall flott machen" | 166 KiB |
| `artwork/kapitel2_erstes_pferd.webp` | Titelkarte Kapitel 2 "Das erste Pferd" | 135 KiB |
| `artwork/kapitel3_dorf_kennenlernen.webp` | Titelkarte Kapitel 3 "Das Dorf kennenlernen" | 143 KiB |
| `artwork/kapitel4_turnier.webp` | Titelkarte Kapitel 4 "Das grosse Turnier" | 133 KiB |
| `artwork/kapitel5_ranchfest.webp` | Titelkarte Kapitel 5 "Das Ranchfest" | 193 KiB |

## 5. Audio (beschafft, zu OGG konvertiert + normalisiert)

Vollstaendige Quell-/Lizenztabelle: **`assets/ranch/audio/License-audio.md`**
(pro Datei: Quelle, Autor, Lizenz, Ausschnitt). Kurzueberblick:

- **Hufschlaege** (`sfx/huf_*.ogg`): Einzelschritte Gras/Sand/Holz/Stein
  (OGA "Horse gallop on different surfaces", CC0 + CC-BY 4.0) sowie
  Galopp-Loop (Alan McKinney, CC-BY 3.0) und Trab-Loop (CC0).
- **Pferdelaute** (`sfx/pferd_*.ogg`): 2x Wiehern, 2x Schnauben (freesound, CC0).
- **Pflege-Foley** (`sfx/sattel_aufsteigen.ogg`, `buerste_striegeln.ogg`,
  `heu_rascheln.ogg`): freesound, CC0.
- **Ambience-Loops** (`sfx/ambience_*.ogg`): Wind (CC0), Regen (CC0), Gewitter
  (CC-BY 3.0), Voegel (CC0), Bach (CC-BY 3.0), Grillen (CC0).
- **Turnier** (`sfx/turnier_fanfare*.ogg`, `menge_*.ogg`): Fanfaren (CC0),
  Menge Jubel/Gemurmel (Gregor Quendel, CC-BY 4.0).
- **Musik** (`musik/`): `musik_ranch_tag` (Apple Cider, CC0),
  `musik_reiten` (Lasso Lady Loop, CC0), `musik_turnier` (Jumping Jamboree,
  CC-BY 4.0), `musik_nacht` (Yoiyami Ambient Piano, CC0),
  `musik_menue` (Komiku "Down the river", CC0).

Format: OGG Vorbis 44,1 kHz, SFX q4 (Einzelsounds mono, Ambience stereo),
Musik q5 stereo. Gesamt ~18 MB.

## 6. Pflicht-Credits (CC-BY, muessen in die Spiel-Credits)

- "Horse gallop on different surfaces" — congusbongus, CC-BY 4.0
  (enthaelt Samples von moodyfingers, Twigy233, CC-BY 4.0)
- Galopp-Loop — Alan McKinney, CC-BY 3.0
- "Rain and Thunder Loop" — DoKashiteru, CC-BY 3.0
- "Stream Sounds" — kurt (OpenGameArt), CC-BY 3.0
- "Free Crowd Cheering Sounds" — Gregor Quendel, CC-BY 4.0
- "Jumping Jamboree" — tcarisland, CC-BY 4.0

Alles andere ist CC0 oder Eigenbau. Optionale Nennungen (CC0, erbeten):
Quaternius, Kenney, Zane Little Music, Komiku, Yoiyami, isaiah658,
Luke.RUSTLTD, Wolfgang_, fvcalderan, EZduzziteh sowie die freesound-Autoren
Lydmakeren, Salsero_classic, bruno.auzet, black_trillium, craigsmith, ldezem,
soundandmelodies, rasunter255.

## 7. Reproduzierbarkeit

- 3D-Eigenbau neu erzeugen: `GOOBY-GODOT/tools/blender/ranch/build_ranch.sh`
  (braucht `blender` im PATH; baut Pferd, Fohlen, 4 Tiere, Props, Hindernisse).
- Texturen neu erzeugen: `python3 GOOBY-GODOT/tools/blender/ranch/gen_texturen.py`.
- Import-Check: `godot --headless --path GOOBY-GODOT --import` (0 Fehler erwartet).
