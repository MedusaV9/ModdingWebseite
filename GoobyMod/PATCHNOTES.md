# Patchnotes — Gooby Mod (NeoForge 1.21.1) · made by Sonic0810

> Neueste Version oben. Gebaute `.jar`-Dateien liegen nummeriert unter `versions/`.
> Newest version on top. Built `.jar` files live numbered under `versions/`.
> Ausführliche Historie bis 2.0.0: siehe `CHANGELOG.md`. / Full history up to 2.0.0: see `CHANGELOG.md`.

---

## v5.2.0 — „Begleiter-Deluxe" / “Companion Deluxe” · 2026-08-16

### DE

**Begleiter-HUD, Effekte & Config-Bildschirm**
- Eine kompakte Begleiter-Karte zeigt Name, Stimmung, Pfeifkommando sowie
  Lebens- und Zufriedenheitsbalken deines nächsten eigenen Goobys. Sie
  blendet sich nach Inaktivität sanft aus und versteckt sich hinter Menüs,
  Debug-Overlay und F1.
- Beim Kuscheln erscheint eine warme Vignette, ein echter Alarm pulsiert
  dezent am Bildschirmrand und schüttelt die Kamera ganz leicht. Alles ist
  einzeln abschaltbar; reduzierte Bewegung deaktiviert Puls und Shake mit.
- Der neue Config-Bildschirm (Mod-Liste → Konfiguration) bündelt alle
  Client-Optionen mit Schiebereglern, Live-Vorschau der Begleiter-Karte und
  „Fertig speichert / Abbrechen verwirft" — komplett per Maus, Tastatur und
  Narrator bedienbar.

**Neue Begleiter-Inhalte**
- **Nutella-Toast** (Brot + Nutella): sättigt kräftig und gibt einen kurzen
  Zuckerschub (Schnelligkeit I). **Knopfauge** (Goldnuggets + Honigwabe):
  Bastelmaterial, das wilde Goobys auch in Bauten horten.
- **Gooby-Plüschtier**: hinstellen, knuddeln (Quietschen + Herzchen) — und
  es dämpft jede Landung so weich wie Gooby-Wolle. **Gooby-Statue**: ein
  gemeißeltes Denkmal, das nachts sanft funkelt („In Stein gemeißelt").

**Apportieren**
- Der neue **Gooby-Ball** (Schleimball + Faden + Gooby-Fussel, ergibt zwei)
  lässt sich werfen; dein erwachsener Gooby flitzt hinterher und bringt
  GENAU deinen Ball zurück — auch nach Chunk-Wechsel oder Server-Neustart
  geht kein Ball verloren. Advancement: „Apport!".
- Unerreichbare Bälle (Loch, Zaun) gibt Gooby nach kurzer Zeit auf und
  probiert es später erneut, statt endlos dagegen zu laufen.

**Explorer-Outfit & Partikel**
- Drei aufeinander abgestimmte Accessoires: **Blumenkranz** (Kopf),
  färbbares **Abenteuer-Halstuch** (Hals) und **Picknick-Rucksack**
  (Rücken). Das komplette Set verleiht „Bereit fürs Abenteuer".
- Eigene Konfetti-, Flausch- und Notenpartikel begleiten Feiern, Landungen
  und den Freudentanz.

**Kunststück-Welle**
- Der Schleich-Luftpfiff öffnet jetzt einen richtigen Auswahlbildschirm statt
  des Chat-Menüs: Karten für alle Kunststücke mit Sternen und Status, per
  Maus, Tastatur und Narrator bedienbar. Fertig bestätigt, Abbrechen/Esc
  verwirft — „Aktiv" zeigt immer nur den wirklich gespeicherten Stand.
- Zwei neue Kunststücke: **Rolle** (Anlauf, Überschlag um die Körpermitte,
  weiche Landung mit Wölkchen) und **Tanz** (Hüpf-Freudentanz mit
  schwingenden Ohren und Noten). Beide werden wie gewohnt mit
  Trainingshappen bis drei Sterne trainiert.
- Die Rolle bleibt dabei vollständig über dem Boden — und ein neuer
  automatischer Geometrie-Test stellt sicher, dass kein Kunststück jemals im
  Boden versinkt.
- Reichweite: Menü öffnen und Kunststück wählen funktioniert bis
  **64 Blöcke** Entfernung zum Gooby; darüber hinaus gibt es eine klare
  Actionbar-Meldung.
- Gesperrte Kunststücke sind im Bildschirm sichtbar, aber nicht auswählbar —
  der Tooltip erklärt den Weg: Schleich-benutze Trainingshappen am Gooby, um
  das Trainingsziel durchzuschalten, dann füttere Happen zum Freischalten.
- Handbuch und Pfeifen-Tooltip sind auf sechs Kunststücke, den neuen
  Bildschirm und die 64-Block-Reichweite aktualisiert.

**Bewegung & Optik**
- Gooby hat jetzt echte Gangarten: gemütliches Gehen und flottes Rennen
  wechseln flüssig je nach Tempo — beim Erwachsenen wie beim Baby. Kein
  Gleiten mehr zwischen Stehen und Hoppeln.
- Alle fünf Felle (klassisch, Creme, Kakao, gefleckt, Baby) wurden als
  Premium-Texturen neu gemalt: Fellrichtung, weiche Schatten an den Kanten,
  Glanzlichter und organisch gewachsene Flecken.

**Draußen in der Welt**
- Gooby-Baue sind echte kleine Höhlensysteme geworden: Tunnel, Kammern und
  eine Vorratskammer mit eigener Truhe schließen sich an den Grashügel an.
- Neu: das seltene **Gooby-Picknick** auf Wiesen, in Ebenen, Blumenwäldern
  und Kirschhainen — eine gedeckte Decke mit Leckereien (auch mal ein
  Plüschtier oder Blumenkranz) lädt zum Entdecken ein.

**Goobys Stimme**
- Die Klangbibliothek wächst auf 91 Clips: praktisch jedes Geräusch besitzt
  jetzt drei Varianten — Knarzen, Rascheln, Nuzzeln, Gähnen, Schnarchen und
  viele mehr klingen nie zweimal exakt gleich.

**Technik & Sicherheit**
- Die Garderobe speichert jetzt den vollständigen Item-Zustand (z. B.
  Namen und Verzauberungs-Glint von Hüten) verlustfrei. Accessoires aus
  entfernten Dritt-Mods gehen beim Laden nicht mehr verloren, sondern warten
  unangetastet auf die Rückkehr des Mods.
- Jede Mod-Änderung läuft durch ein neues, strenges CI-Gate: Audio-,
  Asset- und Weltgenerierungs-Validatoren, Release-Prüfung, Build und alle
  203 Kernsuite-GameTests müssen grün sein.

### EN

**Companion HUD, effects & config screen**
- A compact companion card shows the name, mood, whistle command, plus
  health and satisfaction bars of your nearest own Gooby. It gently fades
  after inactivity and hides behind menus, the debug overlay, and F1.
- Cuddling shows a warm vignette, a real alarm subtly pulses at the screen
  edge and adds a gentle camera shake. Everything can be toggled
  individually; reduced motion also disables pulse and shake.
- The new config screen (mod list → Config) gathers every client option
  with sliders, a live preview of the companion card, and “Done saves /
  Cancel discards” — fully usable via mouse, keyboard, and narrator.

**New companion content**
- **Nutella Toast** (bread + Nutella): filling, with a short sugar rush
  (Speed I). **Button Eye** (gold nuggets + honeycomb): crafting material
  that wild Goobys also hoard in burrows.
- **Gooby Plushie**: place it, squeeze it (squeak + hearts) — and it
  cushions every landing as softly as Gooby Wool. **Gooby Statue**: a
  carved monument that sparkles softly at night (“Set in Stone”).

**Fetch**
- The new **Gooby Ball** (slime ball + string + Gooby Fluff, makes two) can
  be thrown; your adult Gooby dashes after it and returns EXACTLY your ball
  — no ball is lost even across chunk changes or server restarts.
  Advancement: “Fetch!”.
- Unreachable balls (hole, fence) are given up after a short while and
  retried later instead of pathfinding against them forever.

**Explorer outfit & particles**
- Three matching accessories: **Flower Crown** (head), dyeable **Adventure
  Bandana** (neck), and **Picnic Backpack** (back). The complete set grants
  “Ready for Adventure”.
- Custom confetti, fluff, and music-note particles accompany celebrations,
  landings, and the happy dance.

**Trick Wave**
- The sneak air-whistle now opens a proper selection screen instead of the
  chat menu: cards for every trick with stars and status, usable via mouse,
  keyboard, and narrator. Done confirms, Cancel/Esc discards — “Active”
  always reflects only the truly saved state.
- Two new tricks: **Roll** (wind-up, somersault around the body center, soft
  landing with a puff) and **Dance** (a bouncy happy dance with swinging ears
  and musical notes). Both train with Training Treats up to three stars as
  usual.
- The roll stays completely above the ground — and a new automatic geometry
  test makes sure no trick ever sinks into the floor.
- Range: opening the menu and picking a trick works up to **64 blocks** from
  your Gooby; beyond that you get a clear action-bar message.
- Locked tricks are visible on the screen but not selectable — the tooltip
  explains the path: sneak-use Training Treats on your Gooby to cycle the
  training target, then feed treats to unlock.
- The handbook and the whistle tooltip now cover six tricks, the new screen,
  and the 64-block range.

**Motion & looks**
- Gooby now has real gaits: relaxed walking and brisk running blend smoothly
  with its speed — for adults and babies alike. No more gliding between
  standing and hopping.
- All five coats (classic, cream, cocoa, spotted, baby) were repainted as
  premium textures: fur direction, soft edge shading, highlights, and
  organically grown spots.

**Out in the world**
- Gooby burrows have become real little cave systems: tunnels, dens, and a
  pantry with its own chest attach to the grassy mound.
- New: the rare **Gooby Picnic** in meadows, plains, flower forests, and
  cherry groves — a laid-out blanket with treats (sometimes even a plushie
  or flower crown) invites exploration.

**Gooby's voice**
- The sound library grows to 91 clips: virtually every noise now has three
  variants — creaks, rustles, nuzzles, yawns, snores, and many more never
  sound exactly the same twice.

**Tech & safety**
- The wardrobe now stores the complete item state (for example names and
  enchantment glint on hats) losslessly. Accessories from removed
  third-party mods are no longer lost on load; they wait untouched for the
  mod's return.
- Every mod change now passes a strict new CI gate: audio, asset, and
  worldgen validators, the release check, the build, and all 203 core-suite
  GameTests must be green.

---

## v5.1.0 — „Interaktions-Politur" / “Interaction Polish” · 2026-08-13

### DE

**Interaktions-Politur**
- Streichel-Klickspam löst keine Kunststück-Absagen mehr aus: Der
  Doppelklick wird nur noch zum Trick-Wunsch, wenn der Trick wirklich laufen
  kann (erwachsen, eigener Gooby, Kunststück trainiert). Vorher wurde jeder
  zweite Klick von Besuchern oder bei untrainierten Tricks in eine
  Absage-Nachricht samt Verweigerungs-Sound verwandelt.
- Die Bürste schluckt Klicks im Cooldown nicht mehr stumm: Es erscheint die
  Restzeit in der Actionbar („Frisch gebürstet …"), dazu ein weicher Squeak
  und ein Nasen-Wackeln.
- Schnüffel & Such zeigt den Cooldown jetzt mit Restsekunden an, statt den
  Klick unsichtbar zu verwerfen. Alle Such-Absagen sind hörbar.
- Jede Ablehnung (Anschmiegen, Garderobe, Färben, Schere, Mäntel, Tasche)
  spielt jetzt einen leisen Squeak zur Actionbar-Nachricht — kein Klick
  bleibt mehr ohne Reaktion.
- Zweithand-Pflege funktioniert: Mit leerer Haupthand und Nutella, Bürste,
  Happen & Co. in der Zweithand wird das Item jetzt benutzt, statt vom
  Streicheln verschluckt zu werden.
- Scheue wilde Goobys betteln nicht mehr um Streicheleinheiten und begrüßen
  niemanden mehr, vor dem sie gleichzeitig fliehen.
- Nach dem Aufwecken (Streicheln, Füttern, Pfeife) steht Gooby sofort wieder
  auf, statt bis zu 15 Sekunden eingefroren stehen zu bleiben.
- Beim Reiten ohne Nutella-Glas erscheint ein Lenk-Hinweis in der Actionbar.
  Drehung und High-Five haben jetzt eigene Sounds; die Trick-Auswahl per
  Schleichklick klingt ebenfalls.

**Modell-Politur**
- Baby-Gooby ist nicht mehr durchlöchert: Die Baby-Textur wird jetzt direkt auf
  das Baby-UV-Layout gemalt (vorher ein Adult-Recolor, bei dem Schwanz und
  Vorderpfoten komplett transparent blieben und die Kopfunterseite zur Hälfte
  fehlte). Das linke Baby-Ohr teilt sich keine Texel mehr mit dem Hinterkopf,
  die Fuß-UVs ragen nicht mehr über den Texturrand hinaus.
- `baby_hop` und `greeting_bounce` loopen jetzt ruckelfrei: Die End-Keyframes
  entsprechen wieder exakt den Start-Keyframes (vorher sprangen Körperrotation
  bzw. Körper-Squash bei jedem Loop-Neustart sichtbar um).
- Die 3D-Garderoben-Geos (`scarf.geo.json`, `satchel.geo.json`) deklarieren
  jetzt eine passende Texturgröße (64x32 statt 16x16) mit überlappungsfreien
  Box-UVs; vorher liefen alle Faces über den Texturrand hinaus.
- `dug_dirt` verwendet keinen toten `tintindex` mehr (es war nie ein
  BlockColor-Handler registriert).

### EN

**Interaction polish**
- Petting click-spam no longer triggers trick refusals: a double click only
  becomes a trick request when the trick can actually run (adult, your own
  Gooby, trick trained). Previously every second click from visitors or with
  untrained tricks turned into a refusal message plus denial sound.
- The brush no longer swallows clicks silently during its cooldown: the
  remaining time appears on the action bar (“Freshly brushed …”) along with a
  soft squeak and a nose wiggle.
- Sniff & Seek now shows its cooldown with remaining seconds instead of
  discarding the click invisibly. Every seek refusal is audible.
- Every denial (snuggle, wardrobe, dyeing, shears, coats, satchel) now plays
  a quiet squeak alongside its action-bar message — no click goes
  unanswered anymore.
- Offhand care works: with an empty main hand and Nutella, brush, treat & co.
  in the offhand, the item is now used instead of being swallowed by petting.
- Shy wild Goobys no longer beg for pets or greet the very players they are
  fleeing from at the same time.
- After being woken (petting, feeding, whistle) Gooby gets up immediately
  instead of standing frozen for up to 15 seconds.
- Riding without a Jar of Nutella shows a steering hint on the action bar.
  Spin and High Five now have their own sounds; sneak-click trick selection
  is audible too.

**Model polish**
- Baby Gooby is no longer full of holes: the baby texture is now painted
  directly onto the baby UV layout (previously an adult recolor that left the
  tail and front paws fully transparent and half of the head underside
  missing). The left baby ear no longer shares texels with the back of the
  head, and the foot UVs no longer overflow the texture edge.
- `baby_hop` and `greeting_bounce` now loop seamlessly: end keyframes match
  the start keyframes again (body rotation and body squash used to snap
  visibly on every loop restart).
- The 3D wardrobe geos (`scarf.geo.json`, `satchel.geo.json`) now declare a
  fitting texture size (64x32 instead of 16x16) with overlap-free box UVs;
  previously every face overflowed the texture bounds.
- `dug_dirt` no longer carries a dead `tintindex` (no BlockColor handler was
  ever registered).

---

## v5.0.2 — „Ausdauernd" / “Endurance” · 2026-08-12

### DE

**Fixes**
- Spieler-, Emote- und Partnerzustände besitzen jetzt neben ihrem Zeitablauf
  feste Obergrenzen und werden beim Logout sofort freigegeben. Auch manipulierte
  alte Entity-NBT kann Freundschaften, Erinnerungen oder Ritualhistorien nicht
  mehr über die Release-Grenzen aufblasen.
- Die autonome Sozial-KI kann Fangspiele nun tatsächlich auswählen und behält
  ihre Goal-Fortsetzung während einer laufenden Aktion. Hasen suchen nur noch
  einmal pro Sekunde nach wilden Goobys statt bei fast jeder Goal-Auswertung.
- Der statische Gruppen-Soundlimiter leert sich beim Serverstopp, behandelt
  zurückgesetzte Weltzeit korrekt und verdrängt wirklich den ältesten Bucket.
  Synchronisierte Blasen-, Garderoben- und Stallnamen sind paketfest begrenzt.

**Polish**
- Alle zwölf normalen Crafting-Rezepte besitzen jetzt Recipe-Book-Unlocks.
  Nutella, Bürste, Trainingshappen, Funkel-Fussel und Schatzkarte erklären ihren
  nächsten Spielschritt mit vollständigen DE+EN-Tooltips.
- Vier neue Regressions-GameTests decken Logout-Cleanup, NBT-Hard-Limits,
  Recipe-Book/Tooltip-Vollständigkeit und Paketgrenzen ab; bestehende Sozial-
  und Soundtests prüfen zusätzlich Produktionsauswahl und Zeitrücksprünge.

### EN

**Fixes**
- Player, emote, and partner state now has hard caps in addition to expiry and
  is released immediately on logout. Even manipulated legacy entity NBT can no
  longer inflate friendships, memories, or ritual history past release limits.
- Autonomous social AI can now actually choose play chase and keeps its goal
  continuation while an action is active. Rabbits scan for wild Goobys once per
  second instead of during nearly every goal evaluation.
- The static crowd-sound limiter clears on server stop, handles world-time
  rollback, and evicts the true oldest bucket. Synchronized bubble, wardrobe,
  and hutch-name strings now have packet-safe limits.

**Polish**
- All twelve ordinary crafting recipes now have recipe-book unlocks. Nutella,
  the brush, Training Treat, Shimmer Fluff, and treasure map explain their next
  gameplay step with complete DE+EN tooltips.
- Four new regression GameTests cover logout cleanup, NBT hard limits,
  recipe-book/tooltip completeness, and packet bounds; existing social and
  sound tests additionally verify production selection and time rollback.

---

## v5.0.1 — „Zählebig" / “Hardened” · 2026-08-11

### DE

**Fixes**
- Notfall-Teleport gerettet: In Fluss- und Ozean-Terrain lehnte der
  Selbstschutz-Teleport jede Wasseroberfläche ab — eingemauerte oder brennende
  Goobys erstickten bzw. verbrannten, obwohl sie schwimmen können. Ein zweiter
  Notnagel-Pass landet jetzt kontrolliert auf stillem Wasser, wenn kein
  trockenes Land erreichbar ist.
- Drei Speicherlecks geschlossen: Emote-Gedächtnisse, Sozial-Cooldowns und
  Familienritual-Zeiten wuchsen unbegrenzt mit jedem je getroffenen Spieler
  bzw. Partner (und wurden teilweise mitgespeichert). Abgelaufene Einträge
  werden jetzt sekündlich mit dem übrigen transienten Zustand aufgeräumt.
- Emote-Erkennung läuft ohne Entity-Scan: Statt pro Gooby und Tick die
  Entity-Sektionen zu durchsuchen (inkl. Listen-Allokation), wird die
  Spielerliste der Welt direkt gefiltert — Tick-genaue Erkennung bleibt.

**Qualität**
- Drei neue Regressions-GameTests: Wasseroberflächen-Notnagel, Befreiung aus
  dem Fels und Pruning aller transienten Sozial-Maps.
- Headless-Soak mit Monitoring (TPS, Heap/RSS, Entity-Zahlen, Fehlerzähler)
  über eine dedizierte Server-Instanz bestätigt die Fixes.

### EN

**Fixes**
- Emergency teleport rescued: in river/ocean terrain the self-preservation
  teleport rejected every water surface — walled-in or burning Goobys
  suffocated or burned even though they can swim. A second fallback pass now
  lands deliberately on still water when no dry land is reachable.
- Closed three memory leaks: emote memories, social cooldowns, and family
  ritual timestamps grew without bound for every player/partner ever met
  (and were partially persisted). Expired entries are now pruned every second
  together with the rest of the transient state.
- Emote detection no longer scans entities: instead of walking the entity
  sections per Gooby per tick (including a list allocation), the level's
  player list is filtered directly — tick-accurate detection is preserved.

**Quality**
- Three new regression GameTests: water-surface fallback landing, escape from
  solid rock, and pruning of all transient social maps.
- A headless soak with monitoring (TPS, heap/RSS, entity counts, error
  counters) on a dedicated server instance confirms the fixes.

---

## v5.0.0 — „Hochglanz" / “Grand Polish LTS” · 2026-08-11

### DE

**Neu**
- Handbuch 2.0 öffnet acht illustrierte, direkt anwählbare Kapitel mit einem
  animierten Titel-Gooby; alle Texte und Navigationen sind vollständig DE+EN.
- Die lokale Client-Config ergänzt reduzierte Bewegung und kontrastreiche
  Sprechblasen. Pfeifenkommandos zeigen zusätzlich eindeutige Actionbar-Glyphen.
- Die für 5.x stabile Addon-API bietet `GoobyAccessor`, Zähm-/Stufen-/
  Geschenk-Events, den öffentlichen Hut-Tag und registrierbare Sprachpools.

**Fixes**
- Freundschaftsspeicher ist auf 32 zuletzt benutzte Besucher plus den immer
  geschützten Besitzer begrenzt; dadurch wachsen Entity-Saves nicht endlos.
- Mikroanimationen und Pfotenakzente pausieren jenseits 24 Blöcken bzw. ohne
  Rendering. Periodische Stimmen mehrerer Goobys werden pro Chunk gebündelt.
- Jeder Sprachpool besitzt jetzt mindestens vier idiomatische Lines. Alle
  Sounds behalten geprüfte Untertitel; DE/EN-Key-Parität bleibt fail-closed.

**Polish**
- Zwölf neue Handbuchbilder, überarbeitete Blasenfarben, finaler Textur-/
  Animationstiming-Audit und ein reproduzierbarer Showcase-Weltbauplan.
- 105 Default- plus 3 Create-GameTests decken API, LRU/NBT, Sprachpools,
  Accessibility-LOD, Sound-Limiter und alle bisherigen Systeme ab.
- Headless prüft Serverpfade und Assetverträge. Client-FPS, 20-%-Zeitlupen-
  Review und moderierter 30-Minuten-Erstspieler-Test brauchen weiterhin eine
  GPU bzw. menschliche Wahrnehmung und sind daher nicht automatisierbar.

### EN

**New**
- Handbook 2.0 opens eight illustrated, directly selectable chapters with an
  animated cover Gooby; every body and navigation string is fully DE+EN.
- Local client config adds Reduced Motion and High-Contrast Bubbles. Whistle
  commands now also show distinct actionbar glyphs.
- The 5.x-stable addon API provides `GoobyAccessor`, tame/tier/gift events,
  the public hat tag, and registered speech pools.

**Fixes**
- Relationship storage is bounded to 32 recently used visitors plus the
  always-protected owner, preventing unbounded entity-save growth.
- Micro-animations and paw accents pause beyond 24 blocks or while not
  rendered. Periodic voices from Gooby crowds coalesce per chunk.
- Every speech pool now has at least four idiomatic lines. All sounds retain
  verified subtitles and DE/EN key parity remains fail-closed.

**Polish**
- Twelve handbook illustrations, revised bubble contrast, a final texture/
  animation-timing audit, and a reproducible showcase-world blueprint.
- 105 default plus 3 Create GameTests cover API, LRU/NBT, speech pools,
  accessibility LOD, sound limiting, and every existing system.
- Headless validates server paths and asset contracts. Client FPS, 20%-speed
  visual review, and the moderated 30-minute new-player read-through still
  require a GPU or human perception and therefore cannot be automated.

---

## v4.3.0 — „Schatzsucher" / “Treasure Trails” · 2026-08-11

### DE

**Neu**
- Die Winzige Tasche ist jetzt ein besitzergebundenes Vier-Slot-Inventar.
  Erneute Benutzung am ausgerüsteten Gooby öffnet eine eigene kompakte GUI;
  Inhalt bleibt gespeichert und wird beim Ablegen oder erzwungenen Tod gerettet.
- „Schnüffel & Such“ lässt Freund-Goobys nach gezeigten Karotten oder Blöcken
  bis 24 Blöcke tief suchen. Ein Trainingshappen startet die Spur, Pfoten weisen
  den Weg und ein Buddelmarker zeigt den Fund. Erzsuche ist opt-in.
- Beste Freunde können selten Kartenfetzen ausbuddeln. Vier Fetzen ergeben
  eine Karte zum nächsten generierten Gooby-Schatzversteck mit Kosmetik,
  Funkel-Fussel und Nutella.

**Fixes**
- Ferne Buddelgeschenke werden atomar in die Tasche gepackt; ein fehlgeschlagener
  Insert erzeugt genau einen Welt-Drop und kann weder duplizieren noch verlieren.
- Gedroppte Geschenke sind zehn Sekunden für den vorgesehenen Empfänger
  reserviert. Cooldowns gelten auch für erfolglose Suchscans.

**Polish**
- Drei Animationen (`sniff_seek`, `dig_excited`, `present_item`), zwei neue
  Sounds samt Untertiteln, Karten-/GUI-Texturen und zwei Advancements.
- `seek.allowOres` und `seek.cooldown` sind dokumentierte Serveroptionen.
  Das 15-seitige Handbuch und sechs neue GameTests decken den gesamten Loop ab.

### EN

**New**
- The Tiny Satchel is now an owner-gated four-slot inventory. Use an equipped
  satchel on Gooby again to open its compact screen; contents persist and are
  recovered when removed or on a forced death.
- “Sniff & Seek” lets Friend Goobys search up to 24 blocks underground for a
  shown carrot or block. A Training Treat starts the trail, paws lead the way,
  and a dig marker identifies the find. Ore seeking is opt-in.
- Best Friends can rarely dig up map scraps. Four scraps restore a map to the
  nearest generated Gooby treasure cache containing cosmetics, Shimmer Fluff,
  and Nutella.

**Fixes**
- Distant dug gifts atomically enter the satchel; a failed insertion creates
  exactly one world drop, with neither duplication nor loss.
- Dropped gifts reserve pickup for their intended recipient for ten seconds.
  Cooldowns also apply to unsuccessful seek scans.

**Polish**
- Three animations (`sniff_seek`, `dig_excited`, `present_item`), two subtitled
  sounds, map/GUI textures, and two advancements.
- `seek.allowOres` and `seek.cooldown` are documented server options. The
  15-page handbook and six new GameTests cover the complete loop.

---

## v4.2.0 — „Soziale Goobys" / “Gooby & Friends” · 2026-08-11

### DE

**Neu**
- Goobys begrüßen sich mit synchronem Zwei-Phasen-Hopser, spielen höchstens
  30 Sekunden Fangen, tauschen kosmetische Geschenke und kuscheln beim Schlaf.
- Doppelte Schleich-Verbeugung in einer Sekunde und drei Sprünge bei glücklicher
  Stimmung lösen `bow` bzw. gemeinsames `happy_bounce` aus.
- Drei nahe Schläfer verleihen „Flauschhaufen"; ihre Zzz verschmelzen zu einem
  größeren Marker. Benannte Flauschfreunde erscheinen in acht Sozialblasen.

**Fixes**
- Sozial-AI liegt auf der niedrigsten Priorität. Bleiben, Folgen, Schlaf,
  Schutz, Familie und Gefahr brechen sie sofort ab; Paarcooldowns sind symmetrisch.
- Bubble v2 staffelt Nachbarn vertikal, skaliert weich ein/aus und richtet den
  Schwanz aus, statt angrenzende Blasen gegeneinander z-fighten zu lassen.

**Polish**
- Vier neue Clips (`greeting_bounce`, `play_chase_lunge`, `bow`, `nap_huddle`),
  zwei Sozial-Zwitscher samt Untertitel und scharfer Vier-Glyphen-Iconfont.
- `social.playChase` und `social.emoteReactions` sind Server-Schalter.
  14-seitiges Ingame-Handbuch; 94 Default- plus 3 Create-GameTests sind grün.
- Headless prüft Handshake, Gehorsam, 600-Tick-Ende/Cooldown, Advancement,
  Emote-Fenster und Assets. GUI-Skalen 1–4 bleiben visuelle Client-QA.

### EN

**New**
- Goobys share a synchronized two-phase greeting, at most 30 seconds of play
  chase, cosmetic gifts, and huddled sleep.
- Two deliberate sneak-bows inside one second and three jumps near a Happy
  Gooby trigger `bow` and shared `happy_bounce` responses.
- Three nearby sleepers grant “Fluff Pile”; their Zzz merge into one larger
  marker. Named fluff friends appear in eight social bubbles.

**Fixes**
- Social AI has the lowest priority. Stay, Follow, sleep, shelter, family, and
  danger cancel it immediately; pair cooldowns are symmetric.
- Bubble v2 vertically staggers neighbors, gently scales in/out, and aims its
  tail instead of letting adjacent panels z-fight.

**Polish**
- Four new clips (`greeting_bounce`, `play_chase_lunge`, `bow`, `nap_huddle`),
  two subtitled social chirps, and a crisp four-glyph icon font.
- `social.playChase` and `social.emoteReactions` are server switches.
  Fourteen-page handbook; 94 default plus 3 Create GameTests are green.
- Headless covers handshake, obedience, 600-tick stop/cooldown, advancement,
  emote window, and assets. GUI scales 1–4 remain visual client QA.

---

## v4.1.0 — „Wilde Welt" / “Out in the Wild” · 2026-08-11

### DE

**Neu**
- Extrem seltene wilde Goobys spawnen einzeln in Blumenwäldern, Kirschhainen
  und Wiesen. `worldgen.wildSpawns` schaltet nur natürliche Spawns ab.
- Grasbedeckte Gooby-Baue entstehen als Jigsaw-Struktur mit persistentem
  Bewohner, Heimatanker und Startertruhe aus Nutella, Karotten und Fussel.
- Wilde Goobys fliehen bis zum ersten Nutella, spähen scheu, rufen über
  32 Blöcke und hinterlassen Pfotenpartikel auf Sand oder Schnee.
- Buddeln erzeugt eine kollisionslose Erdspur, die nach zwei Minuten zerfällt.
  Hasen folgen wilden Goobys, Katzen starren und wilde Wölfe lösen Alarm aus.

**Fixes**
- Nur natürlich gespawnte, unbenannte wilde Goobys despawnen normal.
  Gezähmte, verwandelte, Spawn-Ei- und Bau-Goobys bleiben persistent.
- `finalizeSpawn` vereinheitlicht die Startzufriedenheit von Spawn-Ei und
  Konversion auf 70; Naturspawns markieren ihren Ursprung persistent.

**Polish**
- Neue `shy_peek`-Animation, Pfoten-/Buddeltexturen, ferner `wild_call` mit
  Untertitel, fünf scheue Lines und „Wer wohnt denn hier?“-Advancement.
- 13-seitiges Ingame-Handbuch und neues DE+EN-Kapitel. 89 Default- plus
  3 Create-GameTests prüfen Despawn, Bau-Heimat, Scheu, Struktur-/Assetdaten.
- Headless validiert Regeln, NBT und Datenpakete. Spawnrate und Geländeform in
  vielen Seeds bleiben als dokumentierte visuelle Weltgenerierungs-QA.

### EN

**New**
- Extremely rare wild Goobys spawn singly in flower forests, cherry groves,
  and meadows. `worldgen.wildSpawns` disables only natural spawning.
- Grass-covered Gooby burrows generate as a jigsaw structure with a persistent
  resident, home anchor, and Nutella/carrot/fluff starter chest.
- Wild Goobys flee until their first Nutella, peek shyly, call over 32 blocks,
  and leave paw particles on sand or snow.
- Digging creates a non-colliding dirt mark that decays after two minutes.
  Rabbits follow wild Goobys, cats stare, and untamed wolves trigger alarms.

**Fixes**
- Only naturally spawned, unnamed wild Goobys despawn normally. Tamed,
  converted, spawn-egg, and burrow Goobys remain persistent.
- `finalizeSpawn` unifies spawn-egg and conversion satisfaction at 70 and
  persistently records natural-spawn origin.

**Polish**
- New `shy_peek` animation, paw/dig textures, distant subtitled `wild_call`,
  five shy lines, and “Who Lives Here?” advancement.
- Thirteen-page in-game handbook and new DE+EN chapter. 89 default plus
  3 Create GameTests cover despawn, burrow home, shyness, and structure/assets.
- Headless validates rules, NBT, and datapacks. Multi-seed spawn-rate and
  terrain-shape checks remain documented visual world-generation QA.

---

## v4.0.0 — „Create-Express" / “Create Express” · 2026-08-11

### DE

**Neu**
- Create 6.0.10+ ist eine echte typisierte, aber optionale Integration. Goobys
  bleiben beim Aufbau von Lager-, Gantry- und Zugkonstruktionen auf ihrem Sitz,
  schaukeln passend zur Bewegung und kommentieren die Ankunft mit sechs Bubbles.
- Create ergänzt zwei bedingte Nutella-Wege: Mixer mit 250 mB Milch, drei
  Kakaobohnen und Zucker sowie Ausgießer mit leerem Gooby-Glas und 250 mB
  Schokolade. Zwei leere Gläser lassen sich aus drei Glasscheiben craften.
- Bleiben-Goobys in der Nähe laufender, nicht überlasteter Kinetik erhalten
  alle 30 Sekunden einen kleinen Zufriedenheitsbonus und sechs Maschinen-Lines.

**Fixes**
- Der Luftpfiff reißt Gooby nicht mehr von fahrenden Konstruktionen; er lehnt
  freundlich ab und bleibt Passagier.
- `isSeatFree` nutzt Create-`SeatBlock`/`SeatEntity` statt Klassennamen. Nur
  echte API-/Linkage-Mismatches degradieren permanent; transiente Fehler
  erhalten drei nicht blockierende Retries mit 1/2/4-Tick-Backoff.
- Ohne Create werden weder Bridge noch Rezepte aktiviert. Der ursprüngliche
  Handcraft-Pfad und normales Reiten bleiben unverändert verfügbar.

**Polish**
- Neue Clips `seated_contraption_idle` und `train_lean`, leere-Glas-Textur,
  lokalisierte Tooltips, zwölfseitiges Ingame-Handbuch und eigener Create-
  Abschnitt mit Rezeptdiagramm.
- Genau eine Startdiagnose nennt erkannte Create-Version und Integrationsstufe.
  Getrennte Gates prüfen 85 Default- plus 3 Create-GameTests, Mixer-
  Registrierung, transiente Erholung und den sicheren Headless-Fallback.

**Bekannte Einschränkung**
- Create 6.0.x kann den Sitz-/Passenger-Lebenszyklus auf NeoForges headless
  GameTestServer nicht zuverlässig abbilden. Dort bleibt die Integration
  absichtlich deaktiviert; reguläre Dedicated-/Client-Server verwenden den
  versionsgebundenen Pfad. Fünfminütiger Zug-Desync, Ankunfts-Bubble und
  Sound-Dämpfung bleiben visuelle Client-QA.

### EN

**New**
- Create 6.0.10+ is a real typed but optional integration. Seated Goobys remain
  passengers when bearing, gantry, and train contraptions assemble, sway with
  the motion, and share one of six arrival bubbles.
- Create adds two conditional Nutella paths: Mixer with 250 mB milk, three
  cocoa beans, and sugar; Spout with an Empty Gooby Jar and 250 mB chocolate.
  Three glass panes craft two empty jars.
- Stay-mode Goobys near running, non-overstressed kinetics gain a small
  satisfaction bonus every 30 seconds and use six machinery lines.

**Fixes**
- Air-whistles no longer pull Gooby off moving contraptions; Gooby politely
  refuses and remains a passenger.
- `isSeatFree` uses typed Create `SeatBlock`/`SeatEntity` checks instead of
  class names. Only true API/linkage mismatches degrade permanently; transient
  failures receive three non-blocking retries with 1/2/4-tick backoff.
- Without Create, neither bridge nor recipes activate. The original handcraft
  path and normal riding remain unchanged.

**Polish**
- New `seated_contraption_idle` and `train_lean` clips, empty-jar texture,
  localized tooltips, twelve-page in-game handbook, and dedicated Create
  chapter with recipe diagram.
- Exactly one startup diagnostic reports detected Create version and
  integration level. Separate gates cover 85 default plus 3 Create GameTests,
  mixer registration, transient recovery, and the safe headless fallback.

**Known limitation**
- Create 6.0.x cannot reliably expose its seat/passenger lifecycle on
  NeoForge's headless GameTestServer. Integration is intentionally disabled
  there; regular dedicated/client servers use the version-gated path. The
  five-minute train-desync, arrival-bubble, and sound-attenuation checks remain
  visual client QA.

---

## v3.9.0 — „Mode & Fussel" / “Fashion Fluff” · 2026-08-11

### DE

**Neu**
- Drei Garderoben-Slots speichern und synchronisieren Hut, Schal/Fliege und
  winzige Tasche. Schals lassen sich mit allen 16 Vanilla-Farbstoffen craften
  oder direkt am Gooby färben.
- Kleine Blumen, alle Wollteppiche und Gooby-Fussel sind datengetrieben über
  `#goobymod:gooby_hats` tragbar; Datapacks können eigene Hüte ergänzen.
- Bürsten auf Beste-Freunde-Stufe hat 5 % Chance auf Funkel-Fussel. Vier Stück
  schalten nacheinander Creme-, Kakao- und Fleckenfell permanent frei;
  Schleich-Bürsten wechselt zwischen freigeschalteten Varianten.
- Curios 9.5.1+ ist optionale Compile-Integration: Die Pfeife passt über den
  Charm-Tag in den Slot, ohne Curios bleibt der Mod vollständig eigenständig.

**Fixes**
- Scheren entfernen jetzt das vollständige Outfit atomar und geben jedes Item
  samt Schalfarbe zurück, statt nur den Hut zu beachten.
- Garderobe, RGB-Farbe, Fellwahl und Fell-Freischaltungen überstehen NBT.
  Fremde Spieler und Babys können Accessoires/Felle nicht verändern.
- Das ungenutzte Modrinth-Repository wurde entfernt; das Curios-Repository wird
  nun von einer echten, versionsgebundenen `compileOnly`-API genutzt.

**Polish**
- 3D-Schal, Fliege und Tasche folgen `neck_anchor`/`back_anchor`; drei
  Felltexturen, farbige Partikel, Stoff-Sound mit Untertitel,
  Status-Glyphen und „Herausgeputzt"-Advancement.
- Suite: 83 GameTests einschließlich Drei-Slot-/RGB-Roundtrip, Tag-Vertrag,
  Fellfreischaltung, Komplett-Scheren, Curios-Abwesenheit und Asset-Gate.
- Headless prüft Daten und Assets. Der geforderte Zwei-Client-Outfit-Check
  sowie Pose-/16-Farben-Sichtprüfung bleiben visuelle Client-QA.

### EN

**New**
- Three wardrobe slots persist and synchronize a hat, scarf/bowtie, and Tiny
  Satchel. Scarves support all 16 vanilla dyes in crafting or directly while
  worn.
- Small flowers, every wool carpet, and Gooby Fluff are wearable through
  `#goobymod:gooby_hats`; datapacks can add their own hats.
- Brushing at Best Friend has a 5% Shimmer Fluff chance. Four pieces
  permanently unlock cream, cocoa, then spotted coats; sneak-brushing cycles
  unlocked appearances.
- Curios 9.5.1+ is an optional compile integration: the whistle enters its
  Charm slot through a data tag while installations without Curios remain
  fully standalone.

**Fixes**
- Shears now atomically remove the complete outfit and return every item,
  including scarf color data, instead of only considering the hat.
- Wardrobe slots, RGB color, selected coat, and permanent coat unlocks survive
  NBT. Foreign players and babies cannot alter accessories or coats.
- The unused Modrinth repository is removed; the Curios repository now backs a
  real version-pinned `compileOnly` API.

**Polish**
- 3D scarf, bowtie, and satchel follow `neck_anchor`/`back_anchor`; three coat
  textures, color-matched particles, subtitled fabric sound, status glyphs,
  and the “Dressed to the Nines” advancement.
- Suite: 83 GameTests including three-slot/RGB round trip, tag contract, coat
  unlock, strip-all shearing, Curios absence, and asset gate.
- Headless gates cover data and assets. The requested two-client outfit check
  plus pose/16-color visual review remains client QA.

---

## v3.8.0 — „Gooby-Nachwuchs" / “Little Goobys” · 2026-08-11

### DE

**Neu**
- Benutze ein Nutella-Glas auf einem platzierten Kuchen: Der Nutella-Kuchen
  begrüßt bei zwei erwachsenen, gezähmten Goobys mit Freund-Stufe ein Baby.
  Beide Besitzer dürfen verschieden sein.
- Derselbe Elternpaar-Cooldown wird auf beiden Goobys persistent gespeichert.
  Ersatzkuchen, Save/Reload und mehrfache Aktivierungen erzeugen deshalb
  höchstens ein Baby pro Paar und Tag.
- Gooby-Babys besitzen ein eigenes 55-%-Rendering mit größerem Kopf, kürzeren
  Ohren und weicherer Textur. Sie folgen ihren gespeicherten Eltern, spielen
  kurze Fangrunden und schlafen als Familie am Ritualnest.
- Nach 1,5 Minecraft-Tagen wachsen Babys mit einem Pop heran. Eigene
  Trainingshappen beschleunigen das Wachstum.

**Fixes**
- `getBreedOffspring` erzeugt nun einen echten, alternden Gooby für den
  expliziten Ritualpfad; Vanilla-Futterzucht bleibt weiterhin deaktiviert.
- Babyalter, beide Eltern-UUIDs, Familiennest und Paar-Cooldowns überstehen
  Save/Reload. Babys ignorieren Pfeife und Follow-Kommando zuverlässig.
- Reiten, Create-Sitze, Hüte und Kunststücke sind für Babys mit verständlicher
  Antwort gesperrt.
- Der Fernpfiff behält seine zufällige Zielvariation, prüft nach Fehlversuchen
  aber alle sicheren Nahfelder. Offener Boden scheitert nicht mehr zufällig.

**Polish**
- Sechs Baby-Bubbles, drei separat gerenderte Piepser, Nuzzle-Sound,
  `baby_hop`, `baby_tumble`, `parent_nuzzle`, `grow_up_pop` und
  „Familienglück"-Advancement.
- Config: `family.growthTicks` (`36000`) und `family.ritualCooldown`
  (`24000`); Suite: 77 GameTests.
- Headless-Gates prüfen Ritual-Atomizität, Persistenz, Wachstum, Kommandos und
  Assets. Der geforderte Baby/Adult-Seitenvergleich bleibt visuelle Client-QA.

### EN

**New**
- Use a Nutella jar on a placed cake: the resulting Nutella Cake welcomes one
  baby when two adult, tamed Goobys are Friends with their owners. The owners
  may be different players.
- The pair cooldown is persisted on both parents. Replacement cakes,
  save/reload, and repeated activation therefore produce at most one baby per
  pair per day.
- Baby Goobys have a dedicated 55% render with a larger head, shorter ears,
  and softer texture. They follow their persisted parents, play short tag
  bursts, and sleep as a family around the ritual nest.
- Babies grow up with a pop after 1.5 Minecraft days. Training Treats accelerate
  that growth.

**Fixes**
- `getBreedOffspring` now creates a real aging Gooby for the explicit ritual
  path while vanilla food breeding remains disabled.
- Baby age, both parent UUIDs, family nest, and pair cooldowns survive
  save/reload. Babies reliably ignore whistles and Follow commands.
- Riding, Create seats, hats, and tricks are gated for babies with a friendly
  explanation.
- Long-range whistle calls retain varied targets but exhaustively check nearby
  safe cells after random misses, eliminating chance failures on open ground.

**Polish**
- Six baby bubbles, three separately rendered chirps, nuzzle sound,
  `baby_hop`, `baby_tumble`, `parent_nuzzle`, `grow_up_pop`, and the
  “Family Bliss” advancement.
- Config: `family.growthTicks` (`36000`) and `family.ritualCooldown`
  (`24000`); suite: 77 GameTests.
- Headless gates cover ritual atomicity, persistence, growth, commands, and
  assets. The requested baby/adult side-by-side comparison remains visual
  client QA.

---

## v3.7.0 — „Traumstall" / “Hutch, Sweet Hutch” · 2026-08-11

### DE

**Neu**
- Hutch 2.0 speichert Komfort, Bewohner, Namensschild, Belegung und
  Morgengeschenk-Tag in einer synchronisierten BlockEntity. Der offene
  Vierseiten-Stall zeigt Gooby im engen Innen-Schlafcurl.
- Rechtsklick mit Wolle baut sichtbares Bettzeug von Komfort 1–3 aus. Jede
  Stufe regeneriert morgens mehr Zufriedenheit; Stufe 3 kann einmal pro Tag
  Karotte, Weizen oder Goldnugget schenken.
- Ein am Amboss benanntes Namensschild bindet den nächsten eigenen Gooby
  explizit an den Stall und rendert seinen Namen an der Frontplatte.
- Die Morgenroutine hoppelt aus dem Eingang, streckt und gähnt, trillert
  glücklich und läuft anschließend zum online anwesenden Besitzer.

**Fixes**
- Ein gebundener Stall hat absolute Priorität vor näheren freien Ställen.
  Gooby reist abends bis zur konfigurierten Reichweite heim, vergisst sein
  Zuhause außerhalb davon aber nicht.
- Beim Abbau eines belegten Stalls wird Gooby kollisionssicher ausgeworfen,
  geweckt, vom alten Zuhause gelöst und reagiert sichtbar traurig.

**Polish**
- Drei Bettzeug-Overlays, Innenraum und Namensplatte, `hutch_enter`,
  `hutch_exit`, `sleep_curl_tight`, Eingang-Zzz, Rascheln und Holzknarzen.
- Das Loot-Table gibt alle eingebauten Wollschichten zurück. Config:
  `home.duskTravelRadius` (Standard 96); Suite: 70 GameTests.
- Headless-Gates prüfen Navigation, Daten, Loot und Asset-Verträge; die
  Sichtkontrolle aller vier Facings und Namensschild-Schrift bleibt Client-QA.

### EN

**New**
- Hutch 2.0 persists comfort, resident, nameplate, occupancy, and last morning
  gift day in a synchronized block entity. Its open four-way shell renders
  Gooby in a tight interior sleep curl.
- Right-clicking with wool adds visible bedding through comfort levels 1–3.
  Each level restores more morning satisfaction; level 3 can gift a carrot,
  wheat, or gold nugget once per day.
- An anvil-named name tag explicitly binds the nearest owned Gooby to the
  hutch and renders that resident's name on the front plate.
- The dawn routine hops through the entrance, stretches and yawns, trills
  happily, then walks toward an online owner.

**Fixes**
- A bound hutch has absolute priority over closer free hutches. Gooby travels
  home at dusk within the configurable radius without forgetting a farther
  home when it must sleep rough.
- Breaking an occupied hutch safely ejects and wakes Gooby, clears the broken
  home, and produces a visibly sad response.

**Polish**
- Three bedding overlays, interior and nameplate, `hutch_enter`, `hutch_exit`,
  `sleep_curl_tight`, doorway Zzz particles, fabric rustle, and wood creak.
- The loot table returns every installed wool layer. Config:
  `home.duskTravelRadius` (default 96); suite: 70 GameTests.
- Headless gates cover navigation, data, loot, and asset contracts; visual
  review of all four facings and nameplate text remains client QA.

---

## v3.6.0 — „Kunststücke" / “Tricks & Training” · 2026-08-11

### DE

**Neu**
- Vier persistente Kunststücke (`Drehung`, `Pfötchen`, `Flauf`, `Sprich`) lassen
  sich mit Trainingshappen in drei Sternstufen lernen und per
  Leerhand-Doppelklick vorführen.
- Die Pfeife ruft in der Luft den nächsten eigenen Gooby; jenseits von 32
  Blöcken nutzt er den sicheren Teleport. Shift-Luftpfiff öffnet ein
  klickbares Kunststückmenü, der Tooltip merkt den letzten Kommandomodus.
- Das lokalisierte Ingame-`Gooby-Handbuch` nutzt den Vanilla-Buchbildschirm,
  wird beim ersten Zähmen config-gesteuert einmal vergeben und ist craftbar.

**Fixes**
- Wilde und fremde Goobys verwenden beim Pfeifen nun ein eigenes tiefes
  Ablehnungssignal statt desselben Erfolgsquietschens.
- Kunststücke laufen über die priorisierte Actions-Schicht und können nicht
  durch Mikroanimationen stecken bleiben.

**Polish**
- Sternfortschritt in der Shift-Anzeige, zwei Advancements, fünf Clips, zwei
  neue Sounds, zwei handgezeichnete Item-Icons und vollständige DE+EN-Seiten.
- Config: `bonding.giveHandbookOnTame`; Suite: 63 GameTests. Der Headless-Gate
  prüft Clip-/Asset-Verträge; der visuelle Foot-slide-Framecheck bleibt Client-QA.

### EN

**New**
- Four persistent tricks (`Spin`, `High Five`, `Flop`, `Speak`) train through
  three stars with Training Treats and perform on an empty-hand double-use.
- Using the whistle in air calls the nearest owned Gooby; beyond 32 blocks it
  uses the safe teleport. Sneak-air-use opens a clickable trick menu, while
  the tooltip remembers the last command mode.
- The localized in-game `Gooby Handbook` uses the vanilla book screen, is
  config-gated and granted once on first taming, and can also be crafted.

**Fixes**
- Wild and foreign Goobys now use a distinct low denial cue instead of the
  same squeak as a successful whistle command.
- Tricks run on the priority actions layer and cannot stall behind micro motion.

**Polish**
- Stars in Shift inspection, two advancements, five clips, two new sounds, two
  hand-drawn item icons, and complete DE+EN handbook pages.
- Config: `bonding.giveHandbookOnTame`; suite: 63 GameTests. The headless gate
  verifies clip/asset contracts; visual foot-slide frame review remains client QA.

---

## v3.5.0 — „Bande des Vertrauens" / “Bonds of Trust” · 2026-08-11

### DE

**Neu**
- Freundschaft hat vier abgeleitete Stufen: Fremd (0–19), Kumpel (20–49),
  Freund (50–89) und Beste Freunde (90–100), jeweils mit lesbarer Feier.
- Stufen schalten Winken, Sprint-Tag-along, Geschenke, Reiten, goldene Geschenke
  und eine tägliche Beste-Freunde-Kuscheleinheit mit Regeneration I frei.
- Erste Fütterung, erstes Streicheln und Stufenaufstiege bleiben als
  Erinnerungen erhalten; nach sieben Ingame-Tagen erinnert sich Gooby daran.
- Benannte Goobys reagieren config-gesteuert, wenn ihr Besitzer ihren Namen im
  Chat sagt.

**Fixes**
- Freundschaft spammt die Actionbar nicht mehr bei jedem +2: nur Stufenwechsel
  und überschrittene Fünfergrenzen werden angezeigt.
- Migration: Reiten benötigt nun die Stufe **Freund (50)** statt des alten
  Einzelwerts 30. Besitzer können ihren eigenen gezähmten Gooby weiterhin reiten.

**Polish**
- Stufen-Icon in der Shift-Anzeige, 12 stufenbezogene Begrüßungen/Erinnerungen,
  `snuggle_time`-Advancement, drei Clips, Signatur-Jingle und langes Schnurren.
- Config: `bonding.nameRecognition`; Suite: 57 GameTests.

### EN

**New**
- Friendship now has four derived tiers: Stranger (0–19), Buddy (20–49),
  Friend (50–89), and Best Friend (90–100), each with a readable celebration.
- Tiers unlock waving, sprint tag-along, gifts, riding, golden gifts, and one
  daily Best-Friend snuggle granting Regeneration I.
- First feed, first pet, and tier-ups persist as memories; after seven in-game
  days Gooby recalls one of them.
- Custom-named Goobys react, behind a config gate, when their owner says their
  name in chat.

**Fixes**
- Friendship no longer spams the actionbar for every +2; only tier crossings
  and crossed multiples of five display progress.
- Migration: riding now requires the **Friend tier (50)** instead of the old
  standalone value 30. Owners can still ride their own tamed Gooby.

**Polish**
- Tier icon in Shift inspection, 12 tier greetings/memories,
  `snuggle_time` advancement, three clips, signature jingle, and long purr.
- Config: `bonding.nameRecognition`; suite: 57 GameTests.

---

## v3.4.0 — „Wachsamer Gefährte" / “Streetwise Companion” · 2026-08-11

### DE

**Neu**
- Gooby erkennt feindliche Mobs in 12 Blöcken, schaut zur Gefahr, schlägt mit
  eigenem Alarmton an und warnt den Besitzer aus einer mutigen Schutzposition.
- Creeper erhalten einen früheren, lauteren Alarm. Wilde Goobys fliehen nach
  Schaden; Feuer, Kakteen und Pulverschnee werden schon bei der Wegsuche gemieden.
- Regen schickt Gooby unter Dächer oder in den Stall. Bei Gewitter versteckt er
  sich hinter dem Besitzer; trockenes Fell wird mit Wassertropfen abgeschüttelt.
- Morgen, Mittag und Abend modulieren Streunen, Buddeln und gemütliches Sitzen.

**Fixes**
- Follow-Teleports prüfen nun zusätzlich Weltgrenze, Bauhöhe, Kollisionen,
  Flüssigkeiten und Gefahrblöcke; ein Lava-Ziel wird nie akzeptiert.
- Alle echten GameTest-Spieler laufen über den zentralen `TestPlayers`-Lifecycle.

**Polish**
- Vier neue Clips (`alert`, `shake_off_water`, `hide_behind`, `shiver`), vier
  Alarm-Lines, zwei Alarmvarianten und ein Fellschütteln mit DE-Untertiteln.
- Config: `awareness.creeperAlarm` und `awareness.alertRadius`; Suite: 49 GameTests.

### EN

**New**
- Gooby detects hostiles within 12 blocks, faces the danger, sounds a distinct
  alarm, and warns its nearby owner from a brave guard position.
- Creepers receive an earlier, louder warning. Wild Goobys flee after damage;
  fire, cactus, and powder snow are avoided during pathfinding.
- Rain sends Gooby toward a roof or hutch. Thunder makes it hide behind its
  owner; drying fur triggers a water-droplet shake.
- Morning, midday, and evening modulate strolling, digging, and cozy sitting.

**Fixes**
- Follow teleports now validate world borders, build height, collisions,
  fluids, and hazard blocks; a lava target is never accepted.
- Every real GameTest player now uses the central `TestPlayers` lifecycle.

**Polish**
- Four new clips (`alert`, `shake_off_water`, `hide_behind`, `shiver`), four
  alarm lines, two alarm variants, and one fur shake with EN subtitles.
- Config: `awareness.creeperAlarm` and `awareness.alertRadius`; suite: 49 GameTests.

---

## v3.3.0 — „Launen & Bedürfnisse" / “Moods & Needs” · 2026-08-11

### DE

**Neu**
- Sechs serverautoritative, synchronisierte Moods: Glücklich, Zufrieden,
  Hungrig, Schläfrig, Einsam und Ängstlich; 30-s-Mindestdauer verhindert Flattern.
- Letzte Fütterung und Besitzer-Abwesenheit sind persistent. Hungriges Füttern
  gibt +2 Freundschaft, einsames Streicheln doppelte Zufriedenheit.
- Shift-Blick-Inspektion, Nutella-Gedankenpartikel, 11 Mood-Lines, Bettelpose,
  hängende Ohren und Happy-Bounce.

**Fixes**
- Zufriedenheit sinkt im Schlaf nicht mehr; schläfrige Goobys betteln nachts
  nicht um Streicheleinheiten.
- Mood, Fütterzeit und Abwesenheitszähler überstehen Save/Reload.

**Polish**
- Hungriges Wimmern und einsames Seufzen mit je zwei Varianten und Untertiteln.
- Config: `needs.hungerHours` und `needs.lonelyMinutes`; Suite: 41 GameTests.

### EN

**New**
- Six server-authoritative synchronized moods: Happy, Content, Hungry, Sleepy,
  Lonely, and Scared; a 30-second dwell prevents flicker.
- Last feeding and owner absence persist. Hungry feeding gives +2 friendship;
  lonely petting gives double satisfaction.
- Shift-look inspection, Nutella thought particles, 11 mood lines, begging,
  drooped ears, and happy bounce.

**Fixes**
- Satisfaction no longer decays during sleep; sleepy Goobys do not request
  pets at night.
- Mood, feeding time, and absence counter survive save/reload.

**Polish**
- Hungry whines and lonely sighs have two variants each and full subtitles.
- Config: `needs.hungerHours` and `needs.lonelyMinutes`; suite: 41 GameTests.

---

## v3.2.0 — „Goobys Stimme" / “Voice of Gooby” · 2026-08-11

### DE

**Neu**
- 29 neue, deterministisch erzeugte Audiodateien liefern Varianten für
  Quietschen, Schnurren, Boing, Plop, Schmatzen, Schnarchen und Bürsten.
- Happy-, Neutral- und Sleepy-Ambient-Pools reagieren auf Zufriedenheit und
  Tageszeit.
- Der Streichelnde hört einen positionsgebundenen Schnurr-Loop mit weichem
  Fade-in/-out. Eine synchronisierte Petter-ID verhindert Observer-Leaks.
- Wander, Follow und Stay haben drei lernbare Pfeiftonmuster.
- Neue Config `audio.goobyVolumeScale` (0,0–2,0, Standard 1,0).

**Fixes**
- `playSound` nutzt wieder Vanillas Seitenlogik; Reit-/Schrittgeräusche werden
  nicht client- und serverseitig doppelt abgespielt.
- Schlaf unterdrückt normalen Ambient weiterhin vollständig; Schnarchen bleibt
  ein gedämpftes räumliches Ereignis.
- Sämtliche Gooby-One-shots erhalten zentral ±10 % Pitch-/Volume-Jitter.

**Polish**
- Jeder Eintrag in `sounds.json` besitzt einen geprüften DE+EN-Untertitel.
- Essen enthält weiterhin die Animationsebene, nun mit drei verschieden
  rhythmisierten Schmatzfolgen; Bürsten klingt weich statt wie Schnurren.
- 35 fail-closed GameTests prüfen Mood-Pools, Pfeifenmapping,
  Petter-Lokalität, Untertitel und Variantenzahlen.
- Headless-QA: Sounddateien, Registry, Auswahl und Untertitel sind vollständig
  runtime-getestet; ein subjektiver Zwei-Spieler-Blindhörtest ist ohne
  Audioausgabe dieser Umgebung nicht durchführbar.

### EN

**New**
- 29 newly generated deterministic audio files provide variants for squeaks,
  purrs, boings, plops, munches, snores, and brushing.
- Happy, neutral, and sleepy ambient pools react to satisfaction and time.
- The petter hears a position-bound purr loop with soft fade-in/out. A synced
  petter ID prevents observer leaks.
- Wander, Follow, and Stay use three learnable whistle patterns.
- New `audio.goobyVolumeScale` config (0.0–2.0, default 1.0).

**Fixes**
- `playSound` uses vanilla side handling again, preventing client/server
  duplication for riding and step sounds.
- Sleep still suppresses normal ambient completely; snores remain softly
  attenuated positional events.
- Every Gooby one-shot receives centralized ±10% pitch/volume jitter.

**Polish**
- Every `sounds.json` event has verified DE+EN subtitles.
- Eating retains animation layering with three differently paced munch
  sequences; brushing sounds like soft fabric instead of a generic purr.
- 35 fail-closed GameTests verify mood pools, whistle mapping, petter locality,
  subtitles, and variant counts.
- Headless QA: files, registration, selection, and subtitles are fully runtime
  tested; a subjective two-player audio blind test cannot run without audio
  output in this environment.

---

## v3.1.0 — „Lebenszeichen" / “Alive & Blinking” · 2026-08-11

### DE

**Neu**
- Eine eigene Micro-Animationsschicht lässt Gooby alle 3–7 Sekunden blinzeln,
  alle 4–10 Sekunden schnuppern sowie zufällig mit den Ohren und bei hoher
  Zufriedenheit mit dem Schwanz wackeln.
- Nach dem Aufwachen spielt Gooby einen Stretch-&-Yawn-Clip mit lokalem
  Gähn-Sound. Näschenwackeln besitzt zwei lokale Schnuppervarianten.
- Neue Übergänge `sit_down`, `stand_up`, `sleep_down` und `wake_up` ersetzen
  harte Pose-Sprünge.
- Fälle über zwei Blöcke enden in einem weichen Landing-Squash samt Wolkenpuff.

**Fixes**
- Sprechblasen verschwinden hinter Wänden und an unsichtbaren Goobys.
- Action-Clips besitzen Priorität: Streicheln, Fressen, Winken und Landen
  können einander nicht mehr mitten in einer Bewegung abschneiden.
- Der in 3.0 eingeführte `hat_anchor` folgt allen neuen Kopf- und
  Übergangsposen ohne festen Renderer-Offset.

**Polish**
- Eigene Lid-Flächen und neue Texturzeilen schließen die Augen beim Blinzeln
  und Schlafen sauber.
- Kopf-Tracking wird geglättet; Idle-Wabbeln ist bei sichtbarer Sprechblase um
  15 % reduziert.
- `docs/ANIMATION_GUIDE.md` dokumentiert Controller-Priorität, Clip-Längen und
  Keyframe-Zahlen. Die Suite wächst auf 31 fail-closed GameTests.
- Headless-QA: Modell, Clips, Controller und Keyframes sind vollständig
  implementiert und strukturell/runtime-seitig getestet; eine GPU-Aufnahme der
  geforderten 60-Sekunden- und Zwei-Client-Beobachtung ist hier nicht verfügbar.

### EN

**New**
- A dedicated micro-animation layer makes Gooby blink every 3–7 seconds,
  sniff every 4–10 seconds, randomly twitch its ears, and wag its tail at high
  satisfaction.
- Waking triggers a stretch-and-yawn clip with a local yawn sound. Nose wiggle
  uses two local sniff variants.
- New `sit_down`, `stand_up`, `sleep_down`, and `wake_up` bridges replace hard
  pose changes.
- Drops over two blocks end in a soft landing squash and cloud puff.

**Fixes**
- Speech bubbles are hidden behind walls and on invisible Goobys.
- Action clips have priority: petting, eating, waving, and landing can no
  longer cut one another off halfway through.
- The v3.0 `hat_anchor` follows every new head pose and transition without a
  fixed renderer offset.

**Polish**
- Dedicated eyelid planes and texture rows close eyes cleanly during blinks
  and sleep.
- Head tracking is eased; idle body sway is reduced by 15% while a speech
  bubble is visible.
- `docs/ANIMATION_GUIDE.md` records controller priority, clip lengths, and
  keyframe counts. The fail-closed suite grows to 31 GameTests.
- Headless QA: model, clips, controllers, and keyframes are fully implemented
  and structurally/runtime tested; the requested 60-second and two-client GPU
  recordings are unavailable in this environment.

---

## v3.0.0 — „Schienen & Schrauben" / “Release Rails” · 2026-08-11

### DE

**Neu**
- Der **Schutzengel** fängt Mob-Schaden an gezähmten Goobys vollständig ab.
  Unter starkem Schutzdruck gerät Gooby kurz in Panik und flieht bei höchstens
  30 % Restdruck zum Besitzer oder zum gemerkten Hasenstall. Der Besitzer
  erhält eine Chat-Nachricht.
- Neue Server-Optionen `protection.goobyMobProtection` und
  `protection.escapeToOwner` (beide standardmäßig aktiv).
- Release-Schiene mit strengem DE/EN-Paritätscheck, Release-Skript,
  nummeriertem Jar-Archiv und vollständigem DE+EN-Spieler-Handbuch.

**Fixes**
- Hostile Mobs können gezähmte Goobys nicht mehr unbemerkt töten. Falls ein
  Tod durch `/kill`, Leere oder abgeschalteten Schutz doch eintritt, fällt der
  getragene Hut sicher als Item.
- Nutella-Gläser speichern nun eine persistente UUID-Lease. Ein entladener
  Claimer-Chunk kann keinen zweiten Gooby mehr erzeugen; Selbstheilung erfolgt
  erst nach 15 Minuten und erfolgloser serverweiter UUID-Suche.
- Das fröhliche Todesquietschen wurde durch zwei leise traurige Wimmer-Varianten
  ersetzt.
- Klickspam zieht Zufriedenheit nur einmal pro fünf Sekunden und Spieler ab;
  alte temporäre Spieler-Einträge werden nach zehn Minuten entfernt.
- Freuden-Hopser beim Reiten werden nur noch serverseitig gewürfelt; kein
  doppeltes/unsynchrones Audio mehr.
- Der Hasenstall blockiert seinen Innenraum nicht mehr. Gooby läuft bis zum
  Innenanker und schläft wirklich im Stall.

**Polish**
- Hüte hängen an `hat_anchor`, einem Kind des animierten Kopfes, statt an einem
  festen Höhen-Offset. So folgen sie Schlaf-, Fress- und Streichelposen.
- Der Stall hat ein sichtbar offenes Shell-Modell.
- 26 fail-closed GameTests decken Schutzengel, Flucht, Hut-Drop, Jar-Lease,
  Anti-Spam, Sprachparität, Stall-Innenraum und Hat-Anchor ab.
- Hinweis zur Headless-QA: Hat-Anchor und Stallmodell wurden als Ressourcen
  vollständig implementiert und automatisiert strukturell geprüft; eine
  GPU-Client-Aufnahme ist in dieser Umgebung nicht verfügbar.

### EN

**New**
- **Guardian Angel** fully blocks mob damage to tamed Goobys. Under heavy
  protection pressure, Gooby briefly panics and at 30% remaining pressure
  escapes to its owner or remembered rabbit hutch. The owner receives a chat
  message.
- New server options `protection.goobyMobProtection` and
  `protection.escapeToOwner` (both enabled by default).
- Release rails with strict DE/EN parity, a fail-closed release script,
  numbered jar archive, and complete DE+EN player manuals.

**Fixes**
- Hostile mobs can no longer silently kill tamed Goobys. If `/kill`, the void,
  or disabled protection still causes death, the equipped hat safely drops.
- Nutella jars now persist a UUID lease. An unloaded claimant chunk cannot
  cause a duplicate Gooby; self-healing waits 15 minutes and then performs a
  server-wide UUID lookup.
- The cheerful death squeak is replaced by two restrained sad-whimper variants.
- Click spam removes satisfaction only once per player every five seconds;
  stale transient player entries are pruned after ten minutes.
- Riding joy hops roll on the server only, eliminating doubled/desynced audio.
- The rabbit hutch no longer blocks its interior. Gooby reaches an interior
  anchor and actually sleeps inside.

**Polish**
- Hats attach to `hat_anchor`, a child of the animated head, instead of a fixed
  height offset, so they follow sleep, eating, and petting poses.
- The hutch uses a visibly open shell model.
- 26 fail-closed GameTests cover Guardian Angel, escape, hat drops, jar leases,
  anti-spam, language parity, the hutch interior, and the hat anchor.
- Headless QA note: the hat anchor and hutch model are faithfully implemented
  and structurally verified by automated tests; GPU client recording is not
  available in this environment.

---

## v2.0.0 — „Best Friends" (Basis / base) · 2026-08-10

**DE** — Importierte Basisversion in dieser Repo. Enthält echte Zähmung & Besitz,
Freundschaftssystem (0–100 pro Spieler), Gooby-Pfeife (Wander/Follow/Stay),
Geschenk-System, aufsetzbare Hüte und einen Advancement-Baum. GeckoLib-Modell,
eigene Sounds, Entity-KI (Follow/Sit/Sleep/Dig), GameTests.

**EN** — Imported base version in this repo. Real taming & ownership, friendship system
(0–100 per player), Gooby whistle (wander/follow/stay), gift system, wearable hats and
an advancement tree. GeckoLib model, custom sounds, entity AI (follow/sit/sleep/dig),
GameTests.

_Nächste Versionen folgen dem Plan in `docs/PLAN_15_VERSIONS.md`._
_Upcoming versions follow the roadmap in `docs/PLAN_15_VERSIONS.md`._
