extends SceneTree
## RW-3-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte des Quest-/NPC-Systems — drei NPC-Gespräche (Begrüßung,
## Options-Drehscheibe, Geschenk-Reaktion), das Quest-Log mit Kapitel-
## Titelkarte, eine Warte-Quest mit Restzeit, die Freundschafts-Ansicht und
## die Welt-Marker über NPC-Figuren. Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/rw3_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW3"
const SETTLE := 30
const NOW_MS := 1768478400000

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _welt: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var dir := "user://rw3_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	RQuestSlices.ensure_registered()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	await _gespraech_shots()
	await _quest_log_shots(gs)
	await _freundschaft_shot(gs)
	await _marker_shot()
	print("Screenshots fertig -> %s" % OUT_DIR)
	gs.free()
	SaveSchema.unregister_slice(RQuestSlices.SLICE_ID)
	RQuestSlices.reset_for_tests()
	quit(0)


## ------------------------------------------------- 1) Drei NPC-Gespräche


func _gespraech_shots() -> void:
	# Rosi, morgens im Stall: Begrüßungs-Knoten nach Tageszeit.
	await _gespraech(
		"rosi",
		{"stunde": 8.0, "wetter": "sonne", "herzen": 1},
		"",
		0,
		"gespraech_rosi_gruss_morgen.png"
	)
	# Opa Alwin als Freund (Herz 4): Options-Drehscheibe sichtbar.
	await _gespraech(
		"alwin",
		{"stunde": 14.0, "wetter": "sonne", "herzen": 4, "quest_vergabe": true},
		"",
		2,
		"gespraech_alwin_hub_optionen.png"
	)
	# Timmi bekommt sein Lieblings-Geschenk: Reaktions-Knoten.
	await _gespraech(
		"timmi",
		{"stunde": 12.0, "wetter": "sonne", "herzen": 2},
		"geschenk_liebt",
		0,
		"gespraech_timmi_geschenk_liebt.png"
	)


## Ein Gespräch aufbauen: 3D-Kulisse mit der NPC-Figur + OrtDialogView.
## `start_knoten` überschreibt den Kontext-Einstieg (""= automatisch);
## `taps` blättert die Bubble weiter (2 = bis zu den Options-Knöpfen).
func _gespraech(
	npc_id: String, kontext: Dictionary, start_knoten: String, taps: int, datei: String
) -> void:
	var def := RNpcKatalog.npc(npc_id)
	_kulisse_bauen()
	var figur := RNpcFigur.neu(def)
	# Bei sichtbaren Optionen steht der NPC links neben dem Options-Stapel;
	# Gesicht (+Z) zeigt zur Kamera.
	figur.position = Vector3(-2.4 if taps > 0 else 0.0, 0.0, 0.0)
	_welt.add_child(figur)
	var view := OrtDialogView.new()
	root.add_child(view)
	var baum := RNpcDialog.lade_baum(def)
	if start_knoten.is_empty():
		baum["start"] = RNpcDialog.start_knoten(baum, kontext)
	else:
		baum["start"] = start_knoten
	view.starte(baum, RNpcDialog.kontext_flags(def, kontext))
	await _settle(SETTLE)
	var bubble: DialogBubble = _finde_bubble(view)
	for _i in taps:
		if bubble != null and bubble.is_active():
			bubble._advance()
			await _settle(SETTLE)
	await _shot(datei)
	root.remove_child(view)
	view.free()
	_kulisse_weg()


## ------------------------------- 2) Quest-Log, Titelkarte, Warte-Restzeit


func _quest_log_shots(gs: Node) -> void:
	# haupt_01 aktiv mit erstem erledigtem Ziel: Kapitel-1-Titelkarte,
	# Status-Chips und Ziel-Fortschritt in einem Bild.
	RQuestState.annehmen(gs, "haupt_01")
	RQuestState.ereignis(gs, {"typ": "sprich_mit", "npc": "rosi"})
	var log_ui := RQuestLogUi.new()
	log_ui.game_state_override = gs
	root.add_child(log_ui)
	await _settle(SETTLE)
	await _shot("quest_log_hauptreihe_titelkarte.png")
	log_ui._on_tab("tages")
	await _settle(SETTLE)
	await _shot("quest_log_tagesaufgaben.png")
	# Warte-Quest: Rosi auf Herz 3 heben, Saat-Quest annehmen, zum
	# Warte-Ziel durchspielen — Restzeit-Chip + Alternativ-Tipp.
	RNpcState.quest_bonus(gs, "rosi", 37.0, NOW_MS)
	RQuestState.annehmen(gs, "neben_rosi_saat")
	RQuestState.ereignis(gs, {"typ": "gehe_zu", "ort": "weide"})
	log_ui._on_tab("neben")
	await _settle(SETTLE)
	await _shot("quest_log_warte_quest_restzeit.png")
	root.remove_child(log_ui)
	log_ui.free()


## ------------------------------------------- 3) Freundschafts-Ansicht


func _freundschaft_shot(gs: Node) -> void:
	# Gestaffelte Herz-Stände, damit volle/leere Herzen + Freischaltungen
	# (erreicht vs. ausgegraut) sichtbar sind.
	RNpcState.quest_bonus(gs, "moehrchen", 4.0, NOW_MS)
	RNpcState.quest_bonus(gs, "timmi", 64.0, NOW_MS)
	var ui := RNpcFreundeUi.new()
	ui.game_state_override = gs
	root.add_child(ui)
	await _settle(SETTLE)
	await _shot("freundschaft_ansicht.png")
	root.remove_child(ui)
	ui.free()


## ------------------------------------------------------ 4) Welt-Marker


func _marker_shot() -> void:
	_kulisse_bauen()
	var links := RNpcFigur.neu(RNpcKatalog.npc("marta"))
	links.position = Vector3(-1.6, 0.0, 0.0)
	_welt.add_child(links)
	var vergabe := RQuestMarker.neu("vergabe")
	vergabe.position = Vector3(0.0, _marker_hoehe(RNpcKatalog.npc("marta")), 0.0)
	links.add_child(vergabe)
	var rechts := RNpcFigur.neu(RNpcKatalog.npc("eisenhuf"))
	rechts.position = Vector3(1.6, 0.0, 0.0)
	_welt.add_child(rechts)
	var abgabe := RQuestMarker.neu("abgabe")
	abgabe.position = Vector3(0.0, _marker_hoehe(RNpcKatalog.npc("eisenhuf")), 0.0)
	rechts.add_child(abgabe)
	await _settle(SETTLE)
	await _shot("welt_marker_vergabe_abgabe.png")
	_kulisse_weg()


## ------------------------------------------------------------ Helfer


func _kulisse_bauen() -> void:
	_welt = Node3D.new()
	root.add_child(_welt)
	var boden := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	boden.mesh = plane
	boden.material_override = RanchPferd.material(Color("#8FBF7F"))
	_welt.add_child(boden)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	licht.light_energy = 1.2
	_welt.add_child(licht)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#BBDDEE")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.92, 0.95)
	environment.ambient_light_energy = 0.7
	_welt.add_child(env)
	var kamera := Camera3D.new()
	kamera.position = Vector3(0.0, 1.7, 3.1)
	kamera.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	_welt.add_child(kamera)
	kamera.make_current()


func _kulisse_weg() -> void:
	root.remove_child(_welt)
	_welt.queue_free()
	_welt = null


## Marker-Höhe wie im RNpcManager (über dem Namensschild).
func _marker_hoehe(def: Dictionary) -> float:
	var modell: Dictionary = def.get("modell") if def.get("modell") is Dictionary else {}
	return 2.3 * clampf(float(modell.get("groesse", 1.0)), 0.4, 1.6) + 0.45


func _finde_bubble(view: Control) -> DialogBubble:
	for kind in view.get_children():
		if kind is DialogBubble:
			return kind
	return null


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
