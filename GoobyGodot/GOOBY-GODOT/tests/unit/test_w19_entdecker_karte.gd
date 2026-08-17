extends TestCase
## W19 — Entdecker-Karte der Ranch: das pure Karten-Modell
## (RanchEntdeckerKarte) ist vollständig/valide aus ranch_karte.json,
## Fog-Zustände kommen korrekt aus dem Save, die Erst-Besuch-Belohnung und
## das „NEU“-Badge buchen genau-einmal, Zonen-Tracking bleibt idempotent —
## und der Karten-Screen läuft headless in BEIDEN Leitformaten
## (Muster test_w18_guide_karte).

## Leitformate [Fenster-px, screen_scale, Insets in PUNKTEN l/t/r/b] —
## Werte wie fb3_ui_audit.SIZES (iPhone 17 Pro Max quer + hochkant).
const FORMATE: Array = [
	[Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]],
	[Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]],
]


## GameState-Double (Muster test_welt1_entdeckungen): dotted-Pfad-Werte
## + update(mutator) für die Münz-Buchung.
class MiniGs:
	var werte: Dictionary = {}
	var state: Dictionary = {"economy": {"coins": 100}}

	func get_value(pfad: String, fallback: Variant = null) -> Variant:
		return werte.get(pfad, fallback)

	func set_value(pfad: String, wert: Variant) -> void:
		werte[pfad] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func coins() -> int:
		return int(state["economy"]["coins"])


## ------------------------------------------------------ Modell (pur)


func test_modell_vollstaendig_und_valide() -> void:
	assert_eq(RanchEntdeckerKarte.probleme(), [] as Array[String], "Modell-Integrität")
	var modell := RanchEntdeckerKarte.modell(MiniGs.new())
	var grenzen: Rect2 = modell["grenzen"]
	assert_eq((modell["zonen"] as Array).size(), RanchKarte.zonen().size(), "alle Zonen")
	assert_eq(
		(modell["fundorte"] as Array).size(), RanchEntdeckungen.alle_orte().size(), "alle Fundorte"
	)
	for zone: Dictionary in modell["zonen"]:
		assert_true(grenzen.encloses(zone["rect"]), "Zone %s in den Grenzen" % zone["id"])
		assert_true((zone["farbe"] as Color).a > 0.0, "Zone %s hat Farbe" % zone["id"])
	for fund: Dictionary in modell["fundorte"]:
		assert_true(grenzen.has_point(fund["zeig_pos"]), "Pin %s in den Grenzen" % fund["id"])
	assert_true((modell["wege"] as Array).size() >= 9, "Wegenetz vorhanden")
	assert_true((modell["bach"] as Array).size() >= 3, "Bachlauf vorhanden")
	var fortschritt: Dictionary = modell["fortschritt"]
	assert_eq(int(fortschritt["zonen_gesamt"]), RanchKarte.zonen().size(), "Zonen-Gesamt")
	assert_eq(int(fortschritt["funde_gesamt"]), RanchEntdeckungen.alle_orte().size(), "Fund-Gesamt")


func test_texte_lokalisiert() -> void:
	for eintrag: Dictionary in RanchEntdeckungen.alle_orte():
		var key := "rkarte.beschr.%s" % eintrag["id"]
		var text := I18nService.t(key)
		assert_true(text != key and not text.is_empty(), "Beschreibung %s" % key)
	for richtung: String in RanchEntdeckerKarte.RICHTUNGEN:
		var key := "rkarte.richtung.%s" % richtung
		assert_true(I18nService.t(key) != key, "Richtung %s übersetzt" % key)
	var kopf := I18nService.t(
		"rkarte.fortschritt",
		{"funde": "1", "funde_gesamt": "16", "zonen": "2", "zonen_gesamt": "16"}
	)
	assert_true(kopf.contains("1/16") and kopf.contains("2/16"), "Fortschritts-Kopf formatiert")


func test_fog_zustaende_aus_save() -> void:
	var gs := MiniGs.new()
	var modell := RanchEntdeckerKarte.modell(gs)
	for zone: Dictionary in modell["zonen"]:
		assert_eq(bool(zone["entdeckt"]), str(zone["id"]) == "hof", "frisch: nur Hof bereist")
	for fund: Dictionary in modell["fundorte"]:
		assert_false(bool(fund["entdeckt"]), "frisch: %s unentdeckt" % fund["id"])
		assert_eq(
			fund["zeig_pos"],
			RanchEntdeckerKarte.grobe_position(fund["pos"]),
			"unentdeckt = GROBE Position (%s)" % fund["id"]
		)
	RanchWeltState.entdecke_zone(gs, "see")
	RanchEntdeckungen.entdecke(gs, "wasserfall")
	modell = RanchEntdeckerKarte.modell(gs)
	for zone: Dictionary in modell["zonen"]:
		if str(zone["id"]) == "see":
			assert_true(bool(zone["entdeckt"]), "See bereist")
	for fund: Dictionary in modell["fundorte"]:
		if str(fund["id"]) != "wasserfall":
			continue
		assert_true(bool(fund["entdeckt"]), "Wasserfall entdeckt")
		assert_true(bool(fund["neu"]), "Wasserfall trägt NEU-Badge")
		assert_eq(fund["zeig_pos"], fund["pos"], "entdeckt = echte Position")


func test_erstbesuch_belohnung_genau_einmal() -> void:
	var gs := MiniGs.new()
	var erster := RanchEntdeckungen.entdecke(gs, "steinkreis")
	assert_true(bool(erster["neu"]), "Erst-Besuch ist neu")
	var muenzen := int(erster["muenzen"])
	assert_true(muenzen > 0, "Erst-Besuch belohnt")
	assert_eq(gs.coins(), 100 + muenzen, "Münzen über den bestehenden Pfad gebucht")
	assert_false(bool(RanchEntdeckungen.entdecke(gs, "steinkreis")["neu"]), "nur einmal neu")
	assert_eq(gs.coins(), 100 + muenzen, "keine Doppel-Belohnung")


func test_neu_badge_genau_einmal() -> void:
	var gs := MiniGs.new()
	RanchEntdeckungen.entdecke(gs, "hoehle")
	assert_eq(RanchEntdeckerKarte.neue_funde(gs), ["hoehle"] as Array[String], "NEU bis Ansehen")
	RanchEntdeckerKarte.markiere_funde_gesehen(gs, ["hoehle", "quatsch_id"])
	assert_eq(RanchEntdeckerKarte.neue_funde(gs), [] as Array[String], "nach Ansehen kein NEU")
	assert_eq(
		RanchEntdeckerKarte.gesehene_funde(gs),
		["hoehle"] as Array[String],
		"unbekannte Ids werden nicht gespeichert"
	)
	RanchEntdeckerKarte.markiere_funde_gesehen(gs, ["hoehle"])
	assert_eq(RanchEntdeckerKarte.gesehene_funde(gs).size(), 1, "markieren bleibt idempotent")


func test_zonen_tracking_erstbesuch() -> void:
	var gs := MiniGs.new()
	assert_eq(int(RanchEntdeckerKarte.fortschritt(gs)["zonen"]), 1, "Start: nur Hof")
	assert_true(RanchWeltState.entdecke_zone(gs, "moor"), "Erst-Besuch zählt")
	assert_false(RanchWeltState.entdecke_zone(gs, "moor"), "Zweit-Besuch zählt nicht")
	assert_false(RanchWeltState.entdecke_zone(gs, "narnia"), "unbekannte Zone zählt nicht")
	assert_eq(int(RanchEntdeckerKarte.fortschritt(gs)["zonen"]), 2, "Hof + Moor bereist")


func test_richtung_und_hinweis() -> void:
	var mitte := Vector2.ZERO
	assert_eq(RanchEntdeckerKarte.richtung_key(mitte, Vector2(0.0, -100.0)), "n", "Norden")
	assert_eq(RanchEntdeckerKarte.richtung_key(mitte, Vector2(100.0, 0.0)), "o", "Osten")
	assert_eq(RanchEntdeckerKarte.richtung_key(mitte, Vector2(100.0, -100.0)), "no", "NO")
	assert_eq(RanchEntdeckerKarte.richtung_key(mitte, Vector2(-100.0, 100.0)), "sw", "SW")
	assert_eq(RanchEntdeckerKarte.richtung_key(mitte, mitte), "", "kein Weg = keine Richtung")
	assert_eq(RanchEntdeckerKarte.hinweis_zone(Vector2(252.0, -470.0)), "huegelkamm", "in Zone")
	assert_eq(
		RanchEntdeckerKarte.hinweis_zone(Vector2(245.0, -250.0)),
		"bachlauf",
		"freies Land = nächste Zone"
	)
	var grob := RanchEntdeckerKarte.grobe_position(Vector2(252.0, -470.0))
	assert_eq(grob, Vector2(270.0, -450.0), "grobe Position = Rasterzelle")
	assert_ne(grob, Vector2(252.0, -470.0), "grob verrät nie die exakte Stelle")


## ------------------------------------------------- Screen (Smoke, UI)


## Fenster + Retina-Skala + Notch-Insets pinnen (Muster test_w18_guide_karte).
func _pin_format(format: Array) -> void:
	var fenster: Vector2i = format[0]
	UiScale.screen_scale_override = float(format[1])
	tree.root.size = fenster
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var scale: float = format[1]
	var insets_pt: Array = format[2]
	var px_per_pt := minf(canvas.x, canvas.y) / (minf(fenster.x, fenster.y) / scale)
	var l := float(insets_pt[0]) * px_per_pt
	var t := float(insets_pt[1]) * px_per_pt
	var r := float(insets_pt[2]) * px_per_pt
	var b := float(insets_pt[3]) * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin_format(fenster_vorher: Vector2i) -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


func _baue_screen(gs: MiniGs) -> RanchKarteScreen:
	var screen := RanchKarteScreen.new()
	screen.auto_navigate = false
	screen.game_state_override = gs
	screen.receive_params({"spieler": [0.0, 160.0]})
	tree.root.add_child(screen)
	await wait_frames(3)
	return screen


func test_screen_smoke_beide_formate() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	for format: Array in FORMATE:
		await _pin_format(format)
		var gs := MiniGs.new()
		RanchEntdeckungen.entdecke(gs, "wasserfall")
		var screen := await _baue_screen(gs)
		var canvas := Vector2(tree.root.get_visible_rect().size)
		assert_true(screen.fortschritt_text().contains("1/16"), "Kopf zählt Funde @ %s" % format[0])
		assert_true(
			screen._rows.has_meta(ScreenShell.META_CONTENT_COLUMN),
			"Inhaltsspalte markiert @ %s" % format[0]
		)
		assert_true(
			Rect2(Vector2.ZERO, canvas).grow(1.0).encloses(screen._rows.get_global_rect()),
			"Inhalt im Viewport @ %s" % format[0]
		)
		assert_eq(screen.pins().size(), RanchEntdeckungen.alle_orte().size(), "alle Pins gebaut")
		var flaeche := screen._canvas
		assert_true(flaeche.size.x > 0.0 and flaeche.size.y > 0.0, "Kartenfläche hat Größe")
		var innen := Rect2(Vector2.ZERO, flaeche.size).grow(4.0)
		for id: String in screen.pins():
			var knopf: Button = screen.pins()[id]
			var mitte: Vector2 = knopf.position + knopf.size / 2.0
			assert_true(innen.has_point(mitte), "Pin %s auf der Karte @ %s" % [id, format[0]])
		screen.queue_free()
		await wait_frames(1)
	await _unpin_format(fenster_vorher)


## W19-Playtest-Befund (Lauf w19karte_quer_v3, Schritt pin_klebt_nach_zoom):
## nach einem Zoom-Wechsel layoutet der ScrollContainer die Kartenfläche
## erst im NÄCHSTEN Frame (neue Min-Size, ggf. auftauchende Scrollbalken) —
## das einmalige deferred _positioniere_pins lief davor, die Pins klebten
## am alten Versatz. Wache: nach Zoom rein/raus sitzt jeder Pin wieder
## EXAKT auf welt_zu_px seiner Zeig-Position.
func test_pins_kleben_nach_zoom() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[0])
	var gs := MiniGs.new()
	RanchEntdeckungen.entdecke(gs, "steinkreis")
	var screen := await _baue_screen(gs)
	for schritt: int in [1, 1, -1, -1]:
		screen._on_zoom(schritt)
		await wait_frames(4)
		for id: String in screen.pins():
			var knopf: Button = screen.pins()[id]
			var fund := _fund_aus_modell(screen, id)
			var soll: Vector2 = screen._canvas.call("welt_zu_px", fund["zeig_pos"])
			var mitte: Vector2 = knopf.position + knopf.size / 2.0
			assert_true(
				mitte.distance_to(soll) < 2.0,
				(
					"Pin %s klebt nach Zoom %+d (Abstand %.1f px)"
					% [id, schritt, mitte.distance_to(soll)]
				)
			)
	screen.queue_free()
	await wait_frames(1)
	await _unpin_format(fenster_vorher)


func _fund_aus_modell(screen: RanchKarteScreen, id: String) -> Dictionary:
	for fund: Dictionary in screen._modell["fundorte"]:
		if str(fund["id"]) == id:
			return fund
	return {}


func test_screen_badge_und_detail() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[0])
	var gs := MiniGs.new()
	RanchEntdeckungen.entdecke(gs, "wasserfall")
	assert_eq(RanchEntdeckerKarte.neue_funde(gs).size(), 1, "Vorbedingung: NEU wartet")
	var screen := await _baue_screen(gs)
	var pin: Button = screen.pins()["wasserfall"]
	assert_ne(pin.get_node_or_null("Neu"), null, "NEU-Badge sitzt am frischen Fund")
	assert_eq(RanchEntdeckerKarte.neue_funde(gs).size(), 0, "Öffnen bucht das Erst-Ansehen")
	assert_eq(str(pin.text), "★", "entdeckter Pin zeigt Stern")
	var frage: Button = screen.pins()["kornkreis"]
	assert_eq(str(frage.text), "?", "unentdeckter Pin zeigt Fragezeichen")
	screen._on_pin("wasserfall")
	await wait_frames(2)
	assert_true(screen._sheet.visible, "Detail-Karte öffnet")
	assert_eq(pin.get_node_or_null("Neu"), null, "Badge verschwindet nach dem Ansehen")
	screen._sheet.close()
	await wait_frames(2)
	screen._on_pin("kornkreis")
	await wait_frames(2)
	assert_true(screen._sheet.visible, "„?“-Pin zeigt Geheimnis-Karte")
	screen._sheet.close()
	await wait_frames(2)
	var zoom_vorher: Vector2 = screen._canvas.custom_minimum_size
	screen._on_zoom(1)
	await wait_frames(2)
	assert_true(screen._canvas.custom_minimum_size.x > zoom_vorher.x, "Zoom vergrößert die Karte")
	screen.queue_free()
	await wait_frames(1)
	await _unpin_format(fenster_vorher)


func test_karte_hat_fokusnavigation_und_sichtbaren_pin_fokus() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[0])
	var screen := await _baue_screen(MiniGs.new())
	await wait_frames(2)
	assert_eq(screen._back.focus_mode, Control.FOCUS_ALL, "Zurück fokussierbar")
	assert_eq(screen._zoom_rein.focus_mode, Control.FOCUS_ALL, "Zoom+ fokussierbar")
	assert_eq(screen._zoom_raus.focus_mode, Control.FOCUS_ALL, "Zoom− fokussierbar")
	assert_eq(tree.root.gui_get_focus_owner(), screen._back, "Karte startet mit Zurück-Fokus")
	for id: String in screen.pins():
		var pin: Button = screen.pins()[id]
		assert_eq(pin.focus_mode, Control.FOCUS_ALL, "Pin %s fokussierbar" % id)
		assert_false(pin.tooltip_text.is_empty(), "Pin %s hat zugänglichen Namen" % id)
		assert_false(pin.focus_next.is_empty(), "Pin %s ist in Tab-Reihenfolge" % id)
		var focus_box := pin.get_theme_stylebox("focus") as StyleBoxFlat
		assert_true(
			focus_box != null and focus_box.get_border_width(SIDE_LEFT) >= 4,
			"Pin %s hat sichtbaren Fokusring" % id
		)
	screen.queue_free()
	await wait_frames(1)
	await _unpin_format(fenster_vorher)
