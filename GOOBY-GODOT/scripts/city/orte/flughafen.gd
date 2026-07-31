class_name OrtFlughafen
extends OrtScene
## Flughafen-Terminal (Doc E §3): Reise-Schalter — Ziel wählen →
## Bestätigungs-Dialog (Preis/Dauer/WARNUNG/NUTZEN) → Taxi bestellen
## (ReiseApp). Die eigentliche Abreise passiert NACH der realen Taxi-
## Wartezeit über die Reise-Cutscene.
##
## W13B/RAUMSTATION (Doc E §3.3 + G §7) ergänzt drei Dinge:
## 1. GOOBY-FREE — der Duty-Free-Stand am Gate: exklusive gfree_*-Deko
##    (Katalogpreis 0 → taucht in KEINEM anderen Laden auf) + Reise-Snacks,
##    Preise „leicht überteuert“ (Flughafen!). Kaufbar NUR mit aktiver
##    Abflug-Buchung (Taxi GERUFEN/WARTET mit Urlaubsziel) — Gate + Kauf
##    sind pure static-Funktionen (testbar ohne Baum).
## 2. GOOB-1-SHUTTLE — der Weg zur Raumstation: Knopf erscheint erst,
##    wenn `vacation.visited.space` gelatcht ist (OrtRaumstation.
##    freigeschaltet); die Station hängt bewusst NICHT an der city_map.
## 3. URLAUBS-BONUS-SYNC — die Abholung passiert HIER (ReiseApp-Sheet),
##    also spiegelt der Flughafen nach jeder vacation-Änderung sofort
##    Erholungs-Buff + Weltengooby-Feier (UrlaubsBonus.sync, idempotent).

const Vacation := preload("res://scripts/logic/vacation.gd")
const Economy := preload("res://scripts/logic/economy.gd")

const INNEN := "res://assets/city/innen"

## GOOBY-FREE-Sortiment: typ "moebel" → home.storage (StorageLogic),
## typ "snack" → inventory.food. Preise BEWUSST über Normalniveau
## (Sandwich 16→24, Keks 8→13; Deko gibt es sonst nirgends — verkaufswert
## der gfree_*-Einträge liegt deutlich darunter, s. furniture_extra.json).
const GOOBY_FREE_SORTIMENT: Array[Dictionary] = [
	{"id": "gfree_shuttle", "typ": "moebel", "preis": 149},
	{"id": "gfree_flitzer", "typ": "moebel", "preis": 129},
	{"id": "gfree_meteorit", "typ": "moebel", "preis": 99},
	{"id": "gfree_sternmoehre", "typ": "moebel", "preis": 88},
	{"id": "gfree_mondstein", "typ": "moebel", "preis": 66},
	{"id": "sandwich", "typ": "snack", "preis": 24},
	{"id": "cookie", "typ": "snack", "preis": 13},
]

## Kauf-Ergebnis-Codes (kaufe_gfree).
const KAUF_OK := "ok"
const KAUF_ZU := "geschlossen"
const KAUF_PLEITE := "pleite"
const KAUF_VOLL := "lager_voll"
const KAUF_REASON := "gooby_free"

var _gfree_liste: VBoxContainer
var _gfree_coins: Label


## Ist der GOOBY-FREE geöffnet? NUR vor einem gebuchten Abflug: Taxi ist
## GERUFEN oder WARTET und das Ziel ist ein Urlaubsziel (Stadt-Taxis mit
## anderem zielId zählen nicht). Pure — direkt über dem State-Dictionary.
static func gooby_free_offen(state: Dictionary) -> bool:
	var stadt: Variant = state.get("city")
	var taxi := TaxiLogic.normalize_slice(stadt.get("taxi") if stadt is Dictionary else null)
	var status := str(taxi["state"])
	if status != TaxiLogic.STATE_GERUFEN and status != TaxiLogic.STATE_WARTET:
		return false
	return Vacation.CATALOG.has(str(taxi["zielId"]))


## GOOBY-FREE-Kauf, atomar (Muster ShopPurchase.buy): Münzen weg UND Ware
## drin, oder nichts. Möbel landen im LAGER (home.storage — der Baumodus
## holt sie ab), Snacks in inventory.food. ShopPurchase selbst ist hier
## BEWUSST außen vor: dessen sellable()-Check (preis > 0) würde die
## exklusiven gfree_*-Artikel (Katalogpreis 0) abweisen.
static func kaufe_gfree(gs: Object, ware: Dictionary) -> String:
	if gs == null or not gooby_free_offen(gs.state()):
		return KAUF_ZU
	var preis := int(ware.get("preis", 0))
	if int(gs.get_value("economy.coins", 0)) < preis:
		return KAUF_PLEITE
	var id := str(ware.get("id", ""))
	var moebel := str(ware.get("typ", "")) == "moebel"
	if moebel:
		var lager: Variant = gs.get_value("home.storage", [])
		var frei := StorageLogic.can_add(
			lager if lager is Array else [],
			id,
			ShopCatalog.defs(),
			int(gs.get_value("home.storageCapacity", 100))
		)
		if not frei:
			return KAUF_VOLL
	# Einelementiges Array als Rückkanal (GDScript-Lambdas fangen per Wert).
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, KAUF_REASON):
				return
			bezahlt[0] = true
			if moebel:
				StorageLogic.add(state[HomeState.SLICE_ID]["storage"], id)
			else:
				var food: Dictionary = state["inventory"]["food"]
				food[id] = int(food.get(id, 0)) + 1
	)
	if not bool(bezahlt[0]):
		return KAUF_PLEITE
	gs.notify_slice_changed(HomeState.SLICE_ID if moebel else "inventory")
	return KAUF_OK


## Anzeigename einer GOOBY-FREE-Ware (Möbel: Katalog de/en, Snack: Food).
static func gfree_name(ware: Dictionary) -> String:
	var id := str(ware.get("id", ""))
	if str(ware.get("typ", "")) == "moebel":
		var item := ShopCatalog.def(id)
		var key := "name_en" if I18nService.get_locale() == "en" else "name_de"
		return str(item.get(key, id))
	return FoodCatalog.display_name(id)


func _ready() -> void:
	super._ready()
	var gs := game_state()
	if gs != null:
		UrlaubsBonus.sync(gs, _now_ms(), self)
		if gs.has_signal("vacation_changed"):
			gs.vacation_changed.connect(_on_vacation_changed)


func _baue_innenraum() -> void:
	# Basisgrößen: Counter 2 m, Menu-Tafel 0,8 m — Skalen klein (s. rehwei.gd).
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(0.0, 0.0, -1.2), 90.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(-2.6, 0.0, -3.4), 0.0, 2.0)
	_prop("%s/menu.gltf" % INNEN, Vector3(2.6, 0.0, -3.4), 0.0, 2.0)
	_baue_gfree_stand(Vector3(3.4, 0.0, -1.6), -30.0)


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#9BB7E8"), "emotion": "happy", "pos": Vector3(0.0, 0.0, -2.2)}


func _baue_ui() -> void:
	super._baue_ui()
	var reihe := HBoxContainer.new()
	reihe.name = "FlughafenKnoepfe"
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("separation", 10)
	reihe.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24
	)
	reihe.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(reihe)
	var reise_btn := Button.new()
	reise_btn.name = "Reise"
	reise_btn.text = I18nService.t("travel.schalter.knopf")
	reise_btn.theme_type_variation = "PrimaryButton"
	reise_btn.custom_minimum_size = Vector2(220.0, 56.0)
	reise_btn.pressed.connect(_on_reise)
	reihe.add_child(reise_btn)
	var gfree_btn := Button.new()
	gfree_btn.name = "GoobyFree"
	gfree_btn.text = I18nService.t("gfree.knopf")
	gfree_btn.theme_type_variation = "AccentButton"
	gfree_btn.custom_minimum_size = Vector2(0.0, 56.0)
	gfree_btn.pressed.connect(_on_gooby_free)
	reihe.add_child(gfree_btn)
	var gs := game_state()
	if gs != null and OrtRaumstation.freigeschaltet(gs.state()):
		var shuttle_btn := Button.new()
		shuttle_btn.name = "Shuttle"
		shuttle_btn.text = I18nService.t("gfree.shuttle_knopf")
		shuttle_btn.theme_type_variation = "AccentButton"
		shuttle_btn.custom_minimum_size = Vector2(0.0, 56.0)
		shuttle_btn.pressed.connect(_on_shuttle)
		reihe.add_child(shuttle_btn)


func _on_reise() -> void:
	ReiseApp.oeffne(self, game_state())


## ---------------------------------------------------------- GOOBY-FREE


func _on_gooby_free() -> void:
	var gs := game_state()
	if gs == null:
		return
	if not gooby_free_offen(gs.state()):
		# Augenzwinkern: ohne Boarding kein Duty-Free — wie im echten Leben.
		zeige_toast(I18nService.t("gfree.zu"))
		return
	AudioDirector.try_play(self, "ui_click")
	zeige_sheet(I18nService.t("gfree.titel"), _gfree_inhalt())


func _gfree_inhalt() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420.0, 0.0)
	box.add_theme_constant_override("separation", 10)
	var hinweis := Label.new()
	hinweis.theme_type_variation = "CaptionLabel"
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.text = I18nService.t("gfree.hinweis")
	box.add_child(hinweis)
	_gfree_coins = Label.new()
	_gfree_coins.theme_type_variation = "CaptionLabel"
	box.add_child(_gfree_coins)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 360.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_gfree_liste = VBoxContainer.new()
	_gfree_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gfree_liste.add_theme_constant_override("separation", 8)
	scroll.add_child(_gfree_liste)
	_gfree_aktualisieren()
	return box


func _gfree_aktualisieren() -> void:
	if _gfree_liste == null or not is_instance_valid(_gfree_liste):
		return
	for kind in _gfree_liste.get_children():
		kind.queue_free()
	var gs := game_state()
	var coins := int(gs.get_value("economy.coins", 0)) if gs != null else 0
	_gfree_coins.text = I18nService.t("city.laden.coins").format({"coins": coins})
	for ware: Dictionary in GOOBY_FREE_SORTIMENT:
		_gfree_liste.add_child(_gfree_zeile(ware, coins))


func _gfree_zeile(ware: Dictionary, coins: int) -> Control:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = gfree_name(ware)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(name_label)
	if str(ware.get("typ", "")) == "moebel":
		var exklusiv := Label.new()
		exklusiv.theme_type_variation = "CaptionLabel"
		exklusiv.text = I18nService.t("gfree.exklusiv")
		zeile.add_child(exklusiv)
	var btn := Button.new()
	btn.theme_type_variation = "AccentButton"
	btn.text = I18nService.t("city.laden.kaufen").format({"preis": int(ware.get("preis", 0))})
	btn.disabled = coins < int(ware.get("preis", 0))
	btn.pressed.connect(_on_gfree_kauf.bind(ware))
	zeile.add_child(btn)
	return zeile


func _on_gfree_kauf(ware: Dictionary) -> void:
	var ergebnis := kaufe_gfree(game_state(), ware)
	match ergebnis:
		KAUF_OK:
			AudioDirector.try_play(self, "ui_click")
			zeige_toast(I18nService.t("gfree.gekauft").format({"name": gfree_name(ware)}))
		KAUF_VOLL:
			zeige_toast(I18nService.t("gfree.lager_voll"))
		KAUF_ZU:
			zeige_toast(I18nService.t("gfree.zu"))
		_:
			pass
	_gfree_aktualisieren()


## Der Duty-Free-Stand in 3D: Counter + Regalwürfel + goldenes Schild.
func _baue_gfree_stand(pos: Vector3, rot_grad: float) -> void:
	var stand := Node3D.new()
	stand.name = "GoobyFreeStand"
	stand.position = pos
	stand.rotation_degrees.y = rot_grad
	add_child(stand)
	var theke := MeshInstance3D.new()
	var korpus := BoxMesh.new()
	korpus.size = Vector3(1.6, 0.9, 0.6)
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.35, 0.52, 0.72)
	kmat.roughness = 0.6
	korpus.material = kmat
	theke.mesh = korpus
	theke.position = Vector3(0.0, 0.45, 0.0)
	stand.add_child(theke)
	var regal := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(1.6, 1.1, 0.35)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.92, 0.88, 0.78)
	rmat.roughness = 0.7
	rbox.material = rmat
	regal.mesh = rbox
	regal.position = Vector3(0.0, 1.45, -0.2)
	stand.add_child(regal)
	var schild := Label3D.new()
	schild.text = I18nService.t("gfree.schild")
	schild.font_size = 52
	schild.pixel_size = 0.004
	schild.modulate = Color(1.0, 0.85, 0.35)
	schild.position = Vector3(0.0, 2.25, 0.0)
	schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stand.add_child(schild)


## ------------------------------------------------------- GOOB-1-Shuttle


func _on_shuttle() -> void:
	var gs := game_state()
	if gs == null or not OrtRaumstation.freigeschaltet(gs.state()):
		return
	AudioDirector.try_play(self, "ui_click")
	var router := get_node_or_null("/root/SceneRouter")
	OrtRaumstation.registriere_route(router)
	if router != null and router.has_method("goto"):
		router.goto(OrtRaumstation.ROUTE, {})


## --------------------------------------------------------- Urlaubs-Bonus


## Nach jeder vacation-Änderung (Abholung passiert im ReiseApp-Sheet über
## DIESEM Ort): Erholungs-Buff spiegeln + ggf. Weltengooby feiern.
func _on_vacation_changed(_phase: String, _dest_id: String) -> void:
	UrlaubsBonus.sync(game_state(), _now_ms(), self)


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
