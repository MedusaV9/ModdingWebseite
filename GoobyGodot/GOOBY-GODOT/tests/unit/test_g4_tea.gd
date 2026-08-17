extends TestCase
## G4-TEA — Präsentations-Verträge der teaParty-Generalkur (W17/G4, Audit
## g4 §3.1): Intro-Beat gatet die Sim (Lauf bleibt zahlengleich —
## test_mg_tea_logic unberührt), _ui-Skalierung des HUD (M9), Füllmeter-
## Mapping (pur, M4), Banner-System für Serie/Spill/Ergebnis (M7), Gieß-Loop
## mit Füllstands-Pitch (M3/M10), Endton-Wahl (M8) und die Reduced-Motion-
## Gates der Stage-Bursts (Q2) samt DE/EN-Parität der Domain-Datei
## mg_tea.json. Die MECHANIK (tea_party_logic.gd) wird hier NICHT berührt.

const Tea := preload("res://scripts/minigames/games/tea_party/tea_party.gd")
const TeaStage := preload("res://scripts/minigames/games/tea_party/tea_party_stage3d.gd")
const SCENE := "res://scripts/minigames/games/tea_party/tea_party.tscn"


func _mount(difficulty := "normal", seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "teaParty"
	ctx.difficulty = difficulty
	ctx.run_seed = seed_value
	var game: MinigameBase = (load(SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


func test_intro_beat_konstante() -> void:
	var consts := (Tea as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "teaParty hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_intro_gatet_die_sim() -> void:
	var game := _mount()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	# Während des Beats wartet die Sim: elapsed bleibt 0, die Servier-Uhr steht.
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim wartet im Intro")
	assert_true(bool(game.get("serving")), "Servier-Phase wartet mit")
	assert_almost(float(game.get("serve_left")), 0.5, 1e-6, "Servier-Uhr steht im Intro")
	# Eingabe ist im Intro gegated: ein Touch darf kein Gießen starten.
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(200.0, 400.0)
	game._unhandled_input(touch)
	assert_false(bool(game.get("holding")), "kein Gießen im Intro")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	assert_almost(float(game.get("serve_left")), 0.3, 1e-6, "Servier-Uhr läuft erst jetzt")
	game.free()


func test_ui_faktor_und_hud_skalierung() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var hint_phone := (game.get("_hint_label") as Label).size.x
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	var hint_pad := (game.get("_hint_label") as Label).size.x
	assert_true(hint_pad > hint_phone, "Hinweis wächst mit (kein 280-px-Nagel mehr)")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	game.free()


func test_fuellmeter_mapping_pur() -> void:
	var rect := Rect2(Vector2(300.0, 100.0), Vector2(14.0, 200.0))
	assert_almost(Tea.meter_level_y(0.0, rect), 300.0, 1e-6, "Level 0 = Unterkante")
	assert_almost(Tea.meter_level_y(1.0, rect), 100.0, 1e-6, "Level 1 (Overflow) = Oberkante")
	assert_almost(Tea.meter_level_y(0.5, rect), 200.0, 1e-6, "halbvoll = Mitte")
	assert_almost(Tea.meter_level_y(9.9, rect), 100.0, 1e-6, "über 1 wird geklemmt")
	var band := Tea.meter_band_rect(rect, 0.7, 0.075)
	assert_almost(band.position.y, 145.0, 1e-6, "Band-Oberkante bei center+half")
	assert_almost(band.end.y, 175.0, 1e-6, "Band-Unterkante bei center−half")
	assert_almost(band.size.x, rect.size.x, 1e-6, "Band füllt die Meter-Breite")
	# Werte 1:1 aus der Logik: das Good-Band liegt IM Meter, der Perfect-Kern
	# liegt IM Good-Band (keine eigene Meter-Mathematik).
	var perfect := Tea.meter_band_rect(rect, 0.7, 0.028)
	assert_true(band.encloses(perfect), "Perfect-Kern liegt im Good-Band")


func test_banner_serie_und_spill() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	game.set("serving", false)
	game.set("cup_slide", 0.0)
	game.set("_banner_t", 0.0)
	# Perfekt in der Bandmitte bei Serie 2 → volle 3er-Serie = Feier-Beat
	# (W21/P5: die Serie feiert als Kit-Beat — Gold-Pille + Sparkle — statt
	# als statisches Banner; die Sim-Zahlen bleiben unangetastet).
	game.set("streak", 2)
	var band: Dictionary = game.get("band")
	game.set("level", float(band["center"]))
	game.call("_release")
	assert_eq(int(game.get("streak")), 3, "Perfect zählt die Serie (Logik unangetastet)")
	var beat := game.get_node_or_null(^"FeierBeat")
	assert_true(beat != null, "Serien-Feier-Beat steht (W21/P5 MG-HUD-Kit)")
	assert_eq(
		(beat.get_node(^"Plate/Text") as Label).text,
		I18nService.t("mg.teaParty.streak_banner", {"n": 3}),
		"Feier-Beat trägt den Serien-Text"
	)
	# Weit unterm Band loslassen → Spill-Banner, Serie reißt (Sim-Zahlen).
	game.set("serving", false)
	game.set("level", 0.05)
	game.call("_release")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.teaParty.spill"), "Spill-Banner")
	assert_false(bool(game.get("_banner_gold")), "Spill-Banner ist nicht gold")
	assert_eq(int(game.get("spills")), 1, "Spill gezählt")
	assert_eq(int(game.get("streak")), 0, "Serie gerissen")
	game.free()


func test_ergebnis_banner_und_endton() -> void:
	assert_eq(Tea.end_sfx_for(12), "mg_win", "gepunktete Runde klingt nach mg_win")
	assert_eq(Tea.end_sfx_for(0), "mg_lose", "Null-Runde klingt nach mg_lose")
	var game := _mount()
	game.set("_intro_left", 0.0)
	game.set("score", 9)
	game.set("cups", 3)
	game.call("_finish")
	assert_true(bool(game.get("finished")), "Runde ist zu")
	assert_eq(
		str(game.get("_banner")),
		I18nService.t("mg.teaParty.ende_zeit", {"cups": 3}),
		"Ergebnis-Banner steht"
	)
	assert_true(bool(game.get("_banner_gold")), "Punkte-Runde feiert gold")
	game.free()
	var endless := _mount("endless")
	endless.set("_intro_left", 0.0)
	endless.call("_finish")
	assert_eq(
		str(endless.get("_banner")),
		I18nService.t("mg.teaParty.ende_spills"),
		"Endlos-Ende (3 Spills) hat ein eigenes Banner"
	)
	assert_false(bool(endless.get("_banner_gold")), "Endlos-Ende feiert nicht gold")
	endless.free()


func test_giess_loop_pitch_folgt_dem_fuellstand() -> void:
	var game := _mount()
	var pour := game.get("_pour") as AudioStreamPlayer
	assert_true(pour != null, "Gieß-Loop-Player existiert (care_wasser aus der SfxMap)")
	if pour == null:
		game.free()
		return
	# Im Intro läuft der Loop gar nicht erst an (play() kommt erst beim
	# Gießen — stream_paused wirkt in Godot nur auf LAUFENDE Playbacks).
	game._process(0.1)
	assert_false(pour.playing, "Intro: Loop ist aus")
	game.set("_intro_left", 0.0)
	game.set("serving", false)
	game.set("cup_slide", 0.0)
	game.set("holding", true)
	game._process(0.1)
	assert_true(pour.playing, "Gießen: Loop läuft an")
	assert_false(pour.stream_paused, "Gießen: nicht pausiert")
	var pitch_low := pour.pitch_scale
	game.set("level", 0.9)
	game._process(0.05)
	assert_true(pour.pitch_scale > pitch_low, "Pitch steigt mit dem Füllstand")
	game.set("holding", false)
	game._process(0.05)
	assert_true(pour.stream_paused, "Loslassen pausiert den Loop")
	game.free()


func test_reduced_motion_gates_der_stage_bursts() -> void:
	var stage: Node3D = TeaStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	stage.call("celebrate", true)
	assert_false((stage.get("_confetti") as GPUParticles3D).emitting, "RM: kein Konfetti")
	stage.call("celebrate", false)
	assert_true((stage.get("_confetti") as GPUParticles3D).emitting, "ohne RM feuert Konfetti")
	stage.call("groan", true)
	assert_false((stage.get("_spill_burst") as GPUParticles3D).emitting, "RM: kein Spill-Burst")
	assert_true(float(stage.get("_puddle_age")) < 0.01, "Pfütze (statisch) bleibt unter RM")
	stage.call("groan", false)
	assert_true((stage.get("_spill_burst") as GPUParticles3D).emitting, "ohne RM Spill-Burst")
	# Tropfen im Strahl hängen am sync-Flag (6. Parameter, Default false —
	# der test_mpa_stages-Altvertrag mit 5 Argumenten bleibt gültig).
	var band := {"center": 0.7, "half": 0.075}
	stage.call("sync", 0.4, band, true, 0.0, 0.016, true)
	assert_false((stage.get("_drops") as GPUParticles3D).emitting, "RM: keine Strahl-Tropfen")
	stage.call("sync", 0.4, band, true, 0.0, 0.016, false)
	assert_true((stage.get("_drops") as GPUParticles3D).emitting, "Gießen: Strahl-Tropfen an")
	tree.root.remove_child(stage)
	stage.free()


func test_fuellmeter_anker_und_intro_totale() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	var stage: Node3D = game.get("_stage")
	var anchors: Dictionary = stage.call("fill_screen_anchors")
	var top: Vector2 = anchors["top"]
	var bottom: Vector2 = anchors["bottom"]
	assert_true(top.is_finite() and bottom.is_finite(), "Anker sind projizierbar")
	assert_true(bottom.y > top.y, "Level 0 liegt am Bildschirm UNTER Level 1")
	# establish(1) muss exakt in der Spielpose landen (Intro-Ende == Spielbild).
	var cam := (stage.get("stage") as Node3D).get("camera") as Camera3D
	stage.call("establish", 0.0)
	var totale := cam.position as Vector3
	stage.call("establish", 1.0)
	assert_true(totale.z > cam.position.z, "Totale steht weiter hinten als die Spielpose")
	assert_true(
		cam.position.distance_to(Vector3(0.0, 1.34, 2.3)) < 0.001,
		"establish(1) == gemerkte Hochkant-Spielpose"
	)
	game.free()


func test_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_tea.json")
	var en := _flat_keys("res://strings/en/mg_tea.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.teaParty.intro"), "Intro-Key vorhanden")
	assert_true(de.has("mg.teaParty.streak_banner"), "Serien-Key vorhanden")
	assert_ne(
		I18nService.t("mg.teaParty.intro"),
		"mg.teaParty.intro",
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
