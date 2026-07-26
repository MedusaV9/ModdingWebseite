extends TestCase
## BACKLOG-REST — EventRunner-Szenen der 7 neuen Random-Events (Doc F §4.2)
## + Nutella-Voll-Fenster: jede Szene wird headless mit Fake-Raum/-Gooby
## durchgespielt (Taps/Choices direkt auf die Handler), geprüft werden
## Auflösung (active leer, resolvedTotal), Reward-Buffs, Stat-Deltas,
## Sticker-Hooks und die wegwischbare Nutella-Fleck-Requisite.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000
const EVENTS_JSON := "res://content/events/data/events.json"

var _dir_seq := 0


## Minimal-Rig: nimmt Emotionen entgegen (Node3D reicht für Posen-Tweens).
class FakeRig:
	extends Node3D

	var emotions: Array[String] = []

	func set_emotion(id: String) -> void:
		emotions.append(id)


## Minimal-Gooby mit der GoobyHome-API, die der EventRunner nutzt.
class FakeGooby:
	extends Node3D

	var rig: FakeRig = FakeRig.new()
	var wander := true
	var clips: Array[String] = []

	func _init() -> void:
		add_child(rig)

	func set_wander_enabled(enabled: bool) -> void:
		wander = enabled

	func play_clip(clip: String) -> void:
		clips.append(clip)

	func walk_to(_world_pos: Vector3, _timeout_s := 6.0) -> void:
		pass


## Minimal-Raum: game_state()/gooby()/say() — grid bleibt absichtlich weg.
class FakeRoom:
	extends Node3D

	var gs: Object = null
	var gooby_node: FakeGooby = FakeGooby.new()
	var bubbles: Array[String] = []

	func _init() -> void:
		add_child(gooby_node)

	func game_state() -> Object:
		return gs

	func gooby() -> Node:
		return gooby_node

	func say(text: String) -> void:
		bubbles.append(text)


func _fresh_gs() -> Node:
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	_dir_seq += 1
	var dir := "user://backlogrest_tests/ev_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _defs() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_JSON))
	return parsed.get("items", []) if parsed is Dictionary else []


## Raum + Runner mit aktiviertem Event aufbauen. Rückgabe {room, gs, runner}.
func _stage(event_id: String) -> Dictionary:
	var gs := _fresh_gs()
	var defs := _defs()
	var def := RandomEventEngine.def_by_id(defs, event_id)
	assert_false(def.is_empty(), event_id + ": Def existiert")
	RandomEventEngine.activate(gs, def, NOW_MS)
	var room := FakeRoom.new()
	room.gs = gs
	tree.root.add_child(room)
	var runner := EventRunner.attach_to(room, defs)
	return {"room": room, "gs": gs, "runner": runner, "def": def}


func _teardown(ctx: Dictionary) -> void:
	(ctx["room"] as Node).queue_free()
	await wait_frames(2)
	(ctx["gs"] as Node).free()


func _assert_resolved(ctx: Dictionary, hook := "") -> void:
	var gs: Object = ctx["gs"]
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "Event aufgelöst")
	assert_eq(int(gs.get_value("events.resolvedTotal", 0)), 1, "resolvedTotal zählt")
	assert_false((ctx["runner"] as EventRunner).is_running(), "Runner frei für das nächste Event")
	if not hook.is_empty():
		var hooks: Variant = gs.get_value("stickers.hooks", {})
		assert_true(hooks is Dictionary and (hooks as Dictionary).has(hook), "Hook %s" % hook)


func test_robo_jagd_weicht_zweimal_aus_dann_gefangen() -> void:
	var ctx := _stage("robo_jagd")
	var runner: EventRunner = ctx["runner"]
	assert_true(runner.is_running(), "Szene läuft")
	var hygiene_vorher := float((ctx["gs"] as Object).get_value("gooby.stats.hygiene", 0.0))
	runner._on_robo_tapped()
	assert_true(runner.is_running(), "1. Tap: ausgewichen")
	runner._on_robo_tapped()
	assert_true(runner.is_running(), "2. Tap: ausgewichen")
	runner._on_robo_tapped()
	_assert_resolved(ctx, "robo_jagd")
	var hygiene := float((ctx["gs"] as Object).get_value("gooby.stats.hygiene", 0.0))
	assert_true(hygiene > hygiene_vorher, "Boden sauber → Hygiene-Bonus")
	var buffs: Dictionary = (ctx["gs"] as Object).get_value("buffs", {})
	assert_almost(GoobyBuffs.stat_bonus(buffs, "fun", NOW_MS), 5.0, 1e-9, "+5 Spaß-Buff")
	await _teardown(ctx)


func test_kleber_stuhl_braucht_alle_rubbel_taps() -> void:
	var ctx := _stage("kleber_stuhl")
	var runner: EventRunner = ctx["runner"]
	var taps := int((ctx["def"] as Dictionary).get("props", 4))
	for i in taps - 1:
		runner._on_kleber_rubbed()
		assert_true(runner.is_running(), "Tap %d/%d: klebt noch" % [i + 1, taps])
	runner._on_kleber_rubbed()
	_assert_resolved(ctx)
	var gooby := (ctx["room"] as FakeRoom).gooby_node
	assert_true(gooby.clips.has("sit"), "saß auf dem Stuhl")
	await _teardown(ctx)


func test_wurm_freund_choice_giessen() -> void:
	var ctx := _stage("wurm_freund")
	var runner: EventRunner = ctx["runner"]
	assert_true(runner.is_running(), "Szene läuft")
	await runner._on_wurm_choice({"giessen": true})
	_assert_resolved(ctx, "wurm_freund")
	await _teardown(ctx)


func test_fernbedienung_nur_das_richtige_kissen() -> void:
	var ctx := _stage("fernbedienung")
	var runner: EventRunner = ctx["runner"]
	var tv: Node3D = runner._props[0]
	var falsch := (runner._remote_index + 1) % 3
	runner._on_cushion_tapped(falsch, tv)
	assert_true(runner.is_running(), "falsches Kissen löst nicht")
	runner._on_cushion_tapped(runner._remote_index, tv)
	_assert_resolved(ctx)
	var buffs: Dictionary = (ctx["gs"] as Object).get_value("buffs", {})
	assert_almost(GoobyBuffs.stat_bonus(buffs, "energy", NOW_MS), 5.0, 1e-9, "Energie-Regen-Buff")
	await _teardown(ctx)


func test_karton_gooby_raus_da() -> void:
	var ctx := _stage("karton_gooby")
	var runner: EventRunner = ctx["runner"]
	await runner._on_karton_choice({"raus": true})
	_assert_resolved(ctx, "karton_gooby")
	var gooby := (ctx["room"] as FakeRoom).gooby_node
	assert_true(gooby.clips.has("hop"), "Hop aus dem Karton")
	await _teardown(ctx)


func test_gewitter_finden_dann_streicheln() -> void:
	var ctx := _stage("gewitter_angst")
	var runner: EventRunner = ctx["runner"]
	var gooby := (ctx["room"] as FakeRoom).gooby_node
	assert_false(gooby.visible, "Gooby ist WEG (nur Augen)")
	runner._on_gewitter_found()
	assert_true(gooby.visible, "gefunden → sichtbar")
	assert_true(runner.is_running(), "noch nicht beruhigt")
	runner._on_gewitter_petted()
	_assert_resolved(ctx, "gewitter_angst")
	assert_true(gooby.clips.has("sleep"), "schläft danach sofort ein")
	await _teardown(ctx)


func test_mehl_unfall_abklopfen_plus_pfannkuchen() -> void:
	var ctx := _stage("mehl_unfall")
	var runner: EventRunner = ctx["runner"]
	var gs: Object = ctx["gs"]
	gs.update(func(s: Dictionary) -> void: s["gooby"]["stats"]["hunger"] = 50.0)
	var taps := int((ctx["def"] as Dictionary).get("props", 5))
	for i in taps - 1:
		runner._on_mehl_klopfen()
		assert_true(runner.is_running(), "Klopfer %d/%d" % [i + 1, taps])
	runner._on_mehl_klopfen()
	_assert_resolved(ctx, "mehl_unfall")
	assert_almost(
		float(gs.get_value("gooby.stats.hunger", 0.0)), 62.0, 1e-6, "Pfannkuchen: +12 Hunger"
	)
	await _teardown(ctx)


func test_nutella_voll_fenster_weitermachen() -> void:
	var ctx := _stage("nutella_nacht")
	var runner: EventRunner = ctx["runner"]
	var gs: Object = ctx["gs"]
	gs.update(
		func(s: Dictionary) -> void:
			s["gooby"]["stats"]["fun"] = 50.0
			s["gooby"]["stats"]["energy"] = 50.0
	)
	await runner._on_nutella_choice({"to_bed": false})
	_assert_resolved(ctx)
	assert_almost(float(gs.get_value("gooby.stats.fun", 0.0)), 60.0, 1e-6, "+10 Freude")
	assert_almost(float(gs.get_value("gooby.stats.energy", 0.0)), 45.0, 1e-6, "−5 Energie")
	assert_eq(RandomEventEngine.fail_prop_of(gs), "", "aufgelöst → kein Fleck-Beweis")
	await _teardown(ctx)


func test_nutella_fleck_im_raum_wegwischen() -> void:
	var gs := _fresh_gs()
	var defs := _defs()
	# Verpasste Nutella-Nacht simulieren: fail_active hinterlässt den Fleck.
	var def := RandomEventEngine.def_by_id(defs, "nutella_nacht")
	RandomEventEngine.activate(gs, def, NOW_MS)
	RandomEventEngine.fail_active(gs, defs, NOW_MS + 30 * 60_000)
	var room := FakeRoom.new()
	room.gs = gs
	tree.root.add_child(room)
	var runner := EventRunner.attach_to(room, defs)
	assert_false(runner.is_running(), "kein aktives Event mehr")
	assert_true(runner.get_child_count() > 0, "Fleck-Requisite steht im Raum")
	runner._on_fail_prop_wiped()
	assert_eq(RandomEventEngine.fail_prop_of(gs), "", "Tap wischt den Beweis weg")
	room.queue_free()
	await wait_frames(2)
	gs.free()
