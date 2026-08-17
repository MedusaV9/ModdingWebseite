extends TestCase
## Liefer-Hetze (deliveryRush) — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/deliveryRush.logic.js;
## die Stadtraster-Konstanten spiegeln GOOBY/src/city/cityBuilder.js.

const Logic := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd")

## Web-Goldwerte: simulateDeliveryAutoplay(seed, mode).score für Seeds 1..5.
const GOLD := {
	"easy": [240, 239, 238, 237, 236],
	"normal": [226, 225, 224, 223, 222],
	"hard": [213, 212, 211, 210, 209],
	"endless": [213, 212, 211, 210, 209],
}

const IDS: Array[String] = [
	"shop", "vetClinic", "fountain", "skyTower", "parkGazebo", "windmillCafe"
]


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.DELIVERY
	assert_eq(int(t["PARCELS"]), 3)
	assert_eq(int(t["LANDMARK_POOL"]), 6)
	assert_almost(float(t["DROP_RADIUS_M"]), 4.0)
	assert_eq(int(t["DROP_POINTS"]), 50)
	assert_eq(int(t["CRASH_PENALTY"]), 5)
	assert_almost(float(t["TIME_BONUS_FROM_SEC"]), 120.0)
	assert_eq(int(t["FRAGILE_CRASH_PENALTY"]), 20)
	assert_eq(int(t["FRAGILE_CLEAN_BONUS"]), 15)
	assert_almost(float(t["PARCEL_EXPIRE_SEC"]), 45.0)
	assert_eq(int(t["ENDLESS_EXPIRED_LIMIT"]), 3)
	assert_eq(Logic.LANDMARKS.size(), int(t["LANDMARK_POOL"]), "6 Landmarken im Topf")


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(7, mode), Logic.simulate_autoplay(7, mode), mode)
	# Coin-Rate > 1 (Trip-Semantik) zahlt zusätzliche Fahrpunkte.
	var run: Dictionary = Logic.simulate_autoplay(1, "normal", 2.0)
	assert_eq(int(run["coinPoints"]), 27)
	assert_eq(int(run["score"]), 253)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_hard_bot_reaches_target() -> void:
	var best := 0
	for seed_value in range(1, 6):
		best = maxi(best, int(Logic.simulate_autoplay(seed_value, "hard")["score"]))
	assert_true(best >= 200, "bester Schwer-Score %d < Ziel 200" % best)


func test_pick_deliveries_matches_web() -> void:
	var rng := GoobyRng.new(1)
	assert_eq(
		Logic.pick_deliveries(rng, IDS), ["windmillCafe", "shop", "skyTower"] as Array[String]
	)
	assert_eq(
		Logic.pick_deliveries(rng, IDS), ["skyTower", "windmillCafe", "parkGazebo"] as Array[String]
	)
	assert_eq(Logic.pick_deliveries(rng, IDS), ["parkGazebo", "skyTower", "shop"] as Array[String])
	# Immer 3 VERSCHIEDENE Ziele, nie der Laden als erstes (Startpunkt).
	for seed_value in range(1, 60):
		var picks := Logic.pick_deliveries(GoobyRng.new(seed_value), IDS)
		assert_eq(picks.size(), 3)
		assert_ne(picks[0], "shop", "Start-Rotation greift (seed %d)" % seed_value)
		var seen := {}
		for p in picks:
			assert_false(seen.has(p), "keine Doppel")
			seen[p] = true


func test_fragile_parcel_rules() -> void:
	var rng := GoobyRng.new(1)
	# Web: nach drei pickDeliveries-Aufrufen liefert derselbe Strom 1, 0, 2, 2.
	Logic.pick_deliveries(rng, IDS)
	Logic.pick_deliveries(rng, IDS)
	Logic.pick_deliveries(rng, IDS)
	assert_eq(Logic.pick_fragile_parcel(rng), 1)
	assert_eq(Logic.pick_fragile_parcel(rng), 0)
	assert_eq(Logic.pick_fragile_parcel(rng), 2)
	assert_eq(Logic.fragile_crash_penalty(1, 1, false), 20)
	assert_eq(Logic.fragile_crash_penalty(1, 1, true), 0, "nur einmal")
	assert_eq(Logic.fragile_crash_penalty(1, 0, false), 0, "nur das getragene Paket")
	assert_eq(Logic.fragile_delivery_bonus(1, 1, false), 15)
	assert_eq(Logic.fragile_delivery_bonus(1, 1, true), 0, "beschädigt = kein Bonus")


func test_score_edges() -> void:
	assert_eq(Logic.apply_drop(0), 50)
	assert_eq(Logic.apply_crash(3), 0, "Boden 0")
	assert_eq(Logic.apply_crash(0), 0)
	assert_eq(Logic.apply_crash(50), 45)
	assert_eq(Logic.time_bonus(0.0), 120)
	assert_eq(Logic.time_bonus(41.5), 78, "Bruchsekunden runden ab")
	assert_eq(Logic.time_bonus(120.0), 0)
	assert_eq(Logic.time_bonus(130.0), 0, "nie negativ")
	assert_eq(Logic.round_score(3, 0, 30.0), 240)
	assert_eq(Logic.round_score(3, 1, 41.0), 224)
	assert_eq(Logic.round_score(3, 2, 49.0), 211)
	assert_eq(Logic.round_score(2, 0, 10.0), 100, "ohne 3. Abwurf kein Zeitbonus")
	assert_eq(Logic.round_score(3, 0, 200.0), 150)


func test_difficulty_rows() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.DELIVERY, "easy")
	assert_almost(float(easy["SPEED_MULT"]), 0.85)
	assert_almost(float(easy["TRAFFIC_DENSITY_MULT"]), 0.85)
	assert_eq(int(easy["CRASH_ALLOWANCE"]), 1)
	var hard: Dictionary = Logic.apply_difficulty(Logic.DELIVERY, "hard")
	assert_almost(float(hard["SPEED_MULT"]), 1.2)
	assert_almost(float(hard["TRAFFIC_DENSITY_MULT"]), 1.15)
	assert_eq(int(hard["CRASH_ALLOWANCE"]), 0)
	assert_false(bool(hard["ENDLESS"]))
	assert_eq(Logic.apply_difficulty(Logic.DELIVERY, "normal"), Logic.DELIVERY)
	var rated: Dictionary = Logic.with_coin_rate(Logic.DELIVERY, 2.0)
	assert_almost(float(rated["COIN_RATE"]), 2.0)
	assert_almost(float(rated["COIN_INTERVAL_SEC"]), 4.0)
	assert_eq(Logic.with_coin_rate(Logic.DELIVERY, 1.0), Logic.DELIVERY)


func test_endless_ends_on_three_expired() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.DELIVERY, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.parcel_expired(44.0, tune))
	assert_true(Logic.parcel_expired(45.0, tune))
	assert_false(Logic.parcel_expired(999.0, Logic.DELIVERY), "Zeitmodus lässt nie verfallen")
	var state := Logic.create_endless_state()
	assert_false(Logic.record_expiry(state))
	assert_false(Logic.record_expiry(state))
	assert_true(Logic.record_expiry(state), "dritter Verfall beendet")
	assert_eq(int(state["expired"]), 3)
	# Nach dem Ende zählt nichts mehr hoch.
	Logic.record_expiry(state)
	assert_eq(int(state["expired"]), 3)


func test_drop_geometry() -> void:
	# Web: dropPoint({20,-46}) aus dem skyTower-Kollider herausgeschoben.
	var pushed := Logic.drop_point(
		{"x": 20.0, "z": -46.0}, [{"minX": 15.0, "maxX": 25.0, "minZ": -47.0, "maxZ": -37.0}]
	)
	assert_almost(float(pushed["x"]), 20.0)
	assert_almost(float(pushed["z"]), -48.6, 1e-12)
	# Freier Anker bleibt unverändert.
	assert_eq(Logic.drop_point({"x": 12.0, "z": 12.0}, []), {"x": 12.0, "z": 12.0})
	assert_true(
		Logic.segment_hits_drop(
			{"x": -10.0, "z": 0.0}, {"x": 10.0, "z": 0.0}, {"x": 0.0, "z": 3.0}
		),
		"gefegter Treffer"
	)
	assert_false(
		Logic.segment_hits_drop({"x": -10.0, "z": 0.0}, {"x": 10.0, "z": 0.0}, {"x": 0.0, "z": 5.0})
	)


func test_parcel_arc() -> void:
	var from := {"x": 0.0, "y": 1.0, "z": 0.0}
	var to := {"x": 4.0, "y": 0.0, "z": 2.0}
	assert_eq(Logic.parcel_arc_pos(from, to, 0.0), from, "exakter Startpunkt")
	assert_eq(Logic.parcel_arc_pos(from, to, 1.0), to, "exakter Endpunkt")
	var mid := Logic.parcel_arc_pos(from, to, 0.5)
	assert_almost(float(mid["x"]), 2.0)
	assert_almost(float(mid["y"]), 3.1, 1e-12)
	assert_almost(float(mid["z"]), 1.0)
	var q := Logic.parcel_arc_pos(from, to, 0.25)
	assert_almost(float(q["y"]), 2.5884776310850235, 1e-12)


func test_city_grid_and_routing() -> void:
	# Ring (r/c ∈ {1,7}) + Kreuz (r/c == 4) sind Straße, alles andere nicht.
	assert_true(Logic.is_road(1, 3))
	assert_true(Logic.is_road(7, 5))
	assert_true(Logic.is_road(4, 2))
	assert_true(Logic.is_road(6, 4))
	assert_false(Logic.is_road(2, 2), "Blockkachel")
	assert_false(Logic.is_road(0, 4), "Rand")
	assert_false(Logic.is_road(8, 8))
	assert_eq(Logic.tile_to_world(4, 4), Vector2.ZERO, "Kachel (4,4) ist der Ursprung")
	assert_eq(Logic.tile_to_world(7, 2), Vector2(-40.0, 60.0))
	assert_eq(Logic.world_to_tile(-40.0, 60.0), Vector2i(7, 2))
	var grid := Logic.build_grid()
	assert_eq(grid.size(), 9)
	assert_eq(str((grid[4][4] as Dictionary)["kind"]), "road")
	assert_eq(str((grid[2][2] as Dictionary)["kind"]), "block")
	assert_eq(str((grid[0][0] as Dictionary)["kind"]), "rim")
	# Nächste Straßenkachel zu einer Blockkachel + BFS über das Netz.
	assert_true(
		Logic.is_road(Logic.nearest_road_tile(grid, 2, 2).x, Logic.nearest_road_tile(grid, 2, 2).y)
	)
	var path := Logic.road_path_between(grid, Vector2i(7, 1), Vector2i(1, 7))
	assert_true(path.size() > 0, "Ring+Kreuz ist zusammenhängend")
	assert_eq(path[0], Vector2i(7, 1))
	assert_eq(path[path.size() - 1], Vector2i(1, 7))
	for tile in path:
		assert_true(Logic.is_road(tile.x, tile.y), "Weg bleibt auf der Straße")
	assert_eq(Logic.road_path_between(grid, Vector2i(2, 2), Vector2i(1, 7)).size(), 0)
