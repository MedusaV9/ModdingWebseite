extends TestCase
## W18/R3 Level-Reise (G8-IDEE Progression Nr. 2): Gate-/Meilenstein-Ableitung
## aus der ECHTEN Kurve (nur lesen!), Rückwirkend-Logik idempotent, Feier-
## Einreihung ohne Overlay-Stapel (über den Sequenzer-/Bremsen-Zustand des
## RewardHub) und deterministische Reise-Karten-Daten. DE/EN-Paritätscheck
## für strings/<locale>/levelreise.json.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")
const Economy := preload("res://scripts/logic/economy.gd")

const T0 := 1_750_000_000_000

var _seq := 0


## Bonus-Bremsen-Double (Sequenzer-Zustand der MorgenSequenz): haelt_bonus()
## steuert, ob die Bühne frei ist — exakt die Schnittstelle, die der Hub
## über bonus_bremse_setzen konsumiert.
class FakeBremse:
	extends RefCounted
	var haelt := true

	func haelt_bonus() -> bool:
		return haelt


func _fresh_state() -> Dictionary:
	return SaveSchema.default_state(T0)


func _fresh_gs(level: int, xp: float) -> Node:
	_seq += 1
	var dir := "user://levelreise_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(T0)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	gs.update(
		func(s: Dictionary) -> void:
			(s["onboarding"] as Dictionary)["done"] = true
			var prog: Dictionary = s["progression"]
			prog["level"] = level
			prog["xp"] = xp
	)
	return gs


## ---------------------------------------------------------------- Kurve/Meilensteine


func test_meilensteine_aus_der_kurve() -> void:
	var steine := LevelReiseLogic.meilensteine()
	@warning_ignore("integer_division")
	var erwartet := Leveling.MAX_LEVEL / LevelReiseLogic.MEILENSTEIN_SCHRITT
	assert_eq(steine.size(), erwartet, "alle 5er-Schritte bis MAX_LEVEL")
	assert_eq(steine[0], 5, "erster Meilenstein Level 5")
	assert_eq(steine[steine.size() - 1], Leveling.MAX_LEVEL, "letzter = MAX_LEVEL (Zeremonie)")
	for m in steine:
		assert_true(LevelReiseLogic.ist_meilenstein(m), "%d ist Meilenstein" % m)
	assert_false(LevelReiseLogic.ist_meilenstein(1), "Level 1 kein Meilenstein")
	assert_false(LevelReiseLogic.ist_meilenstein(12), "Level 12 kein Meilenstein")
	assert_eq(LevelReiseLogic.naechster_meilenstein(1), 5, "nach 1 kommt 5")
	assert_eq(LevelReiseLogic.naechster_meilenstein(5), 10, "nach 5 kommt 10")
	assert_eq(LevelReiseLogic.naechster_meilenstein(Leveling.MAX_LEVEL), 0, "Reise komplett")


func test_fehlende_xp_liest_kurve_nur() -> void:
	var p := {"level": 3, "xp": 50.0}
	var erwartet := Leveling.cumulative_xp_to_level(5) - Leveling.cumulative_xp_to_level(3) - 50
	assert_eq(LevelReiseLogic.fehlende_xp(p, 5), erwartet, "Differenz aus cumulative_xp")
	assert_eq(
		LevelReiseLogic.fehlende_xp(p, 4),
		Leveling.xp_to_next(3) - 50,
		"nächstes Level = xp_to_next minus Stand"
	)
	assert_eq(LevelReiseLogic.fehlende_xp(p, 3), 0, "erreichtes Ziel kostet nichts")
	assert_eq(LevelReiseLogic.fehlende_xp(p, 1), 0, "vergangenes Ziel kostet nichts")


func test_hinweis_daten() -> void:
	var state := _fresh_state()
	(state["progression"] as Dictionary)["level"] = 4
	(state["progression"] as Dictionary)["xp"] = 10.0
	var info := LevelReiseLogic.hinweis(state)
	assert_false(bool(info["max"]), "Level 4 ist nicht das Reiseziel")
	assert_eq(int(info["naechstes_level"]), 5, "nächstes Level 5")
	assert_eq(int(info["fest_level"]), 5, "nächstes Fest Level 5")
	assert_eq(int(info["xp_naechstes"]), Leveling.xp_to_next(4) - 10, "XP bis Level 5")
	assert_eq(int(info["xp_fest"]), int(info["xp_naechstes"]), "Fest = nächstes Level hier")
	(state["progression"] as Dictionary)["level"] = Leveling.MAX_LEVEL
	var max_info := LevelReiseLogic.hinweis(state)
	assert_true(bool(max_info["max"]), "MAX_LEVEL meldet Reiseziel erreicht")


## ---------------------------------------------------------------- Gates (aus dem Code)


func test_gates_kommen_aus_dem_echten_code() -> void:
	var gates := LevelReiseLogic.gates()
	var nach_id := {}
	for gate: Dictionary in gates:
		nach_id[str(gate["id"])] = int(gate["level"])
		assert_true(int(gate["level"]) >= 2, "Gate %s liegt hinter Level 1" % gate["id"])
		assert_true(int(gate["level"]) <= Leveling.MAX_LEVEL, "Gate %s auf der Karte" % gate["id"])
		assert_false(str(gate["label_key"]).is_empty(), "Gate %s beschriftet" % gate["id"])
	assert_eq(nach_id.size(), gates.size(), "Gate-Ids eindeutig")
	assert_eq(int(nach_id["lieferung"]), Economy.QUICK_DELIVERY_LEVEL, "Blitz-Lieferung")
	assert_eq(int(nach_id["goobye"]), GoobyeKatalog.freischalt_level(), "Goo und Bye")
	assert_eq(int(nach_id["mcgooby"]), McGoobyKatalog.freischalt_level(), "McGooby")
	assert_eq(int(nach_id["ranch"]), RanchKatalog.freischalt_level(), "Gooby-Ranch")
	for station: Dictionary in MusicRegistry.STATION_DEFS:
		var unlock := int(station.get("unlock_level", 1))
		var id := "radio_%s" % str(station["id"])
		if unlock > 1:
			assert_eq(int(nach_id.get(id, -1)), unlock, "Radio-Tor %s" % id)
		else:
			assert_false(nach_id.has(id), "Level-1-Sender %s ist KEIN Tor" % id)
	for i in range(1, gates.size()):
		assert_true(
			int(gates[i - 1]["level"]) <= int(gates[i]["level"]), "Gates aufsteigend sortiert"
		)


## ---------------------------------------------------------------- Rückwirkend/Stempeln


func test_backfill_stille_idempotent() -> void:
	var state := _fresh_state()
	(state["progression"] as Dictionary)["level"] = 12
	var erster := LevelReiseLogic.backfill_stille(state)
	assert_eq(erster, [5, 10] as Array[int], "Level 12: 5+10 rückwirkend gestempelt")
	var done := LevelReiseLogic.gefeierte(state)
	assert_eq(int(done.get("5", -1)), 0, "rückwirkend = at_ms 0 (ohne Datum)")
	assert_eq(int(done.get("10", -1)), 0, "rückwirkend = at_ms 0 (ohne Datum)")
	var zweiter := LevelReiseLogic.backfill_stille(state)
	assert_true(zweiter.is_empty(), "zweiter Lauf stempelt NICHTS (idempotent)")
	assert_eq(LevelReiseLogic.gefeierte(state).size(), 2, "keine Duplikate")


func test_stempeln_und_offene_meilensteine() -> void:
	var state := _fresh_state()
	(state["progression"] as Dictionary)["level"] = 12
	assert_eq(LevelReiseLogic.offene_meilensteine(state), [5, 10] as Array[int], "beide offen")
	assert_true(LevelReiseLogic.stemple_gefeiert(state, 5, T0), "erster Stempel neu")
	assert_false(LevelReiseLogic.stemple_gefeiert(state, 5, T0 + 1), "zweiter prallt ab")
	assert_eq(int(LevelReiseLogic.gefeierte(state)["5"]), T0, "at_ms des Fests bleibt")
	assert_eq(LevelReiseLogic.offene_meilensteine(state), [10] as Array[int], "nur 10 noch offen")


## ---------------------------------------------------------------- Stationen/Determinismus


func test_stationen_deterministisch() -> void:
	var state := _fresh_state()
	(state["progression"] as Dictionary)["level"] = 12
	LevelReiseLogic.backfill_stille(state)
	var a := LevelReiseLogic.stationen(state)
	var b := LevelReiseLogic.stationen(state)
	assert_eq(a.size(), Leveling.MAX_LEVEL, "eine Station pro Level")
	assert_eq(var_to_str(a), var_to_str(b), "gleicher State ⇒ identische Karte")
	var s12: Dictionary = a[11]
	assert_true(bool(s12["erreicht"]) and bool(s12["aktuell"]), "Level 12 aktuell")
	assert_false(bool(s12["meilenstein"]), "Level 12 kein Fest-Knoten")
	var s5: Dictionary = a[4]
	assert_true(bool(s5["meilenstein"]) and bool(s5["gefeiert"]), "Level 5 gefeiert")
	var s40: Dictionary = a[Leveling.MAX_LEVEL - 1]
	assert_true(bool(s40["max"]) and bool(s40["meilenstein"]), "Reiseziel = Fest-Knoten")
	assert_false(bool(s40["erreicht"]), "Level 40 noch nicht erreicht")
	var s8: Dictionary = a[Economy.QUICK_DELIVERY_LEVEL - 1]
	var gate_ids: Array[String] = []
	for gate: Dictionary in s8["gates"]:
		gate_ids.append(str(gate["id"]))
	assert_true(gate_ids.has("lieferung"), "Blitz-Lieferungs-Tor sitzt an seinem Level")


func test_meilenstein_stempel_fuer_den_reisepass() -> void:
	var state := _fresh_state()
	(state["progression"] as Dictionary)["level"] = 12
	LevelReiseLogic.stemple_gefeiert(state, 5, T0)
	LevelReiseLogic.backfill_stille(state)
	var stempel := LevelReiseLogic.meilenstein_stempel(state)
	assert_eq(stempel.size(), 2, "Level 12 ⇒ Stempel für 5 und 10")
	var s5: Dictionary = stempel[0]
	assert_eq(str(s5["id"]), "level5", "Stempel-Id")
	assert_eq(str(s5["glyph"]), LevelReiseLogic.GLYPH_FEST, "Torte auf dem 5er")
	assert_eq(int(s5["at_ms"]), T0, "gefeiertes Fest trägt sein Datum")
	assert_false(str(s5["label"]).is_empty(), "Label vor-lokalisiert")
	var s10: Dictionary = stempel[1]
	assert_eq(int(s10["at_ms"]), 0, "rückwirkender Stempel ohne Datum")
	(state["progression"] as Dictionary)["level"] = Leveling.MAX_LEVEL
	var alle := LevelReiseLogic.meilenstein_stempel(state)
	var letzter: Dictionary = alle[alle.size() - 1]
	assert_eq(str(letzter["glyph"]), LevelReiseLogic.GLYPH_MOEHRE, "L40 = Goldene Möhre")


func test_jubel_key_deterministisch() -> void:
	assert_eq(LevelReiseLogic.jubel_key(5), "levelreise.jubel_1", "5 → Variante 1")
	assert_eq(LevelReiseLogic.jubel_key(10), "levelreise.jubel_2", "10 → Variante 2")
	assert_eq(LevelReiseLogic.jubel_key(15), "levelreise.jubel_3", "15 → Variante 3")
	assert_eq(LevelReiseLogic.jubel_key(20), "levelreise.jubel_4", "20 → Variante 4")
	assert_eq(LevelReiseLogic.jubel_key(25), "levelreise.jubel_1", "25 → zyklisch")
	assert_eq(
		LevelReiseLogic.jubel_key(Leveling.MAX_LEVEL),
		"levelreise.jubel_max",
		"Reiseziel hat die Zeremonien-Zeile"
	)


## ---------------------------------------------------------------- Strings DE/EN


func test_strings_de_en_paritaet() -> void:
	var de: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://strings/de/levelreise.json")
	)
	var en: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://strings/en/levelreise.json")
	)
	assert_true(de is Dictionary and en is Dictionary, "beide Dateien parsen")
	var de_keys := _flache_keys(de, "")
	var en_keys := _flache_keys(en, "")
	de_keys.sort()
	en_keys.sort()
	assert_eq(de_keys, en_keys, "DE/EN paritätisch")
	assert_true(de_keys.has("levelreise.titel"), "Kartenkopf-Key da")
	for gate: Dictionary in LevelReiseLogic.gates():
		var key := str(gate["label_key"])
		if not key.begins_with("levelreise."):
			continue
		assert_true(de_keys.has(key), "Gate-Key %s in DE" % key)


func _flache_keys(wert: Variant, prefix: String) -> Array[String]:
	var out: Array[String] = []
	if not (wert is Dictionary):
		return out
	for k: Variant in (wert as Dictionary).keys():
		var pfad := str(k) if prefix.is_empty() else "%s.%s" % [prefix, str(k)]
		var v: Variant = (wert as Dictionary)[k]
		if v is Dictionary:
			out.append_array(_flache_keys(v, pfad))
		else:
			out.append(pfad)
	return out


## ---------------------------------------------------------------- Hub-Einreihung


func test_hub_backfill_still_ohne_nachfeier() -> void:
	# Rückwirkend-Regel am ECHTEN Hub: Level 12 beim Andocken ⇒ 5+10 werden
	# still gestempelt (at_ms 0), es feuert KEIN Fest (kein Nachfeier-Spam).
	var gs := _fresh_gs(12, 0.0)
	var host := Node.new()
	tree.root.add_child(host)
	var hub := RewardHub.attach_to(host, gs)
	var gefeiert: Array[int] = []
	hub.meilenstein_celebrated.connect(func(l: int) -> void: gefeiert.append(l))
	await wait_frames(4)
	var done := LevelReiseLogic.gefeierte(gs.state())
	assert_eq(done.size(), 2, "5+10 gestempelt")
	assert_eq(int(done.get("5", -1)), 0, "still = ohne Datum")
	assert_eq(int(done.get("10", -1)), 0, "still = ohne Datum")
	assert_true(gefeiert.is_empty(), "kein Fest beim Backfill")
	# Level-Erfolge (AchievementsService) dürfen feiern — aber KEIN Fest:
	for entry: Dictionary in hub._queue:
		assert_ne(str(entry.get("kind", "")), "fest", "keine Fest-Einträge in der Queue")
	host.queue_free()
	await wait_frames(1)
	gs.free()


func test_hub_fest_wartet_auf_freie_buehne() -> void:
	# Feier-Einreihung über den Sequenzer-Zustand: solange die Morgen-Bremse
	# haelt_bonus() meldet, feiert NICHTS (kein Overlay-Stapel); nach dem
	# Lösen kommt GENAU EIN Fest. Der Stempel sitzt sofort (Doppel-Schutz).
	var gs := _fresh_gs(4, 0.0)
	var host := Node.new()
	tree.root.add_child(host)
	var hub := RewardHub.attach_to(host, gs)
	var bremse := FakeBremse.new()
	hub.bonus_bremse_setzen(bremse)
	var gefeiert: Array[int] = []
	hub.meilenstein_celebrated.connect(func(l: int) -> void: gefeiert.append(l))
	await wait_frames(2)
	assert_true(LevelReiseLogic.gefeierte(gs.state()).is_empty(), "Level 4: nichts gefeiert")
	# Debug-XP: Level 4 → 5 (exakt die Spiel-Schreibweise via Leveling).
	gs.update(
		func(s: Dictionary) -> void:
			var prog: Dictionary = s["progression"]
			var res := Leveling.apply_xp(
				{"xp": float(prog["xp"]), "level": int(prog["level"])},
				float(Leveling.xp_to_next(4))
			)
			prog["xp"] = res["xp"]
			prog["level"] = res["level"]
	)
	await wait_frames(2)
	assert_eq(int(LevelReiseLogic.gefeierte(gs.state()).get("5", -1)), T0, "sofort gestempelt")
	# Bremse hält: eine Sekunde lang darf kein Fest feuern.
	var deadline := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_true(gefeiert.is_empty(), "Bremse hält ⇒ Fest wartet (kein Overlay-Stapel)")
	# Bühne frei: das Fest kommt — genau einmal.
	bremse.haelt = false
	var kam := await wait_until(func() -> bool: return not gefeiert.is_empty(), 5000)
	assert_true(kam, "nach dem Lösen feiert das Fest")
	assert_eq(gefeiert, [5] as Array[int], "genau EIN Fest für Level 5")
	# XP im selben Level nachlegen ⇒ level_changed feuert, aber KEIN 2. Fest.
	gs.update(
		func(s: Dictionary) -> void:
			var prog: Dictionary = s["progression"]
			prog["xp"] = float(prog["xp"]) + 1.0
	)
	await wait_frames(4)
	assert_eq(gefeiert.size(), 1, "kein Doppel-Fest nach weiterem XP")
	host.queue_free()
	await wait_frames(1)
	gs.free()
