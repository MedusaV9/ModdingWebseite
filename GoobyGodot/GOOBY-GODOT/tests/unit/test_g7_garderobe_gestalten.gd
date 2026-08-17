extends TestCase
## G7-P54 GARDEROBE + GESTALTEN POLIEREN — Wachen für das User-Feedback
## (echte iPhone-Screenshots, Leitformat iPhone 17 Pro Max quer):
## - Gestalten: Kategorie-Liste scrollt MIT Affordance (ScrollFade-Kante),
##   der letzte Eintrag steht am Scroll-Ende voll sichtbar über dem
##   Boden-Polster (kein „Briefkasten halb abgeschnitten“ mehr).
## - Touch-Floors: Kategorie-Zeilen, Raum-Chips und Farb-Swatches halten
##   das physische Minimum (ScreenShell floor_px ≥ 44 pt).
## - Garderobe: Grid-Fade existiert, die Scrollbar hat Rand-Abstand > 0
##   (klebte am äußersten Display-Rand), Kauf-Flow-Smoke mit Feedback-
##   Verdrahtung (ui_buy + Sparkle bzw. ui_error + Kopfschütteln).
## - Formate gepinnt: quer 2868×1320 @3× und hoch 1179×2556 @3×
##   (Muster test_g4_nachfix: screen_scale_override + insets_override).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const WardrobeSzene := preload("res://scripts/cosmetics/wardrobe_screen.tscn")
const WARDROBE_SRC := "res://scripts/cosmetics/wardrobe_screen.gd"
const CUSTOMIZE_SRC := "res://scripts/home/customize/customize_screen.gd"

## Leitformat iPhone 17 Pro Max: Fenster-px, @3×, Insets [l, t, r, b] in pt.
const QUER_FENSTER := Vector2i(2868, 1320)
const QUER_INSETS_PT: Array = [62.0, 0.0, 62.0, 21.0]
const HOCH_FENSTER := Vector2i(1179, 2556)
const HOCH_INSETS_PT: Array = [0.0, 59.0, 0.0, 34.0]
const IPHONE_SCALE := 3.0

var _root_size := Vector2i.ZERO
var _user_factor := 1.0
var _text_factor := 1.0
var _extra_inset := 0.0
var _dir_seq := 0


## Fenster + UiScale-Statics VOR dem Screen-Bau pinnen und am Testende
## zurückstellen (deterministisch, Muster test_g4_nachfix._pin).
func _pin(fenster: Vector2i, scale: float, insets_pt: Array) -> void:
	_root_size = tree.root.size
	_user_factor = UiScale.user_factor
	_text_factor = UiScale.text_factor
	_extra_inset = UiScale.extra_inset
	UiScale.user_factor = 1.0
	UiScale.text_factor = 1.0
	UiScale.extra_inset = 0.0
	UiScale.screen_scale_override = scale
	tree.root.size = fenster
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var pt_kurz := minf(float(fenster.x), float(fenster.y)) / scale
	var px_pt := minf(canvas.x, canvas.y) / pt_kurz
	var l := float(insets_pt[0]) * px_pt
	var t := float(insets_pt[1]) * px_pt
	var r := float(insets_pt[2]) * px_pt
	var b := float(insets_pt[3]) * px_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)


func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	UiScale.user_factor = _user_factor
	UiScale.text_factor = _text_factor
	UiScale.extra_inset = _extra_inset
	tree.root.size = _root_size


func _frisches_gs(coins := 1000) -> Node:
	HomeState.register_slice()
	_dir_seq += 1
	var dir := "user://g7_garderobe_tests/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


func _customize(gs: Node) -> CustomizeScreen:
	var screen := CustomizeScreen.new()
	screen.auto_navigate = false
	screen.game_state_override = gs
	tree.root.add_child(screen)
	return screen


func _wardrobe(gs: Node) -> Node:
	var screen: Node = WardrobeSzene.instantiate()
	screen.set("game_state_override", gs)
	screen.set("auto_navigate", false)
	tree.root.add_child(screen)
	return screen


func _drop(screen: Node, gs: Node) -> void:
	screen.queue_free()
	await wait_frames(2)
	gs.free()


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


## ---------------------------------------------------------- Gestalten


func test_gestalten_kategorien_scrollen_mit_affordance() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	var gs := _frisches_gs()
	var screen := _customize(gs)
	await wait_frames(3)
	var fade := screen.find_child("KategorieFade", true, false) as ScrollFade
	assert_true(fade != null, "Kategorie-Liste hat den ScrollFade-Affordance-Knoten")
	assert_true(screen.find_child("FadeUnten", true, false) != null, "Fade-Unten-Kante existiert")
	var scroll := screen.find_child("KategorieScroll", true, false) as ScrollContainer
	var bar := scroll.get_v_scroll_bar()
	assert_true(
		bar.max_value - bar.page > 1.0,
		"Liste läuft im Leitformat über (sonst prüft der Test nichts)"
	)
	assert_true(fade.unten_aktiv(), "am Listenanfang lädt die Unten-Kante zum Scrollen ein")
	# Ans Ende scrollen: der LETZTE Eintrag (zaun) steht VOLL sichtbar und
	# frei über dem Boden-Polster — nicht mehr hart halbiert.
	scroll.scroll_vertical = int(bar.max_value)
	await wait_frames(2)
	assert_false(fade.unten_aktiv(), "am Listenende verschwindet die Unten-Kante")
	var letzter := screen.find_child("Kat_zaun", true, false) as Control
	assert_true(letzter != null, "letzter Kategorie-Knopf existiert")
	var luft := scroll.get_global_rect().end.y - letzter.get_global_rect().end.y
	assert_true(luft >= 8.0, "letzter Eintrag voll sichtbar mit Luft unten (%.1f px)" % luft)
	var polster := screen.get("_kat_polster") as MarginContainer
	assert_true(
		polster.get_theme_constant("margin_bottom") > 0, "Boden-Polster unter der Liste aktiv"
	)
	await _drop(screen, gs)
	_unpin()


func test_gestalten_zeilen_chips_swatches_halten_touch_floor() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	var gs := _frisches_gs()
	var screen := _customize(gs)
	await wait_frames(3)
	var m := ScreenShell.metrics(screen.get_viewport())
	var floor_px: float = m["floor_px"]
	var liste := screen.find_child("KategorieListe", true, false)
	for kind in liste.get_children():
		if kind is Button:
			assert_true(
				(kind as Button).custom_minimum_size.y >= floor_px - 0.6,
				"Kategorie-Zeile %s hält den Touch-Floor" % kind.name
			)
	for chip in (screen.find_child("RaumChips", true, false) as Control).get_children():
		var mindest := (chip as Control).custom_minimum_size
		assert_true(
			mindest.x >= floor_px - 0.6 and mindest.y >= floor_px - 0.6,
			"Raum-Chip %s hält den Touch-Floor auf beiden Achsen" % chip.name
		)
	screen.set_kategorie("fassade")
	await wait_frames(1)
	var swatch := screen.find_child("Farbe_rose", true, false) as Control
	assert_true(swatch != null, "Fassade zeigt Palette-Swatches")
	assert_true(
		(
			swatch.custom_minimum_size.x >= floor_px - 0.6
			and swatch.custom_minimum_size.y >= floor_px - 0.6
		),
		"Swatch hält den physischen Touch-Floor"
	)
	await _drop(screen, gs)
	_unpin()


## ---------------------------------------------------------- Garderobe


func test_garderobe_scrollbar_randabstand_und_grid_fade() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	var gs := _frisches_gs()
	var screen := _wardrobe(gs)
	await wait_frames(3)
	var fade := screen.get("_grid_fade") as ScrollFade
	assert_true(fade != null, "Garderoben-Grid hat den ScrollFade-Affordance-Knoten")
	assert_true(
		fade.get_theme_constant("margin_right") > 0, "Scrollbar-Rand-Inset ist gesetzt (> 0)"
	)
	var scroll := screen.get("_grid_scroll") as ScrollContainer
	var bar := scroll.get_v_scroll_bar()
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var abstand := canvas.x - bar.get_global_rect().end.x
	assert_true(abstand >= 1.0, "Scrollbar klebt nicht am Display-Rand (Abstand %.1f px)" % abstand)
	var huellen_abstand := fade.get_global_rect().end.x - bar.get_global_rect().end.x
	assert_true(
		huellen_abstand >= 1.0,
		"Scrollbar sitzt eingerückt in der Spalte (Inset %.1f px)" % huellen_abstand
	)
	var polster := screen.get("_grid_polster") as MarginContainer
	assert_true(polster.get_theme_constant("margin_bottom") > 0, "Grid hat Boden-Polster")
	# Läuft das Grid über, lädt die Fade-Kante ein; am Ende verschwindet sie.
	if bar.max_value - bar.page > 1.0:
		assert_true(fade.unten_aktiv(), "überlaufendes Grid zeigt die Unten-Kante")
		scroll.scroll_vertical = int(bar.max_value)
		await wait_frames(2)
		assert_false(fade.unten_aktiv(), "am Grid-Ende verschwindet die Unten-Kante")
	await _drop(screen, gs)
	_unpin()


func test_garderobe_kauf_flow_smoke_mit_feedback() -> void:
	var gs := _frisches_gs(5000)
	var screen := _wardrobe(gs)
	await wait_frames(2)
	screen.call("tab_waehlen", "hut")
	var id := _erstes_kaufbares("hut")
	assert_false(id.is_empty(), "es gibt einen kaufbaren Hut zum Testen")
	var preis := int(CosmeticsCatalog.by_id(id)["preis"])
	var kauf: Dictionary = screen.call("item_tippen", id)
	assert_true(bool(kauf.get("gekauft", false)), "genug Münzen: gekauft")
	assert_eq(int(gs.get_value("economy.coins", 0)), 5000 - preis, "Preis abgebucht")
	await _drop(screen, gs)

	# Pleite-Fall: kein Kauf, KEIN Abzug, Fehler-Feedback verdrahtet.
	var gs_pleite := _frisches_gs(0)
	var screen_pleite := _wardrobe(gs_pleite)
	await wait_frames(2)
	screen_pleite.call("tab_waehlen", "hut")
	var fehl: Dictionary = screen_pleite.call("item_tippen", id)
	assert_false(bool(fehl.get("ok", true)), "pleite: kein Kauf")
	assert_eq(str(fehl.get("grund", "")), "zu_teuer", "Grund benannt")
	assert_eq(int(gs_pleite.get_value("economy.coins", 0)), 0, "kein Münz-Abzug")
	await _drop(screen_pleite, gs_pleite)

	# Feedback-Verdrahtung als Quelltext-Wächter (Muster F5/test_g3):
	# Kauf klingt als ui_buy + Sparkle, „zu teuer“ als ui_error + Schütteln.
	var quelle := _source(WARDROBE_SRC)
	assert_true(quelle.contains('try_play(self, "ui_buy")'), "Kauf-Outcome = ui_buy")
	assert_true(quelle.contains("UiMotion.sparkle("), "Kauf feiert mit Sparkle (RM-Gate intern)")
	assert_true(quelle.contains('try_play(self, "ui_error")'), "Fehl-Outcome = ui_error")
	assert_true(quelle.contains("_kopfschuetteln("), "zu teuer schüttelt die Karte")
	var gestalten := _source(CUSTOMIZE_SRC)
	assert_true(gestalten.contains("UiMotion.bounce("), "Gestalten: Swatch-Mini-Pop verdrahtet")
	assert_true(gestalten.contains("wackeln()"), "Gestalten: Zufalls-Wackler verdrahtet")


## ---------------------------------------------------------- Leitformate


func test_leitformat_quer_2868x1320() -> void:
	await _pin(QUER_FENSTER, IPHONE_SCALE, QUER_INSETS_PT)
	var gs := _frisches_gs()
	var screen := _wardrobe(gs)
	await wait_frames(3)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var m := ScreenShell.metrics(screen.get_viewport())
	var rows := screen.get("_rows") as Control
	var spalte := ScreenShell.content_width(m, WardrobeScreen.SPALTE_BASIS)
	assert_true(rows.size.x <= spalte + 0.6, "Garderobe: Spalte gedeckelt")
	assert_almost(
		rows.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Garderobe: Spalte mittig"
	)
	assert_false((screen.get("_split") as BoxContainer).vertical, "quer: Zwei-Spalten-Teilung")
	var grid := screen.get("_grid") as GridContainer
	assert_true(grid.columns >= 1 and grid.columns <= 5, "Grid-Spalten plausibel")
	await _drop(screen, gs)

	var gs2 := _frisches_gs()
	var gestalten := _customize(gs2)
	await wait_frames(3)
	var g_rows := gestalten.get("_rows_box") as Control
	var g_spalte := ScreenShell.content_width(m, CustomizeScreen.SPALTE_BASIS)
	assert_true(g_rows.size.x <= g_spalte + 0.6, "Gestalten: Spalte gedeckelt")
	assert_almost(
		g_rows.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Gestalten: Spalte mittig"
	)
	# Innen-Kategorie (Raum-Chips sichtbar): darf laut FB3-Design scrollen,
	# aber NUR mit Affordance — und am Scroll-Ende stehen die Aktionen voll
	# sichtbar im Canvas (nichts bleibt unerreichbar abgeschnitten).
	var rechts := gestalten.find_child("RechteSpalteScroll", true, false) as ScrollContainer
	var rbar := rechts.get_v_scroll_bar()
	if rbar.max_value - rbar.page > 1.0:
		assert_true(
			gestalten.find_child("RechteSpalteFade", true, false) != null,
			"überlaufende rechte Spalte hat die Fade-Affordance"
		)
		rechts.scroll_vertical = int(rbar.max_value)
		await wait_frames(2)
	var kauf := gestalten.find_child("ZufallButton", true, false) as Control
	assert_true(
		kauf.get_global_rect().end.y <= canvas.y + 0.6,
		"Aktions-Zeile (nach evtl. Scroll) voll im Canvas"
	)
	# Haus-Kategorie (ohne Chips) MUSS ohne Scrollen komplett passen — das
	# wacht über den Kachel-Deckel-Fix (Options-Zeile fraß 221 statt 150 px).
	gestalten.set_kategorie("fassade")
	await wait_frames(2)
	assert_true(rbar.max_value - rbar.page <= 1.0, "Haus-Kategorie passt quer ohne Spalten-Scroll")
	assert_true(
		kauf.get_global_rect().end.y <= canvas.y + 0.6, "Aktions-Zeile ohne Scroll im Canvas"
	)
	await _drop(gestalten, gs2)
	_unpin()


func test_leitformat_hoch_1179x2556() -> void:
	await _pin(HOCH_FENSTER, IPHONE_SCALE, HOCH_INSETS_PT)
	var gs := _frisches_gs()
	var screen := _wardrobe(gs)
	await wait_frames(3)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	assert_true((screen.get("_split") as BoxContainer).vertical, "hoch: Stapel-Layout")
	assert_true((screen.get("_grid") as GridContainer).columns >= 3, "hoch: >= 3 Grid-Spalten")
	var rows := screen.get("_rows") as Control
	assert_almost(
		rows.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Garderobe hoch: mittig"
	)
	await _drop(screen, gs)

	var gs2 := _frisches_gs()
	var gestalten := _customize(gs2)
	await wait_frames(3)
	var g_rows := gestalten.get("_rows_box") as Control
	assert_almost(
		g_rows.get_global_rect().get_center().x, canvas.x / 2.0, 1.0, "Gestalten hoch: mittig"
	)
	await _drop(gestalten, gs2)
	_unpin()
