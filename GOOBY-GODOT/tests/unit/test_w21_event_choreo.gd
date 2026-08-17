extends TestCase
## W21 Blocker #2 — EVENT-KAPERUNGS-WACHE (Playtest flow_streicheln +
## Befund home_hud_befunde.md §Event-Kaperung): das Schlafenszeit-/
## Nutella-Event feuerte unangekündigt mitten ins Spielen, parkte seine
## Wahlkarte OHNE Timeout in der Welt-Tap-Zone und Gooby steckte hinterm
## Sofa — 10 Streichel-Taps verpufft. Wachen (Fix = EventChoreo):
## (a) EINREIHUNG: die Wahlkarte erscheint NIE, solange ein anderes
##     Overlay offen ist — sie reiht sich beim OverlayDirigenten ein
##     (Prio 35: nach Heimkehr 5/Tagesbonus 10/Coachmark 20/Geburtstag 30,
##     vor Gespräch 40; Muster test_w19_abend_prompt).
## (b) WELT BLEIBT SPIELBAR: kein full-rect STOP im Event-UI-Layer
##     (W18-Muster „unsichtbare Riesen-STOP-Flächen“), und die echte
##     Streichel-Tap-Kette (Muster test_w21_streichel_tap) bucht auch
##     bei OFFENER Karte; Idle-Leben pausiert derweil (_busy-Gate).
## (c) VERTAGEN (injizierte Uhr): ohne Antwort gleitet die Karte nach
##     VERTAGEN_S als Rand-Chip weg, das Event bleibt bit-identisch aktiv
##     (Engine-Timeout unangetastet); Chip-Tap holt die Karte zurück und
##     die Belohnungslogik liefert dieselben Deltas wie immer.
## (d) SICHTBARKEIT: verdeckt ein Möbel-Area die Kamerasicht auf Gooby,
##     rückt die Inszenierung ihn auf die nächste freie, sichtbare Zelle.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const WOHNZIMMER_SCENE := preload("res://scenes/home/wohnzimmer.tscn")

const NOW_MS := 1785448800000  # 2026-07-30 UTC
const EVENTS_JSON := "res://content/events/data/events.json"
const LEITFORMAT_QUER := Vector2i(2868, 1320)
## Tap-Ziel wie flow_streicheln/GoobyReactions: Gooby-Ursprung + 0,35 m.
const TAP_OFFSET := Vector3(0.0, 0.35, 0.0)

var _seq := 0


class FakeRig:
	extends Node3D

	func set_emotion(_id: String) -> void:
		pass


class FakeGooby:
	extends Node3D
	## Minimal-Gooby mit der GoobyHome-API, die der EventRunner nutzt.

	var rig: FakeRig = FakeRig.new()
	var wander := true

	func _init() -> void:
		add_child(rig)

	func set_wander_enabled(enabled: bool) -> void:
		wander = enabled

	func play_clip(_clip: String) -> void:
		pass

	func walk_to(_world_pos: Vector3, _timeout_s := 6.0) -> void:
		pass


class FakeRoom:
	extends Node3D
	## Minimal-Raum (Muster test_events_runner.FakeRoom).

	var gs: Object = null
	var gooby_node: FakeGooby = FakeGooby.new()
	var room_id := "living"

	func _init() -> void:
		add_child(gooby_node)

	func game_state() -> Object:
		return gs

	func gooby() -> Node:
		return gooby_node

	func say(_text: String) -> void:
		pass


func _fresh_gs() -> Node:
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	_seq += 1
	var dir := "user://w21_event_choreo/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _defs() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_JSON))
	return parsed.get("items", []) if parsed is Dictionary else []


## Fake-Raum + Runner mit aktiviertem Event (Muster test_events_runner).
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


func _karte_im_layer(runner: EventRunner) -> Control:
	var layer := runner.get_node_or_null("W3dUiLayer")
	if layer == null:
		return null
	return layer.get_node_or_null("EventChoice")


func _chip_im_layer(runner: EventRunner) -> Control:
	var layer := runner.get_node_or_null("W3dUiLayer")
	if layer == null:
		return null
	return layer.get_node_or_null("EventChoiceChip")


# ── (a) Dirigent-Einreihung ──────────────────────────────────────────────────


func test_prio_liegt_zwischen_geburtstag_und_gespraech() -> void:
	# Begründung der 35: Events sind wartende Szenen mit echtem Engine-
	# Timeout — nach ALLEN Ankunfts-Overlays, aber vor dem sanftesten
	# Hinweis (Abend-Gespräch 40).
	assert_true(EventChoreo.PRIO_EVENT_CHOICE > HeimkehrMoment.PRIO_HEIMKEHR)
	assert_true(EventChoreo.PRIO_EVENT_CHOICE > OverlayDirigent.PRIO_TAGESBONUS)
	assert_true(EventChoreo.PRIO_EVENT_CHOICE > OverlayDirigent.PRIO_COACHMARK)
	assert_true(EventChoreo.PRIO_EVENT_CHOICE > OverlayDirigent.PRIO_GEBURTSTAG)
	assert_true(EventChoreo.PRIO_EVENT_CHOICE < GoobyGespraech.PRIO_GESPRAECH)


func test_karte_wartet_hinter_offenem_overlay() -> void:
	var dirigent := OverlayDirigent.new()
	dirigent.pause_s = 0.0
	tree.root.add_child(dirigent)
	dirigent.set_process(false)
	# Fremdes Overlay ist offen (Heimkehr-Attrappe, Prio 5 wie im Original).
	var fremd := Control.new()
	tree.root.add_child(fremd)
	dirigent.anfordern("heimkehr", 5, func() -> Control: return fremd)
	dirigent.tick(1.0)
	assert_eq(dirigent.aktiv_id(), "heimkehr", "fremdes Overlay ist dran")
	var ctx := _stage("nutella_nacht")
	var runner: EventRunner = ctx["runner"]
	assert_true(runner.is_running(), "Szene ist aufgebaut (Props/Pose)")
	assert_eq(_karte_im_layer(runner), null, "Karte erscheint NICHT unter dem Overlay")
	dirigent.tick(1.0)
	assert_eq(_karte_im_layer(runner), null, "auch nach Takt: warten, solange Overlay steht")
	assert_eq(dirigent.aktiv_id(), "heimkehr", "Overlay bleibt allein sichtbar")
	# Overlay schließt → die Event-Karte kommt DANACH als reguläres Ticket.
	fremd.queue_free()
	await wait_frames(2)
	dirigent.tick(1.0)
	await wait_frames(2)
	assert_ne(_karte_im_layer(runner), null, "Karte kommt NACH dem Overlay")
	assert_eq(dirigent.aktiv_id(), EventChoreo.DIRIGENT_ID, "als Dirigent-Ticket")
	# Reiseantritt räumt ab UND zieht ein etwaiges Ticket zurück.
	runner.abort_staging()
	await wait_frames(2)
	assert_eq(_karte_im_layer(runner), null, "Abbruch räumt die Karte ab")
	assert_false(dirigent.belegt(), "kein Geister-Ticket nach dem Abbruch")
	dirigent.queue_free()
	await _teardown(ctx)


func test_chip_tap_respektiert_offenes_overlay() -> void:
	var dirigent := OverlayDirigent.new()
	dirigent.pause_s = 0.0
	tree.root.add_child(dirigent)
	dirigent.set_process(false)
	var ctx := _stage("nutella_nacht")
	var runner: EventRunner = ctx["runner"]
	dirigent.tick(1.0)
	await wait_frames(2)
	assert_ne(_karte_im_layer(runner), null, "freie Bühne → Karte offen")
	# Karte vertagt sich (injizierte Uhr) → Dirigent-Slot wird frei.
	var choreo: EventChoreo = runner.get_node("EventChoreo")
	choreo.set_process(false)
	choreo.tick(EventChoreo.VERTAGEN_S + 0.1)
	await wait_frames(2)
	assert_eq(_karte_im_layer(runner), null, "vertagt: Karte weg")
	assert_ne(_chip_im_layer(runner), null, "vertagt: Rand-Chip steht")
	dirigent.tick(1.0)
	assert_false(dirigent.belegt(), "Vertagen gibt den Dirigenten frei")
	# Jetzt ist ein ANDERES Overlay dran — der Chip-Tap drängelt nicht.
	var fremd := Control.new()
	tree.root.add_child(fremd)
	dirigent.anfordern("tagesbonus", 10, func() -> Control: return fremd)
	dirigent.tick(1.0)
	assert_eq(dirigent.aktiv_id(), "tagesbonus", "fremdes Overlay ist dran")
	var chip := _chip_im_layer(runner)
	var knopf: BaseButton = chip.get_child(0)
	knopf.pressed.emit()
	await wait_frames(2)
	dirigent.tick(1.0)
	assert_eq(_karte_im_layer(runner), null, "Chip-Tap wartet hinter dem Overlay")
	fremd.queue_free()
	await wait_frames(2)
	dirigent.tick(1.0)
	await wait_frames(2)
	assert_ne(_karte_im_layer(runner), null, "danach kommt die Karte zurück")
	dirigent.queue_free()
	await _teardown(ctx)


# ── (c) Vertagen + Belohnung bit-unverändert ─────────────────────────────────


func test_timeout_vertagt_als_chip_und_belohnung_bleibt_gleich() -> void:
	var ctx := _stage("nutella_nacht")
	var runner: EventRunner = ctx["runner"]
	var gs: Object = ctx["gs"]
	gs.update(
		func(s: Dictionary) -> void:
			s["gooby"]["stats"]["fun"] = 50.0
			s["gooby"]["stats"]["energy"] = 50.0
	)
	# Ohne Dirigent (nackter Test) öffnet die Karte direkt — wie bisher.
	assert_ne(_karte_im_layer(runner), null, "Karte steht (Vorbedingung)")
	var timeout_vorher := int(RandomEventEngine.active_of(gs).get("timeout_ms", 0))
	var choreo: EventChoreo = runner.get_node("EventChoreo")
	choreo.set_process(false)
	# Injizierte Uhr: knapp VOR der Schwelle passiert nichts …
	choreo.tick(EventChoreo.VERTAGEN_S - 0.5)
	assert_ne(_karte_im_layer(runner), null, "vor der Schwelle bleibt die Karte")
	# … über der Schwelle gleitet sie als Rand-Chip weg.
	choreo.tick(1.0)
	await wait_frames(2)
	assert_eq(_karte_im_layer(runner), null, "Timeout: Karte weg")
	var chip := _chip_im_layer(runner)
	assert_ne(chip, null, "Timeout: Rand-Chip steht")
	var knopf: BaseButton = chip.get_child(0)
	assert_true(knopf.text.contains("wartet"), "Chip trägt das Wartet-Muster")
	# Nur Präsentation: Event bleibt AKTIV, Engine-Timeout unangetastet.
	assert_true(runner.is_running(), "Szene läuft weiter")
	var active := RandomEventEngine.active_of(gs)
	assert_false(active.is_empty(), "Event bleibt aktiv (kein resolve/fail)")
	assert_eq(int(active.get("timeout_ms", 0)), timeout_vorher, "Engine-Timeout unverändert")
	# Chip-Tap holt die Karte zurück.
	knopf.pressed.emit()
	await wait_frames(2)
	assert_ne(_karte_im_layer(runner), null, "Chip-Tap: Karte wieder da")
	assert_eq(_chip_im_layer(runner), null, "Chip hat sich abgeräumt")
	# Belohnungslogik bit-unverändert (Werte wie test_events_runner):
	# „Ab ins Bett“ = −5 Freude, +10 Energie, Event aufgelöst.
	await runner._on_nutella_choice({"to_bed": true})
	assert_almost(float(gs.get_value("gooby.stats.fun", 0.0)), 45.0, 1e-6, "−5 Freude")
	assert_almost(float(gs.get_value("gooby.stats.energy", 0.0)), 60.0, 1e-6, "+10 Energie")
	assert_true(RandomEventEngine.active_of(gs).is_empty(), "Event aufgelöst")
	assert_eq(int(gs.get_value("events.resolvedTotal", 0)), 1, "resolvedTotal zählt")
	await _teardown(ctx)


func test_chip_rect_ankert_am_lane_rand() -> void:
	var lane := {"top": 640.0, "width": 500.0}
	var rect := EventProps.chip_rect(Vector2(1280, 720), 8.0, lane, Vector2(180, 56), [])
	assert_almost(rect.end.x, 1280.0 / 2.0 + 250.0, 1e-3, "rechtsbündig an der Lane-Kante")
	assert_almost(rect.end.y, 640.0 - EventProps.CHOICE_GAP, 1e-3, "Unterkante wie die Karte")
	# Belegtes Bottom-Rect (Gooby-Bubble) wird überstiegen, nie überlappt.
	var bubble := Rect2(Vector2(660, 560), Vector2(360, 80))
	var dodged := EventProps.chip_rect(Vector2(1280, 720), 8.0, lane, Vector2(180, 56), [bubble])
	assert_true(
		dodged.end.y <= bubble.position.y - EventProps.CHOICE_GAP + 0.001,
		"Chip rutscht ÜBER die Bubble"
	)


# ── (b) Welt bleibt spielbar (echtes Wohnzimmer) ─────────────────────────────


## Tap-Synthese wie playtest_harness/test_w21_streichel_tap.
func _tippe_canvas(canvas_pos: Vector2) -> void:
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var px := canvas_pos * (Vector2(tree.root.size) / canvas)
	for gedrueckt: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = gedrueckt
		ev.position = px
		ev.global_position = px
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if gedrueckt else 0
		Input.parse_input_event(ev)
		await wait_frames(2)


func _echter_gs() -> Node:
	var gs := _fresh_gs()
	tree.root.add_child(gs)
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})
	return gs


func test_welt_tap_bucht_streicheln_trotz_offener_karte() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	tree.root.size = LEITFORMAT_QUER
	tree.root.size_changed.emit()
	await wait_frames(2)
	var gs := _echter_gs()
	var room: RoomBase = WOHNZIMMER_SCENE.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(6)
	var reactions := GoobyReactions.attach_to(room)
	await wait_frames(4)
	var gooby := room.gooby() as Node3D
	var kamera := tree.root.get_camera_3d()
	assert_ne(gooby, null, "Gooby steht im Raum")
	assert_ne(kamera, null, "aktive 3D-Kamera")
	# Nutella-Event staged mitten im Spielen (kein Dirigent → Karte sofort).
	var defs := _defs()
	var def := RandomEventEngine.def_by_id(defs, "nutella_nacht")
	RandomEventEngine.activate(gs, def, NOW_MS)
	var runner := EventRunner.attach_to(room, defs)
	runner.start(def)
	await wait_frames(4)
	var karte := _karte_im_layer(runner)
	assert_ne(karte, null, "Karte steht (Vorbedingung)")
	# Idle-Leben pausiert während der Inszenierung (_busy-Gate) — sonst
	# trägt ein Idle-walk_to Gooby mitten im Event hinters Sofa.
	assert_true(reactions._busy(), "Idle-Leben pausiert während des Events")
	# (b) W18-Muster-Rückfall-Wache: KEIN Control im Event-UI-Layer stoppt
	# full-rect — die Karte blockt nur sich selbst.
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var layer: CanvasLayer = runner.get_node("W3dUiLayer")
	for kind: Node in layer.get_children():
		_pruefe_kein_riesen_stop(kind as Control, canvas)
	# Streichel-Tap-Kette (Muster test_w21_streichel_tap) NEBEN der Karte.
	var welt: Vector3 = gooby.global_position + TAP_OFFSET
	var canvas_pos := kamera.unproject_position(welt)
	assert_false(
		karte.get_global_rect().has_point(canvas_pos),
		"Vorbedingung: Gooby-Projektion liegt NEBEN der Karte"
	)
	var vorher := int(gs.get_value("achievements.counters.petsToday", 0))
	await _tippe_canvas(canvas_pos)
	await wait_frames(6)
	var nachher := int(gs.get_value("achievements.counters.petsToday", 0))
	assert_true(
		nachher >= vorher + 1,
		"Welt-Tap bucht petsToday trotz offener Karte (%d -> %d)" % [vorher, nachher]
	)
	runner.abort_staging()
	assert_false(reactions._busy(), "nach dem Abbruch lebt das Idle-Leben wieder")
	room.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


func _pruefe_kein_riesen_stop(control: Control, canvas: Vector2) -> void:
	if control == null:
		return
	if control.mouse_filter == Control.MOUSE_FILTER_STOP:
		var rect := control.get_global_rect()
		var anteil := (rect.size.x * rect.size.y) / maxf(canvas.x * canvas.y, 1.0)
		assert_true(
			anteil < 0.5,
			"%s stoppt %d%% des Canvas — Riesen-STOP-Fläche" % [control.name, anteil * 100.0]
		)
	for kind: Node in control.get_children():
		if kind is Control:
			_pruefe_kein_riesen_stop(kind as Control, canvas)


# ── (d) Gooby bleibt sichtbar ────────────────────────────────────────────────


func test_verdeckter_gooby_rueckt_auf_sichtbare_zelle() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	tree.root.size = LEITFORMAT_QUER
	tree.root.size_changed.emit()
	await wait_frames(2)
	var gs := _echter_gs()
	var room: RoomBase = WOHNZIMMER_SCENE.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(6)
	var gooby := room.gooby() as Node3D
	var kamera := tree.root.get_camera_3d()
	assert_ne(gooby, null, "Gooby steht im Raum")
	assert_ne(kamera, null, "aktive 3D-Kamera")
	var defs := _defs()
	var runner := EventRunner.attach_to(room, defs)
	var choreo := EventChoreo.attach_to(runner)
	# Sofa-Attrappe: Area3D-Block GENAU zwischen Kamera und Gooby (wie die
	# Möbel-TapArea des Playtests, die nur Ohren übrig ließ).
	var sofa := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.4)
	shape.shape = box
	sofa.add_child(shape)
	room.add_child(sofa)
	var ziel: Vector3 = gooby.global_position + TAP_OFFSET
	sofa.global_position = kamera.global_position.lerp(ziel, 0.85)
	sofa.look_at(kamera.global_position)
	await wait_frames(3)
	assert_true(
		choreo._verdeckt(kamera, gooby, gooby.global_position),
		"Vorbedingung: Sofa-Attrappe verdeckt die Kamerasicht"
	)
	var vorher: Vector3 = gooby.global_position
	choreo.ruecke_gooby_ins_bild()
	assert_ne(gooby.global_position, vorher, "Gooby rückt weg vom verdeckten Fleck")
	assert_false(
		choreo._verdeckt(kamera, gooby, gooby.global_position),
		"Gooby steht jetzt sichtbar (freie Zelle)"
	)
	sofa.queue_free()
	room.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)
