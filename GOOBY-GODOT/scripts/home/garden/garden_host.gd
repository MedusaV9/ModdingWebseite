class_name GardenHost
extends Node3D
## Garten-Steuerung (Doc D §6) im Garten-Raum: hängt die GardenView ein,
## nimmt Taps auf Zellen entgegen und blendet die Aktionsleiste ein
## (pflanzen, gießen, ernten, sammeln, bauen, Garten erweitern, Shed
## ausbauen, Werkstatt öffnen).
##
## Regeln und Persistenz liegen komplett in GardenState/GardenWorld/
## GardenGrowth — dieser Host ist Verdrahtung, Animation und Anzeige.
## Bauen kostet KEINE Energie (User-Regel).

const Economy := preload("res://scripts/logic/economy.gd")

const ROOM_ID := "garden"
## Auswahl-Info wird nach jeder Aktion neu gerechnet.
const ICON_PX := 20

var _room: Node
var _gs: Object
var _view: GardenView
var _ui: Control
var _info: Label
var _aktionen: HBoxContainer
var _auswahl := Vector2i(-1, -1)
var _menue: VBoxContainer
var _rng := RandomNumberGenerator.new()
var _jetzt_override := -1.0
## Rolltor-Zustand ist RUNTIME-only (W13C, Doc D §7) — nicht im Save.
var _rolltor_zustand := GarageLogic.ROLLTOR_ZU


## Host an den Garten-Raum hängen (idempotent; andere Räume ignoriert er).
static func attach_to(room: Node) -> GardenHost:
	if str(room.get("room_id")) != ROOM_ID:
		return null
	var vorhanden := room.get_node_or_null("GardenHost")
	if vorhanden is GardenHost:
		return vorhanden
	var host := GardenHost.new()
	host.name = "GardenHost"
	room.add_child(host)
	host.setup(room)
	return host


func setup(room: Node) -> void:
	_room = room
	_gs = room.game_state()
	_rng.randomize()
	if _gs == null:
		return
	GardenState.tick(_gs, jetzt_s())
	GardenWorld.refresh_spots(_gs, jetzt_s(), _rng)
	# W13/WETTER-FX: sichtbarer Regen/Schnee im Garten (Plan aus SoulWetter).
	GardenWorld.wetter_fx_anhaengen(room)
	_view = GardenView.new()
	_view.name = "GardenView"
	add_child(_view)
	_view.setup(_gs, _room_meter(), _room.blockers())
	_build_ui()
	_refresh()
	_lieferung_starten()


## Wartet eine Möbel-Bestellung, fährt der LKW vor (Doc D §3.2).
func _lieferung_starten() -> void:
	var szene := DeliveryCutscene.attach_if_pending(_room, _gs)
	if szene == null:
		return
	szene.fertig.connect(func(_menge: int) -> void: _refresh())
	szene.spielen.call_deferred()


## Testbare Uhr (Sekunden). Screenshots/Tests setzen `_jetzt_override`.
func jetzt_s() -> float:
	if _jetzt_override >= 0.0:
		return _jetzt_override
	return Time.get_unix_time_from_system()


func set_jetzt_override(sekunden: float) -> void:
	_jetzt_override = sekunden


func view() -> GardenView:
	return _view


## Zelle auswählen (Tap oder Test). Tap auf die Garage = Rolltor auf/zu
## (W13C, Doc D §7) — nach dem Refresh, damit der Tween den frischen Prop
## animiert statt eines gerade weggeworfenen.
func select_cell(cell: Vector2i) -> void:
	_auswahl = cell
	_view.highlight(cell)
	_refresh()
	if str(_view.garden_grid().structure_at(cell).get("kind", "")) == GarageLogic.KIND:
		rolltor_toggle()


# ── Aktionen ─────────────────────────────────────────────────────────────────


func pflanzen(crop_id: String) -> bool:
	var ok := GardenState.pflanzen(_gs, _auswahl, crop_id)
	if ok:
		AudioDirector.try_play(self, "ui_confirm")
	var text := ""
	if not ok:
		# W15/CROPS: Saatgut-Crops scheitern meist am leeren Samen-Beutel —
		# dann hilft der REHWEI-Hinweis statt „passt nicht hin“.
		text = I18nService.t(
			(
				"garten.samen_fehlt"
				if GardenState.samen_count(_gs, crop_id) == 0
				else "garten.kein_platz"
			)
		)
	_nach_aktion(ok, text)
	return ok


func giessen() -> void:
	var ok := GardenState.giessen(_gs, _auswahl, jetzt_s())
	if ok:
		AudioDirector.try_play(self, "ui_chip")
	_nach_aktion(ok, "" if ok else I18nService.t("garten.leer"))


func ernten() -> void:
	var crop_id := str(_view.garden_grid().cell(_auswahl).get("crop", ""))
	var menge := GardenState.ernten(_gs, _auswahl)
	var text := ""
	if menge > 0:
		text = I18nService.t(
			"garten.ernte_erhalten",
			{"menge": menge, "name": GardenCrops.display_name(crop_id, I18nService.get_locale())}
		)
		# W15/CROPS: knuffiger Gooby-Ernte-Kommentar, wo einer existiert
		# (garten.spruch.<crop_id>, de+en) — hängt an der Ernte-Zeile.
		if I18nService.has_key("garten.spruch.%s" % crop_id):
			text += "\n" + I18nService.t("garten.spruch.%s" % crop_id)
		AudioDirector.try_play(self, "ui_confirm")
	_nach_aktion(menge > 0, text)


func sammeln() -> void:
	var material_id := GardenWorld.sammeln(_gs, _auswahl, jetzt_s())
	var text := ""
	if material_id != "":
		text = I18nService.t(
			"garten.gesammelt",
			{"name": CraftMaterials.display_name(material_id, I18nService.get_locale())}
		)
		AudioDirector.try_play(self, "ui_chip")
	_nach_aktion(material_id != "", text)


## Baum ernten (Holz) — der Baum bleibt stehen und wächst nach.
func baum_ernten() -> void:
	var menge := GardenWorld.baum_ernten(_gs, _baum_zelle(), jetzt_s())
	var text := (
		I18nService.t("garten.baum_reif", {"menge": menge})
		if menge > 0
		else I18nService.t("garten.baum_jung")
	)
	_nach_aktion(menge > 0, text)


## Garten-Bauwerk auf der Auswahl errichten (inkl. Bau-Animation).
func bauen(kind: String) -> bool:
	if kind == "shed":
		return await shed_bauen()
	var tuer := _tuer_zelle(kind, _auswahl)
	var ergebnis := GardenWorld.bauen(_gs, kind, _auswahl, 0, tuer)
	if not bool(ergebnis["ok"]):
		_nach_aktion(false, _bau_fehler(str(ergebnis["reason"])))
		return false
	await _bau_animation(_auswahl)
	_nach_aktion(true, I18nService.t("garten.struktur.%s" % kind))
	return true


## Shed bauen bzw. auf die nächste Stufe ausbauen (mehr Lagerplatz).
func shed_bauen() -> bool:
	var vorher := HomeState.shed_stufe(_gs)
	var frisch := _view.garden_grid().structures_of_kind("shed").is_empty()
	if frisch:
		var grid := GardenState.grid(_gs)
		var pruefung := grid.can_place_structure("shed", _auswahl)
		if not bool(pruefung["ok"]):
			_nach_aktion(false, _bau_fehler(str(pruefung["reason"])))
			return false
	if HomeState.upgrade_shed(_gs) == vorher:
		_nach_aktion(false, I18nService.t("shed.zu_teuer"))
		return false
	if frisch:
		var grid := GardenState.grid(_gs)
		grid.place_structure("shed", _auswahl)
		GardenState.save_grid(_gs, grid)
	await _bau_animation(_auswahl)
	_nach_aktion(true, I18nService.t("shed.fertig"))
	return true


## Garage kaufen + bauen (W13C, Doc D §7) — einmalig, Muster shed_bauen().
func garage_bauen() -> bool:
	var ergebnis := GarageLogic.kaufen(_gs, _auswahl)
	if not bool(ergebnis["ok"]):
		var reason := str(ergebnis["reason"])
		var text := (
			I18nService.t("garage.schon_gebaut")
			if reason == GarageLogic.REASON_SCHON_GEBAUT
			else _bau_fehler(reason)
		)
		_nach_aktion(false, text)
		return false
	await _bau_animation(_auswahl)
	_nach_aktion(true, I18nService.t("garage.fertig"))
	return true


## Rolltor auf/zu (Zustandsmaschine GarageLogic; Toggle mitten in der Fahrt
## kehrt die Richtung um). KEIN _refresh hier — der würde den Prop samt
## laufendem Tween wegwerfen.
func rolltor_toggle() -> void:
	var prop := _garage_prop()
	if prop == null:
		return
	_rolltor_zustand = GarageLogic.rolltor_toggle(_rolltor_zustand)
	var tween := prop.rolltor_fahren(GarageLogic.rolltor_ziel_anteil(_rolltor_zustand))
	if tween != null:
		tween.finished.connect(_rolltor_ende)
	if prop.auto_id() == "" and _room.has_method("say"):
		_room.say(I18nService.t("garage.kein_auto"))
	_leichte_aktualisierung()


func rolltor_zustand() -> String:
	return _rolltor_zustand


## Garten eine Stufe größer machen (kostet Münzen).
func erweitern() -> bool:
	var preis := GardenState.next_stufe_preis(_gs)
	if preis <= 0:
		_nach_aktion(false, I18nService.t("garten.max_ausgebaut"))
		return false
	if int(_gs.get_value("economy.coins", 0)) < preis:
		_nach_aktion(false, I18nService.t("shed.zu_teuer"))
		return false
	_gs.update(
		func(state: Dictionary) -> void: Economy.spend(state["economy"], preis, "garten_ausbau")
	)
	GardenState.erweitern(_gs)
	_nach_aktion(true, I18nService.t("garten.erweitert"))
	return true


## Werkstatt-Panel öffnen (nur wenn die Werkstatt im Garten steht).
func werkstatt_oeffnen() -> void:
	if not CraftState.werkstatt_gebaut(_gs):
		_nach_aktion(false, I18nService.t("craft.werkstatt_fehlt"))
		return
	var panel := CraftPanel.open_in(_ui_layer(), _gs, _room)
	panel.crafted.connect(func(_item: String, _count: int) -> void: _refresh())
	panel.closed.connect(_refresh)


## Goobay-Handy öffnen (Verkauf aus dem Lager).
func goobay_oeffnen() -> void:
	var panel := GoobayPanel.open_in(_ui_layer(), _gs, _room)
	panel.closed.connect(_refresh)


# ── Eingabe ──────────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if _view == null or _room.is_build_mode_active():
		return
	var pressed: bool = (
		(event is InputEventMouseButton and event.pressed and event.button_index == 1)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not pressed:
		return
	var welt := _pointer_to_floor(event.position)
	if welt == Vector3.INF:
		return
	var cell := _view.world_to_cell(welt)
	if cell.x >= 0:
		select_cell(cell)


func _pointer_to_floor(screen_pos: Vector2) -> Vector3:
	var rig: HomeCameraRig = _room.camera_rig()
	if rig == null or rig.camera == null:
		return Vector3.INF
	var origin := rig.camera.project_ray_origin(screen_pos)
	var dir := rig.camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001 or -origin.y / dir.y < 0.0:
		return Vector3.INF
	return origin + dir * (-origin.y / dir.y)


# ── UI ───────────────────────────────────────────────────────────────────────


func _ui_layer() -> Node:
	return _room.ui_layer()


func _build_ui() -> void:
	_ui = PanelContainer.new()
	_ui.name = "GardenUi"
	_ui.theme = ThemeService.theme()
	_ui.theme_type_variation = "AcCard"
	_ui.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_ui_layer().add_child(_ui)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_ui.add_child(box)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_aktionen = HBoxContainer.new()
	_aktionen.add_theme_constant_override("separation", 6)
	box.add_child(_aktionen)
	_menue = VBoxContainer.new()
	_menue.add_theme_constant_override("separation", 4)
	box.add_child(_menue)


func _refresh() -> void:
	if _view == null:
		return
	_view.rebuild(_room_meter())
	_garage_sync()
	_view.highlight(_auswahl)
	_leichte_aktualisierung()


## Nur Menü/Info/Aktionsleiste neu — OHNE View-Rebuild (Rolltor-Tween lebt).
func _leichte_aktualisierung() -> void:
	_menue_leeren()
	_info.text = _info_text()
	_aktions_leiste()


func _info_text() -> String:
	var stufe := HomeState.shed_stufe(_gs)
	var kopf := (
		"%s — %s · %s"
		% [
			I18nService.t("garten.titel"),
			I18nService.t("shed.stufe", {"stufe": stufe}),
			I18nService.t("shed.lager", {"kapazitaet": HomeState.storage_capacity(_gs)}),
		]
	)
	if _auswahl.x < 0:
		return kopf
	var grid := _view.garden_grid()
	var data := grid.cell(_auswahl)
	var crop_id := str(data.get("crop", ""))
	if crop_id == "":
		return "%s\n%s" % [kopf, I18nService.t("garten.leer")]
	var crop := GardenCrops.crop(crop_id)
	var faktoren := GardenGrowth.faktoren(
		grid, _auswahl, jetzt_s(), false, GardenGrowth.schatten_zellen(grid)
	)
	var zustand := (
		I18nService.t("garten.reif")
		if GardenGrowth.ist_erntereif(data)
		else I18nService.t(
			"garten.waechst", {"stufe": int(data.get("stage", 0)), "max": int(crop["stufen"])}
		)
	)
	if float(faktoren["wasser"]) <= 0.0:
		zustand += " " + I18nService.t("garten.durstig")
	return (
		"%s\n%s: %s\n%s"
		% [
			kopf,
			GardenCrops.display_name(crop_id, I18nService.get_locale()),
			zustand,
			_faktor_text(faktoren)
		]
	)


func _faktor_text(faktoren: Dictionary) -> String:
	return (
		" · "
		. join(
			[
				I18nService.t("garten.faktoren", {"rate": snappedf(float(faktoren["rate"]), 0.01)}),
				I18nService.t("garten.faktor_wasser", {"wert": float(faktoren["wasser"])}),
				I18nService.t("garten.faktor_wind", {"wert": float(faktoren["wind"])}),
				I18nService.t("garten.faktor_schatten", {"wert": float(faktoren["schatten"])}),
				I18nService.t(
					"garten.faktor_gewaechshaus", {"wert": float(faktoren["gewaechshaus"])}
				),
			]
		)
	)


func _aktions_leiste() -> void:
	for child in _aktionen.get_children():
		child.queue_free()
	var grid := _view.garden_grid()
	var data := grid.cell(_auswahl) if _auswahl.x >= 0 else {}
	var crop_id := str(data.get("crop", ""))
	if _auswahl.x >= 0 and crop_id == "":
		_knopf("garten.pflanzen", "PrimaryButton", _pflanzen_menue)
	if crop_id != "":
		_knopf("garten.giessen", "ChipSky", giessen)
		if GardenGrowth.ist_erntereif(data):
			_knopf("garten.ernten", "ChipLeaf", ernten)
	if _auswahl.x >= 0 and _spot_hier():
		_knopf("garten.sammeln", "ChipLeaf", sammeln)
	if _auswahl.x >= 0 and str(grid.structure_at(_auswahl).get("kind", "")) == "baum":
		_knopf("garten.baum_ernten", "ChipLeaf", baum_ernten)
	if _auswahl.x >= 0 and str(grid.structure_at(_auswahl).get("kind", "")) == GarageLogic.KIND:
		var tor_key := (
			"garage.tor_zu"
			if GarageLogic.rolltor_ziel_anteil(_rolltor_zustand) > 0.5
			else "garage.tor_auf"
		)
		_knopf(tor_key, "ChipSky", rolltor_toggle)
	if _auswahl.x >= 0:
		_knopf("garten.bauen", "AccentButton", _bau_menue)
	_knopf("craft.titel", "AcChip", werkstatt_oeffnen)
	_knopf("goobay.titel", "AcChip", goobay_oeffnen)
	var preis := GardenState.next_stufe_preis(_gs)
	if preis > 0:
		var btn := Button.new()
		btn.text = I18nService.t("garten.erweitern", {"preis": preis})
		btn.theme_type_variation = "AcChip"
		btn.pressed.connect(erweitern)
		_aktionen.add_child(btn)


func _knopf(key: String, variation: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = I18nService.t(key)
	btn.theme_type_variation = variation
	btn.pressed.connect(handler)
	_aktionen.add_child(btn)


func _menue_leeren() -> void:
	for child in _menue.get_children():
		child.queue_free()


func _pflanzen_menue() -> void:
	_menue_leeren()
	var im_gh := _view.garden_grid().greenhouse_cells().has(_auswahl)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 6)
	_menue.add_child(zeile)
	for crop: Dictionary in GardenCrops.plantable(im_gh):
		var btn := Button.new()
		btn.theme_type_variation = "AcChip"
		btn.text = GardenCrops.display_name(str(crop["id"]), I18nService.get_locale())
		# W15/CROPS: Saatgut-Crops zeigen den Samen-Vorrat und sperren bei 0
		# (Samen gibt es bei REHWEI; Alt-Crops bleiben frei pflanzbar).
		var samen := GardenState.samen_count(_gs, str(crop["id"]))
		if samen >= 0:
			btn.text += " · " + I18nService.t("garten.samen_kurz", {"n": samen})
			btn.disabled = samen <= 0
		btn.pressed.connect(pflanzen.bind(str(crop["id"])))
		zeile.add_child(btn)


func _bau_menue() -> void:
	_menue_leeren()
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 6)
	_menue.add_child(zeile)
	for kind: String in GardenWorld.KAUFBAR:
		var btn := Button.new()
		btn.theme_type_variation = "AcChip"
		btn.text = (
			"%s (%d ᴳ)"
			% [
				I18nService.t("garten.struktur.%s" % kind),
				CraftMaterials.baumarkt_preis("struktur", kind),
			]
		)
		btn.pressed.connect(bauen.bind(kind))
		zeile.add_child(btn)
	var shed := Button.new()
	shed.theme_type_variation = "AcChip"
	var shed_preis := ShedLogic.upgrade_preis(HomeState.shed_stufe(_gs))
	shed.text = (
		I18nService.t("shed.max")
		if shed_preis <= 0
		else "%s (%d ᴳ)" % [I18nService.t("garten.struktur.shed"), shed_preis]
	)
	shed.disabled = shed_preis <= 0
	shed.pressed.connect(shed_bauen)
	zeile.add_child(shed)
	var garage := Button.new()
	garage.theme_type_variation = "AcChip"
	garage.text = (
		I18nService.t("garage.gebaut")
		if GarageLogic.gebaut(_gs)
		else "%s (%d ᴳ)" % [I18nService.t("garage.name"), GarageLogic.PREIS]
	)
	garage.disabled = GarageLogic.gebaut(_gs)
	garage.pressed.connect(garage_bauen)
	zeile.add_child(garage)


# ── Helfer ───────────────────────────────────────────────────────────────────


func _nach_aktion(ok: bool, text: String) -> void:
	if not ok:
		AudioDirector.try_play(self, "ui_error")
	if text != "" and _room.has_method("say"):
		_room.say(text)
	_refresh()


func _bau_animation(cell: Vector2i) -> void:
	var welt := _view.cell_to_world(cell)
	await HomeBuildAnim.puff(self, welt)
	_view.rebuild(_room_meter())
	_room.request_rebake()


## Der lebende Garage-Prop im Baum (queue_free-Leichen nach Rebuild filtern).
func _garage_prop() -> GarageProp:
	for node in get_tree().get_nodes_in_group(GarageProp.GRUPPE):
		if node is GarageProp and not node.is_queued_for_deletion():
			return node
	return null


## Nach jedem View-Rebuild steht der frisch erzeugte Prop wieder auf „zu" —
## den Torzustand der Zustandsmaschine (Fahrten enden dabei sofort) aufs
## Prop-Blatt schnappen.
func _garage_sync() -> void:
	var prop := _garage_prop()
	if prop == null:
		_rolltor_zustand = GarageLogic.ROLLTOR_ZU
		return
	_rolltor_zustand = GarageLogic.rolltor_ende(_rolltor_zustand)
	prop.set_rolltor_anteil(GarageLogic.rolltor_ziel_anteil(_rolltor_zustand))


func _rolltor_ende() -> void:
	_rolltor_zustand = GarageLogic.rolltor_ende(_rolltor_zustand)
	_leichte_aktualisierung()


func _bau_fehler(reason: String) -> String:
	if reason == "zu_teuer":
		return I18nService.t("shed.zu_teuer")
	return I18nService.t("garten.kein_platz")


## Tür-Zelle eines Gewächshauses: erste Footprint-Zelle mit freiem Nachbarn.
func _tuer_zelle(kind: String, at: Vector2i) -> Vector2i:
	if kind != "gewaechshaus":
		return Vector2i(-1, -1)
	var grid := _view.garden_grid()
	for cell in GardenGrid.structure_cells(kind, at, 0):
		if bool(grid.can_place_structure(kind, at, 0, cell)["ok"]):
			return cell
	return Vector2i(-1, -1)


func _spot_hier() -> bool:
	for spot: Dictionary in GardenWorld.offene_spots(_gs):
		if spot["at"] == _auswahl:
			return true
	return false


func _baum_zelle() -> Vector2i:
	var eintrag := _view.garden_grid().structure_at(_auswahl)
	return eintrag.get("at", Vector2i(-1, -1)) if not eintrag.is_empty() else Vector2i(-1, -1)


func _room_meter() -> Vector2:
	var zellen: Vector2i = RoomDefs.room(ROOM_ID).get("grid", Vector2i(28, 24))
	return Vector2(zellen.x * GridData.CELL_SIZE, zellen.y * GridData.CELL_SIZE)
