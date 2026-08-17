extends TestCase
## REST-3 Rang 6 — Krankheit: Ausloeser (schlechte Ernaehrung, wenig Schlaf,
## Kaelte, Vernachlaessigung), Grade (healthy → queasy → sick, EIN Uebergang
## pro Takt), Heilung (Ruhe, Medizin, Tierarzt) und die sanften Spiel-Folgen
## (fun x1.25, Minispiel-Gate NUR bei sick). Ende-zu-Ende gegen den ECHTEN
## GameState (Fuettern → Ticker → Events) plus pure Trigger-Matrix.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const Health := preload("res://scripts/logic/health.gd")
const GoobyTicker := preload("res://scripts/state/gooby_ticker.gd")
const SoulWetterScript := preload("res://scripts/soul/soul_wetter.gd")

const NOW_MS := 1768478400000
const MIN_MS := 60000

var _dir_seq := 0


func _fresh_path() -> String:
	_dir_seq += 1
	var dir := "user://rest3_tests/health_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir + "/save_v5.json"


func _fresh_game_state(now_ms := NOW_MS) -> Node:
	var gs: Node = GameStateScript.new()
	gs.clock.pin(now_ms)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(_fresh_path())
	return gs


func _feed(gs: Node, food_id: String, count: int) -> void:
	for _i in count:
		gs.update(func(s: Dictionary) -> void: FoodCatalog.apply_feed(s, food_id))


func _tick_1min(gs: Node) -> Array:
	var events_seen: Array = []
	var handler := func(ev: Array) -> void: events_seen.append_array(ev)
	gs.gooby_events.connect(handler)
	gs.clock.advance(1 * MIN_MS)
	gs.run_live_tick()
	gs.gooby_events.disconnect(handler)
	return events_seen


func test_junkfood_pfad_warnung_kraenklich_krank() -> void:
	var gs := _fresh_game_state()
	gs.set_value("gooby.stats.hunger", 10.0)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.update(func(s: Dictionary) -> void: s["inventory"]["food"]["cookie"] = 12)
	# 4 Kekse: junkScore 4 → naechster Takt warnt (Bauch gluckert), gesund.
	_feed(gs, "cookie", 4)
	var events := _tick_1min(gs)
	assert_true(events.has("tummyWarning"), "Warnrampe bei junkScore 4 (got %s)" % [events])
	assert_eq(str(gs.get_value("gooby.health.state")), "healthy", "Warnung ist keine Krankheit")
	# 2 weitere: junkScore ~6 → kraenklich.
	_feed(gs, "cookie", 2)
	events = _tick_1min(gs)
	assert_true(events.has("becameQueasy"), "becameQueasy (got %s)" % [events])
	assert_eq(str(gs.get_value("gooby.health.state")), "queasy")
	# 3 weitere: junkScore ~9 → richtig krank (nie eine Stufe uebersprungen).
	_feed(gs, "cookie", 3)
	events = _tick_1min(gs)
	assert_true(events.has("becameSick"), "becameSick (got %s)" % [events])
	assert_eq(str(gs.get_value("gooby.health.state")), "sick")
	assert_false(Health.can_play_minigame(gs.get_value("gooby.health")), "sick: Minispiel-Gate zu")
	gs.free()


func test_gesundes_essen_senkt_den_junkdruck() -> void:
	var h := Health.on_eat(null, true)
	h = Health.on_eat(h, true)
	assert_almost(float(h["junkScore"]), 2.0, 1e-6, "2x Junk = +2")
	h = Health.on_eat(h, false)
	assert_almost(float(h["junkScore"]), 1.5, 1e-6, "gesund = -0.5")
	for _i in 5:
		h = Health.on_eat(h, false)
	assert_almost(float(h["junkScore"]), 0.0, 1e-6, "Boden bei 0")


func test_trigger_matrix_vernachlaessigung_erschoepfung_kaelte() -> void:
	# Vernachlaessigung: >= 2 Stats unter 15 fuer 120 min → kraenklich.
	var res := Health.tick(null, 119.0, 2)
	assert_eq(str(res["h"]["state"]), "healthy", "119 min reichen nicht")
	res = Health.tick(res["h"], 1.0, 2)
	assert_eq(str(res["h"]["state"]), "queasy", "120 min Vernachlaessigung")
	# Pflege setzt sofort zurueck (nie eine Strafe).
	res = Health.tick(null, 100.0, 2)
	res = Health.tick(res["h"], 1.0, 0)
	assert_almost(float(res["h"]["neglectMin"]), 0.0, 1e-6, "Pflege tilgt neglectMin")
	# Erschoepfung (zu wenig Schlaf): 240 min → queasy, 720 min → sick.
	res = Health.tick(null, 240.0, 0, {"exhausted": true})
	assert_eq(str(res["h"]["state"]), "queasy", "240 min erschoepft")
	res = Health.tick(res["h"], 480.0, 0, {"exhausted": true})
	assert_eq(str(res["h"]["state"]), "sick", "720 min erschoepft")
	# Kaelte: 180 min durchgefroren → queasy; aufwaermen setzt zurueck.
	res = Health.tick(null, 180.0, 0, {"chill": true})
	assert_eq(str(res["h"]["state"]), "queasy", "180 min Kaelte")
	res = Health.tick(null, 100.0, 0, {"chill": true})
	res = Health.tick(res["h"], 1.0, 0, {"chill": false})
	assert_almost(float(res["h"]["chillMin"]), 0.0, 1e-6, "Waerme tilgt chillMin")


func test_chill_braucht_nasses_wetter_und_klamme_hygiene() -> void:
	# Deterministisch einen Regen-/Schnee-Moment und einen trockenen suchen.
	var nass_ms := -1
	var trocken_ms := -1
	for tag in 60:
		var unix := int(NOW_MS / 1000.0) + tag * 86400
		var date := Time.get_datetime_dict_from_unix_time(unix)
		var datum := "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]
		var wetter: Dictionary = SoulWetterScript.zustand(datum, float(date["hour"]))
		var ist_nass := bool(wetter.get("regen", false)) or bool(wetter.get("schnee", false))
		if ist_nass and nass_ms < 0:
			nass_ms = unix * 1000
		elif not ist_nass and trocken_ms < 0:
			trocken_ms = unix * 1000
		if nass_ms >= 0 and trocken_ms >= 0:
			break
	assert_true(nass_ms >= 0, "SoulWetter liefert in 60 Tagen mindestens einen nassen Moment")
	assert_true(trocken_ms >= 0, "und mindestens einen trockenen")
	var klamm := {"hygiene": 20.0}
	var sauber := {"hygiene": 80.0}
	assert_true(GoobyTicker._chill_active(klamm, nass_ms), "nass + klamm = friert")
	assert_false(GoobyTicker._chill_active(sauber, nass_ms), "gebadet friert nicht")
	assert_false(GoobyTicker._chill_active(klamm, trocken_ms), "trocken friert nicht")


func test_heilung_durch_ruhe() -> void:
	# Kraenklich + 60 durchgehend saubere Minuten → erholt (recovered).
	var res := Health.tick({"state": "queasy"}, 59.0, 0)
	assert_eq(str(res["h"]["state"]), "queasy", "59 min reichen noch nicht")
	res = Health.tick(res["h"], 1.0, 0)
	assert_eq(str(res["h"]["state"]), "healthy", "60 saubere Minuten heilen")
	assert_true(res["events"].has("recovered"), "recovered-Event")
	# Richtig krank heilt NIE von selbst — nur Medizin/Tierarzt.
	res = Health.tick({"state": "sick"}, 100000.0, 0)
	assert_eq(str(res["h"]["state"]), "sick", "sick braucht Hilfe")


func test_heilung_durch_medizin_im_save() -> void:
	var gs := _fresh_game_state()
	gs.set_value("gooby.health", {"state": "sick", "junkScore": 6.0})
	# Ohne Medizin: freundliche Ablehnung, nichts geht kaputt.
	var res := {"r": {}}
	gs.update(func(s: Dictionary) -> void: res["r"] = Health.use_medicine_state(s, NOW_MS))
	assert_false(bool(res["r"]["ok"]), "ohne Vorrat keine Medizin")
	assert_eq(str(res["r"]["reason"]), "none")
	# Mit Medizin (GOOBYTHEKE-Inventarpfad items.medicine): sick → queasy → healthy.
	gs.set_value("inventory.items.medicine", 2)
	gs.update(func(s: Dictionary) -> void: res["r"] = Health.use_medicine_state(s, NOW_MS))
	assert_true(bool(res["r"]["ok"]))
	assert_eq(str(gs.get_value("gooby.health.state")), "queasy", "Medizin: eine Stufe runter")
	gs.update(func(s: Dictionary) -> void: res["r"] = Health.use_medicine_state(s, NOW_MS))
	assert_eq(str(gs.get_value("gooby.health.state")), "healthy", "zweite Dosis heilt ganz")
	assert_eq(int(gs.get_value("inventory.items.medicine")), 0, "Vorrat verbraucht")
	assert_eq(int(gs.get_value("achievements.counters.medsGiven")), 2, "medsGiven-Zaehler")
	# Gesund: Medizin wird NICHT verschwendet.
	gs.set_value("inventory.items.medicine", 1)
	gs.update(func(s: Dictionary) -> void: res["r"] = Health.use_medicine_state(s, NOW_MS))
	assert_false(bool(res["r"]["ok"]))
	assert_eq(str(res["r"]["reason"]), "healthy")
	assert_eq(int(gs.get_value("inventory.items.medicine")), 1, "Dosis bleibt im Schrank")
	gs.free()


func test_kraenklich_verfaellt_der_spass_schneller() -> void:
	var gs := _fresh_game_state()
	gs.set_value("gooby.health", {"state": "queasy"})
	gs.set_value("gooby.stats.fun", 70.0)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.clock.advance(10 * MIN_MS)
	gs.run_live_tick()
	# §C3.3: fun x1.25 → 70 - 0.5*10*1.25 = 63.75 (statt 65.0 gesund).
	assert_almost(float(gs.get_value("gooby.stats.fun")), 63.75, 1e-6, "fun x1.25 kraenklich")
	gs.free()


func test_grade_und_minigame_gate_sind_sanft() -> void:
	assert_eq(Health.grade(null), 0, "leerer Slice = gesund")
	assert_eq(Health.grade({"state": "queasy"}), 1)
	assert_eq(Health.grade({"state": "sick"}), 2)
	assert_true(Health.can_play_minigame(null), "gesund spielt")
	assert_true(Health.can_play_minigame({"state": "queasy"}), "kraenklich spielt WEITER (sanft)")
	assert_false(Health.can_play_minigame({"state": "sick"}), "nur sick pausiert Minispiele")


func test_health_slice_ueberlebt_saven_und_laden() -> void:
	var path := _fresh_path()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(path)
	gs.set_value(
		"gooby.health", {"state": "queasy", "junkScore": 5.5, "tiredMin": 30.0, "chillMin": 12.0}
	)
	gs.set_value("gooby.weight", 63.0)
	assert_true(gs.save_now())
	gs.free()
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW_MS)
	gs2.clock.set_utc_offset_minutes(0)
	gs2.initialize(path)
	assert_eq(str(gs2.get_value("gooby.health.state")), "queasy", "state persistiert")
	assert_almost(float(gs2.get_value("gooby.health.tiredMin")), 30.0, 1e-6, "tiredMin additiv")
	assert_almost(float(gs2.get_value("gooby.health.chillMin")), 12.0, 1e-6, "chillMin additiv")
	assert_almost(float(gs2.get_value("gooby.weight")), 63.0, 1e-6, "weight persistiert")
	gs2.free()
