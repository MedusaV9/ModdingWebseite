# F-103 Team A — FX Respawn Hygiene Report ("Duplicate fx runtime object id"-Sturm)

**Mission:** die Photon-Client-WARN-Flut `[Photon/]: Duplicate fx runtime object id <uuid>
is replaced` ausrotten (1296 Zeilen in `/tmp/client_f102.log`, 10 unique UUIDs, Bursts
22:49:39 / 23:00:18).

**Verdikt:** Es war KEIN Respawn-pro-Tick-Loop und KEIN `allowMulti`-Fehler. Die
Root-Cause ist eine **Vergiftung des geteilten `FXHelper.getFX`-Asset-Caches** durch
`FX.createInternalRuntime()` in den beiden Channel-A-Tunern (`StormNearfieldFx.Tuner`,
`StormPhotonFx.Tuner`). Beide sind gefixt; alle anderen verdächtigen Pfade
(StructureFlightFx-Rim-Lightning, Altar-Aura-WINDOWED-Loops) sind durch die
UUID-Beweislage exoneriert und im Phase-4-Sweep verifiziert.

---

## 1. Beweisführung (warum genau diese Root-Cause)

### 1.1 Die 10 UUIDs sind Asset-Objekt-IDs der drei Nearfield-Loops

`rg "Duplicate fx runtime" /tmp/client_f102.log | rg -o "id [0-9a-f-]+" | sort | uniq -c`:

| warns | UUID | Objekt (aus dem kompilierten `.fx`) | Asset |
| --- | --- | --- | --- |
| 222 | `59a3db05…` / `37e7e8ce…` | `scud_shreds` / `scud_grit` (particle_emitter) | `storm_ground_scud.fx` |
| 222 | `3b540c46…` / `85c60212…` | `updraft_motes` / `updraft_glints` | `storm_updraft_motes.fx` |
| 135 | `47592327…` / `262f26a3…` / `a7ce4ea9…` | `wisp_racers` / `wisp_veils` / `rain_curtain` | `storm_nearfield_wisps.fx` |
| 1 | `092d8199…` / `38c51be4…` / `bc09bc35…` | die drei `*_root`-Empties | (je Asset) |

Alle 10 UUIDs gehören zu den DREI Assets, die `StormNearfieldFx` fährt. Die von
`tools/photon/fxlib.py` deterministisch (uuid5 über den Hierarchie-Pfad) vergebenen
Objekt-IDs sind **innerhalb** jedes Assets eindeutig (per Scan verifiziert) — die
Kollision entsteht also erst zur Laufzeit. Anmerkung: die Missions-Annahme
„PhotonBridge leitet Runtime-UUIDs aus fx-Id + Anker ab" stimmt so nicht —
PhotonBridge vergibt gar keine UUIDs; die kollidierenden IDs sind die **im Asset
gespeicherten Objekt-Transform-IDs**.

### 1.2 Wo Photon die WARN loggt

`FXRuntime.addSceneObjectInternal` (photon 2.1.5, javap-verifiziert): pro `FXRuntime`
(= Szene) existiert eine eigene `LinkedHashMap<UUID, IFXObject> objects`; die WARN
feuert genau dann, wenn `objects.put(o.id(), o)` einen **anderen** Objekt-Instanz-Wert
unter derselben UUID ersetzt. Zwei Runtimes können sich also NIE gegenseitig warnen —
es müssen zwei verschiedene Instanzen mit derselben Asset-UUID in DIESELBE Szene
gelangen.

### 1.3 Die Vergiftungs-Kette (alle Glieder javap-verifiziert)

1. **`Tuner.attach` (alt)** rief `FX.createInternalRuntime()` auf dem **gecachten**
   `FXHelper.getFX(loc)`-Asset auf. `createInternalRuntime()` baut ein `FXRuntime`
   direkt auf der geteilten `FXData` — **ohne Kopie**. Der Konstruktor ruft auf jedem
   Template-Objekt `setScene(runtime)` + `awake()`: `Transform.awake()` löst die
   persistierte `_parentId` auf und baut **live Parent/Child-Links** zwischen den
   Template-Objekten; der Template-Root wird unter den Runtime-Root geparentet. Ab
   jetzt hat der Cache-Inhalt eine lebende Szene + lebende Transform-Hierarchie —
   genau der Zustand, den ein frisch von Platte geladenes Asset NICHT hat.
2. **Jeder normale Spawn** (`BlockEffectExecutor.start()` → `FX.createRuntime()` →
   `FXData.copy(false)`) kopiert jedes Objekt via `FXObject.copy(false)`:
   `shallowCopy()` + `setName` + `copyTransformFrom(template)`. Und
   `Transform.copyTransformFrom(other, true, true)` kopiert neben Pos/Rot/Scale auch
   **`parent(other.parent())`** — den LIVE-Parent! Auf einem unvergifteten Cache ist
   `other.parent() == null` → No-Op. Auf dem vergifteten Cache hängt sich die frische
   Kopie damit **in die Transform-Hierarchie des Templates**:
   `Transform.addChildInternal` ruft `copy.setScene(templateScene)` → die Kopie landet
   in der Objekt-Map des alten **internen** Tuner-Runtimes. Danach stempelt
   `copyTransformFrom` noch `_setInternalID(other.id())` — die Kopie trägt die
   Asset-UUID.
3. **Akkumulation:** die Kopien werden zwar in `initRuntime` ihrer eigenen Runtime
   wieder umgesetzt (`setScene(newRuntime)` entfernt sie aus der internen Map), aber
   ihr Transform bleibt **Kind des Template-Roots** (Re-Parenting passiert nie, weil
   `initRuntime` Schritt 3 nur parent-lose Objekte umhängt). Jeder Respawn eines
   Nearfield-Loops hinterlässt so ein Stale-Child pro Emitter am Template-Root.
4. **Der Burst:** beim NÄCHSTEN `Tuner.attach` (Fenster-Re-Open, z. B. Teleport in die
   Altar-Zone → Release + Re-Ensure) zog `createInternalRuntime()` den Template-Root in
   eine neue interne Szene um — `ISceneObject.setScene` rekursiert über **alle**
   Transform-Children, also auch über sämtliche akkumulierten Kopien: jede trägt die
   Asset-UUID ihres Emitters → `objects.put` ersetzt der Reihe nach → **eine WARN pro
   akkumulierter Kopie pro Emitter**, alle im selben Frame geflusht (das
   llvmpipe-Bunching aus der Beweislage).

Die Zahlen passen exakt: `3·135 (wisps) + 2·222 (scud) + 2·222 (updraft) = 1293 =
592 + 701` (die beiden Bursts) `+ 3` Root-Warns (je Asset genau EINMAL, beim ersten
vergifteten Spawn, wenn die Root-Kopie den Template-Root in der internen Map ersetzt —
danach ist der Map-Slot leer, weil die Kopie beim Umzug in ihre eigene Runtime per
`removeSceneObjectInternal` unter derselben UUID entfernt wird).

**Warum Burst 1 „im StructureFlightFx-Fenster" lag:** Koinzidenz über das
Nearfield-Fenster — beide Bursts sind Attach-Flushes des Nearfield-Tuners (Fenster-
Re-Open in Sturmnähe während des Struktur-Tests bzw. beim Teleport). Kein einziges
Lightning-/Altar-Asset-UUID taucht im Log auf.

### 1.4 Nebenschaden derselben Root-Cause (mit-gefixt)

Der Attach-Flush riss die Emitter **live spielender** Loop-Runtimes aus deren
Objekt-Map (`setScene`-Umzug in die neue interne Szene) — Loops starben dadurch
vorzeitig und wurden vom (korrekt gebauten) `ensureLoop`-Keepalive respawnt: das ist
der Respawn-Churn, der die 135/222 Kopien akkumuliert hat. Quelle und Verstärker sind
also dieselbe Vergiftung; mit dem Fix verschwindet beides.

---

## 2. Fix

**Prinzip:** Der Channel-A-Tuner braucht überhaupt keine Runtime — er braucht nur die
`EmissionSetting`s der **geteilten** `ParticleConfig`s (genau die teilen sich alle
gespawnten Runtimes per `ParticleEmitter.shallowCopy()`). Die Emitter werden jetzt
read-only über die flache Objektliste des Assets aufgelöst:

```java
// vorher (vergiftet den Cache):
Object cachedRt   = createInternalRuntime.invoke(getFxCached.invoke(null, id));
Object pristineRt = createInternalRuntime.invoke(getFxIsolated.invoke(null, id, false));
emissions[i] = emissionOf(cachedRt, name);   // FXRuntime.findObject(name)

// nachher (kein FXRuntime, kein setScene, keine Hierarchie-Mutation):
Object cachedFx   = getFxCached.invoke(null, id);
Object pristineFx = getFxIsolated.invoke(null, id, false);
emissions[i] = emissionOf(cachedFx, name);   // FX.getFxData().objects() + Name-Match
```

`FX.getFxData()`, `FXData.objects()` und `IFXObject.getName()` sind public
(javap-verifiziert, photon 2.1.5) — die Reflection bleibt fail-soft wie gehabt (erste
Überraschung → Tuner-Disable, Loops behalten Autoren-Raten). Semantik-Parität:
Name-Match auf der flachen Liste = `findObject`-Verhalten; die Pristine-Snapshots
kommen weiter aus dem ISOLIERTEN `getFX(loc, false)`-Load (frisch von Platte, kein
Cache-Write — javap-verifiziert). UUID5-Determinismus der Assets bleibt unangetastet
(wir vergeben/ändern keine IDs).

**Neue Tuner-Regel (als Kommentar-Law in beiden Klassen verewigt):** NIEMALS
`FX.createInternalRuntime()` auf dem geteilten `FXHelper`-Cache — ein internes Runtime
`setScene()`t + re-parentet die gecachten Templates und macht aus jedem späteren
`createRuntime()`-Spawn einen Duplicate-Warn-Kandidaten.

### Geänderte Dateien

- `src/main/java/dev/projecteclipse/eclipse/stormfx/StormNearfieldFx.java`
  (Tuner: Runtime-lose Emitter-Auflösung + Hygiene-Law-Doku)
- `src/main/java/dev/projecteclipse/eclipse/stormfx/StormPhotonFx.java`
  (identischer Fix im Ursprungs-Tuner desselben Musters)

**Ownership-Anmerkung:** die Root-Cause liegt NICHT in den gelisteten
Kandidaten-Dateien, sondern in `stormfx/*` — von keinem anderen Team (B: `ritual/*`,
`CreditsFinaleFxRows`, `credits5_fx.py`; C: FX-Generatoren) beansprucht und von der
Verbotsliste nicht erfasst. Da die Mission „Quelle fixen, nicht Symptom" verlangt und
ohne diesen Fix 0-neue-Warnungen unerreichbar ist, wurden beide stormfx-Tuner direkt
gefixt und die Entscheidung hier dokumentiert. `veilfx/PhotonBridge.java`,
`StructureFlightFx.java`, `glitchzone/*`, `client/drama/*` und alle FxRows-Klassen
brauchten KEINE Änderung.

---

## 3. Phase-4-Sweep (alle anderen Spawn-Pfade)

Systematisch geprüft (`rg "PhotonBridge\.spawn|spawnLoop|ensureLoop|ensureAttachedFx|sendFxEvent"`):

- **`FX.createInternalRuntime`-Nutzer:** exakt die beiden gefixten Tuner — sonst
  niemand im Repo.
- **`StructureFlightFx` (Rim-Lightning + Center-Crack):** exoneriert. Strikes feuern
  auf `LIGHTNING_INTERVAL_TICKS`-Kadenz mit golden-angle-Sweep → **jeder Strike hat
  einen eigenen Anker**; kein Nearfield-/Lightning-Asset-UUID im Log.
- **Altar-Aura/Corona (`client/drama/AltarAuraIdle`, `AltarCoronaIdle`):** sauber —
  laufen über `PhotonFxRegistry.ensureLoop` (Handle-Liveness + Grace, Respawn nur nach
  echtem Tod, Release beim Fensterschluss). Keine Altar-Asset-UUIDs im Log.
- **Crown-Halo (`StormFxClient`), Portal-Loops (`RiftFx`), Storm-Suite
  (`StormPhotonFx.ensureLoops`), `ensureAttachedFx`-Nutzer:** alle mit
  `LoopHandle.alive()`-Check vor jedem Respawn — kein blinder Tick-Respawn.
- **`PhotonBridge.SPAWN_GRACE_TICKS` (100 t)** deckt weiterhin die llvmpipe-Catch-up-
  Falle ab (frisch gespawnte Runtime meldet `isAlive()==false` bis zum ersten
  Render-Tick); unverändert gelassen.
- **Wiederholte Einzel-Events am selben Anker** (z. B. `storm_vein_bolt`,
  `OFFERING_SWALLOW_SOUL`): nutzen explizit `allowMulti` — gewollt und warn-frei
  (jede Runtime hat ihre eigene Objekt-Map; ohne Cache-Vergiftung kollidiert nichts).

---

## 4. Gate-Ergebnisse

- `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` →
  **BUILD SUCCESSFUL** (2 actionable tasks).
- Keine Server/Clients gestartet oder gestoppt, kein RCON (Live-Acceptance beim
  Main-Agent, §5).

---

## 5. RCON-Verifikationsskript für den Main-Agent

Reproduziert exakt die beiden Log-Bursts aus der Beweislage. Vorbedingung: Client mit
Photon läuft, `/tmp`-Clientlog wird getailt.

```bash
# 0) Referenzzähler VOR dem Test (Clientlog-Pfad ggf. anpassen):
rg -c "Duplicate fx runtime" run/logs/latest.log   # (oder das aktuelle Client-Log)

# 1) Sturm + Nearfield-Fenster öffnen (Tuner.attach #1) — Spieler in Sturmnähe:
#    per RCON:
#      dev storm spawn sphere ~ ~ ~ 24        # (bzw. der Session-übliche /dev-Sturmspawn)
#      tp @p <sturm-rand-x> <y> <sturm-rand-z> # Shell-Distanz < 250 → Loops attachen
#    ~30 s stehen lassen (Loops laufen, Tuner tuned).

# 2) Burst-1-Repro (Struktur-Spawn-Test wie F-102):
#      dev structure spawn <site>              # das StructureFlightFx-Fenster
#    Erwartung: KEINE neue "Duplicate fx runtime"-Zeile.

# 3) Burst-2-Repro (Fenster-Re-Open per Teleport — der härteste Fall):
#      tp @p 10000 108 10000                   # raus (Release: Shell-Distanz > 270)
#      (5 s warten)
#      tp @p 0.5 108 12.5                      # zurück in die Altar-/Spawn-Zone
#    3–4× wiederholen (jeder Zyklus war vorher ein Attach-Flush).

# 4) Akzeptanz:
rg "Duplicate fx runtime" <clientlog> | wc -l
#    → Zähler UNVERÄNDERT gegenüber Schritt 0 (0 neue Warnungen).
#    Zusatzcheck Tuner intakt: beim Rein-/Rauslaufen am 150–250-Band ändern die
#    Nearfield-Loops sichtbar ihre Dichte (Channel A lebt), und `dev photon status`
#    zeigt stabile Executor-Zahlen ohne Respawn-Churn.
```

**Log-Erwartung:** 0 neue `Duplicate fx runtime object id`-Warnungen bei
Struktur-Spawn UND Altar-Teleport; keine `Photon nearfield live-tuner disabled`- /
`Photon storm live-tuner disabled`-DEBUG-Zeile (Reflection-Pfad intakt).

---

## 6. Restrisiken

- **Reflection-Oberfläche:** statt `createInternalRuntime`/`findObject` hängt der
  Tuner jetzt an `FX.getFxData()` + `FXData.objects()` + `IFXObject.getName()` — alle
  public in photon 2.1.5. Eine künftige Photon-Version, die das umbaut, degradiert
  fail-soft (Tuner disabled, Loops mit Autoren-Raten) — wie bisher.
- **Session-Altlast:** eine BEREITS vergiftete Session (alter Build) heilt der Fix
  nicht rückwirkend — er verhindert die Vergiftung ab dem ersten Attach der Session.
  Nach Client-Neustart mit dem Fix ist der Cache dauerhaft sauber.
- **Photon-Editor:** wer im laufenden Spiel den Photon-In-Game-Editor auf dieselben
  Assets richtet, erzeugt eigene Szenen auf Cache-Objekten (Photon-intern, außerhalb
  unserer Kontrolle) — für den Serverbetrieb irrelevant.
- **Nicht angefasst:** `PhotonBridge`-Grace/Sweep, `PhotonFxRegistry`-Loop-Lane,
  alle FxRows — Verhalten unverändert; das Duplicate-Law im PhotonBridge-Header
  (Zeile ~331) bleibt korrekt und gilt weiter für echte Respawn-Antipatterns.

---

## Runde 2 (F-103 A′) — die "neue" Evidenz widerlegt den Fix NICHT, aber der §6-Restvektor ist jetzt an der Quelle zu

**Verdikt:** Die Live-Runtime-Evidenz der Nacht stammt aus einer Client-JVM, die den
Runde-1-Fix **nie geladen hat** — die beobachteten Bursts sind exakt der Runde-1-
Mechanismus (alte Klassen), nicht ein neuer Pfad. Der reale Rest-Vektor ist die in §6
dokumentierte **Session-Altlast**: ein einmal vergifteter `FXHelper`-Cache akkumuliert
im **normalen `createRuntime()`-Spawn-Pfad** für den Rest der JVM-Session weiter, und
kein bisheriger Code konnte das heilen. Runde 2 schließt genau das mit einem
**Template-Hygiene-Sweep** am einzigen Spawn-Chokepoint (`PhotonBridge.startExecutor`).

### R2.1 Beweis: die JVM lief die ganze Nacht auf Pre-Fix-Bytecode

- `run/logs/debug.log` enthält **genau einen** `ModLauncher running`-Eintrag:
  `[31Jul2026 23:11:51.273]` (`rg -c "ModLauncher running" debug.log` → 1). Die Datei
  läuft ununterbrochen bis in den Morgen — **02:48 und 04:31 waren Welt-Re-Joins**
  (voicechat-Reconnects), keine JVM-Starts.
- Der Fix wurde **00:30 kompiliert / 00:32 committed** (e44c785;
  `build/classes/.../StormNearfieldFx$Tuner.class` mtime 00:30). Die JVM hatte die
  ALTEN Tuner-Klassen da längst geladen: erste Duplicate-Warns **23:43:26** — 10 Stück,
  darunter die drei `*_root`-UUIDs (`092d8199…` u. a.) = die "erster vergifteter
  Spawn"-Signatur aus §1.3. Geladene Klassen werden in einer laufenden JVM nie
  ausgetauscht → `createInternalRuntime` feuerte bei jedem Tuner-attach weiter.
- Die Bursts liefen nach dem angeblichen "0 weitere Warns"-Zeitpunkt (04:44:25)
  weiter: **05:07:16 (7966 = 7×1138)** und **05:09:17/18 (Σ 8029 = 7×1147)** —
  debug.log-Burstserie: 10 @23:43:26, dann 7×1025 / 7×1026 / 7×1027 (04:44:05/15/25),
  7×1029 (04:56:20), 7×1138, 7×1147.
- **Die "Wisp-Anomalie" existiert nicht.** Über alle Bursts sind die 7 Emitter-UUIDs
  exakt uniform verteilt (`rg … | rg -o "id [0-9a-f]{8}" | sort | uniq -c` → 7 × 3078
  in latest.log). Die 1027/700/1-These der Missions-Beschreibung war ein Zählfehler.

### R2.2 Die vollständige Mechanik (jedes Glied javap-verifiziert, photon 2.1.5 + ldlib2 2.2.29)

Die Runde-1-Kette stimmt und ist jetzt bis in die Silent-Phase präzisiert:

1. **Vergiftung (einmalig, 23:43:26):** alter `Tuner.attach` →
   `FX.createInternalRuntime()` auf dem geteilten Cache → `FXRuntime.initRuntime`
   Schritt 2 ruft `setScene(runtime)` + `awake()` auf jedem TEMPLATE-Objekt;
   `Transform.awake()` löst `_parentId` über `IScene.getSceneObject` auf und baut live
   Parent/Child-Links (`getSceneObject` hat `getOrDefault(uuid, root)` — nie null).
2. **Silent-Akkumulation (+1 Graft pro Objekt pro Spawn, KEINE Warns):** jeder normale
   Spawn (`BlockEffectExecutor.start` → `FX.createRuntime()` → `FXData.copy(false)` →
   `FXObject.copy(false)`) ruft `copy.copyTransformFrom(template)` →
   `Transform.copyTransformFrom(other, true, true)` → **`parent(other.parent())`** —
   der live Template-Parent wird kopiert. `Transform.addChildInternal` macht
   `children.add(child)` **ohne Duplikat-Check** (nur `_childrenId` wird
   contains-geprüft) → der Template-Root sammelt pro Spawn eine Kopie pro Emitter.
   Warum ohne Warn: `addChildInternal` ruft zwar `copy.setScene(templateScene)` und
   `objects.put` ersetzt kurz — aber `initRuntime` Schritt 2 zieht die Kopie sofort in
   ihre eigene Runtime um, und `ISceneObject.setScene` macht dabei
   `removeSceneObjectInternal` auf der alten Szene → **der Map-Slot der internen Szene
   wird geleert**, der nächste Spawn-put trifft einen leeren Slot. Der Transform-Graft
   bleibt (Schritt 3 von `initRuntime` re-parentet nur parent-lose Objekte; der
   `setScene`-Umzug korrigiert nur die Map, nie den Transform-Baum).
3. **Flush (der Burst, N Warns pro Emitter):** nächster `Tuner.attach` nach einem
   Fenster-Re-Open (der `EMISSIONS[slot] != null`-Guard verhindert attaches innerhalb
   eines offenen Fensters — deshalb bursten nur TP-Zyklen) → neues
   `createInternalRuntime()` → `setScene`-Kaskade (`children().forEach(c ->
   c.setScene(scene))`) über den Template-Root → alle N akkumulierten Kopien werden
   sequenziell unter derselben Asset-UUID geputtet: Kopie 1 ersetzt das
   Template-Objekt, Kopie k ersetzt Kopie k−1 → **exakt N Warns pro Emitter**
   (7×1025 = 7175 ✓).
4. **Churn-These korrigiert:** `Emitter.isAlive()` ist `!removed || particleAmount>0
   || FXObject.isAlive()` — ein laufender Loop meldet auch auf llvmpipe alive (`dev
   photon status` 04:52: "10/24 live (9 loops)"). Der ~6s-Respawn-Churn (Population
   +109 zwischen 04:56 und 05:07) ist der §1.4-Nebenschaden des ALTEN Codes: der
   attach-Flush + die Graft-Fehlanker reißen live Loops kaputt, das Keepalive respawnt
   nach Ablauf der 100t-Grace (~5–6s). Mit sauberem Cache gibt es weder Flush noch
   Fehlanker → kein Churn; ein zusätzlicher Respawn-Backoff wäre reine
   Symptomdämpfung und wurde bewusst NICHT eingebaut.

### R2.3 Fix: Template-Hygiene-Sweep am Spawn-Chokepoint

`PhotonBridge.startExecutor` (der einzige Pfad, über den JEDER Bridge-Spawn läuft —
One-Shots, Loops, Entity-Attaches, alle Teams) prüft jetzt VOR jedem Spawn das
gecachte FX-Template (`TemplateHygiene.scrub`):

- **Probe (immer, ~12 reflektive Reads):** zählt `liveParents` / `liveChildren` /
  `liveScenes` über alle Template-Objekte und loggt sie als DEBUG-Zeile
  (`Photon template hygiene probe: <fx> liveParents=0 liveChildren=0 liveScenes=0`) —
  auf sauberem Cache immer 0/0/0, dann No-Op.
- **Scrub (nur bei Dirt):** (A) alle live Children jedes Templates strippen
  (`Transform.destroy()` pro Kind + `children().clear()` als Belt-and-Braces für
  detach-verweigernde Edge-States), (B) Templates von live Parents lösen
  (`destroy()` erhält das eigene persistierte `_parentId` und resettet den
  `isValid`-Awake-Latch = exakt der Frisch-von-Platte-Zustand), (C) Templates aus
  stale Szenen-Maps ziehen (`removeSceneObjectInternal` + `setSceneInternal(null)`),
  (D) die von `removeChildInternal` erodierten persistierten `_childrenId`-Listen aus
  einem Vorher-Snapshot restaurieren. Geteilte `ParticleConfig`s (Channel-A-Fläche
  der Tuner) werden bewusst NICHT angefasst; ebenso KEINE Cache-Eviction (die würde
  die Tuner-`EMISSIONS`-Referenzen von künftigen Spawns entkoppeln).
- **Fail-soft:** erste reflektive Überraschung → Sweep session-disabled (DEBUG-Zeile
  `Photon template hygiene sweep disabled`), Spawns laufen exakt wie vorher.
- **Tripwire:** ein dirty Scrub loggt einmal pro fx-Id eine WARN
  (`Photon template hygiene: <fx> had live scene-graph state …`) — in gesunden
  Sessions existiert diese Zeile nie. Zähler: `PhotonBridge.hygieneDirtyScrubs()` /
  `hygieneLinksRemoved()` (public, für eine künftige `/dev photon status`-Zeile —
  FxDevClient liegt außerhalb der R2-Zone und wurde nicht angefasst).

Damit gilt für Produktion (echte GPU) UND llvmpipe: beliebig häufige
Fenster-Re-Opens/Respawns erzeugen ausschließlich selbst-konsistente Runtimes
(`initRuntime`-`awake()` löst `_parentId` innerhalb der eigenen Runtime-Map auf), und
selbst wenn ein künftiger Pfad (Photon-Editor, Fremdcode) die Templates erneut
vergiftet, heilt der nächste Spawn den Cache statt eine Session lang zu leaken →
**0 Duplicate-Warns garantiert**.

### R2.4 Geänderte Dateien

- `src/main/java/dev/projecteclipse/eclipse/veilfx/PhotonBridge.java`
  (`TemplateHygiene`-Sweep + Probe + Zähler-Accessors; Scrub-Aufruf in
  `startExecutor`). Sonst nichts — beide Tuner bleiben auf dem Runde-1-Stand,
  `PhotonFxRegistry` unverändert.

### R2.5 Gate-Ergebnisse

- `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` →
  **BUILD SUCCESSFUL** (2 actionable tasks). Keine Server-/Client-Starts, kein RCON.

### R2.6 Verifikationsskript für den Main-Agent (Runde 2)

**Schritt 0 ist zwingend und war der blinde Fleck der Nacht-Session:**

```bash
# 0) CLIENT-JVM NEU STARTEN (die laufende JVM führt Pre-Fix-Bytecode aus!):
#    Client-Prozess beenden, `flock /tmp/gradle.lock ./gradlew compileJava --offline`
#    (bereits grün), Client frisch starten. Kontrolle: run/logs/debug.log beginnt neu
#    mit einer frischen "ModLauncher running"-Zeile NACH dem Kompilat-Zeitstempel.

# 1) Baseline nach Join:
rg -c "Duplicate fx runtime" run/logs/latest.log   # merken (frisches Log: 0)

# 2) Churn-Repro exakt wie in der Nacht (RCON):
#      eclipsefx storm add 24 60 sphere            # Sturm bei ~(40,112,12)
#      tp @p 0.5 108 12.5                          # Nearfield-Fenster öffnet
#      35 s stehen lassen; dann 3 TP-Zyklen:
#      tp @p 10000 108 10000  → 5 s →  tp @p 0.5 108 12.5   (3× wiederholen)
#      optional: dev structure spawn <site> dazwischen (Burst-1-Repro aus Runde 1)

# 3) Akzeptanz Warns:
rg -c "Duplicate fx runtime" run/logs/latest.log   # UNVERÄNDERT (0 neue)

# 4) Populations-Sonde (misst die Template-Kindliste bei JEDEM Spawn):
rg "template hygiene probe" run/logs/debug.log | tail -20
#    → JEDE Zeile "liveParents=0 liveChildren=0 liveScenes=0", auch nach N Zyklen
#      (eine wachsende liveChildren-Zahl wäre der Leak — darf nie auftreten).
rg -c "Photon template hygiene:" run/logs/debug.log
#    → 0 (die Dirty-WARN ist der Tripwire; >0 heißt: irgendwas vergiftet wieder,
#      der Sweep hat es geheilt — dann bitte die Zeile mit fx-Id an Team A′ melden).
rg -c "template hygiene sweep disabled" run/logs/debug.log
#    → 0 (Reflection-Pfad intakt).

# 5) Tuner/Loop-Gesundheit (wie Runde 1):
#      dev photon status  → stabile "executors: X/24 live"-Zahlen, keine Respawn-Serie;
#      Dichte-Modulation beim Rein-/Rauslaufen am 150–250-Band sichtbar (Channel A lebt).
```

**Log-Erwartung:** 0 neue `Duplicate fx runtime`-Warns über beliebig viele
TP-Zyklen; Hygiene-Probe konstant 0/0/0; keine `hygiene`-WARN, keine
`live-tuner disabled`-Zeile.

### R2.7 Restrisiken (Runde 2)

- **Alt-Session:** die noch laufende Nacht-JVM warnt weiter, bis sie neu gestartet
  wird — kein Code kann geladene Klassen ersetzen. Nach dem Neustart ist auch die
  §6-Altlast obsolet: ein künftig vergifteter Cache heilt am nächsten Spawn.
- **Reflection-Oberfläche:** der Sweep hängt zusätzlich an `ISceneObject.transform/
  getScene/setSceneInternal`, `IScene.removeSceneObjectInternal`,
  `Transform.parent()/children()/destroy()/_getInternalChildID/_setInternalChildID`
  (alle public, javap-verifiziert). Ein Photon/ldlib-Umbau degradiert fail-soft auf
  das Runde-1-Verhalten (Sweep aus, eine DEBUG-Zeile).
- **Poisoned-Session-Optik:** trifft der Scrub eine BEREITS vergiftete Session (nur
  via Editor/Fremdcode möglich), verlieren die live gerafteten Alt-Kopien ihren
  (ohnehin falschen) Template-Anker — deren Partikel können einen Frame springen.
  Auf sauberen Sessions ist der Sweep beweisbar ein No-Op (Probe-Fast-Path).

## Runde 2 — Live-Abnahme (01.08. 06:11–06:13 UTC, frischer Client) ✅

Durchgeführt exakt nach R2.6 (`/tmp/f103_a_verify.sh`), Client-JVM frisch gebootet
(Boot 06:04, Join 06:10 — Schritt 0 war zwingend: die Vor-Nacht-JVM lud nachweislich
Pre-R2-Bytecode, 0 Hygiene-Proben trotz 7 Wave3-Spawns, weil `build/classes` erst
NACH ihrem Boot auf R2 kompiliert wurde; FML liest die Modklassen beim Boot-Scan).

| Messpunkt | Erwartung | Ergebnis |
| --- | --- | --- |
| Baseline `Duplicate fx runtime` | 0 | **0** |
| Storm r=24 gesetzt, Fensterplatz, 35 s Dwell | Loop-FX attach + Tuner aktiv | ✅ (`storm_vein_bolt`-Proben im Takt) |
| 3× Teleport-Churn (10 000 Blöcke hin/zurück, je 5 s) | erzwingt Voll-Despawn/Respawn | ✅ |
| 60 s Catch-up, dann `Duplicate fx runtime` gesamt | 0 | **0** (alt: 3 Bursts à ~7 180) |
| Hygiene-Probe (jede Spawn-Passage) | konstant `0/0/0` | **konstant `liveParents=0 liveChildren=0 liveScenes=0`** |
| `Photon template hygiene:` Dirty-WARN (Tripwire) | 0 | **0** (R1-Fix hält: nichts vergiftet mehr, Sweep bleibt No-Op) |
| `template hygiene sweep disabled` / `live-tuner disabled` | 0 / 0 | **0 / 0** (Reflection-Pfad läuft in Photon 2.1.5 live) |

Damit sind beide Vektoren geschlossen und live bewiesen: R1 (Cache-Vergiftung durch
`createInternalRuntime` in den Tunern) + R2 (Session-Altlast-Flush am Re-Attach).

**Beifang der Abnahme (nicht Team A):** Auf der Alt-JVM lief seit der ersten
Licht-Aktivierung (05:45:49, `veil:light/point`-Sampler-Validierungswarnung auf
llvmpipe) ein `Finished uploading vanilla shaders`-INFO-Flood mit ~25 Zeilen/s —
Veils `DynamicBufferManager.update()` loggt die Zeile jeden Frame, solange ein
Shader in `swapShaders` nie `isRecompileReady` wird. Framework-Quirk (Bytecode
dekompiliert und verifiziert), kein Eclipse-Code beteiligt, funktional harmlos
(alle 78 Vanilla-Shader kompilierten in 544 ms), aber er bläht Logs auf: bei
Log-basierten Abnahmen auf llvmpipe einplanen. Frische R2-Session: 2 Vorkommen.
