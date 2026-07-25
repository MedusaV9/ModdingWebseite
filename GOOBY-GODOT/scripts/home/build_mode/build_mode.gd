class_name BuildMode
extends Node
## Baumodus (W2a HOUSE, Doc D §2): Grid-Overlay, Ghost mit grün/rot-Feedback,
## Platzieren/Aufheben/Rotieren/Verschieben/Einlagern per Touch-Drag,
## Pflichtmöbel-Regeln (§2.4), Bett-Bauquest + Hammer-Gag (§3.1) und
## Speichern ins GameState-home-Slice. KEINE Energie-Kosten.
##
## Die 3D-Seite (Overlay, Möbel-Nodes, Gooby, Kamera) gehört RoomBase —
## BuildMode steuert sie über die in setup() übergebenen Referenzen.

signal opened
signal closed
signal furniture_changed

const DRAWER_HEIGHT := 168.0
## Max. Bodenabstand (m) zur Wand, ab dem ein Tap als Wand-Item-Auswahl
## zählt (negativ = Projektion hinter der Wand, der Normalfall beim Tap
## direkt aufs hängende Item).
const WALL_PICK_RANGE := 0.6

# RoomBase (Duck-Typing statt Typ — vermeidet zyklische class_name-Referenz).
var _room: Variant
var _grid: GridData
var _overlay: GridOverlay
var _camera_rig: HomeCameraRig
var _gs: Object

var _active := false
var _ui: Control
var _drawer_items: HBoxContainer
var _capacity_label: Label
var _action_bar: HBoxContainer
var _ghost: FurnitureNode
var _ghost_state: Dictionary = {}
var _dragging := false
var _local_uid_seq := 1


func setup(
	room: Variant, grid: GridData, overlay: GridOverlay, ui_layer: Node, camera_rig: HomeCameraRig
) -> void:
	_room = room
	_grid = grid
	_overlay = overlay
	_camera_rig = camera_rig
	_gs = room.game_state()
	_build_ui(ui_layer)


func is_active() -> bool:
	return _active


func toggle() -> void:
	if _active:
		close()
	else:
		open()


func open() -> void:
	if _active:
		return
	_active = true
	_ui.visible = true
	_overlay.visible = true
	_camera_rig.set_build_mode(true)
	_refresh_drawer()
	opened.emit()
	_maybe_start_bed_quest()


func close() -> void:
	if not _active:
		return
	if _bed_quest_active():
		_room.say(I18nService.t("build.bett_quest"))
		return
	_cancel_ghost()
	_active = false
	_ui.visible = false
	_overlay.visible = false
	_camera_rig.set_build_mode(false)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var motion := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenTouch:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		pos = event.position
		motion = true
	else:
		return
	if pressed:
		_on_tap(pos)
	elif released:
		_dragging = false
	elif motion and _dragging and not _ghost_state.is_empty():
		_move_ghost_to_pointer(pos)


func _on_tap(pos: Vector2) -> void:
	var world := _pointer_to_floor(pos)
	if world == Vector3.INF:
		return
	if not _ghost_state.is_empty():
		_dragging = true
		_move_ghost_to_pointer(pos)
		return
	var cell := GridData.cell_of(world)
	for layer in [GridData.Layer.SURFACE, GridData.Layer.FLOOR, GridData.Layer.RUG]:
		var uid := _grid.item_at(cell, layer)
		if uid != "":
			_begin_move(uid)
			_dragging = true
			return
	# Kein Boden-Treffer: Wand-Items prüfen (E9 P0-1 — sie belegen keine
	# Zelle und wären sonst nie wieder auswählbar/einlagerbar).
	var wall_uid := _wall_item_at_pointer(world)
	if wall_uid != "":
		_begin_move(wall_uid)
		_dragging = true


## Ghost aus dem Lager starten (Drawer-Tap).
func _begin_new(def: Dictionary) -> void:
	_cancel_ghost()
	var center := Vector2i(_grid.size.x / 2, _grid.size.y / 2)
	var fp: Vector2i = def["footprint"]
	_ghost_state = {
		"def": def,
		"at": center - fp / 2,
		"rot": 0,
		"uid": "",
		"mode": "new",
		"wall": "N",
		"offset": 0,
	}
	_rebuild_ghost()


func _begin_move(uid: String) -> void:
	var item := _grid.get_item(uid)
	if item.is_empty():
		return
	_cancel_ghost()
	var def: Dictionary = item["def"]
	_ghost_state = {
		"def": def,
		"at": item["at"],
		"rot": item["rot"],
		"uid": uid,
		"mode": "move",
		"wall": item.get("wall", "N"),
		"offset": item["at"].x if item.has("wall") else 0,
		"original": {"at": item["at"], "rot": item["rot"], "wall": item.get("wall", "")},
	}
	_room.set_furniture_visible(uid, false)
	_rebuild_ghost()


func _move_ghost_to_pointer(pos: Vector2) -> void:
	var world := _pointer_to_floor(pos)
	if world == Vector3.INF or _ghost_state.is_empty():
		return
	var def: Dictionary = _ghost_state["def"]
	if int(def["layer"]) == GridData.Layer.WALL:
		var slot := _nearest_wall_slot(world, int(def["wall_size"]))
		_ghost_state["wall"] = slot["wall"]
		_ghost_state["offset"] = slot["offset"]
	else:
		var fp := GridData.rotated_footprint(def["footprint"], int(_ghost_state["rot"]))
		var cell := GridData.cell_of(world)
		_ghost_state["at"] = cell - fp / 2
	_rebuild_ghost()


func _rebuild_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if _ghost_state.is_empty():
		_overlay.clear_highlight()
		_update_action_bar()
		return
	var def: Dictionary = _ghost_state["def"]
	var check := _ghost_check()
	if int(def["layer"]) == GridData.Layer.WALL:
		_ghost = FurnitureNode.create_wall(
			def, _ghost_state["wall"], int(_ghost_state["offset"]), _grid.size, "ghost"
		)
		_overlay.clear_highlight()
	else:
		var at: Vector2i = _ghost_state["at"]
		var rot := int(_ghost_state["rot"])
		_ghost = FurnitureNode.create(def, at, rot, "ghost")
		if _ghost != null and int(def["layer"]) == GridData.Layer.SURFACE:
			_ghost.position.y = _room.surface_height_at(at)
		_overlay.highlight(GridData.cells_for(at, def["footprint"], rot), bool(check["ok"]))
	if _ghost != null:
		_ghost.set_ghost(bool(check["ok"]))
		_room.grid_mount().add_child(_ghost)
	_update_action_bar()


func _ghost_check() -> Dictionary:
	var def: Dictionary = _ghost_state["def"]
	var ignore := str(_ghost_state.get("uid", ""))
	if int(def["layer"]) == GridData.Layer.WALL:
		return _grid.can_place_wall(def, _ghost_state["wall"], int(_ghost_state["offset"]), ignore)
	return _grid.can_place(def, _ghost_state["at"], int(_ghost_state["rot"]), ignore)


func _rotate_ghost() -> void:
	if _ghost_state.is_empty():
		return
	_ghost_state["rot"] = (int(_ghost_state["rot"]) + 1) % 4
	_rebuild_ghost()


func _confirm_ghost() -> void:
	if _ghost_state.is_empty() or not bool(_ghost_check()["ok"]):
		return
	var def: Dictionary = _ghost_state["def"]
	var is_new: bool = _ghost_state["mode"] == "new"
	if is_new:
		if _gs != null and not HomeState.take_from_storage(_gs, def["id"]):
			_cancel_ghost()
			return
		var uid := _next_uid()
		if int(def["layer"]) == GridData.Layer.WALL:
			_grid.place_wall(def, _ghost_state["wall"], int(_ghost_state["offset"]), uid)
		else:
			_grid.place(def, _ghost_state["at"], int(_ghost_state["rot"]), uid)
	elif int(def["layer"]) == GridData.Layer.WALL:
		var uid_w := str(_ghost_state["uid"])
		_grid.remove_item(uid_w)
		_grid.place_wall(def, _ghost_state["wall"], int(_ghost_state["offset"]), uid_w)
	else:
		_grid.move_item(str(_ghost_state["uid"]), _ghost_state["at"], int(_ghost_state["rot"]))
	var gag: bool = is_new and str(def.get("pflicht", "")) == "bett" and _bed_gag_pending()
	var gag_pos := GridData.world_center(
		_ghost_state.get("at", Vector2i.ZERO), def["footprint"], int(_ghost_state["rot"])
	)
	_ghost_state = {}
	_rebuild_ghost()
	_commit()
	if gag:
		if _gs != null:
			HomeState.set_flag(_gs, HomeState.FLAG_BED_PLACED, true)
		_room.play_hammer_gag(gag_pos)


func _cancel_ghost() -> void:
	if _ghost_state.get("mode", "") == "move":
		_room.set_furniture_visible(str(_ghost_state["uid"]), true)
	_ghost_state = {}
	_dragging = false
	_rebuild_ghost()


## Einlagern des aufgenommenen Items (Doc D §2.3/§2.4).
func _store_ghost() -> void:
	if _ghost_state.get("mode", "") != "move":
		return
	var uid := str(_ghost_state["uid"])
	var def: Dictionary = _ghost_state["def"]
	if FurnitureCatalog.is_last_of_mandatory_slot(_grid.to_items_array(), uid):
		_room.say(I18nService.t("build.pflicht." + str(def["pflicht"])))
		return
	if _gs != null and not HomeState.store_item(_gs, def["id"]):
		_room.say(I18nService.t("build.lager_voll"))
		return
	_grid.remove_item(uid)
	_ghost_state = {}
	_rebuild_ghost()
	_commit()


func _commit() -> void:
	if _gs != null:
		HomeState.save_room_grid(_gs, _room.room_id, _grid)
	furniture_changed.emit()
	_refresh_drawer()


func _next_uid() -> String:
	if _gs != null:
		return HomeState.next_uid(_gs)
	_local_uid_seq += 1
	return "local-%06d" % _local_uid_seq


func _bed_quest_active() -> bool:
	if _gs == null or HomeState.flag(_gs, HomeState.FLAG_BED_PLACED):
		return false
	for entry: Variant in HomeState.storage(_gs):
		var def := FurnitureCatalog.def(str(entry.get("item", "")))
		if def.get("pflicht", "") == "bett":
			return true
	return false


func _bed_gag_pending() -> bool:
	return _gs != null and not HomeState.flag(_gs, HomeState.FLAG_BED_PLACED)


func _maybe_start_bed_quest() -> void:
	if not _bed_quest_active():
		return
	_room.say(I18nService.t("build.bett_quest"))
	for entry: Variant in HomeState.storage(_gs):
		var def := FurnitureCatalog.def(str(entry.get("item", "")))
		if def.get("pflicht", "") == "bett":
			_begin_new(def)
			return


# ── UI ───────────────────────────────────────────────────────────────────────


func _build_ui(ui_layer: Node) -> void:
	_ui = Control.new()
	_ui.name = "BuildModeUi"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.visible = false
	ui_layer.add_child(_ui)
	_build_action_bar()
	_build_drawer()


func _build_action_bar() -> void:
	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_bar.position.y -= DRAWER_HEIGHT + 56.0
	_action_bar.add_theme_constant_override("separation", 10)
	_ui.add_child(_action_bar)
	_add_action_button("build.rotieren", "GhostButton", _rotate_ghost)
	_add_action_button("build.bestaetigen", "AccentButton", _confirm_ghost)
	_add_action_button("build.einlagern", "GhostButton", _store_ghost)
	_add_action_button("build.abbrechen", "GhostButton", _cancel_ghost)


func _add_action_button(key: String, variation: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = I18nService.t(key)
	btn.theme_type_variation = variation
	btn.pressed.connect(handler)
	_action_bar.add_child(btn)


func _build_drawer() -> void:
	var drawer := PanelContainer.new()
	drawer.theme_type_variation = "AcCard"
	drawer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	drawer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	drawer.custom_minimum_size = Vector2(0, DRAWER_HEIGHT)
	_ui.add_child(drawer)
	var box := VBoxContainer.new()
	drawer.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_capacity_label = Label.new()
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_capacity_label)
	var done := Button.new()
	done.text = I18nService.t("build.fertig")
	done.theme_type_variation = "PrimaryButton"
	done.pressed.connect(close)
	header.add_child(done)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)
	_drawer_items = HBoxContainer.new()
	_drawer_items.add_theme_constant_override("separation", 8)
	scroll.add_child(_drawer_items)


func _refresh_drawer() -> void:
	for child in _drawer_items.get_children():
		child.queue_free()
	var storage: Array = HomeState.storage(_gs) if _gs != null else []
	var used := StorageLogic.points_used(storage, FurnitureCatalog.defs())
	var cap := HomeState.storage_capacity(_gs) if _gs != null else 100
	_capacity_label.text = I18nService.t("build.lager", {"used": used, "cap": cap})
	if storage.is_empty():
		var empty := Label.new()
		empty.text = I18nService.t("build.leer")
		_drawer_items.add_child(empty)
		return
	for entry: Variant in storage:
		if not (entry is Dictionary):
			continue
		var def := FurnitureCatalog.def(str(entry.get("item", "")))
		if def.is_empty():
			continue
		var btn := Button.new()
		var fp: Vector2i = def["footprint"]
		btn.text = (
			"%s ×%d (%d×%d)"
			% [
				FurnitureCatalog.display_name(def, I18nService.get_locale()),
				int(entry.get("count", 1)),
				fp.x,
				fp.y,
			]
		)
		btn.theme_type_variation = "AcChip"
		btn.pressed.connect(_begin_new.bind(def))
		_drawer_items.add_child(btn)


func _update_action_bar() -> void:
	var has_ghost := not _ghost_state.is_empty()
	_action_bar.visible = has_ghost
	if not has_ghost:
		return
	var ok := bool(_ghost_check()["ok"])
	(_action_bar.get_child(1) as Button).disabled = not ok
	(_action_bar.get_child(2) as Button).visible = _ghost_state.get("mode", "") == "move"


# ── Picking-Helfer ───────────────────────────────────────────────────────────


func _pointer_to_floor(screen_pos: Vector2) -> Vector3:
	var camera := _camera_rig.camera
	if camera == null:
		return Vector3.INF
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector3.INF
	return origin + dir * t


func _nearest_wall_slot(world: Vector3, span: int) -> Dictionary:
	var w := _grid.size.x * GridData.CELL_SIZE
	var d := _grid.size.y * GridData.CELL_SIZE
	var dists := {
		"N": world.z,
		"S": d - world.z,
		"W": world.x,
		"E": w - world.x,
	}
	var wall := "N"
	for candidate: String in dists:
		if dists[candidate] < dists[wall]:
			wall = candidate
	var along := world.x if (wall == "N" or wall == "S") else world.z
	var offset := int(floor(along / GridData.CELL_SIZE)) - span / 2
	offset = clampi(offset, 0, _grid.wall_width(wall) - span)
	return {"wall": wall, "offset": offset, "dist": dists[wall]}


## Wand-Item unterm Tap ("" = keins). Der y=0-Schnittpunkt eines Taps AUF
## ein Wand-Item (hängt auf ~1,35 m) liegt HINTER der Wandebene (dist < 0);
## Taps knapp vor der Wand zählen als Fat-Finger-Toleranz ebenfalls. Die
## Nachbar-Slots fangen den seitlichen Versatz der Bodenprojektion ab.
func _wall_item_at_pointer(world: Vector3) -> String:
	var slot := _nearest_wall_slot(world, 1)
	if float(slot["dist"]) > WALL_PICK_RANGE:
		return ""
	var wall: String = slot["wall"]
	var offset := int(slot["offset"])
	for candidate in [offset, offset - 1, offset + 1]:
		var uid := _grid.wall_item_at(wall, candidate)
		if uid != "":
			return uid
	return ""
