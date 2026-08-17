extends TestCase
## CONTENT-B — Kauf-Logik der Möbelausstellung: Münzen runter, Möbel ins LAGER
## (nicht in den Raum), Farbvariante reist mit, und beides passiert atomar.
## Läuft gegen einen echten GameState mit eigener Save-Datei (kein Autoload).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
## Ein günstiges Deko-Möbel und ein teures Möbel aus dem neuen Bestand.
const CHEAP := "toaster"

var _seq := 0


func _fresh_gs(coins := 1000) -> Node:
	_seq += 1
	var dir := "user://contentb_shop_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


func _drop(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _storage(gs: Node) -> Array:
	var raw: Variant = gs.get_value("home.storage", [])
	return raw if raw is Array else []


func test_kauf_bucht_muenzen_ab_und_legt_ins_lager() -> void:
	var gs := _fresh_gs()
	var preis := ShopPurchase.price_of(CHEAP)
	assert_true(preis > 0, "Testmöbel hat einen Preis")
	assert_eq(ShopPurchase.buy(gs, CHEAP), ShopPurchase.RESULT_OK)
	assert_eq(int(gs.get_value("economy.coins", 0)), 1000 - preis, "Münzen abgebucht")
	var storage := _storage(gs)
	assert_eq(storage.size(), 1, "genau eine Lagerzeile")
	assert_eq(str(storage[0]["item"]), CHEAP)
	assert_eq(int(storage[0]["count"]), 1)
	assert_eq(str(storage[0]["variant"]), FurnitureVariants.DEFAULT_ID, "Default ist 'natur'")
	# Zweiter Kauf derselben Variante wird zusammengefasst.
	assert_eq(ShopPurchase.buy(gs, CHEAP), ShopPurchase.RESULT_OK)
	assert_eq(int(_storage(gs)[0]["count"]), 2, "gleiche Zeile hochgezählt")
	assert_eq(int(gs.get_value("economy.coins", 0)), 1000 - 2 * preis)
	_drop(gs)


func test_variante_reist_ins_lager_mit() -> void:
	var gs := _fresh_gs()
	assert_eq(ShopPurchase.buy(gs, CHEAP, "mint"), ShopPurchase.RESULT_OK)
	assert_eq(ShopPurchase.buy(gs, CHEAP, "rose"), ShopPurchase.RESULT_OK)
	var storage := _storage(gs)
	assert_eq(storage.size(), 2, "verschiedene Farben = verschiedene Lagerzeilen")
	var farben := {}
	for entry: Variant in storage:
		farben[str((entry as Dictionary)["variant"])] = true
	assert_true(farben.has("mint") and farben.has("rose"), "beide Farben gespeichert")
	# Eine Farbe, die das Möbel nicht führt, fällt weich auf "natur" zurück.
	assert_eq(ShopPurchase.buy(gs, CHEAP, "gibtsnicht"), ShopPurchase.RESULT_OK)
	assert_eq(str(_storage(gs)[2]["variant"]), FurnitureVariants.DEFAULT_ID)
	_drop(gs)


func test_zu_wenig_muenzen_aendert_gar_nichts() -> void:
	var gs := _fresh_gs(1)
	assert_eq(ShopPurchase.check(gs, CHEAP), ShopPurchase.RESULT_BROKE)
	assert_false(ShopPurchase.can_buy(gs, CHEAP))
	assert_eq(ShopPurchase.buy(gs, CHEAP), ShopPurchase.RESULT_BROKE)
	assert_eq(int(gs.get_value("economy.coins", 0)), 1, "Münzen unangetastet")
	assert_true(_storage(gs).is_empty(), "nichts im Lager")
	_drop(gs)


func test_volles_lager_blockt_den_kauf() -> void:
	var gs := _fresh_gs(999_999)
	gs.set_value("home.storageCapacity", 2)
	var lagerwert := int(ShopCatalog.def(CHEAP)["lagerwert"])
	assert_true(lagerwert <= 2, "Toaster ist leichtes Deko-Gut")
	assert_eq(ShopPurchase.buy(gs, CHEAP), ShopPurchase.RESULT_OK)
	var muenzen_nachher := int(gs.get_value("economy.coins", 0))
	# Ab hier ist kein Platz mehr für ein zweites Exemplar.
	gs.set_value("home.storageCapacity", lagerwert)
	assert_eq(ShopPurchase.check(gs, CHEAP), ShopPurchase.RESULT_FULL)
	assert_eq(ShopPurchase.buy(gs, CHEAP), ShopPurchase.RESULT_FULL)
	assert_eq(int(gs.get_value("economy.coins", 0)), muenzen_nachher, "kein Geld verbrannt")
	assert_eq(int(_storage(gs)[0]["count"]), 1, "kein Phantom-Möbel")
	_drop(gs)


func test_storage_free_zaehlt_lagerpunkte() -> void:
	var gs := _fresh_gs()
	gs.set_value("home.storageCapacity", 10)
	assert_eq(ShopPurchase.storage_free(gs), 10)
	ShopPurchase.buy(gs, CHEAP)
	var lagerwert := int(ShopCatalog.def(CHEAP)["lagerwert"])
	assert_eq(ShopPurchase.storage_free(gs), 10 - lagerwert, "Lagerwert zieht ab")
	_drop(gs)


func test_unbekanntes_und_unverkaeufliches_moebel() -> void:
	var gs := _fresh_gs()
	assert_eq(ShopPurchase.check(gs, "gibtEsNichtXY"), ShopPurchase.RESULT_UNKNOWN)
	assert_eq(ShopPurchase.buy(gs, "gibtEsNichtXY"), ShopPurchase.RESULT_UNKNOWN)
	assert_eq(ShopPurchase.price_of("gibtEsNichtXY"), 0)
	# Werkstatt-Möbel (Preis 0) sind im Katalog, dürfen aber nicht gratis über
	# die Ladentheke gehen.
	var gratis := ""
	for id: String in ShopCatalog.ids():
		if not ShopCatalog.sellable(ShopCatalog.def(id)):
			gratis = id
			break
	if gratis != "":
		assert_eq(ShopPurchase.buy(gs, gratis), ShopPurchase.RESULT_UNKNOWN, "%s" % gratis)
		assert_true(_storage(gs).is_empty(), "nichts eingesackt")
	_drop(gs)


func test_ohne_gamestate_kein_absturz() -> void:
	assert_eq(ShopPurchase.check(null, CHEAP), ShopPurchase.RESULT_UNKNOWN)
	assert_eq(ShopPurchase.buy(null, CHEAP), ShopPurchase.RESULT_UNKNOWN)
	assert_eq(ShopPurchase.storage_free(null), 0)


func test_gekauftes_moebel_laesst_sich_bauen() -> void:
	# Ende-zu-Ende: was im Laden liegt, muss der Baumodus auch instanziieren
	# können (gleiche Def, gleicher GLB-Pfad).
	var gs := _fresh_gs(999_999)
	assert_eq(ShopPurchase.buy(gs, CHEAP, "himmel"), ShopPurchase.RESULT_OK)
	var eintrag: Dictionary = _storage(gs)[0]
	var item := ShopCatalog.def(str(eintrag["item"]))
	var node := FurnitureNode.create(item, Vector2i.ZERO, 0, "kauf")
	assert_true(node != null, "Möbel baut sich")
	if node != null:
		FurnitureVariants.apply(node, str(eintrag["variant"]))
		node.free()
	_drop(gs)
