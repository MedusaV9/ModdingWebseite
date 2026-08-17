extends TestCase
## W18/4 (Fix-Agent G5) — Wächter für die fünf Playtest-Befunde:
## - B6 (TapArea): `emulate_touch_from_mouse` liefert pro Klick ZWEI
##   Press-Events; make_tap_area feuert jetzt auf RELEASE + dedupliziert
##   das Maus/Touch-Paar — ein simulierter Doppel-Press öffnet GENAU ein
##   Sheet, das offen BLEIBT (vorher: sofort wieder zu über den Backdrop).
## - B2 (GOOBERANDO): Korb-Zeile + „Bestellen“ leben GEPINNT im
##   PhoneShell-Fuß (IKEA-Muster W18/F6) und stehen in BEIDEN Leitformaten
##   im Bild; der Maus-Wisch scrollt den Telefon-Inhalt (F6-Arcade-Pan).
## - Turnierplatz: „Fertig“ sitzt AUSSERHALB der Scroll-Spalte
##   (comp_level_select-Muster) und bleibt auch bei überlaufendem Menü im Bild.
## - McGooby: der Früh-Tap-Callout „noch roh!“ wird beim Zustandswechsel
##   geräumt (stand vorher dauerhaft über dem goldbraunen/verkohlten Patty);
##   Ergebnis-Callouts (perfekt!) bleiben davon unberührt.
## - GooUndBye: Slot-Chips spreizen überlappungsfrei (chip_spalten_x,
##   Rect-Test) und der Kassensturz-Umsatz trägt sein Label.

const TURNIER_SKRIPT := "res://scripts/minigames/games/ranch_turnier/turnier_game.gd"
const SCHICHT_SZENE := "res://scripts/dlc/mcgooby/schicht_scene.tscn"
const LadenSzene := preload("res://scripts/dlc/goobye/laden_scene.tscn")
const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## Leitformate (physische px, Screen-Scale 3) — Muster test_g7_phone.
const IPHONE_HOCH := Vector2i(1179, 2556)
const IPHONE_QUER := Vector2i(2868, 1320)
const IPHONE_SCALE := 3.0

var _saved_root_size := Vector2i.ZERO


## GameState-Double fürs Telefon (Muster test_g7_phone.FakeGameState).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {
		"city": {"taxi": TaxiLogic.default_slice(), "fahrdienst": "", "fotos": []},
		"economy": {"coins": 300},
		"gooby": {"stats": {"energy": 80.0}},
		"inventory": {"items": {}, "food": {}},
	}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## ------------------------------------------------------ B6: TapArea


## Der EXAKTE Event-Sturm eines Klicks unter emulate_touch_from_mouse
## (Maus-Press + emulierter Touch-Press, dann beide Releases) über echtes
## 3D-Physik-Picking: GENAU EIN on_tap, das geöffnete Sheet BLEIBT offen.
## Mit dem alten Press-Feuer schoss der zweite Press das frisch gespawnte
## Backdrop ab (schließt auf Press) — Sheet öffnete und schloss sofort.
func test_b6_doppel_press_oeffnet_genau_ein_sheet_das_offen_bleibt() -> void:
	PanelStack.clear()
	var welt := Node3D.new()
	tree.root.add_child(welt)
	var kamera := Camera3D.new()
	welt.add_child(kamera)
	kamera.look_at_from_position(Vector3(0.0, 1.2, 4.0), Vector3(0.0, 0.65, 0.0))
	kamera.current = true
	var moebel := Node3D.new()
	welt.add_child(moebel)
	var sheet: PanelSheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	tree.root.add_child(sheet)
	var taps := [0]
	var area := InteractablesHost.make_tap_area(
		moebel,
		func() -> void:
			taps[0] += 1
			if not sheet.is_open():
				sheet.open()
	)
	moebel.add_child(area)
	# Physik-Space braucht einen Tick, bis der Collider pickbar ist.
	await wait_frames(5)
	var canvas := kamera.unproject_position(Vector3(0.0, 0.65, 0.0))
	tree.root.push_input(_maus(canvas, true), true)
	tree.root.push_input(_touch(canvas, true), true)
	await wait_frames(3)
	tree.root.push_input(_maus(canvas, false), true)
	tree.root.push_input(_touch(canvas, false), true)
	var gefeuert := await wait_until(func() -> bool: return taps[0] >= 1, 3000)
	assert_true(gefeuert, "der Möbel-Tap kommt über das 3D-Picking an")
	await wait_frames(5)
	assert_eq(taps[0], 1, "GENAU ein on_tap trotz Maus+Touch-Doppel-Press")
	assert_true(sheet.is_open(), "das Sheet ist offen …")
	await wait_frames(5)
	assert_true(sheet.is_open(), "… und BLEIBT offen (B6: schloss sofort wieder)")
	sheet.queue_free()
	welt.queue_free()
	await wait_frames(2)
	PanelStack.clear()


## Release-Logik pur (input_event-Signal direkt): Zieh-Gesten über dem
## Möbel feuern nicht, das Maus/Touch-Doppel dedupliziert auf EINEN Tap,
## ein loses Release ohne Press feuert nie.
func test_b6_release_toleranz_und_dedup() -> void:
	var moebel := Node3D.new()
	tree.root.add_child(moebel)
	var taps := [0]
	var area := InteractablesHost.make_tap_area(moebel, func() -> void: taps[0] += 1)
	moebel.add_child(area)
	await wait_frames(1)
	# Zieh-Geste: Release 300 px weiter ist KEIN Tap (Toleranz 24 ×f).
	_area_event(area, _maus(Vector2(100.0, 100.0), true))
	_area_event(area, _maus(Vector2(400.0, 100.0), false))
	assert_eq(taps[0], 0, "Zieh-Geste über dem Möbel feuert nicht")
	# Der Doppel-Press-Sturm nahe beieinander: genau EIN Tap.
	_area_event(area, _maus(Vector2(100.0, 100.0), true))
	_area_event(area, _touch(Vector2(101.0, 100.0), true))
	_area_event(area, _maus(Vector2(102.0, 100.0), false))
	_area_event(area, _touch(Vector2(102.0, 100.0), false))
	assert_eq(taps[0], 1, "Maus+Touch-Doppel dedupliziert: genau EIN Tap")
	# Loses Release ohne Press bleibt stumm.
	_area_event(area, _maus(Vector2(102.0, 100.0), false))
	assert_eq(taps[0], 1, "Release ohne Press feuert nie")
	moebel.queue_free()
	await wait_frames(1)


## -------------------------------------------------- B2: GOOBERANDO


## Der Bestell-CTA lebt im gepinnten PhoneShell-Fuß (nicht im Scroll) und
## steht in BEIDEN Leitformaten komplett im Canvas — im Querformat lag
## „Bestellen“ vorher ~2 Viewports unter der Falz.
func test_b2_gooberando_cta_gepinnt_und_im_bild_beide_formate() -> void:
	var rm: Variant = _set_reduced_motion(true)
	for format: Vector2i in [IPHONE_HOCH, IPHONE_QUER]:
		await _pin(format, IPHONE_SCALE)
		var shell := await _gooberando_menue_oeffnen()
		var app := _gooberando_app(shell)
		assert_true(app != null, "%s: GooberandoApp ist gemountet" % format)
		if app == null:
			await _schliesse_shell(shell)
			continue
		var knopf: Button = app._kaufen_knopf
		var fuss := PhoneShell.app_fuss_bereich(app)
		assert_true(knopf != null and fuss != null, "%s: CTA + Fuß existieren" % format)
		if knopf == null or fuss == null:
			await _schliesse_shell(shell)
			continue
		assert_true(fuss.is_ancestor_of(knopf), "%s: CTA lebt im gepinnten Fuß" % format)
		assert_true(fuss.visible, "%s: Fuß ist sichtbar" % format)
		assert_false(
			_hat_scroll_vorfahren(knopf, shell),
			"%s: kein ScrollContainer zwischen CTA und Shell" % format
		)
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var rect := knopf.get_global_rect()
		assert_true(rect.size.y > 0.0, "%s: CTA hat Layout-Höhe" % format)
		assert_true(
			rect.position.y >= -0.5 and rect.end.y <= canvas.y + 0.5,
			(
				"%s: CTA komplett im Canvas (y %f..%f, Canvas %f)"
				% [format, rect.position.y, rect.end.y, canvas.y]
			)
		)
		await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


## Maus-Wisch scrollt den Telefon-Inhalt (F6-Arcade-Pan im gui_input des
## Scrolls): Press + Aufwärts-Drags über die Deadzone bewegen
## scroll_vertical — vorher blieb der Wisch unter Desktop/xvfb tot.
func test_b2_maus_wisch_scrollt_das_telefon() -> void:
	var rm: Variant = _set_reduced_motion(true)
	await _pin(IPHONE_QUER, IPHONE_SCALE)
	var shell := await _gooberando_menue_oeffnen()
	# Überlauf sicherstellen (der Pan greift bewusst NUR bei Überlauf).
	var fueller := Control.new()
	fueller.custom_minimum_size = Vector2(0.0, 2400.0)
	fueller.mouse_filter = Control.MOUSE_FILTER_PASS
	shell._inhalt.add_child(fueller)
	await wait_frames(2)
	var scroll: ScrollContainer = shell._scroll
	assert_true(
		shell._inhalt.get_combined_minimum_size().y > scroll.size.y + 1.0,
		"Testaufbau: Inhalt überläuft das Scroll-Fenster"
	)
	scroll.scroll_vertical = 0
	await wait_frames(1)
	var pos := scroll.get_global_rect().get_center()
	tree.root.push_input(_maus(pos, true), true)
	for _i in 6:
		pos += Vector2(0.0, -40.0)
		tree.root.push_input(_maus_zug(pos, Vector2(0.0, -40.0)), true)
		await wait_frames(1)
	tree.root.push_input(_maus(pos, false), true)
	await wait_frames(2)
	assert_true(
		scroll.scroll_vertical > 0,
		"Maus-Wisch scrollt den Telefon-Inhalt (ist %d)" % scroll.scroll_vertical
	)
	await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


## ------------------------------------------------ Turnier: „Fertig“


## Das Turnier-Menü hält den Fuß AUSSERHALB der Scroll-Spalte
## (comp_level_select-Muster): auch wenn Liga-Panel + Disziplinen-Grid die
## Sicht sprengen, bleibt „Fertig“ unten gepinnt im Bild.
func test_turnier_fertig_bleibt_bei_ueberlauf_im_bild() -> void:
	var game: Variant = (load(TURNIER_SKRIPT) as GDScript).new()
	tree.root.add_child(game)
	# Kleines Quer-Fenster: das Menü überläuft sicher (Befund-Situation).
	game.view_size = Vector2(640.0, 360.0)
	game._balance = RanchCompKatalog.load_balance()
	game._plan = RanchCompLiga.turniertag_plan(
		game._balance, Time.get_date_string_from_system(), 777
	)
	var menu: Control = game._baue_menu()
	game.add_child(menu)
	await wait_frames(3)
	var fertig := _finde_knopf(menu, I18nService.t("rcomp.menu.fertig"))
	assert_true(fertig != null, "Fertig-Knopf steht im Menü")
	var scroll := _finde_scroll(menu)
	assert_true(scroll != null, "Menü-Inhalt lebt in einem ScrollContainer")
	if fertig == null or scroll == null:
		game.queue_free()
		await wait_frames(1)
		return
	var spalte: Control = scroll.get_child(0)
	assert_true(
		spalte.get_combined_minimum_size().y > 360.0,
		"Testaufbau: Menü-Inhalt sprengt die Sicht (%f px)" % spalte.get_combined_minimum_size().y
	)
	assert_false(_hat_scroll_vorfahren(fertig, menu), "Fertig hängt NICHT in der Scroll-Spalte")
	var rect := fertig.get_global_rect()
	assert_true(
		rect.end.y <= 360.0 + 0.5, "Fertig bleibt über der Falz (unten %f ≤ 360)" % rect.end.y
	)
	assert_true(rect.position.y >= 0.0, "Fertig startet im Bild")
	game.queue_free()
	await wait_frames(1)


## ---------------------------------------------- McGooby: Callout


## Der Früh-Tap-Callout „noch roh!“ gilt nur, solange der Patty roh ist:
## der Zustandswechsel räumt ihn; Ergebnis-Callouts (perfekt!) überleben
## spätere Zustandswechsel unangetastet.
func test_mcgooby_roh_callout_wird_beim_zustandswechsel_geraeumt() -> void:
	McGoobyKatalog.reset_cache()
	var gs := FakeGameState.new()
	gs.set_value("mcgooby.introGesehen", true)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = 4711
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(szene.ist_am_laufen(), "Testaufbau: Schicht läuft")
	var callout: Label = szene.find_child("Callout", true, false)
	assert_true(callout != null, "Callout-Label existiert")
	# Das AKTIVE Patty-Timing der Szene (rezeptspezifisch) statt Raten.
	var timing: Dictionary = szene._patty_timing
	var gar := float(timing["gar_sec"])
	var fenster := float(timing["fenster_sec"])
	# Früh-Tap auf den ROHEN Patty → „noch roh!“-Callout.
	szene.patty_zeit_setzen(0.1)
	szene.patty_knopf().pressed.emit()
	await wait_frames(1)
	var roh_text := I18nService.t("dlc_mcgooby.schicht.roh")
	assert_eq(callout.text, roh_text, "Früh-Tap zeigt den Roh-Hinweis")
	# Zustandswechsel roh → goldbraun: der Hinweis hat gelogen → geräumt.
	szene.patty_zeit_setzen(gar + minf(0.2, fenster * 0.5))
	await wait_frames(1)
	assert_ne(callout.text, roh_text, "Roh-Callout steht NICHT über dem goldbraunen Patty")
	assert_eq(callout.text.strip_edges(), "", "Callout ist geräumt (Leerstand)")
	# Ergebnis-Callout (perfekt!) bleibt über spätere Zustandswechsel stehen.
	szene.patty_knopf().pressed.emit()
	await wait_frames(1)
	var perfekt_text := I18nService.t("dlc_mcgooby.schicht.perfekt")
	assert_eq(callout.text, perfekt_text, "Wenden im Fenster zeigt „perfekt!“")
	# Frisches Timing des NÄCHSTEN Pattys lesen — ein echter Zustands-
	# wechsel roh → goldbraun darf den Ergebnis-Callout nicht räumen.
	var timing2: Dictionary = szene._patty_timing
	szene.patty_zeit_setzen(float(timing2["gar_sec"]) + 0.1)
	await wait_frames(1)
	assert_eq(callout.text, perfekt_text, "Ergebnis-Callout überlebt den Zustandswechsel")
	szene.queue_free()
	await wait_frames(1)


## ------------------------------------------- GooUndBye: Chips + Label


## Befund-Situation: 5 Anker auf ~90 px projiziert, Chips 66 px breit
## (44-pt-Floor) — chip_spalten_x spreizt überlappungsfrei (Rect-Test)
## und hält die Reihe um die Anker-Mitte zentriert.
func test_goobye_chips_spreizen_ueberlappungsfrei() -> void:
	var anker: Array[float] = [100.0, 122.5, 145.0, 167.5, 190.0]
	var breite := 66.0
	var schritt := breite + 6.0
	var xs := GoobyeLadenUiTeile.chip_spalten_x(anker, schritt)
	assert_eq(xs.size(), anker.size(), "eine Mitte pro Anker")
	for i in xs.size() - 1:
		assert_true(xs[i + 1] - xs[i] >= schritt - 0.01, "Mindest-Schritt %d gehalten" % i)
		var a := Rect2(xs[i] - breite / 2.0, 0.0, breite, 44.0)
		var b := Rect2(xs[i + 1] - breite / 2.0, 0.0, breite, 44.0)
		assert_false(a.intersects(b), "Chip-Rects %d/%d überlappen nicht" % [i, i + 1])
	assert_almost(
		(xs[0] + xs[xs.size() - 1]) / 2.0,
		(anker[0] + anker[anker.size() - 1]) / 2.0,
		0.01,
		"Reihe bleibt um die Anker-Mitte zentriert"
	)


## Weit auseinanderliegende Anker bleiben unangetastet (kein Spreizen ohne
## Not); Solo-/Leerfälle laufen durch.
func test_goobye_chips_behalten_weite_anker() -> void:
	var anker: Array[float] = [100.0, 300.0, 500.0]
	assert_eq(GoobyeLadenUiTeile.chip_spalten_x(anker, 72.0), anker, "weite Anker unverändert")
	var solo: Array[float] = [42.0]
	assert_eq(GoobyeLadenUiTeile.chip_spalten_x(solo, 72.0), solo, "Solo-Anker unverändert")
	var leer: Array[float] = []
	assert_eq(GoobyeLadenUiTeile.chip_spalten_x(leer, 72.0).size(), 0, "leer bleibt leer")


## B8: die große Kassensturz-Zähl-Zahl trägt ihr Label (Key
## dlc_goobye.abschluss.umsatz existierte, war aber unbenutzt) — das Label
## sitzt DIREKT über der Zahl und löst in der aktiven Sprache auf.
func test_goobye_kassensturz_umsatz_hat_label() -> void:
	GoobyeKatalog.reset_cache()
	var gs := FakeGameState.new()
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = 4711
	szene.tempo = 0.05
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	szene.umsatz_heute = 37
	szene._zeige_abschluss()
	await wait_frames(2)
	var titel: Label = szene.find_child("UmsatzTitel", true, false)
	assert_true(titel != null, "Kassensturz-Umsatz hat ein Label (war nackte Zahl)")
	var zahl: Label = szene.find_child("AbschlussUmsatz", true, false)
	assert_true(zahl != null, "Zähl-Zahl existiert")
	if titel != null and zahl != null:
		assert_eq(titel.text, I18nService.t("dlc_goobye.abschluss.umsatz"), "i18n-Key")
		assert_false(titel.text.begins_with("dlc_goobye"), "Key löst in der Sprache auf")
		assert_eq(titel.get_parent(), zahl.get_parent(), "Label und Zahl teilen die Spalte")
		assert_eq(titel.get_index() + 1, zahl.get_index(), "Label steht DIREKT über der Zahl")
	szene.queue_free()
	await wait_frames(2)


## ------------------------------------------------------------- Helfer


func _pin(size: Vector2i, screen_scale := 0.0) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	UiScale.screen_scale_override = screen_scale
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)


func _set_reduced_motion(enabled: bool) -> Variant:
	var svc := tree.root.get_node_or_null("UiTheme")
	if svc == null:
		return null
	var previous := bool(svc.reduced_motion)
	svc.reduced_motion = enabled
	return previous


func _restore_reduced_motion(previous: Variant) -> void:
	var svc := tree.root.get_node_or_null("UiTheme")
	if svc != null and previous != null:
		svc.reduced_motion = bool(previous)


## Telefon öffnen, GOOBERANDO starten und ins Menü des ersten Restaurants
## wechseln (die Ansicht mit Korb-Zeile + Bestell-CTA).
func _gooberando_menue_oeffnen() -> PhoneShell:
	var gs := FakeGameState.new()
	var shell := PhoneShell.oeffne(tree.root, gs)
	await wait_frames(3)
	shell.oeffne_app("gooberando")
	await wait_frames(2)
	var app := _gooberando_app(shell)
	if app != null:
		var restaurant: Dictionary = GooberandoRestaurants.alle()[0]
		app._on_restaurant(str(restaurant.get("id", "")))
		await wait_frames(3)
	return shell


func _gooberando_app(shell: PhoneShell) -> GooberandoApp:
	for kind in shell._inhalt.get_children():
		if kind is GooberandoApp:
			return kind
	return null


func _schliesse_shell(shell: PhoneShell) -> void:
	shell.schliesse()
	await wait_frames(2)


## Liegt zwischen `ctl` und `stopp` ein ScrollContainer? (CTA-Pinning-Wache)
func _hat_scroll_vorfahren(ctl: Node, stopp: Node) -> bool:
	var knoten := ctl.get_parent()
	while knoten != null and knoten != stopp:
		if knoten is ScrollContainer:
			return true
		knoten = knoten.get_parent()
	return false


func _finde_knopf(wurzel: Node, text: String) -> Button:
	if wurzel is Button and (wurzel as Button).text == text:
		return wurzel
	for kind in wurzel.get_children():
		var gefunden := _finde_knopf(kind, text)
		if gefunden != null:
			return gefunden
	return null


func _finde_scroll(wurzel: Node) -> ScrollContainer:
	if wurzel is ScrollContainer:
		return wurzel
	for kind in wurzel.get_children():
		var gefunden := _finde_scroll(kind)
		if gefunden != null:
			return gefunden
	return null


func _area_event(area: Area3D, event: InputEvent) -> void:
	area.input_event.emit(null, event, Vector3.ZERO, Vector3.ZERO, 0)


func _maus(pos: Vector2, gedrueckt: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = gedrueckt
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if gedrueckt else 0
	return ev


func _maus_zug(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev


func _touch(pos: Vector2, gedrueckt: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = gedrueckt
	return ev
