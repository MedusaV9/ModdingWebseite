extends TestCase
## G3 P03 SPALTE-WARDROBE — Garderobe + Gestalten auf der Inhaltsspalte:
## zentrierte, breiten-gedeckelte Wurzel-Container (eigene Grid-Basis 920),
## Hochformat-Stapel der Garderobe (Bühne oben, Grid unten, ≥3 Spalten),
## Scroll-Sprung-Fix (Antippen baut das Grid NICHT mehr neu, Karten werden
## in-place aufgefrischt) und die Audio-Grammatik-Verdrahtung als
## Quelltext-Wächter (Muster F5 der Sound-Fixliste).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const WardrobeSzene := preload("res://scripts/cosmetics/wardrobe_screen.tscn")
const WARDROBE_SRC := "res://scripts/cosmetics/wardrobe_screen.gd"
const CUSTOMIZE_SRC := "res://scripts/home/customize/customize_screen.gd"


func test_wardrobe_liegt_auf_der_inhaltsspalte() -> void:
	# Fenster VOR dem Screen-Bau pinnen: im Voll-Runner kann ein Vorgänger-
	# Test das Fenster verstellt haben, und headless übernimmt das Window
	# eine neue Größe erst im Folge-Frame — ein Pin NACH dem Bau ließ Layout
	# (alter Stand, 936 px/Mitte 648) und Messung (neuer Stand, 920/640)
	# auseinanderlaufen (W16-Befund). Vorher pinnen = ein gemeinsamer Stand.
	var vorher: Vector2i = tree.root.size
	tree.root.size = Vector2i(1280, 720)
	await wait_frames(2)
	var screen := await _wardrobe()
	await wait_frames(1)
	var rows: Control = screen.get("_rows")
	assert_true(
		rows.has_meta(ScreenShell.META_CONTENT_COLUMN), "Garderobe trägt das W16-Spalten-Meta"
	)
	var m := ScreenShell.metrics(screen.get_viewport())
	var spalte := ScreenShell.content_width(m, WardrobeScreen.SPALTE_BASIS)
	assert_true(
		rows.size.x <= spalte + 0.6, "Spalte gedeckelt: %.1f <= %.1f" % [rows.size.x, spalte]
	)
	var canvas: Vector2 = m["canvas"]
	assert_almost(rows.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Spalte sitzt mittig")
	tree.root.size = vorher
	await wait_frames(1)
	_aufraeumen(screen)


func test_wardrobe_stapelt_im_hochformat() -> void:
	var screen := await _wardrobe()
	var vorher: Vector2i = tree.root.size
	tree.root.size = Vector2i(720, 1280)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var split: BoxContainer = screen.get("_split")
	assert_true(split.vertical, "hochkant: Split stapelt vertikal (Bühne oben, Grid unten)")
	var saeule: Control = screen.get("_saeule_links")
	assert_true(saeule.custom_minimum_size.y > 0.0, "Bühne bekommt ein festes Höhenbudget")
	assert_eq(saeule.custom_minimum_size.x, 0.0, "…und keine feste Breite (volle Spalte)")
	var grid: GridContainer = screen.get("_grid")
	assert_true(grid.columns >= 3, "Grid hochkant mit >=3 Spalten (ist %d)" % grid.columns)
	tree.root.size = vorher
	tree.root.size_changed.emit()
	await wait_frames(2)
	assert_false(split.vertical, "quer wieder nebeneinander")
	assert_true(saeule.custom_minimum_size.x > 0.0, "quer: Bühne hat wieder feste Breite")
	_aufraeumen(screen)


func test_tap_baut_grid_nicht_neu_und_frischt_karten_auf() -> void:
	var screen := await _wardrobe(5000)
	screen.call("tab_waehlen", "hut")
	await wait_frames(1)
	var grid: GridContainer = screen.get("_grid")
	var kinder_vorher := grid.get_children()
	var id := _erstes_kaufbares("hut")
	assert_false(id.is_empty(), "es gibt einen kaufbaren Hut zum Testen")

	var kauf: Dictionary = screen.call("item_tippen", id)
	assert_true(bool(kauf["ok"]), "Tap kauft: %s" % str(kauf.get("grund", "")))
	var kinder_nachher := grid.get_children()
	assert_eq(kinder_nachher.size(), kinder_vorher.size(), "gleich viele Karten")
	var identisch := kinder_nachher.size() == kinder_vorher.size()
	for i in kinder_vorher.size():
		if i < kinder_nachher.size() and kinder_vorher[i] != kinder_nachher[i]:
			identisch = false
	assert_true(identisch, "Karten bleiben dieselben Instanzen (kein Rebuild = kein Scroll-Sprung)")

	var ui: Dictionary = screen.get("_karten_ui")
	var status: Label = (ui[id] as Dictionary)["status"]
	assert_eq(status.text, I18nService.t("wardrobe.angelegt"), "Status in-place: angelegt")
	var rahmen: PanelContainer = (ui[id] as Dictionary)["rahmen"]
	var stil := rahmen.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(stil.border_color, AcTokens.LEAF, "Angelegt-Border in-place")

	screen.call("item_tippen", id)
	assert_eq(status.text, I18nService.t("wardrobe.besessen"), "Ablegen in-place: besessen")
	_aufraeumen(screen)


func test_customize_liegt_auf_der_inhaltsspalte() -> void:
	HomeState.register_slice()
	# Fenster VOR dem Screen-Bau pinnen (gleicher Schutz wie bei der
	# Garderobe, s. o. — headless übernimmt Window-Größen erst im Folge-Frame).
	var vorher: Vector2i = tree.root.size
	tree.root.size = Vector2i(1280, 720)
	await wait_frames(2)
	var dir := "user://g3_wardrobe_tests/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	var screen := CustomizeScreen.new()
	screen.auto_navigate = false
	screen.game_state_override = gs
	tree.root.add_child(screen)
	await wait_frames(2)
	var rows: Control = screen.get("_rows_box")
	assert_true(
		rows.has_meta(ScreenShell.META_CONTENT_COLUMN), "Gestalten trägt das W16-Spalten-Meta"
	)
	var m := ScreenShell.metrics(screen.get_viewport())
	var spalte := ScreenShell.content_width(m, CustomizeScreen.SPALTE_BASIS)
	assert_true(
		rows.size.x <= spalte + 0.6, "Spalte gedeckelt: %.1f <= %.1f" % [rows.size.x, spalte]
	)
	var canvas: Vector2 = m["canvas"]
	assert_almost(rows.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Spalte sitzt mittig")
	var kat: Control = screen.get("_kat_spalte")
	assert_true(
		kat.custom_minimum_size.x <= spalte * 0.3 + 0.6,
		"Kategorie-Spalte bezieht ihr Budget aus der Spaltenbreite"
	)
	tree.root.size = vorher
	await wait_frames(1)
	screen.free()
	gs.free()


func test_sound_grammatik_verdrahtung() -> void:
	# Quelltext-Wächter (Muster F5): richtige SfxMap-Ids, Momente-Haptik,
	# keine Button.new()-Rückfälle, keine manuelle Tap-Haptik.
	var wardrobe := _source(WARDROBE_SRC)
	assert_false(wardrobe.is_empty(), "wardrobe_screen.gd lesbar")
	assert_true(wardrobe.contains('try_play(self, "ui_chip")'), "Tabs klingen als ui_chip")
	assert_true(wardrobe.contains('try_play(self, "ui_back")'), "Zurück klingt als ui_back")
	assert_true(wardrobe.contains('try_play(self, "ui_buy")'), "Kauf-Outcome = ui_buy")
	assert_true(wardrobe.contains('try_play(self, "ui_error")'), "Fehl-Outcome = ui_error")
	assert_true(wardrobe.contains("Haptics.success(self)"), "Kauf-Erfolg mit Erfolgs-Haptik")
	assert_false(wardrobe.contains("= Button.new()"), "Garderobe: nur SquishButton")
	assert_false(wardrobe.contains("Haptics.tap("), "Tap-Haptik kommt zentral vom SquishButton")

	var customize := _source(CUSTOMIZE_SRC)
	assert_false(customize.is_empty(), "customize_screen.gd lesbar")
	assert_true(customize.contains('try_play(self, "ui_buy")'), "Kauf-Outcome = ui_buy")
	assert_false(customize.contains('"ui_confirm"'), "Münz-Ausgabe klingt nicht als confirm")
	assert_true(customize.contains('try_play(self, "ui_tick")'), "Hausnummer-Stepper = ui_tick")
	assert_true(customize.contains('try_play(self, "ui_error")'), "Fehl-Outcome = ui_error")
	assert_true(customize.contains("Haptics.success(self)"), "Kauf-Erfolg mit Erfolgs-Haptik")
	assert_false(customize.contains("= Button.new()"), "Gestalten: nur SquishButton")
	assert_false(customize.contains("Haptics.tap("), "Tap-Haptik kommt zentral vom SquishButton")


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _erstes_kaufbares(kategorie: String) -> String:
	for def: Dictionary in CosmeticsCatalog.by_kategorie(kategorie):
		if not def["standard"] and int(def["preis"]) > 0 and int(def["min_level"]) <= 1:
			return str(def["id"])
	return ""


func _wardrobe(coins := 1000) -> Node:
	var dir := "user://g3_wardrobe_tests/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	var screen: Node = WardrobeSzene.instantiate()
	screen.set("game_state_override", gs)
	screen.set("auto_navigate", false)
	screen.set_meta("gs", gs)
	tree.root.add_child(screen)
	await tree.process_frame
	return screen


func _aufraeumen(screen: Node) -> void:
	var gs: Variant = screen.get_meta("gs")
	tree.root.remove_child(screen)
	screen.queue_free()
	if gs is Node:
		(gs as Node).free()
