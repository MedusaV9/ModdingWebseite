extends TestCase
## W13B GESCHICHTEN — Schüttel-Secret: deterministische Stufen-Erkennung
## (synthetische Beschleunigungs-Sequenzen → Stufe 1/2/3), Gravitation/
## Kippen löst nichts aus, Abklingen, 10-min-Cooldown (zeitinjiziert) und
## Counter-Inkremente (`shakes`/`shakeStage3`) über den GameState.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000
const DT := 1.0 / 60.0
const GRAVITY := Vector3(0.0, -9.8, 0.0)

var _dir_seq := 0


class FakeRig:
	extends Node3D

	var emotions: Array[String] = []
	var clips: Array[String] = []

	func set_emotion(id: String) -> void:
		emotions.append(id)

	func play_clip(clip: String) -> void:
		clips.append(clip)


## Minimal-Gooby mit der GoobyHome-API, die das Secret nutzt.
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

	func cancel_walk() -> void:
		pass


## Fake-Raum fürs Secret: GameState + optionaler Gooby, kein Baumodus.
class FakeRoom:
	extends Node3D

	var gs: Object
	var gooby_node: Node = null
	var build_active := false
	var bubbles: Array[String] = []

	func game_state() -> Object:
		return gs

	func gooby() -> Node:
		return gooby_node

	func is_build_mode_active() -> bool:
		return build_active

	func say(text: String) -> void:
		bubbles.append(text)


## Schüttel-Sequenz: alternierende Rest-Beschleunigung ±staerke auf X über
## der Gravitation — deterministisch, kein Zufall.
func _shake(logic: ShakeLogic, staerke: float, sekunden: float) -> int:
	var stage := logic.stage()
	var samples := int(round(sekunden / DT))
	for i in samples:
		var richtung := 1.0 if i % 2 == 0 else -1.0
		stage = logic.feed(GRAVITY + Vector3(staerke * richtung, 0.0, 0.0), DT)
	return stage


func _ruhe(logic: ShakeLogic, sekunden: float) -> int:
	var stage := logic.stage()
	for _i in int(round(sekunden / DT)):
		stage = logic.feed(GRAVITY, DT)
	return stage


func _fresh_game_state() -> Node:
	_dir_seq += 1
	var dir := "user://w13b_tests/shake_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_ruhe_und_kippen_loesen_nichts_aus() -> void:
	var logic := ShakeLogic.new()
	assert_eq(_ruhe(logic, 3.0), 0, "ruhig liegen = Stufe 0")
	assert_almost(logic.energy, 0.0, 0.001, "keine Energie im Stillstand")
	# Gerät kippen (Gravitation wandert auf eine andere Achse): der Low-Pass
	# schluckt den Übergang — keine Stufe.
	var gekippt := Vector3(6.93, -6.93, 0.0)
	for _i in int(round(3.0 / DT)):
		logic.feed(gekippt, DT)
	assert_eq(logic.stage(), 0, "Kippen ist kein Schütteln")
	assert_true(logic.energy < ShakeLogic.STAGE1_ENERGY, "Energie bleibt unter Stufe 1")


func test_stufen_eskalation_deterministisch() -> void:
	var logic := ShakeLogic.new()
	logic.feed(GRAVITY, DT)
	# ~1 s leichtes Schütteln → Stufe 1 (und noch nicht 2).
	var stage := _shake(logic, 6.5, 1.2)
	assert_eq(stage, 1, "leicht ~1 s = Stufe 1 (energy=%f)" % logic.energy)
	# weiter kräftig bis ~2.5 s → Stufe 2.
	stage = _shake(logic, 9.0, 1.3)
	assert_eq(stage, 2, "kräftig ~2.5 s = Stufe 2 (energy=%f)" % logic.energy)
	# wild bis ~4 s → Stufe 3.
	stage = _shake(logic, 14.0, 1.5)
	assert_eq(stage, 3, "wild ~4 s = Stufe 3 (energy=%f)" % logic.energy)


func test_abklingen_nach_ruhe() -> void:
	var logic := ShakeLogic.new()
	logic.feed(GRAVITY, DT)
	assert_eq(_shake(logic, 6.5, 1.2), 1, "erst Stufe 1")
	var energie_vorher := logic.energy
	_ruhe(logic, 1.0)
	assert_true(logic.energy < energie_vorher, "Energie klingt ab")
	assert_eq(_ruhe(logic, 2.0), 0, "nach Ruhe wieder Stufe 0")
	assert_almost(logic.energy, 0.0, 0.001)


func test_reset_und_stage_for_energy() -> void:
	assert_eq(ShakeLogic.stage_for_energy(0.0), 0)
	assert_eq(ShakeLogic.stage_for_energy(4.1), 1)
	assert_eq(ShakeLogic.stage_for_energy(9.1), 2)
	assert_eq(ShakeLogic.stage_for_energy(15.1), 3)
	var logic := ShakeLogic.new()
	logic.feed(GRAVITY, DT)
	_shake(logic, 14.0, 3.0)
	logic.reset()
	assert_eq(logic.stage(), 0, "reset leert die Energie")
	assert_almost(logic.energy, 0.0, 0.0)


func test_cooldown_zeitinjiziert() -> void:
	assert_true(ShakeLogic.cooldown_ready(0, NOW_MS), "nie ausgelöst = bereit")
	assert_false(ShakeLogic.cooldown_ready(NOW_MS, NOW_MS), "frisch = gesperrt")
	assert_false(
		ShakeLogic.cooldown_ready(NOW_MS, NOW_MS + ShakeLogic.COOLDOWN_MS - 1), "9:59 gesperrt"
	)
	assert_true(ShakeLogic.cooldown_ready(NOW_MS, NOW_MS + ShakeLogic.COOLDOWN_MS), "10 min frei")


func test_secret_counter_und_cooldown_im_node() -> void:
	var gs := _fresh_game_state()
	var room := FakeRoom.new()
	room.gs = gs
	tree.root.add_child(room)
	var secret := ShakeSecret.attach_to(room)
	# Testtreiber: _process stilllegen, Samples laufen nur über ingest().
	secret.set_process(false)
	var now := NOW_MS
	# Wilde Sequenz bis Stufe 3: Episode zählt shakes 1× und shakeStage3 1×.
	_drive(secret, 14.0, 4.0, now)
	assert_eq(int(gs.get_value("achievements.counters.shakes", 0)), 1, "shakes zählt Episode")
	assert_eq(int(gs.get_value("achievements.counters.shakeStage3", 0)), 1, "shakeStage3 zählt")
	assert_eq(secret.cooldown_until_ms(), now + ShakeLogic.COOLDOWN_MS, "Cooldown armiert")
	assert_true((room.bubbles as Array).size() >= 2, "Bubbles gefeuert (Stufe 1+2)")
	# Im Cooldown: wildes Schütteln bleibt still (zeitinjiziert über now_ms).
	_drive(secret, 14.0, 4.0, now + 60_000)
	assert_eq(int(gs.get_value("achievements.counters.shakes", 0)), 1, "Cooldown blockt")
	# Nach 10 Minuten: nächste Episode zählt wieder.
	_drive(secret, 6.5, 1.2, now + ShakeLogic.COOLDOWN_MS)
	assert_eq(int(gs.get_value("achievements.counters.shakes", 0)), 2, "nach Cooldown wieder da")
	# Baumodus pausiert die Erkennung komplett.
	room.build_active = true
	var stage_im_bau := _drive(secret, 14.0, 2.0, now + ShakeLogic.COOLDOWN_MS + 120_000)
	assert_eq(stage_im_bau, 1, "Baumodus: Stufe friert ein (kein Feed)")
	room.queue_free()
	await wait_frames(1)
	gs.free()


func test_stufe2_gooby_haelt_sich_am_boden_fest() -> void:
	var gs := _fresh_game_state()
	var room := FakeRoom.new()
	room.gs = gs
	var gooby := FakeGooby.new()
	room.gooby_node = gooby
	room.add_child(gooby)
	tree.root.add_child(room)
	var secret := ShakeSecret.attach_to(room)
	secret.set_process(false)
	# Bis Stufe 2 (NICHT 3) treiben: Gooby duckt sich in die Bäuchlings-Pose.
	var stage := _drive(secret, 6.5, 1.2, NOW_MS)
	assert_eq(stage, 1, "erst Stufe 1")
	assert_true(gooby.rig.emotions.has("scared"), "Gooby erschrickt")
	stage = _drive(secret, 9.0, 1.3, NOW_MS)
	assert_eq(stage, 2, "dann Stufe 2")
	assert_false(gooby.wander, "Wandern aus — er hält sich fest")
	# W13C (Request CLIPS): die Bäuchlings-Pose kommt jetzt aus dem
	# grip_floor-Rig-Clip statt aus einem Kipp-Transform.
	assert_true(gooby.rig.clips.has("grip_floor"), "grip_floor-Clip läuft (Stufe 2)")
	assert_almost(gooby.rig.rotation.x, 0.0, 0.001, "kein Transform-Hack mehr am Rig")
	# Ruhe: Episode klingt ab, Pose und Wandern kommen zurück. Stufe-2-Energie
	# liegt bei bis zu ~15 → mit Decay 2.5/s dauert das Abklingen bis ~6.5 s.
	for _i in int(round(7.0 / DT)):
		secret.ingest(GRAVITY, DT, NOW_MS)
	assert_eq(gooby.rig.clips[gooby.rig.clips.size() - 1], "idle", "zurück in den move-State")
	assert_true(gooby.wander, "Wandern wieder an")
	assert_true(gooby.rig.emotions.has("happy"), "wieder happy")
	assert_eq(int(gs.get_value("achievements.counters.shakeStage3", 0)), 0, "keine Stufe 3")
	room.queue_free()
	await wait_frames(1)
	gs.free()


func _drive(secret: ShakeSecret, staerke: float, sekunden: float, now_ms: int) -> int:
	var stage := 0
	var samples := int(round(sekunden / DT))
	for i in samples:
		var richtung := 1.0 if i % 2 == 0 else -1.0
		var accel := GRAVITY + Vector3(staerke * richtung, 0.0, 0.0)
		stage = secret.ingest(accel, DT, now_ms)
	return stage
