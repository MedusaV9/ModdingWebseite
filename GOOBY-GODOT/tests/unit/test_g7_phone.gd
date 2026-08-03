extends TestCase
## G7/P52 IGOHBIE-TELEFON-REWORK — Wachen fürs User-Feedback (Screenshot vom
## echten iPhone, Querformat): (1) JEDE App-Kachel hat ein geladenes Icon +
## Label, gesperrte Apps sind KEIN dunkler Blob mehr (das INK_FAINT-Modulate
## der Kamera) sondern blass + Schloss-Badge; (2) Labels passen ohne
## Abschneiden in die Kachelbreite (Font-Messung, DE+EN); (3) HomeBalken
## erreicht den 44-pt-Touch-Floor (FB3-Altbefund 40,2 pt); (4) Querformat-
## Leitformat 2868×1320: breites Gerät, ≥4 Spalten, Kacheln ⊆ Gerät, Labels
## ⊆ Scroll-Sichtfenster, Statusleiste sitzt sauber; (5) Wisch-Gesten per
## Drag-Synthese (runter = schließen/zurück, von links = zurück aufs Grid);
## (6) Öffnen-Pop mit Reduced-Motion-Gate. Fenster werden gepinnt und am
## Testende zurückgestellt (Muster test_g4_phone).

## Leitformat iPhone 17 Pro Max (physische px, Screen-Scale 3 → 956×440 pt).
const IPHONE_HOCH := Vector2i(1179, 2556)
const IPHONE_QUER := Vector2i(2868, 1320)
const IPHONE_SCALE := 3.0

var _saved_root_size := Vector2i.ZERO


## GameState-Double (Muster test_g4_phone): dotted get/set + update().
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


# ------------------------------------------------------------------ Helfer


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


## Reduced Motion am ECHTEN UiTheme-Autoload schalten; liefert den Vorzustand
## (null = Autoload fehlt). Geometrie-Tests laufen mit RM=an deterministisch.
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


func _oeffne_shell(gs: FakeGameState) -> PhoneShell:
	var shell := PhoneShell.oeffne(tree.root, gs)
	await wait_frames(3)
	return shell


func _schliesse_shell(shell: PhoneShell) -> void:
	shell.schliesse()
	await wait_frames(2)


func _kachel_von(shell: PhoneShell, app_id: String) -> VBoxContainer:
	return shell.find_child("Kachel%s" % app_id.capitalize(), true, false)


func _kachel_button(kachel: VBoxContainer) -> Button:
	for kind in kachel.get_children():
		if kind is Button:
			return kind
	return null


func _kachel_label(kachel: VBoxContainer) -> Label:
	for kind in kachel.get_children():
		if kind is Label:
			return kind
	return null


## Drag-Folge auf dem Gerät synthetisieren (InputEventScreenDrag): `start`
## ist die lokale Startposition, `schritt` der Weg PRO Ereignis.
func _wische(shell: PhoneShell, start: Vector2, schritt: Vector2, schritte: int) -> void:
	var pos := start
	for _i in schritte:
		pos += schritt
		var drag := InputEventScreenDrag.new()
		drag.position = pos
		drag.relative = schritt
		shell._on_geraet_input(drag)
	# Loslassen: Touch-Ende setzt den Gesten-Speicher zurück.
	var ende := InputEventScreenTouch.new()
	ende.pressed = false
	ende.position = pos
	shell._on_geraet_input(ende)


## Label-Breiten-Wache: jedes Kachel-Label passt einzeilig in seine Kachel
## (Font-Messung mit dem ECHTEN Theme-Font in der aktuellen Sprache).
func _pruefe_label_breiten(shell: PhoneShell, kontext: String) -> void:
	for app: Dictionary in PhoneApps.alle():
		var id := str(app["id"])
		var kachel := _kachel_von(shell, id)
		if kachel == null:
			fail_test("%s: Kachel fehlt (%s)" % [kontext, id])
			continue
		var label := _kachel_label(kachel)
		if label == null:
			fail_test("%s: Label fehlt (%s)" % [kontext, id])
			continue
		var font := label.get_theme_font("font")
		var groesse := label.get_theme_font_size("font_size")
		var text_px := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, groesse)
		assert_true(
			text_px.x <= label.custom_minimum_size.x + 0.5,
			(
				"%s: Label „%s“ passt in die Kachel (%.1f ≤ %.1f px)"
				% [kontext, label.text, text_px.x, label.custom_minimum_size.x]
			)
		)


# ------------------------------------------------------- Icon + Label-Wache


func test_alle_kacheln_haben_icon_und_label_ohne_blob() -> void:
	var rm: Variant = _set_reduced_motion(true)
	await _pin(Vector2i(1440, 2560))
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	for app: Dictionary in PhoneApps.alle():
		var id := str(app["id"])
		var kachel := _kachel_von(shell, id)
		assert_true(kachel != null, "%s: Kachel existiert" % id)
		if kachel == null:
			continue
		var btn := _kachel_button(kachel)
		assert_true(btn != null, "%s: Kachel-Knopf existiert" % id)
		if btn == null:
			continue
		# Icon geladen und das RICHTIGE (kein leerer Platzhalter).
		assert_true(btn.icon != null, "%s: Icon geladen" % id)
		if btn.icon != null:
			assert_eq(
				(btn.icon as Texture2D).resource_path,
				PhoneApps.icon_pfad(id),
				"%s: Icon-Pfad stimmt" % id
			)
			assert_true(btn.icon.get_width() > 0, "%s: Icon-Textur hat Pixel" % id)
		# Kein Dunkel-Blob: modulate bleibt neutral (Farbe unangetastet).
		assert_true(
			btn.modulate.is_equal_approx(Color.WHITE),
			"%s: kein dunkles Modulate auf der Kachel" % id
		)
		assert_almost(btn.self_modulate.r, 1.0, 0.01, "%s: Farbkanal bleibt" % id)
		var badge: TextureRect = kachel.find_child("SchlossBadge", true, false)
		if id == "kamera":
			# Gesperrt = blass + Schloss, NICHT dunkel multipliziert.
			assert_almost(btn.self_modulate.a, PhoneShell.GESPERRT_ALPHA, 0.01, "Kamera: blass")
			assert_true(badge != null, "Kamera: Schloss-Badge sitzt auf der Kachel")
			if badge != null:
				assert_true(badge.texture != null, "Schloss-Icon geladen")
		else:
			assert_almost(btn.self_modulate.a, 1.0, 0.01, "%s: voll sichtbar" % id)
			assert_true(badge == null, "%s: kein Schloss" % id)
		# Label vorhanden, übersetzt und nicht leer.
		var label := _kachel_label(kachel)
		assert_true(label != null, "%s: Label existiert" % id)
		if label != null:
			assert_false(label.text.is_empty(), "%s: Label-Text nicht leer" % id)
			assert_ne(label.text, str(app["name_key"]), "%s: Label übersetzt" % id)
	await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


func test_labels_passen_in_die_kacheln_de_und_en() -> void:
	var rm: Variant = _set_reduced_motion(true)
	var locale_vorher := I18nService.get_locale()
	var gs := FakeGameState.new()
	# Hochformat (3 Spalten) UND Quer-Leitformat (mehr, schmalere Spalten).
	for format: Vector2i in [Vector2i(1179, 2556), Vector2i(2868, 1320)]:
		await _pin(format, IPHONE_SCALE)
		var shell := await _oeffne_shell(gs)
		for locale: String in ["de", "en"]:
			I18nService.set_locale(locale)
			shell.zeige_grid()
			await wait_frames(2)
			_pruefe_label_breiten(shell, "%s/%s" % [format, locale])
		I18nService.set_locale(locale_vorher)
		await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


# ------------------------------------------------------- HomeBalken-Floor


func test_home_balken_erreicht_den_touch_floor_iphone_hoch() -> void:
	var rm: Variant = _set_reduced_motion(true)
	await _pin(IPHONE_HOCH, IPHONE_SCALE)
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	var m := ScreenShell.metrics(shell.get_viewport())
	var floor_px: float = m["floor_px"]
	var home: Button = shell.find_child("HomeBalken", true, false)
	assert_true(home != null, "HomeBalken existiert")
	if home != null:
		assert_true(
			home.custom_minimum_size.y >= floor_px - 0.5,
			(
				"HomeBalken-Minimum erreicht den Touch-Floor (%.1f ≥ %.1f px)"
				% [home.custom_minimum_size.y, floor_px]
			)
		)
		assert_true(home.size.y >= floor_px - 0.5, "reale Höhe ≥ Floor")
		# FB3-Altbefund: 40,2 pt < 44 pt — jetzt in PUNKTEN nachgemessen.
		var px_pro_pt := UiScale.touch_px_per_pt(shell.get_viewport())
		var punkte := home.size.y / px_pro_pt
		assert_true(punkte >= 44.0 - 0.1, "HomeBalken ≥ 44 pt (ist %.1f pt)" % punkte)
	await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


# ------------------------------------------------ Querformat-Leitformat


func test_querformat_leitformat_grid_layout() -> void:
	var rm: Variant = _set_reduced_motion(true)
	await _pin(IPHONE_QUER, IPHONE_SCALE)
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	await wait_frames(2)
	var m := ScreenShell.metrics(shell.get_viewport())
	var f: float = m["f"]
	assert_true(PhoneShell.ist_querformat(m), "Leitformat ist quer")
	var geraet: PanelContainer = shell.find_child("Geraet", true, false)
	# Breite Quer-Basis statt schmaler Hochkant-Karte im Höhen-Deckel.
	assert_true(
		geraet.custom_minimum_size.x > 380.0 * f + 1.0,
		"Gerät nutzt die Breite (%.0f > %.0f)" % [geraet.custom_minimum_size.x, 380.0 * f]
	)
	var grid: GridContainer = shell.find_child("AppGrid", true, false)
	assert_true(grid != null, "AppGrid existiert")
	assert_true(grid.columns >= 4, "quer: mehr Spalten statt Riesen-Abstände (%d)" % grid.columns)
	# Kacheln ⊆ Gerät + Mindestabstände in der Reihe.
	var geraet_rect := geraet.get_global_rect().grow(1.0)
	var scroll: ScrollContainer = shell._inhalt.get_parent()
	var scroll_rect := scroll.get_global_rect().grow(1.0)
	var kacheln: Array = shell.find_children("Kachel*", "VBoxContainer", true, false)
	assert_eq(kacheln.size(), PhoneApps.ids().size(), "alle Apps im Grid")
	var reihen: Dictionary = {}
	for kachel: Control in kacheln:
		var rect := kachel.get_global_rect()
		assert_true(geraet_rect.encloses(rect), "%s ⊆ Gerät" % kachel.name)
		var label := _kachel_label(kachel)
		if label != null:
			assert_true(
				scroll_rect.encloses(label.get_global_rect()),
				"%s: Label voll im Scroll-Sichtfenster (nicht abgeschnitten)" % kachel.name
			)
		var reihe := int(roundf(rect.position.y))
		if not reihen.has(reihe):
			reihen[reihe] = []
		(reihen[reihe] as Array).append(rect)
	for reihe: int in reihen:
		var rects: Array = reihen[reihe]
		rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
		for i in range(1, rects.size()):
			var luecke: float = (rects[i] as Rect2).position.x - (rects[i - 1] as Rect2).end.x
			assert_true(
				luecke >= PhoneShell.GRID_LUECKE * f - 1.0,
				"Mindestabstand in der Reihe (%.1f px)" % luecke
			)
	# Statusleiste sitzt sauber: Uhr zeigt HH:MM und liegt im Gerät.
	var uhr: Label = shell._uhr
	assert_eq(uhr.text.length(), 5, "Uhr zeigt HH:MM")
	assert_true(geraet_rect.encloses(uhr.get_global_rect()), "Uhr liegt im Gerät")
	var status: HBoxContainer = shell.find_child("Statusleiste", true, false)
	assert_true(geraet_rect.encloses(status.get_global_rect()), "Statusleiste ⊆ Gerät")
	await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


# ------------------------------------------------------------ Wisch-Gesten


func test_wisch_gesten_schliessen_und_navigieren() -> void:
	var rm: Variant = _set_reduced_motion(true)
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	# Runterwischen auf dem GRID schließt das Telefon.
	var shell := await _oeffne_shell(gs)
	var zustand := {"zu": false}
	shell.geschlossen.connect(func() -> void: zustand["zu"] = true)
	_wische(shell, Vector2(300.0, 100.0), Vector2(0.0, 30.0), 4)
	await wait_frames(2)
	assert_true(zustand["zu"], "Runterwisch auf dem Grid schließt das Telefon")
	# Von-links-Wisch in einer App führt zurück aufs Grid (Telefon bleibt auf).
	shell = await _oeffne_shell(gs)
	var zustand2 := {"zu": false}
	shell.geschlossen.connect(func() -> void: zustand2["zu"] = true)
	shell.oeffne_app("taxi")
	await wait_frames(2)
	assert_eq(shell.aktive_app, "taxi", "Taxi-App ist offen")
	_wische(shell, Vector2(10.0, 300.0), Vector2(30.0, 0.0), 4)
	await wait_frames(2)
	assert_eq(shell.aktive_app, "", "Links-Wisch: zurück aufs Grid")
	assert_false(zustand2["zu"], "Links-Wisch schließt NICHT das Telefon")
	# Rechts-Wisch aus der Geräte-MITTE navigiert nicht (keine Rand-Geste).
	shell.oeffne_app("taxi")
	await wait_frames(2)
	_wische(shell, Vector2(300.0, 300.0), Vector2(30.0, 0.0), 4)
	await wait_frames(2)
	assert_eq(shell.aktive_app, "taxi", "Mitten-Wisch bleibt in der App")
	# Runterwischen IN der App geht zurück aufs Grid (Bestandsgeste).
	_wische(shell, Vector2(300.0, 100.0), Vector2(0.0, 30.0), 4)
	await wait_frames(2)
	assert_eq(shell.aktive_app, "", "Runterwisch in der App: zurück aufs Grid")
	await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


# ------------------------------------------------------- Öffnen-Animation


func test_oeffnen_animation_poppt_und_respektiert_rm() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	# RM AUS: das Gerät startet klein/transparent und federt auf 1,0 hoch.
	var rm: Variant = _set_reduced_motion(false)
	var shell := PhoneShell.oeffne(tree.root, gs)
	await wait_frames(1)
	var geraet: PanelContainer = shell.find_child("Geraet", true, false)
	assert_true(geraet.scale.x < 1.0, "Öffnen-Pop läuft (Scale %.2f < 1)" % geraet.scale.x)
	var fertig := await wait_until(func() -> bool: return geraet.scale.is_equal_approx(Vector2.ONE))
	assert_true(fertig, "Pop endet in der Ruhelage (Scale 1)")
	assert_almost(geraet.modulate.a, 1.0, 0.05, "voll eingeblendet")
	await _schliesse_shell(shell)
	# RM AN: sofort Endzustand, keine Bewegung.
	_set_reduced_motion(true)
	shell = PhoneShell.oeffne(tree.root, gs)
	await wait_frames(1)
	geraet = shell.find_child("Geraet", true, false)
	assert_true(geraet.scale.is_equal_approx(Vector2.ONE), "RM: keine Pop-Bewegung")
	assert_almost(geraet.modulate.a, 1.0, 0.001, "RM: sofort sichtbar")
	await _schliesse_shell(shell)
	await _unpin()
	_restore_reduced_motion(rm)


# -------------------------------------------------------- Spalten-Fenster


func test_grid_spalten_fenster() -> void:
	assert_eq(PhoneShell.grid_spalten(340.0, 1.0), 3, "schmal: nie unter 3 Spalten")
	assert_eq(PhoneShell.grid_spalten(604.0, 1.0), 5, "Quer-Basis f=1: 5 Spalten")
	assert_eq(PhoneShell.grid_spalten(5000.0, 1.0), 5, "Deckel bei 5 Spalten")
	assert_eq(PhoneShell.grid_spalten(464.0, 1.0), 4, "4 Kacheln + Lücken → 4 Spalten")


# ------------------------------------------------- Statusleiste live (B8)


## GameState-Double MIT den echten Store-Signalen (PT2-B8): die Shell hört
## auf coins_changed/stats_changed, der Basis-Fake oben hat sie bewusst
## nicht (has_signal-Wache bleibt so mitgetestet).
class FakeGameStateMitSignalen:
	extends FakeGameState
	signal coins_changed(coins: int)
	signal stats_changed(stats: Dictionary)


func test_statusleiste_folgt_buchungen_live() -> void:
	# PT2-B8: Nach der GOOBERANDO-Bestellung (−19 ᴳ) zeigte die Status-
	# Zeile weiter „300“, während das HUD 281 zeigte — erst ein App-/
	# Grid-Wechsel aktualisierte sie. Jetzt folgt sie den Signalen sofort.
	var rm: Variant = _set_reduced_motion(true)
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameStateMitSignalen.new()
	var shell := await _oeffne_shell(gs)
	var muenzen: Label = shell._muenzen
	var akku: ProgressBar = shell._akku
	assert_eq(muenzen.text, "300", "Öffnen zeigt den Startstand")
	gs.set_value("economy.coins", 281)
	gs.coins_changed.emit(281)
	assert_eq(muenzen.text, "281", "Buchung aktualisiert die Leiste OHNE App-Wechsel")
	gs.set_value("gooby.stats.energy", 55.0)
	gs.stats_changed.emit({"energy": 55.0})
	assert_almost(akku.value, 55.0, 0.01, "Akku folgt stats_changed live")
	await _schliesse_shell(shell)
	# Basis-Fake OHNE Signale: Öffnen darf nicht krachen (has_signal-Wache).
	var stumm := FakeGameState.new()
	var shell2 := await _oeffne_shell(stumm)
	assert_eq((shell2._muenzen as Label).text, "300", "stummer Store: Leiste steht trotzdem")
	await _schliesse_shell(shell2)
	await _unpin()
	_restore_reduced_motion(rm)
