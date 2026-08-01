extends TestCase
## P25 DLC-MCGOOBY-A (Welle G5) — McGooby-Fundament: Menü-Pack schema-valide
## (8–12 Start-Rezepte, Stationen-Balance), golden Bestell-Folge + Bot-
## Abrechnung (Seed → exakte Werte), „Perfekt!“-Fenster-Bewertung (Doc §2.2),
## Save-Slice-Self-Heal, Schicht-Szene mountet headless fehlerfrei
## (Erststart-Intro → Schicht → Ende-Karte) und Geometrie-Grundcheck.

const MENU_DATEI := "res://content/dlc/data/mcgooby_menu.json"
const SCHICHT_SZENE := "res://scripts/dlc/mcgooby/schicht_scene.tscn"
const GOLD_SEED := 4711


## GameState-Double: dotted get/set wie /root/GameState + update()-Pfad
## mit economy-Slice (der EINE Geld-Pfad der Szene läuft über Economy.award).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {"economy": {"coins": 0}}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)


## SceneRouter-Double: zeichnet register_route/goto auf (Muster GoobyeRouten).
class FakeRouter:
	extends RefCounted
	var routen: Dictionary = {}
	var reisen: Array = []

	func register_route(id: StringName, pfad: String) -> void:
		routen[id] = pfad

	func goto(ziel: StringName, params: Dictionary = {}) -> void:
		reisen.append({"ziel": ziel, "params": params})


func _menu() -> Array:
	McGoobyKatalog.reset_cache()
	return McGoobyKatalog.rezepte_fuer("grill")


## ------------------------------------------------------------ Pack-Schema


func test_menu_json_schema_valide() -> void:
	assert_true(FileAccess.file_exists(MENU_DATEI), "mcgooby_menu.json existiert")
	McGoobyKatalog.reset_cache()
	var rezepte := McGoobyKatalog.rezepte()
	assert_true(rezepte.size() >= 8 and rezepte.size() <= 12, "8–12 Start-Rezepte (Doc §3)")
	var pro_station: Dictionary = {}
	for rezept: Variant in rezepte:
		assert_true(rezept is Dictionary, "Rezept ist Dictionary")
		var def: Dictionary = rezept
		assert_true(McGoobyKatalog.ist_gueltig(def), "Rezept schema-valide: %s" % def.get("id"))
		for feld: String in ["name_de", "name_en"]:
			assert_true(
				not str(def.get(feld, "")).is_empty(),
				"%s: Parodie-Name %s gefüllt" % [def.get("id"), feld]
			)
		for station: Variant in def.get("stationen", []):
			pro_station[str(station)] = int(pro_station.get(str(station), 0)) + 1
	# Balancing-Prinzip Doc §3.1: jede Station trägt 3–5 Rezepte.
	for station: String in McGoobyKatalog.STATION_IDS:
		var n := int(pro_station.get(station, 0))
		assert_true(n >= 3 and n <= 5, "Station %s trägt 3–5 Rezepte (%d)" % [station, n])
	# Möhren-Pommes haben das KÜRZERE Fenster (knackig!, Doc §2.2 #3).
	var moehren := McGoobyKatalog.rezept("moehren_pommes")
	assert_true(float(moehren.get("fenster_mult", 1.0)) < 1.0, "Möhren-Fenster verengt")
	var normal := McGoobyKatalog.timing("fritteuse")
	var knackig := McGoobyKatalog.timing("fritteuse", moehren)
	assert_true(
		float(knackig["fenster_sec"]) < float(normal["fenster_sec"]),
		"fenster_mult verengt das Timing-Fenster"
	)
	# Balance-Block trägt alle Schicht-Zahlen (Pack-updatebar, Doc §3.1).
	var bal := McGoobyKatalog.balance()
	for key: String in [
		"bestellungen_min",
		"bestellungen_max",
		"punkte_perfekt",
		"punkte_roestaroma",
		"bestellung_fertig_bonus",
		"coin_divisor",
		"coin_min",
		"coin_max",
		"trinkgeld_basis",
		"combo_schritt",
		"combo_max",
	]:
		assert_true(bal.has(key), "Balance-Key %s vorhanden" % key)


func test_katalog_zugriff_und_grill_menu() -> void:
	McGoobyKatalog.reset_cache()
	assert_false(McGoobyKatalog.rezept("gooby_mac").is_empty(), "GoobyMac lesbar")
	assert_true(McGoobyKatalog.rezept("gibt_es_nicht").is_empty(), "Unbekannt = {}")
	var grill := _menu()
	assert_eq(grill.size(), 4, "4 Grill-Rezepte fürs Welle-A-Menü")
	assert_eq(
		McGoobySchichtLogic.grill_schritte(McGoobyKatalog.rezept("gooby_mac")),
		2,
		"GoobyMac = Doppeldecker: 2 Pattys"
	)


## ---------------------------------------------------- Golden Bestell-Folge


func test_golden_bestell_folge_seed_4711() -> void:
	var folge := McGoobySchichtLogic.bestell_folge(GOLD_SEED, _menu(), McGoobyKatalog.balance())
	assert_eq(folge.size(), 2, "Seed 4711 → exakt 2 Bestellungen")
	assert_eq(str(folge[0]["rezept_id"]), "garten_gooby", "Bestellung 1: Garten-Gooby")
	assert_eq(int(folge[0]["patties"]), 1)
	assert_eq(str(folge[1]["rezept_id"]), "gooby_mac", "Bestellung 2: GoobyMac")
	assert_eq(int(folge[1]["patties"]), 2)
	for i in folge.size():
		assert_eq(int(folge[i]["nr"]), i + 1, "Bestell-Nummern fortlaufend")


func test_golden_bestell_folge_seed_1234() -> void:
	var folge := McGoobySchichtLogic.bestell_folge(1234, _menu(), McGoobyKatalog.balance())
	var ids: Array[String] = []
	for bestellung: Dictionary in folge:
		ids.append(str(bestellung["rezept_id"]))
	assert_eq(
		ids,
		["kaese_knusperle", "gooby_mac", "garten_gooby", "gurken_deluxe"] as Array[String],
		"Seed 1234 → exakte 4er-Folge"
	)


func test_golden_autoplay_abrechnung() -> void:
	var bal := McGoobyKatalog.balance()
	var gold := McGoobySchichtLogic.simulate_autoplay(GOLD_SEED, _menu(), bal)
	assert_eq(int(gold["bestellungen"]), 2)
	assert_eq(int(gold["perfekt"]), 3, "Bot wendet 3/3 Pattys perfekt")
	assert_eq(int(gold["roestaroma"]), 0)
	assert_eq(int(gold["punkte"]), 60, "25 + 35 Punkte")
	assert_eq(int(gold["trinkgeld"]), 4, "Combo ×1,1/×1,2 auf Basis 2")
	assert_eq(int(gold["muenzen"]), 19, "floor(60/4) + 4 Trinkgeld")
	var gold2 := McGoobySchichtLogic.simulate_autoplay(1234, _menu(), bal)
	assert_eq(int(gold2["punkte"]), 105)
	assert_eq(int(gold2["roestaroma"]), 1)
	assert_eq(int(gold2["muenzen"]), 32)


## ------------------------------------------------- Timing-Fenster (§2.2)


func test_timing_fenster_bewertung() -> void:
	var timing := {"gar_sec": 4.0, "fenster_sec": 1.4, "nachlauf_sec": 2.0}
	var bal := McGoobyKatalog.balance()
	var frueh := McGoobySchichtLogic.bewerte_tap(3.99, timing, bal)
	assert_eq(str(frueh["wertung"]), "roh", "vor gar_sec = roh")
	assert_eq(int(frueh["punkte"]), 0, "zu früh kostet nichts")
	var start := McGoobySchichtLogic.bewerte_tap(4.0, timing, bal)
	assert_eq(str(start["wertung"]), "perfekt", "Fenster-Beginn inklusiv")
	assert_eq(int(start["punkte"]), 10)
	var knapp := McGoobySchichtLogic.bewerte_tap(5.39, timing, bal)
	assert_eq(str(knapp["wertung"]), "perfekt", "Fenster-Ende exklusiv bei 5.4")
	var spaet := McGoobySchichtLogic.bewerte_tap(5.4, timing, bal)
	assert_eq(str(spaet["wertung"]), "roestaroma", "danach Röstaroma-Spezial")
	assert_eq(int(spaet["punkte"]), 5, "halbe Punkte — nie verloren")
	var vergessen := McGoobySchichtLogic.bewerte_liegengelassen(bal)
	assert_eq(str(vergessen["wertung"]), "roestaroma", "liegen lassen = Röstaroma")
	assert_eq(McGoobySchichtLogic.zustand(0.0, timing), "roh")
	assert_eq(McGoobySchichtLogic.zustand(4.5, timing), "goldbraun")
	assert_eq(McGoobySchichtLogic.zustand(6.0, timing), "kohle")
	assert_almost(McGoobySchichtLogic.fortschritt(2.7, timing), 0.5, 1e-6)
	assert_almost(McGoobySchichtLogic.fortschritt(99.0, timing), 1.0, 1e-6, "geklemmt")


func test_abrechnung_combo_und_coin_table() -> void:
	var bal := McGoobyKatalog.balance()
	assert_almost(McGoobyAbrechnung.combo_mult(0, bal), 1.0)
	assert_almost(McGoobyAbrechnung.combo_mult(5, bal), 1.5)
	assert_almost(McGoobyAbrechnung.combo_mult(20, bal), 2.0, 1e-6, "Deckel ×2,0")
	assert_eq(McGoobyAbrechnung.muenzen_fuer(0, bal), 6, "coin_min greift")
	assert_eq(McGoobyAbrechnung.muenzen_fuer(40, bal), 10, "40/4")
	assert_eq(McGoobyAbrechnung.muenzen_fuer(9999, bal), 30, "coin_max deckelt")
	var kasse := (
		McGoobyAbrechnung
		. abrechnung(
			[
				{"punkte": 35, "fehlerfrei": true},
				{"punkte": 25, "fehlerfrei": true},
				{"punkte": 20, "fehlerfrei": false},
				{"punkte": 45, "fehlerfrei": true},
			],
			bal
		)
	)
	assert_eq(int(kasse["punkte"]), 125)
	assert_eq(int(kasse["trinkgeld"]), 6, "Kette 1,1/1,2 → Bruch → 1,1")
	assert_almost(float(kasse["combo_max_mult"]), 1.2)
	assert_eq(int(kasse["muenzen_basis"]), 30, "floor(125/4)=31 → Deckel 30")
	assert_eq(int(kasse["muenzen"]), 36)
	assert_eq(int(kasse["fehlerfreie"]), 3)


## ------------------------------------------------------------- Save-Slice


func test_state_slice_selfheal_und_verbuchen() -> void:
	var def := McGoobyState.default_slice()
	assert_eq(def["v"], 1)
	assert_false(bool(def["introGesehen"]))
	var geheilt := McGoobyState.normalize_slice({"introGesehen": 1, "schichten": "kaputt"})
	assert_true(bool(geheilt["introGesehen"]), "truthy wird bool")
	assert_eq(int((geheilt["schichten"] as Dictionary)["gespielt"]), 0, "kaputt → Default")
	assert_eq(McGoobyState.normalize_slice(null)["v"], 1, "null → Defaults")
	var gs := FakeGameState.new()
	assert_false(McGoobyState.ist_intro_gesehen(gs))
	McGoobyState.setze_intro_gesehen(gs)
	assert_true(McGoobyState.ist_intro_gesehen(gs))
	McGoobyState.schicht_verbuchen(gs, 60)
	McGoobyState.schicht_verbuchen(gs, 40)
	assert_eq(int(gs.get_value("mcgooby.schichten.gespielt", 0)), 2)
	assert_eq(int(gs.get_value("mcgooby.schichten.bestwert", 0)), 60, "Bestwert nie runter")


## ------------------------------------------------------------ Szene-Smoke


func test_route_zeigt_auf_existierende_szene() -> void:
	assert_eq(McGoobySchichtScene.ROUTE, &"mcgooby_schicht")
	var pfad := str(McGoobySchichtScene.ROUTES[McGoobySchichtScene.ROUTE])
	assert_eq(pfad, SCHICHT_SZENE)
	assert_true(FileAccess.file_exists(pfad), "Routen-Szene existiert")


func test_routen_helfer_registriert_und_reist() -> void:
	# Der EINE Hub-Aufruf (dlc_screen-Hunk): registriert + reist in einem Zug.
	var router := FakeRouter.new()
	McGoobyRouten.router_override = router
	var ok := McGoobyRouten.fahre_zur_schicht(null, {"seed": 7})
	McGoobyRouten.router_override = null
	assert_true(ok, "fahre_zur_schicht meldet Erfolg")
	assert_eq(str(router.routen.get(McGoobyRouten.ROUTE_SCHICHT, "")), SCHICHT_SZENE)
	assert_eq(router.reisen.size(), 1, "genau eine Reise")
	assert_eq(router.reisen[0]["ziel"], McGoobyRouten.ROUTE_SCHICHT)
	assert_eq(int((router.reisen[0]["params"] as Dictionary).get("seed", 0)), 7)
	# Ohne Router (kein Override, kein Baum): fail-closed statt Crash.
	assert_false(McGoobyRouten.fahre_zur_schicht(null), "ohne Router = false")


func test_schicht_szene_erststart_intro_und_komplette_schicht() -> void:
	McGoobyKatalog.reset_cache()
	var gs := FakeGameState.new()
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	# Erststart: Eröffnungs-Hook-Karte (Doc §1.3) liegt über der Schicht.
	assert_true(szene.ist_intro_offen(), "Intro-Karte beim Erststart")
	assert_false(szene.ist_am_laufen(), "Schicht wartet auf die Schürze")
	var schuerze: Button = szene.find_child("SchuerzeKnopf", true, false)
	assert_true(schuerze != null, "Intro-Knopf existiert")
	schuerze.pressed.emit()
	await wait_frames(1)
	assert_false(szene.ist_intro_offen(), "Intro schließt nach Bestätigung")
	assert_true(McGoobyState.ist_intro_gesehen(gs), "Erststart-Haken sitzt im Slice")
	assert_true(szene.ist_am_laufen(), "Schicht läuft")
	assert_eq(str(szene.bestellung_aktuell().get("rezept_id", "")), "garten_gooby")
	# Deterministisch durchspielen: jeden Patty im goldenen Fenster wenden.
	var timing := McGoobyKatalog.timing("grill")
	var sicherheit := 0
	while szene.ist_am_laufen() and sicherheit < 12:
		sicherheit += 1
		szene.patty_zeit_setzen(float(timing["gar_sec"]) + 0.2)
		szene.patty_knopf().pressed.emit()
		await wait_frames(1)
	assert_true(szene.ist_ende_offen(), "Schicht-Ende-Karte offen")
	var kasse := szene.schicht_ergebnis()
	assert_eq(int(kasse["punkte"]), 60, "3× Perfekt + 2× Fertig-Bonus (Goldwert)")
	assert_eq(int(kasse["muenzen"]), 19, "Kassensturz wie simulate_autoplay")
	assert_eq(int(gs.get_value("economy.coins", 0)), 19, "Münzen über Economy.award")
	assert_eq(int(gs.get_value("mcgooby.schichten.gespielt", 0)), 1, "Schicht verbucht")
	assert_eq(int(gs.get_value("mcgooby.schichten.bestwert", 0)), 60)
	szene.queue_free()
	await wait_frames(1)
	# Zweitstart mit demselben Spielstand: KEIN Intro mehr, Schicht sofort.
	var szene2: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene2.gs_override = gs
	szene2.seed_override = GOLD_SEED
	szene2.auto_navigate = false
	tree.root.add_child(szene2)
	await wait_frames(3)
	assert_false(szene2.ist_intro_offen(), "Zweitstart ohne Intro")
	assert_true(szene2.ist_am_laufen(), "Schicht startet direkt")
	szene2.queue_free()
	await wait_frames(1)


func test_schicht_szene_pause_und_roestaroma() -> void:
	McGoobyKatalog.reset_cache()
	var gs := FakeGameState.new()
	gs.set_value("mcgooby.introGesehen", true)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(szene.ist_am_laufen())
	# Pause: Modal öffnet, Schicht friert ein; Fortsetzen taut auf (§2.4).
	var pause: Button = szene.find_child("Pause", true, false)
	pause.pressed.emit()
	await wait_frames(1)
	assert_false(szene.ist_am_laufen(), "pausiert = eingefroren")
	var modal: MinigamePauseModal = szene.find_child("PauseModal", true, false)
	assert_true(modal != null and modal.is_open(), "Pause-Modal offen")
	modal.close()
	await wait_frames(1)
	assert_true(szene.ist_am_laufen(), "Fortsetzen taut auf")
	# Zu spätes Wenden: Röstaroma-Spezial (halbe Punkte, kein Fail).
	var timing := McGoobyKatalog.timing("grill")
	var spaet := float(timing["gar_sec"]) + float(timing["fenster_sec"]) + 0.1
	szene.patty_zeit_setzen(spaet)
	szene.patty_knopf().pressed.emit()
	await wait_frames(1)
	assert_true(szene.ist_am_laufen(), "Schicht läuft nach Röstaroma weiter")
	var punkte: Label = szene.find_child("Punkte", true, false)
	assert_true(punkte.text.contains("20"), "5 Röstaroma + 15 Fertig-Bonus verbucht")
	szene.queue_free()
	await wait_frames(1)


func test_schicht_szene_geometrie_grundcheck() -> void:
	McGoobyKatalog.reset_cache()
	var gs := FakeGameState.new()
	gs.set_value("mcgooby.introGesehen", true)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(4)
	var m := ScreenShell.metrics(szene.get_viewport())
	var floor_px := float(m["floor_px"])
	var canvas: Vector2 = m["canvas"]
	# Touch-Floor: Patty-Knopf und Header-Knöpfe sind echte Tippflächen.
	var patty := szene.patty_knopf()
	assert_true(patty.size.x >= floor_px - 0.5, "Patty-Knopf ≥ Touch-Floor (x)")
	assert_true(patty.size.y >= floor_px - 0.5, "Patty-Knopf ≥ Touch-Floor (y)")
	for knopf_name: String in ["Zurueck", "Pause"]:
		var knopf: Button = szene.find_child(knopf_name, true, false)
		assert_true(knopf.size.y >= floor_px - 0.5, "%s ≥ Touch-Floor" % knopf_name)
	# Bedienelement mittig: der Patty sitzt horizontal in der Bildschirmmitte.
	var patty_mitte := patty.get_global_rect().get_center()
	assert_true(
		absf(patty_mitte.x - canvas.x / 2.0) <= 4.0,
		"Patty horizontal zentriert (Δ=%f)" % absf(patty_mitte.x - canvas.x / 2.0)
	)
	assert_true(patty_mitte.y > canvas.y * 0.33, "Patty in der unteren Daumen-Hälfte")
	# Hintergrund vollflächig: das Wallpaper deckt den ganzen Canvas.
	var wallpaper: Control = szene.find_child("Wallpaper", true, false)
	assert_true(wallpaper != null, "Wallpaper existiert")
	var rect := wallpaper.get_global_rect()
	assert_true(rect.position.x <= 0.5 and rect.position.y <= 0.5, "Wallpaper ab (0,0)")
	assert_true(rect.size.x >= canvas.x - 1.0 and rect.size.y >= canvas.y - 1.0, "vollflächig")
	# Inhaltsspalte trägt das W16-Meta (FB3-Audit-Kontrakt).
	var spalte: Control = szene.find_child("Spalte", true, false)
	assert_true(spalte.has_meta(ScreenShell.META_CONTENT_COLUMN), "Content-Column-Meta")
	szene.queue_free()
	await wait_frames(1)
