extends TestCase
## G3/P05 UI-ORTE — der gemeinsame Ort-Rahmen-Umbau (g1/ui-reisen HOCH 1/2/4,
## g1/ui-shop §4):
## - `OrtScene._baue_knopfleiste()`: zentrierte, Safe-Area-bewusste
##   Bottom-Leiste (HFlow-Umbruch statt Hochformat-Überlauf) + physischer
##   Touch-Floor auf allen Knöpfen — Flughafen, Raumstation, Urlaubs-Orte.
## - „Verlassen“ raus aus der (16,16)-Ecke: Position hängt an den
##   Safe-Area-Insets (Notch/Dynamic Island) und zieht bei Rotation nach.
## - TapSpots der Urlaubs-Mini-Aktivität: Floor-Größe + Klemmung in die
##   Safe-Area (nie hinter Notch oder Knopfleiste).
## - GOOBY-FREE „geschlossen“ SICHTBAR am Ort (Knopf disabled + Hinweis-
##   Zeile) statt Toast-Überraschung; folgt Buchungs-/Urlaubs-Änderungen.
## Testnamen-Verträge bleiben: FlughafenKnoepfe/StationsKnoepfe/
## BesuchsKnoepfe/TapSpot<i>.

const Vacation := preload("res://scripts/logic/vacation.gd")
const FlughafenSzene := preload("res://scenes/city/orte/flughafen.tscn")

const QUER := Vector2i(1280, 720)
const HOCH := Vector2i(720, 1280)


## GameState-Double (Muster test_w13b_raumstation) MIT Signalen, damit der
## Flughafen den GOOBY-FREE-Zustand live nachziehen kann.
class FakeGameState:
	extends RefCounted

	signal slice_changed(slice_id: String, data: Variant)
	signal vacation_changed(phase: String, dest_id: String)

	var daten: Dictionary = {}

	func _init(start: Dictionary = {}) -> void:
		daten = start

	func state() -> Dictionary:
		return daten

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = daten
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = daten
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(daten)

	func notify_slice_changed(slice_id: String) -> void:
		slice_changed.emit(slice_id, daten.get(slice_id))

	func melde_vacation(phase: String, dest_id: String) -> void:
		vacation_changed.emit(phase, dest_id)


class FakeRouter:
	extends RefCounted

	var routen: Dictionary = {}
	var ziele: Array = []

	func register_route(target: StringName, szene: String) -> void:
		routen[target] = szene

	func goto(target: StringName, params: Dictionary = {}) -> void:
		ziele.append({"target": target, "params": params})

	func back() -> bool:
		return true


func _basis_state() -> Dictionary:
	return {
		"vacation": Vacation.default_slice(),
		"buffs": {"aktiv": []},
		"economy": {"coins": 500},
		"inventory": {"items": {}, "food": {}},
		"home": {"storage": [], "storageCapacity": 100},
		"gooby": {"stats": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "fun": 50.0}},
		"city": {},
	}


func _away_state(dest_id: String) -> Dictionary:
	var state := _basis_state()
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var v: Dictionary = state["vacation"]
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = dest_id
	v["bookedAt"] = now - Vacation.MS_PER_DAY
	v["returnAt"] = now + 2 * Vacation.MS_PER_DAY
	v["pickupBy"] = now + 3 * Vacation.MS_PER_DAY
	return state


func _mit_buchung(gs: FakeGameState, ziel := "beach") -> void:
	(
		gs
		. set_value(
			"city.taxi",
			{
				"state": TaxiLogic.STATE_GERUFEN,
				"gerufenAt": 0,
				"ankunftAt": 300000,
				"zielId": ziel,
			}
		)
	)
	gs.notify_slice_changed("city")


## Fenster + simulierte Notch setzen (Muster fb3_ui_audit/test_ui_rest1).
func _setze_format(win_size: Vector2i, hochformat: bool) -> void:
	tree.root.size = win_size
	await wait_frames(1)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	if hochformat:
		UiScale.insets_override = Rect2(0.0, 90.0, canvas.x, canvas.y - 90.0 - 34.0)
	else:
		UiScale.insets_override = Rect2(88.0, 0.0, canvas.x - 176.0, canvas.y - 30.0)
	if tree.root.has_signal("size_changed"):
		tree.root.size_changed.emit()
	await wait_frames(1)


func _reset_format() -> void:
	UiScale.insets_override = Rect2()
	tree.root.size = QUER
	await wait_frames(1)


func _knoepfe_von(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		stack.append_array(current.get_children())
		if current is Button:
			out.append(current)
	return out


## ------------------------------------------------ Flughafen + GOOBY-FREE


func test_flughafen_leiste_verlassen_und_gfree_sichtbar() -> void:
	await _setze_format(QUER, false)
	var state := _basis_state()
	state["vacation"]["visited"] = {"space": true}
	var gs := FakeGameState.new(state)
	var ort: OrtFlughafen = FlughafenSzene.instantiate()
	ort.game_state_override = gs
	tree.root.add_child(ort)
	await wait_frames(3)
	var m := ScreenShell.metrics(tree.root)
	var insets: Dictionary = m["insets"]
	var floor_px: float = m["floor_px"]
	var f: float = m["f"]
	# Verlassen: raus aus der (16,16)-Ecke, rein in die Safe-Area + Floor.
	var zurueck: Button = ort.find_child("Verlassen", true, false)
	assert_ne(zurueck, null, "Verlassen-Knopf heißt jetzt Verlassen")
	assert_almost(zurueck.position.x, float(insets["left"]) + 16.0 * f, 0.5, "links = Inset + 16·f")
	assert_almost(zurueck.position.y, float(insets["top"]) + 12.0 * f, 0.5, "oben = Inset + 12·f")
	assert_true(zurueck.custom_minimum_size.y >= floor_px - 0.5, "Verlassen hält den Floor")
	# Leiste: HFlow (Umbruch!), Breite gedeckelt, über dem Home-Indicator.
	var leiste: Control = ort.find_child("FlughafenKnoepfe", true, false)
	assert_ne(leiste, null, "FlughafenKnoepfe steht (Namens-Vertrag)")
	assert_true(leiste is HFlowContainer, "Leiste bricht per HFlow um")
	assert_almost(
		leiste.offset_bottom, -(float(insets["bottom"]) + 16.0 * f), 0.5, "Unterkante über Inset"
	)
	var breite := ScreenShell.card_width(m, OrtScene.LEISTE_BASIS_BREITE)
	assert_almost(leiste.offset_right - leiste.offset_left, breite, 0.5, "Breiten-Deckel")
	for knopf in _knoepfe_von(leiste):
		assert_true(
			(
				knopf.custom_minimum_size.x >= floor_px - 0.5
				and knopf.custom_minimum_size.y >= floor_px - 0.5
			),
			"%s hält den Touch-Floor" % knopf.name
		)
	assert_ne(leiste.get_node_or_null("Shuttle"), null, "Shuttle-Knopf in der Leiste")
	# GOOBY-FREE zu: Knopf sichtbar ausgegraut + Hinweis-Zeile statt Toast.
	var gfree: Button = ort.find_child("GoobyFree", true, false)
	var hinweis: Label = ort.find_child("GoobyFreeHinweis", true, false)
	assert_ne(hinweis, null, "Hinweis-Zeile existiert")
	assert_true(gfree.disabled, "ohne Buchung: Knopf disabled")
	assert_true(hinweis.visible, "ohne Buchung: Grund sichtbar am Ort")
	assert_eq(hinweis.text, I18nService.t("gfree.zu"), "Hinweis nutzt den gfree.zu-Text")
	# Regression: Leiste wächst erst im deferred Container-Sort auf ihre
	# Minimum-Höhe — der Hinweis muss trotzdem ÜBER ihr landen, nicht drauf.
	assert_true(
		hinweis.get_global_rect().end.y <= leiste.get_global_rect().position.y + 0.5,
		"Hinweis-Zeile steht über der Knopfleiste"
	)
	# Buchung kommt rein (city-Slice) → Zustand zieht live nach.
	_mit_buchung(gs)
	await wait_frames(1)
	assert_false(gfree.disabled, "mit Buchung: Knopf aktiv")
	assert_false(hinweis.visible, "mit Buchung: Hinweis weg")
	ort.queue_free()
	await wait_frames(1)
	await _reset_format()


func test_flughafen_rotation_zieht_layout_nach() -> void:
	await _setze_format(QUER, false)
	var gs := FakeGameState.new(_basis_state())
	var ort: OrtFlughafen = FlughafenSzene.instantiate()
	ort.game_state_override = gs
	tree.root.add_child(ort)
	await wait_frames(3)
	# Drehen: Hochformat mit Insel oben (90) + Indicator unten (34).
	await _setze_format(HOCH, true)
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var insets: Dictionary = m["insets"]
	# Im Hochformat expandiert das Stretch die Canvas (Kurzkante 1280) —
	# f steigt auf ~1,78, Ränder skalieren mit (16·f / 12·f).
	var f: float = m["f"]
	var zurueck: Button = ort.find_child("Verlassen", true, false)
	assert_almost(
		zurueck.position.y, float(insets["top"]) + 12.0 * f, 0.5, "Verlassen unter der Insel"
	)
	var leiste: Control = ort.find_child("FlughafenKnoepfe", true, false)
	assert_almost(
		leiste.offset_bottom,
		-(float(insets["bottom"]) + 16.0 * f),
		0.5,
		"Leiste über dem Home-Indicator"
	)
	ort.queue_free()
	await wait_frames(1)
	await _reset_format()


## ------------------------------------------------------------ Raumstation


func test_raumstation_leiste_floor_und_namen() -> void:
	await _setze_format(QUER, false)
	var state := _basis_state()
	state["vacation"]["visited"] = {"space": true}
	var gs := FakeGameState.new(state)
	var ort: OrtRaumstation = load("res://scenes/city/orte/raumstation.tscn").instantiate()
	ort.game_state_override = gs
	ort.router_override = FakeRouter.new()
	tree.root.add_child(ort)
	await wait_frames(3)
	var m := ScreenShell.metrics(tree.root)
	var floor_px: float = m["floor_px"]
	var leiste: Control = ort.find_child("StationsKnoepfe", true, false)
	assert_ne(leiste, null, "StationsKnoepfe steht (Namens-Vertrag)")
	assert_true(leiste is HFlowContainer, "Leiste bricht per HFlow um")
	for name_id in ["TerminalRocket", "TerminalStar", "Automat", "Sternenfoto"]:
		var knopf: Button = leiste.get_node_or_null(name_id)
		assert_ne(knopf, null, "Knopf %s in der Leiste" % name_id)
		assert_true(
			(
				knopf.custom_minimum_size.x >= floor_px - 0.5
				and knopf.custom_minimum_size.y >= 52.0 - 0.5
			),
			"%s hält Floor + 52er-Höhe" % name_id
		)
	# Verdrahtung überlebt den Leisten-Umbau: Terminal startet sein Spiel.
	ort.starte_spiel(OrtRaumstation.SPIEL_ROCKET)
	var router: FakeRouter = ort.router_override
	assert_eq(router.ziele.size(), 1, "Terminal-Start läuft weiter")
	ort.queue_free()
	await wait_frames(1)
	await _reset_format()


## ---------------------------------------------------------- Urlaubs-Orte


func test_urlaub_hochformat_ohne_ueberlauf_und_titel_safe() -> void:
	await _setze_format(HOCH, true)
	var gs := FakeGameState.new(_away_state("beach"))
	var ort: UrlaubsOrt = load(str(UrlaubsBesuch.SZENEN["strand"])).instantiate()
	ort.game_state_override = gs
	ort.router_override = FakeRouter.new()
	tree.root.add_child(ort)
	await wait_frames(4)
	var m := ScreenShell.metrics(tree.root)
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	var leiste: Control = ort.find_child("BesuchsKnoepfe", true, false)
	assert_ne(leiste, null, "BesuchsKnoepfe steht (Namens-Vertrag)")
	# DER W15-Hauptbefund: im Hochformat lief die 4er-HBox über beide
	# Ränder — jetzt bleibt jeder Knopf im Safe-Rechteck (Flow-Umbruch).
	for knopf in _knoepfe_von(leiste):
		var rect := knopf.get_global_rect()
		assert_true(
			rect.position.x >= float(insets["left"]) - 0.5,
			"%s ragt links raus (%s)" % [knopf.name, rect]
		)
		assert_true(
			rect.end.x <= canvas.x - float(insets["right"]) + 0.5,
			"%s ragt rechts raus (%s)" % [knopf.name, rect]
		)
		assert_true(
			rect.end.y <= canvas.y - float(insets["bottom"]) + 0.5,
			"%s liegt im Home-Indicator (%s)" % [knopf.name, rect]
		)
	var titel: Label = ort.find_child("UrlaubsTitel", true, false)
	assert_true(
		titel.get_global_rect().position.y >= float(insets["top"]) - 0.5,
		"Titel kollidiert nicht mit der Statusinsel"
	)
	ort.queue_free()
	await wait_frames(1)
	await _reset_format()


func test_urlaub_tapspots_floor_und_safe_klemmung() -> void:
	await _setze_format(HOCH, true)
	var gs := FakeGameState.new(_away_state("beach"))
	var ort: UrlaubsOrt = load(str(UrlaubsBesuch.SZENEN["strand"])).instantiate()
	ort.game_state_override = gs
	ort.router_override = FakeRouter.new()
	tree.root.add_child(ort)
	await wait_frames(3)
	ort._on_mini()
	await wait_frames(3)
	var m := ScreenShell.metrics(tree.root)
	var seite := maxf(56.0 * float(m["f"]), float(m["floor_px"]))
	var frei: Rect2 = ort._tap_safe_rect(m, seite)
	assert_eq(ort.tap_knoepfe.size(), UrlaubsAktivitaeten.TAP_ANZAHL, "5 Tap-Spots")
	for knopf in ort.tap_knoepfe:
		assert_true(
			(
				knopf.custom_minimum_size.x >= seite - 0.5
				and knopf.custom_minimum_size.y >= seite - 0.5
			),
			"%s hält den Floor (%s)" % [knopf.name, knopf.custom_minimum_size]
		)
		assert_true(
			(
				knopf.position.x >= frei.position.x - 0.5
				and knopf.position.x + seite <= frei.end.x + 0.5
			),
			"%s horizontal in der Safe-Area (%s)" % [knopf.name, knopf.position]
		)
		assert_true(
			(
				knopf.position.y >= frei.position.y - 0.5
				and knopf.position.y + seite <= frei.end.y + 0.5
			),
			"%s über der Knopfleiste (%s)" % [knopf.name, knopf.position]
		)
	# Der Spot-Bereich endet ÜBER der Knopfleiste (kein Spot hinter Knöpfen).
	var leiste: Control = ort.find_child("BesuchsKnoepfe", true, false)
	assert_true(
		frei.end.y <= leiste.get_global_rect().position.y + 0.5,
		"Safe-Rect endet an der Leisten-Oberkante"
	)
	# Durchspielen räumt weiter sauber ab (Bestandsvertrag).
	for i in UrlaubsAktivitaeten.TAP_ANZAHL:
		ort._on_tap(i)
	await wait_frames(2)
	assert_eq(ort.find_child("TapEbene", true, false), null, "Tap-Ebene abgeräumt")
	ort.queue_free()
	await wait_frames(1)
	await _reset_format()
