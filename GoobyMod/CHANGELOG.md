# Changelog — Gooby Mod

## 5.2.0 „Begleiter-Deluxe" / “Companion Deluxe” (2026-08-16)

### Engineering (DE)

- Premium-Entity-Texturen: `scripts/gen_entity_textures.py` malt die fünf
  Entity-Sheets (classic, cream, cocoa, spotted, baby) deterministisch direkt
  aus den Runtime-Geometrien — gerichtete Fellsträhnen, Kanten-AO,
  Face-abhängiges Licht, Rim-Highlights und organisch gewachsene Flecken.
  `gen_textures.py` fasst `textures/entity/` bewusst nie mehr an;
  `validate_assets.py` prüft Geos, Clips, UVs, Texturen und
  `.bbmodel`-Konsistenz fail-closed. Blockbench-Quellen unter
  `assets_src/blockbench/` entstehen synchron über `scripts/gen_bbmodel.py`,
  eine Blender-Referenz liegt unter `assets_src/blender/`.
- Walk/Run-Lokomotion: `GoobyLocomotion` wählt den Gang deterministisch über
  geglättete Blocks/Tick mit Hysterese (Walk-Enter 0,04 / -Exit 0,02,
  Run-Enter 0,204 / -Exit 0,196), sodass Follow-Tempo im Walk- und
  Panik-/Zulauf-Tempo im Run-Band liegt. Walk-/Run-Clips existieren für
  Adult- UND Baby-Geometrie; `GoobyLocomotionTests` decken die Bänder ab.
- Begleiter-HUD & Screen-FX: `GoobyCompanionHud` rendert eine kompakte Karte
  des nächsten eigenen Goobys (Name, Mood-Glyphe, Pfeifkommando, Lebens- und
  Zufriedenheitsbalken) rein aus bereits synchronisierter Entity-Data — kein
  zusätzliches Networking. Auto-Fade nach Inaktivität; versteckt hinter
  Screens, Debug-Overlay und F1. `GoobyScreenEffects` zeichnet Kuschel-
  Vignette und Alarm-Puls shaderfrei über GUI-Quads; `GoobyCameraShake`
  bleibt über `screenFx.cameraShake` UND `reducedMotion` abschaltbar.
- Config-Screen: `GoobyConfigScreen` (Mod-Liste → Config) editiert auf einem
  `GoobyConfigDraft` — Fertig speichert atomar, Abbrechen/Esc fragt bei
  ungespeicherten Änderungen nach. Live-Vorschau der Begleiter-Karte inkl.
  GUI-Scale-abhängiger Offset-Klammerung; neue Client-Keys
  `companionHud.showCompanionHud`/`companionHudOffsetX`/`companionHudOffsetY`
  und `screenFx.screenEffects`/`cameraShake`.
- Content-Welle: `NutellaToastItem` (7 Hunger / 9,1 Sättigung, 10 s
  Schnelligkeit I), Knopfauge (2× aus Goldnuggets + Honigwabe),
  `GoobyPlushieBlock` (Knuddel-Quietschen samt Herzchen, dämpft Landungen wie
  Gooby-Wolle) und wasserloggbare `GoobyStatueBlock` mit nächtlichem
  Ehrenfunke plus Advancement „In Stein gemeißelt".
- Sichere Garderoben-Persistenz: `GoobyWardrobe` hält serverseitig den VOLLEN
  ItemStack inkl. DataComponents und speichert ihn verlustfrei nach NBT.
  Alte Wire-String-Saves migrieren automatisch; nicht parsebares
  Fremd-Mod-Slot-NBT wird wörtlich konserviert und wieder ausgegeben.
  `reconcile()` heilt abgeschnittene oder inkonsistente Sync-Werte.
- Worldgen-Welle: Der Gooby-Bau expandiert zum echten Mehrteile-Jigsaw
  (Tunnel gerade/Ecke, kleine Kammer, Vorratskammer mit eigenem Pantry-Loot,
  Terminator-Kappen samt Template-Pools). Neu ist die oberirdische
  Picknick-Begegnung `goobymod:gooby_picnic` (Structure-Set, Biome-Tag
  `#goobymod:has_gooby_picnics`, eigener Loot mit Toast, Plüschtier und
  Blumenkranz). `scripts/validate_worldgen.py` prüft die Datenkette
  Structure→Set→Pool→NBT→Loot fail-closed; ein GameTest assembelt den Bau
  mit dem echten `JigsawPlacement`-Placer.
- Neuer Custom-Payload-Layer (`goobymod:trick_menu` S2C, `goobymod:trick_select`
  C2S): Codecs hart gebounded und fail-closed, komplette serverseitige
  Autorisierung (Besitz, Erwachsenenstatus, Dimension, Distanz, Trainingsstand)
  in `GoobyNetwork.trySelectTrick`. Der Sneak-Luftpfiff öffnet den nativen
  Trick-Auswahlbildschirm; Clients ohne Payload-Kanal erhalten das klickbare
  Chat-Menü als Fallback. Menü-Öffnung UND Auswahl gelten bis **64 Blöcke**
  Entfernung (`GoobyNetwork.TRICK_MENU_RANGE`).
- Zwei neue Kunststücke ROLL und DANCE: Enum append-only, name-keyed NBT —
  alte Vier-Trick-Saves laden verlustfrei, neue Tricks starten bei null
  Sternen. `trick_roll` rotiert geometrisch korrekt um die Körpermitte
  (Root-Lift kompensiert den Bodenpivot exakt), Anticipation und weiche
  Landung bleiben erhalten; Runtime-JSON und Blockbench-Quelle werden per
  `scripts/gen_bbmodel.py` synchron gehalten.
- Neuer Geometrie-GameTest (`GoobyAnimationGeometryTests`) sampelt ALLE
  Animations-Clips hierarchisch gegen Adult- UND Baby-Geometrie
  (Easing-Kurven, Vorzeichen-agnostisch): Voll-Überschläge müssen die
  kompletten Bounds über dem Boden halten, kein Clip darf praktisch komplett
  im Boden verschwinden — Unterboden-Rollen werden künftig rot.
- Trick-Screen: Statuszeilen strikt auf Kartenbreite geklammert (Scrolltext
  statt Überlauf), „Aktiv" zeigt ausschließlich den serverseitig bestätigten
  Stand, die unbestätigte Wahl heißt „Ausgewählt" (Cancel/Esc kann nie eine
  falsche Aktiv-Aussage hinterlassen). Initialfokus läuft über den
  parameterlosen `setInitialFocus()`-Hook, damit Tastatur/Narrator exakt auf
  der aktiven Karte starten. Gesperrte Karten bleiben bewusst nicht
  auswählbar; ihr Tooltip erklärt, dass Sneak+Trainingshappen das
  Trainingsziel durchschaltet.
- Handbuch (Buchseiten + Kapitel 3) und Pfeifen-Tooltip auf sechs
  Kunststücke, den nativen Bildschirm und die 64-Block-Reichweite
  aktualisiert; alle neuen Lang-Keys DE/EN paritätisch.
- Fetch-Welle: `GoobyBallItem` wirft GENAU einen Ball als `ItemEntity` mit
  Besitzer-Signatur in den PersistentData (überlebt Chunk-Reload, liegt nie
  im ItemStack — aufgehobene Bälle sind wieder normale Wurf-Items).
  `GoobyFetchGoal` apportiert ausschließlich Bälle des eigenen Besitzers,
  hält den Trage-Zustand synced + NBT-persistent über Chunk-/Server-Reloads
  und blacklistet unerreichbare Bälle zeitlich begrenzt und hart gebounded —
  keine Endlos-Pathfinding-Schleifen. Rezept (2× aus Schleimball + Faden +
  Gooby-Fussel) und Advancement „Apport!".
- Audio-Ausbau: Die vollsynthetische, deterministische Bibliothek
  (`scripts/gen_sounds.py`, numpy → WAV → ffmpeg/libvorbis) wächst auf
  91 OGG-Clips mit Drei-Varianten-Pools für alle Kernereignisse.
  `docs/audio_manifest.json` + `gen_sounds.py --verify` bilden ein
  fail-closed Audio-Gate (SHA-256-Manifest, Container, Lautheit), Details in
  `docs/AUDIO.md`; `GoobyAudioExpansionTests` prüfen Registry und Pools.
- Explorer-Outfit: Blumenkranz (HEAD über `#goobymod:gooby_hats`), färbbares
  Abenteuer-Halstuch (NECK, `minecraft:dyeable` + Item-Tint) und
  Picknick-Rucksack (BACK) laufen über denselben serverautoritativen
  `tryEquipAccessory`-Pfad wie die bestehende Garderobe (Policy-Gates,
  Swap-Drop inkl. Tascheninhalt, volle DataComponents). Set-Advancement
  „Bereit fürs Abenteuer", handmodellierte 3D-Itemmodelle plus
  Blockbench-Quellen.
- Eigene Partikel: `ConfettiParticle`, `FluffPuffParticle` und
  `MusicNoteParticle` mit über `scripts/gen_particle_textures.py --check`
  verifizierten, deterministisch generierten Sheets;
  `GoobyParticleWaveTests` decken Registrierung und Assets ab.
- Root-CI: `.github/workflows/gooby-mod.yml` ist das fail-closed Gate für
  alle Mod-Änderungen (genestete Workflows unter `GoobyMod/.github/` führt
  GitHub nicht aus) — Audio-Gate, Asset-/Worldgen-Validatoren, Python-Tests,
  Release-Gate, Gradle-Build und GameTests. Jars werden nur als
  Workflow-Artefakt hochgeladen, nie ins Repo committet.
- Release-Gate: `scripts/release.py --check-only` verlangt jetzt zusätzlich
  die versionierte CHANGELOG-Sektion (neben README, PATCHNOTES, allen vier
  Handbüchern und der DE/EN-Sprachparität).
- Suite: 203 Kernsuite-GameTests (`runGameTestServer`), dazu 3 isolierte
  Create-Tests (`-PwithCreate`) und die separate Soak-Suite (`-PwithSoak`).

### Engineering (EN)

- Premium entity textures: `scripts/gen_entity_textures.py` deterministically
  paints all five entity sheets (classic, cream, cocoa, spotted, baby)
  directly from the runtime geometries — directional fur strands, edge
  ambient occlusion, face-dependent lighting, rim highlights, and organically
  grown spots. `gen_textures.py` deliberately never touches
  `textures/entity/` anymore; `validate_assets.py` gates geos, clips, UVs,
  textures, and `.bbmodel` consistency fail-closed. Blockbench sources
  (`assets_src/blockbench/`) stay in sync via `scripts/gen_bbmodel.py`, with
  a Blender reference under `assets_src/blender/`.
- Walk/run locomotion: `GoobyLocomotion` picks the gait deterministically
  from smoothed blocks/tick with hysteresis (walk enter 0.04 / exit 0.02,
  run enter 0.204 / exit 0.196), placing follow speed inside the walk band
  and panic/tempt speed inside the run band. Walk/run clips exist for the
  adult AND baby geometry; `GoobyLocomotionTests` cover the bands.
- Companion HUD & screen FX: `GoobyCompanionHud` renders a compact card for
  the nearest own tamed Gooby (name, mood glyph, whistle command, health and
  satisfaction bars) purely from already-synchronized entity data — no extra
  networking. It auto-fades after inactivity and hides behind screens, the
  debug overlay, and F1. `GoobyScreenEffects` draws the cuddle vignette and
  alarm pulse shader-free through GUI quads; `GoobyCameraShake` stays
  disableable via `screenFx.cameraShake` AND `reducedMotion`.
- Config screen: `GoobyConfigScreen` (mod list → Config) edits on a
  `GoobyConfigDraft` — Done saves atomically, Cancel/Esc confirms when
  changes are unsaved. Live preview of the companion card including
  GUI-scale-dependent offset clamping; new client keys
  `companionHud.showCompanionHud`/`companionHudOffsetX`/`companionHudOffsetY`
  and `screenFx.screenEffects`/`cameraShake`.
- Content wave: `NutellaToastItem` (7 hunger / 9.1 saturation, 10 s Speed I),
  Button Eye (2× from gold nuggets + honeycomb), `GoobyPlushieBlock`
  (squeeze squeak with hearts, cushions landings like Gooby Wool), and the
  waterloggable `GoobyStatueBlock` with a nightly honor sparkle plus the
  “Set in Stone” advancement.
- Safe wardrobe persistence: `GoobyWardrobe` keeps the FULL server-side
  ItemStack including data components and persists it losslessly to NBT.
  Legacy wire-string saves migrate automatically; slot NBT that fails to
  parse (removed third-party mod) is preserved verbatim and re-emitted.
  `reconcile()` heals truncated or inconsistent sync values.
- Worldgen wave: the Gooby burrow expands into a true multi-piece jigsaw
  (straight/corner tunnels, small den, pantry with its own loot table,
  terminator caps with template pools). New above-ground picnic encounter
  `goobymod:gooby_picnic` (structure set, biome tag
  `#goobymod:has_gooby_picnics`, dedicated loot with toast, plushie, and
  flower crown). `scripts/validate_worldgen.py` gates the
  structure→set→pool→NBT→loot data chain fail-closed; a GameTest assembles
  the burrow with the real `JigsawPlacement` placer.
- New custom payload layer (`goobymod:trick_menu` S2C, `goobymod:trick_select`
  C2S): codecs hard-bounded and fail-closed, full server-side authorization
  (ownership, adult status, dimension, distance, training level) in
  `GoobyNetwork.trySelectTrick`. The sneak air-whistle opens the native trick
  selection screen; clients without the payload channel fall back to the
  clickable chat menu. Opening the menu AND selecting are valid up to
  **64 blocks** (`GoobyNetwork.TRICK_MENU_RANGE`).
- Two new tricks, ROLL and DANCE: enum append-only, name-keyed NBT — old
  four-trick saves load losslessly and the new tricks start at zero stars.
  `trick_roll` now rotates geometrically around the body center (the root
  lift compensates the ground-level pivot exactly) while keeping anticipation
  and the soft landing; runtime JSON and the Blockbench source stay in sync
  via `scripts/gen_bbmodel.py`.
- New geometry GameTest (`GoobyAnimationGeometryTests`) samples ALL animation
  clips hierarchically against the adult AND baby geometry (easing curves,
  sign-agnostic): full flips must keep the complete bounds above ground and
  no clip may effectively vanish below the floor — under-floor rolls now
  fail red.
- Trick screen: status rows are strictly clamped to card width (scrolling
  text instead of overflow), “Active” exclusively reflects the server-side
  confirmed state while the unconfirmed pick reads “Selected” (Cancel/Esc can
  never leave a false active claim). Initial focus goes through the
  parameterless `setInitialFocus()` hook so keyboard/narrator users start on
  the active card. Locked cards deliberately stay unselectable; their tooltip
  explains that sneak-using Training Treats cycles the training target.
- Handbook (book pages + chapter 3) and the whistle tooltip now cover six
  tricks, the native screen, and the 64-block range; all new language keys
  are DE/EN paritous.
- Fetch wave: `GoobyBallItem` throws EXACTLY one ball as an `ItemEntity`
  carrying the owner signature in persistent data (survives chunk reload,
  never lives in the ItemStack — picked-up balls are ordinary throwables
  again). `GoobyFetchGoal` only fetches balls thrown by the Gooby's own
  owner, keeps the carry state synced + NBT-persistent across chunk/server
  reloads, and time-blacklists unreachable balls with hard bounds — no
  endless pathfinding loops. Recipe (2× from slime ball + string + Gooby
  Fluff) and the “Fetch!” advancement.
- Audio expansion: the fully synthetic deterministic library
  (`scripts/gen_sounds.py`, numpy → WAV → ffmpeg/libvorbis) grows to 91 OGG
  clips with three-variant pools for every core event.
  `docs/audio_manifest.json` + `gen_sounds.py --verify` form a fail-closed
  audio gate (SHA-256 manifest, container, loudness), documented in
  `docs/AUDIO.md`; `GoobyAudioExpansionTests` verify registry and pools.
- Explorer outfit: Flower Crown (HEAD via `#goobymod:gooby_hats`), dyeable
  Adventure Bandana (NECK, `minecraft:dyeable` + item tint), and Picnic
  Backpack (BACK) run through the same server-authoritative
  `tryEquipAccessory` path as the existing wardrobe (policy gates, swap drop
  including satchel contents, full data components). Set advancement
  “Ready for Adventure”, hand-modeled 3D item models plus Blockbench sources.
- Custom particles: `ConfettiParticle`, `FluffPuffParticle`, and
  `MusicNoteParticle` with deterministically generated sheets verified via
  `scripts/gen_particle_textures.py --check`; `GoobyParticleWaveTests` cover
  registration and assets.
- Root CI: `.github/workflows/gooby-mod.yml` is the fail-closed gate for all
  mod changes (GitHub does not execute nested workflows under
  `GoobyMod/.github/`) — audio gate, asset/worldgen validators, Python
  tests, release gate, Gradle build, and GameTests. Jars are only uploaded
  as workflow artifacts, never committed back into the repo.
- Release gate: `scripts/release.py --check-only` now additionally requires
  the versioned CHANGELOG section (alongside README, PATCHNOTES, all four
  manuals, and DE/EN language parity).
- Suite: 203 core-suite GameTests (`runGameTestServer`), plus 3 isolated
  Create tests (`-PwithCreate`) and the separate soak suite (`-PwithSoak`).

## 5.1.0 „Interaktions-Politur" / “Interaction Polish” (2026-08-13)

### Engineering (DE)

- `handleBareHandInteraction` fordert Kunststücke nur noch an, wenn
  `canPerformSelectedTrickFor()` wahr ist — Klickspam-Streicheln erzeugt keine
  Absagen mehr. `GoobyRandomSitGoal.canContinueToUse()` prüft das Sitz-Flag,
  damit externe `wakeUp()`-Aufrufe die MOVE/JUMP-Flags sofort freigeben.
- Leere Haupthand reicht per `PASS` an Pflegeitems in der Zweithand durch
  (`isCareItem()`). `isOpenToPlayers()` blockt Streichel-Bitten und Begrüßungen
  scheuer wilder Goobys. `denyInteraction()` vereinheitlicht Absage-Sound und
  Actionbar-Nachricht; Bürsten-/Such-Cooldowns zeigen Restsekunden.
- Baby-Textur wird direkt aufs Baby-UV-Layout gemalt; Loop-Keyframes von
  `baby_hop`/`greeting_bounce` versiegelt; Garderoben-Geos mit korrekter
  Texturgröße; drei neue Lang-Keys DE+EN.
- Sechs neue Regressions-GameTests (118 gesamt) plus eigener
  `goobymod_soak`-Namespace: 12.000-Tick-Soak mit 12 Goobys und zwei
  FakePlayern unter Dauerinteraktion; zusätzlich 9,5-Minuten-Wall-Clock-Soak
  mit 20 Goobys auf dem Dedicated-Server via RCON.

### Engineering (EN)

- `handleBareHandInteraction` only requests tricks when
  `canPerformSelectedTrickFor()` holds — pet click-spam no longer produces
  refusals. `GoobyRandomSitGoal.canContinueToUse()` checks the sitting flag so
  external `wakeUp()` calls release the MOVE/JUMP flags immediately.
- An empty main hand passes through to offhand care items via `PASS`
  (`isCareItem()`). `isOpenToPlayers()` gates pet requests and greetings of
  shy wild Goobys. `denyInteraction()` unifies denial sound plus action-bar
  message; brush/seek cooldowns display remaining seconds.
- The baby texture is painted directly onto the baby UV layout; loop keyframes
  of `baby_hop`/`greeting_bounce` sealed; wardrobe geos declare correct
  texture sizes; three new DE+EN language keys.
- Six new regression GameTests (118 total) plus a dedicated `goobymod_soak`
  namespace: a 12,000-tick soak with 12 Goobys and two FakePlayers under
  constant interaction; additionally a 9.5-minute wall-clock soak with 20
  Goobys on the dedicated server via RCON.

## 5.0.2 „Ausdauernd" / “Endurance” (2026-08-12)

### Engineering (DE)

- Alle UUID-basierten Session-/Partner-Maps besitzen neben TTL feste Limits;
  Logout entfernt Spielersitzungen sofort. NBT-Laden begrenzt Freundschaften,
  Erinnerungen, Sozialcooldowns und Ritualhistorien bereits beim Einlesen.
- `GoobySocialGoal` behält aktive Aktionen korrekt und wählt autonom auch
  Fangspiel; der Hasen-Fauna-Scan läuft höchstens einmal pro Sekunde.
- Statische Sound-Buckets sind echtes Access-LRU, serversitzungsgebunden und
  robust gegen Zeitrücksprünge. Entity-/BlockEntity-Syncstrings sind begrenzt.
- Zwölf Recipe-Book-Advancements, sechs DE+EN-Tooltip-Keys und vier neue
  Regressions-GameTests schließen den Release-Pass.

### Engineering (EN)

- Every UUID-keyed session/partner map now has a hard limit in addition to TTL;
  logout releases player sessions immediately. NBT loading bounds friendship,
  memory, social-cooldown, and ritual collections as entries are read.
- `GoobySocialGoal` now retains active actions correctly and autonomously
  selects play chase; the rabbit fauna scan runs at most once per second.
- Static sound buckets are true access-LRU, scoped to one server session, and
  robust to time rollback. Entity/block-entity sync strings are bounded.
- Twelve recipe-book advancements, six DE+EN tooltip keys, and four new
  regression GameTests complete the release pass.

## 5.0.0 „Hochglanz" / “Grand Polish LTS” (2026-08-11)

### Engineering (DE)

- `de.sonic0810.goobymod.api` friert `GoobyAccessor`, drei abgeschlossene
  Lifecycle-Events, Hut-Tag und fail-fast Sprachpool-Registry für 5.x ein.
- Eigenes Acht-Kapitel-`Screen` rendert zwölf scriptgenerierte Illustrationen
  und ein Frame-animiertes Titelportrait; 16 lokalisierte Buchseiten bleiben
  als Datenkomponenten-Fallback.
- Client-Config steuert Reduced Motion/High Contrast. Renderer markiert echte
  Frames; der Micro-Controller pausiert nach zwei nicht gerenderten Ticks oder
  24 Blöcken. Periodischer Sound nutzt begrenzte Dimension/Chunk/Event-Buckets.
- Access-order-`LinkedHashMap` hält 32 Besucher plus Besitzer und persistiert
  diese LRU-Reihenfolge. Fünf neue GameTests prüfen API, NBT-Cap, Speech-Hooks,
  Accessibility/Assets und Sound-Coalescing.

### Engineering (EN)

- `de.sonic0810.goobymod.api` freezes `GoobyAccessor`, three completed-state
  lifecycle events, the hat tag, and fail-fast speech-pool registry for 5.x.
- A custom eight-chapter `Screen` renders twelve script-generated illustrations
  and a frame-animated cover portrait; sixteen localized written-book pages
  remain as a data-component fallback.
- Client config controls Reduced Motion/High Contrast. The renderer marks real
  frames; the micro controller suspends after two unrendered ticks or 24
  blocks. Periodic sound uses bounded dimension/chunk/event buckets.
- An access-order `LinkedHashMap` retains 32 visitors plus owner and persists
  that LRU order. Five new GameTests cover API, NBT cap, speech hooks,
  accessibility/assets, and sound coalescing.

## 4.3.0 „Schatzsucher" / “Treasure Trails” (2026-08-11)

### Engineering (DE)

- `GoobyEntity` besitzt ein persistentes Vier-Slot-`SimpleContainer`; das
  Entity-Menu löst per ID auf und prüft Besitz, Distanz und ausgerüstete Tasche.
- Eine einmalige, kugelbegrenzte 24-Block-Suche gleicht Cozy-Ziele bzw.
  config-aktivierte Erze ab. Ziel und Cooldown sind NBT-sicher; Navigation,
  Pfotenspur und Marker bleiben serverautoritativ.
- Geschenk-Commit verbraucht die Ladung genau einmal: entfernte Empfänger
  erhalten einen atomaren Satchel-Insert, sonst einen UUID-priorisierten
  `ItemEntity`-Drop mit tickgenauem 200-Tick-Ablauf.
- 5-%-BEST_FRIEND-Scraps, Karte, eigener Structure-Tag/Jigsaw-Cache/Loot,
  drei GeckoLib-Clips, zwei Sounds, DE+EN und sechs GameTests bilden den Loop.

### Engineering (EN)

- `GoobyEntity` owns a persistent four-slot `SimpleContainer`; its entity menu
  resolves by ID and validates owner, distance, and equipped satchel.
- One spherical bounded 24-block scan matches cozy targets or config-enabled
  ores. Target and cooldown are save-safe; navigation, paw trail, and marker
  remain server-authoritative.
- Gift commit spends exactly one charge: distant recipients get one atomic
  satchel insertion, otherwise one UUID-prioritized `ItemEntity` drop whose
  ownership expires after exactly 200 ticks.
- Five-percent Best-Friend scraps, resolving map, tagged jigsaw cache/loot,
  three GeckoLib clips, two sounds, DE+EN, and six GameTests complete the loop.

## 4.2.0 „Soziale Goobys" / “Gooby & Friends” (2026-08-11)

### Engineering (DE)

- `GoobySocialGoal` läuft auf Priorität 13. Synchronisierte Action-Bytes und
  Partner-UUID bilden Begrüßungs-Handshake/Fangspiel; beide Seiten besitzen
  denselben persistenten 6000-Tick-Paarcooldown.
- Server-Emote-Memory erkennt zwei Schleich-Presses in 20 Ticks bzw. drei
  Sprünge in 40 Ticks. Zustands-/Kommandogates verhindern False-Movement.
- Schlafmagnetismus ergänzt `GoobySleepGoal`; ein 3er-Haufen vergibt
  `group_nap`. Clientseitige Huddle-Auswahl verschmilzt Zzz deterministisch.
- Der Renderer cached Bubble-Lebenszyklen für Pop-in/out, staffelt per Entity-ID,
  richtet den Tail und rendert Text über `goobymod:icons` mit Default-Referenz.

### Engineering (EN)

- `GoobySocialGoal` runs at priority 13. Synchronized action bytes and partner
  UUIDs form greeting/chase handshakes; both sides keep the same persistent
  6000-tick pair cooldown.
- Server emote memory recognizes two sneak presses in 20 ticks or three jumps
  in 40 ticks. State/command gates prevent movement false positives.
- Nap magnetism extends `GoobySleepGoal`; a three-Gooby huddle grants
  `group_nap`. Client huddle selection deterministically merges Zzz particles.
- The renderer caches bubble lifecycles for pop-in/out, staggers by entity ID,
  aims the tail, and renders through `goobymod:icons` with default-font fallback.

## 4.1.0 „Wilde Welt" / “Out in the Wild” (2026-08-11)

### Engineering (DE)

- NeoForge-`add_spawns`-Biome-Modifier plus
  `RegisterSpawnPlacementsEvent` verbinden den Biome-Tag mit einem
  config-geschützten, seltenen Einzeltier-Spawn.
- `GoobyEntity` persistiert Naturursprung, Erstfütterung und Bau-Bewohnerstatus.
  Nur ungezüchtete Naturtiere dürfen despawnen; alle Spieler-/Strukturpfade
  setzen Persistenz. Scheu-AI, Wildruf, Pfoten und Bau-Fund laufen serverseitig.
- Der Bau verwendet `minecraft:jigsaw`, Template-Pool, Structure-Set und
  reproduzierbar generiertes NBT mit Loot-Truhe und persistentem Gooby.
- `DugDirtBlock` ist kollisionslos und entfernt sich nach 2400 Ticks.
  Fauna-Ziele werden einmalig beim Entity-Join an Hasen/Katzen ergänzt;
  `GoobyAlertGoal` erkennt zusätzlich wilde Wölfe.

### Engineering (EN)

- A NeoForge `add_spawns` biome modifier plus
  `RegisterSpawnPlacementsEvent` connects the biome tag to a config-gated,
  rare single-creature spawn.
- `GoobyEntity` persists natural origin, first feeding, and burrow residency.
  Only unassociated natural creatures may despawn; every player/structure path
  requires persistence. Shy AI, wild calls, paws, and discovery are server-led.
- The burrow uses `minecraft:jigsaw`, a template pool, structure set, and
  reproducibly generated NBT containing a loot chest and persistent Gooby.
- `DugDirtBlock` has no collision and removes itself after 2400 ticks. Fauna
  goals are attached once when rabbits/cats join; `GoobyAlertGoal` also sees
  untamed wolves.

## 4.0.0 „Create-Express" / “Create Express” (2026-08-11)

### Engineering (DE)

- `CreateCompat` bleibt der importfreie Guard/Fallback; ausschließlich
  `CreateBridge` referenziert typisiert Create 6.0.10. `CreateRetryPolicy`
  trennt `TRANSIENT` mit drei 1/2/4-Tick-Retries von
  `PERMANENT_API_MISMATCH`.
- Typisierte `SeatBlock`-Belegung, `AbstractContraptionEntity`-Passagierstatus
  und `KineticBlockEntity#getSpeed` ersetzen Stringheuristiken. Montage/
  Demontage, Bewegungserkennung, Zugpfiff-Schutz, Ankunfts-Bubbles und
  600-Tick-Maschinenkomfort laufen serverautoritativ.
- Bedingte `create:mixing`-/`create:filling`-Rezepte, leeres Glas samt
  Vanilla-Rezept/Item/Texture/Tooltips, zwei GeckoLib-Clips und zwölfseitiges
  DE+EN-Handbuch bilden den Spielerpfad.
- Default-CI bleibt Create-frei; `modjar-create.yml` startet mit dem offiziellen
  Create-/Ponder-/Flywheel-/Registrate-Stack. 85 Default- und 3 isolierte
  Create-GameTests prüfen Dormanz, transienten Recovery, Recipe-Registrierung,
  Assets und den sicheren Headless-Fallback. Der versionsgebundene Sitzpfad
  bleibt auf NeoForges GameTestServer aus, weil Create 6.0.x dort den
  Passenger-/Netzwerk-Lebenszyklus nicht zuverlässig bereitstellt.

### Engineering (EN)

- `CreateCompat` remains the import-free guard/fallback; only `CreateBridge`
  has typed Create 6.0.10 references. `CreateRetryPolicy` separates
  `TRANSIENT` with three 1/2/4-tick retries from
  `PERMANENT_API_MISMATCH`.
- Typed `SeatBlock` occupancy, `AbstractContraptionEntity` passenger state,
  and `KineticBlockEntity#getSpeed` replace string heuristics. Assembly/
  disassembly, motion detection, train-whistle refusal, arrival bubbles, and
  600-tick machine comfort are server-authoritative.
- Conditional `create:mixing`/`create:filling` recipes, Empty Gooby Jar with
  vanilla recipe/item/texture/tooltips, two GeckoLib clips, and a twelve-page
  DE+EN handbook complete the player path.
- Default CI remains Create-free; `modjar-create.yml` boots the official
  Create/Ponder/Flywheel/Registrate stack. 85 default and 3 isolated Create
  GameTests cover dormancy, transient recovery, recipe registration, assets,
  and the safe headless fallback. The version-gated seat path stays disabled
  on NeoForge's GameTestServer because Create 6.0.x does not reliably provide
  its passenger/network lifecycle there.

## 3.9.0 „Mode & Fussel" / “Fashion Fluff” (2026-08-11)

### Engineering (DE)

- Drei `SynchedEntityData`-Strings bilden Head/Neck/Back; `GoobyWardrobe`
  codiert beim Schal zusätzlich RGB. Alle Slots und Caches besitzen NBT-
  Roundtrip und gemeinsames Drop-/Shear-Verhalten.
- `#goobymod:gooby_hats` ersetzt die Java-Itemmenge. Vanilla-`dyeable`,
  Curios-`charm` und 3D-Itemmodelle machen Hut-/Farb-/Compat-Verhalten
  datengetrieben und pack-erweiterbar.
- Ein Byte synchronisiert `GoobyCoatVariant`; ein persistenter Bitmask speichert
  permanente Freischaltungen. BEST_FRIEND-Brush-RNG, Vier-Fussel-Kauf und
  Owner-validiertes Sneak-Cycling sind serverautoritativ.
- Curios 9.5.1+ ist `compileOnly` und `ModList`-bewacht; ungenutztes Modrinth-
  Repository entfernt. Vier Items, drei Rezepte, drei Felltexturen, zwei
  Attachment-Geos, OGG, Advancement, DE+EN-Parität und 83 GameTests.

### Engineering (EN)

- Three `SynchedEntityData` strings implement head/neck/back;
  `GoobyWardrobe` additionally encodes scarf RGB. Every slot and render cache
  has NBT round-trip and unified drop/shear behavior.
- `#goobymod:gooby_hats` replaces the Java item set. Vanilla `dyeable`, Curios
  `charm`, and 3D item models make hat/color/compat behavior data-driven and
  pack-extensible.
- One byte synchronizes `GoobyCoatVariant`; a persistent bitmask stores
  permanent unlocks. BEST_FRIEND brush RNG, four-fluff purchase, and
  owner-validated sneak cycling are server-authoritative.
- Curios 9.5.1+ is `compileOnly` and `ModList`-guarded; the unused Modrinth
  repository is removed. Four items, three recipes, three coat textures, two
  attachment geos, OGG, advancement, DE+EN parity, and 83 GameTests.

## 3.8.0 „Gooby-Nachwuchs" / “Little Goobys” (2026-08-11)

### Engineering (DE)

- `NutellaItem` konvertiert Vanilla-Kuchen in einen tickenden
  `NutellaCakeBlock`; die server-thread-atomare Paarwahl prüft Tame, Adult,
  jeweilige Owner-FRIEND-Stufe und beidseitige persistente Cooldown-Leases.
- `GoobyEntity` persistiert Vanilla-Age plus Eltern-UUIDs, Familiennest und
  Partnerzeitpunkte. Der implementierte `getBreedOffspring` bleibt vom
  weiterhin falschen `isFood`-Pfad getrennt.
- `GoobyFollowParentGoal`, begrenztes Familien-Tag, Nest-Schlafplätze,
  Treat-Wachstumsboost sowie Baby-Gates für Follow/Pfeife/Reiten/Create/Hut/
  Training bilden den vollständigen Lebenszyklus.
- Safe-Follow-Teleports ergänzen die Zufallsstichprobe um einen vollständigen
  begrenzten Fallback und können auf offenem sicheren Boden nicht mehr würfeln.
- Eigenes Geo/Texture-Rendering bei 0,55 Scale, vier Clips, vier OGGs,
  Advancement, DE+EN-Parität und 77 GameTests.

### Engineering (EN)

- `NutellaItem` converts vanilla cake into a ticking `NutellaCakeBlock`; its
  server-thread atomic pair selection checks tame/adult state, each owner's
  FRIEND tier, and persistent cooldown leases on both parents.
- `GoobyEntity` persists vanilla age plus parent UUIDs, family nest, and
  partner timestamps. Implemented `getBreedOffspring` remains isolated from
  the deliberately false `isFood` path.
- `GoobyFollowParentGoal`, bounded family tag, nest sleep spots, treat growth
  boost, and baby gates for Follow/whistle/ride/Create/hat/training cover the
  full lifecycle.
- Safe-follow teleport retains randomized sampling with an exhaustive bounded
  fallback, eliminating chance failures on open safe ground.
- Dedicated geo/texture rendering at 0.55 scale, four clips, four OGGs,
  advancement, DE+EN parity, and 77 GameTests.

## 3.7.0 „Traumstall" / “Hutch, Sweet Hutch” (2026-08-11)

### Engineering (DE)

- `RabbitHutchBlockEntity` persistiert/synchronisiert Komfort 0–3,
  Resident-UUID/-Name, Occupant-UUID und atomaren Morgengeschenk-Tag.
- Blockstate-/Multipart-Modell koppelt offene richtungsabhängige Shapes mit
  drei Bettzeug-Overlays; ein BER rendert das UUID-gebundene Namensschild.
- `GoobySleepGoal` priorisiert gebundene Homes bis
  `home.duskTravelRadius`, reserviert Belegung, spielt Entry/Tight-Curl und
  übergibt morgens an die geskriptete Exit→Stretch→Trill→Owner-Sequenz.
- Sicherer Break-Eject, zustandsabhängiges Woll-Loot, Eingang-Zzz, zwei OGGs,
  drei Clips, vollständige DE+EN-Parität und 70 GameTests.

### Engineering (EN)

- `RabbitHutchBlockEntity` persists/synchronizes comfort 0–3, resident UUID
  and name, occupant UUID, and an atomic last-morning-gift day.
- Blockstate multipart rendering pairs open directional shapes with three
  bedding overlays; a block-entity renderer draws the UUID-bound nameplate.
- `GoobySleepGoal` prioritizes bound homes within
  `home.duskTravelRadius`, reserves occupancy, plays entry/tight curl, and
  hands dawn to a scripted exit→stretch→trill→owner sequence.
- Safe break ejection, state-driven wool loot, entrance Zzz, two OGGs, three
  clips, complete DE+EN parity, and 70 GameTests.

## 3.6.0 „Kunststücke" / “Tricks & Training” (2026-08-11)

### Engineering (DE)

- Persistente `EnumMap<GoobyTrick, proficiency>` mit Auswahl, 40-Tick-
  Trainingsgate, Drei-Sterne-Mastery, Doppelklick-Anforderung und NBT-Roundtrip.
- `GoobyWhistleItem` ruft den nächsten geladenen Owner-Gooby, verwendet ab 32
  Blöcken den gehärteten Safe-Teleport und speichert den Modus als Item-Komponente.
- Eigentümer-validiertes `/goobytrick`-Clickmenü und Vanilla-`WrittenBookItem`
  mit zehn clientlokalisierten Komponenten-Seiten plus persistentem Give-once.
- Fünf Action-Clips, zwei synthetisierte OGGs, zwei Items/Rezepte, zwei
  Advancements, vollständige DE+EN-Parität und 63 GameTests.

### Engineering (EN)

- Persistent `EnumMap<GoobyTrick, proficiency>` with selection, 40-tick
  training gate, three-star mastery, double-click request, and NBT round trip.
- `GoobyWhistleItem` calls the nearest loaded owned Gooby, uses hardened safe
  teleport beyond 32 blocks, and stores its remembered mode as item data.
- Owner-validated `/goobytrick` click menu and vanilla `WrittenBookItem` with
  ten client-localized component pages plus persistent give-once state.
- Five action clips, two synthesized OGGs, two items/recipes, two
  advancements, complete DE+EN parity, and 63 GameTests.

## 3.5.0 „Bande des Vertrauens" / “Bonds of Trust” (2026-08-11)

### Engineering (DE)

- Reine `FriendshipTier.of(int)`-Tabelle ersetzt verstreute Ride-/Gift-
  Konstanten; Tier-Crossings liefern atomar Animation, Jingle, Partikel,
  Bubble, Actionbar und persistente Zeitmarke.
- UUID-gebundene `FriendshipMemory`-NBTs für Firsts, Tier-Ups, Anniversary und
  täglichen Snuggle-Cooldown; alte Saves leiten Tiers ohne Migration ab.
- FRIEND-Tag-along, tierbasierte Greetings/Gifts/Ride-Gates, BEST_FRIEND-
  Snuggle mit Regeneration und Advancement.
- Begrenzter Owner-Chat-Namensscan, Goldherz-Partikel, drei Clips, zwei Sounds,
  vollständige DE+EN-Parität und 57 GameTests.

### Engineering (EN)

- Pure `FriendshipTier.of(int)` table replaces scattered ride/gift constants;
  tier crossings atomically emit animation, jingle, particle, bubble,
  actionbar, and persistent timestamp.
- UUID-bound `FriendshipMemory` NBT stores firsts, tier-ups, anniversary, and
  daily snuggle cooldown; old saves derive tiers without migration.
- FRIEND tag-along, tier greetings/gifts/ride gates, and BEST_FRIEND
  regeneration snuggle with advancement.
- Bounded owner-chat name scan, gold-heart particle, three clips, two sounds,
  complete DE+EN parity, and 57 GameTests.

## 3.4.0 „Wachsamer Gefährte" / “Streetwise Companion” (2026-08-11)

### Engineering (DE)

- Priorisierter `GoobyAlertGoal` mit 10-Tick-Scans, Creeper-Frühwarnradius,
  60-Tick-Hysterese, synchronisiertem Alert-Pose-State und Alarm-Telemetrie.
- Wetter-Shelter-/Behind-Owner-Navigation, trocknungsgebundener Shake-State und
  tageszeitabhängige Intervalle der bestehenden Idle-Goals.
- Wild-only `PanicGoal`, explizite Path-Mali sowie gehärtete Follow-/Danger-
  Teleports für Weltgrenze, Bauhöhe, Fluids, Kollisionen und Gefahrblöcke.
- Zwei Alarm-OGGs, Shake-Sound, vier Clips, DE+EN-Parität und 49 GameTests.

### Engineering (EN)

- Prioritized `GoobyAlertGoal` with 10-tick scans, creeper early-warning radius,
  60-tick hysteresis, synchronized alert pose state, and alarm telemetry.
- Weather shelter/behind-owner navigation, drying-bound shake state, and
  time-of-day intervals for existing idle goals.
- Wild-only `PanicGoal`, explicit path maluses, and hardened follow/danger
  teleports covering borders, build height, fluids, collisions, and hazards.
- Two alarm OGGs, shake sound, four clips, DE+EN parity, and 49 GameTests.

## 3.3.0 „Launen & Bedürfnisse" / “Moods & Needs” (2026-08-11)

- Synced/persistent six-state mood machine with 600-tick dwell, persistent
  feeding/owner-away inputs, readable particles/animations/speech, and
  shift-look actionbar inspection.
- Hungry-feed and lonely-pet bonuses; sleep-safe decay/request behavior.
- Four need-sound variants, three clips, full DE+EN i18n, 41 GameTests.

## 3.2.0 „Goobys Stimme" / “Voice of Gooby” (2026-08-11)

### Engineering (DE)

- 29 neue OGGs und echte Variant-Pools für alle Kern-Sounds; drei
  serverautoritativ ausgewählte Ambient-Moods.
- Client-lokaler `AbstractTickableSoundInstance`-Schnurr-Loop mit
  Petter-UUID-Bindung und Fade.
- Eindeutige Pfeifen-Sounds pro Kommando, Bürsten-Event, globale Config-Skala
  und zentrale ±10-%-Jitterung.
- Vanilla-Seitenlogik für `playSound` wiederhergestellt; vollständiger
  Subtitle-/Pool-Audit. Suite: 35 GameTests.

### Engineering (EN)

- 29 new OGG files and true variant pools for every core sound; three
  server-authoritatively selected ambient moods.
- Client-local `AbstractTickableSoundInstance` purr loop with petter UUID
  binding and fades.
- Distinct whistle sound per command, brush event, global config scale, and
  centralized ±10% jitter.
- Restored vanilla side handling for `playSound`; complete subtitle/pool
  audit. Suite: 35 GameTests.

## 3.1.0 „Lebenszeichen" / “Alive & Blinking” (2026-08-11)

### Engineering (DE)

- Allokationsfreier Micro-Controller mit unabhängigen Blink-, Schnupper- und
  Flavor-Timern; lokale Sound-Keyframes für Gähnen/Schnuppern.
- Deterministischer Plain-Java-Zustandsautomat hält Sit-/Stand- und
  Sleep-/Wake-Übergänge bis zum Clip-Ende.
- Server-autoritativer Landing-Squash für >2-Block-Fälle; Action-Cooldown
  verhindert Clip-Unterbrechung.
- Eyelid-Bones/Texturzeilen, geglättetes Head-Look, Bubble-LOS und 11 neue
  Animationsclips. Suite: 31 GameTests.

### Engineering (EN)

- Allocation-free micro controller with independent blink, sniff, and flavor
  timers; local sound keyframes for yawns/sniffs.
- Deterministic plain-Java state holder keeps sit/stand and sleep/wake bridges
  alive until clip completion.
- Server-authoritative landing squash for drops over two blocks; action
  cooldown prevents clip interruption.
- Eyelid bones/texture rows, eased head look, bubble LOS, and 11 new animation
  clips. Suite: 31 GameTests.

## 3.0.0 „Schienen & Schrauben" / “Release Rails” (2026-08-11)

### Engineering (DE)

- Schutzengel für gezähmte Goobys: Mob-Schaden abgefangen, synchronisierte
  Panik, druckbasierte Flucht zu Besitzer/Stall, konfigurierbar.
- Persistente UUID+Zeit-Lease im Nutella-Glas-BlockEntity ersetzt lokalen
  24-Block-Scan; chunk-sicher und nach 15 Minuten selbstheilend.
- Garantierter Hut-Drop im Death-Loot-Pfad, eigener `sad_whimper`-Soundpool,
  Zufriedenheits-Anti-Spam und serverseitige Reit-Hop-RNG.
- Nichtsolider Stall-Innenraum + präziser Schlafanker; animierter
  `hat_anchor` ersetzt festen Renderer-Offset.
- Release-Skript, DE/EN-Handbücher, CI-Concurrency/Filter und 26 GameTests.

### Engineering (EN)

- Guardian Angel for tamed Goobys: blocked mob damage, synchronized panic,
  pressure-based owner/hutch escape, and server configuration.
- Persistent UUID+time lease in a Nutella jar block entity replaces the local
  24-block scan; safe across chunk unloads with 15-minute self-healing.
- Guaranteed hat death drop, dedicated `sad_whimper` pool, satisfaction
  anti-spam, and server-only riding joy-hop RNG.
- Non-solid hutch interior with precise sleep anchor; animated `hat_anchor`
  replaces the renderer's fixed offset.
- Release helper, DE/EN manuals, CI concurrency/filtering, and 26 GameTests.

## 2.0.0 „Best Friends" (2026-08-10)

### Neue Features

- **Echte Zähmung & Besitz:** Nutella füttern zähmt wilde Goobys (Vanilla-
  TamableAnimal, Owner-UUID persistent); Hasen-Konversion zähmt sofort auf
  den Fütterer
- **Freundschaft 0–100 pro Spieler-UUID**, persistent: Streicheln (+2, mit
  5-s-Anti-Spam-Cooldown pro Spieler), Füttern (+8); Fortschritt als
  Actionbar-Anzeige; Herzchen-Moment + Advancement bei 100
- **Gooby-Pfeife** (2× Goldnugget + Faden + Fussel): schaltet für den
  BESITZER Wander → Follow → Stay durch; Fremde werden abgewiesen; Modus
  persistent; Follow nutzt das echte Vanilla-FollowOwnerGoal inkl. Teleport
- **Geschenk-System statt Endlos-Karotten:** Buddeln droppt nur noch dann
  etwas, wenn eine Geschenk-Ladung da ist (Kosten: 1 gefüttertes Nutella-
  Glas pro Ladung, max. 3), der Cooldown (Standard 5 min, konfigurierbar)
  abgelaufen ist und ein Freund (Freundschaft ≥ 50) in der Nähe ist;
  goldene Karotten nur für beste Freunde (≥ 90)
- **Hüte:** kleine Blumen als Hut aufsetzbar (nur Besitzer), via EntityData
  für ALLE Spieler sichtbar, persistent; Schere nimmt den Hut ab
- **Advancement-Baum:** Goobyologie (root) → Mein Gooby! (echter
  tame_animal-Trigger) → Beste Freunde / Gut erzogen / Gooby-Express /
  Buddel-Bote / Hutmode (DE/EN)
- **Server-Config** (synchronisiert): enableSpecialLines (Killswitch),
  specialLineChance, bubbleDistance, idleLineMin/MaxTicks,
  giftCooldownTicks, maxGiftCharges
- **Zuhause/Nest:** Gooby merkt sich seinen Hasenstall (persistent) und
  kehrt nachts dorthin zurück
- **Reit-Progression:** Reiten nur auf gezähmten Goobys (Besitzer immer,
  andere ab Freundschaft ≥ 30)

### Audit-Fixes (P0)

- Sophie-Special-Lines sind jetzt AUSSCHLIESSLICH kosmetisch: der
  Zufriedenheits-Sonderfall beim Schlagen wurde entfernt (identisch für
  alle Namen), die Blase rendert nur noch LOKAL beim passenden Spieler,
  Killswitch + Chance über die Config, keine Logs/Telemetrie; Regression-
  Tests gegen Fremdnamen-Matches (exakt, case-insensitive)
- Nutella-Glas-Spawn ist atomar: das Glas wird im selben Server-Tick VOR
  dem Spawn reserviert (Blockstate `claimed`) — mehrere randomTicks können
  nie mehr als einen Gooby erzeugen; Reservierung wird beim Verlust des
  Goobys wieder freigegeben
- Schlaf-Unterbrechung korrekt: Aufwecken setzt eine 30-s-Sperre, statt
  dass Gooby im selben Tick wieder einschläft
- Create-6.x-Sitz-Integration abgesichert: Signatur-Verifikation
  (static void, exakte Parametertypen), Throwable-Fangnetz, dauerhafte
  crashfreie Degradation aufs normale Reiten; Sitz-Setzen nur noch durch
  den Besitzer
- Vollständige Persistenz: Owner, Freundschafts-Map, Kommando-Modus,
  Zuhause, Glas-Ziel, Geschenk-Ladungen/-Cooldown, Hut, Zufriedenheit —
  abgedeckt durch einen Save/Reload-GameTest
- GeckoLib-Mindestversion auf die tatsächlich kompilierte Linie korrigiert
  ([4.9,) statt [4.7,))
- CI: GameTests sind FATAL (kein „Jar trotzdem hochladen" mehr), Build
  läuft als `clean build` (keine Jar-Duplikate im Artefakt)
- README: toter Portrait-Verweis entfernt; EN/DE-Sprachparität für alle
  neuen Keys
- Sprechblasen-Text war seit 1.0 unsichtbar (leere Blasen): der Text-Z-
  Offset zeigte im Billboard-Raum von der Kamera WEG, der Depth-Test
  verschluckte jede Zeile — Text rückt jetzt zur Kamera (auf echtem Client
  mit 2 Spielern verifiziert)

### Qualität

- 18 GameTests (vorher 7): Zähmung, Freundschaft+Cooldown, Pfeife/Owner-
  Bindung, Stay/Follow-Verhalten, Geschenk-Kosten+Cooldown, Persistenz-
  Roundtrip, Hut-Sync, atomarer Glas-Spawn (Nacht-Batch), Schlaf-
  Unterbrechung, Create-Degradation, Advancement-Baum, Sophie-Regression +
  Killswitch + Gameplay-Paritäts-Test

## 1.0.0 (2026-08-09)

Erste Version. GOOBY ist da!

### Gooby selbst

- GeckoLib-Modell: kugelrunder Körper, große Schlappohren, Kulleraugen,
  permanentes Lächeln, rosa Näschen, Puschel-Schwanz
- 9 Animationen: Idle-Wackeln (Bauch wabbelt), Hoppeln mit Squash & Stretch,
  Schlafen (zusammengerollt + Zzz-Partikel), Streichel-Freude (Augen zu,
  Ohren zittern), Nutella-Fressen (Gesicht ins Glas!), Winken, Sitzen,
  Buddeln, Traurig-Sein
- 7 selbst synthetisierte Sounds: Quietschen, Schnurren, Boing, Plop,
  Schmatzen, Schnarchen, Mümmeln

### Spawn-Wege

- Nutella-Rezept: 3× Kakaobohnen + Milcheimer + Zucker
- Wildhase + Nutella → Gooby (Wirbel-Partikel + Plop)
- Nutella-Glas nachts auf Grasblock → wilder Gooby hoppelt heran

### Features

- Streicheln (Rechtsklick, leere Hand): Herzchen + Quietsch-/Schnurr-Sound
- Zufriedenheits-System: Glücks-Aura + Speed-Bonus ab 60 Zufriedenheit;
  Streichel-Wunsch alle 1–2 Minuten („Streicheln? 🥺")
- Sprechblasen-System: 66 Lines (DE + EN), Kontext-Lines für Regen/Nacht/
  Kuchen, Begrüßungs-Winken für neu ankommende Spieler
- 10 Special-Lines exklusiv für sophiex456 (case-insensitive, erhöhte
  Häufigkeit)
- Verführungs-Goal: Gooby folgt Spielern mit Nutella in der Hand
- Reiten ohne Sattel, Lenkung per Nutella-Glas, wackeliger Gang inkl.
  Freuden-Hopsern
- Buddeln: Karotten- und Goldkarotten-Funde
- Gooby-Bürste → Gooby-Fussel → Gooby-Wolle (dämpft Fallschaden komplett)
- Hasenstall: Gooby schläft nachts darin, Herzchen am Morgen
- Unverwundbar gegenüber Spielern (Boing! + trauriger Blick)
- Teleportiert sich aus Gefahr (Lava, Feuer, Ersticken, …)
- Create-Kompat: Gooby auf Create-Sitze setzen (optional, ohne harte
  Dependency)

### Qualität

- 7 GameTests (Rezept, Konversion, Streicheln, Sophie-Lines,
  Unverwundbarkeit, Buddel-Drop, Gooby-Wolle)
- Sprachparität en_us/de_de
