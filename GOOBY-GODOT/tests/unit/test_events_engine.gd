extends TestCase
## W3d — Random-Event-Engine: pure Kernlogik (Fenster/Cooldown/Roll/Timeout),
## Store-Glue (roll_on_start/resolve/fail → Fail-Bubble), Reward-Buffs und
## NotifyStub-Schema. Event-Defs kommen aus content/events/data/events.json.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000
const EVENTS_JSON := "res://content/events/data/events.json"
const EVENT_IDS := [
	"hingefallen",
	"kuehlschrank",
	"glas",
	"teller",
	"nutella_nacht",
	"sockensuche",
	"robo_jagd",
	"kleber_stuhl",
	"wurm_freund",
	"fernbedienung",
	"karton_gooby",
	"gewitter_angst",
	"mehl_unfall",
]
## Album/HUD-Keys, die die Runner-Szenen wirklich referenzieren.
const USED_KEYS := [
	"events.marienkaefer.bubble",
	"events.marienkaefer.danke",
	"events.kuehlschrank.bubble",
	"events.kuehlschrank.danke",
	"events.glas.bubble",
	"events.teller.bubble",
	"events.scherben.danke",
	"events.nutella.upps",
	"events.nutella.ab_ins_bett",
	"events.nutella.weitermachen",
	"events.nutella.murmel",
	"events.nutella.strahlen",
	"events.nutella.aufraeumen",
	"events.nutella.fleck_weg",
	"events.sockensuche.bubble",
	"events.sockensuche.danke",
	"events.robo.bubble",
	"events.robo.ausweichen",
	"events.robo.danke",
	"events.kleber.bubble",
	"events.kleber.rubbel",
	"events.kleber.plopp",
	"events.wurm.bubble",
	"events.wurm.draussen",
	"events.wurm.giessen",
	"events.wurm.winken",
	"events.wurm.giessen_danke",
	"events.fernbedienung.bubble",
	"events.fernbedienung.nix",
	"events.fernbedienung.danke",
	"events.karton.bubble",
	"events.karton.raus",
	"events.karton.moebel",
	"events.karton.raus_danke",
	"events.karton.moebel_ok",
	"events.karton.moebel_ende",
	"events.gewitter.bubble",
	"events.gewitter.gefunden",
	"events.gewitter.danke",
	"events.mehl.bubble",
	"events.mehl.danke",
	"events.story.hinweis",
	"events.story.kichern",
	"events.story.einschlafen",
]
## Szenen-Hooks, die der EventRunner tatsächlich implementiert (start()-match).
const RUNNER_SETUPS := [
	"marienkaefer",
	"kuehlschrank",
	"glas_scherben",
	"teller_scherben",
	"nutella_nacht",
	"sockensuche",
	"robo_jagd",
	"kleber_stuhl",
	"wurm_freund",
	"fernbedienung",
	"karton_gooby",
	"gewitter_angst",
	"mehl_unfall",
]

var _dir_seq := 0


func _fresh_gs() -> Node:
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	_dir_seq += 1
	var dir := "user://w3d_tests/ev_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _defs() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_JSON))
	assert_true(parsed is Dictionary, "events.json parst")
	return parsed.get("items", []) if parsed is Dictionary else []


## Immer-Trigger-Def für deterministische Glue-Tests (Gate 1.0 → randf()<1).
func _sure_def(id := "testfall") -> Dictionary:
	return {
		"id": id,
		"weight": 1,
		"cooldown_days": 1,
		"trigger_window": ["00:00", "23:59"],
		"wahrscheinlichkeit": 1.0,
		"notification_text_de": "Testfall!",
		"timeout_min": 8,
		"fail_text_de": "Gooby hat es schon alleine hingekriegt -_-",
		"reward": {"buff_id": "spass_plus", "stat": "fun", "wert": 10, "dauer_h": 5},
		"szene_setup": "marienkaefer",
	}


func test_parse_minutes_und_fenster() -> void:
	assert_eq(RandomEventEngine.parse_minutes("08:00"), 480)
	assert_eq(RandomEventEngine.parse_minutes("22:30"), 1350)
	assert_eq(RandomEventEngine.parse_minutes("24:00"), -1, "24:00 ist kaputt")
	assert_eq(RandomEventEngine.parse_minutes("quatsch"), -1)
	assert_true(RandomEventEngine.window_contains(["08:00", "22:00"], 480), "Fensterstart")
	assert_true(RandomEventEngine.window_contains(["08:00", "22:00"], 1320), "Fensterende")
	assert_false(RandomEventEngine.window_contains(["08:00", "22:00"], 479), "davor")
	# Übernacht-Fenster (Nutella-Nacht 22:30→03:00) wrappt über Mitternacht.
	assert_true(RandomEventEngine.window_contains(["22:30", "03:00"], 1351), "23-Uhr-Seite")
	assert_true(RandomEventEngine.window_contains(["22:30", "03:00"], 60), "1-Uhr-Seite")
	assert_false(RandomEventEngine.window_contains(["22:30", "03:00"], 720), "mittags nicht")
	assert_true(RandomEventEngine.window_contains([], 720), "leeres Fenster = immer")


func test_is_available_cooldown_und_aktiv() -> void:
	var def := _sure_def()
	var slice := RandomEventEngine.default_slice()
	assert_true(RandomEventEngine.is_available(def, slice, NOW_MS, 720), "frisch verfügbar")
	slice["cooldowns"]["testfall"] = NOW_MS + 1
	assert_false(RandomEventEngine.is_available(def, slice, NOW_MS, 720), "Cooldown blockt")
	slice["cooldowns"]["testfall"] = NOW_MS
	assert_true(RandomEventEngine.is_available(def, slice, NOW_MS, 720), "Cooldown abgelaufen")
	slice["active"] = {"id": "anderes"}
	assert_false(RandomEventEngine.is_available(def, slice, NOW_MS, 720), "aktives Event blockt")


func test_pick_event_gewichtet_deterministisch() -> void:
	var a := _sure_def("a")
	a["weight"] = 3
	var b := _sure_def("b")
	b["weight"] = 1
	var slice := RandomEventEngine.default_slice()
	var low := RandomEventEngine.pick_event([a, b], slice, NOW_MS, 720, 0.0, 0.0)
	assert_eq(low.get("id"), "a", "roll 0.0 → erstes Gewicht")
	var high := RandomEventEngine.pick_event([a, b], slice, NOW_MS, 720, 0.9, 0.0)
	assert_eq(high.get("id"), "b", "roll 0.9 → hinteres Gewicht")
	a["wahrscheinlichkeit"] = 0.35
	var gated := RandomEventEngine.pick_event([a, b], slice, NOW_MS, 720, 0.0, 0.35)
	assert_eq(gated, {}, "Gate-Roll >= Wahrscheinlichkeit → nichts")
	var passed := RandomEventEngine.pick_event([a, b], slice, NOW_MS, 720, 0.0, 0.349)
	assert_eq(passed.get("id"), "a", "Gate-Roll < Wahrscheinlichkeit → Event")


func test_timeout_und_cooldown_deadlines() -> void:
	var def := _sure_def()
	assert_eq(RandomEventEngine.timeout_deadline(def, NOW_MS), NOW_MS + 8 * 60_000)
	assert_eq(RandomEventEngine.cooldown_until(def, NOW_MS), NOW_MS + 86_400_000)
	var active := {"id": "x", "timeout_ms": NOW_MS + 100}
	assert_false(RandomEventEngine.is_timed_out(active, NOW_MS + 99))
	assert_true(RandomEventEngine.is_timed_out(active, NOW_MS + 100))
	assert_false(RandomEventEngine.is_timed_out({}, NOW_MS), "kein aktives = kein Timeout")


func test_events_json_defs_vollstaendig() -> void:
	var defs := _defs()
	assert_eq(defs.size(), EVENT_IDS.size(), "13 Event-Defs (M1-6 + Backlog F §4.2)")
	var seen := {}
	for def: Dictionary in defs:
		var id := str(def.get("id", ""))
		seen[id] = true
		assert_true(EVENT_IDS.has(id), "%s: bekannte Event-Id" % id)
		assert_false(str(def.get("notification_text_de", "")).is_empty(), id + ": notification")
		assert_false(str(def.get("fail_text_de", "")).is_empty(), id + ": fail_text")
		var setup := str(def.get("szene_setup", ""))
		assert_true(RUNNER_SETUPS.has(setup), "%s: Runner kennt Szene '%s'" % [id, setup])
		_check_timeout(def)
		var chance := float(def.get("wahrscheinlichkeit", 0.0))
		assert_true(chance > 0.0 and chance <= 1.0, id + ": Wahrscheinlichkeit (0..1]")
		assert_true(float(def.get("weight", 0)) > 0.0, id + ": weight > 0")
		assert_true(float(def.get("cooldown_days", 0)) > 0.0, id + ": cooldown_days > 0")
		var window: Array = def.get("trigger_window", [])
		assert_eq(window.size(), 2, id + ": trigger_window [von,bis]")
		for edge: Variant in window:
			assert_ne(RandomEventEngine.parse_minutes(str(edge)), -1, id + ": Fenster parst")
		var reward: Variant = def.get("reward")
		if reward is Dictionary:
			assert_false(str(reward.get("buff_id", "")).is_empty(), id + ": reward.buff_id")
			assert_false(str(reward.get("stat", "")).is_empty(), id + ": reward.stat")
			assert_true(float(reward.get("dauer_h", 0)) > 0.0, id + ": reward.dauer_h")
	assert_eq(seen.size(), EVENT_IDS.size(), "Ids eindeutig")


## timeout_min: Zahl 5..10 ODER Spanne [min,max] innerhalb 5..30 (Nutella
## Voll-Fenster: 10–20 min, Doc F §4.2).
func _check_timeout(def: Dictionary) -> void:
	var id := str(def.get("id", ""))
	var raw: Variant = def.get("timeout_min", 0)
	if raw is Array:
		assert_eq((raw as Array).size(), 2, id + ": Timeout-Spanne [min,max]")
		var lo := float((raw as Array)[0])
		var hi := float((raw as Array)[1])
		assert_true(lo >= 5.0 and hi <= 30.0 and lo <= hi, id + ": Spanne plausibel")
	else:
		var timeout := int(raw)
		assert_true(timeout >= 5 and timeout <= 10, "%s: timeout_min 5-10 (%d)" % [id, timeout])


func test_roll_on_start_aktiviert_und_plant_notification() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var chosen := RandomEventEngine.roll_on_start(gs, [_sure_def()], NOW_MS, 720, rng)
	assert_eq(chosen.get("id"), "testfall", "Gate 1.0 aktiviert immer")
	var active := RandomEventEngine.active_of(gs)
	assert_eq(active.get("id"), "testfall")
	assert_eq(int(active.get("timeout_ms")), NOW_MS + 8 * 60_000)
	assert_eq(active.get("szene"), "marienkaefer")
	var pending := NotifyStub.pending()
	assert_eq(pending.size(), 1, "Notification geplant")
	assert_eq(pending[0]["id"], "event_testfall")
	assert_eq(pending[0]["body"], "Testfall!")
	# Zweiter Start im selben Moment: aktives Event blockt Neu-Roll.
	var again := RandomEventEngine.roll_on_start(gs, [_sure_def()], NOW_MS, 720, rng)
	assert_eq(again, {}, "max. 1 aktives Event")
	gs.free()


func test_timeout_fail_bubble_beim_naechsten_start() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	var defs := [_sure_def()]
	RandomEventEngine.activate(gs, defs[0], NOW_MS)
	var later := NOW_MS + 9 * 60_000
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rolled := RandomEventEngine.roll_on_start(gs, defs, later, 729, rng)
	assert_eq(rolled, {}, "abgelaufenes Event rollt nicht sofort neu")
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "active geräumt")
	var notice := RandomEventEngine.take_fail_notice(gs)
	assert_eq(notice, "Gooby hat es schon alleine hingekriegt -_-", "Fail-Bubble-Text")
	assert_eq(RandomEventEngine.take_fail_notice(gs), "", "nur einmal abholbar")
	assert_eq(NotifyStub.pending().size(), 0, "Notification storniert")
	gs.free()


func test_resolve_gewaehrt_reward_buff() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	var defs := [_sure_def()]
	RandomEventEngine.activate(gs, defs[0], NOW_MS)
	RandomEventEngine.resolve_active(gs, defs, NOW_MS)
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "active geräumt")
	assert_eq(int(gs.get_value("events.resolvedTotal", 0)), 1, "resolvedTotal zählt")
	var buffs: Dictionary = gs.get_value("buffs", {})
	assert_almost(GoobyBuffs.stat_bonus(buffs, "fun", NOW_MS), 10.0, 1e-9, "+10 Spaß aktiv")
	assert_almost(
		GoobyBuffs.stat_bonus(buffs, "fun", NOW_MS + 5 * 3_600_000),
		0.0,
		1e-9,
		"nach 5 h abgelaufen"
	)
	assert_eq(NotifyStub.pending().size(), 0, "Notification storniert")
	gs.free()


func test_buffs_pure_kein_stacking() -> void:
	var slice := GoobyBuffs.default_slice()
	GoobyBuffs.add_buff(slice, "spass_plus", "fun", 10.0, 5.0, NOW_MS)
	GoobyBuffs.add_buff(slice, "spass_plus", "fun", 12.0, 2.0, NOW_MS)
	assert_eq((slice["aktiv"] as Array).size(), 1, "gleiche id ersetzt (kein Stacking)")
	assert_almost(GoobyBuffs.stat_bonus(slice, "fun", NOW_MS), 12.0, 1e-9)
	GoobyBuffs.add_buff(slice, "hunger_effizienz", "hunger", 8.0, 4.0, NOW_MS)
	assert_eq((slice["aktiv"] as Array).size(), 2, "andere id stapelt daneben")
	assert_eq(GoobyBuffs.prune(slice, NOW_MS + 3 * 3_600_000), 1, "abgelaufene geprunt")
	assert_eq((slice["aktiv"] as Array).size(), 1)


func test_notify_stub_schema() -> void:
	NotifyStub.reset_for_tests()
	NotifyStub.schedule_local("a", "GOOBY", "spät", NOW_MS + 50)
	NotifyStub.schedule_local("b", "GOOBY", "früh", NOW_MS + 10)
	NotifyStub.schedule_local("a", "GOOBY", "ersetzt", NOW_MS + 5)
	var pending := NotifyStub.pending()
	assert_eq(pending.size(), 2, "gleiche id ersetzt")
	assert_eq(pending[0]["body"], "ersetzt", "sortiert nach at_ms")
	NotifyStub.cancel_local("b")
	assert_eq(NotifyStub.pending().size(), 1)
	var due := NotifyStub.take_due(NOW_MS + 5)
	assert_eq(due.size(), 1, "fällige entnommen")
	assert_eq(NotifyStub.pending().size(), 0)


func test_timeout_spanne_deterministisch() -> void:
	var def := _sure_def()
	def["timeout_min"] = [10, 20]
	assert_eq(
		RandomEventEngine.timeout_deadline(def, NOW_MS, 0.0),
		NOW_MS + 10 * 60_000,
		"roll 0.0 → Untergrenze"
	)
	assert_eq(
		RandomEventEngine.timeout_deadline(def, NOW_MS, 1.0),
		NOW_MS + 20 * 60_000,
		"roll 1.0 → Obergrenze"
	)
	assert_eq(
		RandomEventEngine.timeout_deadline(def, NOW_MS, 0.5),
		NOW_MS + 15 * 60_000,
		"roll 0.5 → Mitte"
	)
	# Kaputte Spannen fallen auf plausible Werte zurück.
	def["timeout_min"] = [0, 20]
	var lo := RandomEventEngine.timeout_deadline(def, NOW_MS, 0.0)
	assert_true(lo >= NOW_MS + 60_000, "min. 1 Minute")
	def["timeout_min"] = 8
	assert_eq(RandomEventEngine.timeout_deadline(def, NOW_MS), NOW_MS + 8 * 60_000, "Zahl wie M1")


func test_fail_prop_bleibt_bis_zum_wegwischen() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	var def := _sure_def("nutella_test")
	def["fail_prop"] = "nutella_fleck"
	RandomEventEngine.activate(gs, def, NOW_MS)
	RandomEventEngine.fail_active(gs, [def], NOW_MS + 9 * 60_000)
	assert_eq(RandomEventEngine.fail_prop_of(gs), "nutella_fleck", "Fleck-Beweis liegt")
	# Fail-Bubble ist einmalig, der Fleck bleibt bis zum Wegwischen.
	assert_ne(RandomEventEngine.take_fail_notice(gs), "", "Fail-Bubble da")
	assert_eq(RandomEventEngine.fail_prop_of(gs), "nutella_fleck", "Fleck überlebt die Bubble")
	RandomEventEngine.clear_fail_prop(gs)
	assert_eq(RandomEventEngine.fail_prop_of(gs), "", "weggewischt")
	gs.free()


func test_fail_ohne_prop_hinterlaesst_nichts() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	var def := _sure_def()
	RandomEventEngine.activate(gs, def, NOW_MS)
	RandomEventEngine.fail_active(gs, [def], NOW_MS + 9 * 60_000)
	assert_eq(RandomEventEngine.fail_prop_of(gs), "", "kein fail_prop → kein Beweis")
	gs.free()


func test_roll_on_start_deterministisch_pro_seed() -> void:
	var defs := _defs()
	# Zwei Engines mit gleichem Seed treffen im Nachtfenster (23:30) dieselbe
	# Entscheidung — Grundlage für reproduzierbare Bug-Reports.
	var picks: Array[String] = []
	for round_i in 2:
		var gs := _fresh_gs()
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var chosen := RandomEventEngine.roll_on_start(gs, defs, NOW_MS, 23 * 60 + 30, rng)
		picks.append(str(chosen.get("id", "")))
		gs.free()
	assert_eq(picks[0], picks[1], "gleicher Seed → gleiche Wahl")


func test_neue_events_haben_sticker_hooks() -> void:
	var defs := _defs()
	for id: String in ["robo_jagd", "wurm_freund", "karton_gooby", "gewitter_angst", "mehl_unfall"]:
		var def := RandomEventEngine.def_by_id(defs, id)
		assert_false(def.is_empty(), id + ": Def existiert")
		assert_false(str(def.get("sticker_hook", "")).is_empty(), id + ": sticker_hook gesetzt")


func test_de_en_paritaet_events_domain() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in USED_KEYS:
		assert_true(de.has(key), "DE fehlt Key: %s" % key)
	for key: String in de:
		if key.begins_with("events."):
			assert_true(en.has(key), "EN fehlt Key: %s" % key)
	for key: String in en:
		if key.begins_with("events."):
			assert_true(de.has(key), "DE fehlt Key: %s" % key)
