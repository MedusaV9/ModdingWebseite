extends TestCase
## W13/RANCH — Ranch ab Level 15 + Ranch-Random-Events: Level-Gate
## (Angebot bei 15, nicht bei 14), Events nur bei gekaufter Ranch,
## Kontext-Filter (Haus-Roll würfelt keine Ranch-Events), Scheduler-
## Determinismus mit injizierter Zeit/Zufall, Schema-Validität der vier
## neuen Defs und Reward-Gutschrift über die bestehenden Mechanismen.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const MITTAG := 720
const EVENTS_JSON := "res://content/events/data/events.json"
const BALANCE_JSON := "res://content/ranch/data/balance.json"
const RANCH_IDS := ["ausgebuext", "heudieb", "hufschmied", "karottenregen"]

var _dir_seq := 0


## Ranch-Szenen-Attrappe (Duck-Typing-Vertrag des RanchEventHosts).
class StubSzene:
	extends Node3D

	var gs: Object = null
	var meldungen: Array = []

	func game_state() -> Object:
		return gs

	func zeige_meldung(text: String) -> void:
		meldungen.append(text)

	func event_anker() -> Vector3:
		return Vector3(10.0, 0.0, 20.0)


func _fresh_gs(level := 15) -> Node:
	RanchState.register_slice()
	RandomEventEngine.register_slice()
	_dir_seq += 1
	var dir := "user://w13_tests/ev_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	SaveSchema.unregister_slice(RandomEventEngine.SLICE_ID)
	RanchState.reset_for_tests()
	RandomEventEngine.reset_for_tests()


func _alle_defs() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_JSON))
	assert_true(parsed is Dictionary, "events.json parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func _ranch_defs() -> Array:
	var out: Array = []
	for def: Variant in _alle_defs():
		if def is Dictionary and str((def as Dictionary).get("context", "home")) == "ranch":
			out.append(def)
	return out


func _ranch_def(id: String) -> Dictionary:
	return RandomEventEngine.def_by_id(_ranch_defs(), id)


## Immer-Trigger-Ranch-Def für deterministische Host-Tests.
func _sure_ranch_def(id := "w13_test", setup := "ranch_heudieb") -> Dictionary:
	return {
		"id": id,
		"context": "ranch",
		"weight": 1,
		"cooldown_days": 1,
		"trigger_window": ["00:00", "23:59"],
		"wahrscheinlichkeit": 1.0,
		"notification_text_de": "Testfall auf der Ranch!",
		"timeout_min": 8,
		"fail_text_de": "Gooby und die Pferde haben es alleine geregelt -_-",
		"reward": null,
		"ranch_reward": {"items": {"heu": 2}},
		"szene_setup": setup,
		"props": 3,
	}


## Host mit injizierter Zeit/Zufall an eine Stub-Szene hängen.
func _mount_host(gs: Object, defs: Array, seed_wert := 7) -> Array:
	var szene := StubSzene.new()
	szene.gs = gs
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	var host := RanchEventHost.new()
	host.name = "RanchEventHost"
	host.game_state_override = gs
	host.now_ms_override = NOW_MS
	host.minuten_override = MITTAG
	host.rng_override = rng
	szene.add_child(host)
	host.setup(szene, defs)
	return [szene, host]


# ── (a) Level-15-Gate ────────────────────────────────────────────────────────


func test_balance_pack_und_default_stehen_auf_15() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_JSON))
	assert_true(parsed is Dictionary, "balance.json parst")
	var werte: Dictionary = parsed.get("values", {})
	assert_eq(int((werte.get("ranch", {}) as Dictionary).get("freischalt_level", -1)), 15)
	assert_eq(RanchKatalog.DEFAULT_FREISCHALT_LEVEL, 15, "Fallback-Default = User-Wunsch 15")


func test_angebot_kommt_bei_15_nicht_bei_14() -> void:
	var gs := _fresh_gs(14)
	assert_false(RanchState.ist_freigeschaltet(gs), "Level 14 gesperrt")
	assert_false(RanchOffer.sollte_zeigen(gs), "Level 14: kein Angebot nach dem Rückblick")
	gs.set_value("progression.level", 15)
	assert_true(RanchState.ist_freigeschaltet(gs), "Level 15 offen")
	assert_true(RanchOffer.sollte_zeigen(gs), "Level 15: Angebot fällig")
	_teardown_gs(gs)


# ── (b) Schema der neuen Defs ────────────────────────────────────────────────


func test_ranch_defs_schema_valide() -> void:
	var defs := _ranch_defs()
	assert_eq(defs.size(), RANCH_IDS.size(), "genau 4 Ranch-Event-Defs")
	for def: Dictionary in defs:
		var id := str(def.get("id", ""))
		assert_true(RANCH_IDS.has(id), id + ": bekannte Ranch-Id")
		assert_eq(str(def.get("context", "")), "ranch", id + ": context ranch")
		assert_true(str(def.get("szene_setup", "")).begins_with("ranch_"), id + ": Ranch-Szene")
		assert_false(str(def.get("notification_text_de", "")).is_empty(), id + ": notification")
		assert_true(
			str(def.get("fail_text_de", "")).contains("alleine geregelt -_-"),
			id + ": knuffiger Fail-Text"
		)
		var timeout := int(def.get("timeout_min", 0))
		assert_true(timeout >= 5 and timeout <= 10, "%s: timeout_min 5-10 (%d)" % [id, timeout])
		assert_true(float(def.get("weight", 0)) > 0.0, id + ": weight > 0")
		assert_true(float(def.get("cooldown_days", 0)) > 0.0, id + ": cooldown_days > 0")
		var chance := float(def.get("wahrscheinlichkeit", 0.0))
		assert_true(chance > 0.0 and chance <= 1.0, id + ": Wahrscheinlichkeit (0..1]")
		var window: Array = def.get("trigger_window", [])
		assert_eq(window.size(), 2, id + ": trigger_window [von,bis]")
		for edge: Variant in window:
			assert_ne(RandomEventEngine.parse_minutes(str(edge)), -1, id + ": Fenster parst")
		assert_eq(def.get("reward"), null, id + ": kein Haus-Buff-Reward")
		var reward: Variant = def.get("ranch_reward")
		assert_true(
			reward is Dictionary and not (reward as Dictionary).is_empty(),
			id + ": ranch_reward gesetzt"
		)


# ── (b) Kontext-Filter + Determinismus ───────────────────────────────────────


func test_haus_roll_wuerfelt_keine_ranch_events() -> void:
	var slice := RandomEventEngine.default_slice()
	var defs := _alle_defs()
	for def: Dictionary in _ranch_defs():
		assert_false(
			RandomEventEngine.is_available(def, slice, NOW_MS, MITTAG),
			str(def.get("id")) + ": im Haus-Kontext nicht verfügbar"
		)
	for zehntel in 10:
		var chosen := RandomEventEngine.pick_event(
			defs, slice, NOW_MS, MITTAG, float(zehntel) / 10.0, 0.0
		)
		assert_false(
			RANCH_IDS.has(str(chosen.get("id", ""))),
			"Haus-Pick (roll %.1f) trifft nie ein Ranch-Event" % (float(zehntel) / 10.0)
		)


func test_ranch_roll_wuerfelt_nur_ranch_events() -> void:
	var slice := RandomEventEngine.default_slice()
	for zehntel in 10:
		var chosen := RandomEventEngine.pick_event(
			_alle_defs(), slice, NOW_MS, MITTAG, float(zehntel) / 10.0, 0.0, "ranch"
		)
		assert_true(
			RANCH_IDS.has(str(chosen.get("id", ""))),
			"Ranch-Pick (roll %.1f) trifft nur Ranch-Events" % (float(zehntel) / 10.0)
		)


func test_scheduler_determinismus_mit_injizierter_zeit() -> void:
	NotifyStub.reset_for_tests()
	var picks: Array[String] = []
	for runde in 2:
		var gs := _fresh_gs()
		gs.set_value("ranch.gekauft", true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var chosen := RandomEventEngine.roll_on_start(
			gs, _alle_defs(), NOW_MS, MITTAG, rng, "ranch"
		)
		picks.append(str(chosen.get("id", "")))
		_teardown_gs(gs)
	assert_eq(picks[0], picks[1], "gleicher Seed + gepinnte Zeit → gleiche Wahl")


# ── (b) Host: Gate + Szenen-Fluss ────────────────────────────────────────────


func test_host_rollt_nur_bei_gekaufter_ranch() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	var mounted := _mount_host(gs, [_sure_ranch_def()])
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "nicht gekauft = kein Event")
	assert_false((mounted[1] as RanchEventHost).is_running(), "Host bleibt still")
	(mounted[0] as Node).free()
	gs.set_value("ranch.gekauft", true)
	var aktiv := _mount_host(gs, [_sure_ranch_def()])
	assert_eq(RandomEventEngine.active_of(gs).get("id"), "w13_test", "gekauft = Event aktiv")
	assert_true((aktiv[1] as RanchEventHost).is_running(), "Szene läuft")
	(aktiv[0] as Node).free()
	_teardown_gs(gs)


func test_heudieb_szene_bis_zur_reward_gutschrift() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	gs.set_value("ranch.gekauft", true)
	var def := _sure_ranch_def()
	var mounted := _mount_host(gs, [def])
	var host: RanchEventHost = mounted[1]
	assert_true(host.is_running(), "Heudieb-Szene steht")
	var heu_vorher := int(gs.get_value("ranch.wirtschaft.lager.heu", 0))
	var geloest: Array = []
	host.event_resolved.connect(func(id: String) -> void: geloest.append(id))
	for tap in 3:
		host._on_kraehe_verscheucht()
	assert_eq(geloest, ["w13_test"], "3× tippen löst das Event")
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "active geräumt")
	assert_eq(int(gs.get_value("events.resolvedTotal", 0)), 1, "resolvedTotal zählt")
	assert_eq(
		int(gs.get_value("ranch.wirtschaft.lager.heu", 0)) - heu_vorher, 2, "Heu gerettet (+2)"
	)
	assert_false(host.is_running(), "Szene beendet")
	(mounted[0] as Node).free()
	_teardown_gs(gs)


func test_karottenregen_sammelt_maximal_props_karotten() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	gs.set_value("ranch.gekauft", true)
	var def := _ranch_def("karottenregen")
	RandomEventEngine.activate(gs, def, NOW_MS)
	var mounted := _mount_host(gs, [def])
	var host: RanchEventHost = mounted[1]
	assert_true(host.is_running(), "Karottenregen-Szene steht")
	var vorher := int(gs.get_value("inventory.food.carrot", 0))
	for tap in int(def.get("props", 10)):
		host._on_karotte_gesammelt()
	assert_eq(
		int(gs.get_value("inventory.food.carrot", 0)) - vorher,
		10,
		"max. 10 Karotten wandern ins Haupt-Inventar"
	)
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "Event gelöst")
	(mounted[0] as Node).free()
	_teardown_gs(gs)


func test_timeout_fail_text_der_pferde() -> void:
	NotifyStub.reset_for_tests()
	var gs := _fresh_gs()
	gs.set_value("ranch.gekauft", true)
	var def := _sure_ranch_def()
	RandomEventEngine.activate(gs, def, NOW_MS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spaeter := NOW_MS + 9 * 60_000
	var rolled := RandomEventEngine.roll_on_start(gs, [def], spaeter, MITTAG, rng, "ranch")
	assert_eq(rolled, {}, "abgelaufenes Event rollt nicht sofort neu")
	assert_eq(
		RandomEventEngine.take_fail_notice(gs),
		"Gooby und die Pferde haben es alleine geregelt -_-",
		"Ranch-Fail-Bubble-Text"
	)
	_teardown_gs(gs)


# ── (b) Reward-Gutschrift im Detail ──────────────────────────────────────────


func test_ausgebuext_reward_muenzen_und_bindung() -> void:
	var gs := _fresh_gs()
	gs.set_value("economy.coins", 100)
	gs.set_value("ranch.tiere.pferde", {"pony": {"bindung": 10.0}})
	var vergeben := RanchEventRewards.anwenden(gs, _ranch_def("ausgebuext"), NOW_MS)
	assert_eq(int(vergeben["muenzen"]), 25, "Münz-Reward laut Def")
	assert_eq(int(gs.get_value("economy.coins", 0)), 125, "Münzen gutgeschrieben")
	assert_almost(
		float(gs.get_value("ranch.tiere.pferde.pony.bindung", 0.0)),
		16.0,
		1e-9,
		"Pferde-Freundschaft +6"
	)
	_teardown_gs(gs)


func test_bindung_klemmt_bei_100() -> void:
	var gs := _fresh_gs()
	gs.set_value("ranch.tiere.pferde", {"pony": {"bindung": 98.0}})
	RanchEventRewards.bindung_gutschreiben(gs, "pony", 6.0)
	assert_almost(
		float(gs.get_value("ranch.tiere.pferde.pony.bindung", 0.0)), 100.0, 1e-9, "Deckel 100"
	)
	_teardown_gs(gs)


func test_hufschmied_buff_ist_zeitinjiziert_24h() -> void:
	var gs := _fresh_gs()
	var vergeben := RanchEventRewards.anwenden(gs, _ranch_def("hufschmied"), NOW_MS)
	assert_eq(int(vergeben["huf_check_until"]), NOW_MS + 24 * 3_600_000, "Ablauf = now + 24 h")
	assert_true(RanchEventRewards.huf_check_aktiv(gs, NOW_MS), "sofort aktiv")
	assert_true(
		RanchEventRewards.huf_check_aktiv(gs, NOW_MS + 23 * 3_600_000), "nach 23 h noch aktiv"
	)
	assert_false(
		RanchEventRewards.huf_check_aktiv(gs, NOW_MS + 25 * 3_600_000), "nach 25 h abgelaufen"
	)
	_teardown_gs(gs)


# ── Texte: DE/EN-Parität + I18n-Anbindung ────────────────────────────────────


func test_texte_de_en_paritaet_und_i18n_laedt() -> void:
	var de := _flach("res://strings/de/ranch_events.json")
	var en := _flach("res://strings/en/ranch_events.json")
	assert_true(de.size() > 0, "DE ist leer")
	for key: String in de:
		assert_true(en.has(key), "EN fehlt Key %s" % key)
	for key: String in en:
		assert_true(de.has(key), "DE fehlt Key %s" % key)
	for szenario in RANCH_IDS:
		assert_true(de.has("revents.%s.bubble" % szenario), szenario + ": bubble-Key")
		assert_true(de.has("revents.%s.danke" % szenario), szenario + ": danke-Key")
	assert_true(str(de["revents.karottenregen.danke"]).contains("{n}"), "DE-Platzhalter {n}")
	assert_true(str(en["revents.karottenregen.danke"]).contains("{n}"), "EN-Platzhalter {n}")
	assert_ne(
		I18nService.t("revents.heudieb.bubble"),
		"revents.heudieb.bubble",
		"I18nService lädt strings/*/ranch_events.json"
	)


func _flach(pfad: String) -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
	if parsed is Dictionary:
		_texte_flatten("", parsed, out)
	return out


func _texte_flatten(prefix: String, node: Dictionary, out: Dictionary) -> void:
	for key: String in node:
		var full := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_texte_flatten(full, node[key], out)
		else:
			out[full] = node[key]


func test_rewards_ohne_pferd_und_ohne_gs_sind_robust() -> void:
	var gs := _fresh_gs()
	# Kein Pferd im Bestand: Münzen kommen trotzdem, Bindung verpufft leise.
	var vergeben := RanchEventRewards.anwenden(gs, _ranch_def("ausgebuext"), NOW_MS)
	assert_eq(int(vergeben["muenzen"]), 25)
	assert_almost(float(vergeben["bindung"]), 0.0, 1e-9, "kein Ziel-Pferd = keine Bindung")
	assert_eq(RanchEventRewards.anwenden(null, _ranch_def("heudieb"), NOW_MS)["items"], {})
	_teardown_gs(gs)
