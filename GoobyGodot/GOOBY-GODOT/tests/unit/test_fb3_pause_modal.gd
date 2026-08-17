extends TestCase
## FB3 — Pause-Modal im MinigameHost (P0 „Pause vereinnahmt die ganze
## Fläche / pausiert nicht wirklich“): über 6 verschiedene ECHTE Spiele
## (gemeinsamer Host-Pfad = gilt für alle 30+):
## - Pause öffnet ein KOMPAKTES, MITTIGES Modal (nie Vollfläche),
## - das Spiel pausiert WIRKLICH (SubViewport-Ast tickt nicht mehr),
## - Fortsetzen läuft über den 3-2-1-Countdown und gibt sauber frei,
## - Neustart/Beenden/Ton/Hilfe funktionieren.

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
## 6 Spiele quer durch die Batches (Hoch- und Querformat).
const GAME_IDS: Array[String] = [
	"teaParty", "carrotCatch", "bubblePop", "memoryMatch", "pipeFlow", "bunnyHop"
]


## Jede Runde kostet Energie (§C6) — ohne Refill verweigert der Host nach
## den Läufen anderer Tests den Start („Gooby erschöpft“).
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


func _mount_host(game_id: String) -> MinigameHost:
	_refill_energy()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.resume_step_sec = 0.0
	host.receive_params({"game_id": game_id, "difficulty": "normal", "seed": 4242})
	tree.root.add_child(host)
	return host


func _wait_go(host: MinigameHost) -> bool:
	return await wait_until(
		func() -> bool:
			var btn: Button = host.get("_pause_button")
			return btn != null and not btn.disabled,
		8000
	)


func _unmount(host: MinigameHost) -> void:
	host.queue_free()
	await wait_frames(2)


func test_pause_modal_in_sechs_spielen_kompakt_und_wirklich_pausiert() -> void:
	for game_id in GAME_IDS:
		var host := _mount_host(game_id)
		var go := await _wait_go(host)
		assert_true(go, "%s: GO erreicht" % game_id)
		if not go:
			await _unmount(host)
			continue
		var modal: MinigamePauseModal = host.get("_pause_modal")
		assert_true(modal != null, "%s: Modal existiert" % game_id)
		assert_false(modal.is_open(), "%s: Modal vor Pause zu" % game_id)
		host._on_pause_pressed()
		await wait_frames(2)
		assert_true(modal.is_open(), "%s: Modal offen" % game_id)
		var game: MinigameBase = host.get("_game")
		assert_true(game.game_paused, "%s: game_paused gesetzt" % game_id)
		var container: SubViewportContainer = host.get("_viewport_container")
		assert_eq(
			container.process_mode,
			Node.PROCESS_MODE_DISABLED,
			"%s: SubViewport-Ast WIRKLICH eingefroren" % game_id
		)
		# Kompakt + mittig: Karte ≤ 62 % der Canvas-Breite, Zentrum ≈ Mitte.
		var card: Control = modal.get("_card")
		var canvas := Vector2(host.get_viewport().get_visible_rect().size)
		var rect := card.get_global_rect()
		assert_true(
			rect.size.x <= canvas.x * 0.62 + 1.0,
			"%s: Karte kompakt (%.0f px von %.0f)" % [game_id, rect.size.x, canvas.x]
		)
		assert_true(
			rect.size.y <= canvas.y * 0.9,
			"%s: Karte nie Vollhöhe (%.0f von %.0f)" % [game_id, rect.size.y, canvas.y]
		)
		assert_true(
			rect.get_center().distance_to(canvas / 2.0) <= canvas.y * 0.08,
			"%s: Karte mittig (Zentrum %s)" % [game_id, rect.get_center()]
		)
		# Fortsetzen: Modal zu → 3-2-1 → Spiel läuft wieder.
		modal._on_resume_pressed()
		assert_false(modal.is_open(), "%s: Modal nach Fortsetzen zu" % game_id)
		var resumed := await wait_until(
			func() -> bool:
				var btn: Button = host.get("_pause_button")
				return not btn.disabled and not game.game_paused,
			5000
		)
		assert_true(resumed, "%s: Countdown gibt das Spiel frei" % game_id)
		assert_eq(
			container.process_mode,
			Node.PROCESS_MODE_INHERIT,
			"%s: SubViewport-Ast läuft wieder" % game_id
		)
		await _unmount(host)


func test_resume_countdown_zaehlt_drei_zwei_eins() -> void:
	var host := _mount_host("teaParty")
	host.resume_step_sec = 0.05
	var go := await _wait_go(host)
	assert_true(go, "GO erreicht")
	host._on_pause_pressed()
	await wait_frames(2)
	var modal: MinigamePauseModal = host.get("_pause_modal")
	modal._on_resume_pressed()
	await wait_frames(2)
	var label: Label = host.get("_countdown_label")
	assert_true(label.visible, "Countdown-Ziffer sichtbar")
	assert_eq(label.text, "3", "Countdown startet bei 3")
	var game: MinigameBase = host.get("_game")
	assert_true(game.game_paused, "Spiel bleibt WÄHREND des Countdowns pausiert")
	var done := await wait_until(func() -> bool: return not game.game_paused, 5000)
	assert_true(done, "nach 3-2-1 läuft das Spiel weiter")
	assert_false(label.visible, "Countdown-Ziffer wieder weg")
	await _unmount(host)


func test_neustart_aus_der_pause_startet_frische_runde() -> void:
	var host := _mount_host("carrotCatch")
	var go := await _wait_go(host)
	assert_true(go, "GO erreicht")
	var first_game: MinigameBase = host.get("_game")
	host._on_pause_pressed()
	await wait_frames(2)
	var modal: MinigamePauseModal = host.get("_pause_modal")
	modal._on_restart_pressed()
	await wait_frames(2)
	assert_false(modal.is_open(), "Modal nach Neustart zu")
	var restarted := await _wait_go(host)
	assert_true(restarted, "neue Runde erreicht GO")
	var second_game: MinigameBase = host.get("_game")
	assert_true(second_game != null and second_game != first_game, "frisches Spiel gemountet")
	assert_false(second_game.game_paused, "frische Runde läuft")
	var container: SubViewportContainer = host.get("_viewport_container")
	assert_eq(container.process_mode, Node.PROCESS_MODE_INHERIT, "Freeze gelöst")
	await _unmount(host)


func test_beenden_aus_der_pause_verlaesst_zum_arcade() -> void:
	var host := _mount_host("bubblePop")
	var go := await _wait_go(host)
	assert_true(go, "GO erreicht")
	host._on_pause_pressed()
	await wait_frames(2)
	var exits: Array = []
	host.exit_requested.connect(
		func(target: StringName, _params: Dictionary) -> void: exits.append(target)
	)
	var modal: MinigamePauseModal = host.get("_pause_modal")
	modal._on_quit_pressed()
	await wait_frames(2)
	assert_eq(exits, [&"arcade"], "Beenden feuert exit_requested → arcade")
	assert_false(modal.is_open(), "Modal zu")
	await _unmount(host)


func test_hilfe_zeigt_spielhinweis_und_backdrop_setzt_fort() -> void:
	var host := _mount_host("teaParty")
	var go := await _wait_go(host)
	assert_true(go, "GO erreicht")
	host._on_pause_pressed()
	await wait_frames(2)
	var modal: MinigamePauseModal = host.get("_pause_modal")
	var help: Button = modal.get("_help")
	help.button_pressed = true
	modal._on_help_pressed()
	await wait_frames(1)
	var hint: Label = modal.get("_hint_label")
	assert_true(hint.visible, "Hilfe-Text sichtbar")
	assert_eq(hint.text, I18nService.t("mg.teaParty.hint"), "Hilfe = Spiel-Hinweis")
	# Ton-Knopf existiert und crasht ohne AppSettings-Autoload nicht.
	var sound: Button = modal.get("_sound")
	assert_true(sound != null, "Ton-Knopf existiert")
	modal._on_sound_pressed()
	# Backdrop-Tap (oberstes Panel) = Fortsetzen.
	var game: MinigameBase = host.get("_game")
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	modal._on_backdrop_input(press)
	assert_false(modal.is_open(), "Backdrop-Tap schließt das Modal")
	var resumed := await wait_until(func() -> bool: return not game.game_paused, 5000)
	assert_true(resumed, "Backdrop-Tap setzt fort (3-2-1)")
	await _unmount(host)
