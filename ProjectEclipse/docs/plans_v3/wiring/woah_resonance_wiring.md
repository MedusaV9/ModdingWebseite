# WOAH-04 RESONANZFELD — Verdrahtung / geteilte Dateien (für den Hauptagenten)

Feature-Code lebt komplett in `dev.projecteclipse.eclipse.woah.resonance` (+ `…client`).
Dieses Dokument listet (a) die minimal-additiven Berührungen geteilter Dateien und
(b) die bewusst offen gelassenen Merge-Punkte.

## A. Geteilte Dateien — was geändert wurde (alles rein additiv, 0 Löschungen)

### 1. `network/EclipsePayloads.java` (sanktionierte Ausnahme laut Plan)

- EINE `registrar.playToClient(...)`-Zeile für `S2CResonanceFieldPayload`
  (TYPE/STREAM_CODEC voll qualifiziert, kein neuer Import) direkt hinter der
  ScareCue-Zeile, plus der private Handler `handleResonanceField`, der lazy auf
  `woah.resonance.client.ResonanceFieldClient.handle(payload)` dispatcht (das
  Client-Klassenladen bleibt dem Payload-Thread-Kontext überlassen — exakt das
  ScareCue-Muster darüber).

### 2. `protection/LandmarkProtection.java` (sanktionierte Ausnahme laut Plan)

- Konstanten `RESONANCE_RADIUS = 52` / `RESONANCE_DEPTH = 24` + ein `Zone`-Eintrag in
  `buildZones` (Zylinder um den authored Anker `(−395, −30)`, Boden `surfaceY − 24`,
  Deckel offen) — Referenzhöhe deterministisch über
  `DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, …)`, KEIN SavedData-Zugriff im
  Zonen-Build (die Zone muss vor dem ersten Bau stehen).

### 3. `core/config/EclipseConfig.java` (zusätzliche geteilte Datei — minimal-additiv)

- Plan §8 verlangt den Flag `resonance.hint_glow`. Umsetzung OHNE Anfassen des
  `General`-Records: statisches Feld + Accessor `EclipseConfig.resonanceHintGlow()`,
  gelesen/geschrieben als optionales verschachteltes `"resonance": {"hintGlow": true}`
  Objekt in `general.json` (fehlt der Block, gilt `true`). Konsumiert von
  `ResonanceMelodyMachine.hintExpected` (LISTEN-Glow-Hint).

### 4. `veilfx/PhotonBridge.java` (zusätzliche geteilte Datei — minimal-additiv)

- Neue Überladung `spawnLoop(ResourceLocation, Vec3, SpawnOptions)` (13 Zeilen, neben
  der bestehenden positionsbasierten `spawnLoop`-Methode): Loops mit Executor-Rotation/
  -Scale — gebraucht für die Bahn-Loops (Yaw + Kantenlängen-Z-Scale) und die
  Aura-/Fern-Schaft-Loops (Kristallklassen-Scale). `allowMulti(true)` wird wie bei den
  anderen Loop-Startern erzwungen. Keine bestehende Signatur verändert.

### 5. `woah/WoahFeatures.java`

- Nur ein Kommentar unter dem Anker `// --- WOAH-04 resonance field: mod-bus
  registrations go here ---`: dieses Feature braucht KEINE Mod-Bus-Registrierungen
  (kein DeferredRegister; Payload über die sanktionierte EclipsePayloads-Zeile,
  Game-Events via `@EventBusSubscriber`, Client-Rows via `FMLClientSetupEvent` in der
  eigenen Registrar-Klasse).

## B. Offene Merge-Punkte

### 1. Lang-Keys (Lang-Dateien gesperrt)

- `docs/plans_v3/langdrop/woah_resonance.json` (en+de) in `assets/eclipse/lang/en_us.json`
  / `de_de.json` mergen. Ohne Merge zeigen Captions/Dev-Feedback rohe Keys — funktional,
  aber hässlich.

### 2. Sounds (sounds.json + EclipseSounds gesperrt)

- KEIN Merge nötig: alles ist live aus Vanilla (`NOTE_BLOCK_BELL` Holder-Overload +
  `AMETHYST_BLOCK_CHIME` etc.) + `eclipse:event.emerge` komponiert — Inventar in
  `docs/plans_v3/wiring/woah_resonance_sounds.json`. OPTIONALES Upgrade: die dort
  spezifizierte Row `ambient.crystal_voice` (+ .ogg); `ResonanceChoir.resolveVoice()`
  löst die Id bereits dynamisch auf und nimmt sie automatisch, sobald sie existiert
  (bis dahin: gepitchter `AMBIENT_LIMBO_LOOP`-Fallback, SanctumHum-Doktrin).

### 3. FxCues-Konsolidierung (optional)

- Die vier Cue-Ids leben in `woah/resonance/ResonanceCues` (via `FxCues.cue(…)`), weil
  `network/fx/FxCues.java` gesperrt war. Der Hauptagent KANN sie als
  `FxCues.CUE_RESONANCE_*` einziehen und `ResonanceCues` auf Delegation umstellen
  (Wire-Format identisch — reine Aufräumarbeit, kein Muss).

### 4. DiscMapDefaults

- BEWUSST keine Zeile: die Anlieferung läuft über das SkyLauncher-Self-Enqueue-Muster
  (`ResonanceFieldService.maybeEnqueue`, 100-t-Poll, Stage ≥ 5, idempotent gegen
  `StructurePendingRegistry.wasPlaced`/pending) — Plan §2.2. Nichts zu mergen.
