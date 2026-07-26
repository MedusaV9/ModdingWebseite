extends "res://tools/capture/clip_driver.gd"
## Clip: Baumodus (Schlafzimmer) — öffnet den echten Baumodus, zieht das
## Bett aus dem Lager auf eine GÜLTIGE freie Zelle (Ghost wandert sichtbar
## dorthin, Hammer-Gag der Erste-Male-Bauquest beim Platzieren) und stellt
## danach noch eine Pflanze auf.
##
## WICHTIG: Die Build-Kamera lerpt nach open() noch mehrere Sekunden weiter.
## Deshalb wird das Ziel-Pixel JEDEN Frame frisch unprojiziert (statt einmalig
## beim Schedulen) und der Ghost am Ende der Fahrt hart auf die Zielzelle
## gesnappt, bevor bestätigt wird.

var room: Node3D
var _ziel_zelle := Vector2i(-1, -1)
var _ziel_def: Dictionary = {}
var _glide_t0 := 0.0
var _glide_t1 := 0.0
var _glide_live := false
var _confirm_until := -1.0


func _setup() -> void:
	duration = 13.0
	var packed: PackedScene = load("res://scenes/home/schlafzimmer.tscn")
	room = packed.instantiate()
	room.stunde_override = 15.0
	add_child(room)
	schedule(0.4, func() -> void:
		if room._gooby != null:
			room._gooby.set_wander_enabled(false)
			room._gooby.walk_to(_ecke_welt()))
	schedule(1.2, func() -> void: room.open_build_mode())
	schedule(2.4, func() -> void: _neues_teil("bedSingle"))
	schedule(2.6, func() -> void: _glide_zu_freier_zelle("bedSingle", 1.8))
	schedule(4.8, func() -> void: _bestaetigen_bis(6.4))
	schedule(7.0, func() -> void: _neues_teil("plantSmall2"))
	schedule(7.2, func() -> void: _glide_zu_freier_zelle("plantSmall2", 1.4))
	schedule(9.0, func() -> void: _bestaetigen_bis(10.2))
	schedule(10.8, func() -> void: _bm().close())


func _bm() -> Node:
	return room._build_mode


## Weltposition einer Ecke vorne links — dorthin läuft Gooby, damit er der
## Platzierung nicht im Weg steht.
func _ecke_welt() -> Vector3:
	var grid: Object = room.grid
	var zelle := Vector2i(1, grid.size.y - 2)
	var lokal: Vector3 = GridData.world_center(zelle, Vector2i.ONE, 0)
	return _mount().to_global(lokal)


func _mount() -> Node3D:
	return room.grid_mount() if room.has_method("grid_mount") else room._grid_mount


func _neues_teil(item_id: String) -> void:
	var def: Dictionary = FurnitureCatalog.def(item_id)
	if def.is_empty():
		push_warning("[home_build] unbekanntes Möbel %s" % item_id)
		return
	_bm()._begin_new(def)


## Sucht eine gültige, möglichst mittige Zelle und startet die sichtbare
## Ghost-Fahrt dorthin (Unprojektion passiert live in _tick).
func _glide_zu_freier_zelle(item_id: String, dauer: float) -> void:
	var def: Dictionary = FurnitureCatalog.def(item_id)
	var grid: Object = room.grid
	var mitte := Vector2(grid.size) * 0.5
	var beste := Vector2i(-1, -1)
	var beste_d := 1e9
	for y in grid.size.y:
		for x in grid.size.x:
			var at := Vector2i(x, y)
			if not bool(grid.can_place(def, at, 0, "")["ok"]):
				continue
			var d: float = Vector2(at).distance_to(mitte)
			# Leicht außermittig bevorzugen, damit Gooby sichtbar bleibt.
			if d < beste_d and d > 1.5:
				beste_d = d
				beste = at
	if beste.x < 0:
		push_warning("[home_build] keine freie Zelle für %s" % item_id)
		return
	_ziel_zelle = beste
	_ziel_def = def
	_glide_t0 = t
	_glide_t1 = t + dauer
	_glide_live = true


## Pixelziel: Mitte der Zelle, deren cell_of()-Treffer den Ghost exakt auf
## _ziel_zelle legt (BuildMode rechnet at = cell - footprint/2).
func _ziel_px() -> Vector2:
	var fp: Vector2i = _ziel_def["footprint"]
	var treffer_zelle: Vector2i = _ziel_zelle + fp / 2
	var lokal: Vector3 = GridData.world_center(treffer_zelle, Vector2i.ONE, 0)
	var welt: Vector3 = _mount().to_global(lokal)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(-1, -1)
	return cam.unproject_position(welt)


func _bestaetigen_bis(deadline: float) -> void:
	_confirm_until = deadline


func _tick(_delta: float) -> void:
	if _glide_live and _bm() != null and not _bm()._ghost_state.is_empty():
		var ziel := _ziel_px()
		if ziel.x >= 0.0:
			var k := clampf((t - _glide_t0) / (_glide_t1 - _glide_t0), 0.0, 1.0)
			var eased := k * k * (3.0 - 2.0 * k)
			var start := ziel + Vector2(-240.0, 160.0)
			_bm()._move_ghost_to_pointer(start.lerp(ziel, eased))
			if k >= 1.0:
				# Hart snappen — Raycast-/Rundungsfehler ausschließen.
				_bm()._ghost_state["at"] = _ziel_zelle
				_bm()._rebuild_ghost()
				_glide_live = false
	if _confirm_until > 0.0 and t <= _confirm_until and not _glide_live:
		if _bm() != null and not _bm()._ghost_state.is_empty():
			_bm()._confirm_ghost()
		else:
			_confirm_until = -1.0
