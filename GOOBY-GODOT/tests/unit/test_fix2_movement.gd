extends TestCase
## FIX2 P0-Movement-Regression (User: „Gooby glitcht hin und her" / „kann sich
## keinen Meter bewegen"). Ursache war der NavigationAgent3D-3D-Distanzvergleich
## gegen Navmesh-Wegpunkte ~0.58 m über dem Boden: der Pfad-Index stallte bei 0
## und Gooby pendelte im 2-Frame-Ping-Pong. Diese Tests nageln das Soll fest:
## walk_to erreicht sein Ziel in N Physics-Frames, ohne Positionssprünge über
## SPEED/Tick und ohne Richtungs-Ping-Pong; Pfade führen UM Möbel herum.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## SPEED (1.15) / 60 Hz + Epsilon: mehr pro Frame wäre ein Teleport/Sprung.
const MAX_STEP_PRO_FRAME := 1.15 / 60.0 + 0.002

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://fix2_tests/move_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _make_living_room(gs: Node) -> RoomBase:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(3)
	# Navmesh-Bake abwarten (0.5 s Debounce) + 2 Physics-Frames Map-Sync.
	await wait_until(func() -> bool: return not room._rebake_pending, 4000)
	await tree.physics_frame
	await tree.physics_frame
	return room


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


## Läuft `gooby` bis zum Stopp und sammelt die XZ-Positionskurve.
## Liefert {"frames": int, "max_step": float, "flips": int, "track": Array}.
func _beobachte_lauf(gooby: GoobyHome, max_frames: int) -> Dictionary:
	var prev := gooby.global_position
	var prev_dir := Vector3.ZERO
	var max_step := 0.0
	var flips := 0
	var frames := 0
	var track: Array[Vector3] = [prev]
	for _i in max_frames:
		await tree.physics_frame
		frames += 1
		var pos := gooby.global_position
		var d := Vector3(pos.x - prev.x, 0.0, pos.z - prev.z)
		max_step = maxf(max_step, d.length())
		if d.length() > 0.0001:
			if prev_dir != Vector3.ZERO and d.dot(prev_dir) < 0.0:
				flips += 1
			prev_dir = d
		track.append(pos)
		prev = pos
		if not gooby._walking:
			break
	return {"frames": frames, "max_step": max_step, "flips": flips, "track": track}


func test_walk_to_erreicht_ziel_ohne_spruenge() -> void:
	var gs := _fresh_gs()
	var room: RoomBase = await _make_living_room(gs)
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	var ziel := Vector3(0.75, 0.0, 0.75)
	gooby.walk_to(ziel, 20.0)
	var lauf: Dictionary = await _beobachte_lauf(gooby, 600)
	var rest := GoobyHome._xz(ziel - gooby.global_position).length()
	assert_true(
		rest <= 0.35,
		"walk_to kommt am Ziel an (Rest %.3f m nach %d Frames)" % [rest, lauf["frames"]]
	)
	assert_true(int(lauf["frames"]) < 600, "Ziel in unter 600 Physics-Frames erreicht")
	assert_true(
		float(lauf["max_step"]) <= MAX_STEP_PRO_FRAME,
		"kein Positionssprung > SPEED/Tick (max %.4f)" % float(lauf["max_step"])
	)
	assert_true(
		int(lauf["flips"]) <= 2,
		"kein Richtungs-Ping-Pong (Flips=%d; vor dem Fix: >700)" % int(lauf["flips"])
	)
	await _cleanup(room, gs)


func test_idle_wandern_bewegt_sich_wirklich() -> void:
	var gs := _fresh_gs()
	var room: RoomBase = await _make_living_room(gs)
	var gooby := room.gooby()
	# Wander-Timer sofort feuern lassen statt 1–3 s zu warten.
	gooby._wander_timer = 0.0
	# Deterministischer Würfel: der Idle-Akt wird pro Feuerung gerollt (90 %
	# wandern, 10 % Clip an Ort und Stelle) — der Test darf im Voll-Runner
	# nicht am RNG hängen (W16: zweimal flaky mit netto 0.00). Fester Seed
	# = feste Roll-Folge = der Streifzug kommt sicher.
	gooby._rng.seed = 7
	var start := gooby.global_position
	var max_step := 0.0
	var prev := start
	var netto := 0.0
	for _i in 600:
		await tree.physics_frame
		var pos := gooby.global_position
		max_step = maxf(max_step, GoobyHome._xz(pos - prev).length())
		netto = maxf(netto, GoobyHome._xz(pos - start).length())
		prev = pos
	var freie: int = gooby.grid.free_cells().size() if gooby.grid != null else -1
	assert_true(
		netto >= 0.5,
		(
			(
				"Gooby bewegt sich beim Idle-Wandern wirklich vom Fleck (netto %.2f m; "
				+ "Diagnose: enabled=%s scripted=%s walking=%s freie_zellen=%d timer=%.2f)"
			)
			% [
				netto,
				gooby._wander_enabled,
				gooby._scripted,
				gooby._walking,
				freie,
				gooby._wander_timer,
			]
		)
	)
	assert_true(max_step <= MAX_STEP_PRO_FRAME, "kein Sprung > SPEED/Tick (max %.4f)" % max_step)
	# Nach dem Lauf steht er sauber (kein Dauerzittern am Ziel).
	var ruhe_start := gooby.global_position
	if not gooby._walking:
		for _i in 30:
			await tree.physics_frame
			if gooby._walking:
				break
		if not gooby._walking:
			var drift := GoobyHome._xz(gooby.global_position - ruhe_start).length()
			assert_true(drift <= 0.001, "kein Zittern im Stand (Drift %.4f m)" % drift)
	await _cleanup(room, gs)


## PT1-B7 (G8-Playtest): snap_to_walkable stellt Gooby von einer Möbel-Zelle
## auf die nächste begehbare Bodenzelle (Mumie-Event fror ihn sonst AUF dem
## Küchentisch ein) — und ist auf begehbarem Boden ein No-Op (kein Hop).
func test_snap_to_walkable_holt_gooby_vom_moebel() -> void:
	var gs := _fresh_gs()
	var room: RoomBase = await _make_living_room(gs)
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	# Couchtisch-Zelle (5,5): Welt x 2.5..3.0, z 2.5..3.0 — unbegehbar.
	gooby.global_position = Vector3(2.75, 0.0, 2.75)
	assert_false(
		gooby.grid.walkable(GridData.cell_of(gooby.global_position)),
		"Startzelle liegt wirklich auf dem Couchtisch"
	)
	gooby.snap_to_walkable()
	var zelle := GridData.cell_of(gooby.global_position)
	assert_true(gooby.grid.walkable(zelle), "nach dem Snap steht Gooby auf begehbarer Zelle")
	assert_almost(gooby.global_position.y, 0.0, 0.001, "…und auf dem Boden (y=0)")
	assert_true(
		GoobyHome._xz(gooby.global_position - Vector3(2.75, 0.0, 2.75)).length() <= 2.0,
		"Snap bleibt in der Nachbarschaft (Ring-Suche, kein Teleport quer durch den Raum)"
	)
	# Schon begehbar → No-Op, kein sichtbarer Versatz.
	var vorher := gooby.global_position
	gooby.snap_to_walkable()
	assert_almost(
		(gooby.global_position - vorher).length(), 0.0, 0.0001, "No-Op auf begehbarer Zelle"
	)
	await _cleanup(room, gs)


func test_pfad_fuehrt_um_moebel_herum() -> void:
	var gs := _fresh_gs()
	var room: RoomBase = await _make_living_room(gs)
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	# Wohnzimmer-Default: tableCoffee auf Zellen x5–6, y5 (Welt x 2.5..3.5,
	# z 2.5..3.0). Start SO, Ziel NW — die Luftlinie schneidet den Couchtisch.
	gooby.global_position = Vector3(5.25, 0.0, 4.5)
	await tree.physics_frame
	var ziel := Vector3(0.75, 0.0, 0.75)
	gooby.walk_to(ziel, 20.0)
	var lauf: Dictionary = await _beobachte_lauf(gooby, 900)
	var rest := GoobyHome._xz(ziel - gooby.global_position).length()
	assert_true(rest <= 0.35, "Ziel hinter dem Couchtisch erreicht (Rest %.3f m)" % rest)
	var tisch_min := Vector2(2.5 + 0.1, 2.5 + 0.1)
	var tisch_max := Vector2(3.5 - 0.1, 3.0 - 0.1)
	var drin := 0
	for pos: Vector3 in lauf["track"]:
		if (
			pos.x >= tisch_min.x
			and pos.x <= tisch_max.x
			and pos.z >= tisch_min.y
			and pos.z <= tisch_max.y
		):
			drin += 1
	assert_eq(drin, 0, "Positionskurve läuft nie DURCH den Couchtisch (%d Frames drin)" % drin)
	assert_true(
		float(lauf["max_step"]) <= MAX_STEP_PRO_FRAME,
		"kein Sprung > SPEED/Tick (max %.4f)" % float(lauf["max_step"])
	)
	await _cleanup(room, gs)
