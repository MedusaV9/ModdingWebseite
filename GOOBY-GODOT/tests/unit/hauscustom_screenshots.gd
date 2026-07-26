extends SceneTree
## HAUS-CUSTOM-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte des Gestalten-Modus — den Gestalten-Screen (innen +
## außen), denselben ECHTEN Wohnzimmer-Raum mit drei Tapeten/Böden
## (HouseStyle.apply_to_room auf wohnzimmer.tscn), das Haus von außen in
## drei Stilen und das Grundstück mit zwei Bodenbelägen. Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/hauscustom_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/HAUSCUSTOM"
const SETTLE := 40

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Drei Looks für DENSELBEN Raum (Wohnzimmer).
const RAUM_LOOKS: Array[Dictionary] = [
	{"wand": "gebluemt", "wandFarbe": "rose", "boden": "dielen_hell", "bodenFarbe": "eiche"},
	{"wand": "gestreift", "wandFarbe": "himmel", "boden": "fliesen_schach", "bodenFarbe": "weiss"},
	{"wand": "holzpaneel", "wandFarbe": "nussbaum", "boden": "teppich", "bodenFarbe": "mint"},
]
## Drei Außen-Stile (Dachform/Fassade/Deko komplett verschieden).
const HAUS_STILE: Array[Dictionary] = [
	{
		"haus": {"fassade": "creme", "dachForm": "sattel", "dachFarbe": "ziegelrot"},
		"grundstueck": {"weg": "platten", "zaun": "latten", "zaunFarbe": "eiche"},
	},
	{
		"haus":
		{
			"fassade": "himmel",
			"dachForm": "walm",
			"dachFarbe": "anthrazit",
			"tuerFarbe": "pink",
			"vordach": "markise_gestreift",
			"vordachFarbe": "teal",
			"briefkasten": "kugel",
			"briefkastenFarbe": "pink",
			"hausnummerZahl": 12,
		},
		"grundstueck":
		{"weg": "rund", "wegFarbe": "sandstein", "zaun": "latten", "zaunFarbe": "weiss"},
	},
	{
		"haus":
		{
			"fassade": "rose",
			"dachForm": "flach",
			"dachFarbe": "grau",
			"tuerFarbe": "teal",
			"fensterFarbe": "anthrazit",
			"hausnummer": "modern",
			"briefkasten": "modern",
			"briefkastenFarbe": "anthrazit",
		},
		"grundstueck":
		{
			"boden": "steinplatten",
			"bodenFarbe": "sandstein",
			"weg": "ziegel",
			"wegFarbe": "ziegelrot",
			"zaun": "metall",
			"zaunFarbe": "anthrazit",
		},
	},
]
## Zwei Grundstücks-Beläge (Wildblumenwiese vs. Kies mit Trittsteinen).
const GRUND_LOOKS: Array[Dictionary] = [
	{
		"grundstueck":
		{"boden": "wildblumen", "bodenFarbe": "blattgruen", "zaun": "latten", "zaunFarbe": "weiss"}
	},
	{
		"grundstueck":
		{
			"boden": "kies",
			"bodenFarbe": "grau_hell",
			"weg": "rund",
			"wegFarbe": "sandstein",
			"zaun": "hecke",
			"zaunFarbe": "tannengruen",
		}
	},
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var dir := "user://hauscustom_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	gs.update(func(state: Dictionary) -> void: state["economy"]["coins"] = 1450)
	# Etwas Vorbesitz, damit die Kacheln „Im Besitz" UND Preise zeigen.
	for paar: Array in [["wand", "punkte"], ["wand", "gebluemt"], ["boden", "teppich"]]:
		HouseStyleState.kaufen(gs, paar[0], paar[1])
	await _screen_shots(gs)
	await _raum_shots(gs)
	await _aussen_shots()
	print("Screenshots fertig -> %s" % OUT_DIR)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	quit(0)


## 1) Gestalten-Screen: Innen (Tapeten, Vormerkung) + Außen (Dach).
func _screen_shots(gs: Node) -> void:
	var screen := CustomizeScreen.new()
	screen.auto_navigate = false
	screen.game_state_override = gs
	root.add_child(screen)
	await _settle(SETTLE)
	HouseStyleState.set_raum_flaeche(gs, "living", "wand", "gebluemt", "rose")
	screen.set_kategorie("wand")
	await _settle(SETTLE)
	await _shot("gestalten_screen_innen_tapeten.png")
	screen.set_kategorie("boden")
	screen.select_option("parkett_fischgraet")  # nicht gekauft → Anprobe + Kaufen
	await _settle(SETTLE)
	await _shot("gestalten_screen_innen_anprobe_kauf.png")
	screen.set_kategorie("dach")
	await _settle(SETTLE)
	await _shot("gestalten_screen_aussen_dach.png")
	screen.set_kategorie("grund_boden")
	await _settle(SETTLE)
	await _shot("gestalten_screen_grundstueck.png")
	root.remove_child(screen)
	screen.free()


## 2) DERSELBE echte Raum (wohnzimmer.tscn) mit drei Tapeten/Böden.
func _raum_shots(gs: Node) -> void:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: Node = scene.instantiate()
	room.set("game_state_override", gs)
	room.set("stunde_override", 13.0)
	root.add_child(room)
	await _settle(70)
	for i in RAUM_LOOKS.size():
		var style := HouseStyleState.normalize({"raeume": {"living": RAUM_LOOKS[i]}})
		var geaendert := HouseStyle.apply_to_room(room, style)
		print("  Raum-Look %d: %d Flächen umgestellt" % [i + 1, geaendert])
		await _settle(20)
		await _shot("raum_look_%d_%s.png" % [i + 1, RAUM_LOOKS[i]["wand"]])
	root.remove_child(room)
	room.queue_free()
	await _settle(2)


## 3) Haus von außen in drei Stilen + Grundstück mit zwei Belägen.
func _aussen_shots() -> void:
	var preview := CustomizePreview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(preview)
	await _settle(5)
	for i in HAUS_STILE.size():
		preview.show_exterior(HouseStyleState.normalize(HAUS_STILE[i]))
		await _settle(SETTLE)
		await _shot("haus_aussen_stil_%d_%s.png" % [i + 1, HAUS_STILE[i]["haus"]["dachForm"]])
	for i in GRUND_LOOKS.size():
		preview.show_exterior(HouseStyleState.normalize(GRUND_LOOKS[i]))
		preview.set_pose(0.6, 0.75)
		preview.set_zoom(0.85)
		await _settle(SETTLE)
		var boden: String = GRUND_LOOKS[i]["grundstueck"]["boden"]
		await _shot("grundstueck_belag_%d_%s.png" % [i + 1, boden])
	root.remove_child(preview)
	preview.free()


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
