extends SceneTree
## W21/P3 Nachher-Sichtung: die Belege des Sheet-/Menü-Umbaus im Leitformat
## (iPhone 17 Pro Max quer, 2868×1320 @3x, Dynamic-Island-Insets) —
## (1) Profil (Vorzeige-Stück: EIN Kartenraster, blatt_kopf, Count-Up),
## (2) Quest-Blatt (PanelSheet + Stempel-Häkchen), (3) IKEA (Laden-Mood),
## (4) Album (Sticker-Raster + Stagger). Braucht einen echten Renderer
## (Muster w21_p4_screens.gd):
##   W21_OUT=/tmp/gooby-godot/artifacts/W21_P3 xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 \
##     --script res://tests/tools/w21_p3_screens.gd
## Optional W21_ONLY=profil,quests,... und W21_HOCH=1 (Hochformat).

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/W21_P3"
const WINDOW := Vector2i(2868, 1320)
const WINDOW_HOCH := Vector2i(1320, 2868)
const SCALE := 3.0
const INSETS_PT: Array[float] = [59.0, 0.0, 59.0, 21.0]
const INSETS_PT_HOCH: Array[float] = [0.0, 59.0, 0.0, 34.0]

var _out := OUT_DEFAULT
var _only: Array[String] = []
var _hoch := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment("W21_OUT")
	if env != "":
		_out = env
	for part: String in OS.get_environment("W21_ONLY").split(","):
		if not part.is_empty():
			_only.append(part)
	_hoch = OS.get_environment("W21_HOCH") == "1"
	DirAccess.make_dir_recursive_absolute(_out)
	# llvmpipe-FPS triggert sonst die Qualitäts-Bremse samt Banner mitten
	# im Foto („Qualität angepasst“-Toast über dem Blatt-Kopf).
	var quality := root.get_node_or_null("/root/Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	_pin_leitformat()
	await _frames(6)
	if _will("profil"):
		await _capture_profil()
	if _will("quests"):
		await _capture_quests()
	if _will("ikea"):
		await _capture_ikea()
	if _will("album"):
		await _capture_album()
	quit(0)


func _will(station: String) -> bool:
	return _only.is_empty() or station in _only


## Leitformat pinnen (Rechnung wie test_fb3_uiscale_conformance._pin_format).
func _pin_leitformat() -> void:
	var fenster := WINDOW_HOCH if _hoch else WINDOW
	var insets_pt := INSETS_PT_HOCH if _hoch else INSETS_PT
	UiScale.screen_scale_override = SCALE
	DisplayServer.window_set_size(fenster)
	root.size = fenster
	var canvas := Vector2(root.get_visible_rect().size)
	var pt_kurz := minf(float(fenster.x), float(fenster.y)) / SCALE
	var px_per_pt := minf(canvas.x, canvas.y) / pt_kurz
	var l := insets_pt[0] * px_per_pt
	var t := insets_pt[1] * px_per_pt
	var r := insets_pt[2] * px_per_pt
	var b := insets_pt[3] * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)


## Etwas Leben in den Spielstand, damit Profil/Album nicht bei 0 stehen
## (Serie, Münzen, Spielzeit — die Count-Up-Zahlen haben so echte Ziele).
func _fuelle_spielstand() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("set_value"):
		return
	gs.call("set_value", "daily.streak", 6)
	gs.call("set_value", "economy.coins", 385)
	gs.call("set_value", "meta.playMs", 5_520_000)
	gs.call("set_value", "gooby.level.xp", 40)


## (1) Profil: Vorzeige-Stück — Reisepass, Erfolge, Stat-Blöcke auf EINEM
## Kartenraster unter dem blatt_kopf; Count-Up spielt beim Aufbau.
func _capture_profil() -> void:
	_fuelle_spielstand()
	var screen: Control = (
		(load("res://scripts/ui/profil/profil_screen.tscn") as PackedScene).instantiate()
	)
	screen.set("auto_navigate", false)
	root.add_child(screen)
	# Count-Up + Stagger ausspielen lassen, dann in Ruhe fotografieren.
	await _sekunden(1.6)
	await _snap("w21_p3_nachher_profil")
	# Zweiter Blick: zum Kartenraster (Abschluss/Statistik/Favoriten)
	# scrollen — Beleg „alle Karten gleiche Breite/Radius“.
	var liste: VBoxContainer = screen.get("_list_box")
	var scroll := liste.get_parent() as ScrollContainer
	if scroll != null and liste.get_child_count() > 1:
		scroll.scroll_vertical = int(liste.get_child(1).position.y)
		await _frames(8)
		await _snap("w21_p3_nachher_profil_raster")
	screen.queue_free()
	await _frames(4)


## (2) Quest-Blatt: PanelSheet-Grammatik (Griff, Titel, gepinnter Fuß) mit
## echten Katalog-Quests — eine fertig (Stempel-Häkchen), zwei offen.
func _capture_quests() -> void:
	var sheet: PanelSheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
	root.add_child(sheet)
	await _frames(2)
	var panel := DailyQuestPanel.new()
	var board := [
		{
			"def": {"id": "feed3", "kategorie": "care", "muenzen": 20, "xp": 10},
			"target": 3,
			"progress": 3,
			"complete": true,
			"claimed": true,
		},
		{
			"def": {"id": "pet5", "kategorie": "care", "muenzen": 15, "xp": 8},
			"target": 5,
			"progress": 2,
			"complete": false,
			"claimed": false,
		},
		{
			"def": {"id": "play3", "kategorie": "games", "muenzen": 30, "xp": 15},
			"target": 3,
			"progress": 1,
			"complete": false,
			"claimed": false,
		},
	]
	var f := UiScale.for_viewport(root)
	panel.rebuild(board, {"muenzen": 25, "xp": 15, "paid": false}, true, f)
	sheet.set_title(I18nService.t("quests.titel"))
	sheet.add_content(panel)
	sheet.add_footer(panel.footer_control())
	sheet.open()
	# Blatt-Slide zu Ende fahren lassen (BLATT_S = 0.24 s).
	await _sekunden(0.6)
	await _snap("w21_p3_nachher_quests")
	sheet.queue_free()
	await _frames(4)


## (3) IKEA: Laden-Mood (Shop-Wash) + Zeilenliste mit Blatt-Kopf.
func _capture_ikea() -> void:
	var screen: Control = (load("res://scripts/shop/ikea_screen.tscn") as PackedScene).instantiate()
	screen.set("auto_navigate", false)
	root.add_child(screen)
	await _sekunden(1.0)
	await _snap("w21_p3_nachher_ikea")
	screen.queue_free()
	await _frames(4)


## (4) Album: blatt_kopf + Sticker-Raster (Stagger ausgespielt).
func _capture_album() -> void:
	_fuelle_spielstand()
	var screen: Control = (
		(load("res://scripts/ui/album/album_screen.tscn") as PackedScene).instantiate()
	)
	screen.set("auto_navigate", false)
	root.add_child(screen)
	await _sekunden(1.2)
	await _snap("w21_p3_nachher_album")
	screen.queue_free()
	await _frames(4)


func _snap(name: String) -> void:
	await process_frame
	if _hoch:
		name += "_hoch"
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("[w21_p3] %s.png" % name)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _sekunden(sec: float) -> void:
	var deadline := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
