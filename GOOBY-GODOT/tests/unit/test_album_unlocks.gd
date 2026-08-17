extends TestCase
## W3d — Sticker-Unlock-Regeln: cond-Vokabular (counter/special/event/code)
## pure gegen den Save-State + der signal-basierte StickerUnlocks-Service am
## echten GameState (kein Polling — slice_changed stößt die Auswertung an).

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000

var _dir_seq := 0


func _fresh_gs() -> Node:
	_dir_seq += 1
	var dir := "user://w3d_tests/al_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _state() -> Dictionary:
	return {
		"achievements": {"counters": {"feeds": 3, "washes": 0}},
		"progression": {"level": 7},
		"daily": {"streak": 4},
		"stickers": {"unlocked": {}, "hooks": {"gvz_kampagne": true}},
		"codes": {"redeemed": {"herz": 1}},
		"cosmetics":
		{
			"outfits":
			{"owned": ["a", "b"], "equipped": {"hat": "a", "glasses": null, "neck": null}},
			"fur": {"owned": ["cream"]},
		},
	}


func test_cond_met_counter() -> void:
	var state := _state()
	assert_true(StickerUnlocks.cond_met({"type": "counter", "key": "feeds", "count": 3}, state))
	assert_false(StickerUnlocks.cond_met({"type": "counter", "key": "feeds", "count": 4}, state))
	assert_false(StickerUnlocks.cond_met({"type": "counter", "key": "washes", "count": 1}, state))
	assert_false(StickerUnlocks.cond_met({"type": "counter", "key": "fehlt", "count": 1}, state))


func test_cond_met_special_event_code() -> void:
	var state := _state()
	assert_true(StickerUnlocks.cond_met({"type": "special", "key": "level", "count": 7}, state))
	assert_false(StickerUnlocks.cond_met({"type": "special", "key": "level", "count": 8}, state))
	assert_true(StickerUnlocks.cond_met({"type": "special", "key": "streak", "count": 4}, state))
	assert_true(StickerUnlocks.cond_met({"type": "special", "key": "first_boot"}, state))
	assert_false(
		StickerUnlocks.cond_met({"type": "special", "key": "unbekanntes_special"}, state),
		"unbekannte specials nie erfüllt"
	)
	assert_true(StickerUnlocks.cond_met({"type": "event", "key": "gvz_kampagne"}, state))
	assert_false(StickerUnlocks.cond_met({"type": "event", "key": "nie_gefeuert"}, state))
	state["stickers"]["hooks"]["kaputt"] = "ja"
	assert_false(
		StickerUnlocks.cond_met({"type": "event", "key": "kaputt"}, state),
		"feindlicher Nicht-Bool-Hook crasht nicht"
	)
	assert_true(StickerUnlocks.cond_met({"type": "code", "key": "herz"}, state))
	assert_false(StickerUnlocks.cond_met({"type": "code", "key": "anderer"}, state))
	assert_false(StickerUnlocks.cond_met({"type": "quatsch", "key": "x"}, state))


func test_newly_met_ueberspringt_unlocked() -> void:
	var catalog := [
		{"id": "s1", "cond": {"type": "counter", "key": "feeds", "count": 1}},
		{"id": "s2", "cond": {"type": "counter", "key": "feeds", "count": 99}},
		{"id": "s3", "cond": {"type": "event", "key": "gvz_kampagne"}},
	]
	var state := _state()
	state["stickers"]["unlocked"] = {"s3": NOW_MS}
	var fresh := StickerUnlocks.newly_met(catalog, state)
	assert_eq(fresh.size(), 1, "nur neue + erfüllte")
	assert_eq(fresh[0].get("id"), "s1")
	assert_true(StickerUnlocks.is_unlocked(state, "s3"))
	assert_false(StickerUnlocks.is_unlocked(state, "s1"))


func test_unlocked_count_ohne_geheime() -> void:
	var catalog := [
		{"id": "a"},
		{"id": "b", "secret": true},
		{"id": "c"},
	]
	var state := {"stickers": {"unlocked": {"a": 1, "b": 1}}}
	assert_eq(StickerUnlocks.unlocked_count(state, catalog), 1, "geheime zählen nicht")


func test_service_unlockt_signal_basiert() -> void:
	var gs := _fresh_gs()
	var catalog := [
		{"id": "erster_happs", "cond": {"type": "counter", "key": "feeds", "count": 2}},
		{"id": "gvz_sieg", "cond": {"type": "event", "key": "gvz_kampagne"}},
	]
	var service := StickerUnlocks.new()
	var unlocked_ids: Array = []
	service.sticker_unlocked.connect(func(def: Dictionary) -> void: unlocked_ids.append(def["id"]))
	service.attach(gs, catalog)
	assert_eq(unlocked_ids, [], "initial nichts erfüllt")
	gs.update(func(state: Dictionary) -> void: state["achievements"]["counters"]["feeds"] = 2)
	gs.notify_slice_changed("achievements")
	assert_eq(unlocked_ids, ["erster_happs"], "Counter-Signal → Unlock")
	assert_true(gs.get_value("stickers.unlocked", {}).has("erster_happs"), "persistiert")
	# Event-Hook feuert slice_changed("stickers") und unlockt den GvZ-Sticker.
	StickerUnlocks.fire_event_hook(gs, "gvz_kampagne")
	assert_eq(unlocked_ids, ["erster_happs", "gvz_sieg"], "Event-Hook → Unlock")
	# Erneutes Signal unlockt NICHT doppelt.
	gs.notify_slice_changed("achievements")
	assert_eq(unlocked_ids.size(), 2, "keine Doppel-Unlocks")
	service.free()
	gs.free()
