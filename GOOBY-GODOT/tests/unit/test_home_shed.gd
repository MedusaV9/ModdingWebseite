extends TestCase
## M2 HAUS — Shed-Stufen (Doc D §2.3): PURE Kapazitäts-/Preistabelle plus
## das Upgrade am GameState (Münzen weg, Lagerkapazität hoch) und die
## Fenster-/Außenwand-Regel der Wand-Items (Doc D §1.2).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://m2_shed_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_kapazitaetsstufen() -> void:
	assert_eq(ShedLogic.kapazitaet(0), 100)
	assert_eq(ShedLogic.kapazitaet(1), 150)
	assert_eq(ShedLogic.kapazitaet(2), 200)
	assert_eq(ShedLogic.kapazitaet(3), 300)
	assert_eq(ShedLogic.kapazitaet(9), 300, "über Maximum wird geklemmt")
	assert_eq(ShedLogic.kapazitaet(-2), 100, "unter Null auch")
	for stufe in range(0, ShedLogic.MAX_STUFE):
		assert_true(
			ShedLogic.kapazitaet(stufe + 1) > ShedLogic.kapazitaet(stufe),
			"Stufe %d bringt mehr Platz" % (stufe + 1)
		)


func test_upgrade_preise() -> void:
	assert_eq(ShedLogic.upgrade_preis(0), 500)
	assert_eq(ShedLogic.upgrade_preis(2), 4000)
	assert_eq(ShedLogic.upgrade_preis(ShedLogic.MAX_STUFE), 0, "maximal ausgebaut")
	assert_false(ShedLogic.kann_upgraden(0, 499))
	assert_true(ShedLogic.kann_upgraden(0, 500))
	assert_false(ShedLogic.kann_upgraden(ShedLogic.MAX_STUFE, 99_999))


func test_modelle_werden_sichtbar_groesser() -> void:
	var vorher := 0.0
	for stufe in range(1, ShedLogic.MAX_STUFE + 1):
		var modell := ShedLogic.modell(stufe)
		assert_true(float(modell["hoehe"]) > vorher, "Stufe %d ist höher" % stufe)
		vorher = float(modell["hoehe"])
	assert_false(bool(ShedLogic.modell(1)["fenster"]))
	assert_true(bool(ShedLogic.modell(2)["fenster"]), "ab Stufe 2 mit Fenster")
	assert_true(bool(ShedLogic.modell(3)["wetterhahn"]), "Stufe 3 kriegt den Wetterhahn")


func test_upgrade_am_gamestate() -> void:
	var gs := _fresh_gs()
	assert_eq(HomeState.shed_stufe(gs), 0)
	assert_eq(HomeState.storage_capacity(gs), ShedLogic.BASIS_KAPAZITAET)
	gs.set_value("economy.coins", 499)
	assert_eq(HomeState.upgrade_shed(gs), 0, "zu wenig Münzen")
	assert_eq(HomeState.storage_capacity(gs), ShedLogic.BASIS_KAPAZITAET)
	gs.set_value("economy.coins", 2200)
	assert_eq(HomeState.upgrade_shed(gs), 1)
	assert_eq(int(gs.get_value("economy.coins", 0)), 1700)
	assert_eq(HomeState.storage_capacity(gs), 150, "mehr Lagerplatz")
	assert_eq(HomeState.upgrade_shed(gs), 2)
	assert_eq(HomeState.storage_capacity(gs), 200)
	assert_eq(HomeState.upgrade_shed(gs), 2, "Stufe 3 kostet 4000 — reicht nicht")
	_teardown(gs)


func test_mehr_lagerplatz_nimmt_mehr_moebel() -> void:
	var gs := _fresh_gs()
	gs.set_value("home.storage", [])
	gs.set_value("home.storageCapacity", ShedLogic.kapazitaet(0))
	var def := FurnitureCatalog.def("loungeSofa")
	var wert := int(def["lagerwert"])
	var passt := ShedLogic.kapazitaet(0) / wert
	for _i in passt:
		assert_true(HomeState.store_item(gs, "loungeSofa"))
	assert_false(HomeState.store_item(gs, "loungeSofa"), "Lager ist voll")
	gs.set_value("economy.coins", 500)
	assert_eq(HomeState.upgrade_shed(gs), 1)
	assert_true(HomeState.store_item(gs, "loungeSofa"), "nach dem Ausbau passt mehr")
	_teardown(gs)


func test_fenster_nur_auf_aussenwaende() -> void:
	var fenster := FurnitureCatalog.def("window_small")
	assert_true(bool(fenster["exterior"]), "Fenster ist ein Außenwand-Item")
	assert_eq(int(fenster["layer"]), GridData.Layer.WALL)
	assert_eq(str(fenster["vista"]), "strasse")
	var wohnzimmer := RoomDefs.exterior_walls(RoomDefs.room("living"))
	assert_eq(str(wohnzimmer.get("N", "")), "strasse", "Wohnzimmer-Nordwand geht zur Straße")
	var grid := RoomDefs.make_grid("living")
	assert_true(grid.can_place_wall(fenster, "N", 0, "")["ok"], "Nordwand ist außen")
	var innen := grid.can_place_wall(fenster, "S", 0, "")
	assert_false(innen["ok"], "Innenwand bekommt kein Fenster")
	assert_eq(str(innen["reason"]), GridData.REASON_NEEDS_EXTERIOR)
	var lampe := FurnitureCatalog.def("lampWall")
	assert_false(bool(lampe.get("exterior", false)))
	assert_true(grid.can_place_wall(lampe, "S", 0, "")["ok"], "Lampen dürfen überall hängen")
