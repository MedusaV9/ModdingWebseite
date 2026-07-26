extends TestCase
## RW-3 — Tagesrouten (RNpcRoutine): Stationswahl inkl. Nacht-Wrap,
## Fussweg-Interpolation zwischen Stationen, Orts-Aufloesung ueber RW-1s
## hof_plan (Duck-Typing via plan_override) mit Fallback-Ankern.

const ROUTINE := [
	{"von": 7, "ort": "stall", "taetigkeit": "arbeiten"},
	{"von": 13, "ort": "trog", "taetigkeit": "pause"},
	{"von": 19, "ort": "haus", "taetigkeit": "feierabend"},
]


func _abschluss() -> void:
	RNpcRoutine.plan_override = {}


func test_stationswahl_und_nacht_wrap() -> void:
	assert_eq(str(RNpcRoutine.station(ROUTINE, 8.0)["ort"]), "stall")
	assert_eq(str(RNpcRoutine.station(ROUTINE, 14.5)["ort"]), "trog")
	assert_eq(str(RNpcRoutine.station(ROUTINE, 23.0)["ort"]), "haus")
	assert_eq(
		str(RNpcRoutine.station(ROUTINE, 3.0)["ort"]),
		"haus",
		"vor der ersten Station gilt die letzte des Vortags"
	)
	assert_eq(RNpcRoutine.station([], 12.0), {}, "leere Routine crasht nicht")


func test_fussweg_interpolation() -> void:
	var stall := RNpcRoutine.ort_position("stall")
	var trog := RNpcRoutine.ort_position("trog")
	var start := RNpcRoutine.zustand(ROUTINE, 13.0)
	assert_true(bool(start["laeuft"]), "Stationswechsel beginnt mit Laufen")
	assert_true(
		(start["pos"] as Vector3).distance_to(stall) < 0.01,
		"bei von=13.0 steht der NPC noch am alten Ort"
	)
	var mitte := RNpcRoutine.zustand(ROUTINE, 13.0 + RNpcRoutine.WECHSEL_STUNDEN / 2.0)
	var erwartet := stall.lerp(trog, 0.5)
	assert_true(
		(mitte["pos"] as Vector3).distance_to(erwartet) < 0.01, "halber Fussweg = halber Weg"
	)
	var da := RNpcRoutine.zustand(ROUTINE, 13.0 + RNpcRoutine.WECHSEL_STUNDEN + 0.01)
	assert_false(bool(da["laeuft"]))
	assert_true((da["pos"] as Vector3).distance_to(trog) < 0.01, "angekommen")
	assert_eq(str(da["taetigkeit"]), "pause")


func test_ort_aufloesung_aus_dem_hof_plan() -> void:
	RNpcRoutine.plan_override = {
		"gebaeude": [{"id": "stall", "pos": Vector3(100.0, 0.0, 100.0)}],
		"trog_pos": Vector3(1.0, 0.0, 2.0),
		"teich_pos": Vector3(50.0, 0.0, 50.0),
		"tor_pos": Vector3(0.0, 0.0, 200.0),
		"reitplatz": Rect2(-10.0, -10.0, 20.0, 20.0),
		"koppeln": [{"id": "pferde", "rect": Rect2(0.0, 0.0, 40.0, 30.0)}],
	}
	assert_eq(
		RNpcRoutine.ort_position("stall"),
		Vector3(100.0, 0.0, 109.0),
		"NPCs stehen VOR dem Gebaeude"
	)
	assert_eq(RNpcRoutine.ort_position("trog"), Vector3(1.0, 0.0, 2.0))
	assert_eq(RNpcRoutine.ort_position("reitplatz"), Vector3(0.0, 0.0, 0.0), "Rect-Mitte")
	assert_eq(
		RNpcRoutine.ort_position("koppel_pferde"),
		Vector3(20.0, 0.0, 33.0),
		"am Zaunrand, nicht zwischen den Tieren"
	)
	_abschluss()


func test_fallback_anker_ohne_welt() -> void:
	RNpcRoutine.plan_override = {"leer": true}
	assert_eq(
		RNpcRoutine.ort_position("markt"),
		RNpcRoutine.FALLBACK_ORTE["markt"],
		"Orte ausserhalb des hof_plans kommen aus der Fallback-Tabelle"
	)
	assert_eq(
		RNpcRoutine.ort_position("stall"),
		RNpcRoutine.FALLBACK_ORTE["stall"],
		"fehlt das Gebaeude im Plan, greift der Anker"
	)
	assert_eq(RNpcRoutine.ort_position("nirgendwo"), Vector3.ZERO, "unbekannt = Ursprung")
	_abschluss()


func test_echte_welt_liefert_positionen_fuer_alle_routine_orte() -> void:
	# Ohne Override laeuft die Duck-Typing-Kette gegen RW-1s RanchWelt
	# (oder die Fallbacks) — jeder Routine-Ort des Ensembles ist aufloesbar.
	_abschluss()
	for def: Dictionary in RNpcKatalog.alle():
		for station: Dictionary in def.get("routine", []):
			var ort := str(station.get("ort", ""))
			assert_ne(
				RNpcRoutine.ort_position(ort),
				Vector3.ZERO,
				"%s: Ort %s ist nicht aufloesbar" % [def.get("id"), ort]
			)
