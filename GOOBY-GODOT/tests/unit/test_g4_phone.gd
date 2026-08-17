extends TestCase
## G4/P18 UI-PHONE — Geometrie- und Grammatik-Verträge des IGohbie:
## Gerät skaliert ×f mit card_width/card_max_height-Deckel (statt 380×640
## fix), Kacheln/Geste ×f + Touch-Floor, Apps koppeln an die REALE
## Gerätebreite (Breiten-Kollision der 420er-City-Bausteine, G1 ui-post §4),
## Fotomodus-Sucher in der Safe-Area (Top-Leiste, Querformat-Werkzeugspalte),
## SnapAGooby-Hinweis unter der Notch, GoobyPal-Verlauf ×f. Geometrie-Tests
## pinnen das Fenster VOR dem Bau (Muster test_g4_media: headless übernimmt
## Window-Größen erst im Folge-Frame) und setzen es am Testende zurück.

var _saved_root_size := Vector2i.ZERO


## GameState-Double (Muster test_phone_apps): dotted get/set + update().
class FakeGameState:
	extends RefCounted
	var state: Dictionary = {
		"city": {"taxi": TaxiLogic.default_slice(), "fahrdienst": "", "fotos": []},
		"economy": {"coins": 300},
		"gooby": {"stats": {"energy": 80.0}},
		"inventory": {"items": {}, "food": {}},
	}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = state
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## Rig-Double für den Fotomodus (Muster test_w13c_fotowerk).
class FakeRig:
	extends Node3D
	var clips: Array = ["idle", "wave", "hop", "sleep"]
	var gespielt: Array[String] = []

	func clip_names() -> Array:
		return clips

	func play_clip(clip: String) -> void:
		gespielt.append(clip)

	func set_expression_override(_gesicht: Dictionary, _pose: Dictionary) -> void:
		pass

	func clear_expression_override() -> void:
		pass


# ------------------------------------------------------------ Fenster-Helfer


func _pin(size: Vector2i) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.insets_override = Rect2()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)


func _oeffne_shell(gs: FakeGameState) -> PhoneShell:
	var shell := PhoneShell.oeffne(tree.root, gs)
	await wait_frames(2)
	return shell


func _schliesse_shell(shell: PhoneShell) -> void:
	shell.schliesse()
	await wait_frames(2)


func _alle_buttons_squish(root: Node, kontext: String) -> void:
	var geprueft := 0
	for btn: Node in root.find_children("*", "Button", true, false):
		if btn is OptionButton:
			continue
		geprueft += 1
		assert_true(btn is SquishButton, "%s: '%s' ist ein SquishButton" % [kontext, btn.name])
	assert_true(geprueft > 0, "%s: Scan sieht Buttons (%d)" % [kontext, geprueft])


# ------------------------------------------------------------------ Gerät


func test_geraet_skaliert_und_deckelt_mit_dem_canvas() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	var geraet: PanelContainer = shell.find_child("Geraet", true, false)
	assert_true(geraet != null, "Gerät existiert")
	# G7/P52: 1280×720 ist QUER → breite Geräte-Basis 640×480 statt der
	# 380er-Hochkant-Karte, die am Höhen-Deckel zur Briefmarke wurde.
	assert_almost(geraet.custom_minimum_size.x, 640.0, 0.5, "f=1 quer: breite Basis")
	var m := ScreenShell.metrics(shell.get_viewport())
	assert_almost(geraet.custom_minimum_size.y, 480.0, 0.5, "f=1 quer: 480 unterm Deckel")
	assert_true(
		geraet.custom_minimum_size.y <= ScreenShell.card_max_height(m) + 0.5,
		"quer: Höhen-Deckel respektiert"
	)
	assert_almost(shell.geste_schwelle(), 90.0, 0.5, "Geste f=1 = 90 px")
	# Hochkant-Fenster: das canvas_items-Stretch hält die Canvas-Breite bei
	# 1280 → f = 1280/720 ≈ 1,78. Das Gerät wächst ×f statt fix zu kleben.
	tree.root.size = Vector2i(1440, 2560)
	tree.root.size_changed.emit()
	await wait_frames(3)
	m = ScreenShell.metrics(shell.get_viewport())
	var f: float = m["f"]
	assert_true(f > 1.5, "Hochkant-Canvas skaliert hoch (f=%.2f)" % f)
	assert_almost(geraet.custom_minimum_size.x, 380.0 * f, 0.5, "hoch: Breite ×f")
	assert_true(640.0 * f <= ScreenShell.card_max_height(m), "640×f passt unter den Deckel")
	assert_almost(geraet.custom_minimum_size.y, 640.0 * f, 0.5, "hoch: Höhe ×f unterm Deckel")
	assert_almost(shell.geste_schwelle(), 90.0 * f, 0.5, "Geste skaliert ×f")
	# Zurück aufs Referenz-Fenster: Gerät wechselt wieder auf die Quer-Basis.
	tree.root.size = Vector2i(1280, 720)
	tree.root.size_changed.emit()
	await wait_frames(3)
	assert_almost(geraet.custom_minimum_size.x, 640.0, 0.5, "zurück: Quer-Basis")
	assert_almost(geraet.custom_minimum_size.y, 480.0, 0.5, "zurück: Quer-Höhe")
	await _schliesse_shell(shell)
	await _unpin()


func test_kacheln_und_home_balken_grammatik() -> void:
	await _pin(Vector2i(1440, 2560))
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	var m := ScreenShell.metrics(shell.get_viewport())
	var f: float = m["f"]
	var floor_px: float = m["floor_px"]
	assert_true(f > 1.5, "Hochkant-Canvas skaliert hoch (f=%.2f)" % f)
	var home: Button = shell.find_child("HomeBalken", true, false)
	assert_true(home is SquishButton, "HomeBalken ist ein SquishButton (W16 F12)")
	# W21/P3: Kachel-Labels laufen auf der Caption-Stufe der Typo-Skala.
	var kachel_font := AcTokens.font_px(AcTokens.SIZE_CAPTION, f)
	var kacheln := 0
	for kachel: Node in shell.find_children("Kachel*", "VBoxContainer", true, false):
		for btn: Node in kachel.find_children("*", "Button", true, false):
			kacheln += 1
			assert_true(btn is SquishButton, "Kachel-Knopf ist SquishButton")
			assert_true(
				(btn as Control).custom_minimum_size.y >= maxf(84.0 * f, floor_px) - 0.5,
				"Kachel skaliert ×f (%s)" % kachel.name
			)
		var label: Label = kachel.find_child("*", true, false) as Label
		if label == null:
			for kind in kachel.get_children():
				if kind is Label:
					label = kind
		if label != null:
			assert_eq(
				label.get_theme_font_size("font_size"),
				kachel_font,
				"Kachel-Label-Font ×f (Caption→%d)" % kachel_font
			)
	assert_eq(kacheln, PhoneApps.ids().size(), "alle Apps haben eine Kachel")
	await _schliesse_shell(shell)
	await _unpin()


# ------------------------------------------------- Apps koppeln ans Gerät


func test_instant_feed_koppelt_an_die_geraetebreite() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	shell.oeffne_app("instant")
	await wait_frames(3)
	var app: Control = null
	for kind in tree.root.find_children("*", "InstantGoobyApp", true, false):
		app = kind
	assert_true(app != null, "InstantGooby hängt im Gerät")
	if app == null:
		await _schliesse_shell(shell)
		await _unpin()
		return
	# KEINE 420er-Mindestbreite mehr — die App füllt die reale Innenbreite.
	assert_almost(app.custom_minimum_size.x, 0.0, 0.5, "keine Fixbreite")
	var geraet: PanelContainer = shell.find_child("Geraet", true, false)
	var innen := geraet.size.x - 2.0 * PhoneShell.KARTEN_RAND
	assert_true(
		app.size.x <= innen + 0.5,
		"App (%.0f) bleibt in der Geräte-Innenbreite (%.0f)" % [app.size.x, innen]
	)
	assert_true(app.size.x >= 200.0, "App füllt die Karte sinnvoll (%.0f)" % app.size.x)
	_alle_buttons_squish(app, "InstantGooby")
	await _schliesse_shell(shell)
	await _unpin()


func test_fahrdienst_und_kamera_grammatik_und_floor() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	gs.state["inventory"]["items"][PowAngebote.KAMERA_ITEM] = 1
	var shell := await _oeffne_shell(gs)
	var m := ScreenShell.metrics(shell.get_viewport())
	var floor_px: float = m["floor_px"]
	shell.oeffne_app("taxi")
	await wait_frames(2)
	var rufen: Button = shell.find_child("RufenButton", true, false)
	assert_true(rufen is SquishButton, "Rufen ist SquishButton (W16 F13)")
	assert_true(rufen.custom_minimum_size.y >= floor_px - 0.5, "Rufen erreicht den Touch-Floor")
	assert_false(rufen.disabled, "mit 300 Münzen rufbar")
	shell.oeffne_app("kamera")
	await wait_frames(2)
	var starten: Button = shell.find_child("FotomodusStarten", true, false)
	assert_true(starten is SquishButton, "Fotomodus-Start ist SquishButton (W16 F12)")
	assert_true(starten.custom_minimum_size.y >= floor_px - 0.5, "Start erreicht den Touch-Floor")
	await _schliesse_shell(shell)
	await _unpin()


# -------------------------------------------------------------- Fotomodus


func test_fotomodus_hochformat_safe_area_und_floor() -> void:
	await _pin(Vector2i(720, 1280))
	# Notch oben (90 px) + Home-Indicator unten (40 px) simulieren — das
	# Override ist ein Safe-Rect in CANVAS-Koordinaten (Stretch: die Canvas
	# ist im Hochformat 1280 breit, nicht 720).
	var canvas := Vector2(tree.root.get_visible_rect().size)
	UiScale.insets_override = Rect2(0.0, 90.0, canvas.x, canvas.y - 130.0)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var rig := FakeRig.new()
	tree.root.add_child(rig)
	var gs := FakeGameState.new()
	var modus := FotoModus.new()
	modus.gs = gs
	modus.rig_override = rig
	tree.root.add_child(modus)
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var floor_px: float = m["floor_px"]
	var leiste: HBoxContainer = modus.find_child("TopLeiste", true, false)
	assert_true(leiste != null, "Top-Leiste existiert (Zurück/Selfie aus den Ecken)")
	assert_almost(leiste.offset_top, 90.0 + 12.0 * f, 0.5, "Top-Leiste hängt UNTER der Notch")
	var fertig: Button = modus.find_child("FertigButton", true, false)
	assert_true(fertig is SquishButton, "Fertig ist SquishButton")
	assert_true(fertig.custom_minimum_size.y >= floor_px - 0.5, "Fertig erreicht den Floor")
	assert_true(modus._selfie_button != null, "Selfie-Knopf existiert (Gooby im Bild)")
	assert_eq(modus._selfie_button.get_parent(), leiste, "Selfie sitzt in der Top-Leiste")
	var ausloeser: Button = modus.find_child("Ausloeser", true, false)
	assert_true(ausloeser is SquishButton, "Auslöser ist SquishButton")
	assert_almost(
		ausloeser.offset_bottom, -(40.0 + 24.0 * f), 0.5, "Auslöser über dem Home-Indicator"
	)
	assert_true(
		ausloeser.custom_minimum_size.y >= maxf(64.0 * f, floor_px) - 0.5, "Auslöser ≥ Floor"
	)
	# Hochformat: Werkzeuge als Reihen-Block überm Auslöser (BOTTOM_WIDE).
	var werkzeuge: VBoxContainer = modus.find_child("Werkzeuge", true, false)
	assert_almost(werkzeuge.anchor_top, 1.0, 0.01, "Reihen kleben unten")
	assert_almost(werkzeuge.anchor_left, 0.0, 0.01, "Reihen über die Breite")
	assert_almost(werkzeuge.offset_left, 0.0 + 16.0 * f, 0.5, "Reihen in der Safe-Area")
	for art in ["pose", "emotion", "rahmen"]:
		assert_true(modus._werkzeug_chips.has(art), "Werkzeug-Reihe existiert: %s" % art)
	var chip_min := maxf(44.0 * f, floor_px)
	for chips: Variant in modus._werkzeug_chips.values():
		for chip in (chips as BoxContainer).get_children():
			assert_true(chip is SquishButton, "Chip ist SquishButton")
			assert_true(
				(chip as Control).custom_minimum_size.y >= chip_min - 0.5,
				"Chip erreicht den Touch-Floor"
			)
	modus.schliessen()
	await wait_frames(2)
	rig.queue_free()
	await _unpin()


func test_fotomodus_querformat_baut_werkzeug_spalte() -> void:
	await _pin(Vector2i(1280, 720))
	# Seitliche Insets (Notch links/rechts im Querformat) + 20 px unten.
	UiScale.insets_override = Rect2(44.0, 0.0, 1192.0, 700.0)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var rig := FakeRig.new()
	tree.root.add_child(rig)
	var modus := FotoModus.new()
	modus.gs = FakeGameState.new()
	modus.rig_override = rig
	tree.root.add_child(modus)
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var werkzeuge: VBoxContainer = modus.find_child("Werkzeuge", true, false)
	assert_almost(werkzeuge.anchor_left, 1.0, 0.01, "Querformat: Werkzeuge als RECHTE Spalte")
	assert_almost(werkzeuge.anchor_top, 0.5, 0.01, "Spalte vertikal zentriert")
	assert_almost(
		werkzeuge.offset_right, -(44.0 + 16.0 * f), 0.5, "Spalte respektiert den Seiten-Inset"
	)
	# Regressions-Wächter: ohne explizite top/bottom-Offsets wüchse die
	# Spalte um y=0 (set_anchors_preset erhält das leere Alt-Rect) und
	# ragte oben aus dem Bild.
	var safe_mitte := (0.0 + 720.0 - 20.0) / 2.0
	assert_almost(
		werkzeuge.position.y + werkzeuge.size.y / 2.0,
		safe_mitte,
		4.0,
		"Spalte sitzt in der Mitte des Safe-Bands"
	)
	assert_true(werkzeuge.position.y >= 0.0, "Spalte beginnt im Bild (nicht abgeschnitten)")
	# Spalten-Scroller laufen VERTIKAL (statt sich unten zu stapeln).
	var scroller_gesehen := 0
	for scroller: Node in werkzeuge.find_children("*", "ScrollContainer", false, false):
		scroller_gesehen += 1
		assert_eq(
			(scroller as ScrollContainer).horizontal_scroll_mode,
			ScrollContainer.SCROLL_MODE_DISABLED,
			"Spalten-Scroller scrollt nicht horizontal"
		)
	assert_eq(scroller_gesehen, 3, "drei Werkzeug-Gruppen in der Spalte")
	for art in ["pose", "emotion", "rahmen"]:
		var chips: BoxContainer = modus._werkzeug_chips.get(art)
		assert_true(chips is VBoxContainer, "Spalten-Chips stapeln vertikal: %s" % art)
	# Rotation ins Hochformat baut die Reihen-Variante neu.
	UiScale.insets_override = Rect2()
	tree.root.size = Vector2i(720, 1280)
	tree.root.size_changed.emit()
	await wait_frames(3)
	werkzeuge = modus.find_child("Werkzeuge", true, false)
	assert_almost(werkzeuge.anchor_top, 1.0, 0.01, "nach Rotation: Reihen unten")
	assert_true(
		modus._werkzeug_chips.get("rahmen") is HBoxContainer, "Reihen-Chips liegen horizontal"
	)
	modus.schliessen()
	await wait_frames(2)
	rig.queue_free()
	await _unpin()


# ------------------------------------------------------------- SnapAGooby


func test_snap_hinweis_unter_notch_und_countdown_font() -> void:
	await _pin(Vector2i(720, 1280))
	var canvas := Vector2(tree.root.get_visible_rect().size)
	UiScale.insets_override = Rect2(0.0, 90.0, canvas.x, canvas.y - 90.0)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var szene := Node.new()
	tree.root.add_child(szene)
	var snap := SnapAGooby.starte(szene, FakeGameState.new())
	await wait_frames(1)
	var f := UiScale.for_viewport(tree.root)
	var hinweis: Label = snap.find_child("Hinweis", true, false)
	assert_almost(hinweis.offset_top, 90.0 + 16.0 * f, 0.5, "Hinweis hängt UNTER der Notch")
	var zahl: Label = snap.find_child("Countdown", true, false)
	assert_eq(zahl.get_theme_font_size("font_size"), int(120.0 * f), "Countdown-Font ×f")
	# Insets ändern sich (Rotation/anderes Gerät) → Layout zieht nach.
	UiScale.insets_override = Rect2(0.0, 40.0, canvas.x, canvas.y - 40.0)
	tree.root.size_changed.emit()
	await wait_frames(2)
	assert_almost(hinweis.offset_top, 40.0 + 16.0 * f, 0.5, "Resize wendet die Insets neu an")
	szene.queue_free()
	await _unpin()


# ------------------------------------------------------- GoobyPal-Verlauf


func test_goobypal_verlauf_liste_skaliert() -> void:
	await _pin(Vector2i(1280, 720))
	var eintraege: Array = [{"dir": "out", "peer": "GOOBY-X", "amount": 5, "at": 1700000000000}]
	var liste := GoobyPalVerlauf.build_liste(eintraege, {}, 1700000000, 0)
	var scroll: ScrollContainer = liste.find_child("VerlaufScroll", true, false)
	assert_almost(scroll.custom_minimum_size.y, 190.0, 0.5, "f=1: Designhöhe")
	liste.free()
	tree.root.size = Vector2i(1440, 2560)
	tree.root.size_changed.emit()
	await wait_frames(2)
	var f := UiScale.for_viewport(tree.root)
	assert_true(f > 1.5, "Hochkant-Canvas skaliert hoch (f=%.2f)" % f)
	liste = GoobyPalVerlauf.build_liste(eintraege, {}, 1700000000, 0)
	scroll = liste.find_child("VerlaufScroll", true, false)
	assert_almost(scroll.custom_minimum_size.y, 190.0 * f, 0.5, "Hochkant: Höhe ×f")
	liste.free()
	await _unpin()


func test_social_apps_ohne_fixbreite() -> void:
	await _pin(Vector2i(1280, 720))
	var box: Control = PhoneSocialApps.goobypal(
		FakeGameState.new(), func(_f: Dictionary) -> void: pass
	)
	assert_almost(box.custom_minimum_size.x, 0.0, 0.5, "GoobyPal-Box ohne 420er-Fixbreite")
	box.free()
	await _unpin()
