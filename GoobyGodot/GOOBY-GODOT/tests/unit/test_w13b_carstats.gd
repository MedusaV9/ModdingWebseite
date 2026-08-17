extends TestCase
## W13B/DRIVE — Auto-Stats (Doc G §6): der neue stats-Block in cars.json
## (AutoKatalog) + CarStatsLogic (Stats → Fahrparameter-Multiplikatoren).
## Beweise: Katalog vollständig + plausibel zum Preis, Neutralbasis Sedan
## mappt EXAKT auf 1.0 (Bestandsbalance unberührt), Mapping geklemmt +
## monoton + deterministisch, hostile Eingaben fallen auf die Basis zurück,
## Balkenzeile für die Pregame-Anzeige stabil.


func test_katalog_hat_stats_je_auto_plausibel_zum_preis() -> void:
	var autos := AutoKatalog.autos()
	assert_true(autos.size() >= 4, "mindestens die 4 Katalog-Autos")
	var nach_preis: Array = autos.duplicate()
	nach_preis.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("preis", 0)) < int(b.get("preis", 0))
	)
	var letzte_summe := -1
	for eintrag: Dictionary in nach_preis:
		var stats: Variant = eintrag.get("stats")
		assert_true(stats is Dictionary, "%s hat einen stats-Block" % eintrag.get("id"))
		var summe := 0
		for key in ["speed", "handling", "boost"]:
			var wert: Variant = (stats as Dictionary).get(key)
			assert_true(wert is int or wert is float, "%s.%s ist Zahl" % [eintrag.get("id"), key])
			var n := int(wert)
			assert_true(
				n >= CarStatsLogic.STAT_MIN and n <= CarStatsLogic.STAT_MAX,
				"%s.%s in 1..10" % [eintrag.get("id"), key]
			)
			summe += n
		# Plausibel je Preis: teurere Autos sind in der Summe nie schlechter.
		assert_true(
			summe >= letzte_summe,
			(
				"%s (Preis %s): Stat-Summe %d fällt nicht unter den Vorgänger"
				% [eintrag.get("id"), eintrag.get("preis"), summe]
			)
		)
		letzte_summe = summe


func test_startwagen_ist_neutralbasis() -> void:
	var start := AutoKatalog.auto(AutoKatalog.start_auto_id())
	assert_false(start.is_empty(), "Start-Wagen existiert")
	var stats: Dictionary = start.get("stats", {})
	for key in ["speed", "handling", "boost"]:
		assert_eq(int(stats.get(key, -1)), CarStatsLogic.STAT_BASE, "Sedan %s = Basis 3" % key)
	var mults := CarStatsLogic.multipliers(stats)
	assert_almost(float(mults["speed"]), 1.0, 1e-9, "Neutralbasis Tempo = ×1.0")
	assert_almost(float(mults["handling"]), 1.0, 1e-9, "Neutralbasis Lenkung = ×1.0")
	assert_almost(float(mults["boost"]), 1.0, 1e-9, "Neutralbasis Boost = ×1.0")


func test_mapping_geklemmt_und_monoton() -> void:
	# Formel: 1.0 + (stat − 3) × Step, hart geklemmt.
	assert_almost(CarStatsLogic.speed_mult({"speed": 10}), 1.21, 1e-9, "10 → 1 + 7×0.03")
	assert_almost(CarStatsLogic.speed_mult({"speed": 1}), 0.94, 1e-9, "1 → 1 − 2×0.03")
	assert_almost(CarStatsLogic.handling_mult({"handling": 10}), 1.175, 1e-9)
	assert_almost(CarStatsLogic.boost_mult({"boost": 10}), 1.21, 1e-9)
	# Hostile Rohwerte werden ERST auf 1..10 geklemmt (999 == 10, −5 == 1).
	assert_almost(
		CarStatsLogic.speed_mult({"speed": 999}), CarStatsLogic.speed_mult({"speed": 10}), 1e-9
	)
	assert_almost(
		CarStatsLogic.speed_mult({"speed": -5}), CarStatsLogic.speed_mult({"speed": 1}), 1e-9
	)
	# Alle Multiplikatoren bleiben innerhalb der dokumentierten Klemmen.
	for stat in range(CarStatsLogic.STAT_MIN, CarStatsLogic.STAT_MAX + 1):
		var s := CarStatsLogic.speed_mult({"speed": stat})
		assert_true(
			s >= CarStatsLogic.SPEED_MULT_RANGE.x and s <= CarStatsLogic.SPEED_MULT_RANGE.y,
			"speed_mult(%d) in der Klemme" % stat
		)
	# Monotonie: mehr Stat ⇒ nie langsamer/träger.
	for stat in range(CarStatsLogic.STAT_MIN, CarStatsLogic.STAT_MAX):
		assert_true(
			(
				CarStatsLogic.speed_mult({"speed": stat + 1})
				>= CarStatsLogic.speed_mult({"speed": stat})
			),
			"Tempo monoton bei %d" % stat
		)
		assert_true(
			(
				CarStatsLogic.handling_mult({"handling": stat + 1})
				>= CarStatsLogic.handling_mult({"handling": stat})
			),
			"Lenkung monoton bei %d" % stat
		)


func test_mapping_deterministisch_und_hostile() -> void:
	var stats := {"speed": 6, "handling": 4, "boost": 6}
	var a := CarStatsLogic.multipliers(stats)
	var b := CarStatsLogic.multipliers(stats)
	assert_eq(a, b, "gleiche Stats ⇒ bit-identische Multiplikatoren")
	# Hostile Container: alles fällt auf die Neutralbasis 1.0 zurück.
	for kaputt: Variant in [null, [], "quatsch", 7, {}]:
		var m := CarStatsLogic.multipliers(kaputt)
		assert_almost(float(m["speed"]), 1.0, 1e-9, "hostile speed → 1.0")
		assert_almost(float(m["handling"]), 1.0, 1e-9, "hostile handling → 1.0")
		assert_almost(float(m["boost"]), 1.0, 1e-9, "hostile boost → 1.0")
	# Fehlende Einzel-Keys ebenso.
	assert_almost(CarStatsLogic.boost_mult({"speed": 9}), 1.0, 1e-9, "fehlender Key → 1.0")


func test_balkenzeile_stabil() -> void:
	assert_eq(CarStatsLogic.bars(3), "▮▮▯▯▯", "Basis 3 → 2 von 5 Balken")
	assert_eq(CarStatsLogic.bars(10), "▮▮▮▮▮", "Vollausbau")
	assert_eq(CarStatsLogic.bars(1), "▮▯▯▯▯", "Minimum zeigt einen Balken")
	assert_eq(CarStatsLogic.bars(null), CarStatsLogic.bars(3), "hostile → Basis")
	for stat in range(CarStatsLogic.STAT_MIN, CarStatsLogic.STAT_MAX + 1):
		assert_eq(CarStatsLogic.bars(stat).length(), 5, "immer 5 Slots (%d)" % stat)


func test_aktives_auto_liefert_stats_fuer_die_fahr_spiele() -> void:
	# AutoKatalog.aktives_auto (der Host-Injektionspfad) liefert die Stats
	# des GEWÄHLTEN Autos aus dem Besitz — Fallback ist der Start-Sedan.
	var stub := StubState.new()
	stub.data = {
		"city": {"autos": {"hatchback-sports": "#F2C14E"}, "aktivesAuto": "hatchback-sports"}
	}
	var auto := AutoKatalog.aktives_auto(stub)
	assert_eq(str(auto.get("id")), "hatchback-sports", "gewähltes Auto gewinnt")
	assert_eq(int((auto.get("stats", {}) as Dictionary).get("speed")), 6)
	var mults := CarStatsLogic.multipliers(auto.get("stats"))
	assert_almost(float(mults["speed"]), 1.09, 1e-9, "GT: 1 + 3×0.03")
	# Nicht besessenes Wunschauto → Start-Sedan.
	var stub2 := StubState.new()
	stub2.data = {"city": {"aktivesAuto": "van"}}
	assert_eq(str(AutoKatalog.aktives_auto(stub2).get("id")), "sedan", "Fallback Start-Wagen")
	stub.free()
	stub2.free()


## Minimaler GameState-Stub (get_value-Pfadleser wie das Original).
class StubState:
	extends Node
	var data: Dictionary = {}

	func state() -> Dictionary:
		return data

	func update(mutator: Callable) -> void:
		mutator.call(data)

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cur: Variant = data
		for part in path.split("."):
			if cur is Dictionary and (cur as Dictionary).has(part):
				cur = cur[part]
			else:
				return fallback
		return cur
