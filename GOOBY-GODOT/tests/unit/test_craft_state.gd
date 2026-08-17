extends TestCase
## M2 HAUS — Werkstatt/Crafting am echten GameState (Doc D §5): additive
## Save-Keys, Baumarkt-Kauf, Craft legt ins Lager, Werkstatt-Pflicht.
## Jeder Test räumt die Slice-Registry wieder ab (prozessweit).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://m2_craft_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
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


## Werkstatt ohne Bau-Animation direkt in den Garten stellen.
func _werkstatt_bauen(gs: Node) -> void:
	var grid := GardenState.grid(gs)
	grid.place_structure("werkstatt", Vector2i(0, 0))
	GardenState.save_grid(gs, grid)


func test_additive_keys_im_frischen_save() -> void:
	var gs := _fresh_gs()
	assert_eq(CraftState.materials(gs), {})
	assert_eq(CraftState.blueprints(gs), [])
	assert_eq(HomeState.shed_stufe(gs), 0)
	assert_eq(DeliveryCutscene.offene(gs), [])
	assert_false(CraftState.werkstatt_gebaut(gs))
	_teardown(gs)


func test_alter_save_ohne_m2_keys_heilt() -> void:
	var geheilt := HomeState.normalize_slice(
		{"rooms": {}, "storage": [], "storageCapacity": 100, "materials": {"holz": -3}}
	)
	assert_eq(geheilt["materials"], {"holz": 0}, "negative Mengen werden geklemmt")
	assert_eq(geheilt["blueprints"], [])
	assert_eq(geheilt["shedStufe"], 0)
	assert_eq(geheilt["lieferungen"], [])
	assert_true(geheilt["garden"] is Dictionary)
	assert_true(geheilt["goobay"] is Dictionary)
	assert_eq(geheilt["storageCapacity"], 100, "Kapazität bleibt — nur ein Shed-Upgrade ändert sie")


func test_material_kaufen_bucht_muenzen() -> void:
	var gs := _fresh_gs()
	gs.set_value("economy.coins", 100)
	assert_false(CraftState.kaufe_material(gs, "holz", 1), "Holz gibt es nicht im Baumarkt")
	assert_true(CraftState.kaufe_material(gs, "naegel", 4))
	assert_eq(CraftState.material_count(gs, "naegel"), 4)
	assert_eq(int(gs.get_value("economy.coins", 0)), 100 - 4 * 15)
	assert_false(CraftState.kaufe_material(gs, "eisen", 2), "80 ᴳ sind zu viel für den Rest")
	assert_eq(CraftState.material_count(gs, "eisen"), 0)
	_teardown(gs)


func test_bauplan_nur_einmal() -> void:
	var gs := _fresh_gs()
	assert_true(CraftState.add_blueprint(gs, "bp_gartentisch"))
	assert_false(CraftState.add_blueprint(gs, "bp_gartentisch"), "kein Duplikat")
	assert_true(CraftState.has_blueprint(gs, "bp_gartentisch"))
	_teardown(gs)


func test_craft_braucht_werkstatt_und_legt_ins_lager() -> void:
	var gs := _fresh_gs()
	CraftState.add_material(gs, "holz", 2)
	CraftState.add_material(gs, "naegel", 4)
	var ohne := CraftState.craft(gs, "r_hocker_rustikal")
	assert_false(ohne["ok"])
	assert_eq(ohne["reason"], CraftLogic.REASON_STATION)
	_werkstatt_bauen(gs)
	assert_true(CraftState.werkstatt_gebaut(gs))
	var vorher := StorageLogic.count_of(HomeState.storage(gs), "stool_rustic")
	var ergebnis := CraftState.craft(gs, "r_hocker_rustikal")
	assert_true(ergebnis["ok"], "Craft mit Werkstatt + Material")
	assert_eq(ergebnis["item"], "stool_rustic")
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "stool_rustic"),
		vorher + 1,
		"gecraftetes Möbel liegt im LAGER"
	)
	assert_eq(CraftState.materials(gs), {}, "Material ist verbraucht")
	_teardown(gs)


func test_craft_mehrfach_ausgabe() -> void:
	var gs := _fresh_gs()
	_werkstatt_bauen(gs)
	CraftState.add_material(gs, "stock", 2)
	CraftState.add_material(gs, "holz", 1)
	CraftState.add_material(gs, "naegel", 4)
	var ergebnis := CraftState.craft(gs, "r_zaun_holz")
	assert_true(ergebnis["ok"])
	assert_eq(ergebnis["count"], 4)
	assert_eq(StorageLogic.count_of(HomeState.storage(gs), "fence_wood"), 4)
	_teardown(gs)


func test_rezeptzustaende_fuers_ui() -> void:
	var gs := _fresh_gs()
	_werkstatt_bauen(gs)
	var zustaende := CraftState.recipe_states(gs)
	assert_eq(zustaende.size(), CraftRecipes.for_station().size())
	for eintrag: Dictionary in zustaende:
		assert_false(eintrag["ok"], "ohne Material geht noch nichts")
		var erwartet := (
			CraftLogic.REASON_BLUEPRINT
			if str(eintrag["recipe"]["bauplan"]) != ""
			else CraftLogic.REASON_MATERIAL
		)
		assert_eq(str(eintrag["reason"]), erwartet, str(eintrag["recipe"]["id"]))
	_teardown(gs)
