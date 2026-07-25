extends SceneTree
## CONTENT-A-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert Gooby mit
## verschiedenen Outfit-Kombis und den Wardrobe-Screen als Review-Artefakte.
## Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_cosmetics.gd
## Zusatzmodus für die Sitzkontrolle EINZELNER Teile (Kopf-Nahaufnahme):
##   ... --script res://tests/unit/screenshot_cosmetics.gd -- --kontakt=hut

const OUT_DIR := "/tmp/gooby-godot/artifacts/CONTENTA"
const SETTLE_FRAMES := 16

const GameStateScript := preload("res://scripts/state/game_state.gd")

## Vier Kombis für das Abnahme-Blatt.
const KOMBIS: Array[Dictionary] = [
	{
		"datei": "gooby_kombi_1_strohhut.png",
		"titel": "Strohhut + Sonnenbrille + Halstuch",
		"items": {"hut": "strawHat", "brille": "sunglasses", "hals": "bandana"},
		"fell": "caramel",
		"drehung": 0.0,
	},
	{
		"datei": "gooby_kombi_2_zylinder.png",
		"titel": "Zylinder + Monokel + Fliege + Umhang",
		"items":
		{"hut": "topHat", "brille": "monocle", "hals": "bowtie", "ruecken": "ruecken_schirm"},
		"fell": "midnight",
	},
	{
		"datei": "gooby_kombi_3_krone.png",
		"titel": "Krone + Herzbrille + Medaillon + Feenflügel",
		"items":
		{
			"hut": "crown",
			"brille": "heartGlasses",
			"hals": "medalGold",
			"ruecken": "fairyWings",
		},
		"fell": "rose",
		"drehung": -62.0,
	},
	{
		"datei": "gooby_kombi_4_bauhelm.png",
		"titel": "Bauhelm + Taucherbrille + Schal + Jetpack",
		"items":
		{
			"hut": "hut_bauhelm",
			"brille": "brille_taucher",
			"hals": "scarfRed",
			"ruecken": "ruecken_jetpack",
		},
		"fell": "fell_minze",
		"drehung": -62.0,
	},
]

## Nahaufnahmen zur Ohren-/Sitzkontrolle: Kategorie → Kameraziel. `abstand`
## negativ = Kamera steht HINTER Gooby (Rückenteile).
const KONTAKT := {
	"hut": {"ziel": Vector3(0.0, 0.72, 0.0), "abstand": 1.05},
	"brille": {"ziel": Vector3(0.0, 0.6, 0.1), "abstand": 0.9},
	"hals": {"ziel": Vector3(0.0, 0.4, 0.0), "abstand": 1.1},
	"ruecken": {"ziel": Vector3(0.0, 0.32, 0.0), "abstand": -1.3},
}

var _kontakt := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kontakt="):
			_kontakt = arg.trim_prefix("--kontakt=")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	if not _kontakt.is_empty():
		await _kontaktbogen(_kontakt)
		print("Kontaktbogen fertig → %s" % OUT_DIR)
		quit(0)
		return
	for kombi in KOMBIS:
		await _shot_kombi(kombi)
	await _shot_wardrobe()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


# ── Gooby-Kombis ─────────────────────────────────────────────────────────────


func _shot_kombi(kombi: Dictionary) -> void:
	var buehne := _buehne(Vector3(0.0, 0.62, 1.85), Vector3(0.0, 0.52, 0.0))
	var rig: GoobyRig = buehne.get_node("Gooby")
	# Dreiviertel-Ansicht: frontal sieht man von Rucksack, Flügeln und Jetpack
	# genau nichts — und die sind die Hälfte der Kombi.
	rig.rotation.y = deg_to_rad(float(kombi.get("drehung", -34.0)))
	var attach := CosmeticAttach.fuer_rig(rig)
	var map: Dictionary = (kombi["items"] as Dictionary).duplicate()
	map["fell"] = str(kombi.get("fell", ""))
	attach.apply_equipped(map)
	for _i in 30:
		await process_frame
	await _snap(str(kombi["datei"]), str(kombi["titel"]))
	buehne.queue_free()
	await process_frame


## Alle Items einer Kategorie am echten Kopf, in Reihen — damit man in EINEM
## Bild sieht, welches Teil schwebt, versinkt oder durch die Ohren geht.
func _kontaktbogen(kategorie: String) -> void:
	var defs := CosmeticsCatalog.by_kategorie(kategorie)
	var daten: Dictionary = KONTAKT.get(kategorie, KONTAKT["hut"])
	var ziel: Vector3 = daten["ziel"]
	var abstand: float = daten["abstand"]
	var seite := 0
	while seite * 6 < defs.size():
		var buehne := _buehne(ziel + Vector3(0.0, 0.1, abstand), ziel)
		var rig: GoobyRig = buehne.get_node("Gooby")
		var attach := CosmeticAttach.fuer_rig(rig)
		var namen: Array[String] = []
		for i in 6:
			var index := seite * 6 + i
			if index >= defs.size():
				break
			var def: Dictionary = defs[index]
			attach.apply_item(kategorie, str(def["id"]))
			for _f in 12:
				await process_frame
			var bild := root.get_texture().get_image()
			bild.save_png("%s/kontakt_%s_%s.png" % [OUT_DIR, kategorie, def["id"]])
			namen.append(str(def["id"]))
		print("  Kontaktbogen %s Seite %d: %s" % [kategorie, seite, ", ".join(namen)])
		buehne.queue_free()
		await process_frame
		seite += 1


# ── Wardrobe-Screen ──────────────────────────────────────────────────────────


func _shot_wardrobe() -> void:
	var gs := _fresh_gs()
	gs.set_value("economy.coins", 5000)
	CosmeticsState.apply_to_state(
		gs,
		func(slice: Dictionary, _econ: Dictionary) -> Variant:
			for id in [
				"strawHat", "topHat", "sunglasses", "heartGlasses", "scarfRed", "fairyWings"
			]:
				CosmeticsState.grant(slice, str(id), "belohnung")
			CosmeticsState.grant(slice, "caramel", "shop")
			CosmeticsState.equip(slice, "strawHat")
			CosmeticsState.equip(slice, "heartGlasses")
			CosmeticsState.equip(slice, "scarfRed")
			return null
	)
	var packed: PackedScene = load("res://scripts/cosmetics/wardrobe_screen.tscn")
	var screen: Node = packed.instantiate()
	screen.set("game_state_override", gs)
	root.add_child(screen)
	for _i in 60:
		await process_frame
	await _snap("wardrobe_hut.png", "Wardrobe – Tab Hüte")
	screen.call("tab_waehlen", "brille")
	for _i in 30:
		await process_frame
	await _snap("wardrobe_brille.png", "Wardrobe – Tab Brillen")
	screen.call("tab_waehlen", "fell")
	for _i in 30:
		await process_frame
	await _snap("wardrobe_fell.png", "Wardrobe – Tab Fell (nur im Shop kaufbar)")
	screen.queue_free()
	await process_frame
	gs.free()


# ── Gerüst ───────────────────────────────────────────────────────────────────


func _buehne(kamera_pos: Vector3, ziel: Vector3) -> Node3D:
	var buehne := Node3D.new()
	buehne.name = "Buehne"
	root.add_child(buehne)
	var rig := GoobyRig.new()
	rig.name = "Gooby"
	buehne.add_child(rig)
	var camera := Camera3D.new()
	camera.fov = 42.0
	buehne.add_child(camera)
	camera.look_at_from_position(kamera_pos, ziel, Vector3.UP)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_energy = 1.15
	buehne.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, -140.0, 0.0)
	fill.light_energy = 0.5
	buehne.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#cfe8f7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f2ead9")
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	buehne.add_child(world_env)
	return buehne


func _fresh_gs() -> Node:
	var dir := "user://cosmetics_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _snap(datei: String, titel: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, datei])
	print("  gespeichert: %s — %s" % [datei, titel])
