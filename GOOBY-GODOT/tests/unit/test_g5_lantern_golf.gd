extends TestCase
## G5-P29 — Präsentations-Verträge der lanternFloat-/miniGolf-Politur (W17):
## Intro-Beats 1,5 s gaten Sim UND Eingabe (M1, RNG-Strom unangetastet —
## der w13c-Crosscheck bleibt zahlengleich), die Intro-Kameras kehren exakt
## in die Spielpose zurück, Böen-Windlayer folgt der Böenphase (Audit §6:
## Telegraph war stumm), Q2-Gate am Stage-Burst der Laterne, Hint-Fades
## (M6), `_ui`-Faktor des Golf-HUD klemmt (M9), Putt-Pitch wächst mit der
## Schlagkraft, Endton-Wahl beider Spiele (M8) und die DE/EN-Parität der
## neuen Domain-Datei mg_lantern_golf.json.
## Die MECHANIK (lantern_float_logic.gd / mini_golf_logic.gd) bleibt tabu.

const Lantern := preload("res://scripts/minigames/games/lantern_float/lantern_float.gd")
const Golf := preload("res://scripts/minigames/games/mini_golf/mini_golf.gd")
const GolfFeel := preload("res://scripts/minigames/games/mini_golf/mini_golf_feel.gd")
const GolfLogic := preload("res://scripts/minigames/games/mini_golf/mini_golf_logic.gd")
const LANTERN_SCENE := "res://scripts/minigames/games/lantern_float/lantern_float.tscn"
const GOLF_SCENE := "res://scripts/minigames/games/mini_golf/mini_golf.tscn"


func _mount(scene: String, game_id: String, difficulty := "normal") -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = difficulty
	ctx.run_seed = 4242
	var game: MinigameBase = (load(scene) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


func _mount_lantern(difficulty := "normal") -> MinigameBase:
	return _mount(LANTERN_SCENE, "lanternFloat", difficulty)


func _mount_golf(difficulty := "normal") -> MinigameBase:
	return _mount(GOLF_SCENE, "miniGolf", difficulty)


## Schaltet Reduced Motion am ECHTEN AppSettings-Autoload (ein Stub gleichen
## Namens würde verdeckt — Muster test_feel_juice). Liefert den Vorzustand.
func _set_reduced_motion(enabled: bool) -> Variant:
	var settings := tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return null
	var previous := bool(settings.is_reduced_motion())
	settings.set_setting("reduced_motion", enabled)
	return previous


# ------------------------------------------------------------ lanternFloat


func test_lantern_intro_konstante() -> void:
	var consts := (Lantern as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "lanternFloat hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_lantern_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount_lantern()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	var next_index0 := int(game.get("_next_index"))
	var rings0 := (game.get("_rings") as Array).size()
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim-Uhr wartet im Intro")
	assert_almost(float(game.get("travel")), 0.0, 1e-6, "die Laterne wartet")
	assert_eq(int(game.get("_next_index")), next_index0, "kein zusätzlicher Ring-Wurf")
	assert_eq((game.get("_rings") as Array).size(), rings0, "RNG-Strom unangetastet")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(float(game.get("view_size").x), 100.0)
	game._unhandled_input(touch)
	assert_almost(float(game.get("steer_target")), 0.0, 1e-9, "Eingabe zählt im Beat nicht")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	assert_true(float(game.get("travel")) > 0.0, "die Laterne steigt wieder")
	game._unhandled_input(touch)
	assert_true(float(game.get("steer_target")) > 0.0, "Touch steuert nach dem Beat")
	game.free()


func test_lantern_intro_kamera_kehrt_in_die_spielpose_zurueck() -> void:
	var game := _mount_lantern()
	var wrapper: Node3D = game.get("_stage")
	var cam: Camera3D = (wrapper.get("stage") as Node3D).get("camera")
	var base := cam.position
	game._process(0.016)
	assert_true(cam.position.y < base.y - 0.5, "Intro-Kamera senkt sich zur See-Totale")
	for _i in 5:
		game._process(0.4)
	assert_true(cam.position.distance_to(base) < 1e-3, "nach dem Beat exakt die frame()-Pose")
	assert_true(cam.rotation.is_zero_approx(), "Blick wieder frontal auf die Flugebene")
	game.free()


func test_lantern_wind_layer_folgt_der_boee() -> void:
	var game := _mount_lantern()
	game.set("_intro_left", 0.0)
	var wind: AudioStreamPlayer = game.get("_wind")
	assert_true(wind != null, "Windlayer-Player steht (ranch_ambience_wind)")
	assert_true(wind.stream != null, "Loop-Stream geladen")
	game.set("elapsed", 3.0)
	game.call("_sync_wind", 1.0)
	var idle_db := wind.volume_db
	game.set("elapsed", 7.5)
	game.call("_sync_wind", 1.0)
	var telegraph_db := wind.volume_db
	game.set("elapsed", 8.5)
	game.call("_sync_wind", 1.0)
	var push_db := wind.volume_db
	assert_true(idle_db < -40.0, "ohne Böe praktisch still (%s dB)" % idle_db)
	assert_true(telegraph_db > idle_db + 8.0, "Telegraph hörbar leise angekündigt")
	assert_true(push_db > telegraph_db + 8.0, "Blasen deutlich lauter als Telegraph")
	assert_true(wind.pitch_scale > 1.2, "Pitch zieht beim Blasen mit")
	game.free()


func test_lantern_q2_burst_gate() -> void:
	var game := _mount_lantern()
	var wrapper: Node3D = game.get("_stage")
	var burst: GPUParticles3D = wrapper.get("_burst")
	burst.emitting = false
	wrapper.call("award_fx", 0.0, 1.0, false, true)
	assert_false(burst.emitting, "Reduced Motion: kein Stage-Burst (Q2)")
	wrapper.call("award_fx", 0.0, 1.0, false, false)
	assert_true(burst.emitting, "ohne Reduced Motion feuert der Burst")
	game.free()


func test_lantern_hint_fade() -> void:
	var game := _mount_lantern()
	game.set("_intro_left", 0.0)
	assert_almost(float(game.call("_hint_alpha")), 1.0, 1e-6, "Start: Hinweis voll da")
	game.set("elapsed", 5.75)
	assert_almost(float(game.call("_hint_alpha")), 0.5, 1e-6, "halb verblasst")
	game.set("elapsed", 7.0)
	assert_almost(float(game.call("_hint_alpha")), 0.0, 1e-6, "nach 6,5 s weg")
	game.call("_update_labels")
	assert_almost((game.get("_hint_label") as Label).modulate.a, 0.0, 1e-6, "Fade am Label")
	game.free()


func test_lantern_sieg_feier() -> void:
	var game := _mount_lantern()
	game.set("_intro_left", 0.0)
	game.set("score", 12)
	game.set("hits", 5)
	game.set("elapsed", 60.5)
	game._process(0.016)
	assert_true(bool(game.get("finished")), "Zeitablauf beendet die Runde")
	assert_eq(
		str(game.get("_banner")),
		I18nService.t("mg.lanternFloat.win", {"hits": 5}),
		"Sieg-Band steht (Audit §6: Sieg war stumm)"
	)
	assert_almost(float(game.get("_banner_t")), 2.2, 1e-6, "Feier-Band hält länger")
	var wrapper: Node3D = game.get("_stage")
	assert_almost(float(wrapper.get("_light_boost")), 1.0, 1e-6, "Laterne strahlt zur Feier")
	game.free()


func test_lantern_endton_wahl() -> void:
	assert_eq(Lantern.end_sfx_for(false, 12), "mg_win", "gepunktete Zeitfahrt feiert")
	assert_eq(Lantern.end_sfx_for(false, 0), "mg_lose", "Null-Runde tröstet")
	assert_eq(Lantern.end_sfx_for(true, 50), "mg_lose", "Endlos endet über Rempler 3")


# ---------------------------------------------------------------- miniGolf


func test_golf_intro_konstante() -> void:
	var consts := (Golf as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "miniGolf hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_golf_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount_golf()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	var theta0 := float(game.get("theta"))
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("theta")), theta0, 1e-9, "Windmühlen-Uhr wartet im Intro")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(200.0, 400.0)
	game._unhandled_input(touch)
	assert_false(bool(game.get("_dragging")), "Eingabe zählt im Beat nicht")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	game._process(0.2)
	assert_true(float(game.get("theta")) > theta0, "danach dreht die Windmühle wieder")
	game._unhandled_input(touch)
	assert_true(bool(game.get("_dragging")), "Ziehen zielt nach dem Beat")
	game.free()


func test_golf_intro_kamera_kehrt_in_die_spielpose_zurueck() -> void:
	var game := _mount_golf()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var base := cam.position
	game._process(0.016)
	assert_true(cam.position.y > base.y + 0.5, "Intro-Kamera hebt zur Bahn-Totale")
	for _i in 5:
		game._process(0.4)
	assert_true(cam.position.distance_to(base) < 1e-3, "nach dem Beat exakt die fit()-Pose")
	game.free()


func test_golf_ui_faktor_klemmt() -> void:
	var game := _mount_golf()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var hint_phone := (game.get("_hint_label") as Label).size.x
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	var hint_pad := (game.get("_hint_label") as Label).size.x
	assert_true(hint_pad > hint_phone, "Hinweis-Breite wächst mit dem Faktor")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	game.free()


func test_golf_putt_pitch_waechst_mit_der_kraft() -> void:
	var max_power := float(GolfLogic.GOLF["MAX_POWER"])
	assert_almost(GolfFeel.putt_pitch(0.0), 0.9, 1e-9, "Zärtel-Putt klingt tief")
	assert_almost(GolfFeel.putt_pitch(max_power * 0.5), 1.15, 1e-9, "halbe Kraft = Mitte")
	assert_almost(GolfFeel.putt_pitch(max_power), 1.4, 1e-9, "voller Schlag klingt hell")
	assert_almost(GolfFeel.putt_pitch(max_power * 9.0), 1.4, 1e-9, "über Vmax geklemmt")
	assert_true(GolfFeel.putt_pitch(max_power) <= 1.6, "Grammatik-Bereich 0,9–1,6 gewahrt")


func test_golf_hint_fade() -> void:
	var game := _mount_golf()
	game.set("_show_time", 1.5)
	assert_almost(float(game.call("_hint_alpha")), 1.0, 1e-6, "nach dem Beat voll da")
	game.set("_show_time", 1.5 + 5.75)
	assert_almost(float(game.call("_hint_alpha")), 0.5, 1e-6, "halb verblasst")
	game.set("_show_time", 1.5 + 7.0)
	assert_almost(float(game.call("_hint_alpha")), 0.0, 1e-6, "nach ~6,5 s weg")
	game.call("_update_labels")
	assert_almost((game.get("_hint_label") as Label).modulate.a, 0.0, 1e-6, "Fade am Label")
	game.free()


func test_golf_endton_wahl() -> void:
	assert_eq(GolfFeel.end_sfx_for(false, 42), "mg_win", "gepunktete 6-Bahnen-Runde feiert")
	assert_eq(GolfFeel.end_sfx_for(false, 0), "mg_lose", "Null-Runde tröstet")
	assert_eq(GolfFeel.end_sfx_for(true, 99), "mg_lose", "Endlos endet über das Über-Par-Limit")


func test_golf_rundenende_klingt_und_feiert() -> void:
	var game := _mount_golf()
	game.set("_intro_left", 0.0)
	game.set("score", 30)
	game.set("hole_index", 5)
	game.call("_next_hole")
	assert_true(bool(game.get("finished")), "nach Bahn 6 endet die Runde")
	game.free()


# ----------------------------------------------------------------- Strings


func test_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_lantern_golf.json")
	var en := _flat_keys("res://strings/en/mg_lantern_golf.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.lanternFloat.intro"), "Laternen-Intro-Key vorhanden")
	assert_true(de.has("mg.lanternFloat.win"), "Laternen-Sieg-Key vorhanden")
	assert_true(de.has("mg.miniGolf.intro"), "Golf-Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.miniGolf.intro"),
		"mg.miniGolf.intro",
		"Loader mergt die neue Domain-Datei flach"
	)


func _flat_keys(path: String) -> Array[String]:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_true(file != null, "%s fehlt" % path)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	var out: Array[String] = []
	_collect_keys("", data, out)
	out.sort()
	return out


func _collect_keys(prefix: String, node: Variant, out: Array[String]) -> void:
	if node is Dictionary:
		for key: String in node:
			var path := key if prefix.is_empty() else "%s.%s" % [prefix, key]
			_collect_keys(path, node[key], out)
		return
	assert_true(str(node).length() > 0, "%s: Wert leer" % prefix)
	out.append(prefix)
