extends TestCase
## EF-1 (EVAL-1 D2) — Sticker feiern GLOBAL: der RewardHub wertet die
## Freischaltbedingungen nach jeder Handlung aus (note_action → achievements-
## Signal) und feiert neue Sticker sofort — OHNE offenes Album, mit Toast
## auf der eigenen obersten Layer. Kein Doppel-Unlock, keine Doppel-Feier.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://ef1_tests/hub_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_hub_feiert_fuetterung_ohne_album() -> void:
	var gs := _fresh_gs()
	var host := Node.new()
	tree.root.add_child(host)
	var hub := RewardHub.attach_to(host, gs)
	assert_eq(RewardHub.attach_to(host, gs), hub, "attach_to ist idempotent")
	await wait_frames(1)
	var celebrated: Array = []
	hub.sticker_celebrated.connect(
		func(def: Dictionary) -> void: celebrated.append(str(def.get("id", "")))
	)
	# Handlung irgendwo im Spiel: erste Fütterung → feeds=1 → firstNom
	# (echter Katalog) — kein Album offen, nur der Hub.
	gs.update(
		func(state: Dictionary) -> void:
			var counters: Dictionary = state["achievements"]["counters"]
			counters["feeds"] = int(counters.get("feeds", 0)) + 1
	)
	RewardHub.note_action(gs)
	assert_true(
		gs.get_value("stickers.unlocked", {}).has("firstNom"),
		"Unlock persistiert sofort (Auswertung lief ohne Album)"
	)
	# Die Feier selbst kann in der Queue hinter dem Boot-Sticker warten.
	var gefeiert := await wait_until(func() -> bool: return celebrated.has("firstNom"), 9000)
	assert_true(gefeiert, "firstNom wird gefeiert (Queue): %s" % [celebrated])
	assert_true(hub._toasts.get_child_count() > 0, "Toast liegt auf der Hub-Layer")
	# Erneute Auswertung: kein Doppel-Unlock, keine Doppel-Feier.
	celebrated.clear()
	RewardHub.note_action(gs)
	await wait_frames(3)
	assert_false(celebrated.has("firstNom"), "keine Doppel-Feier")
	host.queue_free()
	await wait_frames(1)
	gs.free()


func test_note_action_ohne_gs_crasht_nicht() -> void:
	RewardHub.note_action(null)
	assert_true(true, "note_action(null) ist ein No-Op")
