extends SceneTree
## ORT-LEBEN-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert für
## G8-P1 „Jeder Ort lebt“ (Fix PT2-B4) JEDEN Stadt-Ort mit seinem
## OrtLeben-Ambiente als Review-Artefakt. Je Ort: fester Besucher-Seed,
## Zeitsprung bis kurz HINTER den ersten Orts-Moment (Sprechblase steht
## noch im Bild) und ein Schnappschuss. Braucht einen echten Renderer:
## xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --audio-driver Dummy \
##   --script res://tests/unit/screenshot_ort_leben.gd
## (Aufruf immer über tools/ci/run_godot_isolated.sh + globalen flock.)

const OUT_DIR := "/tmp/gooby-godot/artifacts/ORT_LEBEN"
const SETTLE_FRAMES := 24
const SEED := 4711

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Alle Orte mit OrtLeben-Konfig (G7-Bestand + G8-P1-Rollout).
const ORTE: Array[String] = [
	"rehwei",
	"baumarkt",
	"goobytheke",
	"post",
	"flughafen",
	"goobyman",
	"pow",
	"autohaus",
	"tierarzt",
	"gouhbus",
	"wochenmarkt",
]

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	# Auto-Qualitätsbremse aus (Muster rw5/w15-Screenshot-Tools): unter
	# llvmpipe/xvfb legt sie sonst den "Qualität angepasst"-Toast ins Bild.
	var quality := root.get_node_or_null("Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	for ort_id in ORTE:
		await _shot_ort_leben(ort_id)
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _make_gs() -> Node:
	_seq += 1
	var dir := "user://ort_leben_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", 900)
	return gs


func _teardown(node: Node, gs: Node) -> void:
	PanelStack.clear()
	node.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


## Ein Ort mit Leben: mounten, Modelle laden lassen, dann die OrtLeben-Zeit
## bis kurz hinter den ersten Moment springen — Besucher stehen mitten in
## ihren Runden, die Moment-Sprechblase hängt noch über dem Darsteller.
func _shot_ort_leben(ort_id: String) -> void:
	var gs := _make_gs()
	var ort: OrtScene = load("res://scenes/city/orte/%s.tscn" % ort_id).instantiate()
	ort.game_state_override = gs
	ort.leben_seed_override = SEED
	ort.leben_stumm_override = true
	root.add_child(ort)
	for _i in 40:
		await process_frame
	# Begrüßungs-Dialog ausblenden — er verdeckt sonst den halben Raum
	# und hier geht es um das AMBIENTE, nicht um den Dialog.
	if ort.dialog != null and is_instance_valid(ort.dialog):
		ort.dialog.visible = false
	if ort.leben != null:
		ort.leben.auto_zeit = false
		ort.leben.advance_zeit(_sprung_s(ort.leben))
	await _snap("%s_leben.png" % ort_id)
	var leben_info := "OHNE Leben!"
	if ort.leben != null:
		leben_info = (
			"%d Besucher (%d Sitzer, %d Requisiten), %d Momente gefeuert"
			% [
				ort.leben.besucher_nodes().size(),
				ort.leben.sitzer_anzahl(),
				ort.leben.requisit_anzahl(),
				ort.leben.momente_gefeuert,
			]
		)
	print("  %s: %s" % [ort_id, leben_info])
	await _teardown(ort, gs)


## Zeitsprung: knapp hinter den ersten Moment-Versatz (Sprechblase frisch),
## Orte ohne Momente (G7-Bestand) bekommen 7 s Schlender-Vorlauf.
func _sprung_s(leben: OrtLeben) -> float:
	var momente := leben.momente_liste()
	if momente.is_empty():
		return 7.0
	return float((momente[0] as Dictionary).get("versatz_s", 8.0)) + 0.15


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
