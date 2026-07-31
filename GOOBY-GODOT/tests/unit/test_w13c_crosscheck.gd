extends TestCase
## W13C CROSSCHECK — Difficulty-Zertifizierung der Minigame-Ports gegen die
## Original-Web-Logik. tools/cross_check.mjs fährt die Web-Bots (Seeds 1..50 ×
## easy/normal/hard/endless) und schreibt tests/expected/<spiel>.json; hier
## läuft derselbe Bot in Godot (simulate_autoplay, GoobyRng = mulberry32) und
## muss BIT-GENAU dasselbe Ergebnis liefern (Ints exakt, Floats ±1e-9 wegen
## JSON-Dezimal-Parser, siehe rng.json-Kommentar in cross_check.mjs).
## teaParty/carrotCatch (W2d) bleiben in test_mg_tea_logic/test_mg_catch_logic.

const EXPECTED_DIR := "res://tests/expected"

## Zertifizierungs-Tabelle: Fixture ↔ Godot-Logik. seed_first beschreibt die
## Argument-Reihenfolge von simulate_autoplay (historisch uneinheitlich).
## ints werden exakt verglichen, floats mit ±1e-9.
const GAMES: Array[Dictionary] = [
	{
		"fixture": "bunnyHop",
		"logic": preload("res://scripts/minigames/games/bunny_hop/bunny_hop_logic.gd"),
		"seed_first": true,
		"ints": ["score", "gates"],
		"floats": [],
	},
	{
		"fixture": "memoryMatch",
		"logic": preload("res://scripts/minigames/games/memory_match/memory_match_logic.gd"),
		"seed_first": true,
		"ints": ["score", "rawScore", "misses"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "goobySays",
		"logic": preload("res://scripts/minigames/games/gooby_says/gooby_says_logic.gd"),
		"seed_first": true,
		"ints": ["rounds", "score"],
		"floats": [],
	},
	{
		"fixture": "bubblePop",
		"logic": preload("res://scripts/minigames/games/bubble_pop/bubble_pop_logic.gd"),
		"seed_first": true,
		"ints": ["score", "spikyPops"],
		"floats": [],
	},
	{
		"fixture": "veggieChop",
		"logic": preload("res://scripts/minigames/games/veggie_chop/veggie_chop_logic.gd"),
		"seed_first": true,
		"ints": ["score", "misses", "junkHits"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "pancakeTower",
		"logic": preload("res://scripts/minigames/games/pancake_tower/pancake_tower_logic.gd"),
		"seed_first": false,
		"ints": ["score", "layers"],
		"floats": ["width"],
	},
	{
		"fixture": "burgerBuild",
		"logic": preload("res://scripts/minigames/games/burger_build/burger_build_logic.gd"),
		"seed_first": true,
		"ints": ["completed", "expired"],
		"floats": ["score"],
	},
	{
		"fixture": "snailMail",
		"logic": preload("res://scripts/minigames/games/snail_mail/snail_mail_logic.gd"),
		"seed_first": false,
		"ints": ["score", "deliveries", "splashes", "flowersPicked"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "gardenRush",
		"logic": preload("res://scripts/minigames/games/garden_rush/garden_rush_logic.gd"),
		"seed_first": true,
		"ints": ["score", "withered"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "basketBounce",
		"logic": preload("res://scripts/minigames/games/basket_bounce/basket_bounce_logic.gd"),
		"seed_first": false,
		"ints": ["score", "missStreak", "baskets"],
		"floats": ["elapsed"],
	},
]

## Fixtures, die NICHT von diesem Test abgedeckt werden (Bestands-Muster W2d).
const LEGACY_FIXTURES := ["rng", "framework", "teaParty", "carrotCatch"]


func test_fixture_folder_has_no_orphans() -> void:
	# Jedes expected/*.json muss zertifiziert sein — entweder hier (Tabelle)
	# oder durch die W2d-Bestandstests. Verwaiste Fixtures = tote Referenzen.
	var known: Array[String] = []
	known.assign(LEGACY_FIXTURES)
	for entry in GAMES:
		known.append(String(entry["fixture"]))
	for file in DirAccess.get_files_at(EXPECTED_DIR):
		if not file.ends_with(".json"):
			continue
		var stem := file.get_basename()
		assert_true(known.has(stem), "Fixture %s.json hat keinen Zertifizierungs-Test" % stem)


func test_bunny_hop_matches_web() -> void:
	_certify(GAMES[0])


func test_memory_match_matches_web() -> void:
	_certify(GAMES[1])


func test_gooby_says_matches_web() -> void:
	_certify(GAMES[2])


func test_bubble_pop_matches_web() -> void:
	_certify(GAMES[3])


func test_veggie_chop_matches_web() -> void:
	_certify(GAMES[4])


func test_pancake_tower_matches_web() -> void:
	_certify(GAMES[5])


func test_burger_build_matches_web() -> void:
	_certify(GAMES[6])


func test_snail_mail_matches_web() -> void:
	_certify(GAMES[7])


func test_garden_rush_matches_web() -> void:
	_certify(GAMES[8])


func test_basket_bounce_matches_web() -> void:
	_certify(GAMES[9])


## Kern: 4 Modi × 50 Seeds aus dem Fixture nachfahren und Feld für Feld
## gegen den Godot-Bot halten. Bricht pro Modus nach dem ersten Fehl-Seed ab,
## damit die Fehlerliste lesbar bleibt (ein Drift betrifft fast immer alle).
func _certify(entry: Dictionary) -> void:
	var fixture_name := String(entry["fixture"])
	var fixture: Variant = JsonFixtures.load_json("%s/%s.json" % [EXPECTED_DIR, fixture_name])
	assert_true(
		fixture is Dictionary, "%s.json fehlt — tools/cross_check.mjs laufen lassen" % fixture_name
	)
	if not (fixture is Dictionary):
		return
	var logic: GDScript = entry["logic"]
	var seed_first: bool = entry["seed_first"]
	var int_fields: Array = entry["ints"]
	var float_fields: Array = entry["floats"]
	var modes: Dictionary = fixture["modes"]
	var runs := 0
	for mode: String in modes:
		var mode_ok := true
		for run: Dictionary in modes[mode]:
			if not mode_ok:
				break
			var seed_value := int(run["seed"])
			var got: Dictionary
			if seed_first:
				got = logic.simulate_autoplay(seed_value, mode)
			else:
				got = logic.simulate_autoplay(mode, seed_value)
			var tag := "%s %s seed=%d" % [fixture_name, mode, seed_value]
			for field: String in int_fields:
				if int(got[field]) != int(run[field]):
					fail_test(
						"%s %s: got=%d want=%d" % [tag, field, int(got[field]), int(run[field])]
					)
					mode_ok = false
			for field: String in float_fields:
				if absf(float(got[field]) - float(run[field])) > 1e-9:
					fail_test(
						(
							"%s %s: got=%.17f want=%.17f"
							% [tag, field, float(got[field]), float(run[field])]
						)
					)
					mode_ok = false
			runs += 1
	assert_true(runs >= 200, "%s: erwartet 4x50 Bot-Laeufe, war %d" % [fixture_name, runs])
