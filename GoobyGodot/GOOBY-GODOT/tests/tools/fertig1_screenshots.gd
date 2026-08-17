extends SceneTree
## FERTIG-1-Screenshot-Tool (KEIN Test): rendert die Review-Artefakte für
## das Arcade-Modifier-System (Kachel-Badge, Pregame-Banner, Wirkung im
## Ergebnis), die Abschluss-Karte im Profil (Rundes Ende), das Post-
## Tagespaket (Ex-„bald“-Platzhalter) und den Galerie-Export. Aufruf:
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method \
##     gl_compatibility --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/fertig1_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FERTIG1"
const SETTLE_FRAMES := 16
const NOW_MS := 1_750_000_000_000


class FriendsStub:
	var friends := [
		{"friendCode": "GOOBY-AAA", "name": "Mira", "goobyName": "Bommel", "online": true},
	]


class NetStub:
	var friends := FriendsStub.new()


var _gs: Node
var _net := NetStub.new()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	# WICHTIG: --script lädt die Projekt-Autoloads mit — /root/GameState
	# existiert also schon (ein zweiter gleichnamiger Node würde umbenannt
	# und der Arcade-Badge-Lookup fände den falschen). Deshalb wird der
	# AUTOLOAD gepinnt, auf einen Temp-Save umgebogen und belebt.
	_gs = root.get_node_or_null("/root/GameState")
	if _gs == null:
		push_error("GameState-Autoload fehlt")
		quit(1)
		return
	_prepare_gs()
	await _shot_arcade_badge()
	await _shot_pregame_banner()
	await _shot_results_wirkung()
	await _shot_profil_abschluss()
	await _shot_post_paket()
	await _shot_galerie_export()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


## Belebter Spielstand: Level 12 (alle 6 Modifier-Typen frei), Zähler,
## Sticker und Plays, damit Profil-/Abschluss-Karte echte Quoten zeigen.
func _prepare_gs() -> void:
	var dir := "user://fertig1_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_gs.clock.pin(NOW_MS)
	_gs.clock.set_utc_offset_minutes(0)
	_gs.initialize(dir + "/save_v5.json")
	_gs.update(
		func(state: Dictionary) -> void:
			state["meta"]["goobyNickname"] = "Gooby"
			state["meta"]["createdAt"] = NOW_MS - 90 * 86_400_000
			state["progression"]["level"] = 12
			state["progression"]["xp"] = 40
			state["economy"]["coins"] = 610
			state["economy"]["coinsEarned"] = 1220
			state["gooby"]["stats"]["energy"] = 100.0
			var counters: Dictionary = state["achievements"]["counters"]
			counters["feeds"] = 40
			counters["washes"] = 22
			counters["tickles"] = 100
			counters["photosTaken"] = 9
			counters["questsDone"] = 12
			var sticker_ids := StickerCatalog.all().slice(0, 14)
			for def: Dictionary in sticker_ids:
				state["stickers"]["unlocked"][str(def.get("id", ""))] = NOW_MS
			state["minigames"]["plays"] = {
				"teaParty": 6, "carrotCatch": 3, "bubblePop": 2, "memoryMatch": 1
			}
			state["minigames"]["legacy"]["best"] = {"teaParty": 118, "carrotCatch": 74}
	)
	# Erfolge über den echten Service stempeln (Produktiv-Pfad).
	var service := AchievementsService.new()
	root.add_child(service)
	service.attach(_gs)
	service.free()


func _force(game_id: String, type_id: String) -> void:
	var now := int(_gs.clock.now_ms())
	_gs.update(
		func(state: Dictionary) -> void:
			ModifierEngine.force_event(state, {"gameId": game_id, "type": type_id}, now)
	)


## Arcade-Grid: die Ziel-Kachel (teaParty) trägt das Bonus-Badge
## „Doppel-Gold · 45:00“, alle anderen Kacheln bleiben unverändert.
func _shot_arcade_badge() -> void:
	_resize(Vector2i(720, 1560))
	_force("teaParty", "doppelGold")
	var screen: Control = (
		(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
	)
	screen.set("auto_navigate", false)
	root.add_child(screen)
	await _snap("arcade_modifier_badge.png")
	screen.queue_free()
	await process_frame


## Pregame des Event-Spiels: Banner mit Name, Beschreibung und Restzeit
## VOR dem Start (die geforderte sichtbare Anzeige).
func _shot_pregame_banner() -> void:
	_resize(Vector2i(720, 1160))
	var pregame: MinigamePregame = (
		(load("res://scripts/minigames/pregame.tscn") as PackedScene).instantiate()
	)
	pregame.auto_navigate = false
	pregame.state_node = _gs
	pregame.receive_params({"game_id": "teaParty"})
	root.add_child(pregame)
	await _snap("pregame_modifier_banner.png")
	pregame.queue_free()
	await process_frame


## Ergebnis-Screen nach einer echten Award-Buchung MIT konsumiertem
## Doppel-Gold: Aktiv-Zeile + Bonus-Coins-Zeile sichtbar.
func _shot_results_wirkung() -> void:
	_resize(Vector2i(720, 1160))
	var meta := MinigameRegistry.get_game("teaParty")
	var today := str(_gs.clock.local_day())
	var now := int(_gs.clock.now_ms())
	var box := {"b": {}}
	_gs.update(
		func(state: Dictionary) -> void:
			var res := ModifierEngine.consume(state, "teaParty", now)
			var snap: Dictionary = res.get("modifier", {})
			var params := ModifierEngine.launch_params(snap)
			box["b"] = MinigameAward.award(state, meta, 132, "normal", today, [], params)
	)
	var results := MinigameResults.new()
	root.add_child(results)
	results.show_results(box["b"] as Dictionary, meta)
	await _snap("results_modifier_wirkung.png")
	results.queue_free()
	await process_frame


## Profil mit der neuen Abschluss-Karte (Langzeit-Ziel in Prozent) und
## sichtbarer Level-Kappe „Level 12 / 40“.
func _shot_profil_abschluss() -> void:
	_resize(Vector2i(720, 1280))
	var screen := ProfilScreen.new()
	screen.auto_navigate = false
	screen.gs_override = _gs
	screen.net_override = _net
	root.add_child(screen)
	await _snap("profil_abschluss_karte.png")
	screen.free()


## Post-Schalter: Tagespaket abholbar (Knopf aktiv), danach ehrlich
## deaktiviert („Morgen wieder“) + Münz-Toast — der Ex-„bald“-Platzhalter.
func _shot_post_paket() -> void:
	_resize(Vector2i(720, 1160))
	var hintergrund := ColorRect.new()
	hintergrund.color = AcTokens.BG_CREAM
	hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(hintergrund)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "AcCard"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	var sheet := PostSheet.new()
	sheet.gs = _gs
	panel.add_child(sheet)
	root.add_child(panel)
	var toasts := ToastLayer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(toasts)
	await _snap("post_tagespaket_offen.png")
	sheet._on_paket_holen()
	await _snap("post_tagespaket_geholt_toast.png")
	panel.queue_free()
	toasts.queue_free()
	hintergrund.queue_free()
	await process_frame


## Galerie-Vollansicht: „Exportieren“-Knopf + Erfolgs-Toast mit Zielpfad
## (Ex-„Teilen (bald)“-Platzhalter).
func _shot_galerie_export() -> void:
	_resize(Vector2i(1280, 720))
	var foto := _demo_foto()
	if foto.is_empty():
		print("  ÜBERSPRUNGEN: kein Demo-Foto erzeugbar")
		return
	_gs.update(
		func(state: Dictionary) -> void:
			state["city"]["fotos"] = [
				{"pfad": foto, "at": NOW_MS - 3_600_000, "ort": "funkelpark", "fav": true}
			]
	)
	var screen: GalerieScreen = (
		(load("res://scripts/ui/galerie/galerie_screen.tscn") as PackedScene).instantiate()
	)
	screen.gs_override = _gs
	screen.auto_navigate = false
	root.add_child(screen)
	for _i in 8:
		await process_frame
	screen.oeffne_vollansicht(foto)
	for _i in 8:
		await process_frame
	screen._on_teilen()
	await _snap("galerie_export_toast.png")
	screen.queue_free()
	await process_frame


## Demo-Foto: vorhandenes Artefakt-PNG bevorzugt, sonst ein Verlauf.
func _demo_foto() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://fertig1_fotos"))
	var ziel := "user://fertig1_fotos/demo_0.png"
	var bild := Image.new()
	if bild.load("/tmp/gooby-godot/artifacts/REST4/park_nacht_lichter.png") != OK:
		bild = Image.create(640, 360, false, Image.FORMAT_RGB8)
		for y in 360:
			for x in 640:
				bild.set_pixel(x, y, Color(float(x) / 640.0, 0.6, float(y) / 360.0))
	if bild.save_png(ziel) != OK:
		return ""
	return ziel


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
