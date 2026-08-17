extends SceneTree
## W21/P2 Nachher-Sichtung: die Belege des „Welt zuerst“-Baumodus im
## Leitformat (iPhone 17 Pro Max quer, 2868×1320 @3x, Dynamic-Island-
## Insets) — (1) Dock EINGEKLAPPT (Startzustand: Griff-Zeile + Ebenen-
## Zeile), (2) Item-Blatt OFFEN (Bild-Chips mit Zähler-Badge), (3) Geist
## aktiv (Action-Zeile, Lager automatisch zugeklappt — der frühere
## 59,1-%-Tiefpunkt), (4) Hochformat-Regressions-Blick.
## Braucht einen echten Renderer (Muster w21_p4_screens.gd):
##   W21_OUT=/tmp/gooby-godot/artifacts/W21_P2 xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/w21_p2_screens.gd
## W21_HOCH=1 rendert stattdessen das Hochformat des Leitgeräts.

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/W21_P2"
const WINDOW := Vector2i(2868, 1320)
const WINDOW_HOCH := Vector2i(1320, 2868)
const SCALE := 3.0
## Dynamic-Island-Klasse (Werte wie w21_p4_screens/fb3_ui_audit.SIZES).
const INSETS_PT: Array[float] = [59.0, 0.0, 59.0, 21.0]
const INSETS_PT_HOCH: Array[float] = [0.0, 59.0, 0.0, 34.0]

const GameStateScript := preload("res://scripts/state/game_state.gd")

var _out := OUT_DEFAULT
var _hoch := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment("W21_OUT")
	if env != "":
		_out = env
	_hoch = OS.get_environment("W21_HOCH") == "1"
	DirAccess.make_dir_recursive_absolute(_out)
	# Auto-Qualitätsbremse aus: unter llvmpipe/xvfb bliebe sonst mitten im
	# Bild der "Qualität angepasst"-Toast hängen (Muster rw5/w21_p4).
	var quality := root.get_node_or_null("Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	_pin_leitformat()
	await _frames(6)
	# Frischer Spielstand mit Standard-Einrichtung; Bett-Quest/Umzug aus —
	# die Sichtung zeigt den NORMALEN Bau-Alltag (Muster test_w21_bau_welt).
	var dir := "user://w21_p2_screens/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	gs.set_value("home.movingDay", false)
	var room: RoomBase = (load("res://scenes/home/wohnzimmer.tscn") as PackedScene).instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	root.add_child(room)
	await _frames(30)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	# Thumbnails der CraftVorschau-Bäckerei fertig backen lassen.
	await _sekunden(2.0)
	if _hoch:
		await _snap("w21_p2_nachher_hochkant")
	else:
		# (1) Startzustand: Dock eingeklappt — die Welt zuerst.
		await _snap("w21_p2_nachher_dock_eingeklappt")
		# (2) Blatt offen: Bild-Chips mit Zähler-Badge im Item-Blatt.
		build._dock_ui.klappe_lager(false)
		await _sekunden(0.8)
		await _snap("w21_p2_nachher_blatt_offen")
		# (3) Geist aktiv: Action-Zeile, Lager klappt automatisch zu —
		# der frühere 59,1-%-Tiefpunkt der W21-Playtest-Welle.
		build._begin_new(FurnitureCatalog.def("bedSingle"))
		await _sekunden(0.8)
		await _snap("w21_p2_nachher_geist_zielen")
		build._on_abbrechen()
		await _frames(4)
	build.close()
	room.queue_free()
	await _frames(4)
	gs.free()
	print("[w21_p2] fertig -> %s" % _out)
	quit(0)


## Leitformat pinnen (Rechnung wie w21_p4_screens._pin_leitformat).
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


func _snap(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("[w21_p2] %s.png" % name)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _sekunden(sec: float) -> void:
	var deadline := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
