# Trailer Capture Plan — Project Eclipse (Hero-Stills + Glitch-Bursts)

Kameramann-Drehbuch für den headless llvmpipe-Client (DISPLAY=:1, 1920×1200, ~1–5 fps).
Alle `/dev`- und `/eclipse`-Syntaxen unten sind **gegen den Code bzw. den Live-Server verifiziert**
(Quellen: `src/main/java/dev/projecteclipse/eclipse/devtools/dev/*.java`, `cutscene/dev/FxDevCommands.java`,
RCON-Statusabfragen vom 2026-07-27).

---

## 0. Setup-Fakten (verifiziert)

| Fakt | Wert | Quelle |
|---|---|---|
| Altar (Sanctum-Insel) | **(0, 88, 0)**, Dais-Boden y=84, Insel im Disc-Zentrum | `eclipse_world_state.dat` → `sanctumAltarPos=88` = BlockPos(0,88,0); RCON `execute if block 0 88 0 eclipse:altar` → *Test passed* |
| Altar-Level aktuell | 0 (Aura aus) — für Shots hochsetzen | RCON `eclipse status` |
| Mansion-Glitch-Dome | Zentrum **(219, 86, -219)**, Shell r=67, Boden y=78, Device (207, 89, -223), Status ACTIVE, hits 8/8 | RCON `dev dome status` |
| Gravity Rift (WOAH-02) | Anker **(-239, 62, 167)**, gebaut, Sentinel steht, **0/218 Displays live** → vor Shot `orbitals` feuern | RCON `dev woah gravity status` |
| Chrono Stasis (WOAH-03) | Zentrum **(-24, 76, 240)**, placed, FROZEN, 0/454 Displays (reconciled=false) | RCON `dev woah chrono status` |
| Nether-Opening-Krater | **(85, 72, 85) im OVERWORLD** (Lip-Y 72); Breach noch NICHT gegraben | RCON `dev nether status`; `BreachBuilder.breachCenter()` |
| Fog-Storm-Sites (aktiv) | **(0, ~75, -250)** r=28 und **(-173, ~75, -173)** r=28 — "Storms: 2 active" | `run/world/eclipse/fogstorms.json`; RCON `dev status` |
| Limbo-Geisterschiff | Dimension `eclipse:limbo`, Schiffszentrum (0, ~64, 0), Rumpf x±19/z±4, Ankunftsplattform (0, Wasserlinie+4, 12) | `limbo/GhostShipBuilder.java` (`NOMINAL_CENTER`, `platformArrivalPos`) |
| End-Disc | nicht gebaut → `endarrival` OHNE `fxonly` würde sie PERMANENT bauen | RCON `dev status` ("End disc no") |
| Spielername | **`Tester`** (einziger Op, Level 4, `run/ops.json`; usercache kennt auch `Dev`/`Sonic0810`) | `run/ops.json`, `run/usercache.json` |
| RCON | `python3 tools/rcon/rcon.py "<cmd ohne führenden Slash>"` (Port 25575, `run/server.properties`) | getestet |
| Client-Fenster | `run/options.txt`: `fullscreen:false`, `overrideWidth/Height:0`, `guiScale:2` → Fenstergröße erzwingen (s. §0.2) | `run/options.txt` |
| Server-Adresse im Client | `run/servers.dat` enthält bereits 127.0.0.1 | geprüft |

### 0.1 Client-Neustart (Rezept)

```bash
tmux new-session -d -s trailer-client -c /home/ubuntu/project-eclipse/ProjectEclipse
tmux send-keys -t trailer-client "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=4.6 ./gradlew runClient --console=plain" C-m
```

- Der Server hält den `run/world`-Lock — der Client tritt als **Multiplayer-Client über 127.0.0.1** bei
  (Multiplayer → vorhandener Servereintrag). Kein zweiter `runServer`!
- Falls der Client als anderer Name joint (Default-Dev-Username): per RCON `op <Name>` nachziehen,
  sonst funktionieren Chat-`/dev`-Befehle nicht (RCON-Befehle gehen immer).

### 0.2 Auflösung 1920×1080

`options.txt` hat kein Override gesetzt. Zwei Wege:

1. **Vor** Client-Start in `run/options.txt` setzen: `overrideWidth:1920`, `overrideHeight:1080` (Client darf dabei nicht laufen).
2. Oder nach dem Start: `DISPLAY=:1 xdotool windowsize $(DISPLAY=:1 xdotool search --name "Minecraft NeoForge" | head -1) 1920 1080`
   — danach mit `/tmp/mc.sh geom` prüfen (WW/WH müssen 1920/1080 melden).

### 0.3 Capture-Werkzeuge

- `/tmp/mc.sh click|key|cmd|shot|geom` — Einzelaktionen + gecroppter ffmpeg-Screenshot.
- `/tmp/fire.sh "<chat-text>" <prefix> <N> <gap>` — Chat-Befehl absetzen + N Burst-Frames.
- **HUD verstecken: `/tmp/mc.sh key F1 0.5`** (F1-Toggle; vor JEDEM Hero-Still, danach wieder F1 für Chat-Eingaben — Chat geht auch bei verstecktem HUD mit `t`).
- **Pixel-perfekte Alternative:** `/tmp/mc.sh key F2 1` → natives Minecraft-Screenshot in `run/screenshots/` (volle Renderauflösung, kein x11grab-Crop-Risiko). Für Hero-Stills bevorzugen.
- Burst ohne Chat-Befehl (wenn der Trigger via RCON kommt):
  `for i in $(seq 1 12); do /tmp/mc.sh shot /tmp/burst_$i.png; sleep 0.5; done`
- Rechtsklick (Zauberstab-Cast): `DISPLAY=:1 xdotool windowactivate --sync <WID>; xdotool click 3`
  (mc.sh kennt nur Linksklick).

---

## 1. Befehls-Spickzettel (verifizierte Syntax)

**Konsolen-Tauglichkeit:** RCON = Konsole (perm 4). Befehle, die die Position/Blickrichtung des Aufrufers
brauchen (mit ⚠️CHAT markiert), müssen aus dem **Client-Chat** kommen (`/tmp/mc.sh cmd "..."`), Spieler muss Op sein.

### Events / Sequenzen
| Befehl | Wirkung |
|---|---|
| `/dev event start endarrival fxonly` | ~50 s End-Ankunft NUR als FX (wiederholbar). Timeline: OMEN 0–8 s → CHARGE 8–20 s (Ringe → **violette Säule** → **Himmels-Maul reißt auf**) → SPILL 20–40 s (Inseln + **fallende Trümmer**, Blitz-Ribbons) → FINALE 40–50 s (Implosion + Schockwellenring) |
| `/dev event start endarrival` | dito, aber baut die End-Disc PERMANENT (Weltverbrauch!) |
| `/dev event stop endarrival` | Abbruch, Debris wird verworfen |
| `/dev event start herold [here]` | Herald-Ankunfts-Cutscene über dem Sanctum-Altar; Beats: Säule t=15, Silhouette t=55, Materialize t=130, Spawn t=150 Ticks (≈0.75/2.75/6.5/7.5 s) |
| `/eclipse boss herald kill` · `/eclipse boss ferryman kill` | Boss danach entsorgen |
| `/dev start_ferryman` | ganzer Fährmann-Arc im 15-s-Dev-Cut (Portal-Formation → Limbo) |
| `/dev ferryman skip_to arena` | ALLE sofort aufs Limbo-Deck + Arena-Fight (staged Finale — Weltverbrauch) |
| `/dev credits start` | ECHTE Credits — **beendet auf Dedicated am Ende Clients + SERVER** (DESTRUCTIVE, nicht für Stills!) |
| `/dev replay play credits BLACKHOLE` | **FX-only** Schwarzes-Loch-Phase, via RCON für alle Spieler, wiederholbar. Weitere Phasen: SHATTER, HELM, WHITEOUT, BEACH, LIGHTNING, ECLIPSE, BURST, OUTRO |
| `/dev replay play intro ECLIPSE_ON` | FX-only Eclipse-Himmel-Phase (weitere: FLIGHT, APPROACH, LIGHTNING, BURST, REVEAL, SUNRISE) |
| `/dev replay play expansion SKYWARD` | FX-only Expansions-Phasen (SKYWARD, FLYOVER, GROWTH, STRUCTURES, END) |
| `/dev end_event` | löst die Credits-Haltephase / holt Spieler zurück |
| `/dev nether replay_fx` | ~47 s Nether-Öffnungs-Show NUR FX (kein Graben), wiederholbar; Krater-Punkt (85,72,85) Overworld |
| `/dev nether open` | dito + gräbt den Krater PERMANENT |
| `/dev nether stop` / `/dev nether status` | Abbruch / Phase+Ticks |

### Sturm / Fog
| Befehl | Wirkung |
|---|---|
| (passiv) | 2 aktive Fog-Storm-Sites: (0,-250) und (-173,-173), r=28 — permanente Sturmwände |
| `/eclipsefx storm add <radius 4-128> <height 8-256> wall\|vortex\|sphere` ⚠️CHAT | Dev-Sturmwand/-Wirbel an der Spielerposition |
| `/eclipsefx storm remove` ⚠️CHAT | entfernt sie wieder |
| `/eclipsefx storm bolt <intensity 0-1>` ⚠️CHAT | Blitz wohin man schaut (Burst-Frame!) |

### Glitch-Zonen
| Befehl | Wirkung |
|---|---|
| `/dev glitch add <effect> <radius 1-512> <sek 1-86400> [x y z] [fadeTicks 0-1200] [colour]` | persistente Zone; von RCON **immer x y z angeben** |
| `/dev glitch test <effect> [sek 1-300]` ⚠️CHAT | Vollstärke-Selbsttest nur auf dem Aufrufer (Default 10 s) |
| `/dev glitch color <id> <colour>` · `remove <id>` · `clear` · `list` · `altar [status]` | Zonen umfärben/entfernen/auflisten; `altar` = violetter Void-Puls am Altar |
| Effekte | `outline, datamosh, scanlines, invert, void, dome` — auch als Suffixpaar `void_purple`, `datamosh_red`, … |
| Farben | `purple, green, red, cyan, orange, white, pink` |

### Mansion-Dome (WOAH-01)
| Befehl | Wirkung |
|---|---|
| `/dev dome status` | Geometrie/Hits/Zonen-IDs |
| `/dev dome arm [here [radius]]` | am Mansion-Landmark bzw. Test-Dome am Aufrufer |
| `/dev dome hits <n>` · `destroy` · `shatter` · `reset` | Hits setzen / volle Zerstörungssequenz / NUR BlockDisplay-Scherben-Show (FX) / zurück auf ACTIVE |

### WOAH: Gravity Rift & Chrono Stasis
| Befehl | Wirkung |
|---|---|
| `/dev woah gravity build` · `pulse` · `invert` ⚠️CHAT · `orbitals` · `tp` ⚠️CHAT · `status` | bauen / Puls+Launch-Beat sofort / 15-s-Inversion / ~218 Orbital-Displays neu spawnen / auf den Kraterrand tp / Status |
| `/dev woah chrono spawn` · `tick [count <n>]` · `discharge` · `reset` · `status` | Site bauen / Zeit-Jolt / Entladung sofort / deterministischer Rebuild / Status |

### Zauberstab / XP / Skin
| Befehl | Wirkung |
|---|---|
| `/give Tester eclipse:eclipse_wand` | Stab geben (GeckoLib-Item) |
| `/dev wand set <player> path (none\|riss\|glut\|stern)` | Pfad setzen (Riss=Raum violett, Glut=Feuer, Stern=Schutz) |
| `/dev wand set <player> level <1-5>` · `xp <n>` · `charge <n>` | Level/XP/Ladung |
| `/dev wand xp <player> <amount>` · `/dev wand level <player> <n>` | F-041-Kurzformen |
| Casting | Rechtsklick = Cast des gewählten Spells; Sneak-Rechtsklick/Sneak-Scroll = Spell wechseln. Fotogen: `glut.glutstoss` (BEAM), `riss.umbra_lanze` (BEAM) |
| `/dev player xp give <player> <amount>` · `/dev xp add <amount> [player]` | Skill-XP |
| `/dev skin <player> <url>` · `/dev skin <player> reset` · `/dev adminskin <player>` | Skin-Override (direkter PNG-Link 64×64) / zurück / lila Admin-Skin |

### Kamera / Utility
| Befehl | Wirkung |
|---|---|
| `/tp Tester <x> <y> <z> <yaw> <pitch>` | Vanilla-Kamera-Placement. Yaw: 0=Süd(+Z), 90=West(−X), ±180=Nord(−Z), −90=Ost(+X); Pitch: −90=oben, +90=unten |
| `/gamemode spectator Tester` / `creative` | Spectator = beste "Kamera" (kein Hand-Modell); für Wand-Shot zurück zu creative! |
| `/eclipsefx viewdist <2-32>` ⚠️CHAT / `reset` | kinematische Renderdistanz pushen |
| `/dev viewdist pin Tester <chunks>` | persistenter Renderdistanz-Pin (via RCON) |
| `/eclipse freeze Tester on [s]\|off` · `/eclipse invuln Tester on\|off` | Spieler einfrieren/unverwundbar |
| `/eclipsefx rift <x y z> <width 0.5-64>` ⚠️CHAT · `rift close` | Himmels-Riss-FX an Position öffnen/schließen |
| `/eclipsefx cutscene play <id>` | Kamerafahrt (holt ALLE Spieler — Vorsicht); IDs via `/eclipse cutscene list`: `end_arrival`, `intro_v3_flight`, `expansion_flyover`, `credits_helm`, … |
| `/eclipse tp_limbo [player]` | auf die Geisterschiff-Plattform in `eclipse:limbo` |
| `/execute in eclipse:limbo run tp Tester …` | freies Kamera-Placement in Fremddimensionen |
| `/dev backrooms tp (yellow\|pool\|warehouse\|flooded\|hollow)` ⚠️CHAT · `flicker` ⚠️CHAT | in Backrooms-Layer hüpfen / Blackout-Puls auf sich selbst |
| `/dev backroomsscare <player>` · `/dev ghostscreen <player>` · `/dev jumpscare <version> <player>` (`list` → 30 Versionen, z. B. `static_face`, `red_maw`) | Scare-FX gezielt |
| `/effect give Tester minecraft:night_vision 3600 0 true` | Nachtsicht ohne Partikel (Limbo/Backrooms) |

### Zeit / Wetter / Welt-Look
| Befehl | Wirkung |
|---|---|
| `/time set 6000` | Mittag — **mit Altar-Level ≥1 steht die verfinsterte Sonne im Zenit** (`EclipseSkyState`: Eclipse verlässt den Tageszyklus, Zenit = dayTime 6000) |
| `/time set 13000` / `23000` | Nacht / Morgengrauen |
| `/weather clear` | Regen aus (llvmpipe-fps schonen) |
| `/eclipse altar set <level ≥0>` | Altar-Stufe (1–5): Stufe 1+ Motes+Bodennebelring, 2+ Runen-Orbit+Lichtsäule, 3+ Veil-Aura-Grade, 4+ gegenrotierende Lichtbänder. **Persistiert → nach dem Dreh auf 0 zurück!** |
| `/eclipse day set <1-14>` | Tages-Eskalation des Himmels (lila Grading, Koronen, Tag-Sterne; Tag 14 = Maximum). **Persistiert → zurücksetzen!** |
| `/dev stage skipdark` | Dark-Phase des Stage-Wechsels überspringen (falls hängend) |
| `/dev stage backup now trailer_pre` | **Live-Terrain-Backup vor dem Dreh** (Empfehlung!); zurück mit `/dev stage revert` |

---

## 2. Shotlist (14 Shots + 3 Bursts)

Konvention pro Shot: RCON-Prep → Kamera-`/tp` → Wartezeit → `F1` (`/tmp/mc.sh key F1 0.5`) → `F2`-Still (`/tmp/mc.sh key F2 1`, Datei in `run/screenshots/`).
Spieler standardmäßig im **Spectator** (außer S07 Wand-Cast).

### S01 `altar_hero_aura` — Altar-Monument + Stufen-Aura, nah von schräg unten *(Must-have a)*
- Prep (RCON): `eclipse altar set 3` → `time set 6000` → `weather clear`
- Kamera: `tp Tester 7 85 7 135 -19` (Südost-Ecke des Dais, Blick nach NW hoch zum Altar)
- Warten: 15 s (Photon-Loops `altar_aura_motes/glyphs/pillar` brauchen Anlauf und Spielernähe)
- F1 → F2
- **Erwartungsbild:** Altarblock mit aufsteigenden Motes, Runen-Orbit und weicher Lichtsäule, Luft flimmert leicht — Aura klar über dem Monument sichtbar.
- Schiefgehen: Veil-Grade (Stufe 3+) fehlt evtl. auf llvmpipe → Partikelreihen tragen den Shot trotzdem; notfalls `eclipse altar set 4` für Lichtbänder.

### S02 `altar_island_totale` — Insel-Totale mit Eclipse-Himmel *(Must-have b)*
- Prep (RCON): `eclipse day set 12` → `eclipse altar set 5` → `time set 6000`
- Kamera: `tp Tester 0 96 -110 0 -6` (90 Blöcke nördlich, Blick Süd, Horizont tief für viel Himmel)
- Warten: 10 s · F1 → F2
- **Erwartungsbild:** schwebende Altar-Insel mittig als Silhouette, direkt darüber die schwarz verfinsterte Sonne mit Korona, lila Tages-Grading + Tag-Sterne.
- Schiefgehen: Eclipse-Scheibe sitzt nicht überm Motiv → `time set` feinjustieren (5200–6800) oder Fallback `dev replay play intro ECLIPSE_ON`.

### S03 `herald_silhouette` — Boss-Silhouette materialisiert überm Altar *(Bonus)*
- Kamera VORHER: `tp Tester 14 87 0 90 -10` (Ost vom Altar, Blick West)
- Trigger (RCON): `dev event start herold` → sofort Burst-Loop: 10 Frames à 0.7 s (`mc.sh shot`)
- **Erwartungsbild:** dunkle Vignette, violette Säule, halbtransparente Herald-Silhouette über dem Altar (t≈3–7 s).
- Cleanup: `eclipse boss herald kill`
- Schiefgehen: Boss spawnt und aggro't → sofort killen; Sequenz ist wiederholbar.

### S04 `wand_cast` — Zauberstab-Casting mit Glut-Strahl *(Must-have g)*
- Prep (RCON): `gamemode creative Tester` → `give Tester eclipse:eclipse_wand` → `dev wand set Tester path glut` → `dev wand set Tester level 5` → `dev wand set Tester charge 100`
- Position: `tp Tester -14 85 0 -90 -15` (Westrand des Dais, Blick Ost über den Altar in den Himmel)
- Ansicht: `/tmp/mc.sh key F5 2` zweimal → Front-Third-Person (Spieler + Stab zur Kamera) — oder einmal für Back-View mit Strahl von hinten
- F1, dann Cast + Burst: `DISPLAY=:1 xdotool click 3` gefolgt von 8 Frames à 0.4 s
- **Erwartungsbild:** GeckoLib-Stab Level 5 sichtbar in der Hand, Feuer-Lanze/Partikel-Trail Richtung Himmel.
- Schiefgehen: falscher Spell gewählt → Sneak-Rechtsklick zyklisch; Spectator castet nicht → creative!

### S05 `sky_rift` — Himmels-Riss (+ optional fallende Trümmer) *(Must-have k)*
- Trigger (Client-Chat): `/tmp/mc.sh cmd "/eclipsefx rift 0 135 30 14" 6`
- Kamera: `tp Tester 0 90 -25 0 -35` (Blick nach Süden steil hoch zum Riss)
- F1 → F2. Für Trümmer-Variante: Riss offen lassen und S06 starten — SPILL-Fenster (20–40 s) liefert fallende Debris ins selbe Bild.
- Cleanup: `/tmp/mc.sh cmd "/eclipsefx rift close" 3`
- **Erwartungsbild:** violett glühender Riss-Tear vor dem Eclipse-Himmel, Randglühen deutlich; in der Trümmer-Variante fallende Blöcke davor.
- Schiefgehen: Rift-Renderer ist Veil-lastig → wenn unsichtbar, Ersatz = S06-Maw als "Riss".

### S06 + **BURST-1** `endarrival_pillar_maw` — Himmels-Schlund + violette Säule *(Must-have d)*
- Kamera VORHER: `tp Tester 65 100 65 135 -25` (Spectator, 90 Blöcke SO, Blick NW hoch)
- Trigger (RCON): `dev event start endarrival fxonly`
- Burst: ab t≈8 s **12 Frames à 1 s** (`for i in $(seq 1 12); do /tmp/mc.sh shot /tmp/end_$i.png; sleep 1; done`) — CHARGE-Fenster 8–20 s = Ringe→Säule→Maul; danach optional zweiter Burst 20–40 s für Trümmer.
- **Erwartungsbild:** violette Energiesäule vom Altar hoch in ein aufgerissenes End-Maul; im SPILL-Fenster Inselschutt + Blitz-Ribbons.
- Schiefgehen: **NIE ohne `fxonly`** (baut sonst die End-Disc permanent); Show verpasst → `dev event stop endarrival` und neu starten, beliebig wiederholbar.

### S07 `storm_wall` — Fog-Sturmwand von außen *(Must-have c)*
- Prep (RCON): `time set 6000` (Sturm dunkel gegen hellen Himmel)
- Kamera: `tp Tester 0 92 -165 180 -3` (85 Blöcke südlich der Site (0,-250), Blick Nord)
- Warten: 10 s (Storm-FX rampen client-seitig) · F1 → F2
- Bonus-Frame: `/tmp/mc.sh cmd "/eclipsefx storm bolt 1.0" 1` + sofort shot (Blitz in die Wand)
- **Erwartungsbild:** rotierende dunkle Nebel-/Sturmwand (r=28) klar vom Himmel abgesetzt, ggf. Blitz.
- Schiefgehen: Wand rendert erst näher → auf 60 Blöcke ran (`tp Tester 0 90 -190 180 -3`); Alternative Site (-173,-173); Notnagel: `/eclipsefx storm add 24 64 wall` an eigener Position.

### S08 `dome_totale` — Mansion Glitch Dome Totale *(Must-have f)*
- Prep (RCON): `time set 13500` (Nacht — Glitch-Glühen), `dev dome status` (muss ACTIVE sein; sonst `dev dome reset`)
- Kamera: `tp Tester 219 112 -332 0 10` (110 Blöcke südlich des Zentrums (219,86,-219), leicht erhöht)
- F1 → F2
- **Erwartungsbild:** schimmernde Glitch-Halbkugel (r=67) über dem Mansion-Hügel, Kuppelrand gegen Nachthimmel, innen violettes Flackern.
- Schiefgehen: Dome-Shell ist Post-FX (`glitch_dome`-Pipeline) → falls auf llvmpipe unsichtbar: Burst-2 (Shatter) als Ersatzmotiv, oder Interior-Shot in der Zone (Kamera auf (219,90,-219)).

### **BURST-2** `dome_shatter` — Stop-Motion-Scherbenregen *(Glitch-Moment)*
- Kamera: wie S08, näher: `tp Tester 219 100 -300 0 6`
- Trigger (RCON): `dev dome shatter` (NUR BlockDisplay-Scherben-Show, FX-only) → **10 Frames à 0.6 s**
- Cleanup: `dev dome reset`
- **Erwartungsbild:** Kuppel zerbirst in eckige Display-Scherben — BlockDisplays rendern auch ohne Shader zuverlässig.

### S09 + **BURST-3** `glitch_datamosh` — Vollbild-Glitch fürs Stop-Motion *(Glitch-Moment)*
- Position: im Dome-Bereich (Interieur, z. B. `tp Tester 219 88 -240 0 0`, Spectator raus: `gamemode creative`)
- Trigger + Burst (Client-Chat): `/tmp/fire.sh "/dev glitch test datamosh_red 15" /tmp/glitch 10 0.6`
- **Erwartungsbild:** Frames mit Datamosh-Schlieren/Rot-Akzent über dem Mansion-Interieur — jede Datei anders = Stop-Motion-Material.
- Schiefgehen: `datamosh` kaputt in Software-GL → `outline_cyan` oder `scanlines_purple` testen (`/dev glitch test outline_cyan 15`); zur Not `invert`.

### S10 `gravity_rift` — Gravitationsbruch mit Orbital-Trümmern *(Must-have l — fotogener als Chrono)*
- Prep (RCON): `dev woah gravity orbitals` (218 Displays respawnen — aktuell 0 live!) → `time set 6000`
- Kamera: `tp Tester -174 95 112 50 20` (NO vom Anker (-239,62,167), Blick SW in den Krater)
- Warten: 10 s · F1 → F2
- Puls-Variante (Burst): RCON `dev woah gravity pulse` → 12 Frames à 0.8 s (Launch-Beat + Ring)
- **Erwartungsbild:** Krater mit schwebenden Inseln und ~200 kreisenden Trümmer-Displays, beim Puls ein Energie-Ring.
- Schiefgehen: Displays budgetieren erst bei Spielernähe ein → erst tp'en, dann `orbitals`; Chrono-Ersatz: `dev woah chrono reset` + Kamera `tp Tester 6 82 210 170 5` auf (-24,76,240).

### S11 `nether_crater_smoke` — Nether-Öffnung mit Rauchwolke *(Must-have i)*
- Kamera VORHER: `tp Tester 150 92 150 135 0` (Spectator; Krater-Punkt (85,72,85) Overworld)
- Trigger (RCON): `dev nether replay_fx` (~47 s, FX-only, wiederholbar)
- Burst: ab t≈15 s 12 Frames à 1.2 s; bestes Einzelbild als Hero-Still
- **Erwartungsbild:** Asche-/Rauchsäule + glühende Debris über dem Kraterpunkt, Beben-Staub am Boden.
- Schiefgehen: ohne echten Krater fehlt das Loch im Boden → falls das Loch gewollt ist, `dev nether open` erst im Finale-Cluster (permanent!).

### S12 `limbo_ghost_ship` — Fährmann-Schiff im Limbo *(Must-have h)*
- Prep (RCON): `eclipse tp_limbo Tester` → `gamemode spectator Tester` → `effect give Tester minecraft:night_vision 3600 0 true`
- Kamera: `execute in eclipse:limbo run tp Tester 25 76 22 131 13` (Blick aufs Schiffszentrum (0,~64,0), Laternen + Masten im Bild)
- F1 → F2
- **Erwartungsbild:** Geisterschiff (38 Blöcke lang) mit Laternen im nebligen Seelen-Meer, Deck + Ruder erkennbar.
- Schiefgehen: Wasserlinie variiert → Kamera-Y ±4 anpassen; zu dunkel trotz NV → `time set` wirkt im Limbo nicht zwingend, dann Gamma via optionaler options.txt-Anpassung vorm Start.

### S13 `backrooms_corridor` — Backrooms-Flur *(Must-have j)*
- Prep (RCON): `gamemode creative Tester` (tp braucht Spielerstatus), dann Client-Chat: `/tmp/mc.sh cmd "/dev backrooms tp yellow" 8`
- Kamera: nach dem TP stehen bleiben, per `/tmp/mc.sh key Left/Right` in 90°-Schritten drehen bis Ein-Punkt-Perspektive den längsten Flur zeigt (Yaw exakt 0/90/180/-90 halten!)
- F1 → F2. Optional Poolrooms-Zweitmotiv: `/dev backrooms tp pool`
- Flicker-Burst (Alternative zu Burst-3): `/tmp/fire.sh "/dev backrooms flicker" /tmp/br 10 0.5` — Blackout-Frames dazwischen
- **Erwartungsbild:** endloser gelber Flur mit Neon-Deckenlicht in sauberer Fluchtpunkt-Perspektive; Burst enthält 1–3 schwarze Frames.
- Schiefgehen: TP verweigert außerhalb Event? (Verifikations-Leaf sollte immer gehen) → sonst `dev backrooms start 10` davor, `dev backrooms stop now` danach.

### S14 `credits_blackhole` — Schwarzes-Loch-Finale *(Must-have e — FX-only!)*
- Kamera: zurück in den Overworld-Himmel, z. B. `execute in minecraft:overworld run tp Tester 0 120 -60 0 -30`
- Trigger (RCON): `dev replay play credits BLACKHOLE` (FX-only Replay — NICHT `/dev credits start`!)
- Burst: 10 Frames à 1 s, bestes Frame als Still
- **Erwartungsbild:** schwarzes Loch mit Akkretions-Glühen dominiert den Himmel, Bildränder gravitativ verzerrt/dunkel.
- Schiefgehen: Phase rendert auf llvmpipe schwarz/leer → Ersatzphasen `SHATTER` oder `BURST` testen; letzter Fallback: S06-Implosions-FINALE (t 40–50 s) als "kosmischer Kollaps".

---

## 3. Reihenfolge-Optimierung (Cluster)

**Grundregel:** Ein Client-Login, einmal Fenster einrichten, dann Welt-Positionen abfahren; alles Persistente ans Ende.
**Vorab einmalig:** `dev stage backup now trailer_pre` (RCON) — Sicherheitsnetz für Terrain.

| # | Cluster | Shots | geteilter State |
|---|---|---|---|
| 0 | Setup | Client-Start, Fenster 1920×1080, `op`, `weather clear`, Backup | — |
| 1 | **Altar-Insel (0,88,0)** | S01 → S02 → S03 → S04 → S05 → S06/Burst-1 | `altar set`/`day set` einmal setzen, alle sechs Shots teilen Position + Eclipse-Himmel; endarrival-fxonly zuletzt im Cluster (50 s Show färbt den Himmel um) |
| 2 | **Fog-Site (0,-250)** | S07 | nur 250 Blöcke von Cluster 1, gleicher Tag-Himmel |
| 3 | **Mansion (219,-219)** | S08 → Burst-2 → S09/Burst-3 | einmal `time set 13500` (Nacht) für alle drei; `dome reset` am Ende |
| 4 | **West-Seite** | S10 (Gravity -239,167; optional Chrono -24,240 auf dem Weg) | wieder Tag: `time set 6000`; `orbitals` direkt vor dem Shot |
| 5 | **Nether-Krater (85,85)** | S11 | FX-only, wiederholbar |
| 6 | **Dimensions-Hops** | S12 (Limbo) → S13 (Backrooms) | je ein TP-Rundtrip; NV-Effekt teilen |
| 7 | **Finale / Weltverbraucher** | S14 (Blackhole-Replay) → OPTIONAL echte `dev nether open` / `dev event start endarrival` (ohne fxonly) falls echte Terrain-Narben gewünscht | Replays sind harmlos, aber Screen-Takeover → ans Ende; echte Events sind irreversibel → allerletzt |
| 8 | **Cleanup** | `eclipse altar set 0` · `eclipse day set 1` · `dev glitch clear` · `dev dome reset` · `/eclipsefx rift close` · Bosse killen · ggf. `dev stage revert` | Welt zurück in den Vorher-Zustand |

**Welt-Verbraucher (nur bewusst + zuletzt):** `dev event start endarrival` (ohne fxonly, baut End-Disc), `dev nether open` (gräbt Krater), `dev ferryman skip_to arena` / `dev start_ferryman` (staged Finale), `dev credits start` (**hält den Dedicated-Server an!** — für den Trailer IMMER das Replay nehmen).

---

## 4. Notfall-Alternativen (llvmpipe-Ausfälle)

Software-GL-Risikoklassen und Ersatzmotive:

| Riskantes Motiv (Veil-Post-FX) | Symptom | Ersatz |
|---|---|---|
| Glitch-Shader (`datamosh`, `dome`, `invert`) | schwarzes/unverändertes Bild | einfachere Pipelines `outline_cyan`/`scanlines_purple` testen; sonst **Burst-2 Dome-Shatter** (BlockDisplays, shaderfrei) |
| Credits-BLACKHOLE | leerer Himmel | Replay-Phasen `SHATTER`/`BURST`; sonst S06-FINALE-Implosion (Partikel+Displays) |
| Rift-Tear (`/eclipsefx rift`) | unsichtbar | End-Maw aus S06 als Himmels-Riss framen (CHARGE 12–20 s) |
| Veil-Aura-Grade Stufe 3+ | kein Schimmer | Photon-Partikelreihen (Motes/Glyphen/Säule/Bänder) tragen S01 allein — `altar set 4` |
| Dome-Shell außen | keine Kuppel | Interior-Glitch-Zone (Zone existiert: r=75 @ 219,86,-219) von innen + `glitch color <id> purple` |
| Post-FX generell prüfen | — | Client-Chat: `/eclipsefx post list` (live Pipelines), Einzeltest `/eclipsefx post "<id>" on` |

**Shaderfreie "sichere Bank"-Motive** (reine Geometrie/Partikel/Displays — funktionieren immer):
Altar-Monument + Partikel-Aura (S01), Insel-Totale (S02), Geisterschiff (S12), Backrooms-Flure (S13),
Gravity-Orbitals (S10), Dome-Shatter-Scherben (Burst-2), Nether-Debris/Rauch (S11), Sturmwand-Partikel (S07).

---

## 5. Quick-Checkliste pro Hero-Still

1. RCON-Prep (Zeit/Wetter/Event-State) → 2. `/tp` mit Yaw/Pitch aus der Shotlist → 3. Spectator? →
4. 10–15 s warten (FX-Rampen + llvmpipe-Frame) → 5. `/tmp/mc.sh key F1 0.5` → 6. `/tmp/mc.sh key F2 1` →
7. PNG aus `run/screenshots/` einsammeln → 8. F1 wieder an für den nächsten Chat-Befehl.
