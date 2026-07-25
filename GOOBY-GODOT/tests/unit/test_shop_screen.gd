extends TestCase
## CONTENT-B — der IKEA-Screen selbst: Regalliste, Kategorie-Chips, Suche,
## Vitrine (3D-Modell + Feldplatte + Drehen/Zoomen), Farbmuster und der
## Kaufknopf, der die Münzen wirklich abbucht. Dazu die Route/HUD-Verdrahtung
## nach dem ArcadeScreen-Muster.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const WINDOW := Vector2i(1280, 800)

var _seq := 0
var _root_size := Vector2i.ZERO


class FakeRouter:
	extends Node

	var routes: Dictionary = {}
	var went: Array = []

	func register_routes(new_routes: Dictionary) -> void:
		for key: Variant in new_routes:
			routes[key] = new_routes[key]

	func goto(target: StringName, params: Dictionary = {}) -> void:
		went.append({"target": target, "params": params})


func _fresh_gs(coins := 5000) -> Node:
	_seq += 1
	var dir := "user://contentb_screen_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


## Screen im Baum, mit eigenem GameState und ohne Drehteller (deterministisch).
## Das Root-Fenster ist headless nur 64×64 — für echtes GUI-Input-Routing
## (Ziehen in der Vitrine) muss es auf Screengröße wachsen.
func _mount(gs: Node) -> IkeaScreen:
	_root_size = tree.root.size
	tree.root.size = WINDOW
	var screen := IkeaScreen.new()
	screen.game_state_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	screen.showcase().set_spin_enabled(false)
	return screen


func _drop(screen: IkeaScreen, gs: Node) -> void:
	screen.queue_free()
	await wait_frames(2)
	tree.root.size = _root_size
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _rows(screen: IkeaScreen) -> Array:
	var out: Array = []
	for child in screen.find_child("ItemList", true, false).get_children():
		if child is Button:
			out.append(child)
	return out


func test_regal_ist_gefuellt_und_zeigt_preise() -> void:
	var gs := _fresh_gs()
	var screen := await _mount(gs)
	var rows := _rows(screen)
	assert_eq(rows.size(), ShopCatalog.filter("").size(), "jede Ladenware hat eine Zeile")
	assert_true(rows.size() >= 145, "SEHR viele Möbel im Regal (%d)" % rows.size())
	assert_true(str(rows[0].text).contains("Münzen"), "Zeile nennt den Preis: %s" % rows[0].text)
	assert_ne(screen.selected_id(), "", "das erste Möbel steht schon in der Vitrine")
	await _drop(screen, gs)


func test_kategorie_chips_und_suche_filtern() -> void:
	var gs := _fresh_gs()
	var screen := await _mount(gs)
	screen.set_kategorie("kueche")
	await wait_frames(2)
	var kueche := _rows(screen)
	assert_eq(kueche.size(), ShopCatalog.by_category("kueche").size())
	assert_true(kueche.size() >= 10, "Küche gut bestückt (%d)" % kueche.size())
	screen.set_kategorie(IkeaScreen.CATEGORY_ALL)
	screen.set_search("toast")
	await wait_frames(2)
	var treffer := _rows(screen)
	assert_true(treffer.size() >= 1, "Suche nach 'toast' findet etwas")
	assert_true(str(treffer[0].text).to_lower().contains("toaster"), treffer[0].text)
	screen.set_search("zzzgibtesnicht")
	await wait_frames(2)
	assert_true(_rows(screen).is_empty(), "kein Treffer = keine Zeilen")
	assert_true(
		screen.find_child("ItemList", true, false).get_child_count() >= 1, "Leer-Hinweis steht da"
	)
	screen.set_search("")
	await wait_frames(2)
	assert_true(_rows(screen).size() >= 145, "Suche zurückgesetzt")
	await _drop(screen, gs)


func test_vitrine_zeigt_modell_platte_und_laesst_sich_drehen() -> void:
	var gs := _fresh_gs()
	var screen := await _mount(gs)
	screen.select_item("toaster")
	await wait_frames(2)
	var showcase := screen.showcase()
	assert_true(showcase.model() != null, "3D-Modell steht in der Vitrine")
	var vorher := showcase.get_yaw()
	var mitte := showcase.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = mitte
	tree.root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = mitte + Vector2(120.0, 0.0)
	motion.relative = Vector2(120.0, 0.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	tree.root.push_input(motion)
	await wait_frames(1)
	assert_ne(showcase.get_yaw(), vorher, "Ziehen dreht das Möbel")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	tree.root.push_input(release)
	# Zoom über den Slider (und die Grenzen halten).
	showcase.set_zoom(FurnitureShowcase.ZOOM_MIN - 5.0)
	assert_almost(showcase.get_zoom(), FurnitureShowcase.ZOOM_MIN, 1e-4)
	showcase.set_zoom(1.4)
	assert_almost(showcase.get_zoom(), 1.4, 1e-4)
	# Feldplatte: ein Kästchen je belegtem Grid-Feld eines 2×3-Möbels.
	screen.select_item("bedSingle")
	await wait_frames(2)
	var kacheln := 0
	for child in showcase.model().get_parent().get_children():
		if child is FurnitureNode:
			continue
		kacheln += child.get_child_count()
	assert_eq(kacheln, 6, "2×3 Möbel = 6 Feld-Kästchen")
	assert_true(
		str(screen.find_child("FootprintLabel", true, false).text).contains("2×3"),
		"Text nennt die belegten Felder"
	)
	await _drop(screen, gs)


func test_farbvarianten_faerben_das_modell() -> void:
	var gs := _fresh_gs()
	var screen := await _mount(gs)
	screen.select_item("toaster")
	await wait_frames(2)
	var swatches := screen.find_child("Swatches", true, false)
	assert_true(swatches.get_child_count() >= 4, "mind. 4 Farbmuster")
	assert_eq(screen.selected_variant(), FurnitureVariants.DEFAULT_ID, "Start = Natur")
	screen.select_variant("mint")
	await wait_frames(2)
	assert_eq(screen.selected_variant(), "mint")
	var getoent := false
	for node in _meshes(screen.showcase().model()):
		for surface in node.mesh.get_surface_count():
			if node.get_surface_override_material(surface) != null:
				getoent = true
	assert_true(getoent, "Tint liegt als Override auf dem Modell")
	screen.select_variant(FurnitureVariants.DEFAULT_ID)
	await wait_frames(2)
	for node in _meshes(screen.showcase().model()):
		for surface in node.mesh.get_surface_count():
			assert_true(
				node.get_surface_override_material(surface) == null, "Natur räumt Overrides ab"
			)
	# Möbelwechsel setzt die Farbe zurück, damit nichts „mitfärbt“.
	screen.select_variant("rose")
	screen.select_item("chair")
	await wait_frames(2)
	assert_eq(screen.selected_variant(), FurnitureVariants.DEFAULT_ID)
	await _drop(screen, gs)


func test_kaufen_bucht_ab_und_aktualisiert_die_kopfzeile() -> void:
	var gs := _fresh_gs(500)
	var screen := await _mount(gs)
	screen.select_item("toaster")
	await wait_frames(2)
	var farbe := str(FurnitureVariants.ids_for(ShopCatalog.def("toaster"))[1])
	screen.select_variant(farbe)
	var preis := ShopPurchase.price_of("toaster")
	var gekauft: Array = []
	screen.item_bought.connect(
		func(id: String, variant: String) -> void: gekauft.append([id, variant])
	)
	assert_eq(screen.buy_selected(), ShopPurchase.RESULT_OK)
	await wait_frames(2)
	assert_eq(int(gs.get_value("economy.coins", 0)), 500 - preis)
	assert_eq(gekauft.size(), 1, "Signal gefeuert")
	assert_eq(str(gekauft[0][1]), farbe, "gewählte Farbe im Signal")
	var storage: Array = gs.get_value("home.storage", [])
	assert_eq(str(storage[0]["item"]), "toaster")
	assert_eq(str(storage[0]["variant"]), farbe, "Farbe liegt im Lager")
	var coins_label: Label = screen.find_child("CoinsLabel", true, false)
	assert_true(str(coins_label.text).contains(str(500 - preis)), coins_label.text)
	# Pleite: Knopf sperrt, State bleibt.
	gs.set_value("economy.coins", 0)
	screen.select_item("toaster")
	await wait_frames(2)
	var buy_button: Button = screen.find_child("BuyButton", true, false)
	assert_true(buy_button.disabled, "Kaufknopf ist gesperrt")
	assert_eq(screen.buy_selected(), ShopPurchase.RESULT_BROKE)
	assert_eq(int(gs.get_value("economy.coins", 0)), 0)
	await _drop(screen, gs)


func test_route_und_hud_action() -> void:
	# Der echte SceneRouter ist ein Autoload — für den Test wird er kurz
	# umbenannt, damit /root/SceneRouter auf die Attrappe zeigt (sonst würde
	# handle_hud_action eine echte Szenen-Reise starten).
	var echt := tree.root.get_node_or_null(NodePath("SceneRouter"))
	if echt != null:
		echt.name = "SceneRouterGeparkt"
	var router := FakeRouter.new()
	router.name = "SceneRouter"
	tree.root.add_child(router)
	assert_false(IkeaScreen.handle_hud_action(&"arcade"), "fremde Action bleibt liegen")
	assert_true(IkeaScreen.handle_hud_action(IkeaScreen.HUD_ACTION), "eigene Action konsumiert")
	assert_eq(
		str(router.routes.get(IkeaScreen.ROUTE_IKEA, "")),
		"res://scripts/shop/ikea_screen.tscn",
		"Route angemeldet"
	)
	assert_eq(router.went.size(), 1)
	assert_eq(router.went[0]["target"], IkeaScreen.ROUTE_IKEA)
	assert_true(ResourceLoader.exists(str(IkeaScreen.ROUTES[IkeaScreen.ROUTE_IKEA])), "Szene da")
	tree.root.remove_child(router)
	router.free()
	if echt != null:
		echt.name = "SceneRouter"


func test_szene_laedt_und_baut_sich() -> void:
	# Der Router mountet die .tscn — der Weg über PackedScene muss stehen.
	var scene: PackedScene = load(str(IkeaScreen.ROUTES[IkeaScreen.ROUTE_IKEA]))
	assert_true(scene != null, "ikea_screen.tscn lädt")
	var screen: Variant = scene.instantiate()
	assert_true(screen is IkeaScreen, "Szene trägt das Skript")
	_root_size = tree.root.size
	tree.root.size = WINDOW
	tree.root.add_child(screen)
	await wait_frames(2)
	assert_ne(screen.selected_id(), "", "Vitrine ist bestückt")
	assert_true(screen.showcase().model() != null, "3D-Modell steht")
	assert_true(screen.find_child("BuyButton", true, false) != null, "Kaufknopf da")
	assert_true(screen.find_child("Swatches", true, false).get_child_count() >= 4, "Farbmuster da")
	screen.queue_free()
	await wait_frames(2)
	tree.root.size = _root_size


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root == null:
		return out
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
