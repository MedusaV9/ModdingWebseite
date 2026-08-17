extends TestCase
## CONTENT-A — der Garderoben-Screen als Ganzes.
##
## Kein Pixel-Test (dafür gibt es die xvfb-Screenshots), sondern der Beweis,
## dass der Bildschirm sich baut und dass ein Tap auf eine Karte wirklich im
## Spielstand landet: kaufen, anziehen, ausziehen. Der Screen läuft dabei auf
## einem EIGENEN GameState (`game_state_override`), damit der Test den echten
## Spielstand nicht anfasst.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const WardrobeSzene := preload("res://scripts/cosmetics/wardrobe_screen.tscn")


func test_route_zeigt_auf_eine_echte_szene() -> void:
	var pfad: String = WardrobeScreen.ROUTES[WardrobeScreen.ROUTE_WARDROBE]
	assert_true(ResourceLoader.exists(pfad), "Route-Ziel existiert: %s" % pfad)


func test_hud_action_ignoriert_fremde_knoepfe() -> void:
	# Alle Screens hängen an derselben `action_pressed`-Leitung: wer fremde
	# Actions schluckt, verschluckt den Arcade-Knopf gleich mit.
	assert_false(WardrobeScreen.handle_hud_action(&"arcade"), "fremde Action wird durchgereicht")
	assert_false(WardrobeScreen.handle_hud_action(&"album"), "fremde Action wird durchgereicht")


func test_screen_baut_sich_und_zeigt_alle_tabs() -> void:
	var screen := await _screen()
	var tabs: Node = screen.get("_tab_box")
	assert_eq(tabs.get_child_count(), CosmeticsCatalog.KATEGORIEN.size(), "ein Tab pro Kategorie")
	for kategorie: String in CosmeticsCatalog.KATEGORIEN:
		screen.call("tab_waehlen", kategorie)
		var grid: Node = screen.get("_grid")
		assert_eq(
			grid.get_child_count(),
			CosmeticsCatalog.by_kategorie(kategorie).size(),
			"%s: jede Karte des Katalogs liegt im Grid" % kategorie
		)
	_aufraeumen(screen)


func test_tap_kauft_zieht_an_und_wieder_aus() -> void:
	var screen := await _screen(5000)
	screen.call("tab_waehlen", "hut")
	var id := _erstes_kaufbares("hut")
	assert_false(id.is_empty(), "es gibt einen kaufbaren Hut zum Testen")

	var kauf: Dictionary = screen.call("item_tippen", id)
	assert_true(bool(kauf["ok"]), "erster Tap kauft: %s" % str(kauf.get("grund", "")))
	assert_eq(str(screen.call("getragen")["hut"]), id, "…und setzt den Hut direkt auf")
	var rest: int = int(screen.get("_gs").get_value("economy.coins", 0))
	assert_eq(rest, 5000 - int(CosmeticsCatalog.by_id(id)["preis"]), "Münzen sind abgebucht")

	screen.call("item_tippen", id)
	assert_eq(str(screen.call("getragen")["hut"]), "", "zweiter Tap legt ab")
	assert_eq(
		int(screen.get("_gs").get_value("economy.coins", 0)), rest, "Ablegen kostet nichts mehr"
	)
	screen.call("item_tippen", id)
	assert_eq(
		str(screen.call("getragen")["hut"]), id, "dritter Tap zieht wieder an (schon bezahlt)"
	)
	assert_eq(int(screen.get("_gs").get_value("economy.coins", 0)), rest, "…und zwar gratis")
	_aufraeumen(screen)


func test_ohne_muenzen_passiert_nichts() -> void:
	var screen := await _screen(0)
	screen.call("tab_waehlen", "hut")
	var id := _erstes_kaufbares("hut")
	var kauf: Dictionary = screen.call("item_tippen", id)
	assert_false(bool(kauf["ok"]), "pleite = kein Kauf")
	assert_eq(str(kauf["grund"]), "zu_teuer", "Grund benannt")
	assert_eq(str(screen.call("getragen")["hut"]), "", "nichts angezogen")
	_aufraeumen(screen)


func test_gesperrte_karten_sind_da_aber_nicht_drueckbar() -> void:
	var screen := await _screen(99999)
	var gesperrt := ""
	for kategorie: String in CosmeticsCatalog.KATEGORIEN:
		screen.call("tab_waehlen", kategorie)
		for def: Dictionary in CosmeticsCatalog.by_kategorie(kategorie):
			if int(def["min_level"]) <= 1:
				continue
			gesperrt = str(def["id"])
			var karte: Node = screen.get("_grid").get_node_or_null("Item_%s" % gesperrt)
			assert_true(karte != null, "%s liegt sichtbar im Grid" % gesperrt)
			assert_true(bool(karte.get("disabled")), "%s ist gesperrt, nicht versteckt" % gesperrt)
			break
		if not gesperrt.is_empty():
			break
	assert_false(gesperrt.is_empty(), "der Katalog hat level-gesperrte Items zum Prüfen")
	_aufraeumen(screen)


func _erstes_kaufbares(kategorie: String) -> String:
	for def: Dictionary in CosmeticsCatalog.by_kategorie(kategorie):
		if not def["standard"] and int(def["preis"]) > 0 and int(def["min_level"]) <= 1:
			return str(def["id"])
	return ""


func _screen(coins := 1000) -> Node:
	var dir := "user://contenta_wardrobe_test/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	var screen: Node = WardrobeSzene.instantiate()
	screen.set("game_state_override", gs)
	screen.set("auto_navigate", false)
	screen.set_meta("gs", gs)
	tree.root.add_child(screen)
	await tree.process_frame
	return screen


func _aufraeumen(screen: Node) -> void:
	var gs: Variant = screen.get_meta("gs")
	tree.root.remove_child(screen)
	screen.queue_free()
	if gs is Node:
		(gs as Node).free()
