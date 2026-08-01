extends TestCase
## W14/UISCREENS-A — Screen-Rework-Kontrakte (pure + leichte UI-Proben):
##   1. Settings-GRUPPEN decken alle Sektions-Karten GENAU EINMAL ab, Icons
##      existieren als Dateien, Titel-Keys sind übersetzt (de-Domain).
##   2. Der Settings-Screen baut die 6 Gruppen-Header und die neue
##      „Haptik“-Zeile (game.haptik, Default AN, schreibt nach AppSettings).
##   3. Arcade-Kopfzeile trägt die Zähler-Kapsel (n spielbare Spiele).
##   4. Album-Rail-Chips kürzen lange Texte („…“) statt die Rail-Breite
##      aufzublähen (P0: Sticker liefen im Hochformat aus dem Canvas).

const SETTINGS_SCENE := preload("res://scripts/ui/settings_screen.tscn")
const ARCADE_SCENE := preload("res://scripts/minigames/arcade_screen.tscn")
const ALBUM_SCENE := preload("res://scripts/ui/album/album_screen.tscn")

## Alle Sektions-Karten, die _rebuild über die Gruppen baut (Node-Namen
## „Section<X>“ sind W1c-/RW-7-Kontrakt).
const ERWARTETE_SEKTIONEN := [
	"Allgemein",
	"Steuerung",
	"Spiel",
	"DLC",
	"Benachrichtigungen",
	"Grafik",
	"Anzeige",
	"Barrierefreiheit",
	"Audio",
	"Mehrspieler",
	"Spielstand",
	"Updates",
	"Ueber",
]

const GRUPPEN_NODES := [
	"GruppeSpiel",
	"GruppeAnzeige",
	"GruppeTon",
	"GruppeMehrspieler",
	"GruppeSpielstand",
	"GruppeInfo",
]


func _app() -> Node:
	return tree.root.get_node_or_null("/root/AppSettings")


func _mount(scene: PackedScene) -> Control:
	I18nService.set_locale("de")
	var screen: Control = scene.instantiate()
	if "auto_navigate" in screen:
		screen.set("auto_navigate", false)
	tree.root.add_child(screen)
	return screen


func _unmount(screen: Control) -> void:
	screen.get_parent().remove_child(screen)
	screen.free()


func test_gruppen_kontrakt_deckt_alle_sektionen() -> void:
	assert_eq(SettingsScreen.GRUPPEN.size(), 6, "genau 6 Gruppen (Spiel…Info)")
	var ids := {}
	var abgedeckt := {}
	for gruppe: Dictionary in SettingsScreen.GRUPPEN:
		var id := str(gruppe.get("id", ""))
		assert_false(ids.has(id), "Gruppen-Id doppelt: %s" % id)
		ids[id] = true
		var icon_path := "%s%s.svg" % [SettingsScreen.ICON_DIR, str(gruppe.get("icon", ""))]
		assert_true(ResourceLoader.exists(icon_path), "Gruppen-Icon fehlt: %s" % icon_path)
		var titel_key := str(gruppe.get("titel_key", ""))
		assert_true(I18nService.has_key(titel_key), "Gruppen-Titel fehlt: %s" % titel_key)
		for sektion: Variant in gruppe.get("sections", []):
			assert_false(abgedeckt.has(str(sektion)), "Sektion doppelt: %s" % str(sektion))
			abgedeckt[str(sektion)] = true
	assert_eq(abgedeckt.size(), ERWARTETE_SEKTIONEN.size(), "Gruppen decken alle Karten ab")
	for sektion: String in ERWARTETE_SEKTIONEN:
		assert_true(abgedeckt.has(sektion), "Sektion fehlt in den Gruppen: %s" % sektion)


func test_settings_baut_gruppen_header_und_haptik_zeile() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev: Variant = app.get_setting("game.haptik", true)
	app.set_setting("game.haptik", true)
	var screen := _mount(SETTINGS_SCENE)
	for node_name: String in GRUPPEN_NODES:
		assert_true(
			screen.find_child(node_name, true, false) != null,
			"Gruppen-Header fehlt: %s" % node_name
		)
	var row := screen.find_child("RowGameHaptik", true, false)
	assert_true(row != null, "Haptik-Zeile (game.haptik) fehlt in der Spiel-Sektion")
	if row != null:
		var toggle := row.find_child("Value", true, false) as CheckButton
		assert_true(toggle != null, "Haptik-Zeile hat einen Schalter")
		if toggle != null:
			assert_true(toggle.button_pressed, "Haptik ist per Default AN")
			toggle.button_pressed = false
			assert_false(
				bool(app.get_setting("game.haptik", true)), "Schalter schreibt game.haptik"
			)
	app.set_setting("game.haptik", prev if prev != null else true)
	_unmount(screen)


func test_arcade_kopfzeile_traegt_zaehler_kapsel() -> void:
	var screen := _mount(ARCADE_SCENE)
	await wait_frames(2)
	var label := screen.find_child("CountLabel", true, false) as Label
	assert_true(label != null, "Zähler-Kapsel in der Arcade-Kopfzeile")
	if label != null:
		var spielbar := 0
		for game: Dictionary in MinigameRegistry.all_games():
			if not bool(game.get("coming_soon", false)):
				spielbar += 1
		assert_eq(
			label.text,
			I18nService.t("mg.arcade.zaehler", {"n": spielbar}),
			"Kapsel zählt die spielbaren Spiele"
		)
	_unmount(screen)


func test_album_rail_chips_kuerzen_statt_aufzublaehen() -> void:
	# Fenster VOR dem Mount quer pinnen (Muster test_g3_wardrobe): der Album-
	# Screen kürzt Chips nur im Querformat (Hochformat wickelt die Rail um) —
	# Vorgänger-Tests dürfen kein Hochkant-Fenster hinterlassen (W17-Befund:
	# genau so kippte der Volllauf, isoliert war alles grün).
	var prev := tree.root.size
	tree.root.size = Vector2i(1280, 720)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var screen := _mount(ALBUM_SCENE)
	await wait_frames(2)
	var geprueft := 0
	for chip: Button in screen.find_children("PageChip_*", "Button", true, false):
		assert_true(chip.clip_text, "%s: clip_text nimmt Text aus der Mindestbreite" % chip.name)
		assert_eq(
			chip.text_overrun_behavior,
			TextServer.OVERRUN_TRIM_ELLIPSIS,
			"%s: langer Text wird mit … gekürzt" % chip.name
		)
		geprueft += 1
	assert_true(geprueft > 0, "mindestens ein Rail-Chip geprüft (war %d)" % geprueft)
	_unmount(screen)
	tree.root.size = prev
	tree.root.size_changed.emit()
	await wait_frames(1)
