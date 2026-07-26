extends TestCase
## PURE-Bausteine des Ranch-Multiplayers (RW-6): Kurs-Katalog (Hash-Kontrakt
## mit dem Server!), Interpolations-Puffer, Save-Slice ranch.mp (additiv,
## idempotente Ergebnis-Verbuchung) und Ranch-Metadaten (Builder/Validator).

## --------------------------------------------------------------- RmpKurse


func test_kurs_hash_kontrakt_mit_server() -> void:
	# ranchmp.test.js sichert dieselben Literale serverseitig — beide Seiten
	# MÜSSEN "<id>:v1:<checkpoints>" liefern, sonst werden Läufe unranked.
	assert_eq(RmpKurse.kurs_hash("grasbahn"), "grasbahn:v1:8")
	assert_eq(RmpKurse.kurs_hash("hof_parcours"), "hof_parcours:v1:8")
	assert_eq(RmpKurse.kurs_hash("weide_fangen"), "weide_fangen:v1:0")
	assert_eq(RmpKurse.kurs_hash("gibtsnicht"), "")


func test_kurs_geometrie_und_checkpoints() -> void:
	assert_eq(RmpKurse.checkpoint_anzahl("grasbahn"), 8)
	assert_eq(RmpKurse.checkpoint_pos("grasbahn", 0), Vector3(-330, 0, 60))
	assert_true(
		RmpKurse.checkpoint_erreicht("grasbahn", 0, Vector3(-335, 0, 65)), "innerhalb radius 14"
	)
	assert_false(RmpKurse.checkpoint_erreicht("grasbahn", 0, Vector3(-360, 0, 90)))
	assert_false(
		RmpKurse.checkpoint_erreicht("weide_fangen", 0, Vector3.ZERO), "Fangen hat keine Tore"
	)
	assert_eq(RmpKurse.standard_kurs("rennen"), "grasbahn")
	assert_eq(RmpKurse.gait_index("galopp"), 4)
	assert_eq(RmpKurse.gait_name(2), "trab")


func test_startaufstellung_deterministisch() -> void:
	var a := RmpKurse.start_position("grasbahn", 0, 4)
	var b := RmpKurse.start_position("grasbahn", 1, 4)
	assert_eq(a, RmpKurse.start_position("grasbahn", 0, 4), "deterministisch")
	assert_true(a.distance_to(b) > 2.0, "Plätze liegen auseinander")
	var fang := RmpKurse.start_position("weide_fangen", 1, 4)
	assert_true(fang.distance_to(Vector3(-380, 0, 90)) < 70.0, "im Arena-Kreis")


func test_bestenlisten_richtung() -> void:
	assert_true(RmpKurse.kleiner_gewinnt("grasbahn"))
	assert_true(RmpKurse.kleiner_gewinnt("rw5_tonnen"))
	assert_false(RmpKurse.kleiner_gewinnt("rw5_springen"), "Punkte: größer gewinnt")
	var kurse := RmpKurse.bestenlisten_kurse()
	assert_true(kurse.has("grasbahn"))
	assert_true(kurse.has("rw5_dressur"))
	assert_false(kurse.has("weide_fangen"), "Fangen hat keine Bestenliste")


## -------------------------------------------------------------- RmpInterp


func test_interp_puffer_linear() -> void:
	var z := RmpInterp.neu()
	assert_eq(RmpInterp.sample_at(z, 1000), {}, "leer → {}")
	RmpInterp.push(z, 1000, Vector3(0, 0, 0), 0.0, 1)
	RmpInterp.push(z, 1100, Vector3(10, 0, 0), 0.0, 2)
	# Renderzeit 1200 schaut 150 ms zurück → Ziel 1050 = Mitte.
	var pose := RmpInterp.sample_at(z, 1200)
	assert_almost((pose["pos"] as Vector3).x, 5.0, 0.001, "linear interpoliert")
	assert_eq(int(pose["gait"]), 2)
	assert_false(bool(pose["stale"]))


func test_interp_haelt_letzte_pose_und_meldet_stale() -> void:
	var z := RmpInterp.neu()
	RmpInterp.push(z, 1000, Vector3(3, 0, 4), 1.0, 4)
	var pose := RmpInterp.sample_at(z, 1400)
	assert_eq(pose["pos"], Vector3(3, 0, 4), "hinter dem jüngsten Sample: halten")
	assert_false(bool(pose["stale"]), "400 ms sind noch kein Stillstand")
	var spaet := RmpInterp.sample_at(z, 3000)
	assert_true(bool(spaet["stale"]), "nach 1,2 s Funkstille eingefroren")
	RmpInterp.reset(z)
	assert_eq(RmpInterp.sample_at(z, 3000), {}, "reset leert den Puffer")


func test_interp_yaw_kurzer_weg() -> void:
	var z := RmpInterp.neu()
	RmpInterp.push(z, 1000, Vector3.ZERO, 0.1, 0)
	RmpInterp.push(z, 1100, Vector3.ZERO, TAU - 0.1, 0)
	var pose := RmpInterp.sample_at(z, 1200)
	# Kurzer Weg über 0 herum, NICHT einmal quer durch den Kreis.
	assert_almost(fposmod(float(pose["yaw"]), TAU), 0.0, 0.001, "Mitte = 0 rad")


## --------------------------------------------------------------- RmpState


func test_state_default_und_heilung() -> void:
	var mp := RmpState.normalize({"statistik": {"rennen": {"siege": "kaputt"}}, "murks": 1})
	assert_eq((mp["statistik"] as Dictionary)["rennen"], {"teilnahmen": 0, "siege": 0})
	assert_eq((mp["statistik"] as Dictionary)["fangen"], {"teilnahmen": 0, "siege": 0})
	assert_eq(mp["verlauf"], [])
	assert_eq(mp["murks"], 1, "fremde Schlüssel überleben verbatim")


func test_state_ergebnis_idempotent() -> void:
	var gs := FakeGs.new()
	var result := {
		"rewardId": "rmp-abc-X",
		"mode": "rennen",
		"kurs": "grasbahn",
		"rank": 1,
		"zeitMs": 61000,
		"ranked": true,
		"dnf": false,
	}
	assert_true(RmpState.ergebnis_verbuchen(gs, result))
	assert_false(RmpState.ergebnis_verbuchen(gs, result), "gleiche rewardId zählt nie doppelt")
	assert_eq(RmpState.statistik(gs, "rennen"), {"teilnahmen": 1, "siege": 1})
	var zweiter := {
		"rewardId": "rmp-abc-Y",
		"mode": "rennen",
		"kurs": "grasbahn",
		"rank": 2,
		"zeitMs": 65000,
		"ranked": true,
		"dnf": false,
	}
	assert_true(RmpState.ergebnis_verbuchen(gs, zweiter))
	assert_eq(RmpState.statistik(gs, "rennen"), {"teilnahmen": 2, "siege": 1})
	var verlauf: Array = RmpState.lese(gs)["verlauf"]
	assert_eq(verlauf.size(), 2)
	assert_eq((verlauf[0] as Dictionary)["rewardId"], "rmp-abc-X")


func test_state_save_bleibt_additiv() -> void:
	var gs := FakeGs.new()
	gs.set_value("ranch.tiere", {"pferde": {"p1": {"name": "Wolke"}}})
	RmpState.ergebnis_verbuchen(
		gs, {"rewardId": "r1", "mode": "fangen", "rank": 3, "zeitMs": 0, "ranked": true}
	)
	assert_eq(
		gs.get_value("ranch.tiere", {}),
		{"pferde": {"p1": {"name": "Wolke"}}},
		"ranch.mp fasst NUR den eigenen Unterschlüssel an"
	)
	assert_true((gs.get_value("ranch.mp", {}) as Dictionary).has("statistik"))


## ----------------------------------------------------------- RmpRanchMeta


func test_ranch_meta_builder() -> void:
	var gs := FakeGs.new()
	gs.set_value("meta.playerName", "Mia")
	gs.set_value("meta.goobyNickname", "Flauschi")
	gs.set_value("ranch.wirtschaft.ausbau", {"boxen": 2, "reitplatz": true, "weidezaun": false})
	gs.set_value(
		"ranch.tiere.pferde",
		{"p1": {"name": "Wolke", "rasse": "toelter", "level": 7, "farbe": "weiss"}}
	)
	gs.set_value("ranch.comp", {"trophaeen": ["pokal_holz"], "schleifen": {"springen_holz": 1}})
	var meta := RmpRanchMeta.build_from_state(gs)
	assert_eq(meta["name"], "Mia")
	assert_eq(meta["goobyName"], "Flauschi")
	assert_eq((meta["ausbau"] as Dictionary)["boxen"], 2)
	assert_eq((meta["pferde"] as Array).size(), 1)
	assert_eq(((meta["pferde"] as Array)[0] as Dictionary)["name"], "Wolke")
	assert_eq(((meta["pferde"] as Array)[0] as Dictionary)["level"], 7)
	assert_eq(meta["trophaeen"] as Array, ["pokal_holz"])
	assert_eq(meta["schleifen"], 1)
	assert_true(bool(RmpRanchMeta.validate(meta)["ok"]))


func test_ranch_meta_validate_und_normalize() -> void:
	assert_false(bool(RmpRanchMeta.validate("kein dict")["ok"]))
	var riesig := {"pferde": [], "fett": "x".repeat(20000)}
	assert_eq(RmpRanchMeta.validate(riesig)["reason"], "TOO_LARGE")
	var boese := {
		"name": "H".repeat(99),
		"pferde": [{"name": "Ok", "level": 999}, "murks"],
		"ausbau": {"boxen": 77},
		"schleifen": -5,
	}
	var sauber := RmpRanchMeta.normalize(boese)
	assert_eq((sauber["name"] as String).length(), RmpRanchMeta.MAX_NAME_LEN)
	assert_eq((sauber["pferde"] as Array).size(), 1, "Nicht-Dicts fliegen raus")
	assert_eq(((sauber["pferde"] as Array)[0] as Dictionary)["level"], 99, "Level geklemmt")
	assert_eq((sauber["ausbau"] as Dictionary)["boxen"], 3)
	assert_eq(sauber["schleifen"], 0)


## GameState-Double: get_value/set_value über Pfad-Keys (wie GameState).
class FakeGs:
	var daten: Dictionary = {}

	func get_value(key: String, fallback: Variant = null) -> Variant:
		return daten.get(key, fallback)

	func set_value(key: String, value: Variant) -> void:
		daten[key] = value
