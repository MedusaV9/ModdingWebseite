extends TestCase
## W19-Playtest ABEND-PROMPT — die „Kuschelabend?“-Chips (Gesprächs-Anlass
## gruss_abend) erschienen als graue Karte HINTER der offenen Heimkehr-
## Übergabe: GoobyGespraech öffnete direkt am Raum-Layer (5) und umging
## den Overlay-Dirigenten (W18/J1: immer nur EIN Willkommens-Overlay).
## Wächter (Muster test_w19_mitbringsel::test_overlay_dirigent_einreihung):
## bei offenem fremden Overlay erscheint der Prompt NICHT sofort, sondern
## reiht sich mit Prio PRIO_GESPRAECH (40, sanfter Hinweis NACH Heimkehr 5/
## Tagesbonus 10/Coachmark 20/Geburtstag 30) ein und kommt erst DANACH.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000

var _seq := 0


class RoomStub:
	extends Node3D
	## Minimaler RoomBase-Ersatz (Muster test_w14_voice.RoomStub): GameState,
	## Sprech-Protokoll und eine echte ui_layer für die Antwort-Chips.

	var grid: Variant = null
	var gs_ref: Object = null
	var lines: Array = []
	var layer := CanvasLayer.new()

	func _init() -> void:
		add_child(layer)

	func game_state() -> Object:
		return gs_ref

	func gooby() -> Node3D:
		return null

	func say(text: String) -> void:
		lines.append(text)

	func is_build_mode_active() -> bool:
		return false

	func ui_layer() -> CanvasLayer:
		return layer


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w19_abend/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_abend_prompt_wartet_hinter_offenem_overlay() -> void:
	var gs := _fresh_gs()
	var room := RoomStub.new()
	room.gs_ref = gs
	tree.root.add_child(room)
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	runner.now_ms_override = NOW_MS
	runner.visuals_enabled = false
	room.add_child(runner)
	runner.setup(room)
	var seele: SeeleRunner = runner.get_node("SeeleRunner")
	var gespraech: GoobyGespraech = seele.get_node("GoobyGespraech")
	# Das Abend-Gespräch hat chance 0.5 — Seed deterministisch so wählen,
	# dass der erste Roll trifft (RNG wird injiziert, AGENTS.md-Regel).
	var probe := RandomNumberGenerator.new()
	for kandidat in range(1, 64):
		probe.seed = kandidat
		if probe.randf() < 0.5:
			runner.rng.seed = kandidat
			break
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
	assert_true(gespraech.starte("gruss_abend"), "Abend-Prompt reiht sich ein")
	assert_false(gespraech.aktiv(), "Chips erscheinen NICHT sofort unter dem Overlay")
	dirigent.tick(1.0)
	assert_false(gespraech.aktiv(), "auch nach Takt: warten, solange das Overlay steht")
	assert_eq(dirigent.aktiv_id(), "heimkehr", "Overlay bleibt allein sichtbar")
	# Overlay schließt → der Abend-Prompt kommt DANACH dran (Prio 40).
	fremd.queue_free()
	await wait_frames(2)
	dirigent.tick(1.0)
	assert_true(gespraech.aktiv(), "Chips kommen NACH dem Overlay")
	assert_eq(dirigent.aktiv_id(), "gespraech", "als reguläres Dirigent-Ticket")
	var panel: Control = room.layer.get_node_or_null("GoobyGespraechChips")
	assert_ne(panel, null, "Abend-Chips stehen jetzt am Raum-Layer")
	gespraech._chips_weg()
	dirigent.queue_free()
	room.queue_free()
	gs.queue_free()
	await wait_frames(1)


func test_prio_ist_sanfter_hinweis_nach_allen_willkommens_overlays() -> void:
	# Die Prio-Tabelle des Dirigenten: kleiner = früher. Der Abend-Prompt
	# ist der sanfteste Hinweis und darf NIE vor Heimkehr/Tagesbonus/
	# Coachmark/Geburtstag drankommen.
	assert_true(GoobyGespraech.PRIO_GESPRAECH > OverlayDirigent.PRIO_GEBURTSTAG)
	assert_true(GoobyGespraech.PRIO_GESPRAECH > OverlayDirigent.PRIO_COACHMARK)
	assert_true(GoobyGespraech.PRIO_GESPRAECH > OverlayDirigent.PRIO_TAGESBONUS)
	assert_true(GoobyGespraech.PRIO_GESPRAECH > HeimkehrMoment.PRIO_HEIMKEHR)
