extends SceneTree
## REST-2-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte für Tagesquests, handlungsgeführtes Onboarding und den
## „Was nun?“-Hinweis im ECHTEN Wohnzimmer (wohnzimmer.tscn). Alle Abläufe
## laufen über die echten Pfade (OnboardingGuide, DailyQuestService) —
## erfüllt wird durch ECHTE Zähler-Bumps, nicht durch UI-Fakes. Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/screenshot_rest2.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/REST2"
const GameStateScript := preload("res://scripts/state/game_state.gd")

var _gs: Node = null
var _room: Node = null
var _guide: OnboardingGuide = null
var _service: DailyQuestService = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(720, 1280)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var dir := "user://rest2_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_gs = GameStateScript.new()
	_gs.initialize(dir + "/save_v5.json")
	_gs.update(
		func(s: Dictionary) -> void:
			s["meta"]["playerName"] = "Mira"
			s["meta"]["goobyNickname"] = "Gooby"
			if not (s.get("onboarding") is Dictionary):
				s["onboarding"] = {}
			s["onboarding"]["done"] = true
	)
	_build_room()
	await _settle(70)
	await _shots_onboarding()
	await _shots_quests()
	await _shot_wasnun()
	print("REST2-Screenshots fertig -> %s" % OUT_DIR)
	_room.queue_free()
	await _settle(2)
	_gs.free()
	quit(0)


func _build_room() -> void:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	_room = scene.instantiate()
	_room.set("game_state_override", _gs)
	_room.set("stunde_override", 10.0)
	root.add_child(_room)
	# Der Raum haengt hier manuell im Baum (nicht ueber den Router) — den
	# Router-Verweis nachziehen, damit die In-Raum-Gates echt laufen.
	var router := root.get_node_or_null("SceneRouter")
	if router != null:
		router._current_scene = _room


## --- Onboarding: Ankunft, Tun-Schritt, Erfolgserlebnis, Ausblick -------------


func _shots_onboarding() -> void:
	_guide = OnboardingGuide.attach_to(_room, _gs)
	await _settle(30)
	await _shot("onboarding_1_ankunft.png")
	_guide._on_next_pressed()
	await _settle(20)
	await _shot("onboarding_2_streicheln.png")
	# Echtes Tun: ein Streichler landet im tagesgebundenen Zähler. Die
	# Feier-Karte steht nur FEIER_S (1.6 s) — unter xvfb dauern Frames lang,
	# also sofort schießen, sobald der Feier-Zustand steht.
	_bump_counter("petsToday", 1)
	await _settle(2)
	if not _guide.is_celebrating():
		push_error("Feier-Zustand nach Streichler nicht erreicht.")
	await _shot("onboarding_3_streicheln_geschafft.png")
	# Feier abwarten -> nächster Schritt: Füttern (Kühlschrank).
	await _wait_for_step("fuettern")
	await _settle(10)
	await _shot("onboarding_4_fuettern.png")
	_guide._enter_step(8)
	await _settle(20)
	await _shot("onboarding_5_ausblick.png")
	_guide._end_tour()
	await _settle(10)


## --- Tagesquests: Panel offen + echter Abschluss mit Häkchen -----------------


func _shots_quests() -> void:
	_service = DailyQuestService.attach_to(_room, _gs)
	await _settle(10)
	_service.open_panel()
	await _settle(40)
	await _shot("quests_1_panel_offen.png")
	var row := _first_open_row()
	if row.is_empty():
		push_error("Kein offener Quest-Eintrag auf dem Brett.")
		return
	_satisfy(row["def"])
	await _settle(20)
	_service._on_panel_claim(str((row["def"] as Dictionary).get("id", "")))
	await _settle(25)
	await _shot("quests_2_abschluss_haekchen.png")
	_service._sheet.close()
	await _settle(45)


func _first_open_row() -> Dictionary:
	for r: Dictionary in _service.board():
		if not bool(r.get("claimed", false)):
			return r
	return {}


## Quest-Messung mit ECHTEN Zähler-Bumps erfüllen (alle Messtypen).
func _satisfy(def: Dictionary) -> void:
	var messung: Dictionary = def.get("messung") if def.get("messung") is Dictionary else {}
	var typ := str(messung.get("typ", ""))
	var ziel := DailyQuestEngine.target_of(def)
	var spiel := str(messung.get("spiel", "teaParty"))
	_gs.update(
		func(s: Dictionary) -> void:
			var counters: Dictionary = s["achievements"]["counters"]
			var econ: Dictionary = s["economy"]
			if typ == "counter":
				var key := str(messung.get("key", ""))
				counters[key] = int(counters.get(key, 0)) + ziel
			elif typ == "streicheln_heute":
				counters["petsToday"] = int(counters.get("petsToday", 0)) + ziel
			elif typ == "spiele_gesamt" or typ == "spiel_runden":
				var plays := _plays_dict(s)
				plays[spiel] = int(plays.get(spiel, 0)) + ziel
			elif typ == "spiele_verschieden":
				var plays2 := _plays_dict(s)
				var ids := _playable_ids()
				for i in mini(ziel, ids.size()):
					plays2[ids[i]] = int(plays2.get(ids[i], 0)) + 1
			elif typ == "spiel_punkte":
				var plays3 := _plays_dict(s)
				plays3[spiel] = int(plays3.get(spiel, 0)) + 1
				var legacy: Dictionary = s["minigames"].get("legacy", {})
				if not (legacy.get("best") is Dictionary):
					legacy["best"] = {}
				legacy["best"][spiel] = ziel
				s["minigames"]["legacy"] = legacy
			elif typ == "muenzen_verdient":
				econ["coinsEarned"] = int(econ.get("coinsEarned", 0)) + ziel
			elif typ == "muenzen_ausgegeben":
				econ["coinsSpent"] = int(econ.get("coinsSpent", 0)) + ziel
	)
	_gs.notify_slice_changed("achievements")


func _plays_dict(s: Dictionary) -> Dictionary:
	if not (s.get("minigames") is Dictionary):
		s["minigames"] = {}
	if not (s["minigames"].get("plays") is Dictionary):
		s["minigames"]["plays"] = {}
	return s["minigames"]["plays"]


func _playable_ids() -> Array[String]:
	var ids: Array[String] = []
	for meta in MinigameRegistry.playable():
		ids.append(str(meta["id"]))
	return ids


## --- „Was nun?“ ---------------------------------------------------------------


func _shot_wasnun() -> void:
	_service.refresh_hint()
	await _settle(30)
	await _shot("wasnun_hinweis.png")


## --- Helfer -------------------------------------------------------------------


func _wait_for_step(step_id: String) -> void:
	for _i in 600:
		if _guide == null or not is_instance_valid(_guide):
			return
		if _guide.current_step_id() == step_id and not _guide.is_celebrating():
			return
		await process_frame
	push_error("Schritt %s nicht erreicht." % step_id)


func _bump_counter(key: String, by: int) -> void:
	_gs.update(
		func(s: Dictionary) -> void:
			var counters: Dictionary = s["achievements"]["counters"]
			counters[key] = int(counters.get(key, 0)) + by
	)
	_gs.notify_slice_changed("achievements")


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
