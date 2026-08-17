extends TestCase
## GvZ-Level-Daten (W3b): alle 15 Kampagnen-Level laden + validieren,
## Freischalt-Reihenfolge nach der Doc-G-Tabelle (§4.4), Anti-Softlock-
## Regeln (Ballon nie ohne Anti-Luft) und Boss-Finale L15.

## Freischalt-Plan der Kampagne nach der Doc-G-§4.4-Tabelle (L6 = Nacht und
## L9 = Förderband führen Mechaniken statt Türme ein, L15 den Boss).
const NEW_TOWER_AT := {
	1: ["moehrenschuetze"],
	2: ["nutella_sammler"],
	3: ["dicker_bert"],
	4: ["schnarch_knolle"],
	5: ["boom_beere"],
	7: ["eis_gooby"],
	8: ["doppelmoehre"],
	10: ["magnet_gooby"],
	11: ["trampolin_gooby"],
	12: ["pust_gooby"],
	13: ["sternchen_gooby"],
	14: ["melonen_meier"],
}


func test_fifteen_levels_load_and_validate() -> void:
	var balance := GvzData.load_balance(null)
	var levels := GvzData.load_levels()
	assert_eq(levels.size(), 15, "genau 15 Kampagnen-Level")
	var errors := GvzData.validate_levels(levels, balance)
	assert_eq(errors.size(), 0, "Validierung: %s" % "; ".join(errors))
	for i in levels.size():
		assert_eq(int((levels[i] as Dictionary).get("id", -1)), i + 1, "ids fortlaufend")
		assert_true(
			(levels[i] as Dictionary).get("spawns", []).size() > 0, "L%d ohne Spawns" % (i + 1)
		)


func test_unlock_order_matches_doc_g() -> void:
	var levels := GvzData.load_levels()
	var expected: Array = []
	for level: Dictionary in levels:
		var id := int(level["id"])
		if NEW_TOWER_AT.has(id):
			expected.append_array(NEW_TOWER_AT[id])
			assert_eq(
				level.get("new_towers", []), NEW_TOWER_AT[id], "L%d new_towers laut Tabelle" % id
			)
		var unlocks: Array = level.get("unlock_towers", [])
		assert_eq(unlocks, expected, "L%d Freischaltungen kumulativ" % id)
	assert_eq(expected.size(), 12, "am Ende alle 12 Türme frei")


func test_every_level_introduces_something() -> void:
	var levels := GvzData.load_levels()
	var prev_mods := {}
	for level: Dictionary in levels:
		var id := int(level["id"])
		var mods: Dictionary = level.get("mods", {})
		var fresh: bool = (
			not (level.get("new_towers", []) as Array).is_empty()
			or not (level.get("new_zombies", []) as Array).is_empty()
			or mods.keys() != prev_mods.keys()
			or level.get("boss") is Dictionary
		)
		assert_true(fresh, "L%d führt nichts Neues ein (Doc G §4.4)" % id)
		prev_mods = mods


func test_no_balloon_before_anti_air() -> void:
	# Anti-Softlock: Ballons können nur Pust/Sternchen stoppen — sie dürfen
	# erst spawnen (auch nicht als Boss-Beschwörung), wenn Anti-Luft frei ist.
	var levels := GvzData.load_levels()
	for level: Dictionary in levels:
		var unlocks: Array = level.get("unlock_towers", [])
		var has_air: bool = unlocks.has("pust_gooby") or unlocks.has("sternchen_gooby")
		for spawn: Dictionary in level.get("spawns", []):
			if str(spawn["type"]) == "ballon":
				assert_true(has_air, "L%d: Ballon ohne Anti-Luft" % int(level["id"]))


func test_boss_finale_level_15() -> void:
	var levels := GvzData.load_levels()
	var l15 := GvzData.level_by_id(levels, 15)
	var boss: Dictionary = l15.get("boss", {})
	assert_eq(str(boss.get("type", "")), "boss_knurps", "L15 = Boss Knurps")
	assert_true(int(boss.get("enter_at", -1)) >= 0, "Boss-Einzugszeit gesetzt")
	assert_true(bool(l15.get("mods", {}).get("conveyor_hybrid", false)), "L15 Hybrid-Band")
	var pool: Array = l15.get("conveyor", {}).get("pool", [])
	assert_true(pool.has("boom_beere"), "Band liefert Booms (Boss-Rennen)")
	assert_true(pool.has("pust_gooby"), "Band liefert Anti-Luft")
	for id in [1, 5, 9, 15]:
		assert_true(
			GvzData.level_by_id(levels, id).get("waves", []).size() > 0, "L%d ohne Wellen" % id
		)
	assert_eq(GvzData.level_by_id(levels, 99), {}, "unbekannte Id → leer")


func test_spawn_lanes_active_and_sorted() -> void:
	var levels := GvzData.load_levels()
	for level: Dictionary in levels:
		var lanes: Array = level.get("lanes", [])
		var last_t := -1.0
		for spawn: Dictionary in level.get("spawns", []):
			var lane := int(spawn.get("lane", -1))
			assert_true(lane == -1 or lanes.has(lane), "L%d: tote Reihe" % int(level["id"]))
			var t := float(spawn["t"])
			assert_true(t >= last_t, "L%d: Spawns unsortiert" % int(level["id"]))
			last_t = t
