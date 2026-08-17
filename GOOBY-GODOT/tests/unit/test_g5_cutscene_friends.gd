extends TestCase
## G5/P34 CUTSCENE-FRIENDS — Geometrie- und Grammatik-Verträge:
## (1) Kino-Metrikpass (P17-Request): Skip-Chip als SquishButton IN der
##     Safe-Area mit physischem 44-pt-Touch-Floor, Untertitel ×f ÜBER dem
##     Home-Indicator (Bottom-Inset), Resize/Rotation wendet die Insets neu
##     an (Muster RecapScene G4/P17).
## (2) Freunde-App (P18-Request): mountet als ECHTES Telefon-Layout im
##     IGohbie (kein eingebetteter Vollbild-Screen mehr) und koppelt an die
##     PhoneShell-Helfer-Breiten; offline degradiert sie freundlich.
## (3) Gooberando (P18→P16-Request): Breiten-Regression — die App-Ansicht
##     hängt an PhoneShell.inhalt_breite() statt am 420er-Sheet-Fallback,
##     der breiter als das 380er-Gerät war.
## Geometrie-Tests pinnen das Fenster VOR dem Bau (Muster test_g4_phone).

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


## Minimaler Raum-Host (Muster test_cutscene_player): Ops degradieren zu No-ops.
class FakeRoom:
	extends Node3D


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


# ------------------------------------------------------------- Kino (P17)


func test_kino_skip_und_untertitel_in_der_safe_area() -> void:
	await _pin(Vector2i(1280, 720))
	# Kino-Querformat: Notch LINKS/RECHTS (44 px) + Home-Indicator (20 px).
	UiScale.insets_override = Rect2(44.0, 0.0, 1192.0, 700.0)
	tree.root.size_changed.emit()
	await wait_frames(1)
	var room := FakeRoom.new()
	tree.root.add_child(room)
	var player: CutscenePlayer = CutscenePlayer.play_in_room(room, null, "wake_morning")
	player._build_overlay()
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var tf := UiScale.font_scale(tree.root)
	var insets: Dictionary = m["insets"]
	var floor_px: float = m["floor_px"]
	var skip: Button = player._skip_button
	assert_true(skip is SquishButton, "Skip ist ein SquishButton (W16-Grammatik)")
	assert_true(skip.custom_minimum_size.y >= floor_px - 0.5, "Skip erreicht den Touch-Floor")
	assert_true(skip.custom_minimum_size.x >= floor_px - 0.5, "Skip-Floor auch in der Breite")
	assert_almost(
		skip.offset_top, float(insets["top"]) + 16.0 * f, 0.5, "Skip hängt unter der Safe-Kante"
	)
	assert_almost(
		skip.offset_right,
		-(float(insets["right"]) + 16.0 * f),
		0.5,
		"Skip respektiert den rechten Inset (Notch im Querformat)"
	)
	player._op_caption("Gooby gähnt sich wach.")
	var caption: Label = player._caption
	assert_true(caption.visible, "Untertitel sichtbar nach caption-Op")
	assert_almost(
		caption.offset_bottom,
		-(float(insets["bottom"]) + 40.0 * f),
		0.5,
		"Untertitel bleibt über dem Home-Indicator"
	)
	assert_almost(
		caption.offset_top, caption.offset_bottom - 56.0 * f, 0.5, "Untertitel-Band ist 56·f hoch"
	)
	assert_almost(
		caption.offset_left,
		float(insets["left"]) + 24.0 * f,
		0.5,
		"Untertitel respektiert den linken Inset"
	)
	assert_eq(caption.get_theme_font_size("font_size"), int(26.0 * tf), "Untertitel-Font 26 ×f")
	# Insets ändern sich (Rotation/anderes Gerät) → Layout zieht nach.
	UiScale.insets_override = Rect2(0.0, 90.0, 1280.0, 590.0)
	tree.root.size_changed.emit()
	await wait_frames(2)
	m = ScreenShell.metrics(tree.root)
	insets = m["insets"]
	assert_almost(
		skip.offset_top, float(insets["top"]) + 16.0 * f, 0.5, "Resize wendet die Insets neu an"
	)
	assert_almost(
		caption.offset_bottom,
		-(float(insets["bottom"]) + 40.0 * f),
		0.5,
		"Untertitel folgt dem neuen Bottom-Inset"
	)
	player._teardown()
	player.queue_free()
	room.queue_free()
	await _unpin()


func test_kino_untertitel_skaliert_hochkant_mit_f() -> void:
	await _pin(Vector2i(1440, 2560))
	var room := FakeRoom.new()
	tree.root.add_child(room)
	var player: CutscenePlayer = CutscenePlayer.play_in_room(room, null, "wake_morning")
	player._build_overlay()
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var tf := UiScale.font_scale(tree.root)
	assert_true(f > 1.5, "Hochkant-Canvas skaliert hoch (f=%.2f)" % f)
	var caption: Label = player._caption
	assert_eq(caption.get_theme_font_size("font_size"), int(26.0 * tf), "Untertitel-Font ×f")
	assert_almost(caption.offset_bottom, -(40.0 * f), 0.5, "Untertitel-Abstand skaliert ×f")
	var skip: Button = player._skip_button
	assert_true(
		skip.custom_minimum_size.y >= float(m["floor_px"]) - 0.5, "Skip hält den Floor hochkant"
	)
	assert_almost(skip.offset_top, 16.0 * f, 0.5, "Skip-Abstand skaliert ×f")
	player._teardown()
	player.queue_free()
	room.queue_free()
	await _unpin()


# ------------------------------------------------------ Freunde-App (P18)


func _oeffne_shell(gs: FakeGameState) -> PhoneShell:
	var shell := PhoneShell.oeffne(tree.root, gs)
	await wait_frames(2)
	return shell


func _finde_freunde_app() -> PhoneFriendsApp:
	var app: PhoneFriendsApp = null
	for kind in tree.root.find_children("*", "PhoneFriendsApp", true, false):
		app = kind
	return app


func test_friends_app_mountet_im_telefon_mit_helfer_breiten() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	shell.oeffne_app("freunde")
	await wait_frames(3)
	var app := _finde_freunde_app()
	assert_ne(app, null, "Freunde-App hängt im Gerät")
	if app == null:
		shell.schliesse()
		await _unpin()
		return
	# Kein eingebetteter Vollbild-Screen mehr in der Handy-Fläche.
	assert_eq(
		tree.root.find_children("*", "SocialScreen", true, false).size(),
		0,
		"kein SocialScreen im Gerät"
	)
	# Helfer-Breiten: keine Fixbreite, App bleibt in der Geräte-Innenbreite.
	assert_almost(app.custom_minimum_size.x, 0.0, 0.5, "keine Fixbreite")
	var geraet: PanelContainer = shell.find_child("Geraet", true, false)
	var innen := geraet.size.x - 2.0 * PhoneShell.KARTEN_RAND
	assert_true(
		app.size.x <= innen + 0.5,
		"App (%.0f) bleibt in der Geräte-Innenbreite (%.0f)" % [app.size.x, innen]
	)
	assert_true(app.size.x >= 200.0, "App füllt die Karte sinnvoll (%.0f)" % app.size.x)
	var hinweis: Label = app._offline_hinweis
	assert_almost(
		hinweis.custom_minimum_size.x,
		PhoneShell.text_breite(),
		0.5,
		"Hinweis-Label nutzt die Helfer-Textbreite"
	)
	# Offline-Degradation: Code „—“, Kopieren/Senden gesperrt, Hinweis an.
	var code: Label = app.find_child("CodeWert", true, false)
	assert_eq(code.text, "—", "ohne Netz zeigt die Karte —")
	assert_true(hinweis.visible, "Offline-Hinweis sichtbar")
	var senden: Button = app.find_child("AnfrageSenden", true, false)
	assert_true(senden.disabled, "Senden ist offline gesperrt")
	var kopieren: Button = app.find_child("KopierenButton", true, false)
	assert_true(kopieren.disabled, "ohne Code gibt es nichts zu kopieren")
	# Grammatik + Floor: alle klickbaren Knöpfe sind SquishButtons ≥ Floor.
	var m := ScreenShell.metrics(shell.get_viewport())
	var floor_px: float = m["floor_px"]
	var geprueft := 0
	for btn: Node in app.find_children("*", "Button", true, false):
		if (btn as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue  # Anzeige-Chip (StatusChip) ist bewusst nicht klickbar.
		geprueft += 1
		assert_true(btn is SquishButton, "'%s' ist ein SquishButton" % btn.name)
		assert_true(
			(btn as Control).custom_minimum_size.y >= floor_px - 0.5,
			"'%s' erreicht den Touch-Floor" % btn.name
		)
	assert_true(geprueft >= 2, "Scan sieht Kopieren+Senden (%d)" % geprueft)
	shell.schliesse()
	await wait_frames(2)
	await _unpin()


func test_friends_app_anfragen_und_freundeszeilen() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	shell.oeffne_app("freunde")
	await wait_frames(3)
	var app := _finde_freunde_app()
	assert_ne(app, null, "Freunde-App hängt im Gerät")
	if app == null:
		shell.schliesse()
		await _unpin()
		return
	# Anfrage-Zeile: Karte mit Annehmen/Ablehnen (SquishButtons ≥ Floor).
	app._render_anfragen([{"from": "GOOBY-TEST", "name": "Mira", "goobyName": "Flauschi"}])
	await wait_frames(2)
	var m := ScreenShell.metrics(shell.get_viewport())
	var floor_px: float = m["floor_px"]
	var annehmen: Button = app.find_child("Annehmen", true, false)
	var ablehnen: Button = app.find_child("Ablehnen", true, false)
	assert_ne(annehmen, null, "Annehmen-Knopf steht")
	assert_ne(ablehnen, null, "Ablehnen-Knopf steht")
	for btn: Button in [annehmen, ablehnen]:
		if btn == null:
			continue
		assert_true(btn is SquishButton, "Anfrage-Knopf '%s' squisht" % btn.name)
		assert_true(
			btn.custom_minimum_size.y >= floor_px - 0.5,
			"Anfrage-Knopf '%s' hält den Floor" % btn.name
		)
	assert_true(app._anfragen_titel.visible, "Anfragen-Titel sichtbar bei offener Anfrage")
	# Leere Anfragen blenden die Sektion wieder aus.
	app._render_anfragen([])
	await wait_frames(1)
	assert_false(app._anfragen_titel.visible, "Anfragen-Titel weg ohne Anfragen")
	# Freundes-Zeile: Presence + Name + Münzen in einer Karte.
	var freund := {
		"name": "Mira",
		"goobyName": "Flauschi",
		"online": true,
		"coins": 42,
		"activity": {"kind": "park"},
	}
	app._render_freunde([freund])
	await wait_frames(2)
	var karten := 0
	for panel: Node in app._liste.find_children("*", "PanelContainer", true, false):
		karten += 1
	assert_true(karten >= 1, "Freundes-Karte steht in der Liste")
	var namen_gefunden := false
	for label: Node in app._liste.find_children("*", "Label", true, false):
		if (label as Label).text.begins_with("Mira"):
			namen_gefunden = true
	assert_true(namen_gefunden, "Freundes-Name steht in der Zeile")
	shell.schliesse()
	await wait_frames(2)
	await _unpin()


# ---------------------------------------------- Gooberando-Breiten (P16)


func test_gooberando_koppelt_an_die_geraetebreite() -> void:
	await _pin(Vector2i(1280, 720))
	var gs := FakeGameState.new()
	var shell := await _oeffne_shell(gs)
	shell.oeffne_app("gooberando")
	await wait_frames(3)
	var app: GooberandoApp = null
	for kind in tree.root.find_children("*", "GooberandoApp", true, false):
		app = kind
	assert_ne(app, null, "GOOBERANDO hängt im Gerät")
	if app == null:
		shell.schliesse()
		await _unpin()
		return
	# Breiten-Regression (G1 ui-post §4): kein 420er-Fallback mehr — die
	# App-Ansicht hängt an der realen Geräte-Innenbreite der PhoneShell.
	assert_almost(app.custom_minimum_size.x, 0.0, 0.5, "keine Fixbreite mehr")
	assert_almost(
		app.inhalt_breite(),
		PhoneShell.inhalt_breite(),
		0.5,
		"inhalt_breite = PhoneShell-Innenbreite"
	)
	var geraet: PanelContainer = shell.find_child("Geraet", true, false)
	var innen := geraet.size.x - 2.0 * PhoneShell.KARTEN_RAND
	assert_true(
		app.size.x <= innen + 0.5,
		"App (%.0f) bleibt in der Geräte-Innenbreite (%.0f)" % [app.size.x, innen]
	)
	assert_true(app.inhalt_breite() < innen + 0.5, "Inhaltsbreite passt ins Gerät")
	# Fließtexte nutzen den app_label-Baustein (Helfer-Textbreite).
	var text_breite := PhoneShell.text_breite()
	var gekoppelt := 0
	for label: Node in app.find_children("*", "Label", true, false):
		if absf((label as Label).custom_minimum_size.x - text_breite) <= 0.5:
			gekoppelt += 1
	assert_true(gekoppelt >= 1, "Fließtext koppelt an die Helfer-Textbreite (%d)" % gekoppelt)
	# Live-Karten-Kante bleibt in der Geräte-Innenbreite (Klemme greift).
	assert_true(app.karten_kante() <= innen + 0.5, "Live-Karte passt ins Gerät")
	# Rotation: die Shell baut die App neu — die FRISCHE Instanz koppelt
	# wieder an die (jetzt ×f gewachsene) Geräte-Innenbreite.
	tree.root.size = Vector2i(1440, 2560)
	tree.root.size_changed.emit()
	await wait_frames(3)
	var f := UiScale.for_viewport(tree.root)
	assert_true(f > 1.5, "Hochkant-Canvas skaliert hoch (f=%.2f)" % f)
	var neu: GooberandoApp = null
	for kind in tree.root.find_children("*", "GooberandoApp", true, false):
		if not (kind as Node).is_queued_for_deletion():
			neu = kind
	assert_ne(neu, null, "Rotation baut die App neu")
	if neu != null:
		assert_almost(
			neu.inhalt_breite(),
			PhoneShell.inhalt_breite(),
			0.5,
			"nach Rotation: Breite folgt der PhoneShell"
		)
	shell.schliesse()
	await wait_frames(2)
	await _unpin()
