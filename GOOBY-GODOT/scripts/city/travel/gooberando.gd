class_name GooberandoApp
extends VBoxContainer
## GOOBERANDO-App (W3a CITY, Doc E §5, M1-Kern): „Erstmal Goobyn.“ —
## App-Sheet mit Logo + 3 Gerichten aus dem REHWEI-Sortiment, Bestellung →
## realer 2–5-min-Timer (Dev-Key `debug.gooberando_prep_s`) → Türklingel +
## oranger Liefer-Gooby (W1b-Rig, #FF7A00) + Übergabe + Trinkgeld-Option
## (5 Münzen, 30 % Chance auf 2-h-Energie-Buff; „Trinkgeld schadet nie ;)“
## nach 3× keins). Essen landet im Inventar (GameState).
##
## HUD-Anbindung (Orchestrator): `hud.action_pressed` mit &"igohbie" →
## `GooberandoApp.oeffne(szene, game_state)`.

signal bestellt(gericht_id: String)
signal geliefert(gericht_id: String)

const Economy := preload("res://scripts/logic/economy.gd")
const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")
const LOGO := "res://assets/brand/gooberando.png"
const KLINGEL := "res://assets/city/audio/bong_001.ogg"
const ORANGE := Color("#FF7A00")

var gs: Object
var sheet: PanelSheet

var _box: VBoxContainer
var _tick_akku := 0.0


## GOOBERANDO-Sheet öffnen (Host = beliebige Szene; eigener CanvasLayer).
static func oeffne(host: Node, game_state: Object) -> GooberandoApp:
	var layer := CanvasLayer.new()
	layer.name = "GooberandoLayer"
	host.add_child(layer)
	var app := GooberandoApp.new()
	app.gs = game_state
	app.sheet = PanelSheetScene.instantiate()
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	app.sheet.theme = ThemeService.theme()
	layer.add_child(app.sheet)
	app.sheet.set_title("")
	app.sheet.add_content(app)
	app.sheet.closed.connect(func() -> void: layer.queue_free())
	# open() ERST nach dem ersten Layout-Pass: die Einfeder-Animation liest
	# position.y — im Instanzierungs-Frame ist der Rect noch nicht gelegt und
	# die Offsets verkanten (Sheet wird schirmhoch).
	app.sheet.open.call_deferred()
	return app


## HUD-Aktions-Handler (Orchestrator verdrahtet: action &"igohbie").
static func handle_hud_action(action: StringName, host: Node, game_state: Object) -> bool:
	if action != &"igohbie":
		return false
	oeffne(host, game_state)
	return true


func _ready() -> void:
	# Root = VBoxContainer (min-Höhe propagiert zum PanelSheet); _box = self.
	custom_minimum_size = Vector2(420.0, 0.0)
	add_theme_constant_override("separation", 10)
	_box = self
	_render()


func _process(delta: float) -> void:
	_tick_akku += delta
	if _tick_akku < 1.0:
		return
	_tick_akku = 0.0
	_tick()


func now_ms() -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## Dev-Harness: Lieferzeit via `debug.gooberando_prep_s` verkürzbar.
func prep_s() -> int:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null:
		var debug := int(settings.get_setting("debug.gooberando_prep_s", 0))
		if debug > 0:
			return debug
	return randi_range(GooberandoLogic.PREP_MIN_S, GooberandoLogic.PREP_MAX_S)


func _tick() -> void:
	if gs == null:
		return
	var res := GooberandoLogic.tick(CityState.gooberando_slice(gs), now_ms())
	var events: Array = res["events"]
	if events.is_empty():
		if GooberandoLogic.liefer_rest_s(res["slice"], now_ms()) > 0:
			_render()
		return
	CityState.save_gooberando_slice(gs, res["slice"])
	for ereignis: Dictionary in events:
		match str(ereignis["typ"]):
			"vor_der_tuer":
				_klingel()
				_render()
			"abgestellt":
				_gib_essen(str(ereignis["gerichtId"]))
				_zeige_toast(I18nService.t("travel.gooberando.abgestellt"))
				_render()


## ---------------------------------------------------------------- Views


func _render() -> void:
	for kind in _box.get_children():
		kind.queue_free()
	if gs == null:
		return
	_logo()
	var slice := CityState.gooberando_slice(gs)
	match str(slice["state"]):
		GooberandoLogic.STATE_BESTELLT:
			_render_countdown(slice)
		GooberandoLogic.STATE_VOR_DER_TUER:
			_render_vor_der_tuer()
		GooberandoLogic.STATE_TRINKGELD:
			_render_trinkgeld()
		_:
			_render_menue()


func _logo() -> void:
	if not ResourceLoader.exists(LOGO):
		return
	var bild := TextureRect.new()
	bild.texture = load(LOGO)
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bild.custom_minimum_size = Vector2(0.0, 110.0)
	_box.add_child(bild)
	var slogan := Label.new()
	slogan.text = I18nService.t("travel.gooberando.slogan")
	slogan.theme_type_variation = "CaptionLabel"
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(slogan)


func _render_menue() -> void:
	var coins := int(gs.get_value("economy.coins", 0))
	_label(
		I18nService.t("travel.gooberando.gebuehr").format(
			{"gebuehr": GooberandoLogic.LIEFERGEBUEHR}
		)
	)
	for gericht: Dictionary in CitySortiment.gooberando_gerichte():
		var preis := int(gericht.get("preis", 0)) + GooberandoLogic.LIEFERGEBUEHR
		var btn := Button.new()
		btn.theme_type_variation = "AccentButton"
		btn.text = "%s — %d ᴳ" % [str(gericht.get("name_de", "?")), preis]
		btn.disabled = coins < preis
		btn.pressed.connect(_on_bestellen.bind(gericht))
		_box.add_child(btn)


func _render_countdown(slice: Dictionary) -> void:
	var rest := GooberandoLogic.liefer_rest_s(slice, now_ms())
	_label(I18nService.t("travel.gooberando.unterwegs"))
	_label(
		I18nService.t("travel.gooberando.countdown").format(
			{"min": rest / 60, "s": "%02d" % (rest % 60)}
		)
	)


func _render_vor_der_tuer() -> void:
	_liefer_gooby()
	_label(I18nService.t("travel.gooberando.klingel"))
	var btn := Button.new()
	btn.theme_type_variation = "PrimaryButton"
	btn.text = I18nService.t("travel.gooberando.annehmen")
	btn.pressed.connect(_on_uebergabe)
	_box.add_child(btn)


func _render_trinkgeld() -> void:
	_liefer_gooby()
	_label(I18nService.t("travel.gooberando.uebergeben"))
	var geben := Button.new()
	geben.theme_type_variation = "PrimaryButton"
	geben.text = I18nService.t("travel.gooberando.trinkgeld_geben")
	geben.pressed.connect(_on_trinkgeld.bind(true))
	_box.add_child(geben)
	var winken := Button.new()
	winken.theme_type_variation = "GhostButton"
	winken.text = I18nService.t("travel.gooberando.nur_winken")
	winken.pressed.connect(_on_trinkgeld.bind(false))
	_box.add_child(winken)


## Oranger Liefer-Gooby (W1b-Rig, Fell-Tint #FF7A00) im SubViewport-Porträt.
func _liefer_gooby() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(0.0, 220.0)
	# Container ZUERST in den Tree: GoobyRig lädt sein GLB erst in _ready —
	# vorher findet der Tint-Loop keine MeshInstances.
	_box.add_child(container)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = Vector2i(380, 220)
	container.add_child(viewport)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-40.0, -25.0, 0.0)
	viewport.add_child(licht)
	var rig := GoobyRig.new()
	viewport.add_child(rig)
	rig.set_emotion("happy")
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(ORANGE, 0.6)
				mi.set_surface_override_material(i, kopie)
	var kamera := Camera3D.new()
	# Nah ran: Porträt-Framing — bei 2,6 m wirkt der Liefer-Gooby verloren.
	kamera.position = Vector3(0.0, 0.75, 1.5)
	kamera.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	viewport.add_child(kamera)


## --------------------------------------------------------------- Actions


func _on_bestellen(gericht: Dictionary) -> void:
	var res := GooberandoLogic.bestellen(
		CityState.gooberando_slice(gs), now_ms(), prep_s(), gericht
	)
	if not bool(res["ok"]):
		return
	var bezahlt := false
	gs.update(
		func(state: Dictionary) -> void:
			bezahlt = Economy.spend(state["economy"], int(res["kosten"]), "gooberando")
	)
	if not bezahlt:
		return
	CityState.save_gooberando_slice(gs, res["slice"])
	for notif: Dictionary in res["notifications"]:
		ReiseApp.notifs.plane(
			str(notif["id"]), I18nService.t(str(notif["text_key"])), int(notif["at_ms"])
		)
	bestellt.emit(str(gericht.get("id", "")))
	_zeige_toast(I18nService.t("travel.gooberando.bestellt"))
	_render()


func _on_uebergabe() -> void:
	var res := GooberandoLogic.uebergabe(CityState.gooberando_slice(gs), now_ms())
	if not bool(res["ok"]):
		_render()
		return
	CityState.save_gooberando_slice(gs, res["slice"])
	_gib_essen(str(res["gerichtId"]))
	geliefert.emit(str(res["gerichtId"]))
	_render()


func _on_trinkgeld(geben: bool) -> void:
	var res := GooberandoLogic.trinkgeld(CityState.gooberando_slice(gs), now_ms(), geben, randf())
	if geben:
		gs.update(
			func(state: Dictionary) -> void:
				Economy.spend(state["economy"], int(res["kosten"]), "trinkgeld")
		)
	CityState.save_gooberando_slice(gs, res["slice"])
	if bool(res["buff"]):
		_zeige_toast(I18nService.t("travel.gooberando.buff"))
	elif bool(res["hinweis"]):
		_zeige_toast(I18nService.t("travel.gooberando.trinkgeld_hinweis"))
	_render()


func _gib_essen(gericht_id: String) -> void:
	if gericht_id.is_empty():
		return
	gs.update(
		func(state: Dictionary) -> void:
			var food: Dictionary = state["inventory"]["food"]
			food[gericht_id] = int(food.get(gericht_id, 0)) + 1
	)


func _klingel() -> void:
	if not ResourceLoader.exists(KLINGEL):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(KLINGEL)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Start-Breite VOR add_child setzen: Autowrap rechnet die Min-Höhe an der
	# AKTUELLEN Breite — bei 0 explodiert sie (1 Zeichen/Zeile) und das Sheet
	# wächst per grow_vertical schirmhoch und schrumpft nie zurück.
	label.custom_minimum_size = Vector2(380.0, 0.0)
	label.size = Vector2(380.0, 0.0)
	_box.add_child(label)


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
