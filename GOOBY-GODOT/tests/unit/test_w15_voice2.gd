extends TestCase
## W15/VOICE2 — IGohbie-Selfie-Clips + Kommentar-Anbindungen + Übermut-Gag:
##  - phone_up/phone_tap liegen im GLB (Loop-Flags), Rig-Konstanten stimmen,
##    das Rig hält die Selfie-Pose als StateMachine-Zustand
##  - BoardEmotes „selfie" posiert mit phone_up (W13C-Request eingelöst),
##    FotoWerkzeuge.selfie_clip greift mit der ECHTEN Rig-Clipliste
##  - SeeleRunner.kommentar_global: None-sicher ohne Runner, spricht über
##    den zuletzt aktiven Runner
##  - jede neue Kommentar-Anbindung feuert über die ÖFFENTLICHE Feature-API:
##    Girlande spannen, Galaxie-Fell anlegen, Raumstation betreten,
##    Ranch-Event lösen, Minispiel-Rekord, Sticker-/Erfolgs-Feier
##  - Streichel-Übermut: >10 Streichler in 30 s → EINMAL refuse + Pausen-
##    Zeile, Cooldown hält den Gag danach still (pure Statemaschine).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const GLB_PATH := "res://assets/character/gooby.glb"
const RAUM_SZENE := "res://scenes/city/orte/raumstation.tscn"
const NOW_MS := 1768478400000
## 91 s nach dem Betreten-Moment ist die Seelen-Bremse wieder frei
## (Muster test_w14_voice).
const BREMSE_FREI_MS := 91_000

var _seq := 0


class RoomStub:
	extends Node3D
	## RoomBase-Ersatz (Muster test_w14_voice) + Duck-Typing-Zusätze für
	## GirlandenBau (grid_mount/room_id/stunde_override) und einen
	## optionalen Gooby-Träger (Übermut-Gag mit echtem Rig).

	var grid: Variant = null
	var gs_ref: Object = null
	var lines: Array = []
	var layer := CanvasLayer.new()
	var room_id := "living"
	var stunde_override := 12.0
	var mount := Node3D.new()
	var gooby_traeger: Node3D = null

	func _init() -> void:
		add_child(layer)
		add_child(mount)

	func game_state() -> Object:
		return gs_ref

	func gooby() -> Node3D:
		return gooby_traeger

	func say(text: String) -> void:
		lines.append(text)

	func is_build_mode_active() -> bool:
		return false

	func ui_layer() -> CanvasLayer:
		return layer

	func grid_mount() -> Node3D:
		return mount


class GoobyTraegerStub:
	extends Node3D
	## Minimaler GoobyHome-Ersatz: trägt ein ECHTES GoobyRig (Duck-Typing-
	## Vertrag von GoobyReactions/_uebermut_gag: `gooby.get("rig")`).

	var rig: GoobyRig = null


class RanchStub:
	extends Node3D
	## Ranch-Szenen-Attrappe (Muster test_w13_ranch_events).

	var gs: Object = null

	func game_state() -> Object:
		return gs

	func zeige_meldung(_text: String) -> void:
		pass

	func event_anker() -> Vector3:
		return Vector3.ZERO


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w15_voice2/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


## Home-Fixture: RoomStub + echter GoobyReactions-Runner (registriert die
## Seele auch als kommentar_global-Ziel). Bremse danach direkt frei.
func _runner_fixture(gs: Node, traeger: Node3D = null) -> Array:
	var room := RoomStub.new()
	room.gs_ref = gs
	room.gooby_traeger = traeger
	if traeger != null:
		room.add_child(traeger)
	tree.root.add_child(room)
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	runner.now_ms_override = NOW_MS
	runner.visuals_enabled = false
	room.add_child(runner)
	runner.setup(room)
	runner.now_ms_override = NOW_MS + BREMSE_FREI_MS
	return [room, runner]


func _gebuchte(gs: Node, kategorie: String) -> Array:
	return SoulState.slice_of(gs)["linien"].get(kategorie, [])


func _abbau(room: Node, gs: Node) -> void:
	room.queue_free()
	gs.queue_free()
	await wait_frames(1)


# ── (a) Clips: GLB, Rig-Konstanten, selfie-Mapping ───────────────────────────


func test_glb_hat_selfie_clips_mit_flags() -> void:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	assert_true(player != null, "kein AnimationPlayer im GLB")
	if player != null:
		var have := player.get_animation_list()
		assert_true("phone_up" in have, "phone_up fehlt im GLB")
		assert_true("phone_tap" in have, "phone_tap fehlt im GLB")
		if "phone_up" in have:
			assert_true(
				player.get_animation("phone_up").loop_mode != Animation.LOOP_NONE,
				"phone_up ist die Halte-Loop"
			)
		if "phone_tap" in have:
			assert_true(
				player.get_animation("phone_tap").loop_mode == Animation.LOOP_NONE,
				"phone_tap ist ein One-Shot"
			)
	model.free()


func test_rig_konstanten_und_loop_states() -> void:
	assert_eq(GoobyRig.CLIP_PHONE_UP, "phone_up")
	assert_eq(GoobyRig.CLIP_PHONE_TAP, "phone_tap")
	assert_eq(GoobyRig.W15_LOOP_CLIPS, ["phone_up"] as Array[String])
	assert_eq(GoobyRig.W15_ONESHOT_CLIPS, ["phone_tap"] as Array[String])
	assert_true(GoobyRig.LOOP_STATES.has("phone_up"), "Haltepose lebt als StateMachine-Zustand")
	assert_false(GoobyRig.LOOP_STATES.has("phone_tap"), "phone_tap läuft über den OneShot-Layer")


func test_rig_haelt_selfie_pose_und_snap_a_gooby_greift() -> void:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	var clips := rig.clip_names()
	assert_true(clips.has("phone_up"), "Rig kennt phone_up")
	assert_true(clips.has("phone_tap"), "Rig kennt phone_tap")
	# SnapAGooby posiert das EIGENE Rig über FotoWerkzeuge.selfie_clip —
	# mit der echten Clipliste gewinnt jetzt der echte Clip (kein wave mehr).
	assert_eq(FotoWerkzeuge.selfie_clip(clips), "phone_up", "Selfie nutzt den echten Clip")
	rig.play_clip("phone_up")
	var haelt := await wait_until(func() -> bool: return rig.current_state() == "phone_up", 2000)
	assert_true(haelt, "travel zu phone_up schlug fehl (state=%s)" % rig.current_state())
	rig.free()


func test_board_emote_selfie_auf_phone_up() -> void:
	# Der 1-Zeilen-Request aus W13C: EXTRA_EMOTES „selfie" → phone_up. Der
	# Peer-Pfad (SnapAGooby.RELAY_EMOTE → RemoteGooby.play_emote) zieht mit.
	assert_eq(SnapAGooby.RELAY_EMOTE, "selfie", "Relay-Vokabular unverändert")
	assert_true(BoardEmotes.is_valid("selfie"), "selfie bleibt Relay-gültig")
	assert_eq(BoardEmotes.clip_for("selfie"), "phone_up", "selfie posiert mit phone_up")
	assert_eq(BoardEmotes.emotion_for("selfie"), "happy")
	assert_false(BoardEmotes.ids().has("selfie"), "selfie bleibt aus dem 4er-Rad")


# ── (b) kommentar_global: None-sicher + aktiver Runner ───────────────────────


func test_kommentar_global_none_sicher_und_spricht() -> void:
	# OHNE lebenden Runner (nackte Testumgebung): still, kein Crash.
	assert_eq(SeeleRunner.kommentar_global("w13.raumstation"), "", "ohne Runner still")
	var gs := _fresh_gs()
	var fixture := _runner_fixture(gs)
	var room: RoomStub = fixture[0]
	var key := SeeleRunner.kommentar_global("w13.raumstation")
	assert_true(key.begins_with("soul.linie.w13.raumstation."), "aktiver Runner spricht (%s)" % key)
	assert_eq(_gebuchte(gs, "w13.raumstation").size(), 1, "Anti-Wiederholung gebucht")
	await _abbau(room, gs)
	# Nach dem Abbau ist die Registrierung wieder leer (kein toter Zeiger).
	assert_eq(SeeleRunner.kommentar_global("w13.raumstation"), "", "nach Abbau wieder still")


# ── (c) Kommentar-Anbindungen über die öffentlichen Feature-APIs ─────────────


func test_girlande_spannen_feuert_kommentar() -> void:
	HomeState.register_slice()
	var gs := _fresh_gs()
	var fixture := _runner_fixture(gs)
	var room: RoomStub = fixture[0]
	gs.update(
		func(state: Dictionary) -> void:
			StorageLogic.add(state["home"]["storage"], "girlande_wimpel")
	)
	var flow := GirlandenBau.new()
	room.add_child(flow)
	flow.setup(room, GridData.new(Vector2i(6, 6)), gs)
	flow.starte("girlande_wimpel")
	assert_eq(flow.tippe_zelle(Vector2i(1, 1)), "punkt_a", "erster Tap setzt Punkt A")
	assert_eq(_gebuchte(gs, "w13.girlande").size(), 0, "Punkt A allein spricht nicht")
	assert_eq(flow.tippe_zelle(Vector2i(4, 1)), "gespannt", "zweiter Tap spannt")
	assert_eq(_gebuchte(gs, "w13.girlande").size(), 1, "gespannt → Girlanden-Kommentar")
	await _abbau(room, gs)
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_galaxie_fell_feuert_kommentar() -> void:
	var gs := _fresh_gs()
	var fixture := _runner_fixture(gs)
	var room: RoomStub = fixture[0]
	var runner: GoobyReactions = fixture[1]
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	var attach := CosmeticAttach.fuer_rig(rig)
	assert_true(attach != null, "CosmeticAttach findet das Rig")
	attach.reduced_motion_override = 1
	attach.apply_fell("fell_galaxie")
	assert_eq(_gebuchte(gs, "w13.galaxie").size(), 1, "Galaxie-Equip → Kommentar")
	# Normales Fell (oder Ablegen) spricht NICHT über die Galaxie-Kategorie.
	runner.now_ms_override += BREMSE_FREI_MS
	attach.apply_fell("")
	assert_eq(_gebuchte(gs, "w13.galaxie").size(), 1, "Standard-Fell bleibt still")
	rig.free()
	await _abbau(room, gs)


func test_raumstation_betreten_feuert_kommentar() -> void:
	var gs := _fresh_gs()
	var fixture := _runner_fixture(gs)
	var room: RoomStub = fixture[0]
	var szene: PackedScene = load(RAUM_SZENE)
	var ort: OrtRaumstation = szene.instantiate()
	ort.game_state_override = gs
	tree.root.add_child(ort)
	await wait_frames(3)
	assert_eq(_gebuchte(gs, "w13.raumstation").size(), 1, "Betreten → Weltraum-Kommentar")
	ort.queue_free()
	await _abbau(room, gs)


func test_ranch_event_geloest_feuert_kommentar() -> void:
	RanchState.register_slice()
	RandomEventEngine.register_slice()
	var gs := _fresh_gs()
	var fixture := _runner_fixture(gs)
	var room: RoomStub = fixture[0]
	gs.set_value("ranch.gekauft", true)
	var def := {
		"id": "w15_test",
		"context": "ranch",
		"weight": 1,
		"cooldown_days": 1,
		"trigger_window": ["00:00", "23:59"],
		"wahrscheinlichkeit": 1.0,
		"notification_text_de": "Testfall!",
		"timeout_min": 8,
		"fail_text_de": "-_-",
		"reward": null,
		"ranch_reward": {"items": {"heu": 2}},
		"szene_setup": "ranch_heudieb",
		"props": 3,
	}
	RandomEventEngine.activate(gs, def, NOW_MS)
	var szene := RanchStub.new()
	szene.gs = gs
	tree.root.add_child(szene)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var host := RanchEventHost.new()
	host.name = "RanchEventHost"
	host.game_state_override = gs
	host.now_ms_override = NOW_MS
	host.minuten_override = 720
	host.rng_override = rng
	szene.add_child(host)
	host.setup(szene, [def])
	assert_true(host.is_running(), "Heudieb-Szene steht")
	assert_eq(_gebuchte(gs, "w13.ranch").size(), 0, "vor der Lösung still")
	for tap in 3:
		host._on_kraehe_verscheucht()
	assert_false(host.is_running(), "3× tippen löst das Event")
	assert_eq(_gebuchte(gs, "w13.ranch").size(), 1, "Event gelöst → Ranch-Kommentar")
	szene.free()
	await _abbau(room, gs)
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	SaveSchema.unregister_slice(RandomEventEngine.SLICE_ID)
	RanchState.reset_for_tests()
	RandomEventEngine.reset_for_tests()


func test_minispiel_rekord_feuert_kommentar() -> void:
	var gs := _fresh_gs()
	var fixture := _runner_fixture(gs)
	var room: RoomStub = fixture[0]
	var runner: GoobyReactions = fixture[1]
	var results := MinigameResults.new()
	tree.root.add_child(results)
	await wait_frames(1)
	# Kein neuer Rekord → kein Rekord-Kommentar.
	results.show_results({"score": 3, "best": 9, "newBest": false}, {})
	assert_eq(_gebuchte(gs, "minispiel.rekord").size(), 0, "ohne Rekord still")
	runner.now_ms_override += BREMSE_FREI_MS
	results.show_results({"score": 12, "best": 12, "newBest": true}, {})
	assert_eq(_gebuchte(gs, "minispiel.rekord").size(), 1, "neuer Rekord → Kommentar")
	results.queue_free()
	await _abbau(room, gs)


func test_feiern_feuern_kommentare() -> void:
	var gs := _fresh_gs()
	var fixture := _runner_fixture(gs)
	var room: RoomStub = fixture[0]
	var runner: GoobyReactions = fixture[1]
	var hub := RewardHub.attach_to(room, gs)
	await wait_frames(1)
	hub._celebrate({"id": "w15_test_sticker", "rarity": "haeufig", "page": ""})
	assert_eq(_gebuchte(gs, "feier.sticker").size(), 1, "Sticker-Feier → Kommentar")
	runner.now_ms_override += BREMSE_FREI_MS
	# Reale lokalisierte ID nutzen; gefeiert wird weiterhin direkt und
	# unabhängig vom Achievement-Fortschritt.
	hub._celebrate_achievement({"id": "firstFeed", "coins": 5})
	assert_eq(_gebuchte(gs, "feier.erfolg").size(), 1, "Erfolgs-Feier → Kommentar")
	await _abbau(room, gs)


# ── (d) Bonus: Streichel-Übermut-Gag ─────────────────────────────────────────


func test_uebermut_statemaschine_pur() -> void:
	var sm := StreichelUebermut.new()
	var t0 := 1_000_000
	for i in 10:
		assert_false(sm.registriere(t0 + i * 1000), "die ersten 10 lösen nicht aus (%d)" % i)
	assert_true(sm.registriere(t0 + 10_000), "der 11. Streichler im Fenster löst aus")
	for i in 15:
		assert_false(
			sm.registriere(t0 + 11_000 + i * 1000), "Cooldown blockt auch neue Serien (%d)" % i
		)
	# Nach dem Cooldown wird erst wieder GESAMMELT (kein Sofort-Feuer).
	var t1 := t0 + 10_000 + StreichelUebermut.COOLDOWN_MS
	assert_false(sm.registriere(t1 + 1_000), "nach dem Cooldown sammelt die Maschine neu")
	# Gemütliches Streicheln (alle 31 s) löst NIE aus — Fenster leert sich.
	var gemuetlich := StreichelUebermut.new()
	for i in 30:
		assert_false(gemuetlich.registriere(t0 + i * 31_000), "31-s-Takt bleibt entspannt")


func test_uebermut_gag_spielt_refuse_und_pausen_zeile() -> void:
	var gs := _fresh_gs()
	var traeger := GoobyTraegerStub.new()
	var rig := GoobyRig.new()
	traeger.rig = rig
	traeger.add_child(rig)
	var fixture := _runner_fixture(gs, traeger)
	var room: RoomStub = fixture[0]
	var runner: GoobyReactions = fixture[1]
	await wait_frames(3)
	var clips: Array = []
	rig.clip_finished.connect(func(clip: String) -> void: clips.append(clip))
	var zeile := I18nService.t("soul.linie.uebermut.pause")
	assert_ne(zeile, "soul.linie.uebermut.pause", "Pausen-Zeile existiert in den Strings")
	for i in 11:
		runner.now_ms_override = NOW_MS + BREMSE_FREI_MS + i * 1000
		runner.handle_tap()
	assert_eq(room.lines.count(zeile), 1, "der 11. Streichler bittet um Pause")
	# refuse läuft als One-Shot durch (clip_finished ≈ 1,2 s später).
	var refused := await wait_until(func() -> bool: return clips.has("refuse"), 5000)
	assert_true(refused, "refuse-Clip lief nicht durch (%s)" % [clips])
	# Direkt weiterstreicheln: der Gag feuert im Cooldown NICHT nochmal.
	for i in 5:
		runner.now_ms_override += 1000
		runner.handle_tap()
	assert_eq(room.lines.count(zeile), 1, "Cooldown: keine zweite Pausen-Bitte")
	await _abbau(room, gs)


func test_uebermut_zeile_de_en_paritaetisch() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	assert_true(de.has("soul.linie.uebermut.pause"), "DE-Zeile fehlt")
	assert_true(en.has("soul.linie.uebermut.pause"), "EN-Zeile fehlt")
	assert_eq(
		str(de["soul.linie.uebermut.pause"]),
		"Paus-e-e! Mein Fell ist ganz zerzaust!",
		"die beauftragte Zeile, wortgetreu"
	)
