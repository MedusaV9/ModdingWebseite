extends SceneTree
## RW-5-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte des Wettbewerbs-DLC — vier Disziplin-Läufe (Springen,
## Dressur, Rennen mit Bot-Feld, Trail), den Geisterlauf im Tonnenrennen
## und den echten Turnier-Flow (Liga-Menü → Einweisung → Endstand →
## Siegerehrung mit Podium + Konfetti). Druckt je 3D-Bild die Draw-Calls
## (Budget ≤ 350). Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/rw5_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW5"
const SETTLE := 30
const GROESSE := Vector2i(1280, 720)

const Ghost := preload("res://scripts/ranch/comp/ghost/comp_ghost.gd")
const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")

var _balance: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(GROESSE)
	root.size = GROESSE
	# Auto-Qualitätsbremse aus: unter llvmpipe/xvfb würde sie sonst mitten
	# im Bild den "Qualität angepasst"-Toast einblenden.
	var quality := root.get_node_or_null("Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	_balance = RanchCompKatalog.load_balance()
	await _disziplin_shot("springen", "holz", 3, 5.5, "disziplin_springen_lauf.png")
	await _disziplin_shot("dressur", "holz", 1, 7.0, "disziplin_dressur_figuren.png")
	await _disziplin_shot("rennen", "silber", 3, 3.0, "disziplin_rennen_botfeld.png")
	await _disziplin_shot("trail", "holz", 1, 7.0, "disziplin_trail_stationen.png")
	await _geist_shot()
	await _turnier_flow_shots()
	print("Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


## Ein Disziplin-Lauf: bauen, Gangart hochschalten, Autopilot reiten
## lassen (lenkt aufs Richter-Ziel, springt vor Hindernissen), Bild.
func _disziplin_shot(
	disziplin: String, klasse: String, gaenge: int, bis_zeit_s: float, datei: String
) -> void:
	var cfg := {
		"disziplin": disziplin,
		"klasse": klasse,
		"seed": 4711,
		"balance": _balance,
		"zuschauer": 12,
	}
	if disziplin == "rennen":
		cfg["bots"] = RanchCompTurnier.bots_simulieren(_balance, disziplin, klasse, 4711)
	var lauf := await _lauf_bauen(cfg)
	for _i in gaenge:
		lauf.controller.gait_up()
	await _autopilot(lauf, bis_zeit_s, disziplin == "springen")
	await _shot(datei)
	_lauf_weg(lauf)


## Tonnenrennen mit vorgefertigtem Bestlauf: der transparente Geist reitet
## dem Spieler sichtbar voraus (Spieler bleibt im Trab dahinter).
func _geist_shot() -> void:
	var cfg := {
		"disziplin": "tonnen",
		"klasse": "holz",
		"seed": 4711,
		"balance": _balance,
		"zuschauer": 10,
		"geist_b64": _fake_geist_b64(),
	}
	var lauf := await _lauf_bauen(cfg)
	lauf.controller.gait_up()
	lauf.controller.gait_up()
	await _autopilot(lauf, 3.2, false)
	await _shot("geisterlauf_tonnen_sichtbar.png")
	_lauf_weg(lauf)


## Der ECHTE Turnier-Flow durchs Minigame: Liga-Menü, deutsche Einweisung,
## Endstand-Panel nach dem Lauf und die Siegerehrung (Podium + Konfetti).
func _turnier_flow_shots() -> void:
	var scene: PackedScene = load("res://scripts/minigames/games/ranch_turnier/turnier_game.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	var overlay := Control.new()
	overlay.size = Vector2(GROESSE)
	root.add_child(overlay)
	var juice := JuiceKit.new()
	juice.float_text_parent = overlay
	root.add_child(juice)
	var ctx := MinigameCtx.new()
	ctx.game_id = "ranchTurnier"
	ctx.run_seed = 7
	ctx.orientation = "landscape"
	ctx.juice = juice
	game.setup(ctx)
	game.apply_view(Vector2(GROESSE))
	game.start()
	await _settle(SETTLE)
	await _shot("liga_uebersicht_menue.png")
	game._zeige_einweisung("springen")
	game.apply_view(Vector2(GROESSE))
	await _settle(SETTLE)
	await _shot("einweisung_springen.png")
	game._starte_lauf()
	await _settle(5)
	# Spielerlauf abkürzen: starkes Ergebnis direkt einspeisen — ab hier
	# läuft der echte Ergebnis-/Zeremonie-Pfad des Spiels.
	game._on_lauf_fertig({"wert": 1200.0, "zeit_s": 58.0, "geist_b64": ""})
	game.apply_view(Vector2(GROESSE))
	await _settle(SETTLE)
	await _shot("ergebnis_endstand.png")
	var platz: int = RanchCompTurnier.spieler_platz(game._stand)
	game._nach_ergebnis(platz)
	game.apply_view(Vector2(GROESSE))
	# Früh abdrücken: das Konfetti (1,7 s Lebenszeit) soll mit aufs Bild.
	await _settle(6)
	await _shot("siegerehrung_podium.png")
	for node: Node in [juice, overlay, game]:
		root.remove_child(node)
		node.free()


## ------------------------------------------------------------ Helfer


func _lauf_bauen(cfg: Dictionary) -> RcompLauf:
	var lauf := RcompLauf.new()
	root.add_child(lauf)
	lauf.baue(cfg)
	lauf.apply_size(Vector2(GROESSE))
	var hud := RcompHud.new()
	hud.name = "Hud"
	hud.lauf = lauf
	root.add_child(hud)
	lauf.starte()
	await _settle(2)
	return lauf


func _lauf_weg(lauf: RcompLauf) -> void:
	var hud := root.get_node_or_null("Hud")
	if hud != null:
		root.remove_child(hud)
		hud.free()
	root.remove_child(lauf)
	lauf.free()


## Mini-Autopilot fürs Bildermachen: lenkt jeden Frame aufs aktuelle
## Richter-Ziel (Rennen: der Oval-Tangente nach) und springt kurz vor
## Hindernissen — bis die LAUF-Zeit (Spielzeit, nicht Frames) erreicht ist.
func _autopilot(lauf: RcompLauf, bis_zeit_s: float, springen: bool) -> void:
	var controller := lauf.controller
	controller.keyboard_input = false
	var strecke := 0.0
	var wache := 0
	while lauf.zeit < bis_zeit_s and wache < 900:
		wache += 1
		var ziel_punkt := Vector3.ZERO
		var hat_ziel := false
		if lauf.disziplin == "rennen":
			strecke += controller.tempo * root.get_process_delta_time()
			ziel_punkt = Kurs.rennen_punkt(strecke + 6.0)
			hat_ziel = true
		else:
			var ziel := lauf._marker_ziel()
			if not ziel.is_empty():
				ziel_punkt = ziel["pos"]
				hat_ziel = true
		if hat_ziel:
			var d := ziel_punkt - controller.position
			var wunsch := atan2(-d.x, -d.z)
			var diff := wrapf(wunsch - controller.heading, -PI, PI)
			controller.steer_input(clampf(-diff * 2.2, -1.0, 1.0))
			if springen and Vector2(d.x, d.z).length() < 3.4:
				controller.jump()
		await process_frame


## Synthetischer Bestlauf: 9 s Galopp vom Start Richtung erster Tonne und
## weiter zur zweiten (RanchCompGhost-Format, wie eine echte Aufnahme).
func _fake_geist_b64() -> String:
	var start: Vector3 = Kurs.TONNEN_START
	var rec := Ghost.neuer_recorder("tonnen", start)
	var ziele: Array[Vector3] = [Kurs.TONNEN_POSITIONEN[0], Kurs.TONNEN_POSITIONEN[1]]
	var pos := start
	var ziel_idx := 0
	for _i in 90:
		var ziel: Vector3 = ziele[ziel_idx]
		var richtung := (ziel - pos).normalized()
		pos += richtung * 5.2 * 0.1
		if pos.distance_to(ziel) < 1.6 and ziel_idx < ziele.size() - 1:
			ziel_idx += 1
		Ghost.tick(rec, 0.1, pos, atan2(-richtung.x, -richtung.z), "galopp", false)
	return Ghost.to_b64(rec)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s (draw_calls=%d)" % [file, RcompLauf.draw_calls()])
