extends SceneTree
## W21/P4 Nachher-Sichtung: die 4 Belege des Minispiel-Rahmens im
## Leitformat (iPhone 17 Pro Max quer, 2868×1320 @3x, Dynamic-Island-
## Insets) — (1) Bühne: HOCHKANT-Spiel im Quer-Canvas (Pillar-Diorama),
## (2) Results-Zeremonie, (3) Pregame-Zwei-Spalten-Karte, (4) Arcade.
## Braucht einen echten Renderer (Muster g7_rahmen_screens.gd):
##   W21_OUT=/tmp/gooby-godot/artifacts/W21_P4 xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 \
##     --script res://tests/tools/w21_p4_screens.gd
## Optional W21_ONLY=pregame,results,... für schnelle Einzel-Sichtung,
## W21_HOCH=1 für das Hochformat des Leitgeräts (Regressions-Blick).

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/W21_P4"
const WINDOW := Vector2i(2868, 1320)
const WINDOW_HOCH := Vector2i(1320, 2868)
const SCALE := 3.0
## Dynamic-Island-Klasse: quer 59 pt links/rechts + 21 pt Home-Indicator,
## hoch 59 pt oben + 34 pt unten (Werte wie fb3_ui_audit.SIZES).
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
	# Auto-Qualitätsbremse aus: unter llvmpipe/xvfb würde sie sonst mitten
	# im Bild den "Qualität angepasst"-Toast einblenden (Muster rw5).
	var quality := root.get_node_or_null("Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	_pin_leitformat()
	await _frames(6)
	if _will("buehne"):
		await _capture_buehne()
	if _will("results"):
		await _capture_results()
	if _will("pregame"):
		await _capture_pregame()
	if _will("arcade"):
		await _capture_arcade()
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


## (1) Bühne: teaParty ist ein HOCHKANT-Spiel — im Quer-Canvas rahmt der
## Host es mit Pillar-Bühne (Mood, Muster, Schild, Gooby-Silhouette).
func _capture_buehne() -> void:
	_refill_energy()
	var host: MinigameHost = (
		(load("res://scripts/minigames/minigame_host.tscn") as PackedScene).instantiate()
	)
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "teaParty", "difficulty": "normal", "seed": 4242})
	root.add_child(host)
	var deadline := Time.get_ticks_msec() + 15_000
	while Time.get_ticks_msec() < deadline:
		var btn: Button = host.get("_pause_button")
		if btn != null and not btn.disabled:
			break
		await process_frame
	await _frames(30)
	await _snap("w21_p4_nachher_buehne")
	host.queue_free()
	await _frames(4)


## (2) Results-Zeremonie im Feier-Worst-Case (Rekord + Boni + Geist).
func _capture_results() -> void:
	var results: MinigameResults = (
		(load("res://scripts/minigames/results.tscn") as PackedScene).instantiate()
	)
	root.add_child(results)
	await _frames(2)
	var feier := {
		"score": 123,
		"coins": 52,
		"xp": 25,
		"best": 123,
		"newBest": true,
		"beatTarget": true,
		"firstToday": true,
		"spotlightBonusCoins": 26,
	}
	results.show_results(feier, {"title_key": "mg.teaParty.title"})
	# Choreo ausspielen lassen (Stagger + Count-Up + Sterne-Stempel).
	await _sekunden(3.0)
	await _snap("w21_p4_nachher_results")
	results.queue_free()
	await _frames(4)


## (3) Pregame: Zwei-Spalten-Karte quer (Cover + Gooby links, Zeilen rechts).
func _capture_pregame() -> void:
	var pre: MinigamePregame = (
		(load("res://scripts/minigames/pregame.tscn") as PackedScene).instantiate()
	)
	pre.auto_navigate = false
	pre.receive_params({"game_id": "teaParty"})
	root.add_child(pre)
	await _frames(10)
	await _snap("w21_p4_nachher_pregame")
	pre.queue_free()
	await _frames(4)


## (4) Arcade-Grid (Hierarchie: Titel führt, Reihen-Header eine Stufe runter).
func _capture_arcade() -> void:
	var arcade: Control = (
		(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
	)
	root.add_child(arcade)
	await _frames(10)
	await _snap("w21_p4_nachher_arcade")
	arcade.queue_free()
	await _frames(4)


func _snap(name: String) -> void:
	await process_frame
	if _hoch:
		name += "_hoch"
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("[w21_p4] %s.png" % name)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _sekunden(sec: float) -> void:
	var deadline := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _refill_energy() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)
