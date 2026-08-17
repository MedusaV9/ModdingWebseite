extends SceneTree
## SEELE-Screenshot-Tool (FB-6, KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte der Seelen-Momente im ECHTEN Wohnzimmer (wohnzimmer.tscn
## + GoobyReactions). Zeit läuft über now_ms_override — jeder Moment ist
## deterministisch erzwungen. Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/soul_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FB6"
const SETTLE := 40

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const MS_D := 86_400_000
## 2026-07-27 08:00 UTC — Montagmorgen, Ausgangspunkt aller Momente.
const START_MS := 1_785_139_200_000

var _gs: Node = null
var _room: Node = null
var _runner: GoobyReactions = null
var _now := START_MS


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	SoulState.register_slice()
	var dir := "user://soul_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_gs = GameStateScript.new()
	_gs.initialize(dir + "/save_v5.json")
	_gs.update(func(s: Dictionary) -> void: s["meta"]["playerName"] = "Mira")
	_build_room()
	await _settle(70)
	_attach_runner()
	await _shot_gruss()
	await _shot_geburtstag()
	await _shot_jubilaeum()
	await _shot_erinnerung()
	await _shot_erster_schnee()
	await _shot_kitzlig()
	await _shot_traurig()
	await _shot_turm()
	await _shot_geburtstags_frage()
	print("Seele-Screenshots fertig -> %s" % OUT_DIR)
	_room.queue_free()
	await _settle(2)
	_gs.free()
	SaveSchema.unregister_slice(SoulState.SLICE_ID)
	SoulState.reset_for_tests()
	quit(0)


func _build_room() -> void:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	_room = scene.instantiate()
	_room.set("game_state_override", _gs)
	_room.set("stunde_override", 10.0)
	root.add_child(_room)


func _attach_runner() -> void:
	_runner = GoobyReactions.new()
	_runner.name = "GoobyReactions"
	_runner.now_ms_override = _now
	_room.add_child(_runner)
	_runner.setup(_room)
	# Ohne ContentRegistry-Autoload (--script-Modus) Defs direkt einspeisen.
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/soul/data/soul.json")
	)
	_runner._defs = parsed.get("items", [])
	# Kennen seit 10 Tagen, Besuch heute Morgen — neutraler Ausgangspunkt.
	SoulState.mutate(
		_gs,
		func(s: Dictionary) -> void:
			s["firstMetAt"] = START_MS - 10 * MS_D
			s["lastVisitAt"] = START_MS - 2 * 3_600_000
	)
	# Für ruhige, lesbare Posen: Eigenwanderung UND das autonome Idle-Leben
	# des Runners (dösen/fernsehen/…) während der Shots aus — sonst schläft
	# Gooby zufällig mitten im Artefakt ein (passiert wirklich!).
	_runner.set_process(false)
	var gooby: Node = _room.gooby()
	if gooby != null and gooby.has_method("set_wander_enabled"):
		gooby.set_wander_enabled(false)


## Zeit vorspulen (Frequenzbremse + Tagesgates bleiben realistisch).
func _advance_min(minutes: int) -> void:
	_now += minutes * 60_000
	_runner.now_ms_override = _now


## 1) Morgen-Gruß mit Namen („Guten Morgen, Mira!“). roll=0.1 wählt
## deterministisch die Text-Variante a (mit {namek}).
func _shot_gruss() -> void:
	# setup() hat beim Attach schon natürlich gegrüßt (zufällige Variante) —
	# fürs Artefakt Gruß-Gates zurücksetzen und Variante a (mit Name) wählen.
	SoulState.mutate(
		_gs,
		func(s: Dictionary) -> void:
			s["lastGreetDay"] = ""
			s["ambient"] = {"day": "", "count": 0, "lastAt": 0}
	)
	var slice := SoulState.slice_of(_gs)
	var ctx := _runner._ctx(2 * 3_600_000)
	var moment := SoulService.decide_enter(_gs.state(), slice, _runner._defs, ctx, 0.1)
	SoulState.mutate(_gs, func(s: Dictionary) -> void: SoulService.book_enter(s, moment, ctx))
	_runner._show_moment(moment)
	await _settle(SETTLE)
	await _shot("seele_1_gruss_morgen_mit_name.png")


## 2) Spieler-Geburtstag: Konfetti + Feier-Bubble.
func _shot_geburtstag() -> void:
	_advance_min(10)
	SoulState.mutate(
		_gs, func(s: Dictionary) -> void: s["playerBirthday"] = {"month": 7, "day": 27}
	)
	_runner._run_enter()
	await _settle(12)
	await _shot("seele_2_geburtstag_spieler_konfetti.png")


## 3) Jubiläum: „Wir kennen uns jetzt 100 Tage!“
func _shot_jubilaeum() -> void:
	_advance_min(10)
	SoulState.mutate(
		_gs,
		func(s: Dictionary) -> void:
			s["playerBirthday"] = {"month": 0, "day": 0}
			s["firstMetAt"] = _now - 100 * MS_D
	)
	_runner._run_enter()
	await _settle(12)
	await _shot("seele_3_jubilaeum_100_tage_konfetti.png")


## 4) Persönliche Erinnerung aus ECHTEN Daten (Minigolf-Rekord im Save).
func _shot_erinnerung() -> void:
	_advance_min(10)
	_gs.update(func(s: Dictionary) -> void: s["minigames"]["legacy"]["best"] = {"teaParty": 42})
	var memories := SoulMemories.candidates(_gs.state())
	var memory := SoulMemories.pick(memories, {}, _now, 0.0)
	var def := SoulService.def_by_id(_runner._defs, "erinnerung")
	var moment := _runner._moment_of(def, _runner._ctx(0))
	moment["text_key"] = str(memory["text_key"])
	moment["args"].merge(memory.get("args", {}), true)
	_runner._last_bubble_s = -1000.0
	_runner._show_moment(moment)
	await _settle(SETTLE)
	await _shot("seele_4_erinnerung_teeparty_rekord.png")


## 5) Erster Schnee: Ritual-Bubble, Gooby läuft zum Fenster.
func _shot_erster_schnee() -> void:
	_advance_min(10)
	var def := SoulService.def_by_id(_runner._defs, "ritual_erster_schnee")
	var moment := _runner._moment_of(def, _runner._ctx(0))
	_runner._last_bubble_s = -1000.0
	_runner._show_moment(moment)
	await _settle(150)
	await _shot("seele_5_erster_schnee_fenster.png")


## 6) Antippen: dreimal getippt → kitzlig (kichert + hüpft).
func _shot_kitzlig() -> void:
	_advance_min(10)
	for _i in 3:
		_runner._last_bubble_s = -1000.0
		_runner.handle_tap()
	await _settle(20)
	await _shot("seele_6_kitzlig_nach_tippen.png")


## 7) Vernachlässigung: traurige Blicke + sanfter Kommentar (NIE Strafen).
func _shot_traurig() -> void:
	_advance_min(10)
	_runner._last_bubble_s = -1000.0
	_runner._check_neglect({"hunger": 5.0, "fun": 10.0})
	await _settle(SETTLE)
	await _shot("seele_7_vernachlaessigt_trauriger_blick.png")


## 8) Überraschung: Kissenturm neben Gooby.
func _shot_turm() -> void:
	_advance_min(10)
	var def := SoulService.def_by_id(_runner._defs, "sup_turm")
	var moment := _runner._moment_of(def, _runner._ctx(0))
	_runner._last_bubble_s = -1000.0
	_runner._show_moment(moment)
	_runner._build_tower()
	# Traurig-Zustand aus Shot 7 auflösen, damit der Turm fröhlich wirkt.
	_runner._check_neglect({"hunger": 90.0, "fun": 90.0})
	await _settle(30)
	await _shot("seele_8_ueberraschung_kissenturm.png")


## 9) Geburtstags-Frage: kleines, wegklickbares Panel.
func _shot_geburtstags_frage() -> void:
	_advance_min(10)
	var def := SoulService.def_by_id(_runner._defs, "frage_geburtstag")
	var moment := _runner._moment_of(def, _runner._ctx(0))
	_runner._last_bubble_s = -1000.0
	_runner._show_moment(moment)
	_runner._open_birthday_panel()
	await _settle(SETTLE)
	await _shot("seele_9_geburtstags_frage_panel.png")


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
