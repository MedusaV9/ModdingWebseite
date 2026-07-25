extends TestCase
## GvZ-Balance-Daten (W3b): Katalog-Vollständigkeit nach Doc G §4.2/§4.3,
## Ökonomie-Invarianten, Turm-DPS-Goldwerte und Content-Pack-Override über
## den Balance-Namespace "gvz" (W2b-ContentRegistry-Kontrakt).

## Die 12 Kauf-Türme aus Doc G §4.2 (Goldi ist Code-Gate-Bonus Nr. 13).
const TOWERS := [
	"moehrenschuetze",
	"nutella_sammler",
	"dicker_bert",
	"schnarch_knolle",
	"boom_beere",
	"eis_gooby",
	"doppelmoehre",
	"magnet_gooby",
	"trampolin_gooby",
	"pust_gooby",
	"sternchen_gooby",
	"melonen_meier",
]
## Die 10 Zombies aus Doc G §4.3 (Boss Knurps ist Nr. 11).
const ZOMBIES := [
	"schlurfi",
	"huetchen",
	"sprinter",
	"eimer",
	"huepfer",
	"zeitungsopa",
	"tuersteher",
	"maulwurf",
	"ballon",
	"brocken",
]


## Test-Double der W2b-ContentRegistry (Duck-Typing: nur get_balance zählt).
class RegistryDouble:
	extends RefCounted
	var values := {}

	func get_balance(namespace_id: String, fallback: Variant) -> Variant:
		return values.get(namespace_id, fallback)


func test_towers_complete_and_sane() -> void:
	var balance := GvzData.load_balance(null)
	var towers: Dictionary = balance.get("towers", {})
	for type: String in TOWERS:
		assert_true(towers.has(type), "Turm '%s' fehlt" % type)
		if not towers.has(type):
			continue
		var row: Dictionary = towers[type]
		assert_true(int(row.get("cost", 0)) > 0, "%s: Kosten <= 0" % type)
		assert_true(int(row.get("hp", 0)) > 0, "%s: hp <= 0" % type)
		assert_true(int(row.get("cooldown_ticks", -1)) >= 0, "%s: Cooldown fehlt" % type)
	assert_eq(towers.size(), TOWERS.size() + 1, "genau 12 Türme + Goldi")
	assert_true(bool(towers.get("goldi", {}).get("code_gate", false)), "Goldi braucht Code-Gate")


func test_zombies_complete_and_sane() -> void:
	var balance := GvzData.load_balance(null)
	var zombies: Dictionary = balance.get("zombies", {})
	for type: String in ZOMBIES:
		assert_true(zombies.has(type), "Zombie '%s' fehlt" % type)
		if not zombies.has(type):
			continue
		assert_true(int(zombies[type].get("hp", 0)) > 0, "%s: hp <= 0" % type)
		assert_true(int(zombies[type].get("speed_pct", 0)) > 0, "%s: speed <= 0" % type)
	assert_true(zombies.has("boss_knurps"), "Boss Knurps fehlt")
	assert_eq(zombies.size(), ZOMBIES.size() + 1, "genau 10 Zombies + Boss")
	assert_true(int(zombies.get("boss_knurps", {}).get("hp", 0)) >= 4000, "Boss ist ein Brett")


func test_boss_summons_are_groundable() -> void:
	# Beschworene Ballons würden die Panik-Goobys umfliegen → der Pool darf
	# nur Boden-Zombies enthalten (Ballons kommen geskriptet aus dem Level).
	var balance := GvzData.load_balance(null)
	var zombies: Dictionary = balance.get("zombies", {})
	var pool: Array = zombies.get("boss_knurps", {}).get("summon_types", [])
	assert_true(pool.size() >= 3, "Beschwörungs-Pool zu klein")
	for type: Variant in pool:
		assert_true(zombies.has(type), "Beschwörung '%s' unbekannt" % type)
		assert_false(
			bool(zombies.get(type, {}).get("flying", false)),
			"Beschwörung '%s' fliegt — Panik-Gooby-sicher muss sie sein" % type
		)


func test_economy_and_difficulty() -> void:
	var balance := GvzData.load_balance(null)
	var economy: Dictionary = balance.get("economy", {})
	assert_eq(int(economy.get("start_nutella", 0)), 50, "Start-Nutella (Doc G §4.1)")
	assert_true(int(economy.get("sky_drop_amount", 0)) > 0, "Himmels-Nutella")
	assert_true(int(economy.get("sky_drop_interval_ticks", 0)) > 0, "Himmels-Intervall")
	assert_true(int(economy.get("max_nutella", 0)) >= 999, "Nutella-Deckel")
	assert_eq(int(balance.get("ticks_per_second", 0)), 20, "20-Hz-Fixed-Tick (Doc G §R3)")
	for diff: String in ["easy", "normal", "hard"]:
		var row: Dictionary = balance.get("difficulty", {}).get(diff, {})
		assert_true(int(row.get("zombie_hp_pct", 0)) > 0, "difficulty.%s fehlt" % diff)
	var grid: Dictionary = balance.get("grid", {})
	assert_eq(int(grid.get("lanes", 0)), 5, "5 Reihen (Doc G §4.1)")
	assert_eq(int(grid.get("cols", 0)), 9, "9 Spalten (Doc G §4.1)")


func test_shooter_dps_per_gold_in_band() -> void:
	# Goldwert-Invariante: jeder Schütze liefert 0,25..1,0 Schaden pro Tick
	# je 100 Nutella — hält Neuzugänge im Balancing-Korridor.
	var balance := GvzData.load_balance(null)
	var towers: Dictionary = balance.get("towers", {})
	for type: String in TOWERS:
		var row: Dictionary = towers.get(type, {})
		if not row.has("projectile"):
			continue
		var dmg := int(row.get("damage", 0)) * int(row.get("volley", 1))
		var interval := int(row.get("fire_interval_ticks", 1))
		var cost := int(row.get("cost", 1))
		var dps_per_100 := float(dmg) / float(interval) * 100.0 / float(cost)
		assert_true(
			dps_per_100 >= 0.25 and dps_per_100 <= 1.0,
			"%s: %f dps/100 Nutella außerhalb 0,25..1,0" % [type, dps_per_100]
		)
	var moehre: Dictionary = towers.get("moehrenschuetze", {})
	var doppel: Dictionary = towers.get("doppelmoehre", {})
	assert_eq(int(doppel.get("volley", 0)), 2, "Doppelmöhre schießt Salve à 2")
	assert_eq(int(doppel.get("damage", 0)), int(moehre.get("damage", -1)), "gleiche Möhre")


func test_registry_override_deep_merges() -> void:
	var reg := RegistryDouble.new()
	reg.values = {"gvz": {"towers": {"moehrenschuetze": {"cost": 125}}, "extra": {"neu": 1}}}
	var balance := GvzData.load_balance(reg)
	assert_eq(int(balance["towers"]["moehrenschuetze"]["cost"]), 125, "Override greift")
	assert_eq(int(balance["towers"]["moehrenschuetze"]["damage"]), 20, "Rest bleibt (Deep-Merge)")
	assert_eq(int(balance["extra"]["neu"]), 1, "neue Schlüssel kommen durch")
	var plain := GvzData.load_balance(RegistryDouble.new())
	assert_eq(int(plain["towers"]["moehrenschuetze"]["cost"]), 100, "ohne Override Original")


func test_values_are_intified() -> void:
	# JSON kennt nur double — der Loader macht ganze Zahlen zu int
	# (Determinismus-Regel Doc G §R3).
	var balance := GvzData.load_balance(null)
	assert_eq(typeof(balance["towers"]["moehrenschuetze"]["cost"]), TYPE_INT, "cost ist int")
	assert_eq(typeof(balance["zombies"]["schlurfi"]["hp"]), TYPE_INT, "hp ist int")
	var levels := GvzData.load_levels()
	var level := GvzData.level_by_id(levels, 1)
	assert_eq(typeof(level["start_nutella"]), TYPE_INT, "start_nutella ist int")
	assert_eq(
		typeof((level["spawns"] as Array)[0]["t"]), TYPE_FLOAT, "Spawn-Sekunden bleiben float"
	)
