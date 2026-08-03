extends TestCase
## G3 P02 SPALTE-IKEA — die Möbelausstellung auf der Inhaltsspalte W16:
## zentrierte, breiten-gedeckelte Spalte (eigene Grid-Basis 880), der
## Portrait-Reflow (Body stapelt 1-spaltig: Vitrine oben, Liste darunter),
## der Kauf-Sound nach Audio-Grammatik (F3) und der Titel-Verwechslungs-Fix
## („GOUHBUS“ ≈ Doktor „GOOUHBUS“ — texte-Grenzfall 1).

const QUER := Vector2i(1280, 800)
const HOCH := Vector2i(800, 1280)
## PT2-B6: Leitformat der G8-Playtests (2868×1320 quer) — hier lag der
## Kaufen-Knopf am Scroller-Ende unterm Falz.
const LEIT_QUER := Vector2i(2868, 1320)
const SCREEN_QUELLE := "res://scripts/shop/ikea_screen.gd"

var _root_size := Vector2i.ZERO


func _mount(window: Vector2i) -> IkeaScreen:
	_root_size = tree.root.size
	tree.root.size = window
	var screen := IkeaScreen.new()
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	screen.showcase().set_spin_enabled(false)
	return screen


func _drop(screen: IkeaScreen) -> void:
	screen.queue_free()
	await wait_frames(2)
	tree.root.size = _root_size


func test_inhaltsspalte_mittig_und_gedeckelt() -> void:
	var screen := await _mount(QUER)
	var rows := screen.get("_rows_box") as Control
	assert_true(rows != null, "_rows_box existiert")
	assert_true(
		rows.has_meta(ScreenShell.META_CONTENT_COLUMN),
		"Spalten-Container trägt das W16-Meta-Flag (FB3-Audit-Vertrag)"
	)
	var m := ScreenShell.metrics(screen.get_viewport())
	var spalte := ScreenShell.content_width(m, IkeaScreen.GRID_BASE)
	var rect := rows.get_global_rect()
	assert_almost(rect.size.x, spalte, 1.0, "Spaltenbreite = content_width(880er-Basis)")
	var canvas := Vector2(screen.get_viewport().get_visible_rect().size)
	assert_almost(
		rect.get_center().x, canvas.x / 2.0, 2.0, "Spalte sitzt mittig (headless: Safe = Canvas)"
	)
	var body := screen.get("_body") as BoxContainer
	assert_false(body.vertical, "Querformat = 2 Spalten nebeneinander")
	assert_true(body.get_child(0) == screen.get("_left_column"), "Querformat: Liste steht links")
	await _drop(screen)


func test_portrait_reflow_stapelt_einspaltig_und_zurueck() -> void:
	var screen := await _mount(HOCH)
	var body := screen.get("_body") as BoxContainer
	assert_true(body.vertical, "Hochformat: Body stapelt vertikal")
	# PT2-B6: die rechte Spalte heißt jetzt DetailColumn (Scroller + Kauf-
	# Footer) — im Stapel steht sie weiterhin oben.
	assert_eq(String(body.get_child(0).name), "DetailColumn", "Hochformat: Vitrine + Details oben")
	var left := screen.get("_left_column") as Control
	assert_eq(left.custom_minimum_size.x, 0.0, "Liste nimmt im Stapel die volle Spaltenbreite")
	assert_true(
		left.size_flags_vertical & Control.SIZE_EXPAND != 0,
		"Liste bekommt im Stapel einen Höhen-Anteil"
	)
	# Rotation zurück: der Metrik-Pass muss das 2-Spalten-Layout wiederherstellen.
	tree.root.size = QUER
	await wait_frames(2)
	assert_false(body.vertical, "zurück im Querformat: 2 Spalten")
	assert_true(body.get_child(0) == left, "zurück im Querformat: Liste wieder links")
	assert_true(left.custom_minimum_size.x > 0.0, "Listen-Mindestbreite wieder gesetzt")
	await _drop(screen)


func test_kaufzeile_ist_sticky_footer_im_leitformat() -> void:
	# PT2-B6: Im Leitformat quer (2868×1320) lag der Kaufen-Knopf am Ende
	# des DetailScroll-Inhalts unterm Falz (pt2_b1/047: Tap ins Leere).
	# Jetzt wohnt die Kaufzeile AUSSERHALB des Scrollers und ist ohne
	# Scrollen komplett im Canvas.
	var screen := await _mount(LEIT_QUER)
	await wait_frames(2)
	var buy := screen.find_child("BuyButton", true, false) as Control
	assert_true(buy != null, "BuyButton existiert")
	var ahn: Node = buy.get_parent()
	while ahn != null and not (ahn is ScrollContainer):
		ahn = ahn.get_parent()
	assert_true(ahn == null, "Kaufzeile hängt in KEINEM ScrollContainer mehr")
	var canvas := Vector2(screen.get_viewport().get_visible_rect().size)
	var rect := buy.get_global_rect()
	assert_true(
		rect.position.y >= 0.0 and rect.end.y <= canvas.y + 0.5,
		"Kaufen ohne Scrollen im Canvas (Knopf %s, Canvas %s)" % [rect, canvas]
	)
	assert_true(rect.end.x <= canvas.x + 0.5, "Kaufen läuft rechts nicht aus dem Canvas")
	await _drop(screen)


func test_kauf_sound_ist_ui_buy() -> void:
	# Headless nicht hörbar — der Quelltext-Scan hält die Id-Wahl der
	# Sound-Fixliste F3 fest (Kauf-Erfolg = ui_buy, nicht ui_confirm).
	var quelle := FileAccess.get_file_as_string(SCREEN_QUELLE)
	assert_true(not quelle.is_empty(), "ikea_screen.gd lesbar")
	assert_true(
		quelle.contains('AudioDirector.try_play(self, "ui_buy")'), "Kauf-Erfolg spielt ui_buy (F3)"
	)
	assert_false(quelle.contains('"ui_confirm"'), "ui_confirm ist aus dem Screen verschwunden")


func test_titel_ohne_gouhbus_in_beiden_sprachen() -> void:
	for locale: String in ["de", "en"]:
		var pfad := "res://strings/%s/shop.json" % locale
		var daten: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
		assert_true(daten is Dictionary, "%s parsebar" % pfad)
		var titel := str(((daten["shop"] as Dictionary)["ikea"] as Dictionary)["title"])
		assert_true(not titel.is_empty(), "%s: Titel-Key vorhanden" % locale)
		assert_false(
			titel.contains("GOUHBUS"),
			"%s: kein GOUHBUS mehr im Titel (Verwechslung mit dem Doktor)" % locale
		)
		assert_true(
			titel.contains("IKEA"), "%s: Titel nutzt den Karten-Namen IKEA (ein Name)" % locale
		)
