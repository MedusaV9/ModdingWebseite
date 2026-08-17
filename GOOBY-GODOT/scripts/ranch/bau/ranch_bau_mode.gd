class_name RanchBauMode
extends Node3D
## Ranch-Baumodus (RW-4, User-Wunsch „eigene Ranch mit Grid Design") —
## überträgt den erprobten Haus-Baumodus auf den Außenbereich:
## - 16×16-Grid (3-m-Zellen) über dem Hof, Zonen per Gold freischaltbar,
## - Platzieren/Drehen/Abreißen von Anlagen, Deko, Böden und KANTEN-Zäunen
##   mit Ghost-Vorschau + grün/roter Platzprüfung (RanchBauOverlay),
## - Ausbaustufen mit sichtbarem Nutzen (RanchBauEffekte) direkt am Item,
## - schwenkbare Kamera (Mathe aus BuildCamera: offset_fuer, pure).
## ALLE Buchungen laufen über RanchBauState (atomar, Gold statt Energie).
##
## Einbau: Node mounten (Szene scenes/ranch/dorf/ranch_bau_hof.tscn) ODER
## von RW-1 in die Hof-Szene hängen (standalone=false lässt Licht/Boden
## der Gastszene in Ruhe). Tests injizieren `game_state_override`.

signal fertig_pressed

const ROUTE_BAU := &"ranch/bau"
const SZENE_BAU := "res://scenes/ranch/dorf/ranch_bau_hof.tscn"

const INK := Color("#3B3630")
const PAPIER := Color(0.98, 0.95, 0.88, 0.94)
const GHOST_ALPHA := 0.55
const KANTE_SNAP_M := 0.9

## Eigenes Licht/Boden/Kamera bauen (false, wenn die Hof-Szene das stellt).
@export var standalone := true

var game_state_override: Object

var _balance: Dictionary = {}
var _defs: Dictionary = {}
var _grid: RanchGridData
var _kamera: Camera3D
var _pivot := Vector3(24.0, 0.0, 33.0)
var _yaw := 0.0
var _pitch := BuildCamera.PITCH_SCHRAEG
var _dist := 34.0
var _overlay: RanchBauOverlay
var _items_root: Node3D
var _ghost: Node3D
var _ghost_id := ""
var _ghost_rot := 0
var _ghost_cell := Vector2i(-99, -99)
var _ghost_kante := {}
var _abriss_modus := false
var _auswahl_uid := ""
var _drag_pan := false

var _coins_label: Label
var _feedback: Label
var _feedback_t := 0.0
var _kategorie := "anlage"
var _item_leiste: HBoxContainer
var _info_panel: PanelContainer
var _info_text: Label
var _ausbau_btn: Button
var _abriss_btn: Button
var _zonen_box: HBoxContainer


## Route anmelden + hinreisen (Muster RanchRouten).
static func registriere_route(router: Object) -> void:
	if router != null and router.has_method("register_route"):
		router.register_route(ROUTE_BAU, SZENE_BAU)


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _ready() -> void:
	_balance = RanchBauKatalog.load_balance()
	_defs = RanchBauKatalog.defs(_balance)
	RanchBauState.migriere_bestand(game_state(), _balance)
	if standalone:
		_baue_kulisse()
	_overlay = RanchBauOverlay.new()
	_overlay.name = "Overlay"
	add_child(_overlay)
	_items_root = Node3D.new()
	_items_root.name = "Items"
	add_child(_items_root)
	_rebuild_welt()
	if standalone:
		_baue_kamera()
	_baue_ui()
	_refresh_ui()


func _process(delta: float) -> void:
	if _feedback_t > 0.0:
		_feedback_t -= delta
		_feedback.modulate.a = clampf(_feedback_t / 0.4, 0.0, 1.0)
	if _kamera != null:
		var ziel := _pivot + BuildCamera.offset_fuer(_yaw, _pitch, _dist)
		var t := 1.0 - exp(-9.0 * delta)
		_kamera.global_position = _kamera.global_position.lerp(ziel, t)
		_kamera.look_at(_pivot + Vector3(0, 0.4, 0), Vector3.UP)


## ------------------------------------------------------------------ Welt


func _baue_kulisse() -> void:
	var bau := RanchBau.new(self)
	bau.baue_licht(11.0)
	var boden := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(220.0, 220.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RanchBauVisuals.WIESE_GRUEN
	mat.roughness = 1.0
	mesh.material = mat
	boden.mesh = mesh
	boden.position = Vector3(24.0, -0.02, 24.0)
	boden.name = "Boden"
	add_child(boden)


func _baue_kamera() -> void:
	_kamera = Camera3D.new()
	_kamera.name = "BauKamera"
	_kamera.current = true
	add_child(_kamera)
	_kamera.global_position = _pivot + BuildCamera.offset_fuer(_yaw, _pitch, _dist)
	_kamera.look_at(_pivot + Vector3(0, 0.4, 0), Vector3.UP)


## Grid + Item-Nodes frisch aus dem Save aufbauen (eine Wahrheit: Save).
func _rebuild_welt() -> void:
	var geladen := RanchBauState.grid_von(game_state(), _balance)
	_grid = geladen["grid"]
	_overlay.setup(_grid)
	for kind in _items_root.get_children():
		kind.queue_free()
	var bau := RanchBauState.lese(game_state())
	var zaun_stufe := RanchBauState.anlage_stufe(bau, "weidezaun")
	for uid: String in _grid.items():
		var item: Dictionary = _grid.items()[uid]
		var def: Dictionary = item["def"]
		var node: Node3D
		if item.has("kante"):
			node = RanchBauVisuals.zaun_node(zaun_stufe)
			var welt := RanchGridData.kante_world(item["at"], str(item["kante"]))
			node.position = welt["pos"]
			node.rotation.y = float(welt["rot"])
		else:
			var stufe := maxi(1, RanchBauState.anlage_stufe(bau, str(def["id"])))
			node = RanchBauVisuals.node_fuer(def, stufe)
			node.position = _anker_position(item["at"], def["footprint"], int(item["rot"]))
			node.rotation.y = -int(item["rot"]) * PI * 0.5
		node.set_meta("uid", uid)
		_items_root.add_child(node)


## Min-Ecken-Anker → Node-Position, sodass der Footprint nach Rotation die
## richtigen Zellen deckt (Rotation um die Node-Y-Achse am Anker).
func _anker_position(at: Vector2i, footprint: Vector2i, rot: int) -> Vector3:
	var s := RanchGridData.CELL_SIZE
	var fp := RanchGridData.rotated_footprint(footprint, rot)
	var basis := Vector3(at.x * s, 0.0, at.y * s)
	match posmod(rot, 4):
		1:
			return basis + Vector3(0.0, 0.0, fp.y * s)
		2:
			return basis + Vector3(fp.x * s, 0.0, fp.y * s)
		3:
			return basis + Vector3(fp.x * s, 0.0, 0.0)
		_:
			return basis


## ------------------------------------------------------------------ Input


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_pan and _kamera != null:
			_pan_um((event as InputEventMouseMotion).relative)
		else:
			_update_ghost((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_taste(event as InputEventKey)


func _mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_klick(event.position)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_drag_pan = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_dist = clampf(_dist / 1.12, 8.0, 70.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_dist = clampf(_dist * 1.12, 8.0, 70.0)


func _taste(event: InputEventKey) -> void:
	match event.keycode:
		KEY_R:
			_drehe_ghost()
		KEY_ESCAPE:
			_ghost_weg()
			_setze_abriss(false)
		KEY_Q:
			_yaw = wrapf(_yaw - 0.12, -PI, PI)
		KEY_E:
			_yaw = wrapf(_yaw + 0.12, -PI, PI)
		KEY_W, KEY_UP:
			_pivot += BuildCamera.offset_fuer(_yaw, 0.0, -1.5) * Vector3(1, 0, 1)
		KEY_S, KEY_DOWN:
			_pivot += BuildCamera.offset_fuer(_yaw, 0.0, 1.5) * Vector3(1, 0, 1)
		KEY_A, KEY_LEFT:
			_pivot += BuildCamera.offset_fuer(_yaw + PI * 0.5, 0.0, -1.5) * Vector3(1, 0, 1)
		KEY_D, KEY_RIGHT:
			_pivot += BuildCamera.offset_fuer(_yaw + PI * 0.5, 0.0, 1.5) * Vector3(1, 0, 1)


func _pan_um(relative: Vector2) -> void:
	var faktor := _dist * 0.0016
	var vor := BuildCamera.offset_fuer(_yaw, 0.0, -1.0) * Vector3(1, 0, 1)
	var seite := BuildCamera.offset_fuer(_yaw + PI * 0.5, 0.0, -1.0) * Vector3(1, 0, 1)
	_pivot += (vor * relative.y + seite * relative.x) * faktor
	_pivot.x = clampf(_pivot.x, 0.0, _grid.size.x * RanchGridData.CELL_SIZE)
	_pivot.z = clampf(_pivot.z, 0.0, _grid.size.y * RanchGridData.CELL_SIZE)


func _boden_punkt(screen_pos: Vector2) -> Vector3:
	var kamera := _kamera if _kamera != null else get_viewport().get_camera_3d()
	if kamera == null:
		return Vector3.INF
	var origin := kamera.project_ray_origin(screen_pos)
	var richtung := kamera.project_ray_normal(screen_pos)
	if absf(richtung.y) < 0.0001:
		return Vector3.INF
	var t := -origin.y / richtung.y
	if t < 0.0:
		return Vector3.INF
	return origin + richtung * t


## ------------------------------------------------------------------ Ghost


func _waehle_item(item_id: String) -> void:
	_setze_abriss(false)
	_auswahl_weg()
	_ghost_weg()
	if not _defs.has(item_id):
		return
	_ghost_id = item_id
	_ghost_rot = 0
	var def: Dictionary = _defs[item_id]
	if bool(def.get("kante", false)):
		_ghost = RanchBauVisuals.zaun_node(
			RanchBauState.anlage_stufe(RanchBauState.lese(game_state()), "weidezaun")
		)
	else:
		_ghost = RanchBauVisuals.node_fuer(def, 1)
	_mach_durchsichtig(_ghost)
	add_child(_ghost)
	_ghost.visible = false


func _update_ghost(screen_pos: Vector2) -> void:
	if _ghost == null:
		return
	var punkt := _boden_punkt(screen_pos)
	if punkt == Vector3.INF:
		return
	var def: Dictionary = _defs[_ghost_id]
	_ghost.visible = true
	if bool(def.get("kante", false)):
		var kante := RanchGridData.nearest_kante(punkt)
		_ghost_kante = kante
		var welt := RanchGridData.kante_world(kante["cell"], str(kante["seite"]))
		_ghost.position = welt["pos"]
		_ghost.rotation.y = float(welt["rot"])
		var ok := bool(_grid.can_place_kante(def, kante["cell"], str(kante["seite"]))["ok"])
		_overlay.highlight_kante(kante["cell"], str(kante["seite"]), ok)
	else:
		var cell := RanchGridData.cell_of(punkt)
		_ghost_cell = cell
		_ghost.position = _anker_position(cell, def["footprint"], _ghost_rot)
		_ghost.rotation.y = -_ghost_rot * PI * 0.5
		var ok := bool(_grid.can_place(def, cell, _ghost_rot)["ok"])
		_overlay.highlight_cells(RanchGridData.cells_for(cell, def["footprint"], _ghost_rot), ok)


func _drehe_ghost() -> void:
	if _ghost == null:
		return
	_ghost_rot = posmod(_ghost_rot + 1, 4)
	var def: Dictionary = _defs[_ghost_id]
	if not bool(def.get("kante", false)):
		_ghost.position = _anker_position(_ghost_cell, def["footprint"], _ghost_rot)
		_ghost.rotation.y = -_ghost_rot * PI * 0.5
		var ok := bool(_grid.can_place(def, _ghost_cell, _ghost_rot)["ok"])
		_overlay.highlight_cells(
			RanchGridData.cells_for(_ghost_cell, def["footprint"], _ghost_rot), ok
		)


func _ghost_weg() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_id = ""
	_ghost_kante = {}
	if _overlay != null:
		_overlay.clear_highlight()


func _mach_durchsichtig(node: Node) -> void:
	for kind in node.get_children():
		_mach_durchsichtig(kind)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.9, 1.0, GHOST_ALPHA)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_node.material_override = mat


## ------------------------------------------------------------------ Klick


func _klick(screen_pos: Vector2) -> void:
	var punkt := _boden_punkt(screen_pos)
	if punkt == Vector3.INF:
		return
	if _ghost != null:
		_platziere_ghost()
		return
	if _abriss_modus:
		_reisse_ab(punkt)
		return
	_waehle_an_position(punkt)


func _platziere_ghost() -> void:
	var def: Dictionary = _defs[_ghost_id]
	var res: Dictionary
	if bool(def.get("kante", false)):
		if _ghost_kante.is_empty():
			return
		res = RanchBauState.platziere_kante(
			game_state(), _ghost_id, _ghost_kante["cell"], str(_ghost_kante["seite"]), _balance
		)
	else:
		res = RanchBauState.platziere(game_state(), _ghost_id, _ghost_cell, _ghost_rot, _balance)
	if bool(res["ok"]):
		AudioDirector.try_play(self, "ui_buy")
		_zeige_feedback(I18nService.t("rbau.gebaut"))
		_rebuild_welt()
		# Kanten-Zäune und Böden dürfen in Serie gebaut werden — Ghost bleibt.
		if def["kategorie"] == "anlage":
			_ghost_weg()
	else:
		AudioDirector.try_play(self, "ui_error")
		_zeige_feedback(I18nService.t("rbau.fehler.%s" % str(res["fehler"])))
	_refresh_ui()


func _reisse_ab(punkt: Vector3) -> void:
	var uid := _uid_an_position(punkt)
	if uid == "":
		return
	var res := RanchBauState.entferne(game_state(), uid, _balance)
	if bool(res["ok"]):
		AudioDirector.try_play(self, "ui_back")
		_zeige_feedback(I18nService.t("rbau.abriss_erstattung", {"n": int(res["erstattung"])}))
		_rebuild_welt()
	_refresh_ui()


## Item unter einer Weltposition: erst nahe Kante (Zaun), dann OBJEKT-,
## dann BODEN-Layer.
func _uid_an_position(punkt: Vector3) -> String:
	var kante := RanchGridData.nearest_kante(punkt)
	var kanten_uid := _grid.kante_item_at(kante["cell"], str(kante["seite"]))
	if kanten_uid != "" and _kanten_abstand(punkt, kante) <= KANTE_SNAP_M:
		return kanten_uid
	var cell := RanchGridData.cell_of(punkt)
	var uid := _grid.item_at(cell, RanchGridData.Layer.OBJEKT)
	if uid != "":
		return uid
	return _grid.item_at(cell, RanchGridData.Layer.BODEN)


func _kanten_abstand(punkt: Vector3, kante: Dictionary) -> float:
	var welt := RanchGridData.kante_world(kante["cell"], str(kante["seite"]))
	var pos: Vector3 = welt["pos"]
	return Vector2(punkt.x - pos.x, punkt.z - pos.z).length()


func _waehle_an_position(punkt: Vector3) -> void:
	var uid := _uid_an_position(punkt)
	if uid == "":
		_auswahl_weg()
		return
	_auswahl_uid = uid
	_refresh_info()


func _auswahl_weg() -> void:
	_auswahl_uid = ""
	if _info_panel != null:
		_info_panel.visible = false


## ------------------------------------------------------------------ UI


func _baue_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "Ui"
	add_child(ui)
	# Kopfzeile: Titel, Münzen, Zonen-Freischaltung, Fertig.
	var kopf := PanelContainer.new()
	kopf.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	kopf.self_modulate = PAPIER
	ui.add_child(kopf)
	var kopf_box := HBoxContainer.new()
	kopf_box.add_theme_constant_override("separation", 12)
	kopf.add_child(kopf_box)
	var titel := Label.new()
	titel.text = I18nService.t("rbau.titel")
	titel.add_theme_font_size_override("font_size", 22)
	titel.add_theme_color_override("font_color", INK)
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf_box.add_child(titel)
	_zonen_box = HBoxContainer.new()
	kopf_box.add_child(_zonen_box)
	_coins_label = Label.new()
	_coins_label.add_theme_color_override("font_color", INK)
	kopf_box.add_child(_coins_label)
	_abriss_btn = Button.new()
	_abriss_btn.toggle_mode = true
	_abriss_btn.text = I18nService.t("rbau.abriss")
	_abriss_btn.toggled.connect(func(an: bool) -> void: _setze_abriss(an))
	kopf_box.add_child(_abriss_btn)
	var fertig := Button.new()
	fertig.text = I18nService.t("rbau.verlassen")
	fertig.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			fertig_pressed.emit()
	)
	kopf_box.add_child(fertig)
	# Fußzeile: Kategorien + Item-Leiste (Drawer).
	var fuss := PanelContainer.new()
	fuss.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fuss.grow_vertical = Control.GROW_DIRECTION_BEGIN
	fuss.self_modulate = PAPIER
	ui.add_child(fuss)
	var fuss_box := VBoxContainer.new()
	fuss.add_child(fuss_box)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	fuss_box.add_child(tabs)
	for kat: String in RanchBauKatalog.KATEGORIEN:
		var tab := Button.new()
		tab.text = I18nService.t("rbau.kategorie.%s" % kat)
		tab.pressed.connect(func() -> void: _setze_kategorie(kat))
		tabs.add_child(tab)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 92)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	fuss_box.add_child(scroll)
	_item_leiste = HBoxContainer.new()
	_item_leiste.add_theme_constant_override("separation", 8)
	scroll.add_child(_item_leiste)
	# Info-Panel (Auswahl): Name, Stufe, Nutzen, Ausbauen.
	_info_panel = PanelContainer.new()
	_info_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_info_panel.offset_left = -320.0
	_info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_info_panel.self_modulate = PAPIER
	_info_panel.visible = false
	ui.add_child(_info_panel)
	var info_box := VBoxContainer.new()
	info_box.custom_minimum_size = Vector2(300, 0)
	_info_panel.add_child(info_box)
	_info_text = Label.new()
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_text.add_theme_color_override("font_color", INK)
	info_box.add_child(_info_text)
	_ausbau_btn = Button.new()
	_ausbau_btn.pressed.connect(_on_ausbauen)
	info_box.add_child(_ausbau_btn)
	var zu := Button.new()
	zu.text = I18nService.t("rbau.verlassen")
	zu.pressed.connect(func() -> void: _auswahl_weg())
	info_box.add_child(zu)
	# Feedback-Toast.
	_feedback = Label.new()
	_feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_feedback.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_feedback.offset_top = 64.0
	_feedback.add_theme_font_size_override("font_size", 20)
	_feedback.add_theme_color_override("font_color", INK)
	_feedback.modulate.a = 0.0
	ui.add_child(_feedback)
	_setze_kategorie("anlage")


func _setze_kategorie(kat: String) -> void:
	_kategorie = kat
	for kind in _item_leiste.get_children():
		kind.queue_free()
	var bau := RanchBauState.lese(game_state())
	for id: String in RanchBauKatalog.ids(_balance, kat):
		var def: Dictionary = _defs[id]
		if bool(def.get("upgrade", false)):
			continue
		var knopf := Button.new()
		knopf.custom_minimum_size = Vector2(150, 72)
		var name_text: String = I18nService.t(str(def["name_key"]))
		var lager := int(_lager_anzahl(bau, id))
		if RanchBauState.anlage_stufe(bau, id) > 0 and def["kategorie"] == "anlage":
			knopf.text = (
				"%s\n%s"
				% [
					name_text,
					I18nService.t("rbau.stufe", {"n": RanchBauState.anlage_stufe(bau, id)})
				]
			)
			knopf.disabled = true
		elif lager > 0:
			knopf.text = (
				"%s\n%s" % [name_text, I18nService.t("rbau.platzieren_gratis", {"n": lager})]
			)
		else:
			knopf.text = "%s\n%d G" % [name_text, int(def["kosten"])]
		knopf.pressed.connect(func() -> void: _waehle_item(id))
		_item_leiste.add_child(knopf)


func _lager_anzahl(bau: Dictionary, id: String) -> int:
	var lager: Dictionary = bau.get("lager") if bau.get("lager") is Dictionary else {}
	return int(lager.get(id, 0))


func _setze_abriss(an: bool) -> void:
	_abriss_modus = an
	if _abriss_btn != null and _abriss_btn.button_pressed != an:
		_abriss_btn.button_pressed = an
	if an:
		_ghost_weg()
		_auswahl_weg()


func _refresh_ui() -> void:
	var gs := game_state()
	var coins := int(gs.get_value("economy.coins", 0)) if gs != null else 0
	_coins_label.text = "%d G" % coins
	_setze_kategorie(_kategorie)
	_refresh_zonen()


func _refresh_zonen() -> void:
	for kind in _zonen_box.get_children():
		kind.queue_free()
	var bau := RanchBauState.lese(game_state())
	var zonen := RanchBauKatalog.zonen(_balance)
	for zone_id: String in zonen:
		if (bau["zonen"] as Array).has(zone_id):
			continue
		var knopf := Button.new()
		knopf.text = (
			"%s: %s"
			% [
				I18nService.t("rbau.zone.%s" % zone_id),
				I18nService.t("rbau.zone_freischalten", {"preis": int(zonen[zone_id]["kosten"])}),
			]
		)
		knopf.pressed.connect(func() -> void: _on_zone(zone_id))
		_zonen_box.add_child(knopf)


func _on_zone(zone_id: String) -> void:
	var res := RanchBauState.zone_freischalten(game_state(), zone_id, _balance)
	if bool(res["ok"]):
		AudioDirector.try_play(self, "ui_buy")
		_zeige_feedback(
			I18nService.t("rbau.zone_frei", {"name": I18nService.t("rbau.zone.%s" % zone_id)})
		)
		_rebuild_welt()
	else:
		AudioDirector.try_play(self, "ui_error")
		_zeige_feedback(I18nService.t("rbau.fehler.%s" % str(res["fehler"])))
	_refresh_ui()


func _refresh_info() -> void:
	if _auswahl_uid == "" or not _grid.items().has(_auswahl_uid):
		_auswahl_weg()
		return
	var item: Dictionary = _grid.items()[_auswahl_uid]
	var def: Dictionary = item["def"]
	var id := str(def["id"])
	var bau := RanchBauState.lese(game_state())
	var zeilen: Array[String] = [I18nService.t(str(def["name_key"]))]
	if def["kategorie"] == "anlage":
		var stufe := RanchBauState.anlage_stufe(bau, id)
		var max_stufe := RanchBauKatalog.max_stufe(_balance, id)
		zeilen.append(I18nService.t("rbau.stufe", {"n": stufe}))
		zeilen.append(_nutzen_text(id, bau))
		var naechste := RanchBauKatalog.naechste_stufe_kosten(_balance, id, stufe)
		_ausbau_btn.visible = true
		if stufe >= max_stufe or naechste < 0:
			_ausbau_btn.text = I18nService.t("rbau.stufe_max")
			_ausbau_btn.disabled = true
		else:
			_ausbau_btn.text = I18nService.t("rbau.ausbauen", {"preis": naechste})
			_ausbau_btn.disabled = false
	else:
		_ausbau_btn.visible = false
	_info_text.text = "\n".join(zeilen)
	_info_panel.visible = true


func _nutzen_text(id: String, bau: Dictionary) -> String:
	var n := 0
	match id:
		"stallboxen":
			n = RanchBauEffekte.boxen_kapazitaet(bau, _balance)
		"heulager":
			n = RanchBauEffekte.heu_kapazitaet(bau, _balance)
		"tribuene":
			n = RanchBauEffekte.tribuene_zuschauer(bau, _balance)
	return I18nService.t("rbau.nutzen.%s" % id, {"n": n})


func _on_ausbauen() -> void:
	if _auswahl_uid == "" or not _grid.items().has(_auswahl_uid):
		return
	var id := str((_grid.items()[_auswahl_uid]["def"] as Dictionary)["id"])
	var res := RanchBauState.ausbauen(game_state(), id, _balance)
	if bool(res["ok"]):
		AudioDirector.try_play(self, "ui_buy")
		_zeige_feedback(
			I18nService.t(
				"rbau.ausgebaut",
				{"name": I18nService.t("rbau.item.%s" % id), "n": int(res["stufe"])}
			)
		)
		_rebuild_welt()
		_refresh_info()
	else:
		AudioDirector.try_play(self, "ui_error")
		_zeige_feedback(I18nService.t("rbau.fehler.%s" % str(res["fehler"])))
	_refresh_ui()


func _zeige_feedback(text: String) -> void:
	_feedback.text = text
	_feedback_t = 1.4
	_feedback.modulate.a = 1.0
