# F-109 — "Respawn wirft Spieler an die Soft-Border-Kante ins Void" — Root-Cause-Report

**Session:** 2026-08-02 (Live-Server, Branch `cursor/project-eclipse`, laufender Build)
**Status:** Root Cause identifiziert, chirurgischer Fix in `SoftBorder.java`, `./gradlew compileJava` grün.
**Wichtigste Korrektur gegenüber dem Arbeitstitel:** Der Respawn selbst hat den Spieler **nie** an die
Ring-Kante gesetzt — die Lives-/Limbo-Pipeline hat auf jedem der vier heutigen Tode korrekt aufs
Geisterschiff respawnt. Der Killer ist der **Teleport-Clamp** (`SoftBorder.clampTeleport`), der jedes
geklemmte Ziel in eine **konstruktionsbedingt terrainfreie Void-Säule bei `R−2`** mit unverändertem Y
setzt. Die "fallend bei x=z=318.698"-Beobachtungen nach dem Death-Screen waren die **noch tote Leiche**
(Death-Screen offen), die von Rettungs-`/tp`s erneut in genau diese Void-Säule geklemmt wurde.

---

## 1. Root Cause

### 1.1 Primär: der Teleport-Clamp landet garantiert im Void (Todesschleife)

`SoftBorder.clampTeleport` (vor dem Fix, `border/SoftBorder.java:832-865` alt) klemmte das Ziel von
`EnderPearl`/`ChorusFruit`/`TeleportCommand`-Events auf

```java
double maxR = Math.max(0.0D, radius - TELEPORT_INSET);   // R − 2
...
event.setTargetX(state.getBorderCenterX() + dx * scale); // XZ auf den Kreis R−2
event.setTargetZ(state.getBorderCenterZ() + dz * scale); // Y: "left untouched"
```

Zwei fatale Eigenschaften:

1. **`R−2` liegt IMMER jenseits des äußersten Terrains.** Der Ring ist
   `R = stageOuterRadius + borderOffset` (`onStageCommit`, borderOffset=12, general.json). Heute:
   stageOuter=440, R=452, Clamp-Punkt bei r=450 — 10 Blöcke jenseits der äußersten Terrain-Säule,
   noch vor Rim-Taper/Crumble. Die Landesäule ist **per Konstruktion Void**.
2. **Die "Physik räumt auf"-Annahme im alten Doc-Kommentar war falsch.** Der Clamp-Punkt liegt bei
   `d = R−2 < R`, also **innerhalb** des Rings: Der Tick-Check (`onPlayerTick`,
   `distSq <= radius*radius → return`) greift nie ein — kein `teleportInside`, kein Impuls, nur ggf.
   die Warnband-Actionbar (`R−4 = 448 < 450`), während der Spieler bereits ins Void fällt.

Ergebnis: **Jeder geklemmte Teleport = garantierter Fall-Tod** (`outOfWorld`). Wiederholte
(Rettungs-)Teleports auf dasselbe Außenziel werden immer wieder auf denselben Punkt geklemmt →
Todesschleife. In Survival trifft das jeden Spieler, der eine Enderperle über den Ring wirft oder
per Kommando nach außen teleportiert wird.

Mathematischer Beweis-Match: Border-Center = World-Spawn-Block-Mitte (0.5, 0.5)
(`onServerStarted`, `SoftBorder.java:440-441`). Ziel (3000.5, 3000.5) → Richtung (1/√2, 1/√2) →
Clamp-Punkt `0.5 + 450/√2 = 318.6980515339464` in X und Z — **exakt** die beobachtete Position.

### 1.2 Sekundär: Creative-Exemption fehlte auf dem Clamp-Pfad

Die Exemption existierte nur im Tick-Pfad (`onPlayerTick`: `player.isCreative() → exempt`, mit dem
Log-Spam) und im Vehicle-Pfad (`firstPlayerPassenger`). `onTeleportCommand` bypasste ausschließlich
`player.hasPermissions(2)` — geprüft wird die **Ziel-Entity**, nicht die Kommando-Quelle. Ein per
RCON teleportierter Creative-Spieler ohne Op-Eintrag (Dev; `run/ops.json` ist `[]`) wurde also
geklemmt, obwohl ihn alle anderen Border-Pfade exemptieren. (Devs eigene `/tp`s um 08:25 liefen als
`/execute as Dev …` über RCON — Quellname "Dev", Permission der Konsole.)

### 1.3 Log-Hygiene: per-Tick-DEBUG-Spam

`onPlayerTick` loggte die Exempt-Zeile **jeden Tick** (20/s) pro Creative-Spieler außerhalb des
Rings — 12 239 Zeilen allein in der heutigen Server-Session; die tmux-Scrollback-History bestand zu
>95 % aus dieser Zeile und hat die eigentlichen Incident-Zeilen verdrängt.

### 1.4 NICHT bestätigt: "Respawn landet statt auf dem Geisterschiff im Void"

Die Respawn-Pipeline ist korrekt und das Death-Screen-Versprechen
(`gui.eclipse.death.ship_hint` = "You will wake on the ship of the dead") **wird eingehalten**:

- Pre-Event (`isStartEventDone()==false`, aktueller Weltzustand): `LimboGate.onRespawn`
  (`limbo/LimboGate.java:39-44`) gated jeden Respawn aufs Schiff; danach übernimmt
  `DeathFlowHooks.onPlayerRespawn` (LOWEST, `lives/DeathFlowHooks.java:178-229`) die
  Deck-Wake/Tür-Sequenz und `finishReturn` bringt den Spieler zurück zur (dann in Limbo erfassten)
  `homePos` — der Spieler bleibt pre-event auf dem Schiff. Beleg: **4 Tode ↔ 4 Gate-Zeilen**
  (siehe §2).
- Post-Event greift derselbe `DeathFlowHooks`-Fluss mit echter Vanilla-`homePos`.
- `SoftBorder` fasst Respawns nie an (`LimboGate`/`DeathFlowHooks` teleportieren per
  `ServerPlayer.teleportTo`, das feuert kein `EntityTeleportEvent`).

Die Beobachtung "nach Klick auf 'To the Railing' fallend bei 318.698" entstand so: Der Death-Screen
blieb minutenlang offen (Foto-Session), währenddessen wurde die **tote** Spieler-Entity per RCON-`/tp`
"gerettet" → Clamp → Leiche erneut in der Void-Säule, Death-Cam fiel weiter (Client sendet weiterhin
Bewegungspakete). Erst der spätere Klick löste den echten Respawn aus — der ging nachweislich aufs
Schiff (Gate-Zeile), von wo ihn die nächsten RCON-`/tp`s (Quelle=Konsole ⇒ Ziel-Dimension Overworld)
wieder herauszogen.

---

## 2. Beweiskette (wiederhergestellte Server-Logs)

Server (`gradlew runServer`, tmux `mc-server`) und Client teilen `run/`; der Client hat beim Start
07:23 die Server-Logdateien wegrotiert. Die Server-Logs waren über die noch offenen File-Handles
rekonstruierbar: `/proc/<server-pid>/fd/163` (`latest.log`, gelöscht) und `fd/166` (`debug.log`,
gelöscht) → Kopien unter `/tmp/server-latest.log` / `/tmp/server-debug.log`.

Zeitachse 2026-08-02 (Auszug, alle Zeilen aus den rekonstruierten Logs):

| Zeit | Ereignis | Beleg |
|---|---|---|
| 08:32:52 | RCON `/tp Dev 400.5 90 400.5` → `SoftBorder: clamped a TeleportCommand teleport of Dev from d=565.7 into R-2=450.0` → Landung (318.698, 90, 318.698) = Void | debug fd166 |
| 08:33:00 | Tod #1 (`Saved snapshot for Dev (reason: death)`) — Death-Screen "fell out of the world" (`gui.eclipse.death.cause.outOfWorld`) | latest fd163 |
| 08:34:05 | Respawn → `LimboGate: Dev gated to the ghost ship (pre-event)`; 08:34:13 inverse `moved too quickly`-Deltas = DeathFlow-`finishReturn` Deck→Arrival (beide Limbo) | fd163/fd166 |
| 08:57:37 | RCON `/tp Dev 400.5 …` **ohne** Clamp-Zeile: Dev stand in **Limbo** → `profileOf(limbo)==null` → Clamp-Early-Return; RCON-Quelle=Overworld ⇒ Cross-Dim-Tp mitten ins Void bei d=565 | fd166 |
| 08:57:45 / 08:59:14 | Tod #2 → Gate-Zeile #2 | fd163 |
| 09:08:17 | `clamped … from d=4242.6 into R-2=450.0` (Ziel 3000.5/127/3000.5, Beweis 2) → Fall, Screenshot-Frames zeigen Rim-/Höhlenkulisse statt Plattform | fd166 |
| 09:08:25 / 09:12:12 | Tod #3 → Gate-Zeile #3; 09:12:24 `/tp` aus Limbo (kein Clamp) landete Dev tatsächlich auf der Plattform (3000.5, 120.5) | fd163 |
| 09:18:43 | `clamped … d=4242.6` → Void-Fall | fd166 |
| 09:18:51 | Tod #4; Death-Screen bleibt offen bis 09:19:57 | fd163 |
| 09:19:10 | RCON-"Rettungs"-`/tp 3000.5` auf die **Leiche** → Clamp → `moved too quickly! 0.0,545.35,0.0` ⇒ Client-(Death-Cam-)Position war (318.698, ≈−424, 318.698), Server setzte die Leiche auf (318.698, 120.5, 318.698) → fiel erneut ⇒ die beobachtete "Respawn fallend bei 318.698, −387.76"-Position | fd166 |
| 09:19:41 | `/tp Dev -300.5 170.5 -300.5` (d=425 < 450, kein Clamp) → `moved too quickly! -619.198…,50.0,-619.198…` = exakt (−300.5−318.698, 170.5−120.5) — bestätigt Server-Position der Leiche bei 318.698/120.5 | fd166 |
| 09:19:57 | Klick "To the Railing" → echter Respawn → Gate-Zeile #4 (aufs Schiff); 09:19:58-09:20:00 sechs RCON-`/tp -300.5 …` ziehen ihn vom Schiff (DeathFlow bricht sauber mit `PHASE_CLEAR` ab, `DeathFlowHooks.java:265-270`); 09:20:00 `[DEV AUDIT] Rcon set Dev's Leben 2 -> 4` = Not-Rettung | fd163/fd166 |

Weitere Belege:

- `»taken by the dark«` = `gui.eclipse.death.cause.generic` (en_us.json:2041) — der Fallback-Flavor,
  wenn die msgId keinen eigenen Key hat; `»fell out of the world«` = `…cause.outOfWorld` (:2051).
- Exempt-Spam: 12 239 ד… beyond the overworld ring (d=4242.6, R=452.0) — exempt"-Zeilen in der
  Session (§1.3).
- `run/ops.json` = `[]` ⇒ `player.hasPermissions(2)` für Dev false ⇒ Clamp-"Operator-Bypass" wirkungslos.

---

## 3. Fix (chirurgisch, nur `src/main/java/dev/projecteclipse/eclipse/border/SoftBorder.java`)

### 3.1 Boden-sichere Clamp-Landung (B1) — `clampTeleport`

Vorher (Kern):

```java
double scale = maxR / dist;                               // maxR = R−2: Void-Säule!
event.setTargetX(state.getBorderCenterX() + dx * scale);
event.setTargetZ(state.getBorderCenterZ() + dz * scale);  // Y unverändert → freier Fall
```

Nachher (Kern): dieselbe Bodensuch-Logik wie `teleportInside` —

```java
double startR = maxR;
int stageOuter = stageOuterRadius(profile, state.getWorldStage(profile));
if (stageOuter > 0) {
    startR = Math.min(startR,
            Math.max(0.0D, stageOuter - (double) DiscTerrainFunction.RIM_REWRITE_MARGIN));
}
for (int step = 0; step <= GROUND_SEARCH_STEPS; step++) {
    double r = ...; int surfaceY = groundSurfaceYLoading(level, tx, tz);   // Sync-Chunk-Load!
    // zwei aufeinanderfolgende Nicht-Void-Säulen nötig (Rim-Crumble-Schutz), dann:
    event.setTargetX(tx); event.setTargetY(surfaceY); event.setTargetZ(tz);
    return;
}
// Fallback: World-Spawn-Oberfläche (nie Void), analog teleportInside.
```

- Start bei `min(R−2, stageOuter − RIM_REWRITE_MARGIN)` (heute r≈372): volle Terrain-Dicke
  garantiert (`DiscTerrainFunction.RIM_REWRITE_MARGIN`, Stage-Reproduzierbarkeits-Vertrag).
- **Y wird gesetzt** (Heightmap-Oberfläche) — kein freier Fall mehr.
- Neuer Helper `groundSurfaceYLoading`: lädt den Chunk **synchron** (`level.getChunk`) statt
  `getChunkNow`. Begründung: Der Clamp feuert einmal pro Kommando/Perle (nie per Tick), und die
  Landesäule ist typischerweise ungeladen — eine Heightmap-Abfrage auf ungeladenem Chunk liefert den
  Dimensionsboden (die `FogStormSites.pollFogSites`-min_y-Lektion, `StormRegistry.java:262-264`) und
  wäre exakt der Void-Drop, den der Fix verhindern soll. Der per-Tick-Pfad (`teleportInside`) behält
  bewusst `groundSurfaceY`/`getChunkNow`.

### 3.2 Creative/Spectator-Exemption auf ALLEN Pfaden (B3)

Neuer zentraler Helper `isBorderExempt(player)` (creative ∨ spectator), verwendet in:

- `clampTeleport` (neu: deckt `TeleportCommand`, `EnderPearl`, `ChorusFruit` zentral ab; der
  Operator-Bypass in `onTeleportCommand` bleibt zusätzlich bestehen),
- `onPlayerTick` (Exempt-Branch, semantisch unverändert — Spectator returnte schon früher),
- Vehicle-Eject-Schleife (`onEntityTick`; vorher nur `!isCreative()` — Spectator ergänzt) und
  `firstPlayerPassenger` (identische Semantik, jetzt eine Regel an einer Stelle).

### 3.3 Log-Hygiene (B4)

Exempt-DEBUG-Zeile jetzt über `LAST_EXEMPT_TRACE` ratenlimitiert: max. 1×/200 Ticks (10 s) pro
Spieler; Rückkehr in den Ring löscht den Eintrag (nächste Exkursion loggt sofort = Zustandswechsel);
Cleanup in `onPlayerLoggedOut` und `onServerStopped` (bestehendes Map-Hygiene-Muster).

### 3.4 Bewusst NICHT geändert (B2)

Death-Screen-Text und Respawn-Ziel stimmen überein (§1.4) — kein Eingriff in Lives-/Limbo-Pipeline,
keine Lang-Änderungen. Kein Refactoring des Border-Systems.

---

## 4. Beantwortung der Analysefragen

1. **Warum nicht auf dem Geisterschiff?** Er WAR dort (4/4 Gate-Zeilen). Die "fallend"-Beobachtung
   war die geklemmt-teleportierte Leiche vor dem Respawn-Klick bzw. der frisch Respawnte, der von
   den parallelen RCON-`/tp`s sofort wieder vom Schiff gezogen wurde (09:19:58-09:20:00).
2. **Welcher Pfad produziert Richtung×(R−Margin) und die Fall-Y?** `clampTeleport`
   (TeleportCommand-Event der RCON-`/tp`s): XZ = `center + dir×(R−2)` = 0.5+450/√2 = 318.698…,
   Y unverändert (127/120.5/90) → Fall. Keine Heightmap-Abfrage beteiligt — es gab schlicht **keine**
   Y-Auflösung (der verwandte Heightmap-auf-ungeladenem-Chunk-Fallstrick ist in `groundSurfaceY`
   bereits abgefangen und im neuen `groundSurfaceYLoading` per Sync-Load gelöst).
3. **Warum griff die Creative-Exemption nicht?** Sie existierte nur im Tick-/Vehicle-Pfad. Der
   Command-Clamp prüfte allein `hasPermissions(2)` der Ziel-Entity; Dev ist kein Op (RCON-Kommandos
   laufen mit Konsolen-Permission, vergeben sie aber nicht an den Ziel-Spieler).
4. **Bonus — Fall neben der Plattform in "Höhle mit Lava":** Der RCON-`/tp` auf (3000.5, 127) wurde
   auf (318.698, 127) geklemmt; die Frames zeigen die Rim-Zone (Taper/Höhlenanschnitte) am Ring,
   nicht (3000,3000). Die "moved too quickly"-Warnungen sind die 2680-Block-Differenz zwischen
   Client-Erwartung (3000er-Ziel bzw. alte Position) und geklemmter Server-Position. Es gibt keinen
   Snap-Pfad, der Creative im Tick bewegt — es war ausschließlich der Command-Clamp.

---

## 5. Restrisiken

1. **Cross-Dimension-Loch im Clamp (bestehend, unverändert):** `clampTeleport` prüft die
   **aktuelle** Dimension der Entity (`entity.level()`), nicht die Ziel-Dimension. Ein `/tp` aus
   Limbo in Overworld-Koordinaten außerhalb des Rings wird weiterhin nicht geklemmt (so landete Dev
   um 09:12:24 auf der 3000er-Plattform). Border-Integritäts-, kein Sicherheitsproblem; bewusst
   nicht angefasst (konservativer Scope).
2. **Sync-Chunk-Load im Clamp:** pro geklemmtem Teleport werden 1-2 (worst case wenige) Chunks
   synchron geladen. Auf dem Kommando-/Perlen-Pfad unkritisch; ein `/tp`-Spam-Angriff von Spielern
   ist durch Vanilla-Permissions (tp = Op) bzw. Perlen-Cooldown begrenzt.
3. **Perlen-Ergonomie:** Eine über den Ring geworfene Perle landet jetzt ggf. deutlich weiter innen
   (r≈372 statt 450) und auf der Oberfläche statt auf Wurf-Y — identische Philosophie wie der
   dokumentierte `teleportInside`-Pull, aber sichtbar andere Position als vorher (vorher: Tod).
4. **Leichen-Teleports:** `/tp` auf einen noch toten Spieler bleibt möglich (Vanilla-Verhalten) und
   wird jetzt boden-sicher geklemmt; die Death-Cam kann kurz "im Boden" stehen — kosmetisch.
5. **Pre-Event-`finishReturn`-Ziel:** pre-event ist `homePos` die Limbo-Arrival-Plattform (LimboGate
   läuft vor DeathFlowHooks) — gewollt/unschädlich, aber erwähnenswert, falls die Event-Reihenfolge
   je geändert wird.

---

## 6. Test-Empfehlung für die Live-Verifikation

Voraussetzung: neuer Build geladen (Server-Neustart durch den Hauptagenten — **nicht** durch diesen
Subagenten). Ring heute: Center (0.5, 0.5), R=452, stageOuter=440.

1. **Todesschleifen-Repro (vorher rot, nachher grün):** Testspieler (Survival, gamemode 0, kein Op)
   per RCON `/tp <name> 3000.5 127 3000.5`.
   - Erwartet mit Fix: Landung **auf festem Boden** bei ≈ (263.6, surfaceY, 263.6) (r≈372 auf der
     45°-Diagonale; Debug-Zeile `clamped a TeleportCommand teleport … onto ground at r=…`), kein
     Fall, kein Tod.
   - Gegenprobe alte Welt/alter Build: gleicher Befehl endete bei (318.698, 127, 318.698) im Void.
2. **Survival-Tod außerhalb + Respawn-Versprechen:** denselben Spieler außerhalb töten (z. B.
   `/kill` oder ins Void schubsen via `/tp <name> 500 200 500` — d=707, Clamp greift, also stattdessen
   direkt `/execute in minecraft:overworld run tp <name> 318.7 -100 318.7`). Nach Death-Screen-Klick:
   Spieler erscheint auf dem Geisterschiff (Gate-/Ship-Wake-Sequenz), Tür-Theater läuft, Rückkehr auf
   die Arrival-Plattform (pre-event). **Während des Schiff-Aufenthalts keine RCON-`/tp`s senden** —
   genau die haben im Incident die "nicht auf dem Schiff"-Fehldiagnose erzeugt.
3. **Creative-Exemption:** Creative-Spieler (kein Op) per RCON auf (3000.5, 127, 3000.5) →
   **kein** Clamp mehr, Ankunft exakt am Ziel (Plattform), keine `clamped`-Zeile.
4. **Perlen-Clamp:** Survival-Spieler nahe der Kante (z. B. r≈430) Perle nach außen werfen →
   Landung auf Boden ≤ r≈372, Slow-Falling nicht nötig, kein Void-Tod.
5. **Log-Hygiene:** Creative-Spieler > 10 min außerhalb des Rings stehen lassen → höchstens 1
   Exempt-DEBUG-Zeile pro 10 s; Wiedereintritt + erneuter Austritt loggt sofort wieder eine Zeile.
