# E4 — Performance-Budgets (GOOBY-Godot-Mega-Eval)

Datum: 2026-07-25 · Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`) · Godot 4.4.1.stable · Messung:
`xvfb-run godot --rendering-method gl_compatibility --rendering-driver opengl3` (llvmpipe),
Wegwerf-Treiber `/tmp/gooby-godot/eval/e4_probe.gd` + `e4_leak_probe.gd` (Vorlage:
`scripts/dev/perf_probe.gd`; Repo unverändert). Orakel = `RenderingServer.get_rendering_info`
(identisch zu `scripts/dev/perf_overlay.gd::snapshot()`), Draw/Tris/Nodes = Max über 40 Frames.
**FPS-Spalte ist llvmpipe-Software-Rasterizer und NICHT iPhone-aussagekräftig** — bewertet wird
ausschließlich gegen die renderer-unabhängigen Zähler (Draw Calls, Tris, VRAM, Lights, Materials).

Budgets: `docs/godot-rewrite/A-engine.md` §7 — Raum ≤150 Draw Calls / ≤150k Tris, Minigame ≤250 / ≤250k,
Schatten-Lights 0 innen / 1 Directional außen, Omni ≤4 (Raum) / ≤6 (Minigame), Unique Materials ≤25 / ≤30,
GPUParticles ≤4 Systeme (Raum) / ≤8, Texturspeicher ≤350 MB, Ziel 60 FPS ab iPhone 11.

## 1) Mess-Tabelle (Lauf 1, vollständig, 1280×720 bzw. Minigame-Formate)

| Szene | Draw Calls | Tris | Nodes | VRAM MB | Omni | Dir | Schatten-L | Partikel-Sys | Unique Mats | Budget-Check |
|---|---|---|---|---|---|---|---|---|---|---|
| Raum bathroom (Tag) | 43 | 10 858 | 139 | 29.2 | 1 | 1 | 0 | 2 | 44 | Draw/Tris OK · Mats ÜBER |
| Raum bathroom (Nacht) | 43 | 10 858 | 139 | 29.2 | 1 | 1 | 0 | 2 | 44 | identisch zu Tag ✓ |
| Raum bedroom (Tag) | 33 | 19 934 | 155 | 37.5 | 2 | 1 | 0 | 4 | 35 | OK · Partikel am Limit · Mats ÜBER |
| Raum bedroom (Nacht) | 33 | 19 934 | 155 | 37.5 | 2 | 1 | 0 | 4 | 35 | identisch zu Tag ✓ |
| Raum garden (Tag) | 30 | 10 020 | 157 | 29.2 | 1 | 1 | 0 | 2 | 31 | OK · Mats ÜBER |
| Raum garden (Nacht) | 30 | 10 020 | 157 | 29.2 | 1 | 1 | 0 | 2 | 31 | identisch zu Tag ✓ |
| Raum kitchen (Tag) | 63 | 12 000 | 163 | 29.3 | 1 | 1 | 0 | 2 | 53 | OK · Mats ÜBER (2,1×) |
| Raum kitchen (Nacht) | 63 | 12 000 | 163 | 29.3 | 1 | 1 | 0 | 2 | 53 | identisch zu Tag ✓ |
| Raum living (Tag) | 55 | 19 492 | 181 | 29.4 | 2 | 1 | 0 | **6** | 59 | Partikel ÜBER (6>4) · Mats ÜBER |
| Raum living (Nacht) | 55 | 19 492 | 181 | 29.4 | 2 | 1 | 0 | **6** | 59 | wie Tag |
| Stadt Tag (Chase-Cam) | 37 | 11 172 | 482 | 46.1 | 0 | 1 | 1 | 0 | 43 | OK (1 Dir-Schatten außen erlaubt) |
| Stadt Tag (Übersicht) | **238** | 42 755 | 483 | 46.1 | 0 | 1 | 1 | 0 | 43 | Draw ÜBER 150 |
| Stadt Nacht (Chase-Cam) | 47 | 11 972 | 519 | 46.2 | 1 | 1 | 1 | 0 | 79 | OK · Mats ÜBER (Laternen/Autolichter) |
| Stadt Nacht (Übersicht) | **280** | 47 606 | 520 | 46.2 | 1 | 1 | 1 | 0 | 79 | Draw ÜBER 150 (1,9×) |
| GvZ Gefecht L8 (7-Zombie-Welle) | **866** | 24 577 | 69 | 22.8 | 0 | 0 | 0 | 0 | 0 | **Draw 3,5× ÜBER 250** |
| GvZ Boss L15 (Knurps aktiv) | **853** | 25 127 | 69 | 22.8 | 0 | 0 | 0 | 0 | 0 | **Draw 3,4× ÜBER 250** |
| teaParty (mitten im Guss) | 14 | 614 | 49 | 12.8 | 0 | 0 | 0 | 0 | 0 | OK (weit unter Budget) |
| carrotCatch (Items in der Luft) | 13 | 448 | 49 | 12.8 | 0 | 0 | 0 | 0 | 0 | OK |
| Besuch (2 Goobys, living) | **166** | **124 526** | 148 | 31.0 | 0 | 1 | **1 (innen!)** | 6 | 32 | **Draw ÜBER 150 · Schatten-Verbot innen verletzt** |
| Battleship-Tisch (Mid-Game) | 244 | 28 756 | 332 | 31.8 | 0 | 1 | 0 | 0 | **232** | Draw knapp unter 250 · **Mats 7,7× ÜBER 30** |
| Onboarding (Welcome) | 8 | 940 | 89 | 30.0 | 0 | 0 | 0 | 0 | 0 | OK |
| Onboarding (Editor, 3D-Preview) | 55 | 3 433 | 89 | 30.2 | 0 | 0 | 0 | 0 | 0 | OK |
| Album (Garten-Seite) | 69 | 9 510 | 134 | 33.7 | 0 | 0 | 0 | 0 | 0 | OK |

Anmerkungen: Raum-/Stadtmessungen ohne HUD (HUD addiert erfahrungsgemäß ~10–20 Calls — Puffer vorhanden).
Tag/Nacht sind in Räumen zählergleich (HomeLicht ändert nur Farben/Energien — sauber). Stadt-Nacht
+10 Calls / +36 Mats durch Laternen-Glow + Autolichter. Werte decken sich mit der W4-P5-Baseline in
`scripts/dev/README.md` (±2 Calls) → Messaufbau reproduzierbar.

## 2) Textur-/Asset-Größen

- `find assets -type f -size +1M` → **leer** (keine einzelne Ressource ≥1 MB). Größte Dateien:
  `assets/character/gooby.glb` 0.41 MB (4 406 Tris, 1 Mesh — vorbildlich), `pothos_plant…bin` 0.25 MB,
  `assets/city/autos/delivery.glb` 0.23 MB, `assets/covers/gvz.png` 0.18 MB.
- Verzeichnis-Summen: `assets/` gesamt **21 MB** (stickers 12 MB ÷ 37 Einträge, city 4.4 MB,
  furniture 1.8 MB, audio 0.6 MB); Skripte 2.3 MB, Szenen 64 KB; `.godot/imported` 17 MB.
- **PCK-Schätzung: ~20–25 MB** (Projekt ohne `.godot` = 25 MB; PCK packt importierte Ressourcen ≈
  `imported`-Größe + Skripte/Szenen). Für Mobile hervorragend klein.
- VRAM-Zähler max. **46 MB** (Stadt) — selbst unkomprimiert (llvmpipe/GL zählt ohne ASTC) weit unter
  dem 350-MB-Budget; mit `import_etc2_astc=true` (in `project.godot` aktiv) auf Gerät noch weniger. ✓

## 3) Speicher-Signale

Raum-Wechsel ×10 (living↔kitchen = 20 Mounts, headless, `e4_leak_probe.gd`):

| Zyklus | Nodes | Objects | Resources | Orphan-Nodes |
|---|---|---|---|---|
| Baseline | 45 | 1 662 | 158 | 0 |
| 1 | 45 | 1 672 | 158 | 1 |
| 2–10 (konstant) | 45 | 1 674 | 158 | 1 |
| Ende (nach gs.free) | 45 | 1 669 | 158 | 0 |

→ **Kein Leak**: Nodes/Resources absolut flach; +12 Objects sind der persistente GameState+Slice,
der 1 Orphan-Node ist der bewusst tree-freie GameState und verschwindet nach `free()`. ✓

**ObjectDB-Leak-Warnung analysiert:** erscheint bei **jedem** Exit, auch bei nacktem
`godot --headless --quit` (also kein Treiber-Artefakt). `--verbose` zeigt konstant ~6 Objekte:
1 suspendierter `GDScriptFunctionState` + `AudioStreamPlaybackOggVorbis`/`OggPacketSequence(Playback)`
von `res://assets/audio/sfx/close_001.ogg` (= SFX `ui_close`). Quelle: Boot-Pfad
`LoadingVeil.cover()` → `AudioDirector.try_play(self, "ui_close")` (`scripts/core/loading_veil.gd:96`)
— eine beim Quit noch schwebende Coroutine hält die Playback-Kette. Konstant, wächst nicht
(Leak-Tabelle flach) → exit-only, kosmetisch. Risiko: verrauscht CI-Logs und maskiert künftige echte Leaks.

## 4) Boot-Zeit headless (Proxy, 4-Core-VM)

| Lauf | Zeit |
|---|---|
| 1 | 2 232 ms |
| 2 | 2 334 ms |
| 3 | 2 376 ms |

Ø ≈ **2,3 s** (Autoloads + main.tscn + erster Frame). Kein §7-Budget definiert; als Proxy unauffällig.
Auf iPhone kommen Pipeline-Precompile/ASTC-Dekodierung dazu — mit Veil-Design (§A 1.4) abgedeckt.

## 5) Findings (P0–P3)

- **P1 — GvZ reißt das Draw-Call-Budget 3,5-fach** (866 Gefecht L8 / 853 Boss L15 vs. ≤250):
  `gvz_game.gd`/`gvz_art.gd` zeichnen jede Figur immediate-mode aus dutzenden `draw_circle`/`draw_rect`
  (68 draw_*-Stellen allein in gvz_game.gd); jede Primitive = eigener Canvas-Befehl, Batching bricht.
  Auf A13+ vermutlich noch spielbar (2D, nur 25k Tris), aber Budget-Riss und CPU-seitig teuerster Screen.
- **P1 — Besuchs-Szene verletzt zwei Budgets gleichzeitig**: 166 Draw Calls (>150) und **124 526 Tris —
  6,4× desselben Raums über RoomBase (19 492)**. Ursache: `visit_room_view.gd:152` setzt
  `sun.shadow_enabled = true` **innen** (§7: „0 innen, Blob/gebaked“) → Directional-PSSM rendert die
  Raumgeometrie in 4 Schatten-Splits erneut. Nicht die Goobys (gooby.glb = 4 406 Tris).
- **P2 — Unique-Material-Budget (≤25 Raum / ≤30 Minigame) flächig gerissen**: Räume 31–59
  (kitchen 53, living 59), Stadt-Nacht 79, **Battleship 232** — `board_display.gd::_flat()` erzeugt pro
  Kachel/Marker ein frisches `StandardMaterial3D` (≈200 Brett-Kacheln). Draw Calls bleiben (noch) ok,
  aber Shader-/Material-Switches skalieren auf Mobile schlecht; Battleship steht mit 244 Calls bereits
  direkt an der 250er-Grenze.
- **P2 — Stadt-Übersicht 238–280 Draw Calls** (>150; Chase-Cam mit 37–47 im Budget): 482–520 Nodes,
  Laternen (`_baue_laternen`), Deko/Natur (`_baue_deko`/`_baue_natur`) und Verkehr sind einzelne
  MeshInstances. Solange keine Übersichts-/Map-Kamera shipped, latent — Budget-relevant, sobald
  Reise-Cutscene/Map-Zoom die ganze Stadt framet.
- **P2 — living: 6 GPUParticles3D-Systeme** (>4; bedroom exakt am Limit 4). Besuchs-Szene erbt die 6.
- **P3 — ObjectDB-Exit-Warnung** (s. §3): konstant, kein Laufzeit-Leak, aber CI-Log-Hygiene.
- **P0: keins gefunden** — kein wachsendes Leak, kein Budget-Riss, der ein iPhone 11 unter 60 FPS
  drücken dürfte, solange GvZ/Besuch gefixt werden.

## 6) Optimierungs-Empfehlungen (konkret)

1. **GvZ → Sprite-Atlas statt Vektor-Immediate-Mode**: GvzArt-Figuren sind deterministisch → einmalig
   pro Typ/Variante in ein `ImageTexture`-Atlas rendern (SubViewport beim Level-Start), im `_draw()` nur
   noch `draw_texture_rect_region` aus EINEM Atlas → batcht auf <50 Calls. Alternativ `MultiMeshInstance2D`
   für Zombies/Projektile. Erwartung: 866 → <100.
2. **Besuchs-Szene**: `shadow_enabled = false` + Blob-Shadows wie RoomBase (`components/gfx`-Muster);
   erwartet Tris 124k → ~25k und Draw ≤150. Partikel-Erbe aus living auf ≤4 deckeln.
3. **Material-Cache**: zentrale `_flat_material(color)`-Map (Color→Material, wie `_tinte` es für GLBs
   andeutet) für `board_display.gd`, `visit_room_view.gd`, Raum-Builder → Battleship 232 → <10 Mats;
   Battleship-Kacheln zusätzlich als **MultiMesh** (2 Bretter = 2 Draw Calls statt ~200).
4. **MultiMesh-Kandidaten Stadt**: Laternen (identischer Mast + Kopf), Bäume/Büsche (`_baue_natur`),
   Deko-Props — je Typ ein MultiMesh; Verkehrsautos behalten Einzel-Nodes (bewegte Logik), teilen aber
   Materialien. Erwartung Übersicht: 280 → ~120.
5. **Raum-Materialien konsolidieren**: Kenney-Paletten-Prinzip (§7) durchziehen — kitchen/living auf
   gemeinsame Paletten-Materialien prüfen (59 → Richtung 25); billigster Weg: Material-Dedup beim
   Furniture-Import (identische Albedo/Params → gleiche Ressource).
6. **Exit-Leak**: `LoadingVeil.cover()`-SFX-Coroutine beim `NOTIFICATION_WM_CLOSE_REQUEST`/Quit sauber
   abbrechen (oder `try_play` fire-and-forget ohne await-Kette) — hält CI-Logs leak-warnungsfrei.

## Verdict

**Fundament im Budget, zwei klare P1-Budget-Risse.** Räume (30–63 Calls, ≤20k Tris), Stadt-Chase,
teaParty/carrotCatch, Album, Onboarding liegen komfortabel in den §7-Budgets; kein Speicherleck,
Assets winzig (PCK ~25 MB), VRAM ≪350 MB. Fixbedarf: GvZ-Draw-Calls (866/253%-Riss), Besuchs-Szene
(Schatten innen + 124k Tris), Material-Disziplin (Battleship 232). Alle Fixes sind lokal und ohne
Architekturänderung machbar. iPhone-11-60-FPS-Ziel: für Räume/Stadt plausibel, für GvZ/Besuch erst
nach den Fixes belastbar.
