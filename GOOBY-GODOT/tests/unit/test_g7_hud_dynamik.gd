extends TestCase
## G7-P50 HUD-DYNAMIK — Wachen für das „HUD weicht“-Verhalten (iPhone-
## Feedback mit Screenshots):
## (a) Baumodus an → alle HUD-Hauptknöpfe unsichtbar + deaktiviert, keine
##     Rechteck-Überlappung mit den Bau-Dock-Knöpfen (FB3-Schnitt-Rechnung);
##     Baumodus aus → alles wieder da. Zusätzlich der animierte Pfad ohne
##     Reduced Motion (Tween endet im selben Endzustand).
## (b) Blatt offen → HUD weicht; ZÄHLER-Logik mit zwei Blättern, Blatt
##     während Baumodus, offen freigegebenes Blatt und HUD-eigenem
##     Status-Sheet (zählt nicht).
## (c) Label-Wache: kein Kachel-Label wird visuell abgeschnitten
##     (Font-Messung ≤ verfügbare Breite) in quer 2868×1320 (iPhone 17 Pro
##     Max — Leitformat), quer 2556×1179 und hoch 1179×2556; der „Wo ist
##     mein Gooby?“-Chip deckt seine Textbreite ab.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")
## Fenster-Formate der Label-Wache — [Fenster-px, screen_scale, Insets in
## PUNKTEN l/t/r/b], Rechnung wie fb3_ui_audit._audit_size (physische
## Retina-Skala + Notch, sonst misst der Test mit Desktop-f=1 am Gerät
## vorbei). 2868×1320 = iPhone 17 Pro Max quer (NEUES Leitformat).
const FORMATE: Array = [
	[Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]],
	[Vector2i(2556, 1179), 3.0, [59.0, 0.0, 59.0, 21.0]],
	[Vector2i(1179, 2556), 3.0, [0.0, 59.0, 0.0, 34.0]],
]
## FB3-Overlap-Toleranz: Schnitte ≤ 4×4 px gelten als Berührung, nicht Befund.
const OVERLAP_TOLERANZ := 4.0


## Fenster deterministisch pinnen (Muster test_g3_wardrobe: vor dem Bau
## pinnen + size_changed für Layout-Hörer feuern).
func _pin(fenster: Vector2i) -> void:
	tree.root.size = fenster
	tree.root.size_changed.emit()
	await wait_frames(2)


## Reduced Motion global setzen; gibt den vorherigen Zustand zurück.
func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func _hud_bauen() -> Hud:
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	return hud


## Rückkehr komplett: sichtbar, klickbar UND Deckkraft wieder bei 1.
func _kachel_wieder_da(kachel: Button) -> bool:
	return kachel.is_visible_in_tree() and not kachel.disabled and kachel.modulate.a >= 0.99


# ── (a) Baumodus ─────────────────────────────────────────────────────────────


func test_baumodus_blendet_hud_aus_und_wieder_ein() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin(Vector2i(2556, 1179))
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	var bau := BuildMode.new()
	tree.root.add_child(bau)
	await wait_frames(1)
	bau.opened.emit()
	await wait_frames(1)
	assert_true(hud.sichtbarkeit().verdeckt(), "Baumodus an → HUD verdeckt")
	assert_true(hud.sichtbarkeit().bau_aktiv(), "Baumodus-Zustand registriert")
	for id: StringName in hud._buttons:
		var btn: Button = hud._buttons[id]
		assert_false(btn.is_visible_in_tree(), "Kachel %s ist unsichtbar" % id)
		assert_true(btn.disabled, "Kachel %s ist deaktiviert" % id)
	assert_false((hud.get_node("TopBar") as Control).visible, "Status-Leiste weicht")
	assert_false(hud._eye_button.is_visible_in_tree(), "Auge weicht")
	assert_false(hud._gooby_chip.is_visible_in_tree(), "Gooby-Chip weicht")
	# Rechteck-Schnitt-Wache gegen das ECHTE Bau-Dock (FB3-Rechnung):
	# sichtbare HUD-Kacheln dürfen keine Dock-Knöpfe überlappen.
	var layer := CanvasLayer.new()
	tree.root.add_child(layer)
	var dock := BuildUiDock.new()
	dock.build(layer, BuildMode.EBENEN_KEYS)
	dock.ui.visible = true
	await wait_frames(2)
	var dock_rects: Array[Rect2] = []
	for knopf in dock.ui.find_children("*", "Button", true, false):
		if (knopf as Control).is_visible_in_tree():
			dock_rects.append((knopf as Control).get_global_rect())
	assert_true(dock_rects.size() > 0, "Bau-Dock liefert Knopf-Rechtecke")
	for id: StringName in hud._buttons:
		var btn: Button = hud._buttons[id]
		if not btn.is_visible_in_tree():
			continue
		for rect in dock_rects:
			var schnitt := btn.get_global_rect().intersection(rect)
			assert_false(
				schnitt.size.x > OVERLAP_TOLERANZ and schnitt.size.y > OVERLAP_TOLERANZ,
				"HUD-Kachel %s überlappt Bau-Dock: %s" % [id, schnitt]
			)
	# Rotation WÄHREND der Verdeckung: apply_layout blendet Dock/Spalte
	# selbst ein — nach_layout muss die Verdeckung erneut erzwingen, und die
	# Rückkehr muss die Sichtbarkeiten des NEUEN Layouts nutzen.
	tree.root.size = Vector2i(1179, 2556)
	tree.root.size_changed.emit()
	await wait_frames(2)
	for id: StringName in hud._buttons:
		assert_false(
			(hud._buttons[id] as Button).is_visible_in_tree(),
			"Kachel %s bleibt nach Rotation im Baumodus versteckt" % id
		)
	tree.root.size = Vector2i(2556, 1179)
	tree.root.size_changed.emit()
	await wait_frames(2)
	bau.closed.emit()
	await wait_frames(1)
	assert_false(hud.sichtbarkeit().verdeckt(), "Baumodus aus → HUD wieder da")
	var spalte := hud.find_child("LandscapeColumn", true, false) as Control
	assert_true(spalte.visible, "Cockpit-Spalte wieder sichtbar (Querformat)")
	# W20 P1 — Slimming / W21 P1 — Ruhe-Cockpit: im Cockpit sind nur die
	# RUHE-Aktionen sofort sichtbar; alles Weitere lebt hinter der
	# Mehr-Kachel und ist nach deren Aufklappen wieder komplett da.
	for id: StringName in HudButtonOrder.RUHE:
		var btn: Button = hud._buttons[id]
		assert_true(btn.is_visible_in_tree(), "Kachel %s wieder sichtbar" % id)
		assert_false(btn.disabled, "Kachel %s wieder aktiv" % id)
	var mehr := hud.find_child("BtnMehr", true, false) as Button
	assert_true(mehr.is_visible_in_tree(), "Mehr-Kachel wieder sichtbar")
	assert_false(mehr.disabled, "Mehr-Kachel wieder aktiv")
	mehr.pressed.emit()
	await wait_frames(1)
	for id: StringName in hud._buttons:
		var btn: Button = hud._buttons[id]
		assert_true(btn.is_visible_in_tree(), "Kachel %s nach Mehr-Aufklappen da" % id)
		assert_false(btn.disabled, "Kachel %s nach Mehr-Aufklappen aktiv" % id)
	mehr.pressed.emit()
	await wait_frames(1)
	layer.free()
	bau.free()
	hud.free()
	_set_reduced_motion(rm_vorher)
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


func test_baumodus_animiert_ohne_reduced_motion() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin(Vector2i(2556, 1179))
	var rm_vorher := _set_reduced_motion(false)
	var hud := _hud_bauen()
	await wait_frames(2)
	var bau := BuildMode.new()
	tree.root.add_child(bau)
	await wait_frames(1)
	var kachel: Button = hud._buttons[&"bau"]
	bau.opened.emit()
	# Eingaben sperren sofort, das Wegrutschen ist tween-animiert.
	assert_true(kachel.disabled, "Eingaben sofort deaktiviert (Animation läuft)")
	var weg := await wait_until(func() -> bool: return not kachel.is_visible_in_tree(), 3000)
	assert_true(weg, "Rutsch-Animation endet im versteckten Zustand")
	bau.closed.emit()
	# Sichtbar + aktiv gilt sofort beim Rückkehr-Start — fertig ist die
	# Animation erst, wenn die Staffel-Blende die Deckkraft normalisiert hat.
	var zurueck := await wait_until(_kachel_wieder_da.bind(kachel), 3000)
	assert_true(zurueck, "Rückkehr-Animation endet sichtbar + aktiv + deckend")
	assert_true(kachel.is_visible_in_tree(), "Kachel nach Rückkehr sichtbar")
	assert_false(kachel.disabled, "Kachel nach Rückkehr aktiv")
	bau.free()
	hud.free()
	_set_reduced_motion(rm_vorher)
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


# ── (b) Blätter/Modals ───────────────────────────────────────────────────────


func test_blatt_zaehler_zwei_blaetter_und_baumodus_mix() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	var blatt_a: PanelSheet = SHEET_SCENE.instantiate()
	var blatt_b: PanelSheet = SHEET_SCENE.instantiate()
	tree.root.add_child(blatt_a)
	tree.root.add_child(blatt_b)
	await wait_frames(1)
	blatt_a.open()
	await wait_frames(1)
	assert_true(hud.sichtbarkeit().verdeckt(), "1. Blatt offen → HUD weicht")
	assert_eq(hud.sichtbarkeit().blatt_zaehler(), 1, "Zähler = 1")
	blatt_b.open()
	await wait_frames(1)
	assert_eq(hud.sichtbarkeit().blatt_zaehler(), 2, "Zähler = 2")
	blatt_a.close()
	await wait_frames(1)
	assert_true(hud.sichtbarkeit().verdeckt(), "1 von 2 zu → HUD bleibt weg (Zähler!)")
	assert_eq(hud.sichtbarkeit().blatt_zaehler(), 1, "Zähler = 1 nach erstem Schließen")
	blatt_b.close()
	await wait_frames(1)
	assert_false(hud.sichtbarkeit().verdeckt(), "letztes Blatt zu → HUD kommt zurück")
	# Befund 18: der Gooby-Chip lebt quer hinter „Mehr“ — die Rückkehr-Wache
	# prüft eine RUHE-Kachel (in BEIDEN Layouts sichtbar).
	assert_true(
		(hud._buttons[&"igohbie"] as Button).is_visible_in_tree(), "Ruhe-Kachel wieder sichtbar"
	)
	assert_false((hud._buttons[&"quests"] as Button).disabled, "Kacheln wieder aktiv")
	# Blatt WÄHREND Baumodus: erst wenn BEIDE Gründe weg sind, kehrt das
	# HUD zurück (Reihenfolge-Robustheit).
	var bau := BuildMode.new()
	tree.root.add_child(bau)
	await wait_frames(1)
	bau.opened.emit()
	blatt_a.open()
	await wait_frames(1)
	bau.closed.emit()
	await wait_frames(1)
	assert_true(hud.sichtbarkeit().verdeckt(), "Baumodus zu, Blatt noch offen → weiter weg")
	blatt_a.close()
	await wait_frames(1)
	assert_false(hud.sichtbarkeit().verdeckt(), "beide Gründe weg → HUD zurück")
	# Offen FREIGEGEBENES Blatt (queue_free ohne close) leakt den Zähler nicht.
	blatt_b.open()
	await wait_frames(1)
	assert_true(hud.sichtbarkeit().verdeckt(), "Blatt offen → verdeckt")
	blatt_b.free()
	await wait_frames(1)
	assert_eq(hud.sichtbarkeit().blatt_zaehler(), 0, "freigegebenes Blatt zählt nicht mehr")
	assert_false(hud.sichtbarkeit().verdeckt(), "HUD nach Free wieder da")
	blatt_a.free()
	bau.free()
	hud.free()
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)


func test_eigenes_status_sheet_verdeckt_hud_nicht() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var hud := _hud_bauen()
	await wait_frames(2)
	hud.set_stats({"hunger": 50.0, "energie": 50.0, "hygiene": 50.0, "spass": 50.0})
	hud.open_status_sheet()
	await wait_frames(1)
	assert_false(
		hud.sichtbarkeit().verdeckt(), "HUD-eigenes Status-Sheet zählt nicht als Verdeckung"
	)
	assert_eq(hud.sichtbarkeit().blatt_zaehler(), 0, "Eigen-Sheet bleibt außen vor")
	hud._status_sheet.close()
	await wait_frames(1)
	hud.free()
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)


# ── (c) Label-Wache ──────────────────────────────────────────────────────────


func test_kachel_labels_nie_abgeschnitten_in_leitformaten() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	for format: Array in FORMATE:
		var fenster: Vector2i = format[0]
		var scale: float = format[1]
		var insets_pt: Array = format[2]
		UiScale.screen_scale_override = scale
		await _pin(fenster)
		# Notch/Home-Indicator wie im FB3-Audit in Canvas-px simulieren.
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var px_per_pt := minf(canvas.x, canvas.y) / (minf(fenster.x, fenster.y) / scale)
		var l := float(insets_pt[0]) * px_per_pt
		var t := float(insets_pt[1]) * px_per_pt
		var r := float(insets_pt[2]) * px_per_pt
		var b := float(insets_pt[3]) * px_per_pt
		UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)
		tree.root.size_changed.emit()
		await wait_frames(2)
		var hud := _hud_bauen()
		await wait_frames(2)
		for id: StringName in hud._buttons:
			var btn: Button = hud._buttons[id]
			var font := btn.get_theme_font("font")
			var px := btn.get_theme_font_size("font_size")
			var avail := HudMehrCluster.label_breite(btn)
			var breite := HudLabelFit.text_breite(font, btn.text, px)
			assert_true(
				breite <= avail + 0.5,
				(
					"%s: „%s“ (%d px) misst %.1f > verfügbar %.1f @ %s"
					% [id, btn.text, px, breite, avail, fenster]
				)
			)
			assert_eq(
				btn.text_overrun_behavior,
				TextServer.OVERRUN_NO_TRIMMING,
				"%s braucht kein Ellipsis @ %s" % [id, fenster]
			)
		# „Wo ist mein Gooby?“-Chip: Mindestbreite deckt die Textbreite.
		var chip: Button = hud._gooby_chip
		var chip_breite := HudLabelFit.text_breite(
			chip.get_theme_font("font"), chip.text, chip.get_theme_font_size("font_size")
		)
		assert_true(
			chip.custom_minimum_size.x >= chip_breite,
			(
				"Gooby-Chip-Mindestbreite %.1f deckt Text %.1f @ %s"
				% [chip.custom_minimum_size.x, chip_breite, fenster]
			)
		)
		assert_eq(
			chip.text_overrun_behavior,
			TextServer.OVERRUN_NO_TRIMMING,
			"Gooby-Chip ohne Ellipsis @ %s" % fenster
		)
		hud.free()
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)
