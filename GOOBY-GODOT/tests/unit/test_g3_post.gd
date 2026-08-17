extends TestCase
## G3/P07 UI-POST: MailSheet-Skalierung (card_width/×f/Touch-Floor +
## SquishButton-Scan), Compose-Guard gegen Dim-Tap-Datenverlust und der
## Post-Schalter (Touch-Floor der Knöpfe, Ungelesen-Badge als StatusCapsule).


class FakeGameState:
	extends RefCounted
	var s: Dictionary = {
		"city": {},
		"vacation": {"postcards": 2},
		"economy": {"coins": 100, "coinsEarned": 0, "coinsSpent": 0},
		"inventory": {"food": {}, "items": {}},
	}

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


# ------------------------------------------------------------- MailSheet


func test_mail_karte_nutzt_card_width_und_hoehen_deckel() -> void:
	var sheet := await _baue_mail_sheet()
	var m := ScreenShell.metrics(sheet.get_viewport())
	var karte: PanelContainer = sheet.find_child("MailKarte", true, false)
	assert_true(karte != null, "MailKarte existiert")
	assert_almost(
		karte.custom_minimum_size.x,
		ScreenShell.card_width(m, MailSheet.CARD_BASIS.x),
		0.5,
		"Kartenbreite kommt aus ScreenShell.card_width"
	)
	var deckel := minf(MailSheet.CARD_BASIS.y * float(m["f"]), ScreenShell.card_max_height(m))
	assert_almost(karte.custom_minimum_size.y, deckel, 0.5, "Kartenhöhe ist safe-gedeckelt")
	sheet.free()


func test_mail_buttons_sind_squish_und_erreichen_den_floor() -> void:
	var sheet := await _baue_mail_sheet()
	var m := ScreenShell.metrics(sheet.get_viewport())
	var floor_px: float = m["floor_px"]
	var geprueft := 0
	for btn: Node in sheet.find_children("*", "Button", true, false):
		geprueft += 1
		if not (btn is OptionButton):
			assert_true(btn is SquishButton, "'%s' ist ein SquishButton" % btn.name)
		var ctl := btn as Control
		assert_true(
			ctl.custom_minimum_size.y >= floor_px - 0.5,
			"'%s' erreicht den Touch-Floor (%.0f px)" % [btn.name, floor_px]
		)
	assert_true(geprueft >= 7, "Scan sieht die Mail-Knöpfe (inkl. Schließen + Compose)")
	assert_true(
		sheet.find_child("SchliessenButton", true, false) != null,
		"expliziter Schließen-Knopf existiert"
	)
	sheet.free()


func test_compose_guard_schuetzt_den_entwurf() -> void:
	var sheet := await _baue_mail_sheet()
	var geschlossen := [0]
	sheet.closed.connect(func() -> void: geschlossen[0] += 1)
	sheet._zeige_compose()
	await wait_frames(1)
	var text: TextEdit = sheet.find_child("BriefText", true, false)
	text.text = "Liebe Grüße, Gooby"

	# Daneben-Tippen: Nachfrage-Karte statt Datenverlust.
	sheet._on_dim_input(_klick())
	await wait_frames(1)
	var dialog: Control = sheet.find_child("VerwerfenDialog", true, false)
	assert_true(dialog != null, "Dim-Tap zeigt die Nachfrage-Karte")
	assert_eq(geschlossen[0], 0, "Sheet ist NICHT geschlossen")

	# Weiterschreiben: Karte weg, Entwurf unangetastet.
	var weiter: Button = dialog.find_child("WeiterschreibenButton", true, false)
	weiter.pressed.emit()
	await wait_frames(2)
	assert_true(
		sheet.find_child("VerwerfenDialog", true, false) == null, "Nachfrage-Karte geschlossen"
	)
	assert_eq(text.text, "Liebe Grüße, Gooby", "Entwurf bleibt erhalten")
	assert_eq(geschlossen[0], 0, "Sheet lebt weiter")

	# Zweiter Dim-Tap + bewusstes Wegwerfen → jetzt schließt das Sheet.
	sheet._on_dim_input(_klick())
	await wait_frames(1)
	dialog = sheet.find_child("VerwerfenDialog", true, false)
	assert_true(dialog != null, "Nachfrage-Karte kommt wieder")
	var verwerfen: Button = dialog.find_child("VerwerfenButton", true, false)
	verwerfen.pressed.emit()
	await wait_frames(2)
	assert_eq(geschlossen[0], 1, "Wegwerfen schließt den Briefkasten")
	if is_instance_valid(sheet):
		sheet.free()


func test_dim_tap_ohne_entwurf_schliesst_direkt() -> void:
	var sheet := await _baue_mail_sheet()
	var geschlossen := [0]
	sheet.closed.connect(func() -> void: geschlossen[0] += 1)
	sheet._on_dim_input(_klick())
	await wait_frames(2)
	assert_eq(geschlossen[0], 1, "Inbox-Zustand: Dim-Tap schließt sofort")
	assert_false(is_instance_valid(sheet), "Sheet ist abgeräumt")


func test_leerer_compose_schliesst_ohne_nachfrage() -> void:
	var sheet := await _baue_mail_sheet()
	var geschlossen := [0]
	sheet.closed.connect(func() -> void: geschlossen[0] += 1)
	sheet._zeige_compose()
	await wait_frames(1)
	sheet._on_dim_input(_klick())
	await wait_frames(2)
	assert_eq(geschlossen[0], 1, "leerer Entwurf braucht keine Nachfrage")


# ------------------------------------------------------------- Post-Ort


func test_post_schalter_knoepfe_squish_und_floor() -> void:
	var gs := FakeGameState.new()
	var sheet := PostSheet.new()
	sheet.gs = gs
	tree.root.add_child(sheet)
	await wait_frames(1)
	var m := ScreenShell.metrics(sheet.get_viewport())
	for name: String in ["PaketHolen", "ArchivAnsehen"]:
		var btn: Button = sheet.find_child(name, true, false)
		assert_true(btn != null, "%s existiert" % name)
		assert_true(btn is SquishButton, "%s ist ein SquishButton" % name)
		assert_true(
			btn.custom_minimum_size.y >= float(m["floor_px"]) - 0.5,
			"%s erreicht den Touch-Floor" % name
		)
	sheet.free()


func test_ungelesen_badge_ist_status_capsule() -> void:
	var badge := OrtPost.baue_ungelesen_badge(3)
	assert_eq(String(badge.theme_type_variation), "StatusCapsule", "Capsule-Variation")
	assert_true(badge.visible, "sichtbar bei n > 0")
	var label := badge.get_node("Zahl") as Label
	assert_true(label.text.contains("3"), "Zähler steht im Badge")
	OrtPost.setze_ungelesen_badge(badge, 0)
	assert_false(badge.visible, "bei 0 unsichtbar statt „0 neu“")
	OrtPost.setze_ungelesen_badge(badge, 7)
	assert_true(badge.visible and label.text.contains("7"), "Live-Update zieht den Stand mit")
	badge.free()


# ------------------------------------------------------------- Helfer


func _baue_mail_sheet() -> MailSheet:
	var sheet := MailSheet.new()
	tree.root.add_child(sheet)
	await wait_frames(2)
	return sheet


func _klick() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev
