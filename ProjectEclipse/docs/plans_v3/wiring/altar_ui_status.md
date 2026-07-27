# Altar UI 2 (F-074) — Status

User-Feedback F-074: "Verbessere das Altar UI noch etwas mehr das alles etwas
leichter lesbar ist und beim Shop Tab mach das man seinen Kauf bestätigen muss
plus so eine Kauf Animation hat und dann so eine kurze Cutscene danach je
nachdem was man geholt hat."

## Gebaut

### 1. Lesbarkeit (`client/altar/AltarScreen.java`, komplett überarbeitet)
- Panel minimal breiter/höher (Clamp 340–560 × 240–400), vertikale Hairline
  zwischen Fortschritts- und Shop-Spalte, klarere Sektionstrennung.
- Anforderungszeilen: 24 px Zeilenhöhe (vorher 18), dickerer Fortschrittsbalken
  mit Innenrahmen, ✓-Haken statt Balken bei erfüllten Zeilen, Zähler in
  Klartext; zu lange Item-Namen werden ellipsiert und bekommen einen
  Hover-Tooltip mit vollem Namen + exaktem Stand.
- Angebotszeilen: adaptive Höhe 20–28 px (offer-reiche Tage clippen nicht mehr),
  Preis als gerahmter Chip mit Währungs-Icon rechts, grüne/rote Kante links
  als Leistbarkeits-Signal, Pool-Käufe klar als "Team-Pool" markiert.
- Footer fix unten: persönliches Guthaben und Team-Pool je mit Währungs-Icon
  und heller Zahl (Kontrast TEXT statt DIM), Icon-Positionen werden für die
  Kauf-Animation gemerkt.
- Boss-Hinweisblock: Fließtext heller (TEXT @ 85 % statt DIM).

### 2. Kaufbestätigung (Shop-Tab)
- Klick auf ein Angebot kauft NICHT mehr direkt, sondern öffnet ein modales
  Overlay (abgedunkelter Screen + erhöhtes Panel): Belohnungs-Item als Icon,
  Angebotsname, Preis aufgeschlüsselt (Anzahl × Währungs-Icon + echter
  Währungsname), Guthaben-nach-Kauf bzw. "fehlen dir X" in Rot, Buttons
  "Kaufen" (deaktiviert wenn zu teuer) / "Abbrechen".
- Enter bestätigt, ESC bricht ab, Klick außerhalb des Panels bricht ab.
  Während das Overlay offen ist, sind die Listen-Widgets samt Tooltips stumm
  (Tooltip-Unterdrückung wird beim Schließen wiederhergestellt).
- Server-Guard unverändert: `handleBuy` validiert weiter Reichweite, Angebot,
  Tag und Guthaben — das Overlay ist reine UX, keine Autorität.

### 3. Kauf-Animation im Screen
- Nach Bestätigung fliegen 6 Währungs-Icons gestaffelt vom Footer-Zähler in
  einer leichten Bogenkurve zur gekauften Zeile (Roulette-Tick pro Ankunft),
  die Zeile pulst golden auf (additiver Glow + Rahmen) und 10 Funken sprühen
  radial; Win-Sting (`UiSounds.rouletteWin`) beim Pulsbeginn. Nach ~1,25 s
  schließt der Screen selbst — die Welt-Zeremonie übernimmt.
- `reducedFx`: keine Flug-/Puls-Frames, nur Sting + schneller Close (~0,3 s).
- Fehlkauf (Server sagt nein): kurzer roter Flash auf der Zeile + Error-Sound,
  Screen bleibt offen. Watchdog: bleibt die Antwort > 100 Ticks aus, entsperrt
  sich der Screen selbst.
- Alles `GuiGraphics`, keine Shader.

### 4. Nach-Kauf-Mini-Zeremonie in der Welt (`economy/AltarBuyCeremony.java`, NEU)
- Serverseitig, startet 28 Ticks nach dem Kauf (UI-Animation läuft aus),
  sichtbar für ALLE Spieler in 48 Blöcken, ~3–6 s je Kategorie.
- Kategorie datengetrieben aus der Offer-Form (kein ID-Katalog):
  - `TEAM` (offer.item() == null — Eclipse's Favor, Doppel-XP, Supply Beacon):
    zweiarmige aufsteigende Lichtspirale + violett→goldene Farbwelle
    (Screen-Shockwave + physischer Staubring), Abschluss-Levelup-Ring.
  - `GEAR` (jedes andere Item-Angebot): das gekaufte Item steigt als
    `ItemDisplay` aus der Altarkrone, dreht sich im Lichtspot (END_ROD-Kreis)
    und fliegt in einer Bogenkurve in den Käufer (Live-Retargeting), Catch mit
    heart_burst + Pickup-Pop. Käufer > 24 Blöcke weg → Burst an der Krone.
  - `HEART` (Belohnung ist `VitaeShardItem`): dreifach gestaffelte
    Licht-Fontäne (altar_pillar-Emitter), gerichtete END_ROD-Jets,
    Glockenlinie mit steigender Tonhöhe, rosa-goldener Ascheregen.
- Nur vorhandene Primitive (Quasar-Emitter, FX_SHOCKWAVE, sendParticles,
  Display-Muster aus `HeraldSummonSequence`) — läuft auch für Photon-lose /
  reduced-FX-Clients über die üblichen Fallbacks.
- Despawn-Garantie: Tag `eclipse_altar_buy_gift`, Live-UUID-Set, Stray-Sweep
  bei EntityJoin, Cleanup bei ServerStopped, max. 8 parallele Runs.

## Geänderte/neue Dateien
- `src/main/java/dev/projecteclipse/eclipse/client/altar/AltarScreen.java` (überarbeitet)
- `src/main/java/dev/projecteclipse/eclipse/network/altar/AltarPayloads.java` (additiv: rewardItemId, S2CAltarBuyResultPayload, Erfolgs-Erkennung, Zeremonie-Trigger; Version v6altarui4)
- `src/main/java/dev/projecteclipse/eclipse/economy/AltarBuyCeremony.java` (NEU)
- `docs/plans_v3/langdrop/altar_ui2.json` (NEU — 6 confirm-Keys en+de)
- `docs/plans_v3/wiring/altar_ui_wiring.md` (NEU)
- `docs/plans_v3/wiring/altar_ui_status.md` (diese Datei)

## Verifikation
- Compile-Check ohne Gradle: alle drei Java-Dateien samt transitiver Hülle mit
  `javac` (JDK 21) gegen den NeoForge-1.21.1-Klassenpfad aus dem Gradle-Cache
  kompiliert — 0 Fehler (nur vorbestehende Deprecation-Notes).

## Offen (zentral zu verdrahten — siehe altar_ui_wiring.md)
1. Langdrop `altar_ui2.json` in die echten Lang-Dateien mergen (sonst zeigt
   das Overlay rohe `gui.eclipse.altar.confirm.*`-Keys).
2. `WIRING(altar-model)`-Hook in `AltarBuyCeremony.Run#beatOpening()` an die
   "gift"-Animation des neuen GeckoLib-Altarmodells hängen (Parallel-Welle).

## Testanleitung (nach zentralem Build)
1. `/give @s eclipse:umbral_shard 64`, Splitter am Altar banken (Sneak-Use),
   Altar öffnen → Shop-Tab.
2. Lesbarkeit: Anforderungen mit ✓/Balken, Preise als Chip mit Icon, Footer
   mit zwei Icon-Zählern, lange Namen → Tooltip.
3. Angebot anklicken → Bestätigungs-Overlay. ESC/Außenklick bricht ab,
   Enter oder "Kaufen" kauft. Bei zu wenig Guthaben: "Kaufen" deaktiviert,
   rote "fehlen dir X"-Zeile.
4. Kauf bestätigen → Icons fliegen vom Footer zur Zeile, Gold-Puls + Funken,
   Screen schließt (~1,25 s) → am Altar startet die Welt-Zeremonie:
   - Doppel-XP/Favor/Beacon → Spirale + Farbwelle (TEAM),
   - Ausrüstungs-Item → ItemDisplay steigt, dreht, fliegt in dich (GEAR),
   - Herzfragment → Fontäne + Glocken (HEART).
5. Fehlerpfad: per zweitem Client dasselbe limitierte Angebot schneller
   wegkaufen → roter Flash + Error-Sound, Screen bleibt offen.
6. Cleanup-Probe: während der GEAR-Flugphase `/kill
   @e[tag=eclipse_altar_buy_gift]` → Zeremonie endet leise, kein Geister-Item.
7. `reducedFx` aktivieren → Kauf ohne Flug/Puls, nur Sting + schneller Close;
   Welt-Zeremonie läuft (Quasar degradiert wie üblich).

## Risiken
- `ShopEntry`-Wire-Format geändert → Registrar-Version wurde auf `v6altarui4`
  gehoben; gemischte Client/Server-Stände lehnen sich sauber gegenseitig ab.
- Kauf-Erfolg wird in `handleBuy` über die Guthaben-Differenz erkannt (kein
  Eingriff in `ShardEconomy.buy`): sollte ein künftiges Angebot GENAU 0
  kosten, würde ein abgelehnter Kauf als Erfolg gewertet — aktuell kostet
  jedes Angebot > 0, bei 0-Kosten-Angeboten `ShardEconomy.buyById` auf
  boolean umstellen.
- GEAR-Zeremonie: Wechselt der Käufer während des Flugs die Dimension, endet
  der Run leise am Altar (Burst an der Krone) — kein Crash, kein Leak.
