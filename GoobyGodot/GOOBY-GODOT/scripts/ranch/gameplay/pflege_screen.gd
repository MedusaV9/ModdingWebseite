class_name RanchPflegeScreen
extends Control
## Pferdepflege-Screen (RANCH-2): Füttern (Heu/Apfel/Karotte), Tränken,
## Striegeln und Stall-Ausmisten für EIN Pferd — mit 3D-Vorschau
## (RanchPferd + Gear-Aufsätze), Werte-/Bindungs-Balken und Ausrüstungs-
## Zeile. ALLE Regeln kommen aus RanchHorseCare/RanchWirtschaft (PURE);
## dieser Screen ist nur Verdrahtung + Buchung in den ranch-Slice.
##
## Einbau (RANCH-1): mounten, `setup(pferd_id)` VOR add_child, Signal
## `back_pressed` verdrahten. Tests injizieren `game_state_override`.

signal back_pressed

const Care := preload("res://scripts/ranch/gameplay/horse_care.gd")
const Offline := preload("res://scripts/ranch/gameplay/ranch_offline.gd")

## Fell-Ids → Anzeige-Farben (Fallback ohne RANCH-1s farbeHex am Pferd).
const FELL_HEX := {
	"braun": Color("#C58B5A"),
	"schwarz": Color("#524A4E"),
	"weiss": Color("#EFEBE2"),
	"fuchs": Color("#B55E39"),
	"palomino": Color("#E3C078"),
	"schecke": Color("#D9A066"),
}
const INK := Color("#3B3630")
const BALKEN_FARBEN := {
	"hunger": Color("#E8A23A"),
	"durst": Color("#5FA4D9"),
	"sauberkeit": Color("#8FC98A"),
	"bindung": Color("#E98CA0"),
	"stall": Color("#B79A6B"),
}

var game_state_override: Object
var pferd_id := ""

var _viewport: SubViewport
var _pferd_node: RanchPferd
var _split: BoxContainer
var _name_label: Label
var _laune_label: Label
var _balken: Dictionary = {}
var _lager_label: Label
var _feedback: Label
var _feedback_t := 0.0
var _aktion_buttons: Dictionary = {}
var _gear_row: HBoxContainer


func setup(id: String) -> void:
	pferd_id = id


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_werte_aktualisieren_offline()
	if pferd_id == "":
		pferd_id = _erstes_pferd()
	_build_layout()
	_build_pferd_vorschau()
	refresh()
	resized.connect(_on_resized)
	_on_resized()


func _process(delta: float) -> void:
	if _feedback_t > 0.0:
		_feedback_t -= delta
		_feedback.modulate.a = clampf(_feedback_t / 0.4, 0.0, 1.0)


## Tagesrhythmus/Offline-Verfall VOR dem Anzeigen nachziehen (einzige
## Zeit-Buchung des Screens; die Regeln liegen in RanchOffline).
func _werte_aktualisieren_offline() -> void:
	var gs := game_state()
	if gs == null:
		return
	var tiere: Variant = gs.get_value("ranch.tiere", {})
	if not (tiere is Dictionary):
		return
	var wirtschaft: Variant = gs.get_value("ranch.wirtschaft", {})
	var mult := 1.0
	if wirtschaft is Dictionary:
		mult = RanchWirtschaft.weide_sauberkeit_mult(wirtschaft, RanchWirtschaft.load_balance())
	var ergebnis := Offline.simulate_offline(tiere, _now_ms(), {"sauberkeitMult": mult})
	gs.update(
		func(state: Dictionary) -> void:
			var ranch: Dictionary = state.get("ranch") if state.get("ranch") is Dictionary else {}
			ranch["tiere"] = ergebnis["tiere"]
			state["ranch"] = ranch
	)
	gs.notify_slice_changed("ranch")


func _erstes_pferd() -> String:
	var gs := game_state()
	if gs == null:
		return ""
	var pferde: Variant = gs.get_value("ranch.tiere.pferde", {})
	if pferde is Dictionary and not (pferde as Dictionary).is_empty():
		var ids: Array = (pferde as Dictionary).keys()
		ids.sort()
		return str(ids[0])
	return ""


func _pferd() -> Dictionary:
	var gs := game_state()
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("ranch.tiere.pferde.%s" % pferd_id, {})
	return raw if raw is Dictionary else {}


## ------------------------------------------------------------------ Aufbau


func _build_layout() -> void:
	var hintergrund := ColorRect.new()
	hintergrund.color = Color("#F3EAD9")
	hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hintergrund)
	_split = BoxContainer.new()
	_split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_split)
	# Linke/obere Hälfte: 3D-Vorschau.
	var view_container := SubViewportContainer.new()
	view_container.stretch = true
	view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	view_container.add_child(_viewport)
	_split.add_child(view_container)
	# Rechte/untere Hälfte: Werte + Aktionen.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var kopf := HBoxContainer.new()
	panel.add_child(kopf)
	_name_label = Label.new()
	_name_label.theme_type_variation = &"HeadlineLabel"
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_color", INK)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(_name_label)
	var zurueck := Button.new()
	zurueck.text = I18nService.t("ranchplay.pflege.zurueck")
	zurueck.custom_minimum_size = Vector2(120, 44)
	zurueck.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			back_pressed.emit()
	)
	kopf.add_child(zurueck)
	_laune_label = Label.new()
	_laune_label.theme_type_variation = &"CaptionLabel"
	_laune_label.add_theme_color_override("font_color", INK)
	panel.add_child(_laune_label)
	for key: String in ["hunger", "durst", "sauberkeit", "bindung", "stall"]:
		panel.add_child(_build_balken_zeile(key))
	_lager_label = Label.new()
	_lager_label.theme_type_variation = &"CaptionLabel"
	_lager_label.add_theme_color_override("font_color", INK)
	panel.add_child(_lager_label)
	var aktionen := GridContainer.new()
	aktionen.columns = 3
	aktionen.add_theme_constant_override("h_separation", 8)
	aktionen.add_theme_constant_override("v_separation", 8)
	panel.add_child(aktionen)
	for aktion: String in ["heu", "apfel", "karotte", "traenken", "striegeln", "ausmisten"]:
		var btn := Button.new()
		btn.text = I18nService.t("ranchplay.pflege.%s" % aktion)
		btn.custom_minimum_size = Vector2(120, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_aktion.bind(aktion))
		aktionen.add_child(btn)
		_aktion_buttons[aktion] = btn
	var gear_titel := Label.new()
	gear_titel.theme_type_variation = &"CaptionLabel"
	gear_titel.text = I18nService.t("ranchplay.pflege.gear")
	gear_titel.add_theme_color_override("font_color", INK)
	panel.add_child(gear_titel)
	_gear_row = HBoxContainer.new()
	_gear_row.add_theme_constant_override("separation", 6)
	panel.add_child(_gear_row)
	_feedback = Label.new()
	_feedback.theme_type_variation = &"HeadlineLabel"
	_feedback.add_theme_color_override("font_color", Color("#5FA052"))
	_feedback.modulate.a = 0.0
	panel.add_child(_feedback)


func _build_balken_zeile(key: String) -> Control:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.text = I18nService.t("ranchplay.werte.%s" % key)
	label.custom_minimum_size = Vector2(110, 0)
	label.add_theme_color_override("font_color", INK)
	zeile.add_child(label)
	var balken := ProgressBar.new()
	balken.min_value = 0.0
	balken.max_value = 100.0
	balken.show_percentage = false
	balken.custom_minimum_size = Vector2(0, 22)
	balken.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balken.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fuellung := StyleBoxFlat.new()
	fuellung.bg_color = BALKEN_FARBEN[key]
	fuellung.set_corner_radius_all(8)
	balken.add_theme_stylebox_override("fill", fuellung)
	var hintergrund := StyleBoxFlat.new()
	hintergrund.bg_color = Color("#E2D8C4")
	hintergrund.set_corner_radius_all(8)
	balken.add_theme_stylebox_override("background", hintergrund)
	zeile.add_child(balken)
	var wert := Label.new()
	wert.theme_type_variation = &"CaptionLabel"
	wert.custom_minimum_size = Vector2(46, 0)
	wert.add_theme_color_override("font_color", INK)
	zeile.add_child(wert)
	_balken[key] = {"bar": balken, "label": wert}
	return zeile


func _build_pferd_vorschau() -> void:
	var licht := DirectionalLight3D.new()
	licht.light_energy = 1.15
	licht.look_at_from_position(Vector3(2.0, 4.0, 3.0), Vector3.ZERO, Vector3.UP)
	_viewport.add_child(licht)
	var umgebung := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#DCEFDB")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.88)
	env.ambient_light_energy = 0.7
	umgebung.environment = env
	_viewport.add_child(umgebung)
	var boden := MeshInstance3D.new()
	var boden_mesh := CylinderMesh.new()
	boden_mesh.top_radius = 2.2
	boden_mesh.bottom_radius = 2.2
	boden_mesh.height = 0.12
	boden.mesh = boden_mesh
	boden.position.y = -0.06
	boden.material_override = RanchPferd.material(Color(0.62, 0.8, 0.5))
	_viewport.add_child(boden)
	var pferd := _pferd()
	var fell: Color = FELL_HEX.get(str(pferd.get("farbe", "braun")), FELL_HEX["braun"])
	if str(pferd.get("farbeHex", "")) != "":
		fell = Color(str(pferd["farbeHex"]))
	var maehne := fell.darkened(0.35)
	if str(pferd.get("maehneHex", "")) != "":
		maehne = Color(str(pferd["maehneHex"]))
	_pferd_node = RanchPferd.neu(fell, maehne)
	# Dreiviertel-Frontansicht: Gesicht + Sattelflanke zur Kamera.
	_pferd_node.rotation.y = PI - 0.9
	_viewport.add_child(_pferd_node)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.5, 4.2)
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.fov = 45.0
	cam.current = true
	_viewport.add_child(cam)
	_gear_anwenden()


## Gear-Aufsätze nach Save-Stand anlegen — RanchPferd.equip() kennt die
## richtigen Ankerpunkte seiner Proportionen (Halfter am Kopf-Pivot).
func _gear_anwenden() -> void:
	if _pferd_node == null:
		return
	var ausr: Variant = _pferd().get("ausruestung")
	for slot: String in RanchWirtschaft.GEAR_SLOTS:
		var farbe: Variant = (ausr as Dictionary).get(slot) if ausr is Dictionary else null
		_pferd_node.equip(slot, farbe if farbe is String else null)


## ----------------------------------------------------------------- Anzeige


func refresh() -> void:
	var gs := game_state()
	var pferd := _pferd()
	var werte: Dictionary = (
		pferd.get("werte") if pferd.get("werte") is Dictionary else Care.clamp_werte({})
	)
	var bindung := float(Care.clamp_wert(pferd.get("bindung")))
	var anzeige_name := str(pferd.get("name", pferd_id))
	if str(pferd.get("nameKey", "")) != "" and I18nService.has_key(str(pferd["nameKey"])):
		anzeige_name = I18nService.t(str(pferd["nameKey"]))
	_name_label.text = anzeige_name
	var laune := Care.laune(werte, bindung)
	_laune_label.text = (
		I18nService
		. t(
			"ranchplay.pflege.status",
			{
				"laune": I18nService.t("ranchplay.laune.%s" % Care.laune_band(laune)),
				"stufe": I18nService.t("ranchplay.bindung.%s" % Care.bindung_stufe(bindung)),
			}
		)
	)
	var stall := 100.0
	if gs != null:
		stall = float(Care.clamp_wert(gs.get_value("ranch.tiere.stall.sauberkeit", 100.0)))
	var stand := {
		"hunger": float(werte.get("hunger", 0.0)),
		"durst": float(werte.get("durst", 0.0)),
		"sauberkeit": float(werte.get("sauberkeit", 0.0)),
		"bindung": bindung,
		"stall": stall,
	}
	for key: String in stand:
		var bar: ProgressBar = _balken[key]["bar"]
		bar.value = stand[key]
		(_balken[key]["label"] as Label).text = "%d" % int(round(stand[key]))
	var heu := 0
	var apfel := 0
	var karotten := 0
	if gs != null:
		heu = int(gs.get_value("ranch.wirtschaft.lager.heu", 0))
		apfel = int(gs.get_value("ranch.wirtschaft.lager.apfel", 0))
		karotten = int(gs.get_value("inventory.food.carrot", 0))
	_lager_label.text = I18nService.t(
		"ranchplay.pflege.lager", {"heu": heu, "apfel": apfel, "karotte": karotten}
	)
	(_aktion_buttons["heu"] as Button).disabled = heu <= 0
	(_aktion_buttons["apfel"] as Button).disabled = apfel <= 0
	(_aktion_buttons["karotte"] as Button).disabled = karotten <= 0
	_refresh_gear_row()
	_gear_anwenden()


## Ausrüstungs-Zeile: pro Slot ein Menü-Knopf mit den GEKAUFTEN Farben.
func _refresh_gear_row() -> void:
	for kind in _gear_row.get_children():
		kind.queue_free()
	var gs := game_state()
	var owned: Array = []
	if gs != null:
		var raw: Variant = gs.get_value("ranch.wirtschaft.gear.owned", [])
		owned = raw if raw is Array else []
	var ausr: Variant = _pferd().get("ausruestung")
	for slot: String in RanchWirtschaft.GEAR_SLOTS:
		var btn := MenuButton.new()
		var aktuell: Variant = (ausr as Dictionary).get(slot) if ausr is Dictionary else null
		btn.text = (
			"%s: %s"
			% [
				I18nService.t("ranchplay.gear.%s" % slot),
				(
					I18nService.t("ranchplay.gearfarbe.%s" % aktuell)
					if aktuell is String
					else I18nService.t("ranchplay.gear.ohne")
				),
			]
		)
		btn.custom_minimum_size = Vector2(120, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var popup := btn.get_popup()
		popup.add_item(I18nService.t("ranchplay.gear.ohne"), 0)
		var farben: Array = []
		for id: Variant in owned:
			if str(id).begins_with("%s_" % slot):
				farben.append(str(id).trim_prefix("%s_" % slot))
		for i in farben.size():
			popup.add_item(I18nService.t("ranchplay.gearfarbe.%s" % farben[i]), i + 1)
		popup.id_pressed.connect(
			func(id: int) -> void: _gear_waehlen(slot, null if id == 0 else farben[id - 1])
		)
		_gear_row.add_child(btn)


func _gear_waehlen(slot: String, farbe: Variant) -> void:
	var gs := game_state()
	if gs == null:
		return
	var wirtschaft: Variant = gs.get_value("ranch.wirtschaft", {})
	if not (wirtschaft is Dictionary):
		return
	var ergebnis := RanchWirtschaft.gear_anlegen(wirtschaft, pferd_id, slot, farbe)
	if not bool(ergebnis["ok"]):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var ranch: Dictionary = state["ranch"]
			ranch["wirtschaft"] = ergebnis["wirtschaft"]
			var pferd: Variant = ranch["tiere"]["pferde"].get(pferd_id)
			if pferd is Dictionary:
				(pferd as Dictionary)["ausruestung"][slot] = farbe
	)
	gs.notify_slice_changed("ranch")
	AudioDirector.try_play(self, "ui_confirm")
	refresh()


## ---------------------------------------------------------------- Aktionen


func _on_aktion(aktion: String) -> void:
	match aktion:
		"heu", "apfel", "karotte":
			_fuettern(aktion)
		"traenken":
			_pflege_aktion("traenken", Care.traenken(_werte()), "mg_spill")
		"striegeln":
			_pflege_aktion("striegeln", Care.striegeln(_werte()), "ui_chip")
		"ausmisten":
			_ausmisten()


func _werte() -> Dictionary:
	var pferd := _pferd()
	return pferd.get("werte") if pferd.get("werte") is Dictionary else Care.clamp_werte({})


func _fuettern(futter: String) -> void:
	var gs := game_state()
	if gs == null:
		return
	if futter == "karotte":
		var inventar: Variant = gs.get_value("inventory.food", {})
		if not (inventar is Dictionary) or not RanchWirtschaft.karotte_verfuegbar(inventar):
			return
		gs.update(
			func(state: Dictionary) -> void:
				var food: Dictionary = state["inventory"]["food"]
				food["carrot"] = maxi(0, int(food.get("carrot", 0)) - 1)
		)
	else:
		var wirtschaft: Variant = gs.get_value("ranch.wirtschaft", {})
		if not (wirtschaft is Dictionary):
			return
		var entnahme := RanchWirtschaft.futter_nehmen(wirtschaft, futter)
		if not bool(entnahme["ok"]):
			return
		gs.update(
			func(state: Dictionary) -> void: state["ranch"]["wirtschaft"] = entnahme["wirtschaft"]
		)
	# SFX aus dem SfxMap-Bestand (eigene ranch_*-Ids bei W4-P1 angefragt).
	_pflege_aktion(futter, Care.fuettern(_werte(), futter), "gvz_collect")


## Gemeinsame Buchung aller Pflege-Aktionen: Werte + Bindung (Tagesdeckel)
## + letztePflegeAt, dann Feedback (Sound + Puls + Textblitz).
func _pflege_aktion(aktion: String, neue_werte: Dictionary, sound: String) -> void:
	var gs := game_state()
	if gs == null:
		return
	var pferd := _pferd()
	if pferd.is_empty():
		return
	var heute := _local_day()
	var bond := Care.bond_nach_aktion(
		float(pferd.get("bindung", 0.0)),
		float(pferd.get("bondHeute", 0.0)),
		aktion,
		str(pferd.get("bondTag", "")) != heute
	)
	var jetzt := _now_ms()
	gs.update(
		func(state: Dictionary) -> void:
			var ziel: Variant = state["ranch"]["tiere"]["pferde"].get(pferd_id)
			if not (ziel is Dictionary):
				return
			var p: Dictionary = ziel
			p["werte"] = neue_werte
			p["bindung"] = bond["bindung"]
			p["bondHeute"] = bond["bondHeute"]
			p["bondTag"] = heute
			p["letztePflegeAt"] = jetzt
	)
	gs.notify_slice_changed("ranch")
	AudioDirector.try_play(self, sound)
	if float(bond["gewinn"]) > 0.0:
		_zeige_feedback(
			I18nService.t("ranchplay.pflege.bindung_plus", {"n": "%.0f" % float(bond["gewinn"])})
		)
	else:
		_zeige_feedback(I18nService.t("ranchplay.pflege.gemacht"))
	_puls_pferd()
	refresh()


func _ausmisten() -> void:
	var gs := game_state()
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			state["ranch"]["tiere"]["stall"]["sauberkeit"] = Care.ausmisten()
	)
	gs.notify_slice_changed("ranch")
	# Ausmisten pflegt das AKTUELLE Pferd mit (Bindung, letztePflegeAt).
	_pflege_aktion("ausmisten", _werte(), "gvz_shovel")


func _zeige_feedback(text: String) -> void:
	_feedback.text = text
	_feedback_t = 1.2
	_feedback.modulate.a = 1.0


## Kleiner Freude-Puls der Vorschau (Belohnungsmoment).
func _puls_pferd() -> void:
	if _pferd_node == null:
		return
	var tween := create_tween()
	tween.tween_property(_pferd_node, "scale", Vector3.ONE * 1.07, 0.09)
	tween.tween_property(_pferd_node, "scale", Vector3.ONE, 0.22)
	AudioDirector.try_play(self, "gvz_pop", 0.9 + randf_range(-0.05, 0.05))


## ------------------------------------------------------------------ Layout


func _on_resized() -> void:
	if _split != null:
		_split.vertical = size.y > size.x


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _local_day() -> String:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return str(gs.clock.local_day())
	var datum := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [datum["year"], datum["month"], datum["day"]]
