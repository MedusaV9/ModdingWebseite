extends TestCase
## REST-4 — Fotogalerie (EVAL Rang 14): pure GalerieLogic (Index-
## Normalisierung, Favoriten, Speicheranzeige, Entfernen) und der
## GalerieScreen headless (Raster, Vollansicht + Zoomstufen, Favorit,
## Löschen inklusive PNG-Datei).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const TEST_DIR := "user://test_rest4_galerie"


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var slices_notified: Array[String] = []

	func _init() -> void:
		s = SaveSchema.default_state(1700000000000)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## ------------------------------------------------------ GalerieLogic (pur)


func test_logic_normalisiert_junk() -> void:
	var state := {
		"city":
		{
			"fotos":
			[
				{"pfad": "user://a.png", "at": 1000, "ort": "city"},
				{"pfad": "", "at": 5},
				"quatsch",
				{"pfad": "user://b.png", "at": "kein-int", "fav": true},
				{"pfad": "user://c.png", "at": 3000, "fav": "ja"},
			]
		}
	}
	var fotos := GalerieLogic.fotos_von(state)
	assert_eq(fotos.size(), 3, "Junk-Einträge fallen raus")
	assert_eq(int(fotos[1]["at"]), 0, "kaputter Zeitstempel wird 0")
	assert_true(bool(fotos[1]["fav"]), "fav=true bleibt")
	assert_false(bool(fotos[2]["fav"]), "fav muss strikt bool sein")
	assert_eq(GalerieLogic.favoriten(fotos).size(), 1)
	var speicher := GalerieLogic.speicher(state)
	assert_eq(int(speicher["n"]), 3)
	assert_eq(int(speicher["max"]), GalerieLogic.MAX_FOTOS)


func test_logic_favorit_und_entfernen() -> void:
	var state := {"city": {"fotos": [{"pfad": "user://x.png", "at": 1}]}}
	assert_true(GalerieLogic.toggle_favorit(state, "user://x.png"), "Toggle setzt fav")
	assert_true(bool(state["city"]["fotos"][0].get("fav", false)))
	assert_false(GalerieLogic.toggle_favorit(state, "user://x.png"), "Toggle löscht fav")
	assert_false((state["city"]["fotos"][0] as Dictionary).has("fav"), "Flag verschwindet")
	assert_false(GalerieLogic.toggle_favorit(state, "user://fehlt.png"), "unbekannt: false")
	assert_true(GalerieLogic.entferne(state, "user://x.png"), "Entfernen trifft")
	assert_eq((state["city"]["fotos"] as Array).size(), 0, "Index ist leer")
	assert_false(GalerieLogic.entferne(state, "user://x.png"), "zweites Entfernen: false")


func test_logic_ort_und_datum() -> void:
	assert_eq(GalerieLogic.ort_name(""), I18nService.t("galerie.ort_unbekannt"), "leer = unterwegs")
	var stadt := GalerieLogic.ort_name("funkelpark")
	assert_true(stadt.length() > 0 and stadt != "city.ort.funkelpark", "Ortsname aufgelöst")
	var datum := GalerieLogic.datum(1700000000000)
	assert_true(datum.contains("2023"), "Epoch-ms wird zum Kalenderdatum: %s" % datum)


## ------------------------------------------------------ GalerieScreen (UI)


func test_galerie_screen_raster_vollansicht_loeschen() -> void:
	var pfade := _lege_testfotos_an(2)
	var gs := FakeGameState.new()
	gs.s["city"]["fotos"] = [
		{"pfad": pfade[0], "at": 1700000000000, "ort": "city"},
		{"pfad": pfade[1], "at": 1700000100000, "ort": "funkelpark"},
	]
	var screen: GalerieScreen = load("res://scripts/ui/galerie/galerie_screen.gd").new()
	screen.gs_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	assert_eq(screen.fotos_im_raster(), 2, "beide Fotos im Raster")
	screen.oeffne_vollansicht(pfade[0])
	await wait_frames(1)
	assert_true(screen.vollansicht_offen(), "Vollansicht öffnet")
	screen._zoom_rein()
	screen._on_voll_favorit()
	assert_true(
		bool((gs.s["city"]["fotos"][0] as Dictionary).get("fav", false)),
		"Favorit aus der Vollansicht persistiert"
	)
	screen.nur_favoriten = true
	screen._refresh()
	assert_eq(screen.fotos_im_raster(), 1, "Favoriten-Filter zeigt nur das eine")
	screen.nur_favoriten = false
	screen.oeffne_vollansicht(pfade[0])
	screen._on_loeschen_bestaetigt()
	await wait_frames(1)
	assert_eq((gs.s["city"]["fotos"] as Array).size(), 1, "Index verliert das Foto")
	assert_false(
		FileAccess.file_exists(ProjectSettings.globalize_path(pfade[0])),
		"PNG-Datei ist vom Datenträger gelöscht"
	)
	assert_false(screen.vollansicht_offen(), "Vollansicht schließt nach dem Löschen")
	assert_eq(screen.fotos_im_raster(), 1, "Raster zeigt den Rest")
	screen.queue_free()
	await wait_frames(1)
	_raeume_testfotos_auf()


## Winzige echte PNGs anlegen (die Galerie lädt sie als Texturen).
func _lege_testfotos_an(anzahl: int) -> Array[String]:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var out: Array[String] = []
	for i in anzahl:
		var pfad := "%s/foto_%d.png" % [TEST_DIR, i]
		var bild := Image.create(8, 8, false, Image.FORMAT_RGB8)
		bild.fill(Color(0.2 * i, 0.5, 0.8))
		bild.save_png(pfad)
		out.append(pfad)
	return out


func _raeume_testfotos_auf() -> void:
	var absolut := ProjectSettings.globalize_path(TEST_DIR)
	var dir := DirAccess.open(absolut)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(absolut)
