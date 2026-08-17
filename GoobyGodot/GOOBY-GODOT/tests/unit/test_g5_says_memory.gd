extends TestCase  # gdlint: ignore=max-public-methods
## G5 P28 — Präsentations-Verträge der Duo-Politur goobySays + memoryMatch
## (W17): Intro-Beat 1,5 s gatet Sim-Uhr UND Eingabe (Lauf bleibt zahlen-
## gleich, M1), sichtbare Timeout-Anzeige (Pad-Rand-Puls bzw. Countdown-
## Balken), _ui-Skalierung des HUD (M9), Hint-Fade (M6), Reduced-Motion-
## Gates an den Stage-Burst-Call-Sites (Q2) und die DE/EN-Parität der neuen
## Domain-Datei mg_says_memory.json. Die MECHANIK (gooby_says_logic.gd /
## memory_match_logic.gd) wird hier NICHT berührt — Zahlengleichheit sichert
## test_w13c_crosscheck (test_gooby_says_matches_web/test_memory_match_
## matches_web).

const Says := preload("res://scripts/minigames/games/gooby_says/gooby_says.gd")
const Memory := preload("res://scripts/minigames/games/memory_match/memory_match.gd")
const SAYS_SCENE := "res://scripts/minigames/games/gooby_says/gooby_says.tscn"
const MEMORY_SCENE := "res://scripts/minigames/games/memory_match/memory_match.tscn"


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


func _mount_says(difficulty := "normal") -> MinigameBase:
	return _mount(SAYS_SCENE, "goobySays", difficulty)


func _mount_memory(difficulty := "normal") -> MinigameBase:
	return _mount(MEMORY_SCENE, "memoryMatch", difficulty)


## Schaltet Reduced Motion am ECHTEN AppSettings-Autoload (ein Stub gleichen
## Namens würde verdeckt — Muster test_g4_catch). Liefert den Vorzustand.
func _set_reduced_motion(enabled: bool) -> Variant:
	var settings := tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return null
	var previous := bool(settings.is_reduced_motion())
	settings.set_setting("reduced_motion", enabled)
	return previous


func test_intro_beat_konstanten() -> void:
	var says_consts := (Says as GDScript).get_script_constant_map()
	var memory_consts := (Memory as GDScript).get_script_constant_map()
	assert_almost(float(says_consts["INTRO_S"]), 1.5, 1e-6, "says: Intro 1,5 s (W14-Kanon)")
	assert_almost(float(memory_consts["INTRO_S"]), 1.5, 1e-6, "memory: Intro 1,5 s")
	assert_almost(float(says_consts["HINT_FADE_SEC"]), 6.0, 1e-6, "says: Hint-Fade bei 6 s")
	assert_almost(float(memory_consts["HINT_FADE_SEC"]), 6.0, 1e-6, "memory: Hint-Fade bei 6 s")


func test_says_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount_says()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.goobySays.intro"), "Ziel-Banner")
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner steht im Intro")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim-Uhr wartet im Intro")
	assert_almost(float(game.get("play_timer")), 0.45, 1e-6, "Wiedergabe wartet im Intro")
	# Eingabe ist gegatet: ein Pad-Tap zündet im Intro nicht (auch wenn die
	# Phase künstlich auf input steht).
	game.set("phase", "input")
	var stage: Node3D = game.get("_stage")
	var pads: Array = stage.get("_pads")
	var inner: Node3D = stage.get("stage")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = inner.call("to_screen", (pads[0] as Node3D).position)
	game._unhandled_input(tap)
	assert_eq(int(game.get("lit_pad")), -1, "Tap zündet im Intro nicht")
	assert_eq(int(game.get("step_index")), 0, "kein Schritt-Fortschritt im Intro")
	game.set("phase", "watch")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim-Uhr")
	assert_true(float(game.get("play_timer")) < 0.45, "Wiedergabe läuft nach dem Intro an")
	game.free()


func test_says_intro_kamera_fliegt_in_die_spielpose() -> void:
	var game := _mount_says()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	var play_pos: Vector3 = stage.get("_play_cam_pos")
	game._process(0.1)
	assert_true(cam.position.y > play_pos.y + 0.5, "Intro: Kamera startet erhöht (Totale)")
	# Der letzte Intro-Frame ruft establish(1.0) — exakte Spielpose, kein Ruck.
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, play_pos.y, 1e-4, "Spielpose: exakt wie apply_size")
	assert_almost(cam.position.z, play_pos.z, 1e-4, "Spielpose: exakt wie apply_size (z)")
	game.free()


func test_says_timeout_puls_in_den_letzten_40_prozent() -> void:
	var game := _mount_says()
	game.set("_intro_left", 0.0)
	game.set("phase", "input")
	game.set("step_started_at", 0.0)
	var timeout_ms := float((game.get("tune") as Dictionary)["INPUT_TIMEOUT_MS"])
	var stage: Node3D = game.get("_stage")
	var rims: Array = stage.get("_pad_rims")
	# Bei 50 % des Fensters bleibt der Rand still …
	game.set("elapsed", 0.5 * timeout_ms / 1000.0)
	game._process(0.016)
	assert_almost(float(game.call("_timeout_urgency")), 0.0, 1e-3, "50 %: keine Warnung")
	assert_false((rims[0] as MeshInstance3D).visible, "50 %: Pad-Rand still")
	# … in den letzten 40 % pulsiert er sichtbar.
	game.set("elapsed", 0.75 * timeout_ms / 1000.0)
	game._process(0.016)
	assert_true(float(game.call("_timeout_urgency")) > 0.3, "75 %: Warnanteil steigt")
	for rim: MeshInstance3D in rims:
		assert_true(rim.visible, "75 %: Pad-Rand pulsiert (sichtbarer Timeout)")
	var rim_mat: StandardMaterial3D = stage.get("_rim_mat")
	assert_true(rim_mat.emission_energy_multiplier > 0.0, "Rand glüht")
	assert_false(bool(game.get("finished")), "kein Fail vor Ablauf des Fensters")
	game.free()


func test_says_fehlertext_anker_liegt_ueber_den_pads() -> void:
	var game := _mount_says()
	var stage: Node3D = game.get("_stage")
	var pads_at: Vector2 = stage.call("pads_screen")
	var gooby_at: Vector2 = stage.call("gooby_screen")
	assert_true(pads_at.is_finite(), "Pad-Anker ist projizierbar")
	# Gooby steht VOR dem roten Vorhang (oben), die Pads liegen auf dem
	# hellen Bühnenholz darunter — der Fehler-Text wandert dorthin.
	assert_true(pads_at.y > gooby_at.y, "Anker liegt unter Gooby, über den Pads")
	var vp := (game.call("get_viewport_rect") as Rect2).size
	assert_true(pads_at.y < vp.y, "Anker bleibt im Bild")
	game.free()


func test_says_rm_gate_an_der_konfetti_call_site() -> void:
	var game := _mount_says()
	var stage: Node3D = game.get("_stage")
	var confetti: GPUParticles3D = stage.get("_confetti")
	assert_false(confetti.emitting, "Konfetti startet still")
	stage.call("celebrate", true)
	assert_false(confetti.emitting, "Reduced Motion: kein Konfetti (Q2)")
	stage.call("celebrate", false)
	assert_true(confetti.emitting, "ohne Reduced Motion feiert das Konfetti")
	game.free()


func test_says_hud_ui_skalierung() -> void:
	var game := _mount_says()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var label: Label = game.get("_round_label")
	assert_eq(label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	assert_eq(label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_true(label.get_theme_constant("outline_size") >= 7, "Kontur bleibt (M7)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(label.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "HUD wächst")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui")
	game.free()


func test_says_hint_blendet_nach_sechs_sekunden_aus() -> void:
	var game := _mount_says()
	var hint: Label = game.get("_hint_label")
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Hinweis startet voll sichtbar")
	game.set("elapsed", 7.5)
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach 6 s + Fade ist der Hinweis weg")
	game.free()


func test_memory_intro_gatet_sim_merkfenster_und_eingabe() -> void:
	var game := _mount_memory()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.memoryMatch.intro"), "Ziel-Banner")
	var reveal_start := float(game.get("reveal_left"))
	assert_true(reveal_start > 0.0, "Merk-Fenster ist gefüllt")
	for _i in 3:
		game._process(0.4)
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim-Uhr wartet im Intro")
	assert_almost(float(game.get("reveal_left")), reveal_start, 1e-6, "Merk-Fenster wartet")
	# Eingabe-Gate isoliert prüfen: auch OHNE Merk-Fenster blockt das Intro.
	game.set("reveal_left", 0.0)
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = game.call("_card_center", 0)
	game._unhandled_input(tap)
	var cards: Array = game.get("cards")
	assert_eq(str((cards[0] as Dictionary)["state"]), "down", "Tap flippt im Intro nicht")
	game.set("_intro_left", 0.0)
	game._unhandled_input(tap)
	assert_eq(str((cards[0] as Dictionary)["state"]), "up", "nach dem Intro flippt der Tap")
	game.free()


func test_memory_intro_kamera_fliegt_in_die_spielpose() -> void:
	var game := _mount_memory()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	var consts := (stage.get_script() as GDScript).get_script_constant_map()
	var play_pos: Vector3 = consts["PLAY_CAM_POS"]
	game._process(0.1)
	assert_true(cam.position.y > play_pos.y + 0.5, "Intro: Kamera startet in der Totale")
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, play_pos.y, 1e-4, "Spielpose: exakt wie frame()")
	assert_almost(cam.rotation_degrees.x, float(consts["PLAY_CAM_TILT"]), 1e-4, "Tilt exakt")
	game.free()


func test_memory_countdown_anzeige_fuer_merk_und_spickfenster() -> void:
	var game := _mount_memory()
	var tune: Dictionary = game.get("tune")
	assert_almost(float(game.call("countdown_frac")), 1.0, 1e-6, "Merk-Fenster startet voll")
	game.set("reveal_left", 0.3 * float(tune["REVEAL_SEC"]))
	assert_almost(float(game.call("countdown_frac")), 0.3, 1e-6, "Balken folgt reveal_left")
	game.set("reveal_left", 0.0)
	game.set("peek_left", 0.5 * float(tune["PEEK_SEC"]))
	assert_almost(float(game.call("countdown_frac")), 0.5, 1e-6, "Balken folgt peek_left")
	game.set("peek_left", 0.0)
	assert_almost(float(game.call("countdown_frac")), 0.0, 1e-6, "ohne Fenster kein Balken")
	game.free()


func test_memory_rm_gates_an_den_burst_call_sites() -> void:
	var game := _mount_memory()
	var stage: Node3D = game.get("_stage")
	var stars: GPUParticles3D = stage.get("_star_burst")
	var poof: GPUParticles3D = stage.get("_poof_burst")
	stage.call("match_fx", 0, true)
	assert_false(stars.emitting, "Reduced Motion: kein Star-Burst (Q2)")
	stage.call("match_fx", 0, false)
	assert_true(stars.emitting, "ohne Reduced Motion feiert der Star-Burst")
	stage.call("miss_fx", 1, true)
	assert_false(poof.emitting, "Reduced Motion: kein Poof (Q2)")
	stage.call("miss_fx", 1, false)
	assert_true(poof.emitting, "ohne Reduced Motion pufft der Fehlgriff")
	game.free()


func test_memory_resolve_reicht_reduced_motion_an_die_stage() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount_memory()
	game.set("_intro_left", 0.0)
	var stage: Node3D = game.get("_stage")
	var stars: GPUParticles3D = stage.get("_star_burst")
	# Ein echtes Paar auflösen: gleiche Faces suchen und als gewählt setzen.
	var cards: Array = game.get("cards")
	var pair := Vector2i(-1, -1)
	for i in cards.size():
		for j in range(i + 1, cards.size()):
			if int((cards[i] as Dictionary)["face"]) == int((cards[j] as Dictionary)["face"]):
				pair = Vector2i(i, j)
				break
		if pair.x >= 0:
			break
	(cards[pair.x] as Dictionary)["state"] = "up"
	(cards[pair.y] as Dictionary)["state"] = "up"
	var picked: Array[int] = [pair.x, pair.y]
	game.set("picked", picked)
	game.call("_resolve_pick")
	assert_eq(str((cards[pair.x] as Dictionary)["state"]), "matched", "Paar zählt wie bisher")
	assert_false(stars.emitting, "Call-Site reicht Reduced Motion an match_fx durch")
	game.free()
	_set_reduced_motion(bool(previous))


func test_memory_hud_ui_skalierung() -> void:
	# W21/P5: Zeit/Paare laufen über den Kit-Chip (MgHudKit) — Position und
	# Schriftgrößen kommen aus dem EINEN Raster aller acht Spiele.
	var game := _mount_memory()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var label: Label = game.get("_time_label")
	assert_eq(label.position, Vector2(16.0, 10.0), "Phone: Kit-Chip-Anker")
	assert_eq(
		label.get_theme_font_size("font_size"),
		MgHudKit.font_px(MgHudKit.CHIP_VALUE_D, 1.0),
		"Phone: Chip-Wertgröße aus dem Kit"
	)
	var button: Button = game.get("_peek_button")
	assert_eq(button.custom_minimum_size, Vector2(140.0, 48.0), "Phone: Knopf wie Entwurf")
	game.call("apply_view", Vector2(834.0, 1194.0))
	var ui := 834.0 / 390.0
	assert_almost(float(game.get("_ui")), ui, 1e-4, "iPad: Kurzkante/390")
	assert_eq(
		label.get_theme_font_size("font_size"),
		MgHudKit.font_px(MgHudKit.CHIP_VALUE_D, ui),
		"HUD wächst mit dem Kit-Raster"
	)
	assert_almost(button.custom_minimum_size.x, 140.0 * ui, 0.01, "Spick-Knopf wächst (M9)")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	assert_almost(button.custom_minimum_size.y, 48.0, 0.01, "Touch-Floor 48 px bleibt")
	assert_true(button.size.y >= 48.0, "reale Knopfhöhe hält den Touch-Floor")
	game.free()


func test_memory_hint_blendet_nach_sechs_sekunden_aus() -> void:
	var game := _mount_memory()
	var hint: Label = game.get("_hint_label")
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Hinweis startet voll sichtbar")
	game.set("elapsed", 7.5)
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach 6 s + Fade ist der Hinweis weg")
	game.free()


func test_memory_brett_geschafft_wird_gold_banner() -> void:
	var game := _mount_memory()
	game.set("_intro_left", 0.0)
	game.call("_board_cleared")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.memoryMatch.cleared"), "Banner-Text")
	assert_true(bool(game.get("_banner_gold")), "Brett geschafft feiert in Gold (M7)")
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner steht")
	game.free()


func test_memory_card_at_ohne_tote_ternary() -> void:
	var game := _mount_memory()
	assert_eq(int(game.call("_card_at", Vector2(-999.0, -999.0))), -1, "daneben bleibt −1")
	var center: Vector2 = game.call("_card_center", 0)
	assert_eq(int(game.call("_card_at", center)), 0, "Kartenmitte trifft Karte 0")
	game.free()


func test_strings_de_en_paritaet_der_neuen_domain() -> void:
	var de := _flat_keys("res://strings/de/mg_says_memory.json")
	var en := _flat_keys("res://strings/en/mg_says_memory.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.goobySays.intro"), "says-Intro-Key vorhanden")
	assert_true(de.has("mg.memoryMatch.intro"), "memory-Intro-Key vorhanden")
	assert_true(de.has("mg.memoryMatch.oops"), "memory-Fehlgriff-Key vorhanden")
	assert_ne(
		I18nService.t("mg.goobySays.intro"),
		"mg.goobySays.intro",
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
