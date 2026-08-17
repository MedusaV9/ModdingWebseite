extends TestCase
## W18 Playtest Welle H (Report Agent 3, Arcade/Minispiel-Rahmen) — Wächter
## für die drei Rahmen-Befunde:
## - B1 (BLOCKER): Die Results-Karte muss nach show_results() in JEDER Runde
##   mittig im Screen liegen. Vorher blähte der queue_free-Umbau der Rows den
##   FULL_RECT-verankerten _center transient auf (612→1914 px im Playtest),
##   Godot schrumpfte nie zurück und ab Runde 2 lag die Karte samt Knöpfen
##   off-screen — Soft-Lock im „Nochmal“-Kernpfad.
## - B2 (HOCH): Das Combo-„×N“-Label (JuiceKit.show_combo) darf Rundenende,
##   Results, Pause-Modal und Folgerunde nicht überleben — der Host räumt
##   jedes Juice-Overlay deterministisch ab (clear_overlays) und versteckt
##   die Juice-Ebene unterm Pause-Modal.
## - B7 (POLISH): Die Host-Top-Bar spoilert den Score-Count-Up nicht mehr —
##   sie verschwindet mit dem Results-Screen und kehrt beim Neustart zurück.

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const GAME_ID := "carrotCatch"


func test_b1_results_karte_bleibt_ueber_zwei_runden_zentriert() -> void:
	var host := _mount_host()
	assert_true(await _wait_active(host), "Erststart erreicht das Spiel.")
	await _runde_beenden(host, 3)
	await _warte_results_ruhe(host)
	_pruefe_zentriert(host, "Runde 1")
	# Testbedingung des Wächters: die DOPPELTE Karten-Minhöhe muss den Screen
	# übersteigen, sonst kann ein queue_free-Umbau gar nicht auffallen.
	var panel := _results_teil(host, "_panel")
	var results := host.get("_results") as Control
	assert_true(
		panel.get_combined_minimum_size().y * 2.0 > results.size.y,
		(
			"Testbedingung: 2× Karten-Minhöhe (%.0f) übersteigt den Screen (%.0f)."
			% [panel.get_combined_minimum_size().y * 2.0, results.size.y]
		)
	)
	_refill_energy()
	host._on_again_pressed()
	assert_true(await _wait_active(host), "„Nochmal“ erreicht Runde 2.")
	await _runde_beenden(host, 4)
	await _warte_results_ruhe(host)
	_pruefe_zentriert(host, "Runde 2")
	await _unmount(host)


func test_b2_combo_label_ueberlebt_rundenende_und_neustart_nicht() -> void:
	var host := _mount_host()
	assert_true(await _wait_active(host), "Erststart erreicht das Spiel.")
	var layer := host.juice.float_text_parent as Control
	host.juice.show_combo(3)
	assert_true(_hat_combo_label(layer), "Combo-„×3“ steht während der Runde im JuiceLayer.")
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 5})
	# clear_overlays wirkt SYNCHRON im Rundenende — noch im selben Frame ist
	# der Layer leer (der End-Moment feiert erst 0,12 s später mit frischen
	# Effekten, das ist gewollt).
	assert_eq(layer.get_child_count(), 0, "Rundenende räumt JEDES Juice-Overlay ab.")
	assert_true(host.juice.get("_combo_label") == null, "Kein Combo-Label-Zombie im Kit.")
	var results := host.get("_results") as Control
	assert_true(await wait_until(func() -> bool: return results.visible, 8000), "Results da.")
	assert_false(_hat_combo_label(layer), "Kein „×N“ über „Runde vorbei!“.")
	_refill_energy()
	host._on_again_pressed()
	assert_false(_hat_combo_label(layer), "Kein „×N“ schwebt in die Folgerunde.")
	assert_true(host.juice.get("_combo_label") == null, "Neustart lässt keinen Combo-Rest.")
	assert_true(layer.visible, "JuiceLayer ist für die Folgerunde wieder sichtbar.")
	await _unmount(host)


func test_b2_pause_versteckt_die_juice_ebene() -> void:
	var host := _mount_host()
	host.resume_step_sec = 0.0
	assert_true(await _wait_active(host), "Erststart erreicht das Spiel.")
	var layer := host.get("_float_layer") as Control
	host.juice.show_combo(4)
	assert_true(_hat_combo_label(layer), "Combo-„×4“ steht während der Runde im JuiceLayer.")
	host._on_pause_pressed()
	assert_false(layer.visible, "Pause: Juice-Ebene liegt NICHT über dem Modal („P×2e“).")
	host._on_resume_pressed()
	var wieder := await wait_until(func() -> bool: return layer.visible, 5000)
	assert_true(wieder, "Weiterspielen blendet die Juice-Ebene wieder ein.")
	assert_true(_hat_combo_label(layer), "Laufende Combo überlebt die Pause (Runde läuft ja).")
	await _unmount(host)


func test_b7_top_bar_spoilert_den_count_up_nicht() -> void:
	var host := _mount_host()
	assert_true(await _wait_active(host), "Erststart erreicht das Spiel.")
	var top_bar := host.get("_top_bar") as Control
	assert_true(top_bar.visible, "Top-Bar ist während der Runde sichtbar.")
	await _runde_beenden(host, 7)
	assert_false(top_bar.visible, "Results eingeblendet → Top-Bar (HUD-Spoiler) versteckt.")
	_refill_energy()
	host._on_again_pressed()
	assert_true(top_bar.visible, "Neustart bringt die Top-Bar zurück.")
	await _unmount(host)


func test_results_aktionen_haben_controller_fokus_und_pfeilnavigation() -> void:
	var results := MinigameResults.new()
	tree.root.add_child(results)
	results.show_results({"score": 12, "best": 12, "coins": 3, "xp": 4}, {})
	await wait_frames(3)
	var actions: Array[Button] = [results._again, results._back, results._home]
	assert_eq(tree.root.gui_get_focus_owner(), results._again, "Nochmal erhält Erstfokus")
	for action in actions:
		assert_eq(action.focus_mode, Control.FOCUS_ALL, "%s fokussierbar" % action.name)
		assert_false(action.focus_next.is_empty(), "%s hat Tab-Nachfolger" % action.name)
		assert_false(action.focus_neighbor_left.is_empty(), "%s hat linken Nachbarn" % action.name)
		assert_false(
			action.focus_neighbor_right.is_empty(), "%s hat rechten Nachbarn" % action.name
		)
	results.queue_free()
	await wait_frames(2)


## ── Helfer (Muster test_ef3_quick_retry / test_w17_host_juice) ─────────────


func _mount_host() -> MinigameHost:
	_refill_energy()
	# Landschafts-Fenster mit 720er-Canvas-Höhe: eine einzelne Karte passt,
	# die verdoppelte (Umbau-Frame) nicht — genau die B1-Falle.
	tree.root.size = Vector2i(1152, 648)
	tree.root.size_changed.emit()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.quick_go_sec = 0.05
	host.receive_params({"game_id": GAME_ID, "difficulty": "normal", "seed": 1818})
	tree.root.add_child(host)
	return host


func _unmount(host: MinigameHost) -> void:
	host.queue_free()
	await wait_frames(2)


func _wait_active(host: MinigameHost) -> bool:
	return await wait_until(
		func() -> bool:
			var game: MinigameBase = host.get("_game")
			return game != null and is_instance_valid(game) and game.is_active(),
		8000
	)


## Runde über den sanktionierten Spiel-Kontext beenden und auf den
## (real 0,9 s verzögerten) Results-Screen warten.
func _runde_beenden(host: MinigameHost, score: int) -> void:
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": score})
	var results := host.get("_results") as Control
	var da := await wait_until(func() -> bool: return results.visible, 8000)
	assert_true(da, "Results-Screen erscheint nach dem Rundenende.")


## Wartet, bis der Einblende-Pop der Karte ausgefedert ist (Rect-Messungen
## ohne transiente Skalierung) plus Frames für deferred Frees/Min-Flush.
## Erst REAL warten: der Pop-Tween startet erst im Folgeframe — ein
## sofortiger scale==1-Check wäre ein Scheinerfolg mitten in der Animation.
func _warte_results_ruhe(host: MinigameHost) -> void:
	await tree.create_timer(0.8).timeout
	var panel := _results_teil(host, "_panel")
	await wait_until(func() -> bool: return panel.scale.is_equal_approx(Vector2.ONE), 5000)
	await wait_frames(5)


func _results_teil(host: MinigameHost, feld: String) -> Control:
	var results := host.get("_results") as Control
	return results.get(feld) as Control


## Der B1-Kern: _center füllt exakt den Screen (keine Phantom-Aufblähung)
## und die Karte samt Knopfreihe liegt mittig KOMPLETT im Sichtbereich.
func _pruefe_zentriert(host: MinigameHost, tag: String) -> void:
	var results := host.get("_results") as Control
	var center := _results_teil(host, "_center")
	var panel := _results_teil(host, "_panel")
	var results_rect := results.get_global_rect()
	var center_rect := center.get_global_rect()
	assert_almost(
		center_rect.size.y,
		results_rect.size.y,
		1.0,
		"%s: _center bleibt so hoch wie der Screen (statt 612→1914-Aufblähung)." % tag
	)
	var panel_rect := panel.get_global_rect()
	assert_almost(
		panel_rect.get_center().y,
		results_rect.get_center().y,
		2.0,
		"%s: Karte ist vertikal mittig." % tag
	)
	assert_true(
		results_rect.encloses(panel_rect),
		(
			"%s: Karte (samt Nochmal/Zur Arcade/Nach Hause) komplett im Screen (Karte %s, Screen %s)."
			% [tag, panel_rect, results_rect]
		)
	)


## Sucht ein Combo-Label (Text beginnt mit ×) im Layer (Muster test_feel_juice).
func _hat_combo_label(layer: Control) -> bool:
	for child in layer.get_children():
		if child is Label and (child as Label).text.begins_with("×"):
			return true
	return false


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
