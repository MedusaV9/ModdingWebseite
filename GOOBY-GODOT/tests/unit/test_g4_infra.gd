extends TestCase
## G4/P21 INFRA-FEINSCHLIFF — Wächter für die geteilten UI-Grundbausteine:
## PanelSheet-Close-Animation + Signal-Vertrag (QW #5), Open-Tween-Stapel-
## Fix (QW #23), _relayout ohne queue_free-pendente Kinder (P17-Request),
## zentraler ToastLayer.zeige-Helfer (QW #17), HUD-Gruppe für die Finder
## (QW #18), Leveling._int_or-0-Falle (QW #24) und die Settings-Vertonung
## (Deferred-Punkt der G2-Sound-Fixliste) — alles headless prüfbar.

const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const BUBBLE_SCENE := preload("res://scripts/ui/dialog_bubble.tscn")
const SETTINGS_SCENE := preload("res://scripts/ui/settings_screen.tscn")
const Leveling := preload("res://scripts/logic/leveling.gd")


## Settings-Vertonung ohne Screen-Ballast: nackte Basis-Klasse als Probe.
class RowsProbe:
	extends SettingsRowsBasis


func _audio_played() -> Dictionary:
	var audio := tree.root.get_node_or_null("/root/Audio")
	if audio == null:
		return {}
	return audio.get("_last_played_msec")


func _mount_sheet() -> PanelSheet:
	PanelStack.clear()
	var host := Control.new()
	host.name = "P21Host"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(sheet)
	return sheet


func _unmount_sheet(sheet: PanelSheet) -> void:
	sheet.get_parent().queue_free()
	PanelStack.clear()
	await wait_frames(1)


func _ui_theme() -> Node:
	return tree.root.get_node_or_null("/root/UiTheme")


## ------------------------------------------------------ PanelSheet (QW #5)


func test_panel_sheet_close_faded_aus_signal_sofort() -> void:
	var sheet := _mount_sheet()
	var inhalt := Label.new()
	inhalt.text = "P21-Close-Probe"
	sheet.add_content(inhalt)
	sheet.open()
	await wait_frames(20)
	var karte := sheet.get_node("Sheet") as Control
	var rest_y := karte.position.y
	var box := {"closed": 0}
	sheet.closed.connect(func() -> void: box["closed"] += 1)
	sheet.close()
	# VERTRAG (Signal-Audit): closed feuert SOFORT, Stack ist sofort sauber —
	# nur das AUSBLENDEN ist animiert (Aufrufer queue_free()en direkt danach).
	assert_eq(box["closed"], 1, "closed feuert synchron im close()")
	assert_false(sheet.is_open(), "logisch sofort zu")
	assert_eq(PanelStack.count(), 0, "sofort vom PanelStack abgemeldet")
	assert_true(sheet.visible, "Fade läuft: noch sichtbar (Reduced Motion aus)")
	var blocker := sheet.get_node("FadeBlocker") as Control
	assert_true(blocker.visible, "Input-Schlucker deckt das Fade-Fenster ab")
	var zu := await wait_until(func() -> bool: return not sheet.visible, 2000)
	assert_true(zu, "nach der Animation ist das Sheet versteckt")
	assert_false(blocker.visible, "Input-Schlucker ist nach dem Fade weg")
	assert_almost(karte.position.y, rest_y, 1.0, "Ruhelage fürs nächste open() steht")
	assert_almost(karte.modulate.a, 1.0, 0.001, "Deckkraft zurückgesetzt")
	await _unmount_sheet(sheet)


func test_panel_sheet_close_reduced_motion_sofort() -> void:
	var svc := _ui_theme()
	if svc == null or not ("reduced_motion" in svc):
		return
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = true
	var sheet := _mount_sheet()
	var inhalt := Label.new()
	inhalt.text = "RM-Probe"
	sheet.add_content(inhalt)
	sheet.open()
	await wait_frames(2)
	sheet.close()
	assert_false(sheet.visible, "Reduced Motion: sofort versteckt, kein Fade")
	assert_false(sheet.is_open(), "logisch zu")
	svc.reduced_motion = vorher
	await _unmount_sheet(sheet)


func test_panel_sheet_reopen_mitten_im_fade_wandert_nicht() -> void:
	# QW #23: close→open, während der Fade/Feder-Tween noch läuft, darf die
	# Ruhelage nicht verschieben (früher wanderte das Blatt pro Zyklus +60).
	var sheet := _mount_sheet()
	var inhalt := Label.new()
	inhalt.text = "Tween-Stapel-Probe"
	sheet.add_content(inhalt)
	sheet.open()
	await wait_frames(20)
	var karte := sheet.get_node("Sheet") as Control
	var rest_y := karte.position.y
	sheet.close()
	sheet.open()
	await wait_frames(25)
	assert_almost(karte.position.y, rest_y, 1.0, "Ruhelage nach close→open identisch")
	assert_almost(karte.modulate.a, 1.0, 0.01, "voll eingeblendet")
	assert_true(sheet.visible and sheet.is_open(), "Sheet ist offen")
	sheet.close()
	await _unmount_sheet(sheet)


func test_panel_sheet_relayout_ignoriert_pendente_kinder() -> void:
	# P17-Request: queue_free-pendente _body-Kinder dürfen weder Messung
	# (Guard in _relayout) noch Layout blähen (add_content hängt sofort ab).
	var sheet := _mount_sheet()
	var gross := Control.new()
	gross.custom_minimum_size = Vector2(300.0, 400.0)
	sheet.add_content(gross)
	sheet.open()
	await wait_frames(3)
	var karte := sheet.get_node("Sheet") as Control
	var span_gross := karte.offset_bottom - karte.offset_top
	# Direktes queue_free (Muster mancher Inhalts-Skripte) + Relayout:
	# der pendente Riese zählt nicht mehr in die Wunschhöhe.
	gross.queue_free()
	sheet._relayout()
	var span_leer := karte.offset_bottom - karte.offset_top
	assert_true(
		span_leer < span_gross - 200.0,
		"pendentes Kind zählt nicht mit (vorher %.0f, nachher %.0f)" % [span_gross, span_leer]
	)
	# add_content ersetzt Alt-Inhalt SOFORT (kein pendenter Zwischenzustand).
	var klein := Control.new()
	klein.custom_minimum_size = Vector2(80.0, 60.0)
	sheet.add_content(klein)
	var body := sheet.get_node("%SheetBody") as Control
	assert_eq(body.get_child_count(), 1, "Alt-Inhalt ist sofort abgehängt")
	assert_true(body.get_child(0) == klein, "neuer Inhalt hängt im Body")
	sheet.close()
	await _unmount_sheet(sheet)


## ------------------------------------------------------ ToastLayer (QW #17)


func test_toast_zeige_helfer_und_gruppe() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var layer := ToastLayer.new()
	host.add_child(layer)
	await wait_frames(1)
	assert_true(layer.is_in_group(ToastLayer.GROUP), "ToastLayer meldet sich in der Gruppe an")
	ToastLayer.zeige(host, "P21-Toast")
	assert_true(layer.is_showing(), "zeige() erreicht den Layer über die Gruppe")
	# Fehler-Variante spielt den Fehler-Blip (wie die alte net_client-Kopie).
	ToastLayer.zeige(host, "P21-Fehler", true)
	assert_true(_audio_played().has("ui_error"), "error=true spielt ui_error")
	# Ohne Baum/mit null: stiller No-op statt Crash (alte Kopien crashten teils).
	ToastLayer.zeige(null, "nix")
	var lose := Node.new()
	ToastLayer.zeige(lose, "nix")
	lose.free()
	host.queue_free()
	await wait_frames(1)


## ------------------------------------------------------- HUD-Gruppe (QW #18)


func test_hud_gruppe_und_finder() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(1)
	assert_true(hud.is_in_group(&"hud"), "HUD registriert sich in der hud-Gruppe")
	var bubble: DialogBubble = BUBBLE_SCENE.instantiate()
	tree.root.add_child(bubble)
	await wait_frames(1)
	assert_true(bubble._find_hud() == hud, "DialogBubble findet das HUD über die Gruppe")
	var hint := WhatsNextHint.new()
	tree.root.add_child(hint)
	await wait_frames(1)
	assert_true(hint._find_hud() == hud, "WhatsNextHint findet das HUD über die Gruppe")
	bubble.queue_free()
	hint.queue_free()
	hud.queue_free()
	await wait_frames(1)


## -------------------------------------------------- Leveling._int_or (QW #24)


func test_leveling_int_or_behandelt_null_als_wert() -> void:
	assert_eq(Leveling._int_or(0, 7), 0, "gespeicherte 0 ist ein Wert, kein Fallback")
	assert_eq(Leveling._int_or(0.0, 7), 0, "0.0 ebenso")
	assert_eq(Leveling._int_or(2.9, 1), 2, "floort wie vorher")
	assert_eq(Leveling._int_or(null, 7), 7, "null fällt zurück")
	assert_eq(Leveling._int_or("x", 7), 7, "Nicht-Zahl fällt zurück")
	# Der Level-Fall bleibt über den Clamp am Aufrufer geschützt (min 1).
	var res := Leveling.apply_xp({"level": 0, "xp": 0.0}, 0.0)
	assert_eq(int(res["level"]), 1, "Level 0 im Save wird weiter auf 1 geklemmt")


## --------------------------------------- Settings-Vertonung (G2 „Deferred“)


func test_settings_rows_sounds_toggle_und_tick() -> void:
	var probe := RowsProbe.new()
	tree.root.add_child(probe)
	var rows := VBoxContainer.new()
	probe.add_child(rows)
	await wait_frames(1)
	var box := {"an": false, "wert": 0.5}
	var toggle := probe._add_switch_row(
		rows, "p21_toggle", "Probe", false, func(on: bool) -> void: box["an"] = on
	)
	var slider := probe._add_range_row(
		rows, "p21_slider", "Probe", 0.0, 1.0, 0.05, 0.5, func(v: float) -> void: box["wert"] = v
	)
	await wait_frames(1)
	toggle.button_pressed = true
	assert_true(bool(box["an"]), "Handler läuft weiter (Toggle)")
	assert_true(_audio_played().has("ui_toggle"), "Schalter klingt als ui_toggle")
	slider.value = 0.7
	assert_almost(float(box["wert"]), 0.7, 0.001, "Handler läuft weiter (Slider)")
	assert_true(_audio_played().has("ui_tick"), "Raststufe klingt als ui_tick")
	assert_true(slider.has_meta(SettingsRowsBasis.TICK_META), "Debounce-Stempel gesetzt")
	var stempel := int(slider.get_meta(SettingsRowsBasis.TICK_META))
	slider.value = 0.75
	assert_almost(float(box["wert"]), 0.75, 0.001, "Handler NIE gedrosselt, nur der Ton")
	assert_eq(
		int(slider.get_meta(SettingsRowsBasis.TICK_META)),
		stempel,
		"zweites Tick innerhalb %d ms bleibt stumm (Drossel)" % SettingsRowsBasis.TICK_DEBOUNCE_MS
	)
	probe.queue_free()
	await wait_frames(1)


func test_settings_screen_sounds_verdrahtet() -> void:
	I18nService.set_locale("de")
	var screen: Control = SETTINGS_SCENE.instantiate()
	tree.root.add_child(screen)
	await wait_frames(2)
	var gs := tree.root.get_node_or_null("/root/GameState")
	var vorher_seen := true
	if gs != null and gs.has_method("get_value"):
		vorher_seen = bool(gs.get_value("onboarding.whatsNew5Seen", true))
	# Zeilen-Button (Tutorial-Reset) → ui_click.
	var reset := screen.find_child("TutorialResetButton", true, false) as Button
	reset.pressed.emit()
	assert_true(_audio_played().has("ui_click"), "Zeilen-Button klingt als ui_click")
	if gs != null and gs.has_method("update"):
		gs.update(
			func(s: Dictionary) -> void:
				if s.get("onboarding") is Dictionary:
					s["onboarding"]["whatsNew5Seen"] = vorher_seen
		)
	# Zurück → ui_back.
	var back := screen.find_child("BackButton", true, false) as Button
	back.pressed.emit()
	assert_true(_audio_played().has("ui_back"), "Zurück klingt als ui_back")
	# Sprachwechsel (Segment-Auswahl) → ui_chip; zurückstellen inklusive.
	var lang_en := screen.find_child("LangEN", true, false) as Button
	lang_en.pressed.emit()
	assert_true(_audio_played().has("ui_chip"), "Sprachwechsel klingt als ui_chip")
	await wait_frames(4)
	var lang_de := screen.find_child("LangDE", true, false) as Button
	lang_de.pressed.emit()
	await wait_frames(4)
	assert_eq(I18nService.get_locale(), "de", "Sprache fürs Testende zurückgestellt")
	# News-Knopf bleibt BEWUSST stumm (öffnet PanelSheet → ui_open kommt
	# vom Blatt selbst; Doppel-Klang-Regel §3).
	var click_stempel := int(_audio_played().get("ui_click", -1))
	var news := screen.find_child("NewsButton", true, false) as Button
	news.pressed.emit()
	await wait_frames(2)
	assert_eq(
		int(_audio_played().get("ui_click", -1)),
		click_stempel,
		"News-Knopf spielt keinen eigenen Press-Sound"
	)
	assert_true(_audio_played().has("ui_open"), "das News-Panel selbst klingt als ui_open")
	var panel: Variant = screen.get("_news_panel")
	if panel is PanelSheet:
		(panel as PanelSheet).close()
	PanelStack.clear()
	screen.queue_free()
	await wait_frames(1)
