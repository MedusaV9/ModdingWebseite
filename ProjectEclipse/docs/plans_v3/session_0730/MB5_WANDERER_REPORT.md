# MB5 — Glitched Wanderer / Backrooms (Welle M-B, Mob/Item-Zensus F-098)

**Auftrag:** MOB_ITEM_CENSUS §5 Welle M-B Zeile MB5 — (a) die `notice`→`sprint`-Kette
als DER Horror-Beat der Backrooms: `notice` mit Kopf-Snap (0.1 s) + echtem Halte-Frame,
Timing-Analyse + Cue-Punkte für B5 (Dread/Licht) und B2 (Shroud); (b) `sprint`-Zyklus
unheimlich-unnatürlich (steife Arme, ruckelnde Frame-Versätze); (c) Painter-Skript von
`scripts/skin_gen/` nach `scripts/geckolib_gen/mobs/` umziehen; (d) Shroud-Loop-Bone-Anker
für B2s `wanderer_static_shroud`.

**Datei-Besitz (exklusiv, §5-G1):**
`backrooms/GlitchedWandererEntity.java`, `client/backrooms/*`, Assets `glitched_wanderer*`
(geo/animations/textures), `backrooms_wanderer.py` (mit Umzugsrecht, Auftrag c),
`docs/uv/backrooms_wanderer.md`, dieser Report.
**Nicht angefasst:** `tools/photon/**` + `assets/eclipse/fx/**` (B2 — nur GELESEN),
`backrooms/BackroomsDread.java` / `BackroomsScare.java` / `BackroomsEntities.java`
(B5/andere — nur GELESEN), FROZEN-Basen (`EclipseGeoMonster`, `GlitchedMonster`,
`GlitchedHuskEntity`, `EclipseGeoRenderer`), `validate_geo.py`/`paint_lib.py`,
`glitched_husk.py`/`glitch_lib.py`, Lang-Dateien, `sounds.json`.

---

## 0. Plan (vor der Implementierung festgehalten)

1. Runtime-Trace erst, Design danach: Wann feuert `notice` heute *wirklich*? Wie
   komponiert GeckoLib `base` + `action`? Wo hängt B2s Shroud tatsächlich? Nichts raten.
2. `notice` neu bauen — aber die eigentliche Frage ist nicht „welche Keys", sondern
   „friert der Mob überhaupt ein?". Anim + Server-Freeze zusammen, sonst schlittert die
   Statue durch den Flur.
3. `sprint` auf ein Tick-Raster ziehen und vier gezielte Falschheiten einbauen.
4. Painter umziehen, Pfad-Referenzen per `rg` belegen (nicht raten, welche es gibt).
5. Anker-Bone: Pivot aus B2s echtem Offset **nachrechnen**, nicht schätzen.
6. Validierung nach jeder Runde; Selbstkritik + 2 Polish-Pässe.

---

## 1. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 1.1 Controller-Komposition — warum ein „Freeze" 11 Bones braucht

`EclipseGeoMonster.registerControllers` ist FINAL: `base` (transition 4 t,
`handleBaseState`) wird **zuerst** registriert, `action` (transition **0**,
triggerbare One-Shots) **danach**. GeckoLibs `AnimationProcessor` schreibt Bone-Werte
per **Zuweisung** in Controller-Reihenfolge — der später registrierte Controller
gewinnt, aber **nur für Bones, die er auch animiert**.

Daraus folgt direkt der erste Bug (§2.1): eine `notice`, die die Beine nicht animiert,
lässt den `base`-Controller darunter weiterlaufen. Der „Ganzkörper-Freeze" lief.

### 1.2 Head-Tracking ist ADDITIV

`EclipseGeoRenderer` konstruiert `DefaultedEntityGeoModel(..., turnsHead = true)`.
Dessen `setCustomAnimations` läuft **nach** dem Animations-Pass und addiert:
`head.setRotX(head.getRotX() + headPitch)`. Der `head`-Kanal der `notice` ist damit ein
**Delta auf die Live-Blickrichtung**, kein Absolutwert. Konsequenz fürs Design: der
Snap ist immer sichtbar, egal wo der Spieler steht — er kann nicht „verschluckt" werden,
weil der Kopf schon zufällig dorthin zeigte.

### 1.3 B2s `wanderer_static_shroud` — wo es HEUTE hängt

`PhotonMobFx` (nur gelesen):

```java
new LoopRow(GlitchedWandererEntity.class, fx("wanderer_static_shroud"),
        PhotonBridge.AUTO_ROTATE_NONE, new Vec3(0.0D, -0.7D, 0.0D), 24.0D, 4, ALWAYS, null, null),
```

Anker = **Augenposition + (0, −0.7, 0)**, also Welt-Raum, nicht Bone. Mit
`BackroomsEntities` → `.sized(0.6F, 1.9F).eyeHeight(1.66F)`:

**1.66 − 0.70 = 0.96 Blöcke = 15.36 Modell-px.** Das ist der Pivot in (d), nachgerechnet
statt geschätzt.

### 1.4 B5s Dread — welche Schnittstelle die Kette anfassen wird

`BackroomsDread.isHunting(mob, player)` ist:

```java
return mob.getTarget() == player
    || (mob instanceof GlitchedWandererEntity wanderer && wanderer.pacedPlayer() == player);
```

Also hängt der komplette Herzschlag-/Scrape-Kanal (`tickPursuit`) und dessen
Gegenstück `endPursuit` an **meinem** `pacedPlayer()`-Accessor. Das hat mir in §5.2
einen selbst verursachten Bug beschert.

### 1.5 Wann `notice` bisher feuerte — der eigentliche Designfehler

Alt: ausschließlich in `setTarget`, „first target acquisition". Ein Target bekommt der
Wanderer aber nur über `HurtByTargetGoal` **oder** den `NearestAttackableTargetGoal` mit
Prädikat `distanceToSqr <= ATTACK_TRIGGER_RANGE²` = **3 Blöcke**.

Der Beat feuerte also frühestens auf 3 Blöcken Abstand — im Handgemenge, wo er nichts
mehr aufbaut. Der ganze Sinn („es erstarrt und STARRT, *bevor* es losrennt") setzt
Distanz voraus. `PaceGoal` hält bei `STARE_RANGE` = **12** Blöcken an; **dort** gehört
der Beat hin (§3.2).

---

## 2. Gefundene Bugs

| # | Bug | Nachweis | Fix |
|---|---|---|---|
| **B-1** | `notice` animierte **keine Beine** → `base`-Controller stapfte darunter weiter; der „Ganzkörper-Freeze" lief. | §1.1 Controller-Komposition | `leg_left`/`leg_right` in die `notice` aufgenommen → 11 von 11 bekubten Bones (§3.1) |
| **B-2** | Selbst mit vollem Bone-Set **schlitterte** die Statue: der Anim-Layer stoppt nur die Beine, nicht die Entity-Bewegung. | Navigation/Reibung laufen unabhängig vom Renderer | `NoticeFreezeGoal` (MOVE+LOOK, Prio 1) + Delta-Clamp (§3.3) |
| **B-3** | `notice` feuerte erst auf **3 Blöcken** (Target-Akquise), also im Nahkampf statt über den Flur. | §1.5 | Stare-Edge-Trigger in `PaceGoal` bei 12 Blöcken (§3.2) |
| **B-4** | `glitch_blink` konnte die `notice` **mitten im Starren ersetzen** — beide liegen auf dem `action`-Controller, der genau EINEN One-Shot hält. Der Server hätte den Mob dann in Idle-Pose weiter starr gehalten. Trefferwahrscheinlichkeit ≈ 21/240 ≈ **9 %** pro Notice mit Target. | Blink-Kadenz 200–280 t (`GlitchedHuskEntity`), Notice-Fenster 21 t | `blinkCooldownMinTicks()` liefert `-1`, solange der Freeze läuft (§3.4) |
| **B-5** | **Selbst verursacht:** der Freeze preemptet `PaceGoal`, dessen `stop()` `pacedPlayer` nullt → B5s `isHunting()` sah 21 t lang „nicht gejagt" und hätte `endPursuit()`s Entwarnungs-Thud auf dem gruseligsten Tick gespielt. | §1.4 | `pacedPlayer()` liefert während des Freeze das Stare-Target (§5.2) |
| **B-6** | `notice`-Tremor (`shard_torso` Molang) endete bei t = 1.05 auf einem **Restwert** ≈ 0.073 px → Mikro-Pop beim Layer-Drop. | 1080 · 1.05 = 1134° ≢ 0 (mod 180) | Frequenzen auf 1200/2400 °/s (§3.1 Tick-Gesetz) |
| **B-7** | Der Freeze fraß **Knockback**: der Delta-Clamp nullte auch Treffer-Impulse. | Selbstkritik-Pass | Clamp nur bei `hurtTime == 0` (§3.3) |

---

## 3. (a) Die `notice`→`sprint`-Kette

### 3.1 Das Tick-Gesetz

Die `notice` ist **1.05 s = exakt 21 Ticks**, und **jeder** Zeitstempel darin ist ein
Vielfaches von 0.05 s. Das ist keine Kosmetik, sondern eine Anforderung aus den beiden
Konsumenten des Clips:

- der Server-Freeze zählt in **ganzen Ticks** (`NOTICE_TICKS = 21`),
- B5/B2 planen ihre Flicker-/Audio-Cues relativ zum Trigger-**Tick**.

Ein Beat bei 0.86 s ist nicht cue-bar, einer bei 0.85 s schon. Gegenprobe mit GeckoLibs
eigenem Parser (§6.2): `len = 21.00t`, `sprint` `len = 12.00t` — beides ganzzahlig.

Dasselbe Gesetz gilt für die Molang-Frequenzen. Der Tremor braucht Nullstellen an
**beiden** Enden (`f · 1.05 ≡ 0 mod 180`); 1200 und 2400 °/s sind die zwei niedrigsten
Harmonischen, die das erfüllen (1260 = 7·180, 2520 = 14·180) — das behebt B-6.

### 3.2 Timing-Analyse: die fünf Akte

| Akt | t | Tick | Was passiert |
|---|---|---|---|
| **ANTICIPATION** | 0.00–0.05 | T+0…T+1 | Der Kopf dreht sich **9° WEG** (+4 Pitch), die Naht **atmet ein** auf 0.82×. Es hat dich noch nicht gesehen. Doch. |
| *(Stille)* | 0.05–0.10 | T+1…T+2 | Ein voller Tick, in dem **nichts** passiert — die falsche Pose wird gehalten. Das ist der Beat, der den Snap teuer macht. |
| **SNAP** | **0.10** | **T+2** | Echter Step (`pre`/`post`): 18° Pitch + 12° Yaw + 10° Roll in **einem Frame**, Kiefer klappt 40° auf, Naht flarest 0.82 → **2.05**, Root ruckt zurück. Der Zensus fordert 0.1 s — dieser Snap **ist bei exakt 0.10 s fertig**, und die Reise selbst dauert null. Hälse tun das nicht. |
| **CATCH-UP** | 0.15 / 0.20 | T+3 / T+4 | Der **Körper** kommt **einen Tick nach** dem Kopf (Torso, rechter Arm, rechtes Bein), die linke Seite **einen weiteren Tick später**. Head-first/body-second ist der stärkste „das ist kein Mensch"-Read, den die Kette hat. Die `head_shard` (halbes Gesicht) rutscht ebenfalls einen Tick zu spät nach. |
| **HOLD** | 0.25–0.85 | T+5…T+17 | **0.60 s / 12 Ticks Starre.** Nicht perfekt still — das läse als eingefrorenes *Spiel*: `shard_torso` trägt einen Sub-Pixel-Tremor (3.3 / 6.7 Hz), die Naht atmet 1.75 → 1.58 herunter, und **ein** Korruptions-Zucker feuert bei 0.50 s (Kopf) / 0.55 s (Kiefer + Naht) — einen Tick versetzt, das Gesicht reißt also *vor* dem Kiefer. |
| **LOAD / RELEASE** | 0.85–1.05 | T+17…T+21 | Es **spannt sich** (Torso +12°, Beine laden, Naht schwillt auf 2.35×) und entspannt auf **exaktes Neutral**. |

**Warum das Ende auf Neutral landet:** der `action`-Controller hat `transitionLength 0`
— wenn der One-Shot endet, lässt er seine Bones **ohne Blend** los. Landet die letzte
Pose auf Neutral und liegt `idle` innerhalb ~1° davon, ist die Übergabe unsichtbar.
Nachgemessen (§6.2): bei Tick 21.00 stehen `body` auf (0,0,0) und `glow_seam` auf
(1,1,1) — nicht „nah dran", sondern exakt.

**Die Spannungskurve als Ganzes:** 2 Ticks Ruhe → 1 Frame Gewalt → 2 Ticks Nachziehen →
12 Ticks in denen *nichts passiert* → 4 Ticks Aufladen. Die Länge des Hold ist das
eigentliche Werkzeug: 12 Ticks sind lang genug, dass der Spieler anfängt sich zu fragen,
ob es hängt, und kurz genug, dass er nicht weggeht.

### 3.3 Der Freeze ist echt (Server-Seite)

Die Animation allein reicht nicht (B-2). `NoticeFreezeGoal` (Prio **1**, über Melee=2
und Pace=3, unter `FloatGoal`=0) beansprucht **MOVE + LOOK** für `NOTICE_TICKS`:

- preemptet damit `PaceGoal` (MOVE+LOOK) und `MeleeAttackGoal` vollständig,
- `getNavigation().stop()` **jeden** Tick,
- horizontales Delta auf 0 (Y bleibt — eine schwebende Statue wäre ein Bug), weil
  `stop()` allein die Restgeschwindigkeit erst über mehrere Reibungs-Ticks abbaut —
  genau die Ticks, in denen der Snap läuft,
- der **Kopf trackt weiter** (`getLookControl().setLookAt`): der Körper ist festgenagelt,
  der Blick folgt dir. Zusammen mit dem additiven Head-Tracking (§1.2) ist das der
  gesamte Punkt der Pose.
- Der Delta-Clamp ist auf `hurtTime == 0` gegated, damit der Freeze **keinen Knockback
  frisst** (B-7): ein Treffer wirft es weiterhin, es weigert sich nur zu *laufen*.

`beginNotice()` ruft zusätzlich sofort `getNavigation().stop()` auf, weil der
Goal-Selector erst im nächsten Tick neu bewertet — sonst wäre der erste Frame des Snaps
noch ein Schritt.

**Bewusst nicht unterbrechbar.** Bei 1.05 s ist der Freeze kürzer als ein
Vanilla-Shield-Disable, und ein Starren, aus dem man herauszucken kann, ist kein
Starren. Nur der Tod beendet ihn früher (`endNotice()` in `aiStep`).

### 3.4 Trigger-Logik

**Primär — die Stare-Edge** (`PaceGoal.tick`, der `else`-Zweig): Distanz ≤ 12 **und**
`isSeenBy(followed)`. Das ist der Tick, in dem aus Verfolgen ein **gegenseitiges**
Anstarren wird. Der Ablauf, den das erzeugt, ist genau der gewünschte Beat: du schaust
weg → es schleicht mit +50 % Stalk-Burst näher → du drehst dich um → es steht still →
und **schnappt** auf dich.

`isLookedAtBy` ist der Enderman-Test (`dot > 1 − 0.025/dist`, plus Line-of-Sight) —
auf 12 Blöcken ein ~3.7°-Kegel. Streng, und das ist richtig so: der Beat soll feuern,
wenn du es *wirklich* ansiehst.

**Sekundär — `setTarget`** für Spieler, die nie durch die Pace-Phase gingen (direkt in
die 3-Block-Zone gelaufen). Gegated auf `hurtTime == 0`: wenn **du** den Kampf eröffnet
hast, gibt es den normalen Husk-Ausfall, nicht eine geschenkte Sekunde stillstehendes
Ziel.

**Latch + Re-Arm:** einmal pro **Engagement**, nicht pro Leben. `noticed` wird gelöscht,
sobald 200 t (10 s) lang *weder* Target *noch* gepacter Spieler existieren. Der Re-Arm
läuft über einen Zähler in `aiStep`, **nicht** über `PaceGoal.stop()` — `stop()` wird
auch bei Goal-Preemption gerufen (u. a. von meinem eigenen Freeze-Goal) und wäre als
Signal für „Begegnung vorbei" schlicht falsch.

### 3.5 Die Übergabe an `sprint`

Ist der Freeze vorbei, greift wieder `handleBaseState`: `sprint` läuft, sobald
`isMoving() && hasGazeBurst()`. Der Stalk-Burst wiederum hängt daran, dass der Spieler
**wegschaut**. Die Kette schließt sich also so:

> Starren (12 Ticks reglos) → Load (4 Ticks) → du drehst dich weg → Burst-Modifier → `sprint`.

Der `notice`-Layer endet auf Neutral (§3.2), `sprint` startet aus Neutral — kein Pop.

### 3.6 Cue-Spec für B5 (Dread/Licht) und B2 (Shroud)

**Schnittstelle:** neu synchronisiert `GlitchedWandererEntity.isNoticing()`
(`EntityDataAccessor<Boolean>`, server-gesetzt, client-lesbar). `pacedPlayer()` liefert
während des Freeze das Stare-Target (§5.2), `isHunting()` bleibt also durchgehend wahr.

**Cue-Tabelle**, T = Server-Tick, an dem `beginNotice()` feuert (= der Tick, an dem
`isNoticing()` auf `true` geht):

| Tick | Anim-t | Beat | Vorschlag B5 / B2 |
|---|---|---|---|
| T+0 | 0.00 | Anticipation, Naht atmet **ein** | **Stille.** Herzschlag ausdünnen, Buzz absenken — der Kontrast finanziert den Snap |
| **T+2** | **0.10** | **KOPF-SNAP** (1 Frame), Naht 0.82 → 2.05 | **Der harte Cue.** `triggerFlicker(..., FLICKER_INTENSITY_CHASE)` + einmaliger Stinger auf Maximallautstärke; Dread-Puls auf Vollausschlag. Alles was knallen soll, knallt hier |
| T+3 / T+4 | 0.15 / 0.20 | Körper zieht nach (rechts, dann links) | optional: zweiter, leiserer Schlag — Sub-Bass |
| T+5 … T+17 | 0.25–0.85 | **HOLD**, 12 Ticks Starre | Herzschlag **einsetzen und rampen**; Dread hoch halten. Das Licht bleibt hier bewusst ruhig (Ruhe vor dem Rennen) |
| T+10 / T+11 | 0.50 / 0.55 | Korruptions-Zucker (Kopf, dann Kiefer) | 1-Tick-Mikroflicker (`FLICKER_INTENSITY_AMBIENT`) — reißt die Ruhe genau einmal auf |
| **T+19** | **0.95** | **LOAD** — es spannt sich, Naht 2.35× | **Zweiter harter Cue:** Flicker-Burst + Verfolgungs-Audio einblenden. Das ist der „gleich rennt es"-Moment |
| **T+21** | **1.05** | Release, `isNoticing()` → `false`, Freeze endet | Übergabe an `tickPursuit`: ab hier darf `sprint` laufen, Lautstärke skaliert wie gehabt über die Distanz |

**Für B2 (`wanderer_static_shroud`):** der Shroud sollte während T+5…T+17 **dichter**
werden und beim Load (T+19) kurz aufreißen. Der Anker-Bone dafür ist `fx_shroud_anchor`
(§5.1). `shade:1b` synchronisiert den Shroud bereits mit der Lightmap, d. h. B5s
Flicker-Cues oben ziehen den Shroud automatisch mit — die beiden Systeme müssen sich
nicht kennen.

**Für den `sprint`** (das UserFeedback „beim Anrennen lauter"): der Zyklus ist 12 Ticks
lang, die Fußaufsätze liegen bei **t = 0.00 und t = 0.30 s** (Tick 0 und 6 des Zyklus) —
dort gehören Schritt-Sounds hin, wenn B5 sie ans Rennen koppeln will. Die Naht-Flares
(`glow_seam`, 1200 °/s + 90° Phase) sitzen auf denselben zwei Beats.

---

## 4. (b) Der `sprint`-Zyklus — vier gezielte Falschheiten

Länge **0.55 → 0.60 s (12 Ticks)**. Damit liegt jeder Beat auf einem ganzen Tick *und*
die Molang-Grundfrequenz wird exakt 360/0.6 = **600 °/s** (Harmonische 1200/1800), also
wert- **und** ableitungsstetig über die Loop-Naht. Das alte Paar 654.5/981.8 schloss nur
auf ~1e−4° und 981.8 (= 1.5 Zyklen) kippte an der Naht die Ableitung.

**1. Starre Arme.** Sie schwingen **gar nicht**. Beide sind auf eine feste, asymmetrische
Pose genagelt und hängen an einem 20° nach vorn gekippten Torso — sie schleppen also
gerade nach hinten wie bei einer gezogenen Schaufensterpuppe. Die einzige Bewegung ist
ein Sub-Grad-Rattern rechts (`3 + sin(t·1800)·1.4`) und links **zwei 1-Tick-Spasmen**
(Z 8 → 17 → 8 bei 0.35/0.40).

**2. Gesteppter Torso / Kopf.** `{"pre": …, "post": …}` ist in GeckoLib ein **echter
Step** — der Parser legt den `pre`-Key 0.02 Ticks (= 1 ms) davor, nachgemessen in §6.2.
Der Torso-Yaw springt dadurch in vier diskreten Sprüngen statt zu rollen, der Kopf
schnappt zweimal pro Zyklus für **genau einen Tick** zur Seite. Das sind die
„ruckelnden Frame-Versätze" der Zensus-Zeile. Dieselbe Sprache trägt die `head_shard`:
die lose Gesichtsplatte gleitet nicht, sie **teleportiert**, einmal pro Schritt.

**3. Kaputter Gang.** Die Beine sind **nicht** kontralateral: das rechte Bein hat sein
Vorwärts-Maximum bei 0.00 s, das linke bei 0.40 s eines 0.60-s-Zyklus — **240° auseinander,
nicht 180°**. Dazu ungleiche Amplituden (rechts 62°/−44° = 106° Weg, links 46°/−34° =
80°) und rechts ein **ausgelassener Frame** am hinteren Ende des Schritts (0.30 s und
0.35 s tragen denselben Wert), der danach auf steilerer Flanke aufholt. Der Root-Bob
hinkt mit: hoher Hüpfer auf der starken Seite (1.35 px), kaum vorhandener auf der
schwachen (0.60 px).

**4. Weltparalleler Kopf.** `head.x = −20` hebt `body.x = +20` exakt auf: der Schädel
steht **waagerecht und auf dich gerichtet**, während der Körper nach vorn geworfen ist.
Ausnahme ist die 2-Tick-Torso-Hitze (0.30–0.40 s, Body auf 26°), wo der Kopf *nicht*
kompensiert und um 6° absackt. Keinerlei `catmullrom` im ganzen Zyklus — alles linear,
damit nichts weich wirkt.

---

## 5. (c) Painter-Umzug und (d) Shroud-Anker

### 5.1 (d) `fx_shroud_anchor`

```json
{ "name": "fx_shroud_anchor", "parent": "root", "pivot": [0, 15.36, 0] }
```

- **Welcher Bone: `fx_shroud_anchor`**, würfellos (malt nichts, kostet nichts).
- **Pivot 15.36 px** ist aus B2s echtem Offset nachgerechnet (§1.3), nicht geschätzt —
  der Locator sitzt exakt dort, wo der Emitter heute schon sitzt.
- **Parent `root`, bewusst nicht `body`:** der Shroud ist eine Dunstsäule um das Ding
  herum; würde er die 20°-Torso-Neigung des `sprint` erben, kippte die ganze Säule.
- **Kein Animationskanal, in keinem Clip** — ebenfalls bewusst (Polish-Pass 1, §5.3).
  Ein bone-gebundener Emitter unterscheidet sich damit von der heutigen Welt-Raum-Zeile
  um **exakt die Eigenbewegung von `root` und sonst nichts**: 0 px in `idle` und im
  `notice`-Hold, ≤ 1.35 px (0.084 Blöcke) Bob im `sprint`, dazu das `glitch_blink`-Stottern
  und das Absacken im `death` — genau der Drift, den ein Shroud erben *soll*.

Für B2 heißt das: Umbinden ist ein bewusst *langweiliger* Wechsel. Volle Spec in
`docs/uv/backrooms_wanderer.md` §FX.

### 5.2 Polish-Fund: `pacedPlayer()` (Bug B-5)

Der Freeze preemptet `PaceGoal`; dessen `stop()` nullt `pacedPlayer`. Da B5s
`isHunting()` genau an diesem Accessor hängt (§1.4), hätte der Dread-Kanal 21 Ticks lang
„nicht gejagt" gesehen — also `endPursuit()` mit seinem verklingenden Entwarnungs-Thud
**auf dem Höhepunkt des Starrens**, und danach den Herzschlag bei null neu gestartet.
Exakt verkehrt herum.

Gelöst vollständig innerhalb meiner Datei: `pacedPlayer()` liefert während des Freeze
das Stare-Target. Die interne Stalk-Burst-Logik liest weiterhin das **Feld** — ein
eingefrorener Wanderer darf nicht beschleunigen.

### 5.3 (c) Der Umzug

`scripts/skin_gen/backrooms_wanderer.py` → **`scripts/geckolib_gen/mobs/backrooms_wanderer.py`**
(per `git mv`, danach `git restore --staged` — nichts ist gestaged, der Integrator
committet). Zensus §7 Falle **F-11** („Painter-Ausreißer") ist damit für diese Datei
erledigt; `scripts/skin_gen/` bleibt bestehen (5 fremde Dateien liegen weiterhin dort:
`boss_paint.py`, `eclipsed_player_v2.py`, `ferryman_v2.py`, `gazer_v2.py`, `sunmote_v2.py`).

Angepasst im Skript:

| Stelle | vorher | nachher |
|---|---|---|
| `ROOT` | `parents[2]` | `parents[3]` (eine Ebene tiefer verschachtelt) |
| Import-Pfad | `sys.path.insert(0, ROOT / "scripts/geckolib_gen/mobs")` | `sys.path.insert(0, Path(__file__).resolve().parent)` |

Der Import wurde dadurch nebenbei **robuster**: `glitched_husk` liegt jetzt im
Schwesterverzeichnis, der Import hängt nicht mehr daran, dass `ROOT` korrekt aufgelöst hat.

Der Dateiname bleibt `backrooms_wanderer` (nicht `glitched_wanderer`), weil der Treiber
die Backrooms-**Kunstbegleitung** ist, nicht der Skin-Painter eines einzelnen Mobs: er
schreibt auch `textures/gui/backrooms_scare.png`, das zu keinem Geo-Triple gehört.

**Alte Pfad-Referenzen (per `rg` gefunden, vollständige Liste):**

| Datei | Zeile(n) | Art | Aktion |
|---|---|---|---|
| `scripts/geckolib_gen/mobs/glitched_husk.py` | 59 | **Code**, aber nur Docstring-Verweis | **Integrator/Husk-Team**: nicht meine Datei. Rein kosmetisch, kein Import |
| `docs/plans_v3/session_0730/MOB_ITEM_CENSUS.md` | 26, 225, 380 | Zensus (Bestandszählung, Zeile MB5, Falle F-11) | **Integrator**: Ausreißer-Zählung 2 → 1, Zeile MB5 + F-11 nachziehen |
| `docs/plans_v3/plans_v5/fxteams/MOB-GLITCH.md` | 18 | historisches Planungsdokument | belassen (Historie) |
| `docs/plans_v3/plans_v5/v7/fxteams2/REPASS-MOB.md` | 68, 135, 143 | historischer Report | belassen (Historie) |

**Keine ausführbare Referenz betroffen** — geprüft: kein Python-Import, kein Shell-,
Gradle-, Makefile- oder CI-Aufruf nennt den Pfad, und es gibt keinen Sammel-Treiber, der
über die Painter iteriert. Der Umzug kann nichts brechen.

---

## 6. Validierung

### 6.1 Pflicht-Checks (wörtlich)

```
$ python3 scripts/geckolib_gen/validate_geo.py \
      src/main/resources/assets/eclipse/geo/entity/glitched_wanderer.geo.json \
      src/main/resources/assets/eclipse/animations/entity/glitched_wanderer.animation.json

=== GEO  src/main/resources/assets/eclipse/geo/entity/glitched_wanderer.geo.json
    identifier geometry.glitched_wanderer  canvas 64x64  12 bones  11 cubes
    └─ root  (pivot 0,0,0)
       ├─ body  (pivot 0,12,0 · 1 cube)
       │  ├─ shard_torso  (pivot -4,20,0 · 1 cube)
       │  ├─ glow_seam  (pivot 0,18,0 · 2 cubes · emissive)
       │  ├─ head  (pivot 0,24,0 · 1 cube · head-tracked)
       │  │  ├─ head_shard  (pivot 0,28,0 · 1 cube)
       │  │  └─ jaw_shard  (pivot 0,24,-3 · 1 cube)
       │  ├─ arm_right  (pivot -4,22,0 · 1 cube)
       │  └─ arm_left  (pivot 4,21,0 · 1 cube)
       ├─ leg_right  (pivot -2,12,0 · 1 cube)
       ├─ leg_left  (pivot 2,12,0 · 1 cube)
       └─ fx_shroud_anchor  (pivot 0,15.36,0)
  -> PASS (0 error(s), 0 warning(s))

=== ANIM src/main/resources/assets/eclipse/animations/entity/glitched_wanderer.animation.json
    'animation.glitched_wanderer.idle': loop=True length=5.0 bones=8 keyframes=29 last_key=5.0s
    'animation.glitched_wanderer.walk': loop=True length=1.6 bones=9 keyframes=30 last_key=1.6s
    'animation.glitched_wanderer.attack': loop=False length=0.5 bones=5 keyframes=21 last_key=0.5s
    'animation.glitched_wanderer.glitch_blink': loop=False length=0.4 bones=3 keyframes=22 last_key=0.4s
    'animation.glitched_wanderer.death': loop='hold_on_last_frame' length=1.5 bones=11 keyframes=40 last_key=1.5s
    'animation.glitched_wanderer.sprint': loop=True length=0.6 bones=11 keyframes=54 last_key=0.6s
    'animation.glitched_wanderer.notice': loop=False length=1.05 bones=11 keyframes=76 last_key=1.05s
  -> PASS (0 error(s), 0 warning(s))

============================================================
validate_geo: 2/2 file(s) passed — all good
```

**Painter-Determinismus** — zweimal laufen lassen, md5 aller 7 Ausgaben:

```
$ python3 scripts/geckolib_gen/mobs/backrooms_wanderer.py   # Lauf 1
$ md5sum <7 Ausgaben> > /tmp/mb5_run1.md5
$ python3 scripts/geckolib_gen/mobs/backrooms_wanderer.py   # Lauf 2
$ md5sum <7 Ausgaben> > /tmp/mb5_run2.md5
$ diff /tmp/mb5_run1.md5 /tmp/mb5_run2.md5 && echo IDENTICAL
IDENTICAL

4af2c8ae0979010cbdea6dd0a97e8d4d  geo/entity/glitched_wanderer.geo.json
00ab43a4f4fe8c9cfe86584ed9811320  animations/entity/glitched_wanderer.animation.json
d86d9f771ffe4d0fd8ab06964290469c  textures/entity/glitched_wanderer.png
adc7948eb93a52715a2d258f6837acbc  textures/entity/glitched_wanderer_alt.png
80cd6347264ff3dee09a9e791d4e7998  textures/entity/glitched_wanderer_glowmask.png
8800dc2b5e54a19af605cb0a50c62a0f  textures/entity/glitched_wanderer_alt_glowmask.png
9739d21ff1b96304509d7131d8b4a3ac  textures/gui/backrooms_scare.png
```

**Java:**

```
$ ./gradlew compileJava
> Task :compileJava
BUILD SUCCESSFUL in 1s
```

(Gegengeprüft, dass wirklich neu übersetzt wurde: `GlitchedWandererEntity$NoticeFreezeGoal.class`
ist im `build/classes`-Baum vorhanden und frisch datiert.)

### 6.2 Gegenprobe mit GeckoLibs EIGENEM Parser

Statt die Keyframe-Mathematik von Hand zu behaupten, habe ich den Clip durch
GeckoLib 4.9.2s eigenen `BakedAnimationsAdapter` geparst und mit GeckoLibs eigenem
Sampler (`AnimationController.getAnimationPointAtTick` + `EasingType.apply`)
abgetastet (Wegwerf-Harness in `/tmp/mb5/`, nicht committet).

**Längen ganzzahlig in Ticks** (das Tick-Gesetz, §3.1):

```
animation.glitched_wanderer.notice   len= 21.00t (1.050s)  bones=11
animation.glitched_wanderer.sprint   len= 12.00t (0.600s)  bones=11
```

**Der Kopf-Snap** (`notice` / `head.rotation`, Grad, GeckoLibs X/Y-Flip rückgängig):

```
   t(s)   tick        X        Y        Z
   0.000   0.00    0.0000   0.0000   0.0000
   0.050   1.00    4.0000   9.0000  -3.0000   <-- Anticipation: 9 Grad WEG
   0.060   1.20    4.0000   9.0000  -3.0000
   0.090   1.80    4.0000   9.0000  -3.0000   <-- ein ganzer Tick Stillstand
   0.100   2.00  -14.0000  -3.0000   7.0000   <-- SNAP, null Interpolation
   0.110   2.20  -14.0000  -3.0000   7.0000
   ...
   0.300   6.00  -14.0000  -3.0000   7.0000   <-- Starre
```

Die vom Parser gemeldeten Keyframe-Längen enthalten `0.020`-Einträge — das ist GeckoLibs
1-ms-`pre`-Key: `pre`/`post` ist im Parser ein **echter Step**, nicht nur „sehr schnell".

**Landung auf exaktem Neutral** (widerlegt jeden Pop bei der Layer-Übergabe, §3.2):

```
   t(s)   tick    body.rotation X/Y/Z        glow_seam.scale X/Y/Z
   0.950  19.00   12.0000  2.0000 -1.0000    2.3500 1.2000 2.3500
   1.000  20.00    6.0000  1.0000 -0.5000    1.6750 1.1000 1.6750
   1.050  21.00    0.0000  0.0000 -0.0000    1.0000 1.0000 1.0000
```

**`sprint`-Loop-Naht geschlossen:**

```
   t(s)   tick    leg_right.rotation X    root.position X/Y/Z
   0.550  11.00   42.6667                 0.0000 0.0000 0.0000
   0.600  12.00   62.0000                 0.0000 0.0000 0.0000
```

`leg_right` bei Tick 12.00 = 62.0000 = exakt der Startwert bei t = 0; `root` ebenso auf
(0,0,0). Kein Sprung an der Naht.

*(Molang-Kanäle lassen sich in der Harness nicht sinnvoll auswerten — dort fehlt die
`query.anim_time`-Umgebung. Deren Loop-/Endstetigkeit ist stattdessen rechnerisch
sichergestellt: alle Frequenzen sind so gewählt, dass f·Länge ein Vielfaches von 180°
ist, siehe §3.1 und §4.)*

### 6.3 Kein In-Game-Client

Bewusst nicht gestartet: die VM rendert auf llvmpipe (Sekunden pro Frame, AGENTS.md), und
ein 1-Frame-Snap ist damit prinzipiell nicht einfangbar — ein Video hätte weniger
ausgesagt als die Sampler-Tabellen oben, die den Snap Tick für Tick zeigen. Test-Rezept
für einen echten Client: §7.

---

## 7. Test-Rezept (in-game)

```bash
cd /workspace/ProjectEclipse
./gradlew runClient          # llvmpipe: 20-40 s pro Aktion einplanen
```

1. **Die Kette.** In einen Backrooms-Flur, `/summon eclipse:glitched_wanderer ~ ~ ~15`,
   dann **wegschauen**. Erwartung: es schleicht näher (Stalk-Burst, Portal-Static).
   Umdrehen, sobald es ~12 Blöcke entfernt ist. Erwartung in dieser Reihenfolge:
   es hält an → Kopf **schnappt** (ein Frame) → Körper zieht einen Tick später nach →
   **eine gute Sekunde absolute Starre**, in der es dich anschaut → kurzes Spannen →
   weiter. Wieder wegschauen → `sprint`.
2. **Der Freeze muss echt sein.** Während der Starre darf es sich **keinen Block weit**
   bewegen — kein Gleiten, kein Drehen des Körpers. Nur der Kopf folgt dir.
   Gegenprobe: `/data get entity @e[type=eclipse:glitched_wanderer,limit=1] Motion`
   während des Starrens → x und z müssen 0 sein, y darf fallen.
3. **Kein Doppel-Trigger.** Weiter anstarren: die `notice` darf **nicht** erneut feuern.
   Erst nach ≥ 10 s vollständiger Trennung (> 24 Blöcke weg) ist sie wieder scharf.
4. **Kein Blink-Klau (B-4).** Mehrfach mit Target in Nahkampfreichweite auslösen. Die
   `notice` darf nie mitten im Starren von einem Stutter-Blink abgeschnitten werden.
5. **Knockback (B-7).** Während des Starrens einmal zuschlagen: es muss **zurückfliegen**
   (aber nicht loslaufen).
6. **Regression:** `attack`, `glitch_blink`, `death`, `idle`, `walk` einmal durchlaufen
   lassen. `idle` und `walk` sind unverändert; `attack`/`glitch_blink`/`death` erben
   diese Runde die Husk-Politur (§8.1) — hier nur prüfen, dass nichts *kaputt* ist.

Offline-Äquivalent (ohne Client, Sekunden):

```bash
python3 scripts/geckolib_gen/mobs/backrooms_wanderer.py
python3 scripts/geckolib_gen/validate_geo.py \
    src/main/resources/assets/eclipse/geo/entity/glitched_wanderer.geo.json \
    src/main/resources/assets/eclipse/animations/entity/glitched_wanderer.animation.json
```

---

## 8. Geänderte Dateien

| Datei | Änderung |
|---|---|
| `scripts/geckolib_gen/mobs/backrooms_wanderer.py` | **verschoben** aus `scripts/skin_gen/` (Auftrag c) + `SPRINT`/`NOTICE` neu, `FX_ANCHOR_BONE` ergänzt. 494 → 696 Zeilen |
| `scripts/skin_gen/backrooms_wanderer.py` | **gelöscht** (Zielort siehe oben) |
| `src/main/resources/assets/eclipse/geo/entity/glitched_wanderer.geo.json` | +9 Zeilen — nur der `fx_shroud_anchor`-Locator (GENERIERT) |
| `src/main/resources/assets/eclipse/animations/entity/glitched_wanderer.animation.json` | `sprint` + `notice` neu (GENERIERT); `attack`/`death`/`glitch_blink` sind Fremd-Delta, siehe §8.1 |
| `src/main/java/dev/projecteclipse/eclipse/backrooms/GlitchedWandererEntity.java` | +202/−15 — `NoticeFreezeGoal`, Stare-Edge-Trigger, `isNoticing()`, Blink-Guard, `pacedPlayer()`-Fallback |
| `docs/uv/backrooms_wanderer.md` | **neu** — UV-Tabelle des warped Rigs + `fx_shroud_anchor`-Spec für B2 |
| `docs/plans_v3/session_0730/MB5_WANDERER_REPORT.md` | dieser Report |

Texturen: **byte-identisch** zu HEAD (tauchen nicht im `git status` auf) — die
Geo-Warps blieben unverändert, der neue Locator hat keine Würfel.

**Kein** Lang-Key entstanden (keine neuen benutzersichtbaren Strings) →
`docs/plans_v3/langdrop/MB5-WANDERER.json` **entfällt bewusst**, wie bei allen
M-A-Teams.

### 8.1 ⚠ Fremd-Delta im generierten Anim-File — für den Integrator

Der Painter leitet `attack`/`glitch_blink`/`death` aus `glitched_husk.animation.json`
ab. Ein Parallel-Team hat den Husk **während dieser Session** poliert
(`glitched_husk.animation.json` +258/−13, `glitch_lib.py` +89). Mein Painter-Rerun hat
diese Politur damit korrekt in den Wanderer nachgezogen — der Diff meines Anim-Files
enthält also drei Clips, die **nicht von mir stammen**.

Nachgewiesen, nicht vermutet:

```
death         wanderer == CURRENT husk source ? True
glitch_blink  wanderer == CURRENT husk source ? True
attack        wanderer == CURRENT husk source + MB5 anticipation keys ? True
```

`idle` und `walk` sind unverändert (bespoke, nicht husk-abgeleitet).

**Handlungsanweisung:** landet die Husk-Politur nach meinem Patch oder wird sie noch
einmal angefasst, muss `python3 scripts/geckolib_gen/mobs/backrooms_wanderer.py`
**erneut** laufen, sonst driften die drei geerbten Clips auseinander. Das ist keine
Regression meiner Änderung, sondern die eingebaute Kopplung des Treibers.

---

## 9. Koordinations-Snippets

### 9.1 An B5 (Dread-System) — Aktion optional, Schnittstelle steht

Neu und synchronisiert: `GlitchedWandererEntity.isNoticing()`. Cue-Tabelle in §3.6 —
die zwei Cues, die zählen, sind **T+2** (Kopf-Snap: harter Flicker + lautester Stinger)
und **T+19** (Load: Flicker-Burst + Verfolgungs-Audio einblenden). Dazwischen 12 Ticks,
in denen der Herzschlag rampen kann. Das adressiert das UserFeedback („lauter beim
Anrennen, Licht flackert") an dem Punkt, an dem es am meisten trägt.

Bereits für dich erledigt: `pacedPlayer()` bleibt während des Freeze belegt (§5.2), dein
`isHunting()` bricht also **nicht** mitten im Beat ab. Wenn du das Verhalten je änderst,
lies bitte vorher den Javadoc-Block an dem Accessor.

Fußaufsätze des `sprint` für Schritt-Sounds: **t = 0.00 s und t = 0.30 s** eines
0.60-s-Zyklus.

### 9.2 An B2 (`wanderer_static_shroud`) — Aktion optional

Anker-Bone steht: **`fx_shroud_anchor`**, Pivot `[0, 15.36, 0]`, Parent `root`, in der
Geo. Er reproduziert deinen heutigen `eye + (0,−0.7,0)`-Anker in Ruhe exakt und trägt
sonst nur `root`s Eigenbewegung (≤ 0.084 Blöcke). Umbinden ist damit ein bewusst
langweiliger Wechsel. Volle Spec: `docs/uv/backrooms_wanderer.md` §FX.
Ich habe **nichts** unter `tools/photon/**` oder `assets/eclipse/fx/**` angefasst.

### 9.3 An den Integrator

- Nichts gestaged, nichts committet (Anweisung).
- **Umzug:** `scripts/skin_gen/backrooms_wanderer.py` → `scripts/geckolib_gen/mobs/`.
  Zensus nachziehen: §Bestandszählung „2 Ausreißer" → 1, Zeile MB5, Falle F-11 (§5.3).
- **Fremd-Delta** im generierten Anim-File: §8.1 lesen, Reihenfolge mit dem Husk-Team
  abstimmen.
- Ein Docstring-Verweis in `scripts/geckolib_gen/mobs/glitched_husk.py:59` zeigt noch auf
  den alten Pfad — fremde Datei, deshalb nicht von mir angefasst.
- Neue öffentliche API auf `GlitchedWandererEntity`: `isNoticing()`, `NOTICE_TICKS`;
  geändertes Verhalten von `pacedPlayer()` (§5.2).

---

## 10. Offene Punkte (bewusst nicht gemacht)

1. **Kein Sound-Cue aus MB5 selbst.** Der Snap schreit nach einem eigenen Stinger, aber
   `sounds.json` und die Registry gehören mir nicht. Spec liegt in §3.6, Umsetzung bei B5.
2. **Knockback-Immunität während des Freeze war ein Bug (B-7) und ist behoben** — der
   Mob *bewegt* sich jedoch weiterhin nicht aus eigener Kraft. Wer den Freeze für
   anti-cheese-relevant hält, müsste ihn abbrechbar machen; ich halte 1.05 s für zu kurz,
   um das zu rechtfertigen (§3.3).
3. **Die Stare-Edge braucht echten Sichtkontakt** (~3.7°-Kegel auf 12 Blöcken, Enderman-
   Regel). Ein Spieler, der nur mit dem Augenwinkel hinschaut, löst den Beat nicht aus.
   Das ist Absicht, aber falls Playtests es als „triggert zu selten" melden, ist der
   Hebel `isLookedAtBy` in `GlitchedMonster` — **fremde FROZEN-Datei**, also ein eigenes
   Ticket.
4. **`fx_shroud_anchor` ist noch unbenutzt.** Er wird erst wirksam, wenn B2 die `LoopRow`
   umbindet; bis dahin kostet er ein Bone-Objekt und sonst nichts.
5. **Der Shroud verrät den Freeze nicht.** Schöner wäre, wenn der Shroud während des
   Starrens sichtbar dichter würde — das ist ein FX-Parameter in `tools/photon/mobs_fx.py`
   und gehört B2 (Vorschlag in §3.6).
