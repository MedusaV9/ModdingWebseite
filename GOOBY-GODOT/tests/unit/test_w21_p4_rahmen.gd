extends TestCase
## W21/P4 — Wächter der „EIN Produkt“-Welle des Minispiel-Rahmens:
## (1) BÜHNEN-VERTRAG: Hochkant-Spiel im Quer-Canvas → die Pillar-Flächen
##     sind eine GESTALTETE Bühne (Themen-Muster-Kulisse statt nacktem
##     Verlauf, Spielname-SCHILD + Gooby-Silhouette in den freien Bändern,
##     Paper-Rahmen) und das SPIELFELD bleibt unverzerrt (Web-Parität).
## (2) HOST-TIMER-CHIP: die Top-Bar trägt den einheitlichen Zeit-Chip —
##     Quelle ist die FRAMEWORK-Zeit des Geist-Rekorders („M:SS“),
##     Rundenwechsel setzt auf 0:00 zurück.
## (3) RESULTS-CHOREO: Zeilen fliegen gestaffelt in KARTENREIHENFOLGE ein,
##     die Sterne sind vom Stagger ausgenommen und STEMPELN an ihrem Beat,
##     der Score-Count-Up endet EXAKT beim Endstand; Reduced Motion stellt
##     alles sofort hin (keine Bewegung, Sterne enthüllt).

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const RESULTS_SCENE := "res://scripts/minigames/results.tscn"
const StageChrome := preload("res://scripts/minigames/host_stage_chrome.gd")
## Hochkant-Klassiker (Design 390×844) — im Quer-Canvas entsteht die Bühne.
const GAME_ID := "teaParty"
## Quer-Fenster der Host-Tests (Muster test_w18_mg_results_juice).
const FENSTER_QUER := Vector2i(1152, 648)

var _fenster_vorher := Vector2i.ZERO


## (1) Bühnen-Vertrag: Muster-Kulisse, Schild, Silhouette, Rahmen — und
## das Spielfeld bleibt im Hochkant-Seitenverhältnis (nie skaliert/verzerrt).
func test_buehne_pillar_traegt_muster_schild_und_silhouette() -> void:
	var host := await _mount_host_quer()
	var backdrop: ColorRect = host.get("_backdrop")
	assert_true(backdrop != null and backdrop.visible, "Pillar-Backdrop existiert")
	var mat := backdrop.material as ShaderMaterial
	assert_true(mat != null, "Kulisse ist der Themen-Shader-Pass (kein nackter ColorRect)")
	if mat != null:
		assert_true(
			mat.get_shader_parameter("muster") is Texture2D, "Muster-Textur des Spiel-Moods gesetzt"
		)
		assert_true(
			float(mat.get_shader_parameter("muster_opacity")) > 0.0,
			"Muster sichtbar — KEIN nackter Verlauf"
		)
	var frame: Panel = host.get("_stage_frame")
	assert_true(frame != null and frame.visible, "Paper-Rahmen hinter dem Spielfeld")
	var container := host.get("_viewport_container") as Control
	var feld := container.get_global_rect()
	var schild: Control = host.get("_stage_schild")
	assert_true(schild != null and schild.visible, "Spielname-Schild steht auf der Bühne")
	if schild != null and schild.visible:
		assert_false(
			feld.intersects(schild.get_global_rect()),
			"Schild liegt im Pillar-Band, nicht überm Feld"
		)
		var label := schild.get_node("SchildTitel") as Label
		assert_eq(label.text, I18nService.t("mg.teaParty.title"), "Schild trägt den Spielnamen")
	var gooby: Control = host.get("_stage_gooby")
	assert_true(gooby != null and gooby.visible, "Gooby-Silhouette wartet am Bühnenrand")
	if gooby != null and gooby.visible:
		assert_false(feld.intersects(gooby.get_global_rect()), "Silhouette bleibt neben dem Feld")
	# Web-Parität: Pillar-Behandlung ändert NIE die Feld-Proportionen.
	assert_almost(
		container.size.x / container.size.y,
		390.0 / 844.0,
		0.01,
		"Spielfeld bleibt unverzerrt (390×844-Design)"
	)
	await _unmount(host)


## (1b) Stimmung pur: Mood kommt aus dem EINEN Wallpaper-Themenblock und
## das Muster ist hinter dem Spiel bewusst gedämpft; Unbekanntes → Arcade.
func test_buehne_stimmung_folgt_dem_spiel_mood() -> void:
	var stimmung: Dictionary = StageChrome.stage_stimmung(GAME_ID)
	var kontext := str(stimmung["kontext"])
	assert_true(AcWallpaper.CONTEXTS.has(kontext), "Kontext aus AcWallpaper.CONTEXTS")
	var info: Dictionary = AcWallpaper.CONTEXTS[kontext]
	assert_almost(
		float(stimmung["opacity"]),
		float(info["opacity"]) * StageChrome.MUSTER_DAEMPFUNG,
		1e-6,
		"Muster hinter dem Spiel gedämpft (MUSTER_DAEMPFUNG)"
	)
	assert_eq(
		str(StageChrome.stage_stimmung("gibtEsNicht")["kontext"]),
		AcWallpaper.resolve_context("arcade"),
		"unbekanntes Spiel fällt auf die Arcade-Stimmung zurück"
	)


## (2) Host-Timer-Chip: „M:SS“ pur + im Host aus der Geist-Rekorder-Zeit.
func test_host_timer_chip_zeigt_framework_zeit() -> void:
	assert_eq(ZeitChip.format_zeit(0.0), "0:00", "0 s")
	assert_eq(ZeitChip.format_zeit(5.4), "0:05", "abrunden auf ganze Sekunden")
	assert_eq(ZeitChip.format_zeit(65.0), "1:05", "Minuten:Sekunden")
	assert_eq(ZeitChip.format_zeit(600.0), "10:00", "zweistellige Minuten")
	assert_eq(ZeitChip.format_zeit(-3.0), "0:00", "Negatives klemmt auf 0:00")
	var host := await _mount_host_quer()
	var chip: ZeitChip = host.get("_zeit_chip")
	assert_true(chip != null, "Zeit-Chip existiert")
	assert_eq(chip.get_parent(), host.get("_top_bar"), "Zeit-Chip lebt in der EINEN Top-Bar")
	var label := chip.find_child("ZeitLabel", true, false) as Label
	assert_true(label != null, "Chip trägt das M:SS-Label")
	# Framework-Zeit vorspulen (injizierte Zeit statt Echtzeit-Warterei):
	# der nächste _process-Tick reicht sie an den Chip durch.
	var geist: GeistRekord = host.get("_geist")
	assert_true(geist != null, "Geist-Rekorder läuft nach dem GO")
	geist.tick(65.0, 0)
	await wait_frames(2)
	assert_eq(
		label.text,
		ZeitChip.format_zeit(geist.zeit()),
		"Chip zeigt DIE Framework-Zeit des Rekorders"
	)
	assert_true(label.text.begins_with("1:"), "65 s vorgespult → Minute erreicht")
	chip.setze_zurueck()
	assert_eq(label.text, "0:00", "Rundenwechsel setzt auf 0:00 zurück")
	await _unmount(host)


## (3) Choreo: Stagger in Kartenreihenfolge, Sterne-Stempel am Beat,
## Count-Up endet EXAKT beim Breakdown-Score.
func test_results_choreo_stagger_stempel_und_count_up() -> void:
	var rm_vorher: Variant = _setze_reduced_motion(false)
	var host := await _mount_host_quer()
	var breakdowns: Array = []
	host.round_finished.connect(func(b: Dictionary) -> void: breakdowns.append(b))
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 7})
	var results := host.get("_results") as Control
	assert_true(await wait_until(func() -> bool: return results.visible, 8000), "Results da")
	# Kurz NACH dem Choreo-Start (deferred) sampeln: die erste Kartenzeile
	# federt bereits auf, die letzte wartet noch auf ihren Beat — und die
	# Sterne sind vom Stagger AUSGENOMMEN (sie stempeln später).
	await tree.create_timer(0.08).timeout
	var rows := results.get("_rows") as Control
	var reihen: Array[Control] = []
	for child in rows.get_children():
		if child is Control and child != results.get("_stars"):
			reihen.append(child)
	assert_true(reihen.size() >= 4, "Karte hat mehrere Choreo-Zeilen")
	var erste := reihen[0].modulate.a
	var letzte := reihen[reihen.size() - 1].modulate.a
	assert_true(erste > 0.0, "erste Kartenzeile federt zuerst auf (a=%.2f)" % erste)
	assert_true(
		erste > letzte,
		"Stagger läuft in Kartenreihenfolge (erste %.2f > letzte %.2f)" % [erste, letzte]
	)
	var stars := results.get("_stars") as Control
	assert_true(stars != null, "Sterne-Zeile existiert")
	assert_almost(stars.modulate.a, 0.0, 0.01, "Sterne warten auf ihren STEMPEL-Beat")
	# Choreo ausspielen lassen: alles steht, Sterne gestempelt + enthüllt,
	# Count-Up EXAKT beim Breakdown-Endstand gelandet.
	await tree.create_timer(1.8).timeout
	for reihe in reihen:
		assert_almost(reihe.modulate.a, 1.0, 0.01, "Zeile %s steht nach der Choreo" % reihe.name)
	assert_almost(stars.modulate.a, 1.0, 0.01, "Sterne sind gestempelt (sichtbar)")
	assert_true(int(stars.get("_earned")) >= 1, "Score > 0 enthüllt mindestens 1 Stern")
	assert_eq(breakdowns.size(), 1, "Runde lieferte genau einen Breakdown")
	var final_score := int((breakdowns[0] as Dictionary).get("score", -1))
	var score_label := _score_label(rows)
	assert_true(score_label != null, "Score-Zeile (HeadlineLabel) gefunden")
	assert_eq(
		score_label.text,
		I18nService.t("mg.results.score", {"score": final_score}),
		"Count-Up endet EXAKT beim Endstand %d" % final_score
	)
	_setze_reduced_motion(rm_vorher)
	await _unmount(host)


## (3b) RM-Pfad: Reduced Motion stellt die Karte SOFORT hin — alle Zeilen
## voll sichtbar, Sterne ohne Stempel-Warten enthüllt, Score exakt.
func test_results_choreo_rm_pfad_steht_sofort() -> void:
	var rm_vorher: Variant = _setze_reduced_motion(true)
	var screen: MinigameResults = (load(RESULTS_SCENE) as PackedScene).instantiate()
	tree.root.add_child(screen)
	await wait_frames(1)
	screen.show_results(
		{"score": 50, "best": 50, "newBest": true, "beatTarget": true},
		{"title_key": "mg.teaParty.title"}
	)
	# Choreo startet deferred — unter RM muss DANACH sofort alles stehen.
	await wait_frames(2)
	var rows := screen.get("_rows") as Control
	for child in rows.get_children():
		if child is Control:
			assert_almost(
				(child as Control).modulate.a, 1.0, 0.01, "RM: %s steht sofort" % child.name
			)
	var stars := screen.get("_stars") as Control
	assert_eq(int(stars.get("_earned")), 3, "RM: alle 3 Sterne sofort enthüllt (ohne Stempel)")
	var score_label := _score_label(rows)
	assert_eq(
		score_label.text,
		I18nService.t("mg.results.score", {"score": 50}),
		"RM: Score steht sofort exakt (kein Count-Up)"
	)
	_setze_reduced_motion(rm_vorher)
	screen.free()
	await wait_frames(1)


## ── Helfer (Muster test_w18_mg_results_juice) ──────────────────────────────


func _mount_host_quer() -> MinigameHost:
	_refill_energy()
	if _fenster_vorher == Vector2i.ZERO:
		_fenster_vorher = tree.root.size
	DisplayServer.window_set_size(FENSTER_QUER)
	tree.root.size = FENSTER_QUER
	await wait_frames(2)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.quick_go_sec = 0.05
	host.receive_params({"game_id": GAME_ID, "difficulty": "normal", "seed": 2121})
	tree.root.add_child(host)
	var aktiv := await wait_until(
		func() -> bool:
			var game: MinigameBase = host.get("_game")
			return game != null and is_instance_valid(game) and game.is_active(),
		8000
	)
	assert_true(aktiv, "Host erreicht das laufende Spiel")
	return host


func _unmount(host: MinigameHost) -> void:
	host.queue_free()
	if _fenster_vorher != Vector2i.ZERO:
		tree.root.size = _fenster_vorher
		DisplayServer.window_set_size(_fenster_vorher)
		_fenster_vorher = Vector2i.ZERO
	await wait_frames(2)


## Score-Zeile der Karte: das EINE HeadlineLabel unter den Rows-Kindern.
func _score_label(rows: Control) -> Label:
	for child in rows.get_children():
		if child is Label and (child as Label).theme_type_variation == &"HeadlineLabel":
			return child
	return null


## Reduced-Motion setzen und den vorigen Wert liefern (Restore-Muster).
## Wie der Settings-Screen: AppSettings UND UiTheme im Gleichschritt —
## results._reduced_motion() liest ersteres, MotionKit.reduced() letzteres.
func _setze_reduced_motion(wert: Variant) -> Variant:
	var settings := tree.root.get_node_or_null("/root/AppSettings")
	if settings == null:
		return null
	var vorher: Variant = settings.get_setting("reduced_motion", false)
	settings.set_setting("reduced_motion", bool(wert))
	var theme_svc := tree.root.get_node_or_null("/root/UiTheme")
	if theme_svc != null and "reduced_motion" in theme_svc:
		theme_svc.reduced_motion = bool(wert)
	return vorher


func _refill_energy() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("update"):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and (gooby as Dictionary).get("stats") is Dictionary:
				((gooby as Dictionary)["stats"] as Dictionary)["energy"] = 100.0
	)
