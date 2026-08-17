extends TestCase  # gdlint: ignore=max-public-methods
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
	{
		"fixture": "carrotGuard",
		"logic": preload("res://scripts/minigames/games/carrot_guard/carrot_guard_logic.gd"),
		"seed_first": true,
		"ints": ["score", "stolen"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "danceParty",
		"logic": preload("res://scripts/minigames/games/dance_party/dance_party_logic.gd"),
		"seed_first": true,
		"ints":
		[
			"score",
			"tally.perfect",
			"tally.good",
			"tally.miss",
			"tally.combo",
			"tally.maxCombo",
			"tally.bonus",
		],
		"floats": [],
	},
	{
		"fixture": "deliveryRush",
		"logic": preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd"),
		"seed_first": true,
		"ints": ["score", "crashes", "coinPoints"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "fishingPond",
		"logic": preload("res://scripts/minigames/games/fishing_pond/fishing_pond_logic.gd"),
		"seed_first": true,
		"ints": ["score", "failures"],
		"floats": [],
	},
	{
		"fixture": "ghostHunt",
		"logic": preload("res://scripts/minigames/games/ghost_hunt/ghost_hunt_logic.gd"),
		"seed_first": false,
		"ints": ["score", "caught", "missed", "escapedWaves", "booBonuses"],
		"floats": ["time"],
	},
	{
		"fixture": "goalieGooby",
		"logic": preload("res://scripts/minigames/games/goalie_gooby/goalie_gooby_logic.gd"),
		"seed_first": true,
		"ints": ["score", "saves", "goals"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "harborHopper",
		"logic": preload("res://scripts/minigames/games/harbor_hopper/harbor_hopper_logic.gd"),
		"seed_first": false,
		"ints": ["score", "crates", "rings", "bumps", "steals", "boosts", "distanceM"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "hideSeek",
		"logic": preload("res://scripts/minigames/games/hide_seek/hide_seek_logic.gd"),
		"seed_first": false,
		"ints": ["score", "waves", "found", "expired"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "lanternFloat",
		"logic": preload("res://scripts/minigames/games/lantern_float/lantern_float_logic.gd"),
		"seed_first": false,
		"ints": ["score", "rings", "hits", "golds", "fireflies", "bumps"],
		"floats": ["elapsed"],
	},
	{
		"fixture": "miniGolf",
		"logic": preload("res://scripts/minigames/games/mini_golf/mini_golf_logic.gd"),
		"seed_first": true,
		"ints": ["score", "overPar"],
		"floats": [],
	},
	{
		"fixture": "pipeFlow",
		"logic": preload("res://scripts/minigames/games/pipe_flow/pipe_flow_logic.gd"),
		"seed_first": true,
		"ints": ["score", "solved", "failures"],
		"floats": [],
	},
	{
		"fixture": "rocketRescue",
		"logic": preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_bot.gd"),
		"seed_first": false,
		"ints": ["score", "rescued", "softLandings", "hardLandings"],
		"floats": ["fuelLeft", "elapsed"],
		"strings": ["endReason"],
	},
	{
		"fixture": "runner",
		"logic": preload("res://scripts/minigames/games/runner/runner_logic.gd"),
		"seed_first": false,
		"ints": ["score", "hits"],
		"floats": ["elapsed", "meters"],
	},
	{
		"fixture": "shoppingSurf",
		"logic": preload("res://scripts/minigames/games/shopping_surf/shopping_surf_run.gd"),
		"seed_first": false,
		"ints": ["score", "coins", "crashes", "ended"],
		"floats": ["distanceM", "elapsed"],
	},
	{
		"fixture": "starHopper",
		"logic": preload("res://scripts/minigames/games/star_hopper/star_hopper_logic.gd"),
		"seed_first": true,
		"ints": ["score", "pickups"],
		"floats": ["distance"],
	},
	{
		"fixture": "toyRacer",
		"logic": preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd"),
		"seed_first": false,
		"ints": ["score", "rank", "races", "wins", "overtakes"],
		"floats": ["driftMeters", "time"],
	},
	{
		"fixture": "trampoline",
		"logic": preload("res://scripts/minigames/games/trampoline/trampoline_logic.gd"),
		"seed_first": true,
		"ints": ["score", "failures"],
		"floats": [],
	},
	{
		# Eigener Fixture-Typ (W15): kein Modus-Autoplay, sondern der
		# frame-getriebene Linien-Bot — Web simulateRound(seed, {difficulty}),
		# Godot simulate_round(seed, mode). "round" schaltet den Aufruf um.
		"fixture": "purblePlace",
		"logic": preload("res://scripts/minigames/games/purble_place/purble_place_logic.gd"),
		"seed_first": true,
		"round": true,
		"ints":
		[
			"score",
			"cakesServed",
			"perfectCakes",
			"rejected",
			"expired",
			"serves",
			"perfectBakes",
			"splats",
			"trashed",
			"over",
		],
		"floats": ["tSec"],
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


func test_carrot_guard_matches_web() -> void:
	_certify(GAMES[10])


func test_dance_party_matches_web() -> void:
	_certify(GAMES[11])


func test_delivery_rush_matches_web() -> void:
	_certify(GAMES[12])


func test_fishing_pond_matches_web() -> void:
	_certify(GAMES[13])


func test_ghost_hunt_matches_web() -> void:
	_certify(GAMES[14])


func test_goalie_gooby_matches_web() -> void:
	_certify(GAMES[15])


func test_harbor_hopper_matches_web() -> void:
	_certify(GAMES[16])


func test_hide_seek_matches_web() -> void:
	_certify(GAMES[17])


func test_lantern_float_matches_web() -> void:
	_certify(GAMES[18])


func test_mini_golf_matches_web() -> void:
	_certify(GAMES[19])


func test_pipe_flow_matches_web() -> void:
	_certify(GAMES[20])


func test_rocket_rescue_matches_web() -> void:
	_certify(GAMES[21])


func test_runner_matches_web() -> void:
	_certify(GAMES[22])


func test_shopping_surf_matches_web() -> void:
	_certify(GAMES[23])


func test_star_hopper_matches_web() -> void:
	_certify(GAMES[24])


func test_toy_racer_matches_web() -> void:
	_certify(GAMES[25])


func test_trampoline_matches_web() -> void:
	_certify(GAMES[26])


func test_purble_place_matches_web() -> void:
	_certify(GAMES[27])


## Dot-Pfad-Zugriff für Felder in Unter-Dictionaries (W15: danceParty tally.*).
## Im Fixture-Record ist der Pfad ein flacher Key, hier wird er abgestiegen.
static func _dig(result: Dictionary, path: String) -> Variant:
	var value: Variant = result
	for part in path.split("."):
		value = value[part]
	return value


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
	var string_fields: Array = entry.get("strings", [])
	var modes: Dictionary = fixture["modes"]
	var runs := 0
	for mode: String in modes:
		var mode_ok := true
		for run: Dictionary in modes[mode]:
			if not mode_ok:
				break
			var seed_value := int(run["seed"])
			var got: Dictionary
			if bool(entry.get("round", false)):
				got = logic.simulate_round(seed_value, mode)
			elif seed_first:
				got = logic.simulate_autoplay(seed_value, mode)
			else:
				got = logic.simulate_autoplay(mode, seed_value)
			var tag := "%s %s seed=%d" % [fixture_name, mode, seed_value]
			for field: String in int_fields:
				if int(_dig(got, field)) != int(run[field]):
					fail_test(
						(
							"%s %s: got=%d want=%d"
							% [tag, field, int(_dig(got, field)), int(run[field])]
						)
					)
					mode_ok = false
			for field: String in float_fields:
				if absf(float(_dig(got, field)) - float(run[field])) > 1e-9:
					fail_test(
						(
							"%s %s: got=%.17f want=%.17f"
							% [tag, field, float(_dig(got, field)), float(run[field])]
						)
					)
					mode_ok = false
			for field: String in string_fields:
				if String(_dig(got, field)) != String(run[field]):
					fail_test(
						(
							"%s %s: got=%s want=%s"
							% [tag, field, String(_dig(got, field)), String(run[field])]
						)
					)
					mode_ok = false
			runs += 1
	assert_true(runs >= 200, "%s: erwartet 4x50 Bot-Laeufe, war %d" % [fixture_name, runs])
