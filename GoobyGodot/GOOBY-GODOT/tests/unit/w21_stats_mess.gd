extends SceneTree
## W21 „ACNH-UI" Mess-Sonde (KEIN Test — kein test_-Präfix): vermisst die
## linke Stats-Spalte des Quer-HUD im Leitformat (2868×1320 @3×, Canvas
## 1564×720) und belegt den Flächen-Gewinn der StatKapsel-Gruppe
## (vorher/nachher-Vergleich der Design-Runde). Druckt pro Chip das globale
## Rect, die gemalte Summen-Fläche, die Bounding-Box der Gruppe und die
## Höhenabdeckung — und speichert einen Screenshot (voll + Spalten-Crop),
## wenn ein echter Renderer läuft (xvfb/llvmpipe).
##
## Aufruf (Screenshot-Variante):
##   W21_OUT=/tmp/gooby-godot/artifacts/W21 W21_TAG=vorher xvfb-run -a \
##     godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy --resolution 2868x1320 \
##     --script res://tests/unit/w21_stats_mess.gd
## Headless (nur Zahlen): gleicher Aufruf ohne xvfb-run/--rendering-*.

const OUT_ENV := "W21_OUT"
const TAG_ENV := "W21_TAG"
const DEFAULT_OUT := "/tmp/gooby-godot/artifacts/W21"
const FENSTER := Vector2i(2868, 1320)
## Leitformat-Insets in Punkten (Dynamic-Island-Klasse quer, wie fb3_ui_audit).
const INSETS_PT := [59.0, 0.0, 59.0, 21.0]
const SETTLE_FRAMES := 30

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")

var _out_dir := DEFAULT_OUT
var _tag := "messung"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var env_out := OS.get_environment(OUT_ENV)
	if env_out != "":
		_out_dir = env_out
	var env_tag := OS.get_environment(TAG_ENV)
	if env_tag != "":
		_tag = env_tag
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(FENSTER)
	UiScale.screen_scale_override = 3.0
	await _settle()
	var canvas := Vector2(root.get_visible_rect().size)
	var px_pro_pt := minf(canvas.x, canvas.y) / (minf(FENSTER.x, FENSTER.y) / 3.0)
	var wallpaper := AcWallpaper.for_context("default")
	root.add_child(wallpaper)
	var hud: Hud = HUD_SCENE.instantiate()
	hud.safe_area_override = Rect2(
		INSETS_PT[0] * px_pro_pt,
		INSETS_PT[1] * px_pro_pt,
		canvas.x - (INSETS_PT[0] + INSETS_PT[2]) * px_pro_pt,
		canvas.y - (INSETS_PT[1] + INSETS_PT[3]) * px_pro_pt
	)
	root.add_child(hud)
	await _settle()
	hud.apply_layout(HudLayoutLogic.Layout.LANDSCAPE)
	hud.set_stats({"hunger": 82.0, "energie": 64.0, "hygiene": 91.0, "spass": 73.0})
	hud.set_level(7, 0.45)
	hud.set_coins(265)
	await _settle()
	_messen(hud, canvas)
	await _screenshots(hud)
	quit(0)


## Gemalte Fläche + Bounding-Box der Stats-Gruppe (Chips sind disjunkt).
func _messen(hud: Hud, canvas: Vector2) -> void:
	var chips: Array[Control] = []
	for chip: Control in hud._chip_nodes:
		if chip.is_visible_in_tree():
			chips.append(chip)
	if chips.is_empty():
		print("[W21-MESS] FEHLER: keine sichtbaren Stats-Chips gefunden.")
		return
	var gemalt := 0.0
	var bbox: Rect2 = chips[0].get_global_rect()
	for chip in chips:
		var rect := chip.get_global_rect()
		gemalt += rect.size.x * rect.size.y
		bbox = bbox.merge(rect)
		print("[W21-MESS] chip=%s rect=%s" % [chip.name, rect])
	var canvas_flaeche := canvas.x * canvas.y
	print("[W21-MESS] tag=%s canvas=%s flaeche=%.0f" % [_tag, canvas, canvas_flaeche])
	print(
		(
			"[W21-MESS] gemalt=%.0f px2 (%.2f %% vom Canvas), bbox=%s (%.2f %%), hoehe=%.1f %%"
			% [
				gemalt,
				100.0 * gemalt / canvas_flaeche,
				bbox,
				100.0 * bbox.size.x * bbox.size.y / canvas_flaeche,
				100.0 * bbox.size.y / canvas.y,
			]
		)
	)


## Screenshot voll + Crop um die linke Spalte (nur mit echtem Renderer).
func _screenshots(hud: Hud) -> void:
	if DisplayServer.get_name() == "headless":
		print("[W21-MESS] headless — keine Screenshots.")
		return
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		return
	var voll := "%s/w21_stats_%s_voll.png" % [_out_dir, _tag]
	image.save_png(voll)
	print("[W21-MESS] shot: %s" % voll)
	var canvas := Vector2(root.get_visible_rect().size)
	var faktor := float(image.get_width()) / canvas.x
	var spalte := (hud._left_column as Control).get_global_rect().grow(24.0)
	var px := Rect2i(
		Vector2i((spalte.position * faktor).floor()), Vector2i((spalte.size * faktor).ceil())
	)
	px = px.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if px.size.x > 0 and px.size.y > 0:
		var crop := image.get_region(px)
		var crop_pfad := "%s/w21_stats_%s_spalte.png" % [_out_dir, _tag]
		crop.save_png(crop_pfad)
		print("[W21-MESS] shot: %s" % crop_pfad)


func _settle(frames: int = SETTLE_FRAMES) -> void:
	for _i in frames:
		await process_frame
