# MB2 — Wizard Orin Polish (F-098 Welle M-B)

**Status:** FERTIG — validate_geo 2/2 PASS (0 Errors/0 Warnings), `./gradlew compileJava`
grün, Painter deterministisch (2× Lauf, md5 byte-identisch), Loop-/Handback-Audit sauber
(§5.4). WizardFxRows-Spec + Cue-Snippet für den Integrator in §7.
**Datei-Besitz (Zensus §5, Zeile MB2):** `entity/wizard/*` (inkl. `wizard_catalyst`-Zeile),
`client/entity/wizard/*`, Assets `wizard_orin*`, `scripts/geckolib_gen/mobs/wizard_orin.py`,
`docs/uv/wizard_orin.md`, dieser Report. `veilfx/**`, `network/fx/**`, `tools/photon/**`
NICHT angefasst — alles dorthin nur als Spec/Snippet (§7).

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

- **Ist-Zustand Entity:** `WizardOrinEntity extends EclipseGeoMob` (WANDFIX-5): friedlicher
  Quest-NPC, der für den Zauberstab-Kern PROVOZIERT und BEKÄMPFT werden muss. Scripted
  Fight in `tickCombat`: star_call (Zonen-Bolt-Shower), sun_flare (Nahkampf-Nova),
  veil_step (Blink), unveil bei 50 % HP. `die()`→`ANIM_DEATH` (frozen Basis),
  `dropCustomDeathLoot`→`wizard_catalyst`.
- **Timer-Semantik nachgerechnet (Quelle: `tickCombat`):** Telegraph-Zähler dekrementieren
  mit `--timer < 0` → Release feuert auf dem (N+1)-ten Tick nach Trigger.
  star_call: Konstante 25t → **Release-Beat 26t = 1.30 s**; Bolt 1 bei +1t, dann alle 5t,
  10 Bolts → Shower 2.3 s, **Gesamtbeat 3.6 s**. sun_flare: 15t → **Nova 16t = 0.80 s**.
  (Unveiled: 18t → 0.95 s bzw. 14 Bolts → 3.5 s; siehe §9.)
- **Ist-Zustand Anim-Sheet (HEAD):** 7 Anims; `star_call` war nur **1.5 s** lang → die
  komplette 2.3 s-Shower lief in der IDLE-Pose ("Dirigieren" existierte nicht);
  `sun_flare` teilte sich den star_call-Raise (Gather als Sky-Raise mis-verkauft);
  veil_step hatte GAR keine Anim (nur Partikel). Bart = starres 4×8-Brett + Tuft.
- **GeckoLib-Rotations-Verhalten per Bytecode verifiziert** (`javap -c AnimationProcessor`
  aus dem Gradle-Cache): Anim-Rotationen werden **ADDITIV auf die Bone-Basisrotation**
  angewandt (`setRotX(keyValue + initialSnapshot)`); Positions-Keys ebenso additiv,
  Scale multiplikativ-ersetzend. Konsequenz: Keys auf Bones mit Basisrotation
  (`spyglass` zRot −25, `glow_staff_crystal` [45,0,45]) müssen NULL-basierte Deltas sein.
- **Controller-Contract (frozen `EclipseGeoMob`):** `base` (4 Transition-Ticks,
  idle/walk) + `action` (**0 Transition-Ticks** → One-Shot-Start/-Ende sind HARTE
  Schnitte gegen den laufenden Idle-Wert, nicht gegen die Null-Pose). Deshalb sind alle
  One-Shot-Bookends auf die Idle-**Sway-Zentren** gelegt (§3).
- **FX-Seite gelesen (nur als Referenz):** `PhotonFxRows` (PH-CORE-Referenzmuster,
  Dist.CLIENT-MOD-Bus-Registrar), `PhotonFxRegistry.Row`-Signatur, `FxBudget.Channel`,
  `FxPayloads.sendFxEntityEvent(level, id, entity, float a, float b, range)`,
  `FxCues.CUE_WIZARD_CATALYST` (NEWFX-A5, Row in `ProgressionPhotonFxRows` — **orphaned**,
  Sender starb mit `tryQuestTurnIn` in WANDFIX-5). `gen_player_fx.py`-Familie TABU-gemerkt
  und nicht angefasst.
- **FROZEN:** `EclipseGeoMob/Monster/Animations/Renderer`, `validate_geo.py`,
  `paint_lib.py`; Renderer (`WizardOrinRenderer`/`WizardRenderers`) waren bereits korrekt
  und blieben unangetastet.

## 1. Geo: Bart-Kette (18 → 19 Bones)

Einzige Geo-Änderung: das 4×8×1-Bart-Brett ist in eine **3-Segment-Kette** gesplittet,
damit die Molang-Sinus-Ketten (§3) segmentweise phasenversetzt laufen können:

```
head
└─ beard      pivot (0, 21.5, -2.6)   Wurzel-Fall 4×4×1, UV (28,36)  [war 4×8×1]
   └─ beard_mid  pivot (0, 18, -3.1)  Mittel-Fall 4×4×1, UV (28,41)  [NEU]
      └─ beard_tip pivot (0, 14.5, -3.1)  Tuft 2×3×1, UV (38,36)     [re-parented]
```

Pivots liegen jeweils an der Unterkante des Eltern-Cubes → Kettenglieder rotieren wie
ein hängender Strang. UV (28,41)-(38,46) ist kollisionsfrei (validate_geo 0 Warnings;
Nachbarn: staff x<28, spyglass y≥48, scarf x<28). **19 Bones / 19 Cubes** gesamt.
Painter braucht KEINE Änderung — die `beard*`-Materialregel in `wizard_orin.py` matcht
alle drei Segmente (Strähnen-Streaks laufen visuell durch). `docs/uv/wizard_orin.md`
komplett auf den Ist-Stand nachgezogen (die Doku stand noch auf 14/15 von VOR den
robe_hem/book/crystal-Erweiterungen).

## 2. Animation-Sheet (7 → 9 Anims, format 1.8.0)

| Anim | Länge | Loop | Inhalt / Timing-Anker |
|---|---|---|---|
| idle | 6.0 s | true | Atem-Torso, Sternen-Lese-Kopfbahn, Buch-Blätter-Beat (3.15/3.3/3.7/3.85), Staff-Tap 5.0–5.6; NEU: 3-Glied-Bart-Sway (Molang, −30°/−60° Phasen-Lag), Robe/Hem/Scarf-Wind, Staff-Tip-Puls, spyglass-Keys auf Null-Delta korrigiert (§4-Bug 1) |
| walk | 1.0 s | true | Arm/Bein-Gegenschwung; NEU: Bart-Kette mit Gang-Frequenz (360°/s, −35°/−70° Lag), Hem-Flare 6°+Sinus, Scarf-Flattern, Crystal-Spin 360°/Loop (nahtlos) |
| greet | 1.2 s | false | Hut-Tipp-Salut; NEU: Bart/Scarf/Robe-Follow-Through (Kettenspitze peakt 0.18 s nach der Wurzel) |
| trade | 1.4 s | false | Ledger-Lean zum Zuhörer; NEU: Bart-Kette lehnt gestaffelt mit (0.4/0.48/0.55), Crystal-Puls 1.25× auf dem Angebots-Beat |
| star_call | **3.6 s** (war 1.5) | false | **Auf den Server retimed:** 0–0.18 Crouch → 0.55 Raise → 1.25–1.3 Glow-Peak (tip 2.6×, crystal 3×) = **Release-Beat 26t** → 1.45 Snap → 1.5–3.1 DIRIGIER-Phase (Arm oben, rhythmische 0.4 s-Wellen, crystal 1080°-Spin ≡ 0 mod 360) → 3.6 Settle = letzter Bolt |
| sun_flare | 1.4 s | false | **NEU** (war star_call-Raise): Gather-Crouch mit EINWÄRTS-Armen 0.2–0.72 (matcht den inrushing-Flame-Ring), **Nova-Beat 0.8 s = 16t-Release** (Root-Pop +1, Arme reißen auf, crystal 3×), Settle 1.4 |
| veil_step | 0.55 s | false | **NEU**: Ankunfts-Re-Materialize — Riss-Stretch body-Scale [0.55,1.4,0.55]→Squash 0.12→Settle; Glow-Bones flashen 1.6–1.9×; Bart/Hut/Scarf-Nachpendeln |
| hurt | 0.5 s | false | Flinch auf Idle-Rest ausgerichtet (Torso-Start [2,0,0] statt [0,0,0]); NEU: Bart-Whip-Kette (0.15/0.19/0.24), Glow-Dim 0.7–0.8× |
| death | 2.0 s | hold | Kraft-Verlöschen (Glow guttert), Sit-down-Kollaps; NEU: Bart/Spyglass/Scarf-Nachsacken, Startpose exakt auf Idle-Rest (§5.4-Fix) |

Anim-Ids `animation.wizard_orin.<name>`; catmullrom auf allen organischen Bahnen,
`EclipseGeoAnimations.once/hold`-Kompatibilität unverändert.

## 3. Sway-Design (Auftrag b): phasenversetzte Sinus-Ketten

- **Bart (idle):** `beard` x = `sin(t·60)·2.5 − 2`, `beard_mid` x = `sin(t·60 − 30)·3.2 − 1`,
  `beard_tip` x = `sin(t·60 − 60)·4.2` — Frequenz 60°/s (Periode 6 s = exakt die
  Loop-Länge), Amplitude WÄCHST zur Spitze, Phase LÄUFT der Wurzel nach → Peitschen-Lag
  eines hängenden Strangs. z-Achse gleiche Kette um +90/+60/+30 versetzt (leichte
  Kreisbahn statt reinem Pendel).
- **Robe/Hem/Scarf (idle):** hem doppelte Frequenz (120°/s) gegen die robe_lower-Basis
  (60°/s) — Saum flattert schneller als der Stoff darüber; scarf minimal (0.8/1.5°), er
  ist eng gewickelt.
- **Walk:** identische Kettenlogik auf Gang-Frequenz 360°/s (Phase −35/−70), Hem
  6°-Flare + 720°/s-Ripple.
- **Loop-Mathematik (§5.4-Audit):** ALLE Molang-Frequenzen erfüllen freq·T ≡ 0 mod 360
  (idle: 60·6=360, 120·6=720, 240·6=1440; walk: 360/720·1) → nahtloser Loop; Phasen-
  Offsets verschieben nur, brechen die Schließung nicht.
- **One-Shot-Bookends:** weil der `action`-Controller mit 0 Transition-Ticks schneidet,
  starten/enden alle One-Shots auf den **Sway-Zentren** (beard −2, beard_mid −1,
  beard_tip 0, torso +2, arm ±[−4,0,∓3]) — der maximale Handback-Sprung ist damit
  ≤ Sway-Amplitude (2.5–4.2°) und verschwindet in der laufenden Idle-Welle.

## 4. Java-Verdrahtung (Aufträge c + d) — nur `WizardOrinEntity.java`

1. **NEU `ANIM_SUN_FLARE` + `ANIM_VEIL_STEP`** als Konstanten + `triggerableAnim`-Zeilen
   in `registerActionTriggers` (super = death-hold bleibt).
2. **`startSunFlare` triggert `ANIM_SUN_FLARE`** statt (falsch geteilt) `ANIM_STAR_CALL`.
3. **`tryVeilStep`: `triggerAction(ANIM_VEIL_STEP)` NACH `teleportTo`** — GeckoLib-Trigger
   erreichen nur trackende Clients; nach dem Teleport spielt der One-Shot am ZIEL.
4. **Hurt-Guard erweitert:** `telegraphTimer < 0 && flareTelegraph < 0 && boltsLeft == 0`
   — vorher konnte ein Treffer während der Bolt-Shower das neue 3.6 s-Dirigieren
   zerflinchen (der Cast soll durchlesen; Fairness-Feedback bleibt über Hurt-Sound+Rot-Flash).
5. **`CUE_WIZARD_CATALYST` re-gekoppelt (Bug 3):** orphaned Cue (Row existiert in
   `ProgressionPhotonFxRows`, Sender starb mit `tryQuestTurnIn`) feuert jetzt in
   `dropCustomDeathLoot` beim Catalyst-Drop — Entity-Lane auf Orin (der 40t-Death-Fade
   hält ihn getrackt), Range 64.
6. **`trade`-Kopplung (Auftrag c) verifiziert + dokumentiert:** Orin hat KEIN
   Container-Menü (WANDFIX-5: "trades nothing") — der Dialog-Exchange in `speakLine`
   (via `mobInteract`) IST sein Handel. `triggerAction(ANIM_TRADE)` steht im selben
   Tick wie Caption + `VILLAGER_TRADE`-Sound → alles flusht im selben Packet-Batch,
   der Ledger-Lean landet exakt auf dem Open-Moment. Javadoc-Kommentar an Ort und
   Stelle, damit niemand einen Phantom-Menü-Hook sucht.
7. **Kampf-Anims (Auftrag d) Bestand:** attack-Äquivalente = star_call/sun_flare
   (Orin ist Caster, kein Melee), hurt/death existierten → alle auf M-A-Niveau poliert
   (§2); veil_step als dritter Kampf-Beat ergänzt.

### Gefundene Bugs (alle gefixt)

| # | Bug | Fix |
|---|---|---|
| 1 | `spyglass`-Idle-Keys wiederholten die Basisrotation (−25…−28) → GeckoLib addiert additiv = **doppelter Sag** auf −50° | Keys auf Null-Delta (0→−4→0) umgestellt (Bytecode-Beweis §0) |
| 2 | `star_call` (1.5 s) endete quasi mit dem Release → **ganze Bolt-Shower in Idle-Pose**; hurt konnte zusätzlich reinflinchen | Sheet auf 3.6 s retimed (Dirigier-Phase), Hurt-Guard um `boltsLeft` erweitert |
| 3 | `CUE_WIZARD_CATALYST` **orphaned** (Row ohne Sender seit WANDFIX-5) | Sender in `dropCustomDeathLoot` (Take-Path IST die Übergabe) |
| 4 | `sun_flare` teilte den star_call-Raise → Gather als Sky-Raise mis-verkauft | eigenes 1.4 s-Sheet, Nova-Beat = 16t |
| 5 | `veil_step` hatte keine Anim; `death` startete auf 0-Pose (Torso/Arme 2–4° Snap beim harten action-Schnitt) | veil_step-Sheet + Trigger; death-Startkeys auf Idle-Rest |

## 5. Validierung (wörtlich)

**5.1 validate_geo** (`python3 scripts/geckolib_gen/validate_geo.py …geo.json …animation.json`):

```
=== GEO  …/wizard_orin.geo.json
    identifier geometry.wizard_orin  canvas 64x64  19 bones  19 cubes
  -> PASS (0 error(s), 0 warning(s))
=== ANIM …/wizard_orin.animation.json
    9 animation(s): …idle, …walk, …greet, …trade, …star_call, …sun_flare, …veil_step, …hurt, …death
  -> PASS (0 error(s), 0 warning(s))
============================================================
validate_geo: 2/2 file(s) passed — all good
```

**5.2 Painter-Determinismus** (2× `python3 scripts/geckolib_gen/mobs/wizard_orin.py`,
md5 beider Läufe identisch — `diff` leer, `DETERMINISTIC`):

```
d62c5e37aa7d4dbd51cec4993d53348c  …/textures/entity/wizard_orin.png          (2120 albedo px)
27584a7150eeca044eb28ec59e9f5492  …/textures/entity/wizard_orin_glowmask.png (100 glow px)
```

**5.3 compileJava:** `./gradlew compileJava` → `BUILD SUCCESSFUL` (2 actionable tasks).

**5.4 Loop-/Handback-Audit** (Offline-Skript gegen das ECHTE Runtime-Modell: base 4t
Transition, action 0t → Bookends gegen Idle-Sway-Zentren gemessen, Rotationen mod 360):

```
== 1. LOOP CLOSURE (idle 6.0s / walk 1.0s)
  all molang periods close (freq*T = 0 mod 360), all key channels first==last
== greet/trade/star_call/sun_flare/veil_step/hurt
  worst start-vs-centre 0.00 | worst end-vs-centre 0.00 (within sway amp = invisible)
== death (2.0s, hold)
  worst start-vs-centre 0.00 | held (no handback)
```

(One-Shot-Spins enden auf 360°-Vielfachen: star_call-crystal 1080 ≡ 0, sun_flare 360 ≡ 0.)

**5.5 Polish-Pässe:** (1) spyglass-Doppel-Sag + Sway-Zentren-Bookends nach dem
Bytecode-Befund; (2) star_call-Retiming auf die nachgerechnete 26t-Release-Semantik
(nicht die 25t-Konstante!); (3) death-Startpose-Alignment + finaler Audit-Lauf (5.4).

## 6. Geänderte Dateien (alle im MB2-Besitz)

| Datei | Änderung |
|---|---|
| `assets/eclipse/geo/entity/wizard_orin.geo.json` | Bart 1→3-Segment-Kette (§1); sonst unberührt |
| `assets/eclipse/animations/entity/wizard_orin.animation.json` | 7→9 Anims, star_call 1.5→3.6 s, Sway-Ketten, Bookend-Hygiene (§2/§3) |
| `entity/wizard/WizardOrinEntity.java` | 2 neue Anim-Konstanten+Trigger, veil_step-Hook, sun_flare-Umtriggern, Hurt-Guard, Catalyst-Cue-Sender, trade-Doku (§4) |
| `textures/entity/wizard_orin{,_glowmask}.png` | Painter-Regenerat (Bart-Segment-UVs), NICHT von Hand |
| `docs/uv/wizard_orin.md` | Tabelle auf 19/19-Ist-Stand (robe_hem/crystal/book fehlten schon vorher), Rig-Note zur Bart-Kette |

**Kein langdrop nötig** (keine neuen Lang-Keys). Painter-Skript unverändert
(`beard*`-Regel deckt die neuen Segmente). Renderer unverändert.

## 7. Photon-Partner-WUNSCH für star_call (Auftrag a — Spec, NICHT gebaut)

Eigenes Child-fx, bewusst NICHT aus der `gen_player_fx.py`-Sternfall-Familie: keine
himmelsfallenden Star-Streaks — die Impacts gehören weiter dem Server (`dropStarBolt`,
END_ROD/Firework pro Bolt). Das Child-fx verkauft das DIRIGIEREN, nicht den Einschlag.

**7.1 Cue-Snippet → `network/fx/FxCues.java` (Integrator):**

```java
/**
 * MB2: star_call Photon-Partner ({@code eclipse:wizard_star_call}) — Staff-Tip-Mote-Säule
 * während des rooted Raise, Release-Flash auf dem 26t-Beat, Dirigier-Drizzle solange die
 * Bolts fallen. Entity-Lane auf Orin; a = Sekunden bis zum Release-Beat (1.30 Basis /
 * 0.95 unveiled), b = Shower-Sekunden (Bolts × 0.25). Gesendet von WizardOrinEntity
 * beim Telegraph-START (gleicher Tick wie der ANIM_STAR_CALL-Trigger).
 */
public static final ResourceLocation CUE_WIZARD_STAR_CALL = cue("wizard_star_call");
```

**7.2 Registrar-Klasse → NEU `veilfx/WizardFxRows.java` (PH-CORE-Muster, 1:1 kopierbar):**

```java
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class WizardFxRows {
    private WizardFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WIZARD_STAR_CALL,
                fx("wizard_star_call"),
                null,                       // Vanilla-Chimes/END_ROD bleiben die photon-lose Baseline
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
```

Mode **LAYER** + Fallback `null`: die bestehenden Vanilla-Partikel im Entity-Code sind
bereits eine vollständige Baseline; Photon legt nur die Kür obendrauf (kein
Quasar-Duplikat nötig, Budget-Kanal BURST).

**7.3 Sender-Snippet → `WizardOrinEntity.tickCombat`, direkt nach
`triggerAction(ANIM_STAR_CALL);` (MEINE Datei — Einbau erst NACH 7.1, sonst
kompiliert's nicht; deshalb bewusst noch nicht drin):**

```java
FxPayloads.sendFxEntityEvent(level, FxCues.CUE_WIZARD_STAR_CALL, this,
        unveiled ? 0.95F : 1.30F,                                           // a: Release-Beat s
        (unveiled ? STAR_CALL_BOLTS_UNVEILED : STAR_CALL_BOLTS) * 0.25F,    // b: Shower s
        64.0D);
```

**7.4 Child-fx-Spec `assets/eclipse/fx/wizard_star_call.fx`** (Autor: A-FX-Team via
`tools/photon/fxlib.py`; Timings = Anim-Keyframes aus §2; Anker = Entity-Lane Orin,
Staff-Tip-Offset x −0.31 / y +1.40 über Fuß — Konvention wie `wizard_catalyst_indraw`):

| Emitter | Fenster | Layout | Farbe/Look |
|---|---|---|---|
| `raise_motes` | 0 → a s | schmale aufsteigende Mote-Säule am Staff-Tip (r 0.15, Drift +0.8 b/s, Life 0.5 s), Rate 6→22 p/s mit Dip 0.7× beim Crouch (0.18 s) und Voll-Rampe ab dem Raise (0.55 s) | Staff-Tip-Emissive-Palette `#EAF6FF`→`#BFE2FF`, additiv, Size-Taper 0.06→0.02 |
| `release_flash` | Burst bei a s | 24-Punkt-Radialring r 0.5→2.2 b in 0.3 s + vertikaler Beam-Puls (h 6 b, 0.15 s) — matcht glow_staff_tip 1.9→2.6× (Keys 1.25/1.3) und den Arm-Snap 1.45 | Kern `#FFF7DC`, Saum `#9FC4FF` |
| `conducting_drizzle` | a → a+b s | sanfter Stern-Staub-Kegel um Orin (r 1.6 b, Fall −0.4 b/s, 8 p/s, 3 Hz-Twinkle), endet HART mit dem letzten Bolt | gedimmt `#F5E6B8` α160 |

Budget: Peak < 300 Partikel (BURST-Kanal-üblich). Die Zielzone (`starZone`, bis 4 b
Radius, kann weit weg sein) bleibt dem Child-fx TABU — Lesbarkeit + Budget, und die
Server-Impacts sind dort schon laut genug.

## 8. Test-Rezept (Client, llvmpipe-geduldig)

```
./gradlew build && ./gradlew runClient        # bzw. Server + RCON (AGENTS.md)

/summon eclipse:wizard_orin
# 1) idle 6s beobachten: Bart-Kette peitscht phasenversetzt, Hem-Flattern, Buch-Beat,
#    KEIN Spyglass-Doppel-Sag mehr (hing vorher ~50° statt 25°).
# 2) Rechtsklick → trade-Ledger-Lean EXAKT auf Caption+VILLAGER_TRADE (Auftrag c).
# 3) Provozieren (3 Treffer): star_call — Raise, Release-Blitz bei ~1.3s, dann DIRIGIEREN
#    solange Bolts fallen (Treffer währenddessen: KEIN Flinch — Guard-Check).
# 4) Nahe stehen bleiben: sun_flare-Gather (Arme einwärts!) → Nova-Pop bei 0.8s.
# 5) Bedrängen zwischen Casts: veil_step — Riss-Stretch am ZIELort.
# 6) Auskämpfen: death-Sit-down ohne Start-Snap; Catalyst-Drop feuert
#    CUE_WIZARD_CATALYST (NEWFX-A5-Row, Photon oder Quasar-Fallback sichtbar).
```

## 9. Offene Punkte

1. **§7 komplett beim Integrator:** Cue-Konstante (7.1), `WizardFxRows` (7.2), danach
   Sender (7.3) in meiner Datei, Child-fx (7.4) beim A-FX-Team. Bis dahin läuft
   star_call vollständig auf der Vanilla-Baseline — nichts ist kaputt.
2. **Unveiled-Beat:** EIN star_call-Sheet, getunt auf den Basis-Telegraph (26t). Unveiled
   released bei 19t = 0.95 s → der Anim-Akzent kommt 0.35 s "zu spät" (M-A-Präzedenz:
   MA3 §8 VOLLEY akzeptiert dasselbe bei skaliertem Telegraph). Der a-Parameter im Cue
   hält wenigstens das FX ehrlich. Falls es stört: `star_call_fast`-Variante als Follow-up.
3. **Unveiled-Shower (3.5 s) überragt den Anim-Tail** (Dirigieren endet 3.6 s nach
   Trigger = 2.65 s nach Unveiled-Release) — die letzten ~3 Bolts fallen in den Settle.
   Hurt-Guard greift trotzdem (zählt `boltsLeft`, nicht die Anim).
4. **Beard-Handback ≤ Sway-Amplitude:** bewusste Auslegung (§3) — messbar 2.0–2.5°,
   in der laufenden Idle-Welle unsichtbar; echtes Null-Delta wäre nur mit
   Molang-in-One-Shots (Haus-Sheets nutzen das nicht) erreichbar.
5. Finales AI-Art darf beide PNGs byte-gleich ersetzen (docs/uv-Kontrakt unverändert).
