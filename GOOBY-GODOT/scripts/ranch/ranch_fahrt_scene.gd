class_name RanchFahrtScene
extends Node3D
## Überlandfahrt Stadt → Gooby Ranch (RANCH-1): eine ECHTE kurze
## Fahr-Strecke (kein Ladebildschirm) mit dem vorhandenen CarController —
## Landstraße mit Feldern, Weiden, Heuballen, Zäunen, Windrad, Bachbrücke
## und Kühen/Schafen. Am Ende wartet das Ranch-Tor: vor dem Kauf öffnet
## dort das Kauf-Sheet (Preis in ᴳ, „Kaufen“/„Später kaufen“), nach dem
## Kauf geht es direkt auf den Hof.
##
## Router-Contract (W1a): `ready_for_reveal` nach dem Aufbau. Tests
## injizieren `game_state_override` VOR add_child (Muster CityScene).

signal ready_for_reveal
signal tor_erreicht

const TOR_ZONE_M := 20.0

var game_state_override: Object
## Tests/Screenshots erzwingen eine Uhrzeit (< 0 = echte Systemzeit).
var stunde_override := -1.0

var plan: Dictionary = {}
var auto: CarController
var cam: ChaseCam
var hud: RanchDriveHud
## Das offene Tor-Kauf-Sheet (null = zu) — Tests greifen es hierüber ab.
var tor_sheet: Control

var _bau: RanchBau
var _windrad_rotor: Node3D
var _tor_gemeldet := false
var _toast: Node


func _ready() -> void:
	plan = RanchWelt.fahrt_plan()
	_bau = RanchBau.new(self)
	var profil := _bau.baue_licht(_stunde())
	_baue_welt()
	_baue_auto(bool(profil["lichter_an"]))
	_baue_hud()
	ready_for_reveal.emit()


func _process(delta: float) -> void:
	if _windrad_rotor != null:
		_windrad_rotor.rotation.z += delta * 0.9


func _physics_process(_delta: float) -> void:
	_pruefe_tor()


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## ---------------------------------------------------------------- Aufbau


func _stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


func _baue_welt() -> void:
	var laenge := float(plan["laenge"])
	_bau.baue_boden(260.0, laenge + 60.0)
	_bau.baue_strasse(laenge, float(plan["strasse_breite"]))
	var felder := Node3D.new()
	felder.name = "Felder"
	add_child(felder)
	var korn_plaetze: Array = []
	for feld: Dictionary in plan["felder"]:
		_bau.baue_feld(felder, feld["pos"], feld["groesse"], feld["farbe"])
		if bool(feld["korn"]):
			_sammle_korn(korn_plaetze, feld)
	_bau.baue_multimesh(
		self,
		"%s/natur/crops_cornStageD.glb" % RanchBau.ASSETS,
		korn_plaetze,
		"",
		RanchBau.KLEINTEIL_SICHT_M
	)
	_baue_zaeune()
	_baue_heuballen()
	_baue_baeume()
	_windrad_rotor = _bau.baue_windrad(plan["windrad_pos"])
	_bau.baue_bach(float(plan["bach_z"]), 240.0)
	_bau.baue_tor(
		Vector3(0.0, 0.0, float(plan["tor_z"])), I18nService.t("ranch.fahrt.schild_ranch")
	)
	_bau.baue_schild(
		plan["start_schild_pos"],
		I18nService.t("ranch.exit.schild_zeile1"),
		I18nService.t("ranch.exit.schild_zeile2", {"km": plan["schild_km"]})
	)
	_baue_weidetiere()


func _sammle_korn(korn_plaetze: Array, feld: Dictionary) -> void:
	var pos: Vector3 = feld["pos"]
	var groesse: Vector2 = feld["groesse"]
	var reihen := int(groesse.y / 7.0)
	var spalten := int(groesse.x / 7.0)
	for r in reihen:
		for c in spalten:
			var basis := Basis.IDENTITY.scaled(Vector3.ONE * 3.0)
			korn_plaetze.append(
				Transform3D(
					basis,
					Vector3(
						pos.x - groesse.x / 2.0 + 4.0 + float(c) * 7.0,
						0.0,
						pos.z - groesse.y / 2.0 + 4.0 + float(r) * 7.0
					)
				)
			)


func _baue_zaeune() -> void:
	var latten: Array = []
	for bereich: Vector2 in plan["zaun_z_bereiche"]:
		var z := bereich.x
		while z < bereich.y:
			for seite: float in [-1.0, 1.0]:
				var basis := Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * 2.6)
				latten.append(Transform3D(basis, Vector3(seite * 7.6, 0.0, z)))
			z += 2.6
	_bau.baue_multimesh(self, "%s/natur/fence_simple.glb" % RanchBau.ASSETS, latten)


func _baue_heuballen() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Heuballen"
	add_child(wurzel)
	for pos: Vector3 in plan["heuballen"]:
		_bau.baue_heuballen(wurzel, pos)


func _baue_baeume() -> void:
	var baeume: Array = []
	var i := 0
	for pos: Vector3 in plan["baeume"]:
		var basis := Basis(Vector3.UP, float(i) * 1.3).scaled(Vector3.ONE * 9.0)
		baeume.append(Transform3D(basis, pos))
		i += 1
	_bau.baue_multimesh(self, "%s/natur/tree_default.glb" % RanchBau.ASSETS, baeume)


func _baue_weidetiere() -> void:
	for pos: Vector3 in plan["kuehe"]:
		var kuh := RanchTier.neu("kuh", Color("#F5EFE4"), Color("#7A5C43"))
		kuh.position = pos
		kuh.rotation.y = pos.x
		add_child(kuh)
	for pos: Vector3 in plan["schafe"]:
		var schaf := RanchTier.neu("schaf", Color("#F7F3EA"))
		schaf.position = pos
		schaf.rotation.y = pos.z
		add_child(schaf)


func _baue_auto(licht_an: bool) -> void:
	auto = CarController.new()
	auto.name = "SpielerAuto"
	auto.welt_halb = Vector2(120.0, float(plan["laenge"]) / 2.0 + 20.0)
	auto.licht_an = licht_an
	add_child(auto)
	auto.colliders = _bau.colliders
	auto.teleport(-CityCarFeel.LANE_OFFSET_M, float(plan["spawn_z"]), 0.0)
	cam = ChaseCam.new()
	cam.name = "ChaseCam"
	cam.ziel = auto
	cam.current = true
	add_child(cam)
	cam.snap()


func _baue_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = RanchDriveHud.new()
	hud.name = "RanchDriveHud"
	# Theme explizit: Window-Theme propagiert NICHT durch CanvasLayer.
	hud.theme = ThemeService.theme()
	layer.add_child(hud)
	hud.steer_changed.connect(func(v: float) -> void: auto.set_steer(v))
	hud.brake_changed.connect(func(on: bool) -> void: auto.set_brake(on))
	hud.zur_stadt_pressed.connect(_on_zur_stadt)
	hud.prompt_pressed.connect(_on_tor_aktion)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Tastatur (Desktop-Dev): Pfeile lenken/bremsen wie in der Stadt.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or auto == null:
		return
	var taste: InputEventKey = event
	match taste.keycode:
		KEY_LEFT:
			auto.set_steer(-1.0 if taste.pressed else 0.0)
		KEY_RIGHT:
			auto.set_steer(1.0 if taste.pressed else 0.0)
		KEY_DOWN, KEY_SPACE:
			auto.set_brake(taste.pressed)
		KEY_R:
			auto.set_reverse(taste.pressed)


## ------------------------------------------------------------- Tor-Logik


func _pruefe_tor() -> void:
	if auto == null or hud == null:
		return
	var abstand := float(plan["tor_z"]) - auto.position.z
	if abstand > TOR_ZONE_M:
		if _tor_gemeldet and abstand > TOR_ZONE_M + 6.0:
			_tor_gemeldet = false
			hud.verstecke_prompt()
		return
	if _tor_gemeldet:
		return
	_tor_gemeldet = true
	tor_erreicht.emit()
	var gs := game_state()
	if RanchState.ist_gekauft(gs):
		hud.zeige_prompt(I18nService.t("ranch.hof.willkommen"), I18nService.t("ranch.tor.offen"))
	else:
		hud.zeige_prompt(
			I18nService.t("ranch.fahrt.angekommen"),
			I18nService.t("ranch.tor.kaufen", {"preis": RanchKatalog.preis()})
		)


## Prompt-Knopf am Tor: rein (gekauft) oder Kauf-Sheet öffnen.
func _on_tor_aktion() -> void:
	var gs := game_state()
	if RanchState.ist_gekauft(gs):
		_betrete_hof()
	else:
		_zeige_tor_sheet(gs)


func _zeige_tor_sheet(gs: Object) -> void:
	if tor_sheet != null and is_instance_valid(tor_sheet):
		return
	if auto != null:
		auto.set_frozen(true)
	var sheet: PanelSheet = load("res://scripts/ui/panel_sheet.tscn").instantiate()
	sheet.theme = ThemeService.theme()
	var layer: CanvasLayer = get_node("HudLayer")
	layer.add_child(sheet)
	sheet.set_title(I18nService.t("ranch.tor.titel"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var text := Label.new()
	text.text = I18nService.t("ranch.tor.text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var knoepfe := HBoxContainer.new()
	knoepfe.add_theme_constant_override("separation", 12)
	knoepfe.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(knoepfe)
	var kaufen := Button.new()
	kaufen.theme_type_variation = "PrimaryButton"
	kaufen.text = I18nService.t("ranch.tor.kaufen", {"preis": RanchKatalog.preis()})
	kaufen.pressed.connect(func() -> void: _on_kaufen(gs))
	knoepfe.add_child(kaufen)
	var spaeter := Button.new()
	spaeter.theme_type_variation = "GhostButton"
	spaeter.text = I18nService.t("ranch.tor.spaeter")
	spaeter.pressed.connect(_on_spaeter)
	knoepfe.add_child(spaeter)
	sheet.set_meta(RanchOffer.META_JETZT, kaufen)
	sheet.set_meta(RanchOffer.META_SPAETER, spaeter)
	sheet.add_content(box)
	sheet.closed.connect(
		func() -> void:
			if auto != null:
				auto.set_frozen(false)
	)
	sheet.open()
	tor_sheet = sheet


func _on_kaufen(gs: Object) -> void:
	var ergebnis := RanchKauf.kaufe(gs)
	if ergebnis == RanchKauf.RESULT_OK:
		_schliesse_tor_sheet()
		_zeige_toast(I18nService.t("ranch.tor.gekauft"))
		_betrete_hof()
	elif ergebnis == RanchKauf.RESULT_BROKE:
		var fehlt := RanchKatalog.preis() - int(gs.get_value("economy.coins", 0))
		_zeige_toast(I18nService.t("ranch.tor.zu_teuer", {"fehlt": maxi(0, fehlt)}))
	else:
		_schliesse_tor_sheet()


## „Später kaufen“ am Tor: Stand merken, Sheet zu — Rückweg bleibt frei.
func _on_spaeter() -> void:
	RanchState.angebot_verschieben(game_state())
	_schliesse_tor_sheet()
	_zeige_toast(I18nService.t("ranch.angebot.gemerkt"))


func _schliesse_tor_sheet() -> void:
	if tor_sheet != null and is_instance_valid(tor_sheet):
		tor_sheet.close()
		tor_sheet.queue_free()
	tor_sheet = null


func _betrete_hof() -> void:
	if not RanchRouten.fahre_zum_hof(get_tree()):
		_zeige_toast("(Route %s — Router fehlt)" % RanchRouten.ROUTE_HOF)


func _on_zur_stadt() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		_zeige_toast("(Route city — Router fehlt)")
		return
	router.goto(&"city", {})


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)
