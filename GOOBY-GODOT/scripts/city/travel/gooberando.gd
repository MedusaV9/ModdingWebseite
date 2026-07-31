class_name GooberandoApp
extends VBoxContainer
## GOOBERANDO-App (W3a CITY + W13B-Vollausbau, Doc E §5): „Erstmal Goobyn.“ —
## App-Sheet mit Logo, Restaurant-Wahl (3 Lieferküchen aus
## `data/gooberando_restaurants.json`), Menü mit kleinem Warenkorb,
## Bestellung → deterministische Fahrer-Sim auf dem road_graph
## (delivery/fahrer_sim.gd) mit Live-Karte (Minimap-Baustein + Fahrer-Punkt)
## → Türklingel + oranger Liefer-Gooby (W1b-Rig, #FF7A00) + Übergabe +
## Trinkgeld-Option (5 Münzen, 30 % Chance auf 2-h-Energie-Buff; „Trinkgeld
## schadet nie ;)“ nach 3× keins). Essen landet als FoodCatalog-Ids im
## Inventar (GameState).
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
## Kleiner Warenkorb (Doc E §5.1): mehr trägt der Liefer-Gooby nicht.
const MAX_KORB := 5

var gs: Object
var sheet: PanelSheet

var _box: VBoxContainer
var _tick_akku := 0.0
var _restaurant := ""
var _warenkorb: Array = []
var _karte: CityMap
var _graph: CityRoadGraph
var _route := PackedVector3Array()
var _route_fuer := "?"


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


## Gesamt-Lieferzeit (s) einer Bestellung: Küchen-Wartezeit des Restaurants
## + Fahrzeit der road_graph-Route. Dev-Harness: `debug.gooberando_prep_s`
## überschreibt die Gesamtzeit.
func prep_s(restaurant_id: String) -> int:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null:
		var debug := int(settings.get_setting("debug.gooberando_prep_s", 0))
		if debug > 0:
			return debug
	var restaurant := GooberandoRestaurants.restaurant(restaurant_id)
	var kueche := randi_range(
		int(restaurant.get("prep_min_s", GooberandoLogic.PREP_MIN_S)),
		int(restaurant.get("prep_max_s", GooberandoLogic.PREP_MAX_S))
	)
	return kueche + int(ceilf(GooberandoFahrerSim.fahrzeit_s(_route_zu(restaurant_id))))


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
				for id: Variant in ereignis.get("gerichte", [ereignis["gerichtId"]]):
					_gib_essen(str(id))
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
			if _restaurant.is_empty():
				_render_restaurants()
			else:
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


## Restaurant-Wahl (W13B, Doc E §5.1): Name, Bewertungs-Gag, Wartezeit.
func _render_restaurants() -> void:
	_label(I18nService.t("phone.gooberando.restaurants_titel"))
	for restaurant: Dictionary in GooberandoRestaurants.alle():
		var btn := Button.new()
		btn.theme_type_variation = "AccentButton"
		btn.text = str(restaurant.get("name_de", "?"))
		btn.pressed.connect(_on_restaurant.bind(str(restaurant.get("id", ""))))
		_box.add_child(btn)
		_caption(
			(
				I18nService
				. t("phone.gooberando.bewertung")
				. format(
					{
						"sterne": str(restaurant.get("sterne", "5,0")),
						"gag": I18nService.t(str(restaurant.get("gag_key", ""))),
					}
				)
			)
		)
		_caption(
			(
				I18nService
				. t("phone.gooberando.wartezeit")
				. format(
					{
						"min": int(restaurant.get("prep_min_s", 120)) / 60,
						"max": int(ceilf(float(restaurant.get("prep_max_s", 300)) / 60.0)),
					}
				)
			)
		)


## Menü + kleiner Warenkorb des gewählten Restaurants.
func _render_menue() -> void:
	var restaurant := GooberandoRestaurants.restaurant(_restaurant)
	_label(str(restaurant.get("name_de", "?")))
	_caption(
		I18nService.t("travel.gooberando.gebuehr").format(
			{"gebuehr": GooberandoLogic.LIEFERGEBUEHR}
		)
	)
	for gericht: Dictionary in restaurant.get("gerichte", []):
		var btn := Button.new()
		btn.theme_type_variation = "AccentButton"
		btn.text = "%s — %d ᴳ" % [str(gericht.get("name_de", "?")), int(gericht.get("preis", 0))]
		btn.disabled = _warenkorb.size() >= MAX_KORB
		btn.pressed.connect(_on_in_den_korb.bind(gericht))
		_box.add_child(btn)
	var summe := _korb_summe()
	if _warenkorb.is_empty():
		_caption(I18nService.t("phone.gooberando.warenkorb_leer"))
	else:
		_label(
			(
				I18nService
				. t("phone.gooberando.warenkorb")
				. format(
					{
						"n": _warenkorb.size(),
						"summe": summe,
						"gebuehr": GooberandoLogic.LIEFERGEBUEHR,
					}
				)
			)
		)
	var coins := int(gs.get_value("economy.coins", 0))
	var kaufen := Button.new()
	kaufen.theme_type_variation = "PrimaryButton"
	kaufen.text = I18nService.t("phone.gooberando.bestellen").format({"summe": summe})
	kaufen.disabled = _warenkorb.is_empty() or coins < summe
	kaufen.pressed.connect(_on_bestellen)
	_box.add_child(kaufen)
	if not _warenkorb.is_empty():
		var leeren := Button.new()
		leeren.theme_type_variation = "GhostButton"
		leeren.text = I18nService.t("phone.gooberando.warenkorb_leeren")
		leeren.pressed.connect(_on_korb_leeren)
		_box.add_child(leeren)
	var zurueck := Button.new()
	zurueck.theme_type_variation = "GhostButton"
	zurueck.text = I18nService.t("phone.gooberando.menue_zurueck")
	zurueck.pressed.connect(_on_zurueck_zu_restaurants)
	_box.add_child(zurueck)


## Countdown + Live-Karte (W13B, Doc E §5.2): der orange Fahrer-Punkt
## wandert deterministisch die road_graph-Route entlang.
func _render_countdown(slice: Dictionary) -> void:
	var rest := GooberandoLogic.liefer_rest_s(slice, now_ms())
	var route := _route_zu(str(slice["restaurantId"]))
	var stat := GooberandoFahrerSim.status(
		route, int(slice["bestelltAt"]), int(slice["fertigAt"]), now_ms()
	)
	if str(stat["phase"]) == GooberandoFahrerSim.PHASE_KUECHE:
		_label(I18nService.t("phone.gooberando.fahrer_kueche"))
	else:
		_label(I18nService.t("phone.gooberando.fahrer_unterwegs"))
	_label(
		I18nService.t("travel.gooberando.countdown").format(
			{"min": rest / 60, "s": "%02d" % (rest % 60)}
		)
	)
	if not route.is_empty():
		var center := CenterContainer.new()
		_box.add_child(center)
		var mini := CityMinimap.new()
		mini.karte = _stadt_karte()
		center.add_child(mini)
		var overlay := FahrerKarteOverlay.new()
		overlay.mini = mini
		overlay.route = route
		overlay.fahrer = stat["punkt"]
		overlay.farbe = ORANGE
		center.add_child(overlay)
		_caption(I18nService.t("phone.gooberando.karte_hinweis"))


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
	# KEINE manuelle size: der Stretch-Container übernimmt die Größe (REST5).
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


func _on_restaurant(restaurant_id: String) -> void:
	_restaurant = restaurant_id
	_warenkorb = []
	_render()


func _on_zurueck_zu_restaurants() -> void:
	_restaurant = ""
	_warenkorb = []
	_render()


func _on_in_den_korb(gericht: Dictionary) -> void:
	if _warenkorb.size() >= MAX_KORB:
		return
	_warenkorb.append(gericht)
	_render()


func _on_korb_leeren() -> void:
	_warenkorb = []
	_render()


func _on_bestellen() -> void:
	var res := GooberandoLogic.bestellen_korb(
		CityState.gooberando_slice(gs), now_ms(), prep_s(_restaurant), _warenkorb, _restaurant
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
	bestellt.emit(str(res["slice"]["gerichtId"]))
	_warenkorb = []
	_zeige_toast(I18nService.t("travel.gooberando.bestellt"))
	_render()


func _on_uebergabe() -> void:
	var res := GooberandoLogic.uebergabe(CityState.gooberando_slice(gs), now_ms())
	if not bool(res["ok"]):
		_render()
		return
	CityState.save_gooberando_slice(gs, res["slice"])
	for id: Variant in res["gerichte"]:
		_gib_essen(str(id))
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


## ---------------------------------------------------------------- Helfer


func _gib_essen(gericht_id: String) -> void:
	if gericht_id.is_empty():
		return
	gs.update(
		func(state: Dictionary) -> void:
			var food: Dictionary = state["inventory"]["food"]
			food[gericht_id] = int(food.get(gericht_id, 0)) + 1
	)


func _korb_summe() -> int:
	var summe := GooberandoLogic.LIEFERGEBUEHR
	for gericht: Dictionary in _warenkorb:
		summe += int(gericht.get("preis", 0))
	return summe


func _stadt_karte() -> CityMap:
	if _karte == null:
		_karte = CityMap.laden()
	return _karte


func _stadt_graph() -> CityRoadGraph:
	if _graph == null:
		_graph = CityRoadGraph.aus_karte(_stadt_karte())
	return _graph


## Route Restaurant → Haus (gecacht pro Restaurant). Unbekanntes Restaurant
## (Alt-Bestellung) startet an der GOOBERANDO-Küche der Karte.
func _route_zu(restaurant_id: String) -> PackedVector3Array:
	if _route_fuer == restaurant_id:
		return _route
	var karte := _stadt_karte()
	var start := GooberandoRestaurants.strasse_tile(restaurant_id)
	if start.x < 0:
		var kueche: Dictionary = karte.daten.get("gooberando_kueche", {})
		var roh: Variant = kueche.get("strasse", [5, 6])
		start = Vector2i(int(roh[0]), int(roh[1]))
	_route = GooberandoFahrerSim.route_welt(karte, _stadt_graph(), start, karte.zuhause_tile())
	_route_fuer = restaurant_id
	return _route


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


func _caption(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "CaptionLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(380.0, 0.0)
	label.size = Vector2(380.0, 0.0)
	_box.add_child(label)


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)


## Fahrer-Overlay über der Minimap: Route (blass) + oranger Fahrer-Punkt.
## Eigenes Control statt `draw`-Signal, damit es sicher ÜBER der Karte liegt.
class FahrerKarteOverlay:
	extends Control

	var mini: CityMinimap
	var route := PackedVector3Array()
	var fahrer := Vector3.ZERO
	var farbe := Color("#FF7A00")

	func _ready() -> void:
		custom_minimum_size = Vector2(CityMinimap.GROESSE, CityMinimap.GROESSE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if mini == null:
			return
		if route.size() >= 2:
			var px := PackedVector2Array()
			for punkt in route:
				px.append(mini.welt_zu_pixel(punkt))
			draw_polyline(px, Color(farbe, 0.45), 2.0)
		var mitte := mini.welt_zu_pixel(fahrer)
		draw_circle(mitte, 6.5, AcTokens.PAPER)
		draw_circle(mitte, 5.0, farbe)
