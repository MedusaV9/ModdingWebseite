extends TestCase
## G4-POND — Präsentations-Verträge der fishingPond-Politur (W17):
## Meter-Deckel-Formel (M9 — quer lief der Kurbelbalken ~740 px übers Bild),
## Intro-Beat 1,5 s gatet Sim UND Eingabe (M1, Lauf bleibt zahlengleich,
## Crosscheck-Vertrag), Intro-Kamera kehrt exakt in die Spielpose zurück,
## `_ui`-Faktor klemmt (M9), Hint-Fade (M6), Wasserringe expandieren/recyclen
## und sind Reduced-Motion-gegatet (M3/Q2) und die DE/EN-Parität der neuen
## Domain-Datei mg_pond.json.
## Die MECHANIK (fishing_pond_logic.gd) wird hier NICHT berührt.

const Pond := preload("res://scripts/minigames/games/fishing_pond/fishing_pond.gd")
const Scenery := preload("res://scripts/minigames/games/fishing_pond/fishing_pond_scenery.gd")
const SCENE := "res://scripts/minigames/games/fishing_pond/fishing_pond.tscn"


func _mount(difficulty := "normal", seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "fishingPond"
	ctx.difficulty = difficulty
	ctx.run_seed = seed_value
	var game: MinigameBase = (load(SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


## Schaltet Reduced Motion am ECHTEN AppSettings-Autoload (ein Stub gleichen
## Namens würde verdeckt — Muster test_feel_juice). Liefert den Vorzustand.
func _set_reduced_motion(enabled: bool) -> Variant:
	var settings := tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return null
	var previous := bool(settings.is_reduced_motion())
	settings.set_setting("reduced_motion", enabled)
	return previous


func _active_rings(game: MinigameBase) -> int:
	var holder: Node3D = game.get("_ripples")
	var active := 0
	for ring in holder.get_children():
		if float(ring.get_meta("t")) < Scenery.RIPPLE_LIFE:
			active += 1
	return active


func test_intro_beat_konstante() -> void:
	var consts := (Pond as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "fishingPond hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_meter_deckel_formel() -> void:
	# Hochkant-Phone: 62 % der Breite greifen, der Deckel nicht.
	assert_almost(Pond.reel_meter_width(390.0, 1.0), 241.8, 1e-4, "hochkant 62 %")
	# Quer-Phone (844×390, _ui = 1): der Deckel begrenzt auf 420 px —
	# vorher liefen 0,62 · 844 ≈ 523 px übers Bild.
	assert_almost(Pond.reel_meter_width(844.0, 1.0), 420.0, 1e-6, "quer gedeckelt")
	# iPad quer (1194×834): _ui wächst mit, der Deckel (898) greift nicht —
	# der Balken bleibt bei 62 % (~740 px auf ~900 px erlaubter Breite).
	var ui := clampf(834.0 / 390.0, 0.75, 3.0)
	assert_almost(Pond.reel_meter_width(1194.0, ui), 740.28, 0.01, "iPad: 62 % unterm Deckel")
	# Mini-Fenster: nie breiter als 62 % der Bildbreite.
	assert_almost(Pond.reel_meter_width(200.0, 0.75), 124.0, 1e-4, "Mini-Fenster")


func test_ui_faktor_klemmt() -> void:
	var game := _mount()
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


func test_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	var fish: Array = game.get("fish")
	assert_eq(fish.size(), 7, "7 Schwimmer ab Sekunde 0 (FISH_COUNT unverändert)")
	var x0 := float((fish[0] as Dictionary)["x"])
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim-Uhr wartet im Intro")
	assert_almost(float(game.get("since_boot")), 0.0, 1e-6, "Stiefel-Uhr wartet")
	assert_almost(float((fish[0] as Dictionary)["x"]), x0, 1e-9, "Schwimmer warten")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	game._unhandled_input(touch)
	assert_eq(str(game.get("phase")), "idle", "Eingabe zählt im Beat nicht")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	assert_ne(float((fish[0] as Dictionary)["x"]), x0, "Schwimmer schwimmen wieder")
	game._unhandled_input(touch)
	assert_eq(str(game.get("phase")), "lower", "Touch senkt den Haken nach dem Beat")
	game.free()


func test_intro_kamera_kehrt_in_die_spielpose_zurueck() -> void:
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var base := cam.position
	game._process(0.016)
	assert_true(cam.position.y > base.y + 0.5, "Intro-Kamera hebt übers Diorama")
	for _i in 5:
		game._process(0.4)
	assert_true(cam.position.distance_to(base) < 1e-3, "nach dem Beat exakt die fit()-Pose")
	game.free()


func test_hint_fade() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	assert_almost(float(game.call("_hint_alpha")), 1.0, 1e-6, "Start: Hinweis voll da")
	game.set("elapsed", 5.75)
	assert_almost(float(game.call("_hint_alpha")), 0.5, 1e-6, "halb verblasst")
	game.set("elapsed", 7.0)
	assert_almost(float(game.call("_hint_alpha")), 0.0, 1e-6, "nach 6,5 s weg")
	game.call("_update_labels")
	assert_almost((game.get("_hint_label") as Label).modulate.a, 0.0, 1e-6, "Fade am Label")
	game.free()


func test_ripples_expandieren_und_recyclen() -> void:
	var stage := Node3D.new()
	tree.root.add_child(stage)
	var holder: Node3D = Scenery.build_ripples(stage)
	assert_eq(holder.get_child_count(), Scenery.RIPPLE_POOL, "Ring-Pool steht")
	Scenery.spawn_ripple(holder, Vector3(0.5, 0.015, -0.35), 1.0)
	var ring := holder.get_child(0) as MeshInstance3D
	assert_almost(float(ring.get_meta("t")), 0.0, 1e-9, "erster Ring gestartet")
	Scenery.tick_ripples(holder, 0.3)
	assert_true(ring.visible, "Ring sichtbar")
	var mat: StandardMaterial3D = ring.get_meta("mat")
	assert_true(mat.albedo_color.a > 0.0, "Ring hat Deckkraft")
	var radius := ring.scale.x
	Scenery.tick_ripples(holder, 0.3)
	assert_true(ring.scale.x > radius, "Ring expandiert")
	Scenery.tick_ripples(holder, 1.0)
	assert_false(ring.visible, "Lebenszeit vorbei — Ring aus")
	Scenery.spawn_ripple(holder, Vector3.ZERO, 0.5)
	assert_almost(float(ring.get_meta("t")), 0.0, 1e-9, "Pool recycelt den Ring")
	stage.free()


func test_ripple_gate_reduced_motion() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount()
	game.set("_intro_left", 0.0)
	for _i in 40:
		game._process(0.05)
	assert_eq(_active_rings(game), 0, "Reduced Motion: keine Wasserringe")
	_set_reduced_motion(false)
	# Der Puls feuert alle 1,4 s — bis zum nächsten Ring laufen (gedeckelt).
	var saw := false
	for _i in 60:
		game._process(0.05)
		if _active_rings(game) > 0:
			saw = true
			break
	assert_true(saw, "ohne Reduced Motion pulsen die Ringe")
	_set_reduced_motion(bool(previous))
	game.free()


func test_intro_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_pond.json")
	var en := _flat_keys("res://strings/en/mg_pond.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.fishingPond.intro"), "Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.fishingPond.intro"),
		"mg.fishingPond.intro",
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
