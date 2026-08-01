extends TestCase
## G3/P01 SPALTE-ARCADE — Wächter für die Minigame-Rahmen-Politur:
## - Arcade-Grid liegt als W16-Inhaltsspalte (eigene Basis 880) zentriert
##   im Safe-Rechteck, Spaltenzahl rechnet mit der SPALTEN-Breite,
## - QW #3: results/pregame/arcade/pause bauen SquishButtons statt Button,
## - QW #20: Erfolgs-Grün der Results-Zeilen = AcTokens.LEAF_DARK + Autowrap,
## - QW #6: Pause-Modal blendet weich aus (logisch sofort zu),
## - QW #22: Backdrop schließt nur per LINKER Maustaste,
## - Pregame-Font-Fit gegen Quer-Überlauf (results.gd-Muster),
## - FeelStarRow skaliert Radius/Gap mit dem UiScale-Faktor.

const ARCADE_SCENE := "res://scripts/minigames/arcade_screen.tscn"
const PREGAME_SCENE := "res://scripts/minigames/pregame.tscn"
const RESULTS_SCENE := "res://scripts/minigames/results.tscn"
## QW-#3-Quellen-Wache: KEIN nackter Button.new() mehr in diesen Dateien.
const SQUISH_SOURCES: Array[String] = [
	"res://scripts/minigames/arcade_screen.gd",
	"res://scripts/minigames/pregame.gd",
	"res://scripts/minigames/results.gd",
	"res://scripts/minigames/ui/pause_modal.gd",
]

var _saved_root_size := Vector2i.ZERO


## iPad-Quer-Format (Muster test_fb3_screen_metrics): breiter Canvas, auf
## dem der 880er-Spalten-Deckel wirklich greift.
func _enter_ipad_quer() -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	UiScale.screen_scale_override = 2.0
	DisplayServer.window_set_size(Vector2i(2360, 1640))
	tree.root.size = Vector2i(2360, 1640)
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var px_per_pt := minf(canvas.x, canvas.y) / (1640.0 / 2.0)
	UiScale.insets_override = Rect2(
		0.0, 24.0 * px_per_pt, canvas.x, canvas.y - (24.0 + 20.0) * px_per_pt
	)


func _leave_format() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		DisplayServer.window_set_size(_saved_root_size)
		_saved_root_size = Vector2i.ZERO
	await wait_frames(2)


func test_arcade_grid_liegt_zentriert_in_der_inhaltsspalte() -> void:
	await _enter_ipad_quer()
	var screen: Control = (load(ARCADE_SCENE) as PackedScene).instantiate()
	screen.set("auto_navigate", false)
	tree.root.add_child(screen)
	await wait_frames(3)
	var rows: Control = screen.get("_rows")
	assert_true(rows != null, "_rows existiert")
	assert_true(
		rows.has_meta(ScreenShell.META_CONTENT_COLUMN), "Spalten-Meta-Flag gesetzt (W16-Audit)"
	)
	var m := ScreenShell.metrics(tree.root)
	var want_w := ScreenShell.content_width(m, ArcadeScreen.CONTENT_BASE_WIDTH)
	var rect := rows.get_global_rect()
	assert_almost(rect.size.x, want_w, 2.0, "Spaltenbreite = content_width(880er-Basis)")
	assert_true(
		want_w < float(m["canvas"].x) - 32.0,
		"Deckel greift auf dem breiten Canvas (Spalte schmaler als Vollbreite)"
	)
	var insets: Dictionary = m["insets"]
	var safe_center_x := (
		(float(insets["left"]) + (float(m["canvas"].x) - float(insets["right"]))) / 2.0
	)
	assert_almost(rect.get_center().x, safe_center_x, 2.0, "Spalte mittig im Safe-Rechteck")
	var grid: GridContainer = screen.get("_grid")
	assert_eq(
		grid.columns,
		ArcadeScreen.grid_columns(want_w, float(m["f"])),
		"Spaltenzahl rechnet mit der Spalten- statt Canvas-Breite"
	)
	screen.free()
	await _leave_format()


func test_minigame_rahmen_baut_squish_buttons() -> void:
	# Quellen-Wache (Muster F5): jedes Button.new() ist ein SquishButton.
	for path in SQUISH_SOURCES:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_true(file != null, "%s lesbar" % path)
		if file == null:
			continue
		var src := file.get_as_text()
		var nackte := src.count("Button.new()") - src.count("SquishButton.new()")
		assert_eq(nackte, 0, "%s: kein nacktes Button.new() (QW #3)" % path)
	# Laufzeit-Stichprobe: Arcade-Zurück + Kacheln sind SquishButtons.
	var screen: Control = (load(ARCADE_SCENE) as PackedScene).instantiate()
	screen.set("auto_navigate", false)
	tree.root.add_child(screen)
	await wait_frames(2)
	assert_true(screen.get("_back") is SquishButton, "Arcade-Zurück squisht")
	var grid: GridContainer = screen.get("_grid")
	assert_true(grid.get_child_count() > 0 and grid.get_child(0) is SquishButton, "Kachel squisht")
	screen.free()
	await wait_frames(1)


func test_results_zeilen_brechen_um_und_gruen_ist_token() -> void:
	var screen: MinigameResults = (load(RESULTS_SCENE) as PackedScene).instantiate()
	tree.root.add_child(screen)
	await wait_frames(1)
	screen.show_results(
		{"score": 42, "coins": 5, "best": 99, "xp": 7, "beatTarget": true, "dayCapReached": true},
		{"title_key": "mg.teaParty.title"}
	)
	await wait_frames(2)
	assert_true(screen.get("_again") is SquishButton, "Nochmal-Knopf squisht")
	assert_true(screen.get("_back") is SquishButton, "Zurück-Knopf squisht")
	var rows: VBoxContainer = screen.get("_rows")
	var xp_text := I18nService.t("mg.results.xp", {"xp": 7})
	var ziel_text := I18nService.t("mg.results.beat_target")
	var cap_text := I18nService.t("mg.results.day_cap")
	var gefunden := 0
	for child in rows.get_children():
		if not (child is Label):
			continue
		var label := child as Label
		if label.text == xp_text or label.text == ziel_text:
			gefunden += 1
			assert_eq(
				label.get_theme_color("font_color"),
				AcTokens.LEAF_DARK,
				"Erfolgs-Grün ist Token (QW #20): %s" % label.text
			)
		if label.text == xp_text or label.text == ziel_text or label.text == cap_text:
			assert_eq(
				label.autowrap_mode,
				TextServer.AUTOWRAP_WORD_SMART,
				"dynamische Zeile bricht um: %s" % label.text
			)
	assert_eq(gefunden, 2, "XP- und Ziel-Zeile gefunden")
	screen.free()
	await wait_frames(1)


func test_pause_modal_blendet_weich_aus() -> void:
	# Fade setzt Motion voraus — Reduced-Motion defensiv AUS (und zurück).
	var theme_svc := tree.root.get_node_or_null("/root/UiTheme")
	var rm_vorher: bool = theme_svc.reduced_motion if theme_svc != null else false
	if theme_svc != null:
		theme_svc.reduced_motion = false
	var modal := MinigamePauseModal.new()
	tree.root.add_child(modal)
	await wait_frames(1)
	modal.open()
	await wait_frames(2)
	assert_true(modal.is_open(), "Modal offen")
	modal.hide_modal()
	# Logisch sofort zu (Host darf sofort weitermachen) …
	assert_false(modal.is_open(), "logisch sofort geschlossen")
	assert_eq(int(modal.mouse_filter), int(Control.MOUSE_FILTER_IGNORE), "frisst keine Taps mehr")
	# … optisch klingt der Fade nach (QW #6) und endet unsichtbar.
	assert_true(modal.visible, "Fade läuft noch (nicht hart geschaltet)")
	var weg := await wait_until(func() -> bool: return not modal.visible, 2000)
	assert_true(weg, "nach dem Fade unsichtbar")
	var card: Control = modal.get("_card")
	assert_almost(card.modulate.a, 1.0, 0.001, "Karte für den nächsten open() zurückgesetzt")
	# Wieder öffnen während/nach Fade funktioniert sauber.
	modal.open()
	await wait_frames(2)
	assert_true(modal.is_open() and modal.visible, "erneutes Öffnen funktioniert")
	modal.hide_modal()
	if theme_svc != null:
		theme_svc.reduced_motion = rm_vorher
	modal.free()
	await wait_frames(1)


func test_pause_backdrop_schliesst_nur_per_linksklick() -> void:
	var modal := MinigamePauseModal.new()
	tree.root.add_child(modal)
	await wait_frames(1)
	modal.open()
	await wait_frames(1)
	var rechts := InputEventMouseButton.new()
	rechts.pressed = true
	rechts.button_index = MOUSE_BUTTON_RIGHT
	modal._on_backdrop_input(rechts)
	assert_true(modal.is_open(), "Rechtsklick schließt NICHT (QW #22)")
	var mitte := InputEventMouseButton.new()
	mitte.pressed = true
	mitte.button_index = MOUSE_BUTTON_MIDDLE
	modal._on_backdrop_input(mitte)
	assert_true(modal.is_open(), "Mittelklick schließt NICHT (QW #22)")
	var links := InputEventMouseButton.new()
	links.pressed = true
	links.button_index = MOUSE_BUTTON_LEFT
	modal._on_backdrop_input(links)
	assert_false(modal.is_open(), "Linksklick schließt (Fortsetzen)")
	modal.free()
	await wait_frames(1)


func test_pregame_schrumpft_schriften_bei_ueberlauf() -> void:
	# f künstlich > 1 heben (headless wäre f=1 und der Fit hätte nichts zu
	# tun), dann die Karte gezielt überfüllen (Stellvertreter für
	# CarLine + ModifierBanner + Endlos + Dance-Sektion im Quer-Format):
	# der neue Fit-Pass (results.gd-Muster) muss die Schriften
	# zurückschrumpfen, nachdem der Cover-Schrumpf nicht mehr reicht.
	UiScale.user_factor = 1.6
	var screen: Control = (load(PREGAME_SCENE) as PackedScene).instantiate()
	screen.set("auto_navigate", false)
	screen.call("receive_params", {"game_id": "teaParty"})
	tree.root.add_child(screen)
	await wait_frames(2)
	var card: Control = screen.get("_card")
	var titel: Label = null
	for node in card.find_children("*", "Label", true, false):
		if (node as Label).theme_type_variation == &"TitleLabel":
			titel = node
			break
	assert_true(titel != null, "Titel-Label gefunden")
	var vorher := titel.get_theme_font_size("font_size")
	var rows: VBoxContainer = card.get_child(0)
	var fueller := Control.new()
	fueller.custom_minimum_size = Vector2(0.0, 400.0)
	rows.add_child(fueller)
	screen.call("_apply_touch_floor")
	await wait_frames(1)
	var nachher := titel.get_theme_font_size("font_size")
	assert_true(
		nachher < vorher, "Fit-Pass schrumpft Schriften bei Überlauf (%d → %d)" % [vorher, nachher]
	)
	var cover: Control = screen.get("_cover")
	assert_false(cover.visible, "Cover weicht ZUERST (bestehende Regel bleibt)")
	UiScale.user_factor = 1.0
	screen.free()
	await wait_frames(1)


func test_star_row_skaliert_mit_ui_faktor() -> void:
	var basis := float(FeelStarRow.SLOTS) * (FeelStarRow.STAR_RADIUS * 2.0 + FeelStarRow.GAP)
	UiScale.user_factor = 1.5
	var stars := FeelStarRow.new()
	tree.root.add_child(stars)
	await wait_frames(1)
	var f := UiScale.for_viewport(tree.root)
	assert_true(f > 1.0, "Testfaktor wirkt (f=%.2f)" % f)
	assert_almost(
		stars.custom_minimum_size.x, basis * f, 0.5, "Sterne-Reihe skaliert Radius/Gap mit f"
	)
	UiScale.user_factor = 1.0
	stars.free()
	await wait_frames(1)
