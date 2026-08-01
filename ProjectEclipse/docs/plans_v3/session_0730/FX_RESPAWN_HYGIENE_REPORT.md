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
