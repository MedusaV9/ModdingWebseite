class_name BuildMode
extends Node
## Baumodus (W2a HOUSE, Doc D §2): Grid-Overlay, Ghost mit grün/rot-Feedback,
## Platzieren/Aufheben/Rotieren/Verschieben/Einlagern per Touch-Drag,
## Pflichtmöbel-Regeln (§2.4), Bett-Bauquest + Hammer-Gag (§3.1) und
## Speichern ins GameState-home-Slice. KEINE Energie-Kosten.
##
## FIX-3: freie Kamera (BuildCamera) — Trefferprüfung zuerst: ein Tap, der
## KEIN Möbel trifft, schwenkt die Kamera; zwei Finger zoomen/drehen immer.
## Der Ghost wird GEPOOLT (ein Node pro Aufnahme statt Neuaufbau pro
## Drag-Event) — das war der Ruckler beim Ziehen.
##
## W13B: Ebenen-Umschalter Boden/Wand/Decke (Doc D §2.1). Im Decken-Modus
## wandert das Grid-Overlay an die Decke, die Kamera neigt sich sanft nach
## oben (BuildCamera.set_decken_blick) und Taps picken CEILING-Items bzw.
## treiben den Girlanden-2-Tap-Spann-Flow (GirlandenBau, Doc H §6.3).
##
## Die 3D-Seite (Overlay, Möbel-Nodes, Gooby, Kamera) gehört RoomBase —
## BuildMode steuert sie über die in setup() übergebenen Referenzen.

signal opened
signal closed
signal furniture_changed

## Bau-Ebenen des Umschalters (Doc D §2.1) — BODEN deckt RUG/FLOOR/SURFACE.
enum Ebene { BODEN, WAND, DECKE }

## Layout-Konstanten leben in BuildUiDock (G4/UI-BAU) — hier re-exportiert,
## weil Tests (test_vis2_lager_ui) den Rand über BuildMode referenzieren.
const DRAWER_HEIGHT := BuildUiDock.DRAWER_HEIGHT
const DRAWER_RAND_X := BuildUiDock.DRAWER_RAND_X
const DRAWER_RAND_Y := BuildUiDock.DRAWER_RAND_Y
## Reihenfolge MUSS zum Ebene-Enum passen (Chips + Status-Anzeige).
const EBENEN_KEYS: Array[String] = ["build.ebene.boden", "build.ebene.wand", "build.ebene.decke"]
## Max. Bodenabstand (m) zur Wand, ab dem ein Tap als Wand-Item-Auswahl
## zählt (negativ = Projektion hinter der Wand, der Normalfall beim Tap
## direkt aufs hängende Item).
const WALL_PICK_RANGE := 0.6
## MUSS zu FurnitureNode.create_wall passen (Lift/Inset der Wand-Items) —
## der gepoolte Ghost setzt seine Wand-Transform selbst.
const WALL_LIFT := 1.35
const WALL_INSET := 0.06

# RoomBase (Duck-Typing statt Typ — vermeidet zyklische class_name-Referenz).
var _room: Variant
var _grid: GridData
var _overlay: GridOverlay
var _camera_rig: HomeCameraRig
var _build_camera: BuildCamera
var _gs: Object

var _active := false
## Layout/Metrik des Bau-UIs (G4/UI-BAU) — BuildMode verdrahtet nur noch
## Verhalten auf den vom Dock exponierten Knöpfen.
var _dock_ui: BuildUiDock
## Spiegel-Referenzen (Tests + Update-Methoden greifen hierüber zu).
var _ui: Control
var _drawer_items: HBoxContainer
var _capacity_label: Label
var _drawer_sig := ""
var _action_bar: HFlowContainer
var _ebene := Ebene.BODEN
var _girlanden: GirlandenBau
var _ghost: FurnitureNode
var _ghost_state: Dictionary = {}
var _ghost_sig := ""
var _ghost_gueltig := -1
var _dragging := false
var _local_uid_seq := 1

# Multi-Touch-Zustand (FIX-3): index -> letzte Screen-Position.
var _touches: Dictionary = {}
var _pan_index := -1
var _drag_index := -1
var _pinch_spanne := 0.0
var _pinch_winkel := 0.0
var _maus_gedrueckt := false


func setup(
	room: Variant, grid: GridData, overlay: GridOverlay, ui_layer: Node, camera_rig: HomeCameraRig
) -> void:
	_room = room
	_grid = grid
	_overlay = overlay
	_camera_rig = camera_rig
	_gs = room.game_state()
	_build_camera = BuildCamera.new()
	_build_camera.name = "BuildCamera"
	add_child(_build_camera)
	# Girlanden (W13B): rendern auch außerhalb des Baumodus — der Host hängt
	# seinen Mount unter den GridMount des Raums.
	_girlanden = GirlandenBau.new()
	_girlanden.name = "GirlandenBau"
	add_child(_girlanden)
	_girlanden.setup(room, grid, _gs)
	_girlanden.geaendert.connect(_refresh_drawer)
	_build_ui(ui_layer)
	set_process_unhandled_input(false)
	# Shader der Overlay-/Ghost-Materialien schon beim Raumaufbau (unter dem
	# Reveal-Veil) kompilieren — nicht erst beim ersten Baumodus-Öffnen.
	_warm_up.call_deferred()


func is_active() -> bool:
	return _active


func build_camera() -> BuildCamera:
	return _build_camera


func toggle() -> void:
	if _active:
		close()
	else:
		open()


func open() -> void:
	if _active:
		return
	_active = true
	_reset_gesten()
	_apply_metrics()
	_ui.visible = true
	_overlay.visible = true
	_camera_rig.set_build_mode(true)
	_build_camera.activate(_camera_rig, _room_world_size())
	set_ebene(Ebene.BODEN)
	set_process_unhandled_input(true)
	_refresh_drawer()
	opened.emit()
	_maybe_start_bed_quest()


func close() -> void:
	if not _active:
		return
	if _bed_quest_active():
		# Outcome schlägt Press (Audio-Grammatik): der Fertig-Druck selbst
		# bleibt stumm, die Verweigerung klingt als Fehler.
		AudioDirector.try_play(self, "ui_error")
		_room.say(I18nService.t("build.bett_quest"))
		return
	AudioDirector.try_play(self, "ui_back")
	_girlanden.abbrechen()
	_cancel_ghost()
	set_ebene(Ebene.BODEN)
	_active = false
	_reset_gesten()
	_ui.visible = false
	_overlay.visible = false
	_build_camera.deactivate()
	_camera_rig.set_build_mode(false)
	set_process_unhandled_input(false)
	closed.emit()


# ── Ebenen-Umschalter (W13B, Doc D §2.1) ─────────────────────────────────────


func ebene() -> int:
	return _ebene


## Aktive Bau-Ebene setzen: Decke hebt das Overlay auf Deckenhöhe und neigt
## die Kamera sanft nach oben; Boden/Wand holen beides zurück.
func set_ebene(ebene_neu: int) -> void:
	_ebene = ebene_neu
	_overlay.set_ebene_hoehe(GridData.DECKEN_HOEHE if _ebene == Ebene.DECKE else 0.0)
	_build_camera.set_decken_blick(_ebene == Ebene.DECKE)
	_update_ebenen_leiste()


## Passende Ebene für eine Katalog-Def (Auto-Umschalten beim Aufnehmen).
static func ebene_fuer_def(def: Dictionary) -> int:
	match int(def.get("layer", GridData.Layer.FLOOR)):
		GridData.Layer.CEILING:
			return Ebene.DECKE
		GridData.Layer.WALL:
			return Ebene.WAND
	return Ebene.BODEN


func _on_ebene_gewaehlt(ebene_neu: int) -> void:
	# Aktiver Chip ist NICHT disabled (ChipLeaf-Optik) — ein erneuter Tap
	# darf aber keinen Ghost/Spann-Flow abräumen.
	if ebene_neu == _ebene:
		return
	AudioDirector.try_play(self, "ui_chip")
	_girlanden.abbrechen()
	_overlay.clear_highlight()
	_cancel_ghost()
	set_ebene(ebene_neu)
	_update_action_bar()


# ── Eingabe (FIX-3: Greifen vs. Schwenken vs. Pinch) ─────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		_maus_taste(event as InputEventMouseButton)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_finger_runter(touch.index, touch.position)
		else:
			_finger_hoch(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_finger_zieht(drag.index, drag.position)
	elif event is InputEventMouseMotion and _maus_gedrueckt:
		_finger_zieht(0, (event as InputEventMouseMotion).position)


## Desktop-Komfort: Mausrad zoomt, Linksklick verhält sich wie ein Finger.
func _maus_taste(maus: InputEventMouseButton) -> void:
	if maus.button_index == MOUSE_BUTTON_WHEEL_UP and maus.pressed:
		_build_camera.zoom_um(BuildCamera.ZOOM_SCHRITT)
		return
	if maus.button_index == MOUSE_BUTTON_WHEEL_DOWN and maus.pressed:
		_build_camera.zoom_um(1.0 / BuildCamera.ZOOM_SCHRITT)
		return
	if maus.button_index != MOUSE_BUTTON_LEFT:
		return
	_maus_gedrueckt = maus.pressed
	if maus.pressed:
		_finger_runter(0, maus.position)
	else:
		_finger_hoch(0)


func _finger_runter(index: int, pos: Vector2) -> void:
	_touches[index] = pos
	if _touches.size() == 2:
		# Zweiter Finger: laufende Ein-Finger-Gesten sauber beenden und in
		# den Pinch (Zoom + Drehen) wechseln — der Ghost bleibt aufgenommen.
		_pan_index = -1
		_drag_index = -1
		_dragging = false
		_pinch_start()
		return
	if _touches.size() > 2:
		return
	# Trefferprüfung zuerst (User-Regel): Möbel greifen schlägt Schwenken.
	if _on_tap(pos):
		_drag_index = index
	else:
		_pan_index = index


func _finger_hoch(index: int) -> void:
	_touches.erase(index)
	if index == _pan_index:
		_pan_index = -1
	if index == _drag_index:
		_drag_index = -1
		_dragging = false
	if _touches.size() < 2:
		_pinch_spanne = 0.0
	# Vom Pinch übrig gebliebener Einzelfinger schwenkt nahtlos weiter.
	if _touches.size() == 1 and _pan_index < 0 and _drag_index < 0:
		_pan_index = _touches.keys()[0]


func _finger_zieht(index: int, pos: Vector2) -> void:
	var vorher: Vector2 = _touches.get(index, pos)
	_touches[index] = pos
	if _touches.size() >= 2 and _pinch_spanne > 0.0:
		_pinch_update()
		return
	if index == _drag_index and _dragging and not _ghost_state.is_empty():
		_move_ghost_to_pointer(pos)
	elif index == _pan_index:
		_build_camera.pan_screen(vorher, pos)


func _pinch_start() -> void:
	var punkte := _touches.values()
	if punkte.size() < 2:
		return
	_pinch_spanne = (punkte[0] as Vector2).distance_to(punkte[1])
	_pinch_winkel = ((punkte[1] as Vector2) - (punkte[0] as Vector2)).angle()


func _pinch_update() -> void:
	var punkte := _touches.values()
	if punkte.size() < 2 or _pinch_spanne <= 0.0:
		return
	var spanne := (punkte[0] as Vector2).distance_to(punkte[1])
	var winkel := ((punkte[1] as Vector2) - (punkte[0] as Vector2)).angle()
	if spanne > 1.0:
		_build_camera.zoom_um(spanne / maxf(_pinch_spanne, 1.0))
		_build_camera.rotate_um(wrapf(winkel - _pinch_winkel, -PI, PI))
	_pinch_spanne = spanne
	_pinch_winkel = winkel


func _reset_gesten() -> void:
	_touches = {}
	_pan_index = -1
	_drag_index = -1
	_pinch_spanne = 0.0
	_maus_gedrueckt = false
	_dragging = false


## Tap-Entscheidung. true = Möbel-Interaktion (Ghost bewegen/greifen),
## false = nichts getroffen → Aufrufer startet den Kameraschwenk.
func _on_tap(pos: Vector2) -> bool:
	if _ebene == Ebene.DECKE:
		return _decken_tap(pos)
	var world := _pointer_to_floor(pos)
	if world == Vector3.INF:
		return false
	if not _ghost_state.is_empty():
		_dragging = true
		_move_ghost_to_pointer(pos)
		return true
	var cell := GridData.cell_of(world)
	for layer in [GridData.Layer.SURFACE, GridData.Layer.FLOOR, GridData.Layer.RUG]:
		var uid := _grid.item_at(cell, layer)
		if uid != "":
			_begin_move(uid)
			_dragging = true
			return true
	# Kein Boden-Treffer: Wand-Items prüfen (E9 P0-1 — sie belegen keine
	# Zelle und wären sonst nie wieder auswählbar/einlagerbar).
	var wall_uid := _wall_item_at_pointer(world)
	if wall_uid != "":
		_begin_move(wall_uid)
		_dragging = true
		return true
	return false


## Tap im Decken-Modus (W13B): Girlanden-Spann-Flow > Ghost > Decken-Item
## greifen > Girlanden-Anker (Entfernen). Nichts getroffen → Kameraschwenk.
func _decken_tap(pos: Vector2) -> bool:
	var world := _pointer_to_plane(pos, GridData.DECKEN_HOEHE)
	if world == Vector3.INF:
		return false
	var cell := GridData.cell_of(world)
	if _girlanden.aktiv():
		_girlanden_tap(cell)
		return true
	if not _ghost_state.is_empty():
		_dragging = true
		_move_ghost_to_pointer(pos)
		return true
	var uid := _grid.item_at(cell, GridData.Layer.CEILING)
	if uid != "":
		_begin_move(uid)
		_dragging = true
		return true
	var status := _girlanden.entferne_an(cell)
	if status == "entfernt":
		_room.say(I18nService.t("build.girlande.entfernt"))
	elif status == "lager_voll":
		_room.say(I18nService.t("build.lager_voll"))
	return status != ""


## Ein Schritt des Girlanden-2-Tap-Flows + zugehörige Toasts/Marker.
func _girlanden_tap(cell: Vector2i) -> void:
	match _girlanden.tippe_zelle(cell):
		"punkt_a":
			_overlay.highlight([cell] as Array[Vector2i], true)
			_room.say(I18nService.t("build.girlande.punkt_b"))
		"gespannt":
			_overlay.clear_highlight()
			_room.say(I18nService.t("build.girlande.haengt"))
		"ungueltig":
			_room.say(I18nService.t("build.girlande.ungueltig"))
		"fehlgeschlagen":
			_overlay.clear_highlight()
			_room.say(I18nService.t("build.girlande.ungueltig"))
	_update_action_bar()


## Ghost aus dem Lager starten (Drawer-Tap). Girlanden (Doc H §6.3) haben
## keinen Ghost — sie starten den 2-Tap-Spann-Flow im Decken-Modus.
func _begin_new(def: Dictionary) -> void:
	_cancel_ghost()
	_girlanden.abbrechen()
	set_ebene(ebene_fuer_def(def))
	if str(def.get("kategorie", "")) == "girlanden":
		_overlay.clear_highlight()
		_girlanden.starte(str(def["id"]))
		_room.say(I18nService.t("build.girlande.punkt_a"))
		_update_action_bar()
		return
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
	set_ebene(ebene_fuer_def(def))
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
	if _ghost_state.is_empty():
		return
	var def: Dictionary = _ghost_state["def"]
	var ist_decke := int(def["layer"]) == GridData.Layer.CEILING
	var world := _pointer_to_plane(pos, GridData.DECKEN_HOEHE if ist_decke else 0.0)
	if world == Vector3.INF:
		return
	if int(def["layer"]) == GridData.Layer.WALL:
		var slot := _nearest_wall_slot(world, int(def["wall_size"]))
		_ghost_state["wall"] = slot["wall"]
		_ghost_state["offset"] = slot["offset"]
	else:
		var fp := GridData.rotated_footprint(def["footprint"], int(_ghost_state["rot"]))
		var cell := GridData.cell_of(world)
		_ghost_state["at"] = cell - fp / 2
	_rebuild_ghost()


## Ghost synchronisieren — GEPOOLT (FIX-3): der Node wird nur neu gebaut,
## wenn sich Item/Modus ändern; pro Drag-Event werden nur Transform,
## Overlay-Tönung und (bei Wechsel) die Gültigkeits-Optik angefasst.
func _rebuild_ghost() -> void:
	if _ghost_state.is_empty():
		if _ghost != null:
			_ghost.queue_free()
			_ghost = null
		_ghost_sig = ""
		_ghost_gueltig = -1
		_overlay.clear_highlight()
		_update_action_bar(false)
		return
	var def: Dictionary = _ghost_state["def"]
	var sig := "%s|%s" % [str(def.get("id", "?")), str(_ghost_state["mode"])]
	if _ghost == null or sig != _ghost_sig:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = _make_ghost_node(def)
		_ghost_sig = sig
		_ghost_gueltig = -1
		if _ghost != null:
			_room.grid_mount().add_child(_ghost)
	var check := _ghost_check()
	var ok := bool(check["ok"])
	if int(def["layer"]) == GridData.Layer.WALL:
		_apply_wall_transform(def)
		_overlay.clear_highlight()
	else:
		var at: Vector2i = _ghost_state["at"]
		var rot := int(_ghost_state["rot"])
		if _ghost != null:
			_ghost.position = GridData.world_center(at, def["footprint"], rot)
			_ghost.rotation.y = -rot * PI / 2.0
			if int(def["layer"]) == GridData.Layer.SURFACE:
				_ghost.position.y = _room.surface_height_at(at)
			elif int(def["layer"]) == GridData.Layer.CEILING:
				# Gepoolter Ghost: hängt wie das echte Item mit der
				# Oberkante an der Decke (FurnitureNode.create).
				_ghost.position.y = GridData.DECKEN_HOEHE - _ghost.top_y()
		_overlay.highlight(GridData.cells_for(at, def["footprint"], rot), ok)
	if _ghost != null and int(ok) != _ghost_gueltig:
		_ghost.set_ghost(ok)
		_ghost_gueltig = int(ok)
	_update_action_bar(ok)


func _make_ghost_node(def: Dictionary) -> FurnitureNode:
	if int(def["layer"]) == GridData.Layer.WALL:
		return FurnitureNode.create_wall(
			def, _ghost_state["wall"], int(_ghost_state["offset"]), _grid.size, "ghost"
		)
	return FurnitureNode.create(def, _ghost_state["at"], int(_ghost_state["rot"]), "ghost")


## Wand-Transform des gepoolten Ghosts (Spiegel von FurnitureNode.create_wall).
func _apply_wall_transform(def: Dictionary) -> void:
	if _ghost == null:
		return
	var wall := str(_ghost_state["wall"])
	var span := int(def["wall_size"]) * GridData.CELL_SIZE
	var along := int(_ghost_state["offset"]) * GridData.CELL_SIZE + span * 0.5
	var lift := Vector3(0.0, WALL_LIFT, 0.0)
	match wall:
		"N":
			_ghost.position = Vector3(along, 0, WALL_INSET) + lift
			_ghost.rotation.y = 0.0
		"S":
			_ghost.position = (
				Vector3(along, 0, _grid.size.y * GridData.CELL_SIZE - WALL_INSET) + lift
			)
			_ghost.rotation.y = PI
		"W":
			_ghost.position = Vector3(WALL_INSET, 0, along) + lift
			_ghost.rotation.y = -PI / 2.0
		"E":
			_ghost.position = (
				Vector3(_grid.size.x * GridData.CELL_SIZE - WALL_INSET, 0, along) + lift
			)
			_ghost.rotation.y = PI / 2.0


func _ghost_check() -> Dictionary:
	var def: Dictionary = _ghost_state["def"]
	var ignore := str(_ghost_state.get("uid", ""))
	if int(def["layer"]) == GridData.Layer.WALL:
		return _grid.can_place_wall(def, _ghost_state["wall"], int(_ghost_state["offset"]), ignore)
	return _grid.can_place(def, _ghost_state["at"], int(_ghost_state["rot"]), ignore)


func _rotate_ghost() -> void:
	if _ghost_state.is_empty():
		return
	AudioDirector.try_play(self, "ui_click")
	_ghost_state["rot"] = (int(_ghost_state["rot"]) + 1) % 4
	_rebuild_ghost()


func _confirm_ghost() -> void:
	if _ghost_state.is_empty() or not bool(_ghost_check()["ok"]):
		return
	# Der Platzieren-Knopf ist bei ungültiger Lage disabled — der Druck
	# selbst darf klingen (Audio-Grammatik).
	AudioDirector.try_play(self, "ui_confirm")
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
	_drag_index = -1
	_rebuild_ghost()


## Einlagern des aufgenommenen Items (Doc D §2.3/§2.4). Outcome schlägt
## Press: Verweigerungen (Pflichtmöbel, Lager voll) klingen als Fehler,
## erst das gelungene Einlagern klingt als Aktion.
func _store_ghost() -> void:
	if _ghost_state.get("mode", "") != "move":
		return
	var uid := str(_ghost_state["uid"])
	var def: Dictionary = _ghost_state["def"]
	if FurnitureCatalog.is_last_of_mandatory_slot(_grid.to_items_array(), uid):
		AudioDirector.try_play(self, "ui_error")
		Haptics.warn(self)
		_room.say(I18nService.t("build.pflicht." + str(def["pflicht"])))
		return
	if _gs != null and not HomeState.store_item(_gs, def["id"]):
		AudioDirector.try_play(self, "ui_error")
		Haptics.warn(self)
		_room.say(I18nService.t("build.lager_voll"))
		return
	AudioDirector.try_play(self, "ui_click")
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


func _room_world_size() -> Vector2:
	return Vector2(_grid.size.x * GridData.CELL_SIZE, _grid.size.y * GridData.CELL_SIZE)


## Shader-Warm-up (FIX-3, „laggt am Anfang"): Overlay + Ghost-Materialien
## einmal für 2 Frames sichtbar rendern, während der Reveal-Veil noch zu ist.
## Ohne das kompiliert der Treiber sie erst beim ersten Baumodus-Öffnen.
func _warm_up() -> void:
	if _room == null or not is_inside_tree():
		return
	var mount: Node3D = _room.grid_mount()
	if mount == null:
		return
	_overlay.visible = true
	_overlay.highlight([Vector2i.ZERO] as Array[Vector2i], true)
	var probe := MeshInstance3D.new()
	probe.name = "GhostWarmup"
	probe.mesh = BoxMesh.new()
	probe.scale = Vector3(0.05, 0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.95, 0.5, 0.6)
	probe.material_override = mat
	mount.add_child(probe)
	await get_tree().process_frame
	await get_tree().process_frame
	probe.queue_free()
	if not _active:
		_overlay.visible = false
		_overlay.clear_highlight()


# ── UI ───────────────────────────────────────────────────────────────────────
# G4/UI-BAU: Layout + Metrik-Pass (Safe-Area, ×f, Touch-Floor, scale_fonts)
# leben in BuildUiDock — alle Werkzeuge in EINEM unten-mittigen Dock in der
# Daumenzone. Hier wird nur noch VERHALTEN auf die Dock-Knöpfe verdrahtet.


func _build_ui(ui_layer: Node) -> void:
	_dock_ui = BuildUiDock.new()
	_dock_ui.build(ui_layer, EBENEN_KEYS)
	_ui = _dock_ui.ui
	_action_bar = _dock_ui.action_bar
	_drawer_items = _dock_ui.drawer_items
	_capacity_label = _dock_ui.capacity_label
	_verdrahte_dock()
	_update_ebenen_leiste()


## pressed-Handler + Sounds auf die vom Dock exponierten Knöpfe. Reihenfolge
## der Arrays MUSS zu BuildUiDock._build_action_bar/_build_kamera_leiste
## passen (dort zentral definiert, hier nur Verhalten).
func _verdrahte_dock() -> void:
	var actions: Array[Callable] = [_rotate_ghost, _confirm_ghost, _store_ghost, _on_abbrechen]
	for i in actions.size():
		_dock_ui.action_buttons[i].pressed.connect(actions[i])
	for i in EBENEN_KEYS.size():
		_dock_ui.ebenen_chips[i].pressed.connect(_on_ebene_gewaehlt.bind(i))
	# Ansichtswechsel klingt als Chip, die 90°-Drehung als Standard-Klick.
	var kamera: Array = [
		["ui_chip", func() -> void: _build_camera.set_draufsicht(true)],
		["ui_chip", func() -> void: _build_camera.set_draufsicht(false)],
		["ui_click", func() -> void: _build_camera.schnapp_90(-1)],
		["ui_click", func() -> void: _build_camera.schnapp_90(1)],
	]
	for i in kamera.size():
		var eintrag: Array = kamera[i]
		_dock_ui.kamera_buttons[i].pressed.connect(
			_on_kamera_knopf.bind(str(eintrag[0]), eintrag[1] as Callable)
		)
	# Presets/Goobay öffnen Overlays, die selbst ui_open spielen → Druck stumm.
	_dock_ui.presets_button.pressed.connect(_open_presets)
	_dock_ui.goobay_button.pressed.connect(_open_goobay)
	_dock_ui.done_button.pressed.connect(close)


func _apply_metrics() -> void:
	if _dock_ui != null:
		_dock_ui.apply_metrics()


func _floors_und_schrift() -> void:
	if _dock_ui != null:
		_dock_ui.floors_und_schrift()


func _update_ebenen_leiste() -> void:
	if _dock_ui == null:
		return
	_dock_ui.set_aktive_ebene(_ebene)
	_update_status()


## Persistente, dezente Modus-Anzeige: welche Ebene aktiv ist bzw. welcher
## Girlanden-Spann-Schritt gerade ansteht — immer sichtbar in der Dock-Zeile.
func _update_status() -> void:
	if _dock_ui == null:
		return
	var text: String
	if _girlanden != null and _girlanden.aktiv():
		var key := (
			"build.status.girlande_b" if _girlanden.hat_punkt_a() else "build.status.girlande_a"
		)
		text = I18nService.t(key)
	else:
		text = I18nService.t("build.status.ebene", {"ebene": I18nService.t(EBENEN_KEYS[_ebene])})
	_dock_ui.set_status(text)


## Abbrechen-Knopf: beendet auch einen laufenden Girlanden-Spann-Flow.
func _on_abbrechen() -> void:
	AudioDirector.try_play(self, "ui_back")
	_girlanden.abbrechen()
	_overlay.clear_highlight()
	_cancel_ghost()


func _on_kamera_knopf(sound_id: String, handler: Callable) -> void:
	AudioDirector.try_play(self, sound_id)
	handler.call()


func _refresh_drawer() -> void:
	var storage: Array = HomeState.storage(_gs) if _gs != null else []
	var cap := HomeState.storage_capacity(_gs) if _gs != null else 100
	# Unverändertes Lager nicht neu bauen (FIX-3: Öffnen-Ruckler) — die
	# Signatur deckt Inhalt UND Kapazität ab.
	var sig := "%s|%d" % [str(storage), cap]
	if sig == _drawer_sig:
		return
	_drawer_sig = sig
	for child in _drawer_items.get_children():
		child.queue_free()
	var used := StorageLogic.points_used(storage, FurnitureCatalog.defs())
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
		var btn := SquishButton.new()
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
		# BEWUSST kein text_overrun_behavior: mit Ellipse verloere der Chip
		# seine text-basierte Mindestbreite und kollabiert in der HBox zum
		# leeren Knopf — volle Namen sind hier ok, die Reihe scrollt (VIS-2).
		btn.pressed.connect(_on_drawer_chip.bind(def))
		_drawer_items.add_child(btn)
	# Frisch gebaute Chips brauchen Floor + skalierte Schrift (Metrik-Pass
	# lief schon — hier nur der leichte Nachzieher für neue Nodes).
	_floors_und_schrift()


## Drawer-Chip: Auswahl-Klang, dann Ghost/Spann-Flow starten. Der Umweg
## hält _begin_new stumm für programmatische Aufrufe (Bett-Quest-Autostart).
func _on_drawer_chip(def: Dictionary) -> void:
	AudioDirector.try_play(self, "ui_chip")
	_begin_new(def)


## Goobay-Handy öffnen (Verkaufsliste = Lager ohne Pflichtmöbel).
func _open_goobay() -> void:
	if _gs == null:
		return
	var panel := GoobayPanel.open_in(_room.ui_layer(), _gs, _room)
	panel.verkauft.connect(func(_item: String, _erloes: int) -> void: _refresh_drawer())
	panel.closed.connect(_refresh_drawer)


## Preset-Sheet öffnen (W13C, D §10); Ghost-/Spann-Flows enden sauber vorab.
func _open_presets() -> void:
	if _gs == null:
		return
	_girlanden.abbrechen()
	_overlay.clear_highlight()
	_cancel_ghost()
	var sheet := PresetSheet.open_in(_room.ui_layer(), _gs, str(_room.room_id))
	sheet.angewendet.connect(_on_preset_angewendet)
	sheet.closed.connect(_refresh_drawer)


func _on_preset_angewendet(fehlend: int) -> void:
	reload_grid_from_save()
	var key := "build.preset.fehlend" if fehlend > 0 else "build.preset.angewendet"
	_room.say(I18nService.t(key, {"anzahl": fehlend}))


## Grid nach einem Preset-Tausch IN PLACE aus dem Save neu füllen — Room,
## GirlandenBau und Overlay teilen sich die GridData-Referenz, deshalb wird NIE
## eine neue Instanz zugewiesen. Einträge sind frisch kollisionsgeprüft
## (LayoutPresetsLogic.apply_slot); SURFACE-Items erst nach ihren Trägern.
func reload_grid_from_save() -> void:
	if _gs == null:
		return
	for entry: Dictionary in _grid.to_items_array():
		_grid.remove_item(str(entry["uid"]))
	var raw: Variant = _gs.get_value("home.rooms.%s.items" % str(_room.room_id), [])
	var defs := FurnitureCatalog.defs()
	var surface_entries: Array = []
	for entry: Variant in raw if raw is Array else []:
		if not (entry is Dictionary) or not defs.has(str((entry as Dictionary).get("item", ""))):
			continue
		var def: Dictionary = defs[str((entry as Dictionary)["item"])]
		if int(def["layer"]) == GridData.Layer.SURFACE:
			surface_entries.append(entry)
			continue
		_platziere_save_eintrag(def, entry)
	for entry: Dictionary in surface_entries:
		_platziere_save_eintrag(defs[str(entry["item"])], entry)
	_girlanden.refresh()
	furniture_changed.emit()
	_refresh_drawer()


## Ein Save-Entry (Boden/Decke ODER Wand) ins lebende Grid setzen.
func _platziere_save_eintrag(def: Dictionary, entry: Dictionary) -> void:
	var uid := str(entry.get("uid", ""))
	var at_raw: Array = entry.get("at", [0, 0])
	if entry.has("wall"):
		_grid.place_wall(def, str(entry["wall"]), int(at_raw[0]), uid)
		return
	_grid.place(def, Vector2i(int(at_raw[0]), int(at_raw[1])), int(entry.get("rot", 0)), uid)


func _update_action_bar(ok := false) -> void:
	var has_ghost := not _ghost_state.is_empty()
	var girlande := _girlanden != null and _girlanden.aktiv()
	_action_bar.visible = has_ghost or girlande
	# Modus-Anzeige folgt jedem Flow-Wechsel (Girlande gestartet/gespannt/
	# abgebrochen) — der Hook sitzt hier, weil ALLE Übergänge hier landen.
	_update_status()
	if not _action_bar.visible:
		return
	# Girlanden-Spann-Flow (W13B): kein Ghost — nur Abbrechen ist sinnvoll.
	(_action_bar.get_child(0) as Button).visible = has_ghost
	(_action_bar.get_child(1) as Button).visible = has_ghost
	(_action_bar.get_child(1) as Button).disabled = not ok
	(_action_bar.get_child(2) as Button).visible = (
		has_ghost and _ghost_state.get("mode", "") == "move"
	)


# ── Picking-Helfer ───────────────────────────────────────────────────────────


func _pointer_to_floor(screen_pos: Vector2) -> Vector3:
	return _pointer_to_plane(screen_pos, 0.0)


## Schnittpunkt des Taps mit einer horizontalen Ebene auf `hoehe` — 0 =
## Boden, GridData.DECKEN_HOEHE = Decken-Picking (W13B). INF = kein Schnitt.
func _pointer_to_plane(screen_pos: Vector2, hoehe: float) -> Vector3:
	var camera := _camera_rig.camera
	if camera == null:
		return Vector3.INF
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var t := (hoehe - origin.y) / dir.y
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
