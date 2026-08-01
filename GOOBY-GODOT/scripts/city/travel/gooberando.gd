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
## G4/P16 (ui-reisen MITTEL 6/7): Restaurants sind EINE tappbare Karte
## (AcCardButton mit Name/Sterne-Gag/Wartezeit) statt Button+losen Captions,
## die Live-Karte skaliert dynamisch (`kante = clamp(breite·0,7, 220, 420)`)
## und alle Aktions-Knöpfe sind SquishButtons ≥ 52·f mit Touch-Floor.
## Sounds nach Audio-Grammatik (Outcome schlägt Press: ui_buy erst NACH
## gelungener Zahlung).
##
## G5/P34 (P18→P16-Request): Die App läuft IM Telefon — die App-Ansicht baut
## auf den PhoneShell-Helfern (`richte_app_box_ein`/`app_label`, Breite =
## reale Geräte-Innenbreite via `PhoneShell.inhalt_breite()`) statt auf dem
## 420er-Sheet-Fallback, der breiter als das 380er-Gerät war (gleiche
## Breiten-Kollision wie InstantGooby vor G4/P18, G1 ui-post §4).
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
## Mindesthöhe der Aktions-Knöpfe / Restaurant-Karten in Design-px.
const KNOPF_HOEHE := 52.0
const KARTE_HOEHE := 64.0
## Untergrenze der Inhaltsbreite (Design-px, Robustheit auf Mini-Canvases).
const MIN_BREITE := 220.0
## Live-Karten-Kante: Anteil der Inhaltsbreite + harte Klemmen (Design-px).
const KARTE_ANTEIL := 0.7
const KARTE_MIN := 220.0
const KARTE_MAX := 420.0

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
	# G5/P34: Breite kommt von den PhoneShell-Helfern (keine Fixbreite mehr).
	PhoneShell.richte_app_box_ein(self)
	_box = self
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_on_viewport_resized)
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


## G5/P34: reale Inhaltsbreite = Geräte-Innenbreite der PhoneShell (die App
## läuft IM Telefon; P18 hat die Helfer genau dafür gebaut). Der alte
## 420er-Sheet-Fallback kollidierte mit dem 380er-Gerät (G1 ui-post §4).
func inhalt_breite() -> float:
	return maxf(PhoneShell.inhalt_breite(), MIN_BREITE)


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


## Rotation/Resize: die aktuelle Ansicht mit frischen Metriken neu bauen
## (die Breite kommt je Baustein aus den PhoneShell-Helfern). Guard: die
## PhoneShell hängt die ALTE Instanz beim Rebuild aus, bevor queue_free
## greift — ohne Tree gibt es keinen Viewport zum Vermessen.
func _on_viewport_resized() -> void:
	if not is_inside_tree():
		return
	_render()


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
	_skaliere_schriften()


func _logo() -> void:
	if not ResourceLoader.exists(LOGO):
		return
	var f := UiScale.for_viewport(get_viewport())
	var bild := TextureRect.new()
	bild.texture = load(LOGO)
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bild.custom_minimum_size = Vector2(0.0, roundf(110.0 * f))
	_box.add_child(bild)
	var slogan := Label.new()
	slogan.text = I18nService.t("travel.gooberando.slogan")
	slogan.theme_type_variation = "CaptionLabel"
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(slogan)


## Restaurant-Wahl (W13B, Doc E §5.1): je Lieferküche EINE tappbare Karte
## (Name, Bewertungs-Gag, Wartezeit) statt Button + loser Captions.
func _render_restaurants() -> void:
	_label(I18nService.t("phone.gooberando.restaurants_titel"))
	for restaurant: Dictionary in GooberandoRestaurants.alle():
		var karte := _restaurant_karte(restaurant)
		_box.add_child(karte)
		_klemme_karten_hoehe(karte)


## Kartenhöhe = Inhalt + Ränder, nie unter 64·f/Touch-Floor. ERST nach
## add_child messen: Theme-Variationen (Headline/Caption) lösen nur im Tree
## auf und die Schrift muss VOR der Messung auf f skaliert sein — sonst
## klemmt die Höhe auf den unskalierten Fonts und die Captions clippen.
## (scale_fonts ist idempotent — der Render-Abschluss skaliert erneut.)
func _klemme_karten_hoehe(karte: Button) -> void:
	var m := ScreenShell.metrics(get_viewport())
	ScreenShell.scale_fonts(karte, float(m["f"]))
	var inhalt: Control = karte.get_child(0)
	var innen_h := inhalt.get_combined_minimum_size().y
	karte.custom_minimum_size = Vector2(0.0, maxf(roundf(KARTE_HOEHE * float(m["f"])), innen_h))
	ScreenShell.touch_target(karte, m)


func _restaurant_karte(restaurant: Dictionary) -> Button:
	var id := str(restaurant.get("id", ""))
	var karte := SquishButton.new()
	karte.name = "Restaurant_%s" % id
	karte.theme_type_variation = "AcCardButton"
	karte.focus_mode = Control.FOCUS_NONE
	karte.pressed.connect(_on_restaurant.bind(id))
	var inhalt := MarginContainer.new()
	inhalt.set_anchors_preset(Control.PRESET_FULL_RECT)
	inhalt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for seite: String in ["left", "right"]:
		inhalt.add_theme_constant_override("margin_" + seite, 14)
	for seite: String in ["top", "bottom"]:
		inhalt.add_theme_constant_override("margin_" + seite, 10)
	karte.add_child(inhalt)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 2)
	inhalt.add_child(spalte)
	var titel := Label.new()
	titel.name = "KartenName"
	titel.theme_type_variation = "HeadlineLabel"
	titel.text = str(restaurant.get("name_de", "?"))
	spalte.add_child(titel)
	var textbreite := inhalt_breite() - 28.0
	var bewertung := Label.new()
	bewertung.theme_type_variation = "CaptionLabel"
	bewertung.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bewertung.custom_minimum_size = Vector2(textbreite, 0.0)
	# Autowrap misst die Min-Höhe an der AKTUELLEN Breite — Startbreite
	# setzen, sonst rechnet die Höhen-Klemme mit 1 Zeichen/Zeile.
	bewertung.size = Vector2(textbreite, 0.0)
	(
		bewertung
		. set_text(
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
	)
	spalte.add_child(bewertung)
	var wartezeit := Label.new()
	wartezeit.theme_type_variation = "CaptionLabel"
	(
		wartezeit
		. set_text(
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
	)
	spalte.add_child(wartezeit)
	# Höhen-Klemme folgt NACH add_child (_klemme_karten_hoehe): die
	# FULL_RECT-Innenbox propagiert ihre Min-Höhe nicht durch den Button
	# und Theme-Fonts lösen erst im Tree auf.
	var m := ScreenShell.metrics(get_viewport())
	karte.custom_minimum_size = Vector2(0.0, roundf(KARTE_HOEHE * float(m["f"])))
	ScreenShell.touch_target(karte, m)
	return karte


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
		var btn := _knopf(
			"%s — %d ᴳ" % [str(gericht.get("name_de", "?")), int(gericht.get("preis", 0))],
			"AccentButton"
		)
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
	var kaufen := _knopf(
		I18nService.t("phone.gooberando.bestellen").format({"summe": summe}), "PrimaryButton"
	)
	kaufen.disabled = _warenkorb.is_empty() or coins < summe
	kaufen.pressed.connect(_on_bestellen)
	_box.add_child(kaufen)
	if not _warenkorb.is_empty():
		var leeren := _knopf(I18nService.t("phone.gooberando.warenkorb_leeren"), "GhostButton")
		leeren.pressed.connect(_on_korb_leeren)
		_box.add_child(leeren)
	var zurueck := _knopf(I18nService.t("phone.gooberando.menue_zurueck"), "GhostButton")
	zurueck.pressed.connect(_on_zurueck_zu_restaurants)
	_box.add_child(zurueck)


## Countdown + Live-Karte (W13B, Doc E §5.2): der orange Fahrer-Punkt
## wandert deterministisch die road_graph-Route entlang. G4/P16: die Karte
## skaliert mit der Inhaltsbreite statt Briefmarken-fix 148 px.
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
		var kante := karten_kante()
		var center := CenterContainer.new()
		_box.add_child(center)
		var mini := CityMinimap.new()
		mini.kachel = kante
		mini.karte = _stadt_karte()
		center.add_child(mini)
		var overlay := FahrerKarteOverlay.new()
		overlay.kachel = kante
		overlay.mini = mini
		overlay.route = route
		overlay.fahrer = stat["punkt"]
		overlay.farbe = ORANGE
		center.add_child(overlay)
		_caption(I18nService.t("phone.gooberando.karte_hinweis"))


## Kantenlänge der Live-Karte (ui-reisen MITTEL 7, pure Klemme).
func karten_kante() -> float:
	return clampf(inhalt_breite() * KARTE_ANTEIL, KARTE_MIN, KARTE_MAX)


func _render_vor_der_tuer() -> void:
	_liefer_gooby()
	_label(I18nService.t("travel.gooberando.klingel"))
	var btn := _knopf(I18nService.t("travel.gooberando.annehmen"), "PrimaryButton")
	btn.pressed.connect(_on_uebergabe)
	_box.add_child(btn)


func _render_trinkgeld() -> void:
	_liefer_gooby()
	_label(I18nService.t("travel.gooberando.uebergeben"))
	var geben := _knopf(I18nService.t("travel.gooberando.trinkgeld_geben"), "PrimaryButton")
	geben.pressed.connect(_on_trinkgeld.bind(true))
	_box.add_child(geben)
	var winken := _knopf(I18nService.t("travel.gooberando.nur_winken"), "GhostButton")
	winken.pressed.connect(_on_trinkgeld.bind(false))
	_box.add_child(winken)


## Oranger Liefer-Gooby (W1b-Rig, Fell-Tint #FF7A00) im SubViewport-Porträt.
func _liefer_gooby() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(
		0.0, roundf(220.0 * UiScale.for_viewport(get_viewport()))
	)
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
	# Auswahl/Ansichtswechsel (Grammatik: ui_chip).
	AudioDirector.try_play(self, "ui_chip")
	_restaurant = restaurant_id
	_warenkorb = []
	_render()


func _on_zurueck_zu_restaurants() -> void:
	AudioDirector.try_play(self, "ui_back")
	_restaurant = ""
	_warenkorb = []
	_render()


func _on_in_den_korb(gericht: Dictionary) -> void:
	if _warenkorb.size() >= MAX_KORB:
		return
	# Mikro-Schritt (Korb +1) — Knopf ist bei vollem Korb disabled.
	AudioDirector.try_play(self, "ui_tick")
	_warenkorb.append(gericht)
	_render()


func _on_korb_leeren() -> void:
	AudioDirector.try_play(self, "ui_back")
	_warenkorb = []
	_render()


func _on_bestellen() -> void:
	var res := GooberandoLogic.bestellen_korb(
		CityState.gooberando_slice(gs), now_ms(), prep_s(_restaurant), _warenkorb, _restaurant
	)
	if not bool(res["ok"]):
		return
	# GDScript-Lambdas capturen lokale Werte PER KOPIE — ein bool käme nie
	# zurück (Bestellung würde nie gespeichert). Dictionary teilt die Referenz.
	var zahlung := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			zahlung["ok"] = Economy.spend(state["economy"], int(res["kosten"]), "gooberando")
	)
	if not bool(zahlung["ok"]):
		return
	# Outcome schlägt Press: erst die GELUNGENE Münz-Ausgabe klingt.
	AudioDirector.try_play(self, "ui_buy")
	Haptics.success(self)
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
	# Outcome: Übergabe hat geklappt (Bestätigungs-Klang).
	AudioDirector.try_play(self, "ui_confirm")
	CityState.save_gooberando_slice(gs, res["slice"])
	for id: Variant in res["gerichte"]:
		_gib_essen(str(id))
	geliefert.emit(str(res["gerichtId"]))
	_render()


func _on_trinkgeld(geben: bool) -> void:
	var res := GooberandoLogic.trinkgeld(CityState.gooberando_slice(gs), now_ms(), geben, randf())
	if geben:
		var zahlung := {"ok": false}
		gs.update(
			func(state: Dictionary) -> void:
				zahlung["ok"] = Economy.spend(state["economy"], int(res["kosten"]), "trinkgeld")
		)
		if bool(zahlung["ok"]):
			AudioDirector.try_play(self, "ui_buy")
	else:
		AudioDirector.try_play(self, "ui_click")
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


## Aktions-Knopf im AC-Look: SquishButton (Squish + Tap-Haptik zentral),
## Mindesthöhe 52·f und physischer Touch-Floor (ui-reisen MITTEL 6).
func _knopf(text: String, variation: String) -> SquishButton:
	var btn := SquishButton.new()
	btn.theme_type_variation = variation
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	var m := ScreenShell.metrics(get_viewport())
	btn.custom_minimum_size = Vector2(0.0, roundf(KNOPF_HOEHE * float(m["f"])))
	ScreenShell.touch_target(btn, m)
	return btn


## G5/P34: Fließtexte über den PhoneShell-Baustein — der setzt die
## Autowrap-Startbreite (Geräte-Textbreite) VOR add_child (W3a-GOTCHA).
func _label(text: String) -> void:
	PhoneShell.app_label(_box, text)


func _caption(text: String) -> void:
	PhoneShell.app_label(_box, text, "CaptionLabel")


## Theme-Schriften des frischen Inhalts ×f heben (PhoneShell-Baustein).
func _skaliere_schriften() -> void:
	PhoneShell.app_fonts_skalieren(self)


func _zeige_toast(text: String) -> void:
	ToastLayer.zeige(self, text)


## Fahrer-Overlay über der Minimap: Route (blass) + oranger Fahrer-Punkt.
## Eigenes Control statt `draw`-Signal, damit es sicher ÜBER der Karte liegt.
## G4/P16: `kachel` skaliert Punkt/Linien proportional zur Kartenkante mit.
class FahrerKarteOverlay:
	extends Control

	var mini: CityMinimap
	var route := PackedVector3Array()
	var fahrer := Vector3.ZERO
	var farbe := Color("#FF7A00")
	## Kantenlänge in px (vor add_child setzen; Default = klassische Kachel).
	var kachel := CityMinimap.GROESSE

	func _ready() -> void:
		custom_minimum_size = Vector2(kachel, kachel)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if mini == null:
			return
		var faktor := kachel / CityMinimap.GROESSE
		if route.size() >= 2:
			var px := PackedVector2Array()
			for punkt in route:
				px.append(mini.welt_zu_pixel(punkt))
			draw_polyline(px, Color(farbe, 0.45), 2.0 * faktor)
		var mitte := mini.welt_zu_pixel(fahrer)
		draw_circle(mitte, 6.5 * faktor, AcTokens.PAPER)
		draw_circle(mitte, 5.0 * faktor, farbe)
