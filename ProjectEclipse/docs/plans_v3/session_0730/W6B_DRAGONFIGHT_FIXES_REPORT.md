# W6B Dragonfight Fixes — Crescendo Long-Overflow & Landing-Retry Bounce

Zwei live gefundene Bugs im End-Disc-Drachenkampf, beide in
`src/main/java/dev/projecteclipse/eclipse/worldgen/end/EclipseDragonFight.java` gefixt.
Keine anderen Dateien angefasst (die uncommitteten Limbo-Fog-Änderungen im Arbeitsbaum
stammen von einem parallelen Subagenten und sind nicht Teil dieses Fixes).

---

## Bug 1 (Wave-6-Regression, KRITISCH): Crescendo feuert nie — Long-Overflow

### Root Cause

`lastCrescendoGameTime` war als `Long.MIN_VALUE`-Sentinel initialisiert (Zeile 121),
aber der Cadence-Guard in `tickCrescendo` subtrahierte den Sentinel ungeprüft:

```java
if (cadence < 0 || gameTime - lastCrescendoGameTime < cadence) { return; }
```

`gameTime - Long.MIN_VALUE` ist in 64-bit-Zweierkomplement-Arithmetik äquivalent zu
`gameTime + Long.MIN_VALUE` (Subtraktion von MIN_VALUE wrappt) und ergibt für jedes
realistische `gameTime` einen stark NEGATIVEN Wert → `< cadence` immer wahr → `return`.
Der Sub-10%-Herzschlag war damit toter Code. Live-Beweis der Abnahme: Drache per NBT auf
25/300 HP (8,3 %), `tickCrescendo` lief jeden Tick (Aufruf in `tickFight`), 0
`[w6b-crescendo]`-Zeilen über >60 s Debug-Log.

### Overflow-Beweis (Python, 64-bit-Long-Semantik via ctypes.c_int64)

```
Long.MIN_VALUE           = -9223372036854775808
gameTime                 = 1000000
gameTime - MIN (64-bit)  = -9223372036853775808   ← wrappt stark negativ
diff < cadence(30)?      = True                   ← Guard returned IMMER
```

(Erzeugt mit `ctypes.c_int64(1_000_000 - (-2**63)).value`; mathematisch wäre die
Differenz `9223372036854776808`, also `Long.MAX_VALUE + 1001` — der Überlauf ist für
JEDES `gameTime ≥ 0` unvermeidbar.)

### Vorbild-Analyse (W5-A5, `HeraldEntity.tickHeartbeatCrescendo`)

Das referenzierte Idiom ist dort robust:

```java
private int lastCrescendoTick = -1000;               // kleiner int-Sentinel
...
if (cadence < 0 || this.tickCount - this.lastCrescendoTick < cadence) { return; }
```

`tickCount` startet bei 0, `tickCount - (-1000) = tickCount + 1000` — immer ≥ cadence,
Erstpuls feuert sofort beim Eintritt in die Sub-10%-Zone, kein Overflow möglich (int,
kleiner Sentinel-Betrag). **Das Vorbild hat den Fehler NICHT** — der Bug entstand erst
bei der Portierung auf `long gameTime` mit `Long.MIN_VALUE` als Sentinel.

### Gewählter Fix: expliziter Sentinel-Check

```java
if (cadence < 0) {
    return;
}
// Sentinel-guard BEFORE the elapsed-tick subtraction: gameTime - Long.MIN_VALUE
// overflows strongly negative, which silently swallowed every pulse. With the
// guard, the first pulse fires immediately on entering the sub-10% zone.
if (lastCrescendoGameTime != Long.MIN_VALUE
        && gameTime - lastCrescendoGameTime < cadence) {
    return;
}
```

Begründung gegenüber der Alternative „Init auf `0L`":

- `Long.MIN_VALUE` bleibt als eindeutiger „nie gepulst"-Marker erhalten; die Semantik
  „Erstpuls sofort" steht explizit im Code statt implizit von einem großen `gameTime`
  abzuhängen (bei Init `0L` wäre in den ersten <30 Ticks eines frischen Levels der
  Erstpuls theoretisch verschluckt — irrelevant praktisch, aber unsauber).
- Der bestehende Reset in `onServerStopped` (`lastCrescendoGameTime = Long.MIN_VALUE;`)
  bleibt unverändert korrekt und ist mit dem Sentinel-Check jetzt der SAUBERE
  Frisch-Zustand — keine zweite Stelle anzupassen.
- Transient-Charakter erhalten: kein Persist, statisches Feld, cadence ≤30t.

### Reset-Pfad-Prüfung (zweiter Kampf im selben Prozess)

- Einziger Reset-Pfad der W6B-Transienten ist `onServerStopped` (dort, wo auch
  `perchLatched = false` gesetzt wird). Er setzt das Feld bereits auf
  `Long.MIN_VALUE` zurück → mit dem Sentinel-Check startet eine neue Server-Session
  korrekt mit „Erstpuls sofort". Keine Änderung nötig.
- `begin()` setzt das Feld nicht zurück — unkritisch: ein hypothetischer zweiter Kampf
  im selben Prozess hinterließe nur einen ALTEN (vergangenen) gameTime-Wert, dessen
  Differenz groß-positiv ist → Erstpuls feuert ebenfalls sofort.

---

## Bug 2 (Alt-Code, von W6B-Abnahme aufgedeckt): Landing-Retry bricht laufende Landungen ab

### Root Cause

Der 160t-Landing-Retry (nach Kristall-Ende) forcierte `LANDING_APPROACH`, sobald die
Phase nicht sitting war:

```java
if (state.crystalsRemaining() == 0
        && gameTime % LANDING_RETRY_TICKS == 0L
        && !dragon.getPhaseManager().getCurrentPhase().isSitting()) {
    dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
}
```

Auf der Custom-Disc dauert eine Landung (Anflug-Pfadfindung + Sinkflug) oft länger als
160t. Der Force traf damit regelmäßig einen AKTIV LAUFENDEN Anflug/Sinkflug und warf
ihn auf den Approach-Start zurück — live beobachtet als minutenlanges Zyklen
2 (LANDING_APPROACH) → 3 (LANDING) → Retry-Force → 2 → 3 … Der Drache landete nur, wenn
der Zyklus zufällig günstig zum 160t-Raster lag.

### Gewählter Fix: Retry nur außerhalb des Landeablaufs

```java
if (state.crystalsRemaining() == 0 && gameTime % LANDING_RETRY_TICKS == 0L) {
    // Landing retry: heals a dragon that drifted back into a flight phase
    // (HOLDING_PATTERN/STRAFE/...) without ever perching. It must NOT touch an
    // approach or landing already in progress — on the custom disc a landing
    // legitimately takes longer than one retry window, and re-forcing
    // LANDING_APPROACH restarts the descent (observed 2↔3 phase bouncing).
    var currentPhase = dragon.getPhaseManager().getCurrentPhase();
    var phase = currentPhase.getPhase();
    if (!currentPhase.isSitting()
            && phase != EnderDragonPhase.LANDING_APPROACH
            && phase != EnderDragonPhase.LANDING) {
        dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
    }
}
```

Warum die Bedingung das beobachtete Zyklen beendet, aber echte Hänger weiter heilt:

- **Beendet das Zyklen:** Solange der Drache in `LANDING_APPROACH` oder `LANDING`
  steckt, fasst der Retry ihn nicht mehr an — der Landeablauf darf beliebig viele
  160t-Fenster dauern und läuft ungestört bis zum Aufsetzen (sitting).
- **Heilt echte Hänger weiterhin:** Driftet der Drache OHNE zu landen zurück in eine
  Flugphase (`HOLDING_PATTERN`, `STRAFE_PLAYER`, nach `TAKEOFF` etc. — z. B. weil die
  vanilla-Phasenlogik ohne echten `EndDragonFight` das Landeziel verliert), ist die
  Phase weder approach/landing noch sitting → der nächste 160t-Tick forciert wie bisher
  `LANDING_APPROACH`. Genau das Circling-ohne-Landung-Szenario, für das der Retry
  ursprünglich gebaut wurde.
- Ein zusätzlicher Backoff (≥600t seit letztem Force) wäre ergänzend möglich, ist aber
  nicht nötig: Die Phasen-Bedingung allein entfernt die Abbruch-Ursache; ein Backoff
  ohne Phasen-Check hätte das Zyklen nur verlangsamt, nicht beseitigt. Minimal-invasiv
  gehalten (kein neues State-Feld).

Vanilla-Referenzen: `EnderDragonPhase.LANDING_APPROACH`, `EnderDragonPhase.LANDING`,
`DragonPhaseInstance.isSitting()`; Phasen-Zugriff via
`dragon.getPhaseManager().getCurrentPhase().getPhase()` (dasselbe Idiom wie im
`watchdog` derselben Klasse).

---

## Diff (vollständig, nur `EclipseDragonFight.java`)

```diff
@@ -117,7 +117,13 @@ public final class EclipseDragonFight {
     private static List<Vec3> lastCrystalPositions = List.of();
     /** WAVE6 (F-106 B) B3: perch flank latch — true while the dragon sits (1 beat per landing). */
     private static boolean perchLatched;
-    /** WAVE6 (F-106 B) B4: last crescendo pulse game time (transient; cadence ≤30t). */
+    /**
+     * WAVE6 (F-106 B) B4: last crescendo pulse game time (transient; cadence ≤30t).
+     * {@link Long#MIN_VALUE} is the "never pulsed" sentinel and MUST be guarded before
+     * any {@code gameTime - lastCrescendoGameTime} subtraction — the difference
+     * overflows strongly negative for every realistic game time (the Herald precedent
+     * avoids this with a small int sentinel, {@code lastCrescendoTick = -1000}).
+     */
     private static long lastCrescendoGameTime = Long.MIN_VALUE;
     /** WAVE6 (F-106 B) B4: victory light pillars still owed (staggered over the tick loop). */
     private static int requiemPillarsPending;
@@ -374,10 +380,19 @@ public final class EclipseDragonFight {
         if (gameTime % WATCHDOG_TICKS == 0L) {
             watchdog(dragon, state.crystalsRemaining());
         }
-        if (state.crystalsRemaining() == 0
-                && gameTime % LANDING_RETRY_TICKS == 0L
-                && !dragon.getPhaseManager().getCurrentPhase().isSitting()) {
-            dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
+        if (state.crystalsRemaining() == 0 && gameTime % LANDING_RETRY_TICKS == 0L) {
+            // Landing retry: heals a dragon that drifted back into a flight phase
+            // (HOLDING_PATTERN/STRAFE/...) without ever perching. It must NOT touch an
+            // approach or landing already in progress — on the custom disc a landing
+            // legitimately takes longer than one retry window, and re-forcing
+            // LANDING_APPROACH restarts the descent (observed 2↔3 phase bouncing).
+            var currentPhase = dragon.getPhaseManager().getCurrentPhase();
+            var phase = currentPhase.getPhase();
+            if (!currentPhase.isSitting()
+                    && phase != EnderDragonPhase.LANDING_APPROACH
+                    && phase != EnderDragonPhase.LANDING) {
+                dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
+            }
         }
         if (gameTime % ENTITY_TICKET_TICKS == 0L) {
             loadCrystalChunks(level);
@@ -503,7 +518,14 @@ public final class EclipseDragonFight {
     private static void tickCrescendo(ServerLevel level, EnderDragon dragon, long gameTime) {
         float fraction = dragon.getHealth() / dragon.getMaxHealth();
         int cadence = fraction > 0.10F ? -1 : fraction > 0.0666F ? 30 : fraction > 0.0333F ? 20 : 12;
-        if (cadence < 0 || gameTime - lastCrescendoGameTime < cadence) {
+        if (cadence < 0) {
+            return;
+        }
+        // Sentinel-guard BEFORE the elapsed-tick subtraction: gameTime - Long.MIN_VALUE
+        // overflows strongly negative, which silently swallowed every pulse. With the
+        // guard, the first pulse fires immediately on entering the sub-10% zone.
+        if (lastCrescendoGameTime != Long.MIN_VALUE
+                && gameTime - lastCrescendoGameTime < cadence) {
             return;
         }
         lastCrescendoGameTime = gameTime;
```

## Gate-Belege

```
$ cd /workspace/ProjectEclipse && ./gradlew compileJava --console=plain
> Task :createMinecraftArtifacts UP-TO-DATE
> Task :compileJava

BUILD SUCCESSFUL in 1s
2 actionable tasks: 1 executed, 1 up-to-date
Exit code: 0
```

## Erwartetes Live-Verhalten nach Fix

- **Crescendo:** Sobald HP < 10 % (z. B. NBT 25/300 = 8,3 %), feuert der ERSTE Puls im
  selben Tick (Sentinel-Guard); danach die HP-gestaffelte Leiter im Debug-Log:
  `[w6b-crescendo] hp=0.0xx cadence=30` (>6,66 %), `cadence=20` (>3,33 %),
  `cadence=12` (darunter) — jeder Puls sendet WARDEN_HEARTBEAT an alle lebenden
  Nicht-Spectator-Spieler im 192-Block-Radius um das Fight-Center.
- **Landing:** Nach Kristall-Ende EIN Übergang HOLDING_PATTERN → LANDING_APPROACH (via
  Crystal-Scan-Trigger bzw. erstem Retry), dann ungestörter Anflug → Landung → sitting;
  KEIN 2↔3-Zyklen mehr. Danach stabiles Sitzen bis Spielerkontakt (Perch-Beat 1× pro
  Landung, per Latch). Der Retry greift nur noch, wenn der Drache in eine Flugphase
  zurückdriftet, ohne gelandet zu sein.

### Randnotiz aus der Live-Abnahme (dokumentiert, nichts geändert)

Der Perch-Beat feuerte 3× in ~40 s — je Landung genau 1×, korrekt per Latch-Design.
Das viele Re-Landen war Folge von Bug 2 (Retry-Force brach Landungen ab) plus Takeoff
mangels Angriffsziel in Reichweite. Nach dem Fix erwartet: 1 Landung, stabiles Sitzen
bis Spielerkontakt.

## Regressions-Check

- `LANDING_RETRY_TICKS`: einziger Nutzer ist der gefixte Retry-Block in `tickFight`
  (Konstantendefinition Zeile 73 + eine Verwendung). Keine weiteren Referenzen im Repo.
- `lastCrescendoGameTime`: Nutzer sind ausschließlich Felddefinition (Z. 121ff), Reset
  in `onServerStopped` (Z. ~321, bleibt `Long.MIN_VALUE` — jetzt semantisch korrekt als
  Frisch-Sentinel) und `tickCrescendo` (Guard + Write). Keine weiteren Referenzen.
- Das W5-A5-Vorbild (`HeraldEntity.tickHeartbeatCrescendo`) und die weiteren
  `tickHeartbeatCrescendo`-Implementierungen (`FogTyrantEntity`, `RiftWardenEntity`,
  `FerrymanEntity`) nutzen das int/`tickCount`-Idiom mit kleinem Sentinel und haben den
  Overflow-Fehler NICHT — außerhalb des Scopes, nichts geändert.
- Unangetastet (paralleler Subagent): `veilfx/LimboAmbience.java`, Limbo-Fog-Assets
  (`quasar/emitters/limbo_fog*.json`, `textures/particle/limbo_fog*_soft.png`).
