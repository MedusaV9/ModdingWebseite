# IDEEN-IMPROVER D — Haus, Bau & Garten (Animal-Crossing-Bau-System)

Godot 4.4 · Referenz: `/workspace/GOOBY` (Web-Version) · USER-WISHES §D (Zeilen 39–52)
Asset-Basis geprüft: `public/assets/kenney/furniture-kit` (68 GLBs), `nature-kit` (37),
`city-kit-suburban`, `car-kit` (inkl. `delivery.glb`!), `survival-kit` (`bucket.glb`),
`kaykit-furniture`, `kaykit-city`, `kaykit-restaurant`, `itch/aline-furniture`,
`itch/tinytreats-*` (bubbly-bathroom, charming-kitchen, house-plants, bakery-interior,
pleasant-picnic, pretty-park, baked-goods). Blender 4.0.2 auf der VM (`/usr/bin/blender`).

Altes System (Migration-Quelle): Slot-basiert, KEIN Grid —
`furniture.placed = { 'roomId:slotId': itemId }`, `furniture.owned = string[]`,
`decor.wallpaper/floor = { roomId: id }`, `garden = { plotsOwned, plots[6] }`
(`src/systems/furniturePlacement.js`, `src/data/furniture.js`, `src/systems/garden.js`).

---

## 1. Grid-Datenmodell

### 1.1 Grundentscheidungen

- **Zellgröße 0.5 m** (halbes Kenney-Furniture-Modul). Kenney-Möbel sind ~1 m-Raster;
  0.5 m erlaubt AC-typische „halbe Schritte" (Stuhl neben Tisch, Deko dazwischen), ohne
  Free-Placement-Chaos. Footprints werden in Zellen angegeben (Sofa = 4×2 Zellen = 2×1 m).
- **Zwei getrennte Grid-Typen:** `RoomGrid` (rechteckig, pro Raum, Boden + 4 Wände +
  Decke) und `GardenGrid` (großes, wachsendes Außen-Grid, eigenes Kapitel 6).
- **Kein Godot-GridMap-Node.** GridMap ist für Tile-Welten; wir brauchen Footprints,
  Layer und Validierungslogik → eigene, reine Daten-Klasse `GridData` (RefCounted, kein
  Node) + dünner Renderer. Vollständig headless-testbar (GUT-Unit-Tests ohne Szene).

### 1.2 Layer & Zell-Semantik

| Layer | Trägt | Blockt Gooby? | Beispiele |
|---|---|---|---|
| `RUG` | Boden, unterste Ebene | nein | Teppiche — Möbel dürfen DRAUF stehen |
| `FLOOR` | Boden | ja (per Item-Flag) | Sofa, Bett, Regal, Pflanze |
| `SURFACE` | auf `FLOOR`-Items mit `surface`-Def | nein | Toaster auf Küchenzeile, Buch auf Tisch |
| `WALL` | Wandzellen (Spalte × Höhenreihe) | nein | Bilder, Hängeschrank, Lampe, **Fenster** |
| `CEILING` | Deckenzellen (gleiche XY wie Boden) | nein | Deckenlampe, Ventilator, Girlande |

- Jede Bodenzelle hält max. 1 `RUG` + 1 `FLOOR`-Belegung (Belegung = Referenz auf die
  Item-Instanz, deren Footprint die Zelle überdeckt) + n `SURFACE`-Slots (kommen vom
  darunterliegenden Item, nicht von der Zelle).
- **Wände** sind 4 benannte Segmente (`N/E/S/W`) mit eigenem 2D-Grid: Breite = Raumbreite
  in Zellen, Höhe = 5 Reihen (2.5 m). Reihe 0–1 = „Möbelhöhe" (Hängeschrank kollidiert
  mit hohen FLOOR-Items davor → Flag `tallBlocksWall` am Bodenitem), Reihe 2–4 = frei.
- **Fenster** sind WALL-Items mit `requiresExterior: true`. Jede Wand hat im Raum-Setup
  ein Flag `exterior: bool` + `vista: "street"|"garden"|"sky"`. Fenster rendert
  Loch-Illusion: Shader-Portal-Quad mit Mini-Diorama dahinter (Straße mit vorbeifahrenden
  `car-kit`-Autos auf Spline, 1 gemeinsames Diorama pro Vista, von allen Fenstern geteilt).
  Kein echtes Wand-CSG (Performance/Clipping-Risiko) — Fensterrahmen sitzt AUF der Wand,
  „Glas" ist ein Viewport-Texture-Quad. Balkon-/2.-Etage-Fenster: `vista:"sky"` mit Vögeln.
- **Tür-Freihaltezonen:** `GridData.blocked: Vector2i[]` — Zellen vor Türen/Portalen und
  unter fest verbauten Strukturen (Treppe) sind nie belegbar (Baumodus zeigt sie schraffiert).
  Deckt Wunsch „Weg versperrt"-Gag ab: Gooby-Pathfinding (NavMesh wird nach jedem
  Bau-Commit neu gebacken) meldet Unerreichbarkeit → §F-Lava-Gag triggert Baumodus.

### 1.3 Katalog als Daten (Content-Pack-fähig)

Ein Möbel ist **reine Daten + GLB**. Katalog-JSONs werden beim Start gemerged:
`res://content/base/furniture/*.json` (mit IPA ausgeliefert) → `user://packs/<pack>/furniture/*.json`
(Auto-Updater, §B). Späteres Pack überschreibt per `id`. GLBs aus Packs lädt
`GLTFDocument.append_from_buffer()` zur Laufzeit (kein Import-Schritt nötig — der
Schlüssel dafür, dass „Möbel-Team" ohne .ipa shippen kann).

```json
{
  "schema": "gooby.furniture/1",
  "pack": "base",
  "items": [{
    "id": "loungeSofa",
    "name_de": "Gemütliches Sofa",
    "category": "sitzen",
    "layer": "FLOOR",
    "glb": "kenney/furniture-kit/loungeSofa.glb",
    "footprint": [4, 2],
    "blocksMovement": true,
    "tallBlocksWall": false,
    "surface": null,
    "price": 250,
    "sellBase": 90,
    "storageWeight": 3,
    "mandatorySlot": "couch",
    "variants": [
      { "id": "default" },
      { "id": "rosa", "tint": "#FFB7D5", "tintMaterials": ["fabric"] }
    ],
    "interactions": ["sit", "visitorSleep"],
    "wall": null,
    "craftOnly": false,
    "tags": ["wohnzimmer", "pflicht"]
  }, {
    "id": "window_small",
    "name_de": "Kleines Fenster",
    "category": "fenster",
    "layer": "WALL",
    "glb": "gooby/window_small.glb",
    "footprint": [2, 2],
    "wall": { "rows": [1, 2], "requiresExterior": true },
    "price": 400, "sellBase": 150, "storageWeight": 2
  }]
}
```

- `footprint` ist immer bei Rotation 0 (`[breite, tiefe]` in Zellen). **Rotation 4-way:**
  `rot ∈ {0,1,2,3}` (×90° im Uhrzeigersinn); belegte Zellen = Footprint um Anker-Zelle
  rotiert (Anker = Zelle unter Ursprungs-Ecke; bei rot 1/3 vertauschen sich B/T).
  WALL-Items rotieren nicht (Wand gibt Richtung vor), CEILING-Items nur wenn `footprint`
  nicht quadratisch.
- `surface`-Def macht ein Item zum Träger: `{"height": 0.75, "grid": [3, 1]}` →
  eigenes Mini-Grid oben drauf (SURFACE-Items dürfen nur `storageWeight ≤ 1` sein).
- `mandatorySlot`: `"bett"` / `"couch"` / `"kuehlschrank"` — pro Slot muss IMMER ≥1 Item
  platziert bleiben (Kapitel 2.4).

### 1.4 Save-Format (JSON, Teil des Godot-Saves)

```json
"home": {
  "v": 1,
  "rooms": {
    "living": {
      "wallpaper": "cream", "floor": "wood",
      "items": [
        { "uid": "i-000123", "item": "loungeSofa", "variant": "rosa",
          "at": [6, 4], "rot": 1 },
        { "uid": "i-000124", "item": "toaster", "at": [0, 0], "rot": 0,
          "on": "i-000200" },
        { "uid": "i-000125", "item": "window_small", "wall": "S", "at": [3, 1] },
        { "uid": "i-000126", "item": "ceilingFan", "ceil": [5, 4] }
      ]
    }
  },
  "unlockedRooms": ["hall", "living", "kitchen", "bathroom", "bedroom"],
  "storage": [ { "item": "chair", "variant": "default", "count": 3 } ],
  "storageCapacity": 100
}
```

- `uid` = fortlaufende Instanz-ID (Save-lokal) — nötig für `on`-Referenzen (Item steht
  auf Item) und Multiplayer-Sync (§C: Bauen während Besuch).
- **Update-fähigkeit:** Save referenziert nur Katalog-`id`s. Beim Laden: unbekannte `id`
  (Pack deinstalliert/umbenannt) → Item wandert automatisch ins Lager als
  `{"item":"__unknown__","origId":"..."}` und wird beim nächsten Pack-Update reaktiviert.
  Zellen werden NIE im Save gespeichert als belegt — Belegung wird beim Laden aus den
  Items rekonstruiert (Katalog-Footprint kann sich per Update ändern; Kollisions-Konflikt
  nach Update → betroffenes Item ins Lager + freundliche Meldung).

---

## 2. Baumodus-UX (Handy, Hoch- & Querformat)

### 2.1 Einstieg & Kamera

- Hammer-Button (FAB) im Raum-HUD → Kamera-Tween auf 55°-Schräg-Draufsicht, UI-Chrome
  weicht, Grid blendet als weiches Shader-Decal auf dem Boden ein (Zellen 0.5 m, jede
  2. Linie kräftiger = 1-m-Raster), Möbel bekommen dezenten Outline-Shader. Gooby setzt
  sich an den Rand und schaut zu (Idle-Kommentare: „Ohh, wird das schön?").
- **Wand-Modus:** Tap auf eine Wand (oder Wand-Tab) → Kamera schwenkt frontal auf die
  Wand, Wand-Grid-Overlay, Boden-Items werden halbtransparent. Decken-Modus analog
  (Kamera kippt leicht nach oben, Decken-Grid).

### 2.2 Interaktion (Touch-first)

- **Unteres Drawer-Panel** (BottomSheet, 30 % Höhe, hochziehbar): Tabs „Lager",
  Kategorien (Sitzen/Tische/Schlafen/Küche/Bad/Deko/Wand/Decke/Teppich), Suchfeld.
  Karten: gerendertes Vorschaubild (zur Buildzeit gebakt bzw. SubViewport-Snapshot bei
  Pack-Items), Name, Footprint-Badge „4×2", Lagerwert-Badge „⬛3".
- **Platzieren:** Tap auf Karte → Ghost erscheint in Raummitte. Drag: Ghost snappt auf
  Zellen, schwebt **1.5 Zellen über dem Finger** (Finger verdeckt sonst das Ziel!),
  Drop-Schatten zeigt die echten Zellen. Gültig = grüne Zellen-Tönung, Kollision = rote
  Tönung + kurzes Haptic + „Wackel"-Shake des Ghosts.
- **Am ausgewählten Item klebende Mini-Buttons** (Billboard über dem Item): ↻ Rotieren
  (90°, mit Snap-Sound), ✓ Bestätigen (ausgegraut bei Kollision), ✕ Abbrechen,
  📦 Einlagern, 🏷️ Goobay (nur wenn verkaufbar).
- **Verschieben:** Tap auf platziertes Item = auswählen (Buttons erscheinen), nochmal
  Tap-halten-ziehen = aufnehmen. Original-Zellen bleiben reserviert bis ✓/✕ (Abbrechen
  = zurückspringen mit Bounce).
- **Teppich-Logik:** RUG-Ghost ignoriert FLOOR-Kollision; FLOOR-Items auf Teppich ok.
- Pinch-Zoom + Zwei-Finger-Pan der Baukamera; „Raum-Reset-Blick"-Button.
- **Undo-Stack** (nur innerhalb der Bau-Session, 20 Schritte) — Handy-Vertipper passieren.

### 2.3 Lager (100 Kapazität, Lagerwert, Shed)

- Kapazität in **Lagerpunkten**, Basis 100. Jedes Item hat `storageWeight` 1–4
  (Deko 1, Stuhl 1, Tisch/Regal 2, Sofa/Bett 3, Ecksofa/Badewanne 4). Header-Bar im
  Drawer: „Lager 37/100" mit Farbverlauf grün→orange→rot; voll = Einlagern-Button
  gesperrt + Hinweis „Bau ein Shed im Garten!".
- **Shed:** Garten-Struktur, Footprint 2×2 **Garten**-Zellen (= 2×2 m, GardenGrid-Zellen
  sind 1 m, Kap. 6). Level 1 (+50 LP, 500 Münzen, Holzhütte) → Level 2 (+100 LP gesamt,
  1500, gestrichen + Fenster + Blumenkasten) → Level 3 (+200 LP gesamt, 4000, groß,
  Doppeltür, Wetterhahn). Upgrade = gleicher Grid-Platz, Modell-Swap mit Bau-Animation
  (Kap. 3). Shed ist begehbar-Fake: Tap öffnet direkt das Lager-UI mit Tür-auf-Sound.

### 2.4 Pflichtmöbel-Regeln

- `mandatorySlot`-Zähler pro Slot (`bett`, `couch`, `kuehlschrank`): Das LETZTE
  platzierte Item eines Slots kann **weder eingelagert noch verkauft** werden — Buttons
  ausgegraut mit Bubble „Gooby braucht sein Bett! 😤". Verschieben/Ersetzen geht immer:
  Einlagern wird erlaubt, sobald ein anderes Item desselben Slots platziert ist.
  (Couch = Multiplayer-Gästebett §C, Kühlschrank = Essens-Loop — deshalb Pflicht.)
- Verkaufen von Pflicht-Items, die NICHT das letzte sind (zweites Bett), ist erlaubt.

---

## 3. Erste-Male-Flow & Liefer-Cutscene

### 3.1 Onboarding-Bau (erstes Bett)

1. Neues Spiel: Schlafzimmer enthält nur Umzugskartons (`kaykit-city/box_A/B`).
   Quest-Bubble: „Platziere dein Bett!" → Baumodus öffnet automatisch, Drawer zeigt NUR
   das Bett (Rest gelockt mit „?"-Karten als Neugier-Teaser).
2. Nach ✓: **Hammer-Qualm-Animation** — Karton faltet sich auf, Gooby hüpft hin,
   Hammer-Prop in der Hand, 1.2 s Gehämmer (AnimationPlayer + `impact-sounds`),
   GPUParticles-Staubwolke verdeckt den Swap, Bett ploppt mit Squash-&-Stretch-Bounce
   rein, 2–3 Konfetti-Partikel, Gooby wischt sich die Stirn. Diese Animation läuft bei
   JEDEM Platzieren (ab dem 5. Mal verkürzt auf 0.4 s Puff; in Settings abschaltbar).
3. Info-Karte (einmalig): „Bauen kostet **keine Energie** — bau so viel du willst!"
   (Regel: Baumodus zieht nie Energie; global, nicht nur erstes Mal.)

### 3.2 Möbel-Lieferung-Cutscene (LKW + Clipboard)

Trigger: erster IKEA-/Baumarkt-Kauf einer Session (danach: Kurzversion = LKW fährt im
Fenster-Diorama vorbei + Notification „📦 Lieferung im Lager!"; Vollversion in Settings
erzwingbar).

Ablauf (~12 s, skippbar nach 1. Mal): Kamera auf Einfahrt (Vorgarten-Szene,
`city-kit-suburban/driveway-short`). Gooby steht mit **Clipboard** (Blender-Prop) an der
Einfahrt. `car-kit/delivery.glb` fährt auf Spline heran, Piep-piep-Rückwärtsgang, Gooby
winkt den LKW ein (Wink-Loop-Animation, schaut abwechselnd Clipboard/LKW, nickt wichtig).
Heckklappe auf, 2 Kartons rutschen raus, Gooby hakt auf dem Clipboard ab (✓-Stempel-Sound),
LKW hupt zweimal und fährt weg. Toast: „+<n> Möbel im Lager". Gekaufte Items landen im
**Lager** (nicht auto-platziert) — das macht den Baumodus zum natürlichen nächsten Schritt.

---

## 4. Haus-Upgrades & Raum=Szene-Struktur (Anschluss Improver A)

### 4.1 Raum-Registry als Daten

`res://content/base/rooms.json` (Content-Pack-fähig wie der Möbelkatalog):

```json
{
  "schema": "gooby.rooms/1",
  "rooms": [
    { "id": "living",   "scene": "res://scenes/home/rooms/living.tscn",
      "grid": [12, 10], "walls": { "S": { "exterior": true, "vista": "street" } },
      "startUnlocked": true, "price": 0 },
    { "id": "basement", "scene": "res://scenes/home/rooms/basement.tscn",
      "grid": [12, 10], "walls": {}, "price": 8000,
      "requires": [], "portal": { "from": "hall", "kind": "stairsDown" } },
    { "id": "floor2",   "scene": "res://scenes/home/rooms/floor2.tscn",
      "grid": [14, 10], "walls": { "S": { "exterior": true, "vista": "sky" } },
      "price": 15000, "portal": { "from": "hall", "kind": "stairsUp" } },
    { "id": "balcony",  "scene": "res://scenes/home/rooms/balcony.tscn",
      "grid": [8, 4], "outdoor": true, "price": 5000, "requires": ["floor2"],
      "portal": { "from": "floor2", "kind": "glassDoor" } }
  ]
}
```

- Kauf (im IGohbie „Haus"-Tab oder am Briefkasten): Bestätigen-Dialog → **Bau-Overlay**:
  Fassaden-Shot, Gerüst-Props + große Staubwolke + Hammer/Säge-Sound-Collage (~5 s,
  „Tada!"-Jingle), danach steht das Treppen-/Tür-Portal im Quellraum (Portal-Zellen
  wandern in `GridData.blocked`).
- Keller: keine Fenster, eigene düster-gemütliche Lichtstimmung, ideal für Werkstatt-
  Alternative/Hobbyraum. 2. Etage: frei bespielbarer Großraum. Balkon: `outdoor: true`
  → Skybox/Wetter sichtbar, nur Outdoor-taugliche Möbel (`tags: ["outdoor"]`)
  + Geländer fest verbaut.

### 4.2 Szenen-/Node-Design (pro Raum, kompatibel zu Improver A „Raum = Szene")

```
RoomScene (room_base.gd, Basis-Szene — jeder Raum erbt)
├── Env            (Boden-/Wand-Meshes, Wallpaper/Floor-Material via ShaderParam)
├── Portals        (Door/Stairs-Area3D → SceneRouter von Improver A)
├── FurnitureLayer (Node3D; ein FurnitureItem-Child pro Save-Item)
├── GridDebug      (nur Editor)
├── NavRegion      (NavigationRegion3D, Rebake nach Bau-Commit)
└── CameraRig      (Raum-Blick + Baumodus-Pose, von A's Kamerasystem gesteuert)

FurnitureItem.tscn (furniture_item.gd)
├── Mesh           (GLB-Instanz, zur Laufzeit vom Catalog-Cache geliefert)
├── Body           (StaticBody3D + BoxShape aus AABB — Kamera-Kollision/Raycast-Picking)
└── Hotspot        (optionale Area3D, wenn `interactions` nicht leer)

Autoloads: FurnitureCatalog (JSON-Merge + GLB-Cache), HomeState (Save-Slice `home`),
BuildController (ein globaler Baumodus, dockt an den aktiven RoomScene-Grid an),
StorageService (Lagerpunkte-Logik).
```

`GridData` lebt NICHT in der Szene, sondern in `HomeState` (pro Raum lazy aus Save +
Katalog rekonstruiert) — Multiplayer (§C, Bauen beim Besuch) synct nur Save-Item-Deltas.

---

## 5. Werkstatt, Crafting & Goobay

### 5.1 Werkstatt & Materialien

- **Werkstatt** = kaufbares Garten-Outbuilding (3×2 GardenGrid-Zellen, 2500 Münzen,
  Bau-Animation wie Kap. 4). Tap → Innen-Miniszene (eigene kleine RoomScene, 6×4 Grid,
  Werkbank fest verbaut, Rest dekorierbar).
- **Materialien** (eigenes Material-Inventar, unbegrenzt, im Crafting-UI sichtbar):

```json
{ "schema": "gooby.materials/1", "materials": [
  { "id": "stock",  "name_de": "Stock",  "source": "garten-spawn" },
  { "id": "holz",   "name_de": "Holz",   "source": "baum-ernte" },
  { "id": "eisen",  "name_de": "Eisen",  "source": "baumarkt", "price": 40 },
  { "id": "naegel", "name_de": "Nägel",  "source": "baumarkt", "price": 15 }
]}
```

- **Stöcke:** spawnen täglich auf 2–4 zufälligen freien Garten-Zellen (kleines
  Stock-Mesh, Tap = aufsammeln, Gooby-Bück-Animation). **Holz:** Baum pflanzen
  (Setzling im Baumarkt) → wächst 2 Tage (nature-kit Baum-Stages) → „Ernten" gibt
  3 Holz, Baum wird zum Stumpf (`stump_round`) und wächst nach (kein Fällen-Gewaltakt,
  bleibt knuffig). **Eisen/Nägel:** im Baumarkt kaufen (Baumarkt-Ort = Improver E;
  wir liefern die Datenverträge).

### 5.2 Rezepte/Baupläne als Daten

```json
{ "schema": "gooby.recipes/1", "recipes": [
  { "id": "r_zaun_holz", "output": { "item": "fence_wood", "count": 4 },
    "materials": { "stock": 2, "holz": 1, "naegel": 4 },
    "station": "werkbank", "blueprint": null, "craftSec": 3 },
  { "id": "r_gartentisch", "output": { "item": "table_rustic", "count": 1 },
    "materials": { "holz": 4, "naegel": 8, "eisen": 1 },
    "station": "werkbank", "blueprint": "bp_gartentisch", "craftSec": 5 }
]}
```

Baupläne (`blueprint`) kauft man im Baumarkt; ohne Bauplan wird das Rezept als
Silhouette mit „🔒 Bauplan im Baumarkt!" gelistet (macht Lust + erklärt den Ort).

### 5.3 Crafting-UI

Werkbank-Tap → Vollbild-Panel: links scrollende Rezeptliste (Icon, Name; grau wenn
Material fehlt, Silhouette wenn Bauplan fehlt), rechts Detail: 3D-Vorschau (drehbar,
SubViewport), Material-Checkliste „Stock 2/2 ✓ · Holz 0/1 ✗ (im Garten finden!)" mit
Herkunfts-Hinweis pro fehlendem Material, großer „BAUEN!"-Button → Hammer-Qualm-Puff
auf der Werkbank, Item ins Lager, Gooby-Jubel. Craften kostet keine Energie (wie Bauen).

### 5.4 Goobay — Verhandlungs-Minispiel

Verkauf über Baumodus-🏷️ oder Goobay-App (IGohbie). **Verhandlungslogik:**

- Verdeckter Marktwert `V = sellBase × zustand(1.0) × tagesNachfrage(0.8–1.3, täglich
  pro Kategorie gewürfelt — „heute sind Teppiche gefragt!" als Goobay-Banner).
- Käufer-NPC (zufälliger Gooby mit Name/Avatar) hat verdeckt: Budget
  `B = V × rand(0.95–1.35)` und Geduld `P ∈ {2,3,4}` Runden.
- Eröffnungsangebot `O₀ = V × rand(0.55–0.75)` als Text-Bubble („Ich geb dir 140! 🙂").
- Spieler-Bubbles pro Runde: **„Höher! ☝️"** (Gegenangebot `+18–25 %` automatisch),
  **„Deal! 🤝"** (annehmen), **„Lass gut sein ✕"** (abbrechen, Item bleibt).
- Nach jedem „Höher!": liegt das neue Angebot ≤ B → Käufer erhöht, aber sein
  **Stimmungs-Emoji** verschlechtert sich sichtbar (😊→🙂→😐→😒→😠) — DAS ist das
  lesbare Spiel-Signal. Überschreitet die Forderung B ODER ist P aufgebraucht → 50/50:
  letztes Angebot „ALLERletztes Angebot!!" oder Abbruch („Dann eben nicht! 😤" —
  Item erst morgen wieder listbar, Nachfrage-Malus −10 %).
- Skill-Ausdruck: Emoji + Käufertyp lesen (Vielredner-Bubbles = mehr Geduld; knappe
  Bubbles = wenig). Erwartungswert bei gutem Spiel ~1.1×V, gierig ~0.8×V (Abbrüche).
- Abschluss-Wahl: **Abholung** (Käufer-Gooby klingelt in 1–3 min real, Übergabe an der
  Tür, sofort Münzen) oder **zur Post bringen** (+10 % „Versandbonus", Item wird beim
  nächsten Post-Besuch gutgeschrieben — füttert den Post-Ort aus §C/E).
- Pflichtmöbel (Kap. 2.4) tauchen in Goobay gar nicht erst auf.

---

## 6. Garten 2.0

### 6.1 GardenGrid

Eigenes Grid, **Zellgröße 1 m** (gröber als innen — Außenmaßstab). Start 8×6, Erweiterung
kaufbar in Stufen (10×8 → 12×10 → 16×12; Zaun-Ring versetzt sich sichtbar nach außen,
kleine Bau-Animation). Zell-Inhalte: `empty | plot | path | decor | tree | shed |
werkstatt | greenhouse | garage | sign | stickSpawn`. Zäune sind **Kanten-Elemente**
(zwischen Zellen / am Rand), nicht Zellen-Füller:

```json
"garden": {
  "v": 1, "size": [10, 8],
  "cells": [ { "at": [2, 3], "kind": "plot", "crop": "carrot", "stage": 2,
               "wateredUntil": 1753500000 } ],
  "edges": [ { "from": [0, 0], "dir": "E", "len": 4, "fence": "fence_wood" } ],
  "structures": [
    { "kind": "shed", "at": [8, 0], "level": 2 },
    { "kind": "greenhouse", "at": [4, 5], "rot": 0, "door": [1, 0] }
  ],
  "sprinklers": [ { "at": [3, 3] } ],
  "marketStandUnlocked": true
}
```

### 6.2 Wachstums-Simulation (einfach & lesbar!)

`wachstumsRate = basis × wasser × wind × schatten × gewächshaus`

- **Wasser:** gegossen (Hand: `survival-kit/bucket`-Gieß-Animation pro Plot) = 1.0 für
  X Stunden; Regen (Wetter-System) gießt alles draußen; **Bewässerungsanlage** (Baumarkt,
  1200): Sprinkler-Item, deckt 3×3 ab, gießt täglich automatisch (rotierender
  Wasser-Partikel-Sprenkler morgens — sichtbar!). Ungegossen = 0 (Wachstum pausiert,
  wie altes System — nichts stirbt, bleibt kinderfreundlich).
- **Wind:** Randnähe = windig (äußere 2 Zellringe Faktor 0.85). Zaun/Hecke an der
  Wind-Kante schirmt 3 Zellen dahinter ab (1.0). UI: Wind-Icon am Plot-Tooltip.
- **Schatten:** Bäume/Shed/Gewächshaus werfen Schatten-Zellen (statisch berechnet,
  Süd-Sonne). Sonnen-Crops (Tomate, Melone) 0.75 im Schatten; Schatten-Crops (Salat,
  Pilz — neu!) 1.1. Plot-Tooltip zeigt ☀️/⛅-Symbol → Faktoren sind IMMER erklärbar.
- **Gewächshaus:** belegt 2×3 = **6 Zellen**, Tür-Zelle wird beim Platzieren gewählt
  (muss an begehbare Zelle grenzen). Innen: wind- und wetterfrei (Regen gießt NICHT →
  Anlage/Hand nötig), Faktor 1.25, exklusive Exoten-Crops (Ananas, Chili). Transparentes
  Dach-Mesh (Blender), Innen-Plots durchs Glas sichtbar.

### 6.3 Wochenmarkt (ECHTER Ort)

- Jeden **Samstag** (Datum-basiert; Countdown am Info-Schild). Eigene Szene: Marktplatz
  mit 4–5 Ständen (Blender-Marktstand + `city-kit-commercial/detail-awning` +
  `kaykit-restaurant`-Kisten `crate_carrots/tomatoes/buns/cheese`, `pretty-park`
  fountain/lantern/bird), NPC-Goobys schlendern (Improver-F-Animationen), Händler
  winken, Hintergrund-Gemurmel.
- Eigener Stand: Ernte aus dem Inventar auflegen (bis 8 Slots, 3D auf dem Tisch!),
  Preis pro Sorte per −/+ innerhalb Band (0.8–2.0× Basispreis). Kunden-Goobys treten
  an den Stand, prüfen (Sprechblase 🤔), kaufen oder gehen (zu teuer = seltener Kauf —
  einfache Preiselastizität). Session ~3 min oder „Stand schließen"-Button (Rest wird
  zum 1.2×-Basispreis aufgekauft — kein Frust). Profit-Ziel: Markt ≈ 1.5–2× Kompost-Preis.
- **Erste-Male:** Beim ersten Gartenöffnen Info-Karte („Samstags ist Wochenmarkt!") +
  dauerhaftes **Info-Schild** (Blender, Holz) fest am Gartenrand: Tap → Markt-Erklärung,
  Countdown, aktuelle Nachfrage-Vorschau.

---

## 7. Garage & Autos

- **Auto ab Start:** `car-kit/sedan.glb`, parkt auf `driveway-short` in der
  Vorgarten-Szene. Garage kaufbar (3000, 2×3 GardenGrid am Einfahrtsrand,
  Bau-Animation + Sounds wie Kap. 4) — Rolltor (Blender, animiert), Tap = Tor auf,
  Auto-Detail-Ansicht (drehbar) + Anpassungs-Terminal.
- **Autohaus** (Ort, Improver E baut die Szene; wir liefern Daten): Showroom, Autos auf
  Drehteller. `cars.json` (Content-Pack): `{ id, glb, price, stats: { speed, accel,
  handling } (1–10), colors: ["#…"] }`. Farbe = Material-Override des Karosserie-Slots;
  car-kit nutzt eine Shared-Palette-Textur → **Blender-Skript trennt das
  Karosserie-Material ab** (einmalig pro Auto, damit Tint nur den Lack trifft).
- Stats füttern die Fahr-Minispiele (Improver G): schnellere Autos = echte Upgrades.
- Save: `"cars": { "owned": [{ "id": "sedan", "color": "#E84040" }], "active": "sedan",
  "garageLevel": 1 }`.

---

## 8. Migration (Alt-Save → Grid)

Alt: Slot-basiert (`furniture.placed = {'living:sofa': 'loungeDesignSofa'}`). Vorgehen:

1. **Mapping-Tabelle als Daten** `res://content/base/migration/slots_v1.json`:
   `{ "living:sofa": { "at": [6, 4], "rot": 2 }, "living:tv": { "at": [6, 1], "rot": 0 },
   … }` — für alle ~30 Slot-Keys der 5 Alt-Räume ein handgesetztes Default-Layout, das
   dem alten Raumbild ähnelt (Wiedererkennung!).
2. `furniture.owned`-Einträge, die nicht platziert sind → **Lager**. Alte Gratis-Defaults
   (price 0, default) gelten weiter als besessen.
3. `proc:*`-Items (alte prozedurale Deko: Canvases, Gnome, miniGooby …) → 1:1-Ersatz-GLBs
   im Basis-Pack (Blender baut sie nach, Kap. 9) — Mapping `proc:artSunset → art_sunset`.
   Set-Belohnungen (`reward: true`) behalten ihr Nicht-kaufbar-Flag.
4. `decor.wallpaper/floor` → gleiche IDs (Painter werden Godot-Shader, IDs stabil).
5. Alter Garten: `plotsOwned/plots[6]` → 6 Plots als 2×3-Block bei `[2,2]` im neuen
   8×6-GardenGrid, Crop/Stage/Watering-Zustand übernommen.
6. Migration läuft einmalig beim ersten Start (Save-Versions-Gate), schreibt
   `home.v = 1` + Backup des Alt-Saves; danach Willkommens-Karte „Dein Haus ist
   umgezogen — alles Übrige liegt im Lager!".

---

## 9. Asset-Bedarf

### Vorhanden (Packs — direkt nutzbar)

- **Möbel-Basiskatalog (~85 Items):** komplettes `kenney/furniture-kit` (68 GLBs: Betten,
  Sofas, Küche, Bad, Lampen inkl. `lampWall`/`lampSquareCeiling`/`ceilingFan`, Teppiche,
  TV, Regale, `washer`, `toilet` …), `kaykit-furniture` (armchair, book_set,
  lamp_standing, **pictureframe_medium/standing** = Wandbilder!), `aline-furniture`
  (bookshelf, cactus, plant, rug), tinytreats **house-plants** (3 Topfpflanzen),
  **bubbly-bathroom** (ducky, Seife, Klorollen, Handtücher — SURFACE-Deko),
  **charming-kitchen** (Kettle, Töpfe, Tassen, Dishrack — SURFACE-Deko).
- **Garten:** `nature-kit` (fence_simple/fence_gate, alle Crop-Stages, 6 Bäume, Töpfe,
  Steine, Pilz, Stumpf, Log), `city-kit-suburban` (fence-1x4/2x2/low, path-stones,
  planter, driveway-short, tree-large/small), `survival-kit/bucket` (Gießen).
- **LKW/Autos:** `car-kit` — **`delivery.glb`** (Liefer-Cutscene!), sedan, suv, van,
  race, hatchback-sports, sedan-sports, taxi, wheels, box, cone.
- **Wochenmarkt:** `kaykit-restaurant` (crate_carrots/tomatoes/buns/cheese, Körbe, jars),
  `city-kit-commercial` (detail-awning/awning-wide für Standdächer), tinytreats
  **pretty-park** (fountain, bench, street_lantern, bird, flowers), **bakery-interior**
  (cash_register, display_case, scale), **pleasant-picnic** (Körbe, radio).
- Umzugskartons: `kaykit-city/box_A/box_B`.

### Blender bauen (Kenney-Stil, prozedural per Python-Skript, prio-sortiert)

| # | Asset | Für | Prio |
|---|---|---|---|
| 1 | Fenster-Modul (2 Größen, Rahmen + Glas-Quad) | Wand-Items | M1 |
| 2 | Hammer + Clipboard + Kartonstapel-Props | Bau-Anim, Liefer-Cutscene | M1 |
| 3 | Shed Level 1/2/3 (3 Modelle) | Lager | M1 |
| 4 | `proc:*`-Nachbauten: 5 Wandbilder-Canvases, Gnome (+Gold), Birdbath, miniGooby-Plüschi, Bänke, Goldene Gießkanne, Toy-City, Candy-Jar, Goldfischglas | Migration | M1 |
| 5 | Werkbank + Werkstatt-Hütte | Crafting | M2 |
| 6 | Gewächshaus (2×3, transparentes Dach, Tür-Modul) | Garten 2.0 | M2 |
| 7 | Marktstand (Tisch + Dachmodul) + Info-Schild (Holz) | Wochenmarkt | M2 |
| 8 | Bewässerungsanlage (Sprinkler) | Garten 2.0 | M2 |
| 9 | Stock (Sammel-Mesh), Eisen-Barren, Nagel-Box | Materialien | M2 |
| 10 | Treppe (rauf/runter), Balkon-Geländer | Haus-Upgrades | M3 |
| 11 | Garage (Rolltor animiert) + Karosserie-Material-Split-Skript für car-kit | Garage/Autos | M3 |
| 12 | Craft-only-Möbelserie „Rustikal" (Tisch, Stuhl, Regal, Zaun) | Werkstatt-Belohnung | M2 |

---

## 10. Prioritäten

**M1 — Grid-Bau-Kern:** `GridData` + Validierung (unit-getestet), FurnitureCatalog
(JSON-Merge + Runtime-GLB), Baumodus-UX (Boden/Wand/Decke, Drag/Rotate/Kollision, Undo),
5 Basisräume als Szenen, Lager 100 + Shed L1, Basiskatalog ~85 Pack-Items + Fenster,
Pflichtmöbel-Regeln, Erste-Male-Flow + Hammer-Anim + Liefer-Cutscene, **Migration**,
Garten-Basis (neues Grid, alte 6 Plots, Gießen per Hand).

**M2 — Wirtschafts-Loop:** Werkstatt + Materialien + Rezepte/Baupläne + Crafting-UI,
Goobay-Verhandlung, Garten 2.0 (Wind/Schatten, Erweiterungen, Zäune, Gewächshaus,
Sprinkler), Wochenmarkt-Szene, Baumarkt-Datenverträge.

**M3 — Ausbau:** Keller/2. Etage/Balkon (+ Treppen/Portale), Shed L2/3, Garage +
Autohaus + Auto-Farben/Stats, Fenster-Diorama-Autos, SURFACE-Layer-Feinschliff,
Layout-Presets („Raum speichern").

## 11. Risiken

1. **Runtime-GLB auf iOS** (Content-Packs): `GLTFDocument`-Laufzeit-Load ist ungetestet
   auf Gerät bzgl. Speicher/Ladezeit → früh Spike; Fallback: Packs nur JSON + GLBs im
   IPA-Basis-Bundle, Pack schaltet frei.
2. **Touch-Präzision** beim Drag (kleine Zellen, dicke Finger) → Ghost-Offset + Zoom
   Pflicht; früh auf echtem Gerät testen.
3. **NavMesh-Rebake pro Bau-Commit** kann auf Handys ruckeln → kleine Räume, Rebake
   async, Baumodus pausiert Gooby.
4. **Scope-Falle Garten-Sim:** Wind/Schatten strikt als 3 Multiplikatoren mit
   Tooltip-Erklärung halten — keine Fluid-/Sonnenstand-Sim.
5. **car-kit-Palette-Textur** verhindert naive Lack-Tints → Material-Split-Skript
   einplanen (sonst wirkt Farbwahl kaputt).
6. **Katalog-Updates vs. alte Saves** (Footprint-Änderung) → Ins-Lager-Fallback ist
   Pflicht-Codepfad, nicht Nice-to-have.
7. **Multiplayer-Bauen beim Besuch** (§C): uid-Deltas reichen, aber Konflikt (beide
   bauen dieselbe Zelle) braucht Last-Write-Wins + Warn-Toast (Wunsch erwähnt Warnung).

## 12. Scope (Dateien/LOC, GDScript)

| Block | Dateien | LOC |
|---|---|---|
| GridData + Validierung + Tests | 4 | 1100 |
| FurnitureCatalog + Pack-Loader + GLB-Cache | 3 | 700 |
| BuildController + Bau-UI (Drawer, Ghost, Wand/Decke) | 6 | 2200 |
| RoomScene-Basis + 8 Raum-Szenen + Portale | 10 | 1400 |
| Lager/Shed/Pflichtregeln | 3 | 500 |
| Erste-Male + Hammer-Anim + Liefer-Cutscene | 3 | 700 |
| Werkstatt/Materialien/Crafting-UI | 5 | 1300 |
| Goobay-Verhandlung | 2 | 600 |
| GardenGrid + Wachstum + Gewächshaus/Zäune/Sprinkler | 6 | 1800 |
| Wochenmarkt-Szene | 3 | 900 |
| Garage/Autos/cars.json | 3 | 600 |
| Migration | 2 | 500 |
| Daten-JSONs (Katalog/Rezepte/Räume/Migration) | ~12 | ~2500 (JSON) |
| Blender-Python-Skripte | ~10 | ~1500 (py) |
| **Summe** | **~72** | **~12 300 GD + 4 000 Daten/py** |

---

## Top-Entscheidungen (Abschluss)

1. **Zellgröße 0.5 m innen, 1 m im Garten**, Footprints in Zellen, Rotation als
   `rot ∈ {0..3}` — ein einziges, headless-testbares `GridData`-Modell für beide Welten.
2. **Fünf Layer** (RUG/FLOOR/SURFACE/WALL/CEILING); Fenster sind WALL-Items auf
   `exterior`-Wänden mit geteiltem Straßen-Diorama hinter einem Portal-Quad — kein
   Wand-CSG.
3. **Katalog, Rezepte, Räume, Autos, Migrations-Layout = alles JSON-Content-Packs** mit
   Merge-by-id und Runtime-GLB-Load; Saves referenzieren nur IDs, unbekannte Items
   fallen weich ins Lager. Das ist der Hebel für §B (Updates ohne IPA).
4. **Lager in Punkten** (100 Basis, Gewicht 1–4 pro Item), Shed 2×2 mit 3 visuellen
   Stufen; Pflichtmöbel über `mandatorySlot`-Zähler (letztes Bett/Couch/Kühlschrank
   unverkäuflich, aber immer verschiebbar).
5. **Bauen kostet nie Energie**; Hammer-Qualm-Puff bei jedem Platzieren (später
   verkürzt), Liefer-Cutscene nutzt vorhandenes `car-kit/delivery.glb` + Clipboard-Prop.
6. **Goobay-Verhandlung als Emoji-Lese-Spiel:** verdecktes Budget + Geduld, sichtbare
   Stimmungs-Eskalation, Abbruch-Risiko — 3 Buttons, ein Bildschirm.
7. **Garten-Sim bewusst flach:** Wachstum = Basis × Wasser × Wind × Schatten ×
   Gewächshaus, jeder Faktor per Tooltip erklärbar; Zäune als Kanten-Elemente.
8. **Migration über handgesetzte Slot→Zelle-Tabelle** (Wiedererkennungs-Layout),
   Rest ins Lager, `proc:*`-Deko wird als Blender-GLBs nachgebaut.
9. Reihenfolge: **M1 Grid+Räume+Lager+Migration → M2 Werkstatt/Garten 2.0/Goobay/Markt
   → M3 Etagen/Garage/Autos.** Größtes früh zu testendes Risiko: Runtime-GLB auf iOS.
