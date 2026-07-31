# POLISH2 — „Action-Blend": versionierter Opt-in-Blend für die `action`-Controller

**Auftrag:** Der systemische Befund aus MB1 §9.3 / MA6 §8 — die geteilten GeckoLib-
`action`-Controller stehen auf `transitionLength = 0`, One-Shots schnappen hart aus
idle/walk (Deckhand-Attack: 45° in einem Frame). Lösung: ein versionierter, abwärts-
kompatibler Opt-in-Mechanismus, KEIN pauschales Weichspülen — Teleport/Glitch/Impact-
Snaps bleiben hart.

**Nicht angefasst:** Photon-Generatoren/-Tools, `.fx`-Assets, WizardOrin/DriftLantern/
UmbralStalker-FX-Code, Storm-Dateien, `umbral_blade`/`umbral_pick`/`ferryman_toll`.
`registerControllers` bleibt final, Controller-Namen bleiben `base`/`action`.

---

## 1. Runtime-Fakten (dekompiliert, nicht geraten)

Alle Aussagen gegen das gebundelte `geckolib-neoforge-1.21.1-4.9.2.jar` verifiziert
(`javap -c`, Gradle-Cache).

### 1.1 Eine Transition VERZÖGERT die Anim-Uhr — sie läuft NICHT sofort los

Der Auftragstext vermutete „GeckoLib still starts the animation clock immediately".
**Das ist für 4.9.2 falsch**, und der Unterschied ist der Kern jeder Blend-Entscheidung:

```
AnimationController.process (Bytecode-Offsets 13–51):
  if (animationState == TRANSITIONING && adjustedTick >= transitionLength) {
      shouldResetTick = true;
      animationState  = RUNNING;
      adjustedTick    = adjustTick(seekTime);   // -> tickOffset = seekTime, RETURN 0
  }
AnimationController.adjustTick (Offsets 0–59):
  shouldResetTick gesetzt -> tickOffset = tick; return 0;
```

Während der Transition lerpt der Controller die Bone-Snapshots (= die live sichtbare
Pose, inkl. dessen was `base` gerade schreibt) **linear und ungewrappt** auf die
t=0-Pose des One-Shots (`getAnimationPointAtTick(..., 0, ...)`), `query.anim_time`
steht dabei auf 0 (`lambda$process$4` → `0.0`; deckt sich mit MC5 §1.2). Erst nach
`transitionLength` Ticks beginnt die Uhr bei 0. **Ein N-Tick-Blend verschiebt also die
GESAMTE Anim-Timeline um N Ticks nach hinten** — dieselbe Rasterkanten-Tatsache, auf
der MB1 §5.1 die row-Loop verankert hat („verankert sich 4 t nach der Rasterkante").

### 1.2 Wie dieses Repo anim-synchrone FX feuert: ausschließlich Java-Timer

`rg setSoundKeyframeHandler|setParticleKeyframeHandler|setCustomInstructionKeyframeHandler|sound_effects|particle_effects`
über `src/main/java` + alle `animation.json`: **null Treffer**. Es gibt keine
GeckoLib-Keyframe-FX. Jeder Beat ist ein Server-Tick-Zähler ab dem Trigger-Tick:

| Beat | Timer | Anim-Referenz |
|---|---|---|
| Colossus `slam`-Impact (Damage+Shake+Ring) | `GroundSlamGoal.IMPACT_TICK = 27` | Anim-Drop bei 1.35 s = Tick 27 — **frame-exakt** |
| Hound `charge_windup` → Dash-Start | `ChargedLungeGoal.WINDUP_TICKS = 20` | Anim 1.0 s = 20 t; dazu 20-t-Photon-Spirale `CUE_HOUND_WINDUP` am Trigger-Tick — **frame-exakt** |
| Hound `lunge` | Dash-Velocity ab Trigger-Tick | motion-locked |
| Cultist `cast` → Bolt-Fan | `RangedShadowBoltGoal`, Release ~t21 | Release-Akzent-Keys der Anim bei 1.0–1.05 s — quasi frame-exakt |
| Wand `use_*` | Muzzle-Cue `CUE_WANDFX2_MUZZLE` + Impact-FX am Cast-Tick | Anim folgt kosmetisch (Apex t4–7) |
| Extractor `extract` | Herz-Tausch/Sound/`S2CHeartBurstPayload` am Trigger-Tick | Anim folgt kosmetisch |
| Melee-`attack` (Deckhand/Cultist/Colossus/Hound) | Damage in `doHurtTarget` VOR dem Trigger | Anim ist reiner Follow-Through |
| `death` überall | `tickDeath`-Fenster == Clip-Länge (30/30/50/30 t) | Poof am Fensterende — **frame-exakt** |

Konsequenz: ein Blend verschiebt bei Java-Timern **die sichtbare Pose relativ zum
Beat** (der Beat feuert weiter ab Trigger-Tick). Für frame-exakte Beats ist das ein
Verbot; für Follow-Through-Anims (Damage/Effekt liegt VOR bzw. AUF dem Trigger) ist es
eine um N Ticks längere kosmetische Latenz.

### 1.3 Der Trigger-Trichter ist überschreibbar

`AnimationController` ist public/non-final, `tryTriggerAnimation(String)` public,
`transitionLength(int)` ist ein öffentlicher Laufzeit-Setter,
`triggerableAnimations` protected. JEDER Trigger-Pfad läuft per `invokevirtual` durch
`AnimatableManager.tryTriggerAnimation` → `AnimationController.tryTriggerAnimation`
(server-seitiges `triggerAnim`, GeckoLib-Sync-Packet auf Clients, UND der client-only
Singleton-Kurzschluss der Item-`equip`-Flourishes). Ein Override dort sieht den
Anim-Namen, BEVOR die Transition aufgesetzt wird — der perfekte Policy-Punkt.

---

## 2. Design: `EclipseActionController` + `actionTransitionTicks(String)`

**Neu:** `entity/geo/EclipseActionController.java` — erbt von `AnimationController`,
Konstruktor pinnt 0, `tryTriggerAnimation` setzt vor dem Delegieren
`transitionLength(policy.applyAsInt(animName))` (nur für registrierte Namen; unbekannte
Namen ändern nichts und schlagen wie v1 in super fehl).

**Basen:** `EclipseGeoMob`/`EclipseGeoMonster` (im Lockstep geändert) bauen den
`action`-Controller jetzt als `EclipseActionController` mit dem neuen überschreibbaren
Hook `protected int actionTransitionTicks(String animName) { return 0; }` — spiegelt
das bestehende `baseTransitionTicks()`-Idiom. **Default 0 für jeden Trigger =
bit-identisch zu v1**; kein einziger Bestands-Mob ändert sein Verhalten, solange er
nicht überschreibt (Glitch-Trio, Wanderer-`notice`, Wizard/Lantern/Stalker, Pale,
Gazer, Bosse … bleiben unangetastet hart).

**Items:** gleiche Klasse mit Inline-Policy (Lambda) in `ArmArtifactItem` und
`HeartExtractorItem`.

**Warum per-Trigger statt per-Controller?** Colossus trägt `attack` (soll blenden) und
`slam` (MUSS hart bleiben) auf DEMSELBEN Controller; der Hound `attack` vs.
`charge_windup`/`lunge` ebenso. Ein controller-weiter Wert hätte entweder die
frame-exakten Beats gebrochen oder den Blend verhindert.

**Warum kein dritter „action_blend"-Controller?** Der Zwei-Controller-Contract ist
eingefroren (Namen in Plan §6; `triggerAction` routet über den Namen `action`; Fight-
Code und `DeckhandRenderer.isPlaying(CONTROLLER_ACTION, …)` hängen daran). Ein dritter
Controller hätte jeden Call-Site- und Renderer-Kontrakt angefasst — maximale
Regressionsfläche für null Zusatznutzen gegenüber der per-Trigger-Policy.

**Interrupt-Verhalten (MC5 Bug-B-4-Pfad):** Unterbricht ein neuer Trigger einen
laufenden One-Shot, gilt die Policy des NEUEN Triggers (Wert wird bei jedem
`tryTriggerAnimation` frisch gesetzt) — ein harter Trigger nach einem geblendeten
bleibt hart, und umgekehrt.

---

## 3. Entscheidungstabelle (hart vs. Blend, pro Konsument)

Blend-Werte in Ticks; „—" = Datei nicht angefasst, erbt Default 0.

| Konsument | Trigger | v2 | Begründung |
|---|---|---|---|
| Deckhand | `attack` | **3** | MB1s 45°-Snap (gemessen: worst 49.4°, Mittel 44.8° auf `arm_right.rotx` aus `idle_sag`) → 16.5°/Frame. Damage vor Trigger, kein Timer in den Clip. |
| Deckhand | `rise` | **2** | Verlässt die row-Loop an beliebiger Phase (worst 18.5° `lantern.rotx`) → 9.3°/Frame. Oar-Hand-off sicher: `oarShown` keyt auf Anim-IDENTITÄT (`getCurrentAnimation` steht ab Transitions-START). |
| Deckhand | `death` | 0 | 30-t-`tickDeath`-Fenster == Clip-Länge; Blend würde die gehaltene Endpose um 2–3 t beschneiden. |
| Cultist | `cast`, `attack` | **0 (bewusst)** | Zwei Gründe: (a) MB3s Sheets sind bereits pop-frei authoriert — Entry-Snap ohne `runes` nur 6.2° (idle) / 20.0° (walk); (b) **Spin-Hazard**: `idle`/`walk` drehen `runes.roty` per Molang 0→360, `cast`/`attack` pinnen ab 0 — ein ungewrappter 2-t-Lerp peitscht den Ring an schlechter Phase mit bis zu ~175°/Frame RÜCKWÄRTS durch die falsche Kreishälfte; der harte Cut liest sich dagegen als ≤180°-Wrap-Flip. Bonus: der Bolt-Release (t≈21) bleibt frame-exakt auf dem Release-Akzent (Keys 1.0–1.05 s). |
| Colossus | `attack` | **3** | Feuert i. d. R. aus `walk` (worst 36.0° `arm_right.rotx`) → 12°/Frame; Damage vor Trigger. |
| Colossus | `slam` | 0 | `IMPACT_TICK = 27` == Anim-Drop 1.35 s, **frame-exakt** (Damage, Launch, Shake, Ring-Stamp). Impact-Style per Auftrag hart. |
| Colossus | `roar` | 0 | Notice-Style-Aggro-Cue, Sound am Trigger-Tick; MA6-Exit-Naht nur 5°. |
| Colossus | `death` | 0 | Scripted 50-t-Kollaps, Ground-Shake-Beat bei `DEATH_IMPACT_TICK` nimmt Clip-Start = Trigger an. |
| Storm Hound | `attack` | **3** | Biss aus `sprint` (worst 52.0° `leg_fl.rotx`) → 17.3°/Frame; Damage vor Trigger (Melee + Lunge-Strike). |
| Storm Hound | `charge_windup` | 0 | **Frame-exakt doppelt**: 20-t-Windup-Timer UND 20-t-Photon-Spirale `CUE_HOUND_WINDUP` ab Trigger-Tick; Dash-Richtung lockt am Windup-Ende. |
| Storm Hound | `lunge` | 0 | Motion-locked: Dash-Velocity beginnt am Trigger-Tick. |
| Storm Hound | `howl` | 0 | Notice-Style (Colossus-roar-Muster), Sound am Trigger-Tick. |
| Glitch-Trio (`GlitchedMonster`) | `attack`, `glitch_blink`, `death` | — | Glitch-Ästhetik ist der Punkt; hart per Auftrag. |
| Wanderer (MB5) | `notice` | — | Der Horror-Head-Snap bei 0.10 s ist DELIBERATE; hart per Auftrag. |
| Wizard Orin / Drift Lantern / Umbral Stalker | alle | — | FX-Besitz diese Runde bei anderem Team; erben Default 0 = unverändert. |
| Wand (`EclipseWandItem`) | `use`, `use_riss`, `use_glut`, `use_stern`, `levelup`, `awaken`, `stall` | **0 (bewusst, Datei unverändert)** | Gemessener Entry-Snap ≤ 2.0° — MD1 hat die Entry-Posen matched authoriert („idle-unberührt ⇒ Pop-frei"). Ein Blend würde nichts Sichtbares glätten, aber die Flicks um 2 t gegen die t0-Muzzle-/Impact-FX verspäten. „Only where they help" → hier hilft nichts. |
| Arm-Artifact | `open` | **2** | Worst 26.0° (`glow_page_a.roty` aus `idle_unread`) → 13°/Frame; das Handbook öffnet am selben Tick, Anim ist kosmetisch. |
| Arm-Artifact | `equip` | 0 | **Spin-Hazard**: `equip` startet `ledger.roty` bei −360° (authorierter Voll-Spin, pose-identisch zu idles 0° beim Cut) — ein 2-t-Lerp peitscht den Ledger eine ganze Umdrehung. Zudem maskiert der Vanilla-Item-Raise den Entry ohnehin. |
| Heart Extractor | `extract` | **2** | Worst 25.0° (`chamber_lid.rotx` aus dem `channel`-Plateau) → 12.5°/Frame; Herz-Tausch/Sound bleiben am Trigger-Tick, der sichtbare Rückstoß folgt 2 t später. Der MD2-Deckel-Knall (29°→−2° MIT Nachfedern) liegt IM Clip und bleibt unberührt. |
| Heart Extractor | `refuse` | 0 | Bewusster Ablehnungs-Jolt; Entry-Snap ohnehin nur 3.5°. |
| Heart Extractor | `equip` | 0 | Vom Vanilla-Raise maskiert; kein Nutzen. |
| ReviveSigil / StormHeart / HeraldsLure | alle | — | Außerhalb des Auftrags-Scopes (Storm-Dateien explizit verboten); Controller stehen weiter hart auf 0. Bei Bedarf später via `EclipseActionController` nachrüstbar. |

---

## 4. Snap-Messungen (MB1-§9.3-Methode, generalisiert)

Methode: pro (One-Shot, Basis-Loop)-Paar die t0-Rotationspose des One-Shots (erste
Keyframes, Molang mit `anim_time = 0` bzw. Sweep) gegen die über eine volle Loop-Periode
gesampelte Basis-Pose (dt = 0.02 s, linear zwischen Keys; Molang `math.sin/cos` in GRAD,
`anim_time` in Sekunden — MC5-verifiziert). „Worst" = schlechteste Loop-Phase,
**gewrappte** Winkeldistanz (= was das Auge im Ein-Frame-Cut sieht); „Hazard" =
ungewrappt−gewrappt > 0 (Kanäle, die ein Blend durch die falsche Kreishälfte zöge).
Nicht modelliert: Catmullrom-Überschwinger zwischen Keys (Keys sind dicht) und
Positions-Kanäle (px; überall ≤ ~1 Block-Bruchteil). **Kalibrierung:** Deckhand-Attack
aus `idle_sag` ergibt Mittel 44.8° auf `arm_right.rotx` — deckt MB1s unabhängig
gemessene „45° in einem Frame".

| Sheet | Action | Basis | Worst-Snap (vorher) | Kanal | v2 | nachher (°/Frame) |
|---|---|---|---|---|---|---|
| deckhand | attack | idle_sag | **49.4°** | arm_right.rotx | 3 t | **16.5** |
| deckhand | attack | walk | 16.5° | lantern.rotx | 3 t | 5.5 |
| deckhand | rise | row | 18.5° | lantern.rotx | 2 t | 9.3 |
| eclipse_cultist | cast | idle | 6.2° (ohne runes) | arm_right.rotx | 0 | 6.2 (unverändert) |
| eclipse_cultist | cast | walk | 20.0° (ohne runes) | arm_right.rotx | 0 | 20.0 (unverändert) |
| eclipse_cultist | cast/attack | idle/walk | Hazard: runes.roty 360° ungewrappt | runes.roty | 0 | Blend hätte bis ~175°/Frame Rück-Whip erzeugt |
| fog_colossus | attack | walk | **36.0°** | arm_right.rotx | 3 t | **12.0** |
| fog_colossus | attack | idle | 7.0° | arm_right.rotz | 3 t | 2.3 |
| fog_colossus | slam | walk | 36.0° | arm_right.rotx | 0 | frame-exakter Impact schlägt Kosmetik |
| storm_hound | attack | sprint | **52.0°** | leg_fl.rotx | 3 t | **17.3** |
| storm_hound | attack | walk | 40.0° | leg_fl.rotx | 3 t | 13.3 |
| storm_hound | charge_windup | sprint | 54.0° | leg_fl_lower.rotx | 0 | 20-t-Photon-Sync schlägt Kosmetik |
| eclipse_wand | use/use_* | idle | 1.5° | root.rotz | 0 | bereits pop-frei |
| eclipse_wand | levelup/awaken | idle | 2.0° | knot.roty | 0 | bereits pop-frei |
| arm_artifact | open | idle_unread | **26.0°** | glow_page_a.roty | 2 t | **13.0** |
| arm_artifact | open | idle | 14.0° | fingers.rotx | 2 t | 7.0 |
| arm_artifact | equip | idle | 40.0° gewrappt; Hazard ledger.roty 360° | fingers.rotx / ledger.roty | 0 | Blend hätte Voll-Rotations-Whip erzeugt |
| heart_extractor | extract | channel | **25.0°** | chamber_lid.rotx | 2 t | **12.5** |
| heart_extractor | refuse | idle | 3.5° | chamber_lid.rotx | 0 | Jolt bewusst |
| heart_extractor | equip | idle | 25.0° | root.roty | 0 | vom Vanilla-Raise maskiert |

### 4.1 FX-Beat-Interaktion der geblendeten Trigger (die Timeline-Verschiebung, §1.1)

* **Melee-`attack` (Deckhand 3 t / Colossus 3 t / Hound 3 t):** Damage, Sound und
  Knockback liegen in `doHurtTarget` VOR dem Trigger — der Clip war schon immer reiner
  Follow-Through, der 3-t-Versatz verlängert nur die ohnehin vorhandene
  Hit-zu-Swing-Latenz um 0.15 s. Kein Timer beatet in die Clips.
* **Deckhand `rise` (2 t):** `DROWNED_AMBIENT_WATER` spielt am Trigger-Tick (Szenen-,
  kein Pose-Sound). Die Oar-Sichtbarkeit hängt an der Anim-Identität, nicht an einer
  Tick-Uhr (§3), und der Clip löst das Ruder selbst erst ab 0.14 s auf — 2 t Versatz
  liegen innerhalb dieses Fensters.
* **Artifact `open` (2 t):** Screen-Open ist client-instantan am selben Tick; kein Beat.
* **Extractor `extract` (2 t):** Herzabzug, Fragmente, `S2CHeartBurstPayload`, Sound —
  alles am Trigger-Tick (t0), im Clip liegt kein weiterer Beat. Sichtbarer Rückstoß
  +2 t = 0.1 s nach dem Burst; unterhalb der ohnehin vorhandenen Netz-Latenz-Varianz.

### 4.2 Was v2 bewusst NICHT löst: die Exit-Naht

Der Blend wirkt nur am EINTRITT. Endet ein `once()`-One-Shot, geht der Controller auf
STOPPED und `base` scheint im selben Frame durch — wie bisher. MA6 §8 hat diese Nähte
vermessen (Colossus 5.0°, Hound 18° auf dem head-tracked und damit ohnehin
überschriebenen `head`): die Sheets exiten nahe neutral, der Rest bräuchte einen
Blend-OUT-Mechanismus (GeckoLib 4.9.2 bietet keinen; ein Fake über
`hold_on_last_frame`+Timer wäre ein neuer Contract). Ausdrücklich Folge-Thema.

---

## 5. FROZEN-Contract v2 (Wortlaut-Änderungen)

* `docs/plans_v3/handoff/P6_geckolib_conventions.md` §3: Klassen-Inventar um
  `EclipseActionController` ergänzt; „`action` (transition 0, triggerables only)" ersetzt
  durch die v2-Regel: **Default 0 pro Trigger (bit-identisch v1), Opt-in 2–4 t pro
  One-Shot via `actionTransitionTicks(String)`**, mit den drei MUST-stay-hard-Klassen
  (Timer-beatete Clips, Horror/Glitch-Snaps inkl. `death`, Molang-Spin-Bones) und dem
  Verweis auf diesen Report.
* Javadoc der Basen (`EclipseGeoMob`/`EclipseGeoMonster`, Lockstep) + ausführliche
  Regel-Javadoc auf `EclipseActionController`.
* Die Uhr-Semantik (Blend = Clip-Verzögerung, §1.1) steht jetzt explizit im Contract,
  damit kein Team wieder „Transition schadet nicht, die Uhr läuft ja" annimmt.

---

## 6. Validierung

* `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` →
  **BUILD SUCCESSFUL** (2 vorbestehende, themenfremde Deprecation-Warnungen in
  `MobPhotonFxRows`).
* GeckoLib-Runtime-Harness: `rg "MathParser|BakedModelFactory" tools/ scripts/` →
  **kein Treffer**, es existiert keines; deshalb die mathematische Beweisführung oben
  (Messwerkzeug nach MB1-Vorbild, nicht committet — hängt an keiner Projekt-API).
* Trigger-Pfad-Abdeckung: `AnimatableManager.tryTriggerAnimation` ruft
  `AnimationController.tryTriggerAnimation` per `invokevirtual` (Bytecode geprüft) —
  Server-Trigger, Client-Sync-Packet und der client-only `equip`-Kurzschluss laufen
  alle durch die Policy.

## 7. Geänderte Dateien

| Datei | Änderung |
|---|---|
| `entity/geo/EclipseActionController.java` | NEU — per-Trigger-Transition-Controller (v2) |
| `entity/geo/EclipseGeoMob.java` | `action` → `EclipseActionController`, Hook `actionTransitionTicks(String)` (Default 0), Javadoc v2 |
| `entity/geo/EclipseGeoMonster.java` | dito (Lockstep) |
| `entity/DeckhandEntity.java` | Override: `attack` 3 t, `rise` 2 t (nur Controller-Code) |
| `entity/fog/FogColossusEntity.java` | Override: `attack` 3 t |
| `entity/fog/StormHoundEntity.java` | Override: `attack` 3 t |
| `artifact/ArmArtifactItem.java` | Action-Controller → `EclipseActionController`, `open` 2 t |
| `ritual/HeartExtractorItem.java` | Action-Controller → `EclipseActionController`, `extract` 2 t |
| `docs/plans_v3/handoff/P6_geckolib_conventions.md` | FROZEN-Contract v2 |
| `docs/plans_v3/session_0730/POLISH2_ACTIONBLEND_REPORT.md` | dieser Report |

**Bewusst unverändert:** `EclipseWandItem` (Entry-Snaps ≤ 2°, Blend wäre reine
FX-Latenz), `EclipseCultistEntity` (runes-Spin-Hazard + pop-frei authorierte Entries),
`GlitchedMonster`/`GlitchedWandererEntity` (Snaps deliberate), ReviveSigil/StormHeart/
HeraldsLure (Scope), alle FX-/Asset-Dateien.
