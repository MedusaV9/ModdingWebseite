# WOAH-02 GRAVITATIONSBRUCH — Verdrahtung / geteilte Dateien (für den Hauptagenten)

Feature-Code lebt komplett in `dev.projecteclipse.eclipse.woah.gravityrift` (+ `…client`).
Dieses Dokument listet (a) die minimal-additiven Berührungen geteilter Dateien und
(b) die bewusst offen gelassenen Merge-Punkte.

## A. Geteilte Dateien — was geändert wurde (alles rein additiv, 0 Löschungen)

### 1. `woah/WoahFeatures.java` (die EINZIGE angefasste geteilte Datei)

- Nur ein Kommentar unter dem Anker `// --- WOAH-02 gravity rift: mod-bus
  registrations go here ---`: dieses Feature braucht KEINE Mod-Bus-Registrierungen
  (kein DeferredRegister; der Payload registriert sich über einen EIGENEN
  `RegisterPayloadHandlersEvent`-Subscriber in `GravityRiftPayloads` — das
  `DoorPayloads`/`ShardPayloads`/`EchoGrovePayloads`-Muster, `EclipsePayloads` bleibt
  unberührt; Game-Events via `@EventBusSubscriber`; Client-Rows/Lens-Post via
  `FMLClientSetupEvent` in den eigenen Registrar-Klassen).

### NICHT angefasst (bewusst)

- `worldgen/DiscMapDefaults.java` — die Landmark-Zeile
  `new DiscMapData.Landmark("eclipse:gravity_rift", -239, 167, 40, 4)` war bereits
  zentral eingetragen (Bambus-Dschungel-Ring). Alle Anker-Konstanten im Feature-Code
  (`GravityRiftZone.CENTER_X/CENTER_Z = −239/167`) folgen dieser Zeile.
- `network/fx/FxCues.java` — Cue-IDs entstehen in `GravityRiftCues` über das
  öffentliche `FxCues.cue("woah_gravity_…")`.
- `network/EclipsePayloads.java`, `EclipseMod.java`, `assets/eclipse/lang/*.json`,
  `assets/eclipse/sounds.json` — unberührt (Langdrop/Sounds-Ask siehe unten).

## B. Offene Merge-Punkte

1. **Langdrop**: `docs/plans_v3/langdrop/woah_gravity.json` (19 Keys en+de:
   1 Caption + 6 DevCommandDoc-Beschreibungen + 12 Dev-Command-Meldungen) muss in
   `assets/eclipse/lang/en_us.json` / `de_de.json` gemerged werden. Bis dahin
   rendern die Keys roh — kein Crash (`ServerLang.tr`-Fallback-Verhalten).
2. **Sounds-Ask**: `docs/plans_v3/wiring/woah_gravity_sounds.json` — es werden NUR
   Bestands-Sounds verwendet; ein optionaler dedizierter Hum-Bed
   (`eclipse:ambient.gravity_hum`) ist als deferred Row dokumentiert.
   `GravityRiftAmbience.resolveHum()` schaltet automatisch um, sobald die Row landet
   (bis dahin: `event.rift_drone` auf 0.75 re-pitched).
3. **Zentraler Build**: kein `./gradlew` gelaufen (Regel). Compile-Korrektheit über
   Repo-Signatur-Lesen + `javap` gegen die NeoForge-21.1.238-Jars verifiziert.

## C. Selbstregistrierende Einstiegspunkte (nichts zu verdrahten, nur zur Übersicht)

| Klasse | Bus/Event | Rolle |
|---|---|---|
| `GravityRiftService` | GAME `@EventBusSubscriber` (ServerTick/Login/Attack/…) | Stage-Listener, Zone-Attribute, Puls, Inversion, Selbstheilung |
| `GravityRiftPayloads` | MOD `RegisterPayloadHandlersEvent` + GAME `PlayerLoggedInEvent` (per-Methode-Routing, `bus=` deprecated in FML 4.0.43) | `S2CGravityRiftPayload` v1-Gruppe `v1woahgravity` |
| `GravityRiftDevCommands` | GAME `RegisterCommandsEvent` | `/dev woah gravity build/pulse/invert/orbitals/tp/status` (+ DevCommandDoc-Registry im `static{}`) |
| `client.GravityRiftFxRows` | MOD `FMLClientSetupEvent` (Dist.CLIENT) | 5 PhotonFxRegistry-Rows (3 Burst + 2 WINDOWED-Loop) |
| `client.GravityRiftLensFx` | GAME `ClientTickEvent.Post` (Dist.CLIENT) + `static{}`-Registrierung (StormVolumeFx-Seam) | Veil-Post `eclipse:gravity_lens` (FEATURE-Priorität, ≤140-Blöcke-Gate) |
| `client.GravityRiftAmbience` | GAME `ClientTickEvent.Post` (Dist.CLIENT) | Loop-Hysterese (Column 150/170, Motes 52/64) + Positional-Drone |
