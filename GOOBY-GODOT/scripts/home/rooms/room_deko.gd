class_name RoomDeko
extends RefCounted
## Statische Wand-Deko (WELT2, User: „Warum ist so vieles keine richtigen
## Assets sondern nur Primitives?"): Lichtschalter neben jeder Tür,
## Steckdosen am Wandfuß, Heizkörper unter dem Fenster und ein Bilderrahmen
## — alles selbstgebaute Blender-GLBs (assets/props/, Pipeline:
## tools/blender/props/). Hängt am Walls-Mount des Raums und macht Tür-/
## Fenster-Rebuilds dadurch automatisch mit.
##
## Rein additiv: belegt KEINE Grid-Zellen, ändert keine Möbel-Footprints
## und fasst den Katalog nicht an. Fehlt ein GLB, entfällt nur das eine
## Deko-Stück (weiche Degradation, keine Fehler).

const SCHALTER_Y := 1.08
const DOSE_Y := 0.24
const BILD_Y := 1.72
const HEIZUNG_TIEFE := 0.08
const PLATTE_TIEFE := 0.012


## Hängt alle Deko-Stücke an `mount` (den Walls-Mount). `belegte` ist
## wall → Array[[von, bis]] in Zellen (Türen + echte Außenfenster) — dort
## darf keine Deko hängen. `grid` (optional) liefert die Möbel-Belegung,
## damit der Heizkörper nicht in Möbeln vor der Wand steckt.
static func anbringen(
	mount: Node3D, room_def: Dictionary, belegte: Dictionary, grid: GridData = null
) -> void:
	var wurzel := Node3D.new()
	wurzel.name = "RaumDeko"
	mount.add_child(wurzel)
	var zellen := _grid_zellen(room_def)
	var size := Vector2(zellen.x * GridData.CELL_SIZE, zellen.y * GridData.CELL_SIZE)
	# Attrappen-Fenster blockieren ebenfalls (für Schalter/Dose/Bild).
	var blockiert := {}
	for wall: String in GridData.WALLS:
		var spans: Array = []
		spans.assign(belegte.get(wall, []))
		blockiert[wall] = spans.duplicate()
	for window: Dictionary in room_def.get("windows", []):
		var wall := str(window.get("wall", "N"))
		var von := int(window.get("offset", 0))
		(blockiert[wall] as Array).append([von, von + int(window.get("size", 2))])
	_lichtschalter(wurzel, room_def, blockiert, size)
	_steckdosen(wurzel, room_def, blockiert, size)
	_heizkoerper(wurzel, room_def, belegte, size, grid)
	_bilderrahmen(wurzel, room_def, blockiert, size)


## Ein Lichtschalter neben jeder Tür — bevorzugt rechts vom Rahmen.
static func _lichtschalter(
	wurzel: Node3D, room_def: Dictionary, blockiert: Dictionary, size: Vector2
) -> void:
	for door: Dictionary in room_def.get("doors", []):
		var wall := str(door.get("wall", "N"))
		var offset := int(door.get("offset", 0))
		var breite := _wall_breite(room_def, wall)
		var rechts := (offset + RoomDefs.DOOR_WIDTH) * GridData.CELL_SIZE + 0.33
		var links := offset * GridData.CELL_SIZE - 0.33
		var entlang := -1.0
		if rechts < breite * GridData.CELL_SIZE - 0.15 and _frei(blockiert, wall, rechts):
			entlang = rechts
		elif links > 0.15 and _frei(blockiert, wall, links):
			entlang = links
		if entlang < 0.0:
			continue
		var glb := HomeProps.prop_glb("lichtschalter")
		if glb == null:
			return
		_an_wand(glb, wall, entlang, SCHALTER_Y, PLATTE_TIEFE, size)
		wurzel.add_child(glb)


## Zwei Steckdosen an der Nordwand (erste/letzte freie Lücke).
static func _steckdosen(
	wurzel: Node3D, room_def: Dictionary, blockiert: Dictionary, size: Vector2
) -> void:
	var luecken := _freie_luecken(room_def, "N", blockiert)
	if luecken.is_empty():
		return
	var stellen: Array[float] = []
	var erste: Array = luecken[0]
	stellen.append((float(erste[0]) + 0.6) * GridData.CELL_SIZE)
	if luecken.size() > 1:
		var letzte: Array = luecken[luecken.size() - 1]
		stellen.append((float(letzte[1]) - 0.6) * GridData.CELL_SIZE)
	for entlang in stellen:
		var glb := HomeProps.prop_glb("steckdose")
		if glb == null:
			return
		_an_wand(glb, "N", entlang, DOSE_Y, PLATTE_TIEFE, size)
		wurzel.add_child(glb)


## Heizkörper mittig unter dem Attrappen-Fenster (ab 1 m Fensterbreite);
## entfällt, sobald ein echtes Außenfenster die Attrappe verdeckt oder
## Möbel direkt davor stehen (kein Clipping in Regale/Sofas).
static func _heizkoerper(
	wurzel: Node3D, room_def: Dictionary, belegte: Dictionary, size: Vector2, grid: GridData
) -> void:
	for window: Dictionary in room_def.get("windows", []):
		var zellen := int(window.get("size", 2))
		if zellen < 2:
			continue
		var wall := str(window.get("wall", "N"))
		var von := int(window.get("offset", 0))
		if _ueberlappt(belegte, wall, von, von + zellen):
			continue
		if grid != null and _moebel_vor_wand(grid, wall, von, von + zellen):
			continue
		var glb := HomeProps.prop_glb("heizkoerper")
		if glb == null:
			return
		var entlang := (von + zellen * 0.5) * GridData.CELL_SIZE
		_an_wand(glb, wall, entlang, 0.0, HEIZUNG_TIEFE, size)
		wurzel.add_child(glb)
		return


## Steht in den Bodenzellen direkt vor der Wandspanne ein Möbelstück?
static func _moebel_vor_wand(grid: GridData, wall: String, von: int, bis: int) -> bool:
	var zellen := grid.size
	for i in range(von, bis):
		var cell := Vector2i(i, 0)
		match wall:
			"S":
				cell = Vector2i(i, zellen.y - 1)
			"W":
				cell = Vector2i(0, i)
			"E":
				cell = Vector2i(zellen.x - 1, i)
		if grid.item_at(cell, GridData.Layer.FLOOR) != "":
			return true
	return false


## Ein Bilderrahmen in der größten freien Nordwand-Lücke (nur Wohn- und
## Schlafzimmer — Küche/Bad haben dort das Wandbord).
static func _bilderrahmen(
	wurzel: Node3D, room_def: Dictionary, blockiert: Dictionary, size: Vector2
) -> void:
	if str(room_def.get("id", "")) not in ["living", "bedroom"]:
		return
	var luecken := _freie_luecken(room_def, "N", blockiert)
	var beste: Array = []
	for luecke: Array in luecken:
		if beste.is_empty() or int(luecke[1]) - int(luecke[0]) > int(beste[1]) - int(beste[0]):
			beste = luecke
	# Der Rahmen ist nur 0,34 m breit — eine 2-Zellen-Lücke (1 m) reicht.
	if beste.is_empty() or int(beste[1]) - int(beste[0]) < 2:
		return
	var glb := HomeProps.prop_glb("bilderrahmen")
	if glb == null:
		return
	var entlang := (int(beste[0]) + int(beste[1])) * 0.5 * GridData.CELL_SIZE
	_an_wand(glb, "N", entlang, BILD_Y, 0.028, size)
	wurzel.add_child(glb)


## Freie Zellen-Lücken (>= 2 Zellen) einer Wand zwischen den Spannen.
static func _freie_luecken(
	room_def: Dictionary, wall: String, blockiert: Dictionary
) -> Array[Array]:
	var breite := _wall_breite(room_def, wall)
	var spans: Array = []
	spans.assign(blockiert.get(wall, []))
	spans.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var luecken: Array[Array] = []
	var cursor := 0
	for span: Array in spans:
		if int(span[0]) - cursor >= 2:
			luecken.append([cursor, int(span[0])])
		cursor = maxi(cursor, int(span[1]))
	if breite - cursor >= 2:
		luecken.append([cursor, breite])
	return luecken


## RoomDefs liefert `grid` als Vector2i, rohe rooms.json-Dicts als Array.
static func _grid_zellen(room_def: Dictionary) -> Vector2i:
	var roh: Variant = room_def.get("grid", Vector2i(8, 8))
	if roh is Vector2i:
		return roh
	return Vector2i(int(roh[0]), int(roh[1]))


static func _wall_breite(room_def: Dictionary, wall: String) -> int:
	var zellen := _grid_zellen(room_def)
	return zellen.x if wall == "N" or wall == "S" else zellen.y


## Liegt der Meter-Punkt `entlang` in einer belegten Spanne?
static func _frei(blockiert: Dictionary, wall: String, entlang: float) -> bool:
	var zelle := entlang / GridData.CELL_SIZE
	for span: Array in blockiert.get(wall, []):
		if zelle >= float(span[0]) - 0.4 and zelle <= float(span[1]) + 0.4:
			return false
	return true


static func _ueberlappt(belegte: Dictionary, wall: String, von: int, bis: int) -> bool:
	for span: Array in belegte.get(wall, []):
		if von < int(span[1]) and bis > int(span[0]):
			return true
	return false


## Positioniert `node` an der Innenseite der Wand (Front zeigt in den Raum).
static func _an_wand(
	node: Node3D, wall: String, entlang: float, y: float, tiefe: float, size: Vector2
) -> void:
	match wall:
		"N":
			node.position = Vector3(entlang, y, tiefe)
		"S":
			node.position = Vector3(entlang, y, size.y - tiefe)
			node.rotation.y = PI
		"W":
			node.position = Vector3(tiefe, y, entlang)
			node.rotation.y = PI * 0.5
		"E":
			node.position = Vector3(size.x - tiefe, y, entlang)
			node.rotation.y = -PI * 0.5
