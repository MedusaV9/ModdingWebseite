# UV map — Eclipse Wand (`assets/eclipse/textures/item/wand/eclipse_wand[_<path>].png` + `_glowmask.png`)

**Texture size:** 64×64 — **vier** Varianten-Paare (`none`/`riss`/`glut`/`stern`), alle vom
selben Painter-Lauf, alle mit gleicher Canvas (GeckoLibs `AutoGlowingTexture` erzwingt
Albedo = Glowmask-Canvas). Modell: `assets/eclipse/geo/item/eclipse_wand.geo.json`
(GeckoLib-ITEM, 47 Bones / 33 Cubes — EIN Geo für alle Pfade; `client/wand/
EclipseWandRenderer` blendet fremde `p_<pfad>_s<stufe>`-Gruppen aus und tauscht die
Textur per synced `wand_path`-Komponente). Wie überall ist das Geo die UV-Quelle der
Wahrheit — der Painter (`scripts/geckolib_gen/paint_lib.py`) parst es selbst; hier ist
nur das Layout eingefroren:

| Bone | Cube | Box W×H×D | UV | Notizen |
|---|---|---|---|---|
| handle | Griff | 2×6×2 | box-UV (0,0) | Wurzelholz in Pfad-Tönung |
| handle_wrap | Wicklung | 2×1×2 (inflate 0.25) | box-UV (0,8) | dunkler; Y-Sway im idle, Gulp-Bulge im stall |
| shaft | Schaft unten | 2×3×2 | box-UV (8,0) | Runen-Naht (Glow) auf Nord/Süd-Mittellinie |
| shaft_mid | Schaft Mitte | 2×2×2 (inflate −0.15) | box-UV (8,6) | heller (saftgebleicht), Runen-Naht |
| shaft_top | Schaft oben | 2×2×2 (inflate −0.3) | box-UV (8,11) | hellstes Segment, Runen-Naht |
| knot | Astknoten | 3×2×3 | box-UV (16,0) | 1px-Rim-Light in Halo-Farbe; „Schluck"-Bulge im stall |
| tip | Spitze | 1×2×1 | box-UV (28,0) | flame-Material (Kern→Halo) |
| glow_riss_a | Scherbenkrone Haupt | 2×3×2 | box-UV (0,16) | 45° gedreht; atmet im idle (neu) |
| glow_riss_b/c | Seitensplitter | je 1×2×1 | (8,16) / (12,16) | ±12° Z; Splay im use_riss |
| glow_riss_d/e | Hochsplitter | je 1×2×1 | (16,16) / (20,16) | ±12° X am s3-Orbit |
| riss_ring | Splitterring | 5×0×5 | box-UV (24,16) | plate-Albedo + emissiver Noise-Rim (up) |
| glow_riss_f | Frontsplitter | 1×2×1 | (44,16) | Glitch-Jitter im use_riss |
| glow_glut_core | Glutkern | 2×2×2 | box-UV (0,24) | weißheißes flame-Material |
| glut_fin_a | Flammenfinne XY | 6×4×0 | box-UV (8,24) | Ebene; `set_glow` 0.85 |
| glut_fin_b | Flammenfinne ZY | 0×4×6 | box-UV (20,24) | Ebene, gekreuzt |
| glow_glut_flame_a | Flammenkranz | 4×3×4 | box-UV (32,24) | 45° gedreht, Molang-Konterrotation |
| glow_glut_flame_b | Flammenzunge | 2×2×2 | box-UV (48,24) | Y-Bob im idle |
| glow_glut_flame_c | Funke | 1×1×1 | box-UV (56,24) | Molang-Dauerrotation |
| glow_stern_star | Sternkern | 2×2×2 | box-UV (0,36) | [45,0,45] gedreht; Twinkle im idle (neu) |
| stern_disc | Konstellationsscheibe | 6×0×6 | box-UV (8,36) | plate-Albedo + Konstellations-Pinpoints (up, Glow) |
| glow_stern_p1..p4 | Orbit-Sterne | je 1×1×1 | (32,36) / (36,36) / (40,36) / (44,36) | staffeln im use_stern nach oben |
| glow_cere_ring_a | Zeremonie-Ring innen | 6×0×6 | box-UV (0,44) | **NEU (F-098 MD1)**; Annulus-Material, Mitte transparent |
| glow_cere_ring_b | Zeremonie-Ring außen | 8×0×8 | box-UV (24,44) | NEU; gegenläufig, um [−10,0,18] gekippt |
| glow_cere_core | Zeremonie-Kern | 2×2×2 (inflate 0.45) | box-UV (0,52) | NEU; umhüllt die Spitze beim Klimax |
| glow_cere_frag_a..d | Orbit-Fragmente | je 1×1×1 | (8,52) / (12,52) / (16,52) / (20,52) | NEU; Radien 3.5–4 px auf 4 Höhen |

**Kipp/Spin-Trennung (MD3-§6.1-Gesetz):** die statischen Ring-Kipps liegen auf
`cere_ring_a`/`cere_ring_b`, die animierten Y-Drehungen auf den `glow_cere_ring_*`-
Kindern — nie beides auf einem Bone (Präzession). `cere_anchor` (Kind von `tip`) trägt
keine Cubes und wird vom `idle` permanent auf Scale 0 gepinnt: die Zeremonie-Gruppe ist
im Ruhezustand UNSICHTBAR und existiert nur während `levelup`/`awaken` (Action-Controller
überstimmt den Base-Controller pro Kanal).

**Art-Brief (IDEA-19 „der Stab wächst mit dir"):** ein knorriger Aststab, dessen Holz
sich mit dem gewählten Pfad verfärbt — `none` neutrales Braun `#6B4E37` mit violetter
Runen-Naht, `riss` Void-Violett `#4A3B5E` mit glitch-hellen Splittern `#D9B8FF`, `glut`
glutrissiges Dunkelbraun `#4A322A` mit Emberkern `#FFE9A8`/`#FF7A2E`, `stern`
Mitternachtsblau `#33405E` mit Sternenlicht `#EAF9FF`/`#4FB5D0`. Jede Variante bemalt
ALLE Bones (fremde Ornamente versteckt der Renderer, nie unbemalt). Die
Zeremonie-Elemente mischen die Pfad-Palette Richtung Weiß (Ringe: Rim = Halo+25 % Weiß,
Band = Kern+30 % Weiß; Kern 55 % Weiß) — die Zeremonie trägt die Pfadfarbe, liest aber
als „Aufstieg".

**Emissiv (Glowmask):** alle `glow_*`-Bones (auto), die Runen-Naht der drei
Schaft-Segmente (Noise-gegatet, 45 %-Schwelle), der Noise-Rim des `riss_ring` (up),
die Konstellations-Pinpoints der `stern_disc` (up), `glut_fin_*` mit `set_glow` 0.85 —
und neu die kompletten Zeremonie-Ringe/-Fragmente/-Kern (voll emissiv; im Ruhezustand
via Scale 0 unsichtbar, daher kein Idle-Glow-Budget-Kostenpunkt).

**Generator (deterministisch, Re-Runs byte-identisch):**

```
python3 scripts/geckolib_gen/items/eclipse_wand.py
```

schreibt alle 8 Wand-PNGs + `wizard_catalyst.png`. Texturen NIE von Hand malen
(AGENTS.md-Gesetz); AI-Art ersetzt später an identischen Pfaden/Größen.
