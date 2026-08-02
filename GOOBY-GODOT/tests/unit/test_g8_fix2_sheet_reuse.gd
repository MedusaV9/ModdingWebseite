extends TestCase
## G8/FIX-2 — Wachen für zwei Playtest-Befunde der Welle H:
## (1) B2 KRITISCH „Tagesquests-Blatt beim ZWEITEN Öffnen leer":
##     PanelSheet.add_content darf WIEDERVERWENDETE (vom Aufrufer gecachte)
##     Inhalte nicht zerstören — vorher hängte die Ersetz-Schleife auch den
##     identischen Knoten ab, queue_free-te ihn und hängte den todgeweihten
##     Knoten wieder ein (Inhalt starb im Folgeframe). Getestet über die
##     ECHTEN Nodes: PanelSheet-Szene direkt UND der komplette
##     DailyQuestService-Weg (open → close → open).
## (2) B6/B9 „Was nun?"-Karte hängt über Telefon-Sheet und Bau-UI:
##     die Karte hängt jetzt an DERSELBEN P50-Weiche wie das HUD
##     (HudSichtbarkeit) und weicht zusätzlich dem IGohbie-Vollbild-Overlay
##     (PhoneShell-Gruppe) — geprüft mit echtem HUD, echtem BuildMode-Signal
##     und echter PhoneShell.

const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const SaveSchema := preload("res://scripts/state/save_schema.gd")


## GameState-Double (Muster test_g7_sheets): dotted get/set + update().
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

	func _init() -> void:
		s = SaveSchema.default_state(1700000000000)

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


## Reduced Motion global setzen; gibt den vorherigen Zustand zurück
## (Muster test_g7_hud_dynamik — deterministische Open/Close-Zustände).
func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func _sheet_body(sheet: PanelSheet) -> Node:
	return sheet.find_child("SheetBody", true, false)


# ── (1) add_content-Wiederverwendung ─────────────────────────────────────────


func test_add_content_ueberlebt_wiederverwendeten_inhalt() -> void:
	PanelStack.clear()
	var rm_vorher := _set_reduced_motion(true)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(sheet)
	sheet.set_title("B2-Probe")
	# Gecachter Inhalt wie im quest_service: EIN Panel für alle Öffnungen.
	var inhalt := VBoxContainer.new()
	var zeile := Label.new()
	zeile.text = "Tagesquest-Zeile"
	inhalt.add_child(zeile)
	# Zwei komplette open→close-Runden mit DEMSELBEN Inhalt — der Alt-Bug
	# schlug in Runde 2 zu (Inhalt starb im Folgeframe).
	for runde in 2:
		sheet.add_content(inhalt)
		sheet.open()
		await wait_frames(3)
		assert_true(
			is_instance_valid(inhalt) and not inhalt.is_queued_for_deletion(),
			"Runde %d: wiederverwendeter Inhalt lebt" % (runde + 1)
		)
		assert_eq(
			inhalt.get_parent(),
			_sheet_body(sheet),
			"Runde %d: Inhalt hängt im SheetBody" % (runde + 1)
		)
		assert_true(inhalt.is_visible_in_tree(), "Runde %d: Inhalt ist sichtbar" % (runde + 1))
		sheet.close()
		await wait_frames(3)
	assert_eq(_sheet_body(sheet).get_child_count(), 1, "Body enthält den Inhalt genau einmal")
	host.queue_free()
	await wait_frames(2)
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)


func test_add_content_ersetzt_fremden_inhalt_weiterhin() -> void:
	PanelStack.clear()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(sheet)
	var alt := Label.new()
	alt.text = "alter Inhalt"
	sheet.add_content(alt)
	await wait_frames(1)
	# Ersetzen mit NEUEM Knoten: der alte wird weiterhin abgehängt und
	# freigegeben (P17/P21-Verhalten bleibt — keine Min-Size-Blähung).
	var neu := Label.new()
	neu.text = "neuer Inhalt"
	sheet.add_content(neu)
	assert_true(alt.get_parent() == null, "Alt-Inhalt ist sofort abgehängt")
	await wait_frames(3)
	assert_false(is_instance_valid(alt), "Alt-Inhalt ist freigegeben")
	assert_eq(neu.get_parent(), _sheet_body(sheet), "Neu-Inhalt hängt im SheetBody")
	assert_eq(_sheet_body(sheet).get_child_count(), 1, "genau ein Body-Kind")
	host.queue_free()
	await wait_frames(2)
	PanelStack.clear()


func test_add_content_haengt_anderswo_geparkten_inhalt_um() -> void:
	PanelStack.clear()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(sheet)
	# Aufrufer parken gecachte Panels gern woanders (z. B. am Service) —
	# add_content muss sauber umhängen statt mit add_child zu kollidieren.
	var parkplatz := Control.new()
	host.add_child(parkplatz)
	var inhalt := Label.new()
	inhalt.text = "geparkter Inhalt"
	parkplatz.add_child(inhalt)
	sheet.add_content(inhalt)
	assert_eq(inhalt.get_parent(), _sheet_body(sheet), "Inhalt wurde in den Body umgehängt")
	assert_true(is_instance_valid(inhalt), "umgehängter Inhalt lebt")
	host.queue_free()
	await wait_frames(2)
	PanelStack.clear()


func test_quest_service_blatt_zweimal_oeffnen_hat_inhalt() -> void:
	PanelStack.clear()
	var rm_vorher := _set_reduced_motion(true)
	var host := Node.new()
	tree.root.add_child(host)
	var service := DailyQuestService.attach_to(host, FakeGameState.new())
	await wait_frames(2)
	# Runde 1: Öffnen füllt das Blatt (Brett wird für heute gerollt).
	service.open_panel()
	await wait_frames(3)
	var panel_erste: DailyQuestPanel = service._panel
	assert_true(is_instance_valid(panel_erste), "Runde 1: Panel existiert")
	assert_true(service._sheet.is_open(), "Runde 1: Blatt ist offen")
	assert_true(panel_erste.get_child_count() > 0, "Runde 1: Panel hat Inhalt")
	assert_true(panel_erste.is_visible_in_tree(), "Runde 1: Panel sichtbar")
	# Schließen (Dim-Tap/Wisch-Äquivalent) — der Service cached Sheet+Panel.
	service._sheet.close()
	await wait_frames(3)
	assert_true(
		is_instance_valid(service._panel),
		"Nach dem Schließen lebt der gecachte Panel weiter (B2-Kern)"
	)
	# Runde 2: DER Befund — zweites Öffnen muss wieder Inhalt zeigen.
	service.open_panel()
	await wait_frames(3)
	var panel_zweite: DailyQuestPanel = service._panel
	assert_true(
		is_instance_valid(panel_zweite) and not panel_zweite.is_queued_for_deletion(),
		"Runde 2: Panel lebt (kein queue_free-Zombie)"
	)
	assert_eq(panel_zweite, panel_erste, "Runde 2: gecachter Panel wird wiederverwendet")
	assert_true(service._sheet.is_open(), "Runde 2: Blatt ist offen")
	assert_true(panel_zweite.get_child_count() > 0, "Runde 2: Panel hat Inhalt")
	assert_true(panel_zweite.is_visible_in_tree(), "Runde 2: Panel sichtbar")
	assert_eq(
		panel_zweite.get_parent(), _sheet_body(service._sheet), "Runde 2: Panel hängt im SheetBody"
	)
	service._sheet.close()
	await wait_frames(2)
	host.queue_free()
	await wait_frames(2)
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)


# ── (2) „Was nun?"-Karte weicht Baumodus + Telefon ───────────────────────────


func _hint_suggestion() -> Dictionary:
	return {"id": "arcade", "text_key": "quests.wasnun.arcade", "aktion": "", "args": {}}


func _karte_von(hint: WhatsNextHint) -> Control:
	return hint.find_child("WasNunKarte", true, false) as Control


func test_wasnun_karte_weicht_dem_baumodus() -> void:
	PanelStack.clear()
	var rm_vorher := _set_reduced_motion(true)
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	var hint := WhatsNextHint.new()
	tree.root.add_child(hint)
	hint.show_suggestion(_hint_suggestion())
	await wait_frames(3)
	var karte := _karte_von(hint)
	assert_true(karte != null and karte.visible, "Karte anfangs sichtbar")
	# Baumodus an (P50-Weiche): die Karte weicht mit dem HUD.
	var bau := BuildMode.new()
	tree.root.add_child(bau)
	await wait_frames(1)
	bau.opened.emit()
	await wait_frames(2)
	assert_true(hud.sichtbarkeit().verdeckt(), "P50-Weiche greift im Baumodus")
	assert_false(karte.visible, "Karte duckt sich im Baumodus (B6)")
	bau.closed.emit()
	await wait_frames(2)
	assert_true(karte.visible, "Karte kommt nach dem Baumodus zurück")
	bau.free()
	hint.free()
	hud.free()
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)


func test_wasnun_karte_weicht_dem_telefon() -> void:
	PanelStack.clear()
	var rm_vorher := _set_reduced_motion(true)
	var hint := WhatsNextHint.new()
	tree.root.add_child(hint)
	hint.show_suggestion(_hint_suggestion())
	await wait_frames(3)
	var karte := _karte_von(hint)
	assert_true(karte != null and karte.visible, "Karte anfangs sichtbar")
	# IGohbie-Telefon öffnen (Vollbild-Overlay, KEIN PanelSheet/PanelStack).
	var shell := PhoneShell.oeffne(tree.root, FakeGameState.new())
	await wait_frames(3)
	assert_true(
		tree.get_first_node_in_group(PhoneShell.GRUPPE) != null,
		"offene PhoneShell steht in der Gruppe"
	)
	assert_false(karte.visible, "Karte duckt sich unterm Telefon (B9)")
	shell.schliesse()
	await wait_frames(4)
	assert_true(karte.visible, "Karte kommt nach dem Telefon zurück")
	hint.free()
	PanelStack.clear()
	_set_reduced_motion(rm_vorher)
