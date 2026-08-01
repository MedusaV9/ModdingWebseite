extends TestCase
## G3 P06 UI-SOCIAL — Wächter für den Sozial-Cluster:
## (a) SquishButton-Scan (Muster F5, EIGENE Datei — test_w16_sound_haptik.gd
##     gehört in G3 P09) über SocialScreen, VisitHud, EmoteWheel und
##     GoobyPalSheet inkl. Quell-Tripwire gegen nackte Button.new()-Rückfälle,
## (b) VisitHud-Layout-Verträge: Selfie/Bauen in der zentrierten
##     Bottom-Aktionszeile (kein Ecken-Kleber), Flow-Umbruch, Touch-Floor,
## (c) VisitManager-Knöpfe: AC-Theme + Einreihen in die HUD-Aktionszeile
##     (Fallback: eigener Safe-Area-Layer),
## (d) GoobyPal-Overlay: PanelStack-Policy + close()-Pfad (ui_close),
## (e) Friends-Anfrage-Knöpfe: Touch-Floor >= 44 pt (dynamische Zeilen).

const SOZIAL_DIR := "res://scripts/ui/social"

## Datei → Sound-Ids, die der jeweilige Handler-Satz spielen MUSS (F6/F8).
const SOUND_SOLL := {
	"res://scripts/ui/social/social_screen.gd": ["ui_back", "ui_confirm", "ui_click", "ui_open"],
	"res://scripts/ui/social/visit_hud.gd": ["ui_close", "ui_click", "ui_chip", "ui_toggle"],
	"res://scripts/ui/social/emote_wheel.gd": ["ui_chip"],
	"res://scripts/ui/social/goobypal_sheet.gd": ["ui_tick", "ui_confirm", "ui_error", "ui_close"],
	"res://scripts/multiplayer/visit_manager.gd": ["ui_click", "ui_confirm"],
}

## Datei → erlaubte Anzahl nackter Button.new() (Status-Chip ist bewusst
## KEIN SquishButton — MOUSE_FILTER_IGNORE, reine Anzeige).
const NACKTE_BUTTONS_ERLAUBT := {
	"res://scripts/ui/social/social_screen.gd": 1,
	"res://scripts/ui/social/visit_hud.gd": 0,
	"res://scripts/ui/social/emote_wheel.gd": 0,
	"res://scripts/ui/social/goobypal_sheet.gd": 0,
	"res://scripts/ui/social/tomato_overlay.gd": 0,
	"res://scripts/multiplayer/visit_manager.gd": 0,
}


## Mini-Fake der VisitScene: nur was VisitManager._baue_ui braucht.
class FakeBesuchsSzene:
	extends Node

	var role := "host"
	var hud: VisitHud = null


## Wie FakeBesuchsSzene, aber OHNE hud-Slot → Fallback-Layer-Pfad.
class FakeSzeneOhneHud:
	extends Node

	var role := "host"


# ── Helfer ───────────────────────────────────────────────────────────────────


## F5-Muster: jeder interaktive Knopf im Teilbaum ist ein SquishButton
## (OptionButton-Dropdowns + Anzeige-Chips mit MOUSE_FILTER_IGNORE sind raus).
func _assert_alle_buttons_squish(root: Node, kontext: String) -> void:
	var buttons := root.find_children("*", "Button", true, false)
	assert_true(not buttons.is_empty(), "%s: Scan findet Buttons" % kontext)
	for btn: Node in buttons:
		if btn is OptionButton or (btn as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		assert_true(btn is SquishButton, "%s: '%s' ist kein SquishButton" % [kontext, btn.name])


# ── (a) SquishButton-Scans ───────────────────────────────────────────────────


func test_social_screen_buttons_sind_squish() -> void:
	var services := SocialServices.new()
	tree.root.add_child(services)
	var screen := SocialScreen.new()
	screen.services_override = services
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	screen._on_friends_changed(
		[{"name": "Mia", "goobyName": "Flauschi", "online": true, "friendCode": "GOOBY-A"}]
	)
	screen._add_incoming_card("Anfrage", "Ja", "Nein", func() -> void: pass, func() -> void: pass)
	await wait_frames(1)
	_assert_alle_buttons_squish(screen, "SocialScreen")
	# Status-Chip bleibt bewusst reine Anzeige (nicht interaktiv).
	assert_eq(screen._status_chip.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Chip ignoriert Maus")
	# Anfrage-Karten-Knöpfe haben jetzt den Touch-Floor (g1 2.9.1).
	var m := ScreenShell.metrics(screen.get_viewport())
	for btn: Node in screen._incoming_box.find_children("*", "Button", true, false):
		assert_true(
			(btn as Control).custom_minimum_size.y >= float(m["floor_px"]) - 0.01,
			"Anfrage-Knopf '%s' unter Touch-Floor" % btn.name
		)
	screen.queue_free()
	services.queue_free()
	await wait_frames(1)


func test_emote_wheel_buttons_sind_squish() -> void:
	var wheel := EmoteWheel.new()
	tree.root.add_child(wheel)
	await wait_frames(1)
	_assert_alle_buttons_squish(wheel, "EmoteWheel")
	wheel.queue_free()
	await wait_frames(1)


# ── (b) VisitHud: Layout-Verträge ────────────────────────────────────────────


func test_visit_hud_squish_und_aktionszeile() -> void:
	var hud := VisitHud.new()
	tree.root.add_child(hud)
	await wait_frames(1)
	var rooms: Array[String] = ["living", "kitchen", "bedroom"]
	hud.set_rooms(rooms, "living")
	hud.enable_build_controls([{"item": "bedSingle"}, {"item": "loungeSofa"}])
	await wait_frames(1)
	_assert_alle_buttons_squish(hud, "VisitHud")
	# Selfie raus aus der linken Ecke, Bauen raus aus der rechten: beide
	# sitzen in der zentrierten Bottom-Aktionszeile.
	assert_eq(hud._selfie_button.get_parent(), hud._actions_box, "Selfie in Aktionszeile")
	assert_eq(hud._build_button.get_parent(), hud._actions_box, "Bauen in Aktionszeile")
	# Raum-/Bau-Leisten brechen im Hochformat um (HFlowContainer).
	assert_true(hud._rooms_box is HFlowContainer, "Raumleiste bricht um")
	assert_true(hud._build_bar is HFlowContainer, "Bau-Leiste bricht um")
	# Beenden-Knopf sitzt in der Kopfzeile (Teilbaum von _top), nicht mehr
	# als Ecken-Kleber direkt am Root.
	assert_true(hud._top.is_ancestor_of(hud._end_button), "Beenden in der Kopfzeile")
	# Touch-Floor auf statischen UND dynamischen Knöpfen.
	var m := ScreenShell.metrics(hud.get_viewport())
	var floor_px := float(m["floor_px"])
	for btn: Node in [hud._end_button, hud._selfie_button, hud._remove_button]:
		assert_true(
			(btn as Control).custom_minimum_size.y >= floor_px - 0.01,
			"'%s' unter Touch-Floor" % btn.name
		)
	for btn: Node in hud._rooms_box.get_children():
		assert_true(
			(btn as Control).custom_minimum_size.y >= floor_px - 0.01,
			"Raum-Knopf unter Touch-Floor"
		)
	hud.queue_free()
	await wait_frames(1)


# ── (c) VisitManager-Knöpfe ──────────────────────────────────────────────────


func test_visit_manager_knoepfe_in_hud_aktionszeile() -> void:
	var fake := FakeBesuchsSzene.new()
	tree.root.add_child(fake)
	var hud := VisitHud.new()
	fake.add_child(hud)
	fake.hud = hud
	await wait_frames(1)
	var manager := VisitManager.new()
	fake.add_child(manager)
	manager.setup(fake, true)
	await wait_frames(1)
	assert_true(manager._wake_button is SquishButton, "Aufwecken ist SquishButton")
	assert_true(manager._fahrt_button is SquishButton, "Fahrt ist SquishButton (Host)")
	assert_ne(str(manager._wake_button.theme_type_variation), "", "Aufwecken im AC-Theme")
	assert_ne(str(manager._fahrt_button.theme_type_variation), "", "Fahrt im AC-Theme")
	assert_eq(manager._wake_button.get_parent(), hud._actions_box, "Aufwecken in HUD-Zeile")
	assert_eq(manager._fahrt_button.get_parent(), hud._actions_box, "Fahrt in HUD-Zeile")
	assert_false(manager._wake_button.visible, "Aufwecken startet versteckt (Bestand)")
	assert_true(manager._ui_layer == null, "kein eigener Ecken-Layer mehr, wenn HUD da ist")
	fake.queue_free()
	await wait_frames(1)


func test_visit_manager_fallback_layer_ohne_hud() -> void:
	var fake := FakeSzeneOhneHud.new()
	tree.root.add_child(fake)
	var manager := VisitManager.new()
	fake.add_child(manager)
	manager.setup(fake, true)
	await wait_frames(1)
	assert_true(manager._ui_layer != null, "ohne HUD: eigener Layer als Fallback")
	assert_true(manager._wake_button is SquishButton, "Fallback-Aufwecken ist SquishButton")
	var m := ScreenShell.metrics(manager.get_viewport())
	assert_true(
		manager._wake_button.custom_minimum_size.y >= float(m["floor_px"]) - 0.01,
		"Fallback-Knopf unter Touch-Floor"
	)
	fake.queue_free()
	await wait_frames(1)


# ── (d) GoobyPal-Overlay: PanelStack + close()-Pfad ─────────────────────────


func test_goobypal_sheet_squish_panelstack_und_close() -> void:
	PanelStack.clear()
	var sheet := GoobyPalSheet.new()
	tree.root.add_child(sheet)
	await wait_frames(1)
	_assert_alle_buttons_squish(sheet, "GoobyPalSheet")
	assert_true(PanelStack.is_top(sheet), "Sheet meldet sich am PanelStack an")
	var geschlossen := [0]
	sheet.closed.connect(func() -> void: geschlossen[0] += 1)
	# Back-Geste/Escape-Pfad: PanelStack.close_top ruft close().
	assert_true(PanelStack.close_top(), "close_top schließt das Overlay")
	await wait_frames(1)
	assert_eq(geschlossen[0], 1, "closed-Signal feuert genau einmal")
	assert_eq(PanelStack.count(), 0, "Sheet ist vom Stack abgemeldet")
	await wait_frames(1)


# ── (e) Friends: Anfrage-Knöpfe Touch-Floor ─────────────────────────────────


func test_friends_anfrage_knoepfe_haben_touch_floor() -> void:
	var screen := FriendsScreen.new()
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(1)
	screen._on_requests_changed([{"name": "Mia", "goobyName": "Flauschi", "from": "GOOBY-X"}])
	await wait_frames(1)
	var m := ScreenShell.metrics(screen.get_viewport())
	var buttons := screen._requests_box.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 2, "Annehmen + Ablehnen gefunden")
	for btn: Node in buttons:
		assert_true(
			(btn as Control).custom_minimum_size.y >= float(m["floor_px"]) - 0.01,
			"Anfrage-Knopf '%s' unter Touch-Floor" % btn.name
		)
	screen.queue_free()
	await wait_frames(1)


# ── Quell-Tripwires (Sounds + keine nackten Buttons) ─────────────────────────


func test_sound_ids_sind_verdrahtet_und_gemappt() -> void:
	for pfad: String in SOUND_SOLL:
		var quelle := FileAccess.get_file_as_string(pfad)
		assert_true(not quelle.is_empty(), "Quelle lädt: %s" % pfad)
		for id: String in SOUND_SOLL[pfad]:
			assert_true(SfxMap.SOUNDS.has(id), "SfxMap kennt '%s'" % id)
			assert_true(
				quelle.contains('try_play(self, "%s"' % id), "%s: try_play '%s' fehlt" % [pfad, id]
			)


func test_keine_nackten_buttons_im_sozial_cluster() -> void:
	var nackt := RegEx.new()
	nackt.compile("(?<!Squish)Button\\.new\\(")
	for pfad: String in NACKTE_BUTTONS_ERLAUBT:
		var quelle := FileAccess.get_file_as_string(pfad)
		assert_true(not quelle.is_empty(), "Quelle lädt: %s" % pfad)
		var treffer := nackt.search_all(quelle)
		assert_eq(
			treffer.size(),
			int(NACKTE_BUTTONS_ERLAUBT[pfad]),
			"%s: unerwartete nackte Button.new()" % pfad
		)
