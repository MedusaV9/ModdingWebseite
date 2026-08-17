extends TestCase
## RANCH-1 — RanchKauf: Level-15-Gate (W13: 20→15), atomare Preis-Abbuchung, „zu wenig
## Münzen“ ändert NICHTS, Doppelkauf blockiert, Start-Tiere aus dem Pack
## (start=false-Tiere bleiben draußen).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _dir_seq := 0


class FakeRegistry:
	extends RefCounted

	var items: Array = []
	var balance: Dictionary = {}

	func get_items(_domain: String) -> Array:
		return items

	func get_balance(key: String, default_value: Variant = null) -> Variant:
		return balance.get(key, default_value)


func _fresh_gs(level: int, coins: int) -> Node:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://ranch_tests/kauf_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()
	RanchKatalog.registry_override = null
	RanchKatalog.reset_cache()


func test_gate_blockt_unter_level_15() -> void:
	var gs := _fresh_gs(14, 99999)
	assert_eq(RanchKauf.check(gs), RanchKauf.RESULT_LOCKED, "Level 14 gesperrt")
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_LOCKED)
	assert_eq(gs.get_value("economy.coins"), 99999, "keine Abbuchung im Gesperrt-Fall")
	assert_eq(gs.get_value("ranch.gekauft"), false)
	_teardown_gs(gs)


func test_kauf_bucht_exakt_den_preis_ab() -> void:
	var gs := _fresh_gs(15, RanchKatalog.preis() + 111)
	var vorher_spent := int(gs.get_value("economy.coinsSpent", 0))
	assert_eq(RanchKauf.check(gs), RanchKauf.RESULT_OK)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK)
	assert_eq(gs.get_value("economy.coins"), 111, "exakt der Preis wird abgebucht")
	assert_eq(
		int(gs.get_value("economy.coinsSpent", 0)) - vorher_spent,
		RanchKatalog.preis(),
		"Abbuchung landet im Spent-Buch"
	)
	assert_eq(gs.get_value("ranch.gekauft"), true)
	assert_true(int(gs.get_value("ranch.gekauftAm", 0)) > 0, "Kaufzeit gemerkt")
	_teardown_gs(gs)


func test_zu_wenig_muenzen_aendert_nichts() -> void:
	var gs := _fresh_gs(15, RanchKatalog.preis() - 1)
	assert_eq(RanchKauf.check(gs), RanchKauf.RESULT_BROKE)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_BROKE)
	assert_eq(gs.get_value("economy.coins"), RanchKatalog.preis() - 1, "Muenzen unangetastet")
	assert_eq(gs.get_value("ranch.gekauft"), false, "nicht gekauft")
	assert_eq(gs.get_value("ranch.hoftiere"), [], "keine Hoftiere eingezogen")
	assert_eq(gs.get_value("ranch.tiere.pferde"), {}, "keine Pferde eingezogen")
	_teardown_gs(gs)


func test_doppelkauf_blockiert() -> void:
	var gs := _fresh_gs(15, RanchKatalog.preis() * 2)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OWNED, "zweiter Kauf blockiert")
	assert_eq(gs.get_value("economy.coins"), RanchKatalog.preis(), "nur EINMAL abgebucht")
	_teardown_gs(gs)


func test_start_tiere_kommen_aus_dem_pack() -> void:
	var registry := FakeRegistry.new()
	registry.items = [
		{
			"id": "tier_a",
			"typ": "tier",
			"art": "pferd",
			"start": true,
			"name_key": "ranch.tiere.karamell",
			"farbe": "#111111",
			"fell_id": "palomino",
		},
		{"id": "tier_b", "typ": "tier", "art": "huhn", "start": false, "farbe": "#222222"},
		{"id": "tier_c", "typ": "tier", "art": "kuh", "start": true, "farbe": "#333333"},
		{"id": "welt", "typ": "welt"},
	]
	registry.balance = {"ranch.preis": 500, "ranch.freischalt_level": 15}
	RanchKatalog.registry_override = registry
	RanchKatalog.reset_cache()
	var gs := _fresh_gs(15, 500)
	assert_eq(RanchKatalog.preis(), 500, "Preis kommt aus dem Pack")
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK)
	var hoftiere: Array = gs.get_value("ranch.hoftiere")
	assert_eq(hoftiere.size(), 1, "nur start=true-Hoftiere ziehen ein (huhn=false bleibt)")
	assert_eq(hoftiere[0]["id"], "tier_c")
	assert_eq(hoftiere[0]["art"], "kuh")
	var pferde: Dictionary = gs.get_value("ranch.tiere.pferde")
	assert_eq(pferde.keys(), ["tier_a"], "Pferd zieht in RANCH-2s Pflege-Bestand ein")
	assert_eq(pferde["tier_a"]["name"], "Karamell", "Name aus dem name_key")
	assert_eq(pferde["tier_a"]["farbe"], "palomino", "fell_id → RanchPlaySlices-Farbe")
	assert_eq(pferde["tier_a"]["farbeHex"], "#111111", "Anzeige-Hex reist als Zusatz mit")
	assert_true(pferde["tier_a"]["werte"] is Dictionary, "Pflege-Werte über neues_pferd")
	assert_eq(gs.get_value("economy.coins"), 0, "Pack-Preis abgebucht")
	_teardown_gs(gs)


func test_kauf_loescht_verschoben_flag() -> void:
	var gs := _fresh_gs(15, RanchKatalog.preis())
	RanchState.angebot_verschieben(gs)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK)
	assert_eq(gs.get_value("ranch.angebotVerschoben"), false, "Kauf beendet das Verschieben")
	assert_eq(gs.get_value("ranch.angebotGesehen"), true)
	_teardown_gs(gs)
