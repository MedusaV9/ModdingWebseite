class_name GirlandenBau
extends Node
## Girlanden-Teil des Baumodus (W13B, Doc H §6.3): rendert die Spann-Deko
## eines Raums (auch AUSSERHALB des Baumodus — der Mount lebt unter dem
## GridMount) und führt den 2-Tap-Spann-Flow: Girlanden-Karte antippen →
## Decken-Punkt A → Decken-Punkt B → Catenary hängt durch. Entfernen: im
## Decken-Modus einen Anker-Punkt antippen → zurück ins Lager.
##
## Daten leben im home-Slice (HomeState.girlanden/add_girlande/
## remove_girlande) — hier passiert nur Flow + Rendering. Die Tageszeit
## für die Lichterkette kommt aus room.stunde_override (Tests injizieren
## sie dort) bzw. der Systemuhr.

signal geaendert  # nach Spannen/Entfernen — BuildMode aktualisiert den Drawer

## Lichter-Refresh (Tag/Nacht-Wechsel) — grob reicht: 60 s.
const TAGESZEIT_INTERVALL_S := 60.0

var _room: Variant
var _grid: GridData
var _gs: Object
var _mount: Node3D
var _typ := ""  # aktiver Spann-Flow ("" = keiner)
var _zelle_a := Vector2i(-1, -1)
var _hat_a := false


func setup(room: Variant, grid: GridData, gs: Object) -> void:
	_room = room
	_grid = grid
	_gs = gs
	_mount = Node3D.new()
	_mount.name = "GirlandenMount"
	room.grid_mount().add_child(_mount)
	var timer := Timer.new()
	timer.wait_time = TAGESZEIT_INTERVALL_S
	timer.autostart = true
	timer.timeout.connect(_wende_tageszeit_an)
	add_child(timer)
	refresh()


## Alle Girlanden des Raums neu aus dem Slice aufbauen.
func refresh() -> void:
	if _mount == null:
		return
	for child in _mount.get_children():
		child.queue_free()
	if _gs == null:
		return
	var stunde := _stunde()
	for eintrag: Variant in HomeState.girlanden(_gs, str(_room.room_id)):
		if not (eintrag is Dictionary):
			continue
		var a := HomeState.girlande_zelle(eintrag, "zelle_a")
		var b := HomeState.girlande_zelle(eintrag, "zelle_b")
		_mount.add_child(
			Girlande.create(str(eintrag.get("typ", "")), _decken_punkt(a), _decken_punkt(b), stunde)
		)


# ── Spann-Flow ───────────────────────────────────────────────────────────────


func aktiv() -> bool:
	return _typ != ""


func hat_punkt_a() -> bool:
	return _hat_a


func punkt_a() -> Vector2i:
	return _zelle_a


func starte(typ: String) -> void:
	_typ = typ
	_hat_a = false


func abbrechen() -> void:
	_typ = ""
	_hat_a = false


## Ein Tap auf eine Decken-Zelle im Spann-Flow. Ergebnis-Strings (stabil,
## BuildMode mappt sie auf Toasts): "punkt_a" | "gespannt" | "ungueltig" |
## "fehlgeschlagen" | "" (kein Flow aktiv).
func tippe_zelle(cell: Vector2i) -> String:
	if _typ == "":
		return ""
	if not _grid.in_bounds(cell):
		return "ungueltig"
	if not _hat_a:
		_zelle_a = cell
		_hat_a = true
		return "punkt_a"
	if cell == _zelle_a:
		return "ungueltig"
	if _gs == null or not HomeState.add_girlande(_gs, str(_room.room_id), _typ, _zelle_a, cell):
		abbrechen()
		return "fehlgeschlagen"
	abbrechen()
	refresh()
	geaendert.emit()
	return "gespannt"


## Entfernen (Decken-Modus): Girlande, deren Anker auf `cell` liegt, abnehmen
## und einlagern. "entfernt" | "lager_voll" | "" (kein Anker getroffen).
func entferne_an(cell: Vector2i) -> String:
	if _gs == null:
		return ""
	var liste := HomeState.girlanden(_gs, str(_room.room_id))
	for i in liste.size():
		if not (liste[i] is Dictionary):
			continue
		var eintrag: Dictionary = liste[i]
		var trifft := (
			HomeState.girlande_zelle(eintrag, "zelle_a") == cell
			or HomeState.girlande_zelle(eintrag, "zelle_b") == cell
		)
		if not trifft:
			continue
		if not HomeState.remove_girlande(_gs, str(_room.room_id), i):
			return "lager_voll"
		refresh()
		geaendert.emit()
		return "entfernt"
	return ""


# ── intern ───────────────────────────────────────────────────────────────────


## Welt-Punkt eines Girlanden-Ankers: Zellen-Mitte auf Decken-Höhe.
func _decken_punkt(cell: Vector2i) -> Vector3:
	var punkt := GridData.world_center(cell, Vector2i.ONE, 0)
	punkt.y = GridData.DECKEN_HOEHE
	return punkt


func _wende_tageszeit_an() -> void:
	if _mount == null:
		return
	var stunde := _stunde()
	for child in _mount.get_children():
		if child is Girlande:
			(child as Girlande).wende_tageszeit_an(stunde)


## Tageszeit: injizierter Raum-Override (Tests/Screenshots) vor Systemuhr.
func _stunde() -> float:
	var override := float(_room.stunde_override)
	if override >= 0.0:
		return override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0
