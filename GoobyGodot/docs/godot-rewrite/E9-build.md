# E9 — Baumodus-Edgecases (GOOBY-Godot-Mega-Eval)

**Agent:** EVAL-AGENT E9 · **Blickwinkel:** Haus-Grid / Baumodus-Edgecases
**Repo:** `/workspace` · **Branch:** `cursor/gooby-godot-rewrite-d1d8` · **Engine:** Godot 4.4.1.stable
**Repo unverändert** — alle Treiber liegen in `/tmp/e9/`, alle Artefakte in `/tmp/gooby-godot/eval/`.

---

## Verdict

Das **Datenmodell ist solide**: `GridData` lehnt jeden konstruierten Kollisions-Edgecase mit
dem korrekten stabilen `reason` ab (82/82 Checks), der Save-Roundtrip ist byte-identisch, das
weiche Degradieren bei entfernten Packs verliert keine Daten, und die Blockade-Erkennung
(„BODEN IST LAVA“ / Spidergooby) triggert end-to-end.

Die Probleme sitzen **eine Schicht darüber**, in der Verdrahtung von `BuildMode`,
`FurnitureNode` und der Save-Reihenfolge:

* **1 × P0** — einmal platzierte **Wandmöbel sind für immer unentfernbar** (kein Picking-Pfad).
* **2 × P1** — Möbel auf Tischen **wandern beim Raumwechsel unbemerkt ins Lager**;
  der Auto-Fit hat **keine Höhenbegrenzung** (1×1-Stehlampe wird 3,37 m hoch, Wand ist 2,5 m).
* 6 × P2, 12 × P3.

**Undo: nicht vorhanden** (P2, wie im Auftrag vorgesehen) — verschärft P0-1 zur Sackgasse.

---

## Methode

| Treiber | Zweck | Ergebnis |
|---|---|---|
| `/tmp/e9/drv1_collision.gd` | Kollisions-Edgecases pur (Rotation, Grenzen, Türzonen, WALL/FLOOR, 2×2-Ecken, uid, rot-Normalisierung) | 82 Checks |
| `/tmp/e9/drv2_storage.gd` | Lager 100/Überfüllung, letztes Pflichtmöbel, Brettspieltisch — über die **echte** `BuildMode`/`RoomBase`-Kette | 50 Checks |
| `/tmp/e9/drv3_catalog.gd` | Katalog-Drift: 65 GLB-Pfade, Footprint vs. `_merged_aabb`, Konsistenz | 65 Items |
| `/tmp/e9/gltf_bounds.py` | unabhängige glTF-JSON-Gegenprobe (POSITION-Accessor min/max + Node-Transforms), Stichprobe 10 | deckt sich exakt mit Godot |
| `/tmp/e9/drv4_save.gd` | Save-Roundtrip, Reihenfolge-Abhängigkeit, unbekannte Item-Ids, Katalog-Drift-Kollisionen | 38 Checks |
| `/tmp/e9/drv5_shots.gd` / `drv6_autofit_shot.gd` / `drv8_blockade.gd` | xvfb-Renderings (Overlay beide Orientierungen, Auto-Fit-Beleg, Blockade-Gag) | 13 PNGs |
| `/tmp/e9/drv7_pick_undo.gd`, `drv9_gooby_zubauen.gd` | Picking-Pfade, Undo-Inventur, uid-Kollaps, Bauen auf Gooby | 17 + 5 Checks |

Aufruf:
```bash
godot --headless --path GOOBY-GODOT --script /tmp/e9/drv1_collision.gd
xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
  --rendering-driver opengl3 --script /tmp/e9/drv5_shots.gd
python3 /tmp/e9/gltf_bounds.py
```

---

# P0

## P0-1 · Wandmöbel sind nach dem Platzieren dauerhaft unentfernbar

**Dateien:** `GOOBY-GODOT/scripts/home/build_mode/build_mode.gd:111-126` (insb. **:120**),
`GOOBY-GODOT/scripts/home/grid_data.gd:182-190`

Es gibt genau **einen** Einstieg, um ein bestehendes Möbel anzufassen: `_on_tap()` →
`_begin_move()` (`build_mode.gd:123` ist der **einzige** Aufrufer von `_begin_move`).
`_on_tap` durchsucht ausschließlich die Boden-Layer:

```gdscript
# build_mode.gd:119-125
var cell := GridData.cell_of(world)
for layer in [GridData.Layer.SURFACE, GridData.Layer.FLOOR, GridData.Layer.RUG]:
	var uid := _grid.item_at(cell, layer)
	if uid != "":
		_begin_move(uid)
```

Wand-Items belegen aber **keine** Zelle — sie leben in `_wall_slots` (`grid_data.gd:45`,
`_write_cells` steigt bei `item.has("wall")` sofort aus, `grid_data.gd:317-320`). Und
`item_at()` hat gar keinen `WALL`-Zweig:

```gdscript
# grid_data.gd:182-190 — match kennt RUG/FLOOR/SURFACE, WALL fällt auf return "" durch
func item_at(cell: Vector2i, layer: int) -> String:
	match layer:
		Layer.RUG: ...
		Layer.FLOOR: ...
		Layer.SURFACE: ...
	return ""
```

Es gibt auch keinen Physik-Raycast: `_pointer_to_floor()` (`build_mode.gd:432-443`) projiziert
den Tap immer auf die Ebene `y = 0`.

**Folge:** Badspiegel und Wandlampe können nie verschoben, nie eingelagert und nie ersetzt
werden. Der Slot ist für immer belegt, der `lagerwert` nie zurückholbar. Das Bad startet per
Default mit einem Spiegel (`scripts/home/data/default_layouts.json:49`) — **jeder** Spieler
ist betroffen. In Kombination mit dem fehlenden Undo (P2-1) ist ein Fehl-Tap irreversibel.

**Repro** (`/tmp/e9/drv7_pick_undo.gd`, Abschnitt a — bestätigt):
```gdscript
var cam := room._camera_rig.camera
var spiegel := <FurnitureNode mit uid des bathroomMirror>
build._on_tap(cam.unproject_position(spiegel.global_position))
assert(build._ghost_state.is_empty())      # nichts ausgewählt
# Gegenprobe mit einem FLOOR-Möbel (bathtub) → _ghost_state ist gefüllt
```
```
[OK ] !! der Spiegel belegt KEINE Boden-Zelle -> _on_tap kann ihn nie finden
[OK ] !! Tap direkt auf den Spiegel waehlt NICHTS aus -> Wandmoebel sind unentfernbar
[OK ] Gegenprobe: Bodenmoebel (bathtub) laesst sich antippen
```

**Fix-Richtung:** in `_on_tap` nach dem Boden-Layer zusätzlich den nächsten Wand-Slot prüfen
(`_nearest_wall_slot()` existiert bereits, `build_mode.gd:446`) bzw. `item_at` um einen
`Layer.WALL`-Zweig mit `wall`+`offset`-Signatur erweitern.

---

# P1

## P1-1 · Möbel auf Tischen wandern beim Raumwechsel unbemerkt ins Lager

**Dateien:** `grid_data.gd:251-266` (`to_items_array` sortiert nach **uid**),
`grid_data.gd:272-292` (`from_save` verarbeitet in **Array-Reihenfolge**),
`grid_data.gd:101-102` (`REASON_NEEDS_SURFACE`), `grid_data.gd:153-159` (`remove_item` ohne Kaskade)

`to_items_array()` sortiert deterministisch nach uid — das ist **nicht** die
Abhängigkeitsreihenfolge. `from_save()` platziert stur von vorn nach hinten; ein SURFACE-Item,
dessen uid kleiner ist als die seines Trägers, scheitert an `needs_surface` und landet als
Leftover im Lager (`home_state.gd:118-138`).

Beim Erstbezug geht es gut, weil `ensure_initialized` die Layout-Reihenfolge stempelt
(Träger zuerst). **Eine ganz normale Spieler-Aktion kippt das:** Träger einlagern und wieder
aufstellen → der neue Träger bekommt eine höhere uid als das Objekt, das darauf steht.

Verschärfend: `remove_item()` räumt Aufbauten **nicht** mit ab — die Lampe bleibt zunächst
kontaktlos stehen (danach auf `surface_height_at` = 0.4 m schwebend, `room_base.gd:109-113`).

**Repro** (`/tmp/e9/drv4_save.gd`, Abschnitt d — über die echte `BuildMode`-Kette bestätigt):
```gdscript
# Schlafzimmer-Startlayout: sideTable i-000013 mit lampRoundTable i-000014 darauf
build._begin_move("i-000013"); build._store_ghost()          # Beistelltisch einlagern
build._begin_new(FurnitureCatalog.def("sideTable"))
build._ghost_state["at"] = Vector2i(0, 0); build._rebuild_ghost(); build._confirm_ghost()
# neuer Tisch = i-000060  >  Lampe i-000014
build.close(); room.queue_free()                              # Raum verlassen
# Raum neu laden …
```
```
[OK ] !! Tischlampe schwebt jetzt ohne Traeger weiter im Raum
---- neue Tisch-uid = i-000060
---- Lampe nach Reload im Raum? = false
---- lampRoundTable im Lager vorher/nachher = [0, 1]
[OK ] !! REPRO BESTAETIGT: Tischlampe verschwindet beim Raumwechsel vom Tisch ins Lager
```

Minimal-Repro ohne Szene:
```gdscript
var g := GridData.new(Vector2i(8, 8))
g.place(defs["sideTable"],      Vector2i(3, 3), 0, "i-000020")
g.place(defs["lampRoundTable"], Vector2i(3, 3), 0, "i-000010")
var arr := g.to_items_array()                 # [lampRoundTable, sideTable] — uid-sortiert!
GridData.from_save(arr, defs, Vector2i(8, 8), [], {})["leftovers"].size()   # == 1
```

Kein Datenverlust (das Item liegt im Lager), aber die Einrichtung ändert sich **ohne jede
Rückmeldung** — aus Spielersicht „meine Lampe ist weg“.

**Fix-Richtung:** in `from_save` zweistufig platzieren (erst alle Nicht-SURFACE, dann SURFACE)
— das ist exakt das Muster, das `RoomBase.rebuild_furniture()` beim Rendern schon anwendet
(`room_base.gd:121-131`). Zusätzlich `remove_item` die Aufbauten mitnehmen lassen.

## P1-2 · Auto-Fit hat keine Höhenbegrenzung — Möbel ragen durch Wand und Decke

**Dateien:** `scripts/home/furniture_node.gd:97-111`, Referenz `room_base.gd:15` (`WALL_HEIGHT := 2.5`)

```gdscript
# furniture_node.gd:103-106
var target_w := fp.x * GridData.CELL_SIZE * fill
var target_d := fp.y * GridData.CELL_SIZE * fill
var s := minf(target_w / aabb.size.x, target_d / aabb.size.z)   # ← nur XZ, Y ist frei
_model.scale = Vector3.ONE * s
```

Der Skalierungsfaktor wird ausschließlich aus der Grundfläche bestimmt. Assets mit kleinem
Fuß und großer Höhe werden dadurch massiv hochskaliert. Beide Messungen (Godot `_merged_aabb`
und unabhängiger Python-glTF-Parse) stimmen auf 2 Nachkommastellen überein:

| Item | fp | glTF-Bounds B×T×H (m) | fit-scale | reale Höhe | Verdikt |
|---|---|---|---|---|---|
| `lampSquareFloor` | 1×1 | 0.12 × 0.12 × 0.86 | ×3.92 | **3.37 m** | höher als die 2,5-m-Wand |
| `lampRoundFloor` | 1×1 | 0.15 × 0.18 × 0.86 | ×2.68 | 2.30 m | Stehlampe fast raumhoch |
| `speaker` | 1×1 | 0.15 × 0.15 × 0.64 | ×3.18 | 2.02 m | 2-m-Monolith |
| `treeDefault` | 2×2 | 0.76 × 0.65 × 1.70 | ×1.25 | 2.13 m | |
| `kitchenFridge` | 2×2 | 0.43 × 0.29 × 0.92 | ×2.19 | 2.01 m | |
| `plantSmall1/2` | 1×1 | 0.09 × 0.09 × 0.14 | ×4.97 | 0.70 m | „Pflänzchen“ auf dem Tisch |
| `books` | 1×1 | 0.15 × 0.09 × … | ×3.12 | — | Bücherstapel ×3 |

Beleg: `/tmp/gooby-godot/eval/E9-shots/autofit_stehlampe_3m_in_2m5_raum.png` — die
`lampSquareFloor` steht deutlich über der Wandoberkante, `speaker` reicht fast bis oben.

Zusätzlich sitzen Wand-Items fix auf `y = 1.35` (`furniture_node.gd:41`) ohne jede
Kollisionsprüfung gegen Bodenmöbel — 12 Katalog-Items sind nach dem Fit höher als 1,2 m und
durchdringen damit potenziell Spiegel/Wandlampen (s. `drv3`-Ausgabe „Höhe nach Auto-Fit“).

**Fix-Richtung:** `s` zusätzlich gegen `max_height / aabb.size.y` klemmen (z. B. 0.9 ×
`WALL_HEIGHT`), oder pro Item ein optionales `height`-Feld im Katalog.

---

# P2

## P2-1 · Kein Undo im Baumodus
**Datei:** `scripts/home/build_mode/build_mode.gd` (gesamt)
Volltextsuche über das Repo nach `undo`/`redo`/`history`/`rueckgaengig`: **0 Treffer**.
Die Aktionsleiste bietet nur `Drehen · Platzieren · Einlagern · Abbrechen`
(`build_mode.gd:343-346`); `_cancel_ghost()` bricht ausschließlich die *laufende* Interaktion ab.
Vor `_commit()` (`build_mode.gd:283-287`) wird kein Zustand gesichert. Ein Fehl-Tap ist nur
manuell reparierbar — und bei Wandmöbeln (P0-1) gar nicht.

## P2-2 · uid-lose Save-Einträge kollabieren spurlos (Besuchs-Pfad)
**Dateien:** `grid_data.gd:338-340`, `grid_data.gd:272-292`, `scripts/social/visit_snapshot.gd:91-101`
```gdscript
# grid_data.gd:338-340 — uid "" gilt als "frei"
func _taken(map: Dictionary, cell: Vector2i, ignore_uid: String) -> bool:
	var uid: String = map.get(cell, "")
	return uid != "" and uid != ignore_uid
```
Ein Item mit leerer uid kollidiert also mit nichts, ist über `item_at()` nicht auffindbar
(→ nicht antippbar) und überschreibt in `_items[""]` jeden Vorgänger:
```gdscript
var entries := [ {"item":"chair","at":[1,1],"rot":0},
                 {"item":"chair","at":[5,5],"rot":0},
                 {"item":"table","at":[2,3],"rot":0} ]
var r := GridData.from_save(entries, defs, Vector2i(10, 8), [], {})
r["grid"].to_items_array().size()   # == 1
r["leftovers"].size()               # == 0   ← zwei Items spurlos weg
```
Lokal nicht erreichbar (`HomeState.ensure_initialized` und `room_base.gd:199-200` stempeln
immer uids). **Erreichbar ist der Remote-Pfad:** `VisitSnapshot.validate()`
(`visit_snapshot.gd:48-56`) prüft keine uids und reicht fremde Snapshots direkt an
`from_save` weiter → Besuchsräume rendern stillschweigend falsch.
Doppelte uids erzeugen analog Geisterzellen (`drv1`, Abschnitt f).

## P2-3 · Fenster werden auf dem WALL-Layer nicht freigehalten
**Datei:** `scripts/home/room_defs.gd:74-82`
```gdscript
static func wall_door_spans(room_def: Dictionary) -> Dictionary:
	for door_def: Dictionary in room_def.get("doors", []):   # ← nur doors, nie windows
```
`rooms.json` definiert pro Raum `windows` (z. B. Bad `{"wall":"N","offset":5,"size":1}`),
diese landen aber nie in `GridData.wall_blocked`. Bestätigt:
`g.can_place_wall(bathroomMirror, "N", 5)` → `{"ok": true}`. Ein Spiegel darf mitten aufs
Fenster. Türspannen dagegen werden korrekt geblockt, auch bei mehrzelligen Items.

## P2-4 · Möbel dürfen auf Goobys Standzelle gebaut werden
**Dateien:** `grid_data.gd:80-89` (`can_place` kennt Gooby nicht), `build_mode.gd:224-255`
```
Goobys Zelle: (1, 5) (begehbar: true)
can_place(chair) auf Goobys Zelle: { "ok": true, "reason": "" }
nach dem Bau: walkable((1, 5)) = false
Gooby steht IM Stuhl -> is_zone_reachable = false   # jede Tür meldet jetzt Blockade
```
Erholbar (der Blockade-Dialog öffnet den Baumodus, `room_base.gd:538-545`), aber der Gag
feuert dann aus dem falschen Grund.

## P2-5 · Leftover-Pfad umgeht die Lager-Kapazität
**Dateien:** `scripts/home/home_state.gd:118-138`, `scripts/home/storage_logic.gd:38-43`
`store_item()` prüft korrekt via `can_add` (`home_state.gd:163-171`). Der Leftover-Import ruft
dagegen `StorageLogic.add()` bzw. `storage.append()` **ohne** Prüfung — bei vollem Lager
entsteht `105/100`. Bewusst („nie Daten verlieren“), aber die Drawer-Anzeige
`Lager {used}/{cap}` (`build_mode.gd:391`) zeigt dann einen Wert über der Kapazität und der
Zustand ist ohne Verkaufs-/Wegwerf-Funktion nicht mehr abbaubar.

## P2-6 · `__unknown__`-Einträge sind totes, unsichtbares Gewicht
**Dateien:** `home_state.gd:126-136`, `build_mode.gd:397-416`
Entfernte Pack-Items werden als `{"item":"__unknown__","origId":<id>,"count":1}` gerettet.
Aber: (a) `at`/`rot` gehen verloren, (b) **kein Code liest `origId` je wieder** — es gibt
keinen Wiederherstellungspfad, wenn das Pack zurückkommt, (c) `_refresh_drawer` überspringt
Einträge mit leerer Def, die Zeile ist also unsichtbar, zählt aber je 1 Punkt gegen die
Kapazität. Gemessen: 4 unbekannte Einträge → 0 sichtbare Drawer-Zeilen.

---

# P3

| # | Befund | Datei:Zeile |
|---|---|---|
| P3-1 | **Fußmatte kann nicht vor die Tür.** `_cell_reason` blockt den RUG-Layer in Türzonen; `rugDoormat` ist genau dafür da. Ausgerechnet SURFACE ist vom `blocked`-Check ausgenommen. | `grid_data.gd:96-97` |
| P3-2 | **Rotation an Wänden ohne Auto-Nudge.** `_rotate_ghost` ändert nur `rot`, nie `at`; der Anker bleibt die Min-Ecke. Bett 2×3 auf (10,7) im 12×10-Raum: rot0 ok, rot1 → `out_of_bounds`. Der Spieler muss erst manuell verschieben. Kein Datenverlust (Bestätigen ist disabled). | `build_mode.gd:217-221` |
| P3-3 | **„Drehen“ ist bei Wandmöbeln ein No-Op**, der Button bleibt trotzdem sichtbar und aktiv. `rot` wird gesetzt, aber von `can_place_wall`/`create_wall`/`place_wall` ignoriert. | `build_mode.gd:217-221`, `:191-195` |
| P3-4 | **Teppich unter einem Möbel ist nicht antippbar** — `_on_tap` bricht beim ersten Treffer ab, FLOOR gewinnt immer gegen RUG. Zum Verschieben muss erst alles darauf geräumt werden. | `build_mode.gd:120-125` |
| P3-5 | **Pflichtmöbel-Regel gilt pro Raum, nicht global.** `is_last_of_mandatory_slot` bekommt nur `_grid.to_items_array()` des aktuellen Raums. Ein zweites Bett in einem *anderen* Raum hebt den Schutz nicht auf (überstreng, also sicher) — aber die Doku (`furniture_catalog.gd:87-88`) liest sich global. | `furniture_catalog.gd:89-98`, `build_mode.gd:271` |
| P3-6 | **Bett-Bauquest blockt `close()` in JEDEM Raum** — auch im Garten. Beim Erstbezug muss das Bett notfalls im Freien aufgestellt werden, sonst kommt man aus dem Baumodus nicht heraus. Bestätigt: Baumodus im Garten, `close()` → bleibt aktiv. | `build_mode.gd:69-74`, `:297-319` |
| P3-7 | **`brettspieltisch` ist Katalog-Drift.** Teilt sich `table.glb` mit dem Esstisch (einziges doppelt genutztes GLB), wird auf 2×2 gestaucht (scale ×1.12 statt ×1.68 → 47 % Footprint-Leerlauf), hat `surface:false` obwohl `table` `surface:true` hat, und sitzt allein in der Ein-Item-Kategorie `"wohnen"`. | `scripts/home/data/furniture_catalog.json:938-951` |
| P3-8 | **`brettspieltisch` ist im Spiel nicht erreichbar.** Weder im `default_storage` noch in einem `default_layout`; die einzigen Schreiber von `home.storage` sind `ensure_initialized` und der Leftover-Import — es gibt keinen Shop. Das Social-Gate `VisitSnapshot.has_board_table` kann damit nie durch Besitz erfüllt werden. Platzierbarkeit selbst ist ok (über den echten Baumodus verifiziert). | `visit_snapshot.gd:104-125`, `home_state.gd:163-182` |
| P3-9 | **Kein Verkaufen implementiert.** `furniture_catalog.gd:87-88` verspricht „weder eingelagert noch verkauft“, es existiert aber überhaupt kein Verkaufspfad — die Regel greift nur in `_store_ghost`. | `furniture_catalog.gd:87-98` |
| P3-10 | **`hall` in `DEFAULT_UNLOCKED`, aber kein solcher Raum** in `rooms.json` (`RoomDefs.ids()` = bathroom/bedroom/garden/kitchen/living). Harmlos (`is_room_unlocked` prüft `RoomDefs.room`), aber toter Eintrag. Umgekehrt fehlt `garden` und wird zweimal sondergehandhabt. | `home_state.gd:16`, `:100-101`, `:205` |
| P3-11 | **`can_place()` liefert für WALL-Items `out_of_bounds`.** Irreführender Grund; für die UI wäre `unknown_item` oder ein eigener `wrong_layer` sauberer. | `grid_data.gd:81-83` |
| P3-12 | **Zombie-Lagerzeile.** `StorageLogic.take` bei `count == 0` gibt `false` zurück, entfernt die Zeile aber nicht — sie bleibt für immer im Array. `normalize_slice` räumt nur Einträge ohne `item` weg. | `storage_logic.gd:47-61`, `home_state.gd:62-65` |
| P3-13 | **Baumodus-UI verdeckt die südlichen Raumreihen.** Drawer (168 px) + Dialog-Bubble überlagern in 1280×720 die unteren ~2 Zellreihen; ein roter Ghost dort ist kaum sichtbar (s. `overlay_landscape_rot1_ostwand_oob.png`). Im Hochformat schrumpft die UI zusätzlich stark. | `build_mode.gd:15`, `:357-383` |

---

## Was nachweislich funktioniert

* **Kollisions-Kern:** 82/82 Checks grün. OOB (auch negative Anker und Anker == `size`),
  Teilüberlappung mit Türzonen, `occupied`, `needs_surface`, RUG↔FLOOR-Stapeln,
  Wand-Slot-Belegung, mehrzellige Wand-Items über Türspannen. Ein fehlgeschlagenes `place()`
  schreibt **weder Zellen noch Item** (`grid_data.gd:107-116`).
* **2×2 in allen vier Ecken** aller Räume, in allen 4 Rotationen — sauber; ein 2×2, das in
  eine Türzone ragt, wird korrekt mit `blocked_zone` abgelehnt.
* **rot-Normalisierung:** `posmod` behandelt `rot = -1` (→ 3) und `rot = 7` korrekt.
* **Lager exakt 100:** `can_add` nutzt `<=`, 25 × Badewanne (à 4) ergibt exakt 100/100;
  danach passt weder ein 1- noch ein 4-Punkt-Item. `points_used` ist robust gegen negative
  `count`, fehlende Keys und Nicht-Dictionary-Müll (→ 0).
* **Letztes Bett:** über den echten UI-Pfad verifiziert — `_store_ghost` verweigert, das Bett
  bleibt im Raum, das Lager bleibt unverändert; verschieben bleibt erlaubt; nach dem
  Aufstellen eines zweiten Betts ist das Einlagern wieder möglich.
* **Blockade-Erkennung / Spidergooby:** end-to-end bestätigt (`room_base.gd:501`). Eingemauerter
  Gooby → `is_zone_reachable == false` → Beschwerde-Bubble „Ich kann nicht so gut klettern…
  manno!“ mit „Ich baue um“ / „BODEN IST LAVA“ → Spidergooby-Gag → Baumodus öffnet sich.
  Möbel mit `blocks_movement:false` sperren korrekt **nicht** ein.
* **Save-Roundtrip:** `to_items_array` → `from_save` → `to_items_array` byte-identisch,
  inklusive Belegungskarte aller drei Boden-Layer und der Wand-Slots; zweiter Roundtrip stabil.
* **Weiches Degradieren:** unbekannte Ids, kaputte Einträge, gewachsene Footprints,
  geschrumpfter Raum und neue Türzonen landen alle in `leftovers` → Lager; ein zweiter Load
  dupliziert nichts (der Raum wird nach der Heilung neu geschrieben).
* **Katalog:** alle **65** GLB/GLTF-Pfade existieren (`ResourceLoader` **und** `FileAccess`);
  alle `default_layout`/`default_storage`-Referenzen sind auflösbar; alle Pflicht-Slots sind
  besetzt (bett 2, couch 2, kuehlschrank 1). Ungenutzt: nur `garten/fence_simple.glb`,
  `garten/fence_gate.glb`.
* **Grid-Overlay** rendert in Quer- **und** Hochformat: Raster, schraffierte Türzonen, grüne
  und rote Ghost-Tönung.

---

## Artefakte

`/tmp/gooby-godot/eval/E9-shots/`

| Datei | Zeigt |
|---|---|
| `overlay_landscape_tuerzonen.png` / `overlay_portrait_tuerzonen.png` | Raster + schraffierte Tür-Freihaltezonen, beide Orientierungen |
| `overlay_{landscape,portrait}_ghost_gruen_2x2_ecke.png` | gültiger 2×2-Ghost in der NW-Ecke |
| `overlay_{landscape,portrait}_ghost_rot_tuerzone.png` | roter Ghost in der Türzone (`blocked_zone`) |
| `overlay_{landscape,portrait}_rot0_ostwand_ok.png` | Bett 2×3 bündig an der Ostwand, rot0 gültig |
| `overlay_{landscape,portrait}_rot1_ostwand_oob.png` | dasselbe Bett nach „Drehen“ → `out_of_bounds` (P3-2) |
| `autofit_stehlampe_3m_in_2m5_raum.png` | **P1-2**: `lampSquareFloor` (3,37 m) und `speaker` (2,02 m) gegen die 2,5-m-Wand |
| `blockade_dialog_bodenistlava.png` | Blockade-Gag: „Ich baue um“ / „BODEN IST LAVA“ |
| `spidergooby_gag.png`, `blockade_danach_baumodus.png` | Spidergooby-Flow und der danach geöffnete Baumodus |

Treiber (Wegwerf, außerhalb des Repos): `/tmp/e9/drv1_collision.gd`, `drv2_storage.gd`,
`drv3_catalog.gd`, `drv4_save.gd`, `drv5_shots.gd`, `drv6_autofit_shot.gd`,
`drv7_pick_undo.gd`, `drv8_blockade.gd`, `drv9_gooby_zubauen.gd`, `gltf_bounds.py`.
