extends TestCase
## G4/W17 G4-DANCE — Präsentations-Verträge der danceParty-Politur:
## Intro dockt am BESTEHENDEN musikalischen Vorlauf an (kein Doppel-Gate,
## Uhr/Notenbild zahlengleich — Crosscheck-Vertrag), _ui-Skalierung des HUD
## (M9), Hit-Quality-Popups am Ring farblich gestuft (M3/M7), Hint-Fade
## (M6), Club-Seitenwände füllen die Sichtkante im Quer (M2/M5), Intro-Spot
## fährt hoch (M1) und die DE/EN-Parität der Domain-Datei mg_dance.json.
## Die MECHANIK (dance_party_logic.gd, dance_timing.gd) wird NICHT berührt.

const Dance := preload("res://scripts/minigames/games/dance_party/dance_party.gd")
const DanceStage := preload("res://scripts/minigames/games/dance_party/dance_party_stage3d.gd")
const SCENE := "res://scripts/minigames/games/dance_party/dance_party.tscn"


func _mount(difficulty := "normal", seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "danceParty"
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


func test_intro_dockt_am_vorlauf_an_und_gatet_nicht() -> void:
	var game := _mount()
	assert_almost(float(game.get("song_time")), -2.4, 1e-9, "Song startet am Vorlauf −2,4 s")
	# Banner-Leselinse auf den Vorlauf: sichtbar im Beat, weg nach dem Start.
	assert_almost(Dance.intro_progress(-2.4, 2.4), 0.0, 1e-9, "Vorlauf-Beginn = 0")
	assert_almost(Dance.intro_progress(0.0, 2.4), 1.0, 1e-9, "Songstart = 1")
	assert_true(Dance.intro_banner_alpha(-1.5, 2.4) > 0.9, "Banner steht im Vorlauf")
	assert_almost(Dance.intro_banner_alpha(1.2, 2.4), 0.0, 1e-9, "Banner nach dem Start weg")
	# KEIN Doppel-Gate: die Uhr tickt im Vorlauf normal weiter (zahlengleich).
	game._process(0.5)
	assert_almost(float(game.get("song_time")), -1.9, 1e-9, "Vorlauf-Uhr läuft ungegatet")
	# Notenbild unangetastet: 78 Noten, erste bei 7,2 s (Crosscheck-Vertrag).
	var notes: Array = game.get("notes")
	assert_eq(notes.size(), 78, "Standard-Chart bleibt 78 Noten")
	assert_almost(
		float((notes[0] as Dictionary)["time"]), 7.199999999999999, 1e-12, "erste Note 7,2 s"
	)
	game.free()


func test_ui_faktor_und_hud_skalierung() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var score: Label = game.get("_score_label")
	assert_eq(score.get_theme_font_size("font_size"), 34, "Basisgröße = Theme-Look")
	assert_true(score.has_theme_color_override("font_outline_color"), "Kontur (M7)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(
		score.get_theme_font_size("font_size"),
		int(34.0 * 834.0 / 390.0),
		"Fonts wachsen mit dem Faktor"
	)
	assert_true(score.position.x > 16.0 + 1.0, "Position skaliert statt Fix-16-px")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	assert_almost(Dance.ui_scale_for(Vector2(390.0, 844.0)), 1.0, 1e-9)
	game.free()


func test_hit_popup_zeigt_wertung_farblich_gestuft() -> void:
	var game := _mount()
	game.set("song_time", 10.0)
	game.call("_judge", "perfect", 200.0)
	var pops: Array = game.get("_hit_pops")
	assert_eq(pops.size(), 1, "Treffer erzeugt genau ein Popup")
	var pop: Dictionary = pops[0]
	assert_eq(str(pop["text"]), I18nService.t("mg.danceParty.perfect"), "Perfekt-Text")
	assert_eq(pop["color"], Dance.hit_pop_color("perfect"), "Goldstufe")
	assert_almost(float(pop["x"]), 200.0, 1e-6, "Popup sitzt am getroffenen Ring")
	game.call("_judge", "good", 300.0)
	pops = game.get("_hit_pops")
	assert_eq(pops.size(), 2, "zweites Popup für gut")
	assert_eq(str((pops[1] as Dictionary)["text"]), I18nService.t("mg.danceParty.good"))
	assert_ne(Dance.hit_pop_color("perfect"), Dance.hit_pop_color("good"), "farblich gestuft")
	game.call("_judge", "miss", 200.0)
	assert_eq((game.get("_hit_pops") as Array).size(), 2, "Fehler bekommt KEIN Quality-Popup")
	# Wertung selbst unangetastet: die Logic hat 2 Treffer + 1 Fehler gebucht.
	var tally: Dictionary = game.get("tally")
	assert_eq(int(tally["perfect"]), 1, "Logic-Zahl perfekt")
	assert_eq(int(tally["good"]), 1, "Logic-Zahl gut")
	assert_eq(int(tally["miss"]), 1, "Logic-Zahl Fehler")
	assert_eq(int(tally["combo"]), 0, "Fehler bricht die Serie (unverändert)")
	# Popups altern und räumen sich selbst weg.
	game.call("_age_pops", 0.5)
	game.call("_age_pops", 0.5)
	assert_eq((game.get("_hit_pops") as Array).size(), 0, "Popups laufen aus")
	game.free()


func test_hit_popup_reduced_motion_steht() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount()
	game.set("song_time", 10.0)
	game.call("_judge", "perfect", 200.0)
	var pop: Dictionary = (game.get("_hit_pops") as Array)[0]
	assert_false(bool(pop["rise"]), "Reduced Motion: Popup steigt nicht auf")
	game.free()
	_set_reduced_motion(bool(previous))
	var game2 := _mount()
	game2.set("song_time", 10.0)
	game2.call("_judge", "perfect", 200.0)
	var pop2: Dictionary = (game2.get("_hit_pops") as Array)[0]
	assert_eq(bool(pop2["rise"]), not bool(previous), "ohne RM steigt es (Vorzustand)")
	game2.free()


func test_hint_fade_vor_der_ersten_note() -> void:
	assert_almost(Dance.hint_alpha_for(-2.4), 1.0, 1e-9, "Vorlauf: Hinweis voll")
	assert_almost(Dance.hint_alpha_for(4.0), 1.0, 1e-9, "bis Sekunde 4 voll")
	assert_true(Dance.hint_alpha_for(4.8) > 0.0 and Dance.hint_alpha_for(4.8) < 1.0, "Fade")
	assert_almost(Dance.hint_alpha_for(5.5), 0.0, 1e-9, "ab 5,5 s weg")
	assert_almost(Dance.hint_alpha_for(7.2), 0.0, 1e-9, "erste Note: Feld frei")


func test_stage_fuellt_querformat_bis_zur_sichtkante() -> void:
	var stage: Node3D = DanceStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	# Querformat 1160×720: lane_x/hit/top wie die Szene sie rechnet.
	stage.frame(Vector2(1160.0, 720.0))
	var lane_xs: Array[float] = [430.0, 580.0, 730.0]
	stage.layout(lane_xs, 720.0 * 0.08, 720.0 * 0.74, 150.0)
	var walls: Array = stage.get("_walls")
	assert_eq(walls.size(), 2, "zwei Club-Seitenwände")
	var wall := walls[1] as MeshInstance3D
	assert_true(wall.visible, "Wand sichtbar nach layout()")
	var quad := wall.mesh as QuadMesh
	var outer := wall.position.x + quad.size.x * 0.5
	var inner := wall.position.x - quad.size.x * 0.5
	# Sichtkante an der Wandtiefe: half_width · (CAM_DIST − WALL_Z)/CAM_DIST.
	var depth := (DanceStage.CAM_DIST - DanceStage.WALL_Z) / DanceStage.CAM_DIST
	var edge_quer := DanceStage.HALF_H * (1160.0 / 720.0) * depth
	assert_true(outer >= edge_quer, "Wand deckt die Quer-Sichtkante (%f ≥ %f)" % [outer, edge_quer])
	var ppu := 720.0 / (DanceStage.HALF_H * 2.0)
	assert_true(inner > (730.0 - 580.0) / ppu, "Wand beginnt AUSSERHALB der Bahnen")
	assert_true((stage.get("_side_cones") as Array).size() == 2, "zwei Wand-Scheinwerfer")
	assert_true((stage.get("_wall_strips") as MultiMeshInstance3D).visible, "Neon-Säulen an")
	# Hochkant 720×1160: die Wände rücken an die schmalere Sichtkante.
	stage.frame(Vector2(720.0, 1160.0))
	var lane_hoch: Array[float] = [210.0, 360.0, 510.0]
	stage.layout(lane_hoch, 1160.0 * 0.08, 1160.0 * 0.74, 150.0)
	var outer_hoch := wall.position.x + (wall.mesh as QuadMesh).size.x * 0.5
	assert_true(outer_hoch < outer, "hochkant schmiegt sich die Wand an den Rand")
	stage.queue_free()
	await wait_frames(1)


func test_seiten_lichtshow_reduced_motion_steht() -> void:
	var stage: Node3D = DanceStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	stage.frame(Vector2(720.0, 1160.0))
	var lane_xs: Array[float] = [210.0, 360.0, 510.0]
	stage.layout(lane_xs, 92.8, 858.4, 150.0)
	var notes: Array[Dictionary] = []
	var flash: Array[float] = [0.0, 0.0, 0.0]
	var cones: Array = stage.get("_side_cones")
	# reduced=true: zwei verschiedene Puls-Zeiten, identische Grundstellung.
	stage.sync(notes, flash, 0, 0.6, 1.0, 0.0, false, 1.3, 0.016, true)
	var rot_a := (cones[0] as Node3D).rotation.z
	stage.sync(notes, flash, 0, 0.6, 1.0, 0.0, false, 2.9, 0.016, true)
	assert_eq(rot_a, (cones[0] as Node3D).rotation.z, "Reduced Motion: Scheinwerfer steht")
	# reduced=false (Default-Signatur der mpc-Tests): die Show schwenkt.
	stage.sync(notes, flash, 0, 0.6, 1.0, 0.0, false, 0.9, 0.016)
	var rot_b := (cones[0] as Node3D).rotation.z
	stage.sync(notes, flash, 0, 0.6, 1.0, 0.0, false, 2.2, 0.016)
	assert_ne(rot_b, (cones[0] as Node3D).rotation.z, "ohne RM schwenkt der Scheinwerfer")
	stage.queue_free()
	await wait_frames(1)


func test_intro_spot_faehrt_hoch() -> void:
	var stage: Node3D = DanceStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	stage.frame(Vector2(720.0, 1160.0))
	var lane_xs: Array[float] = [210.0, 360.0, 510.0]
	stage.layout(lane_xs, 92.8, 858.4, 150.0)
	var spot: OmniLight3D = stage.get("_spot")
	stage.intro_spot(0.0)
	var dim := spot.light_energy
	assert_true(dim < 0.5, "Vorlauf-Beginn: Spot gedimmt")
	stage.intro_spot(1.0)
	assert_true(spot.light_energy > dim + 0.8, "Spot fährt sichtbar hoch")
	assert_almost(spot.omni_range, 6.0, 1e-6, "Reichweite landet auf dem Spielwert")
	stage.queue_free()
	await wait_frames(1)


func test_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_dance.json")
	var en := _flat_keys("res://strings/en/mg_dance.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.danceParty.intro"), "Intro-Key vorhanden")
	assert_true(de.has("mg.danceParty.perfect"), "Perfekt-Key vorhanden")
	assert_true(de.has("mg.danceParty.good"), "Gut-Key vorhanden")
	assert_ne(
		I18nService.t("mg.danceParty.perfect"),
		"mg.danceParty.perfect",
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
