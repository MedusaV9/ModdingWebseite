extends TestCase
## W18/F1 — Wächter für zwei Playtest-Befunde (report_home B1 + E1):
## - B1 BLOCKER: PanelSheet.add_content zerstörte den WIEDERVERWENDETEN
##   Inhalts-Node (queue_free → wieder einhängen → am Frame-Ende gelöscht):
##   das Tagesquests-Blatt war nach einmal Öffnen+Schließen dauerhaft leer.
##   Wächter: (a) add_content ist idempotent für denselben Node, (b) das
##   echte Tagesquests-Blatt hat auch beim ZWEITEN Öffnen Quest-Zeilen.
## - E1 ERNST: die „Was nun?“-Karte stahl Taps auf 3D-Objekte (Küchentür),
##   weil ihre STOP-Fläche mit stalen Autowrap-Minima kilometerhoch einfror.
##   Wächter: (a) direkt nach show_suggestion ist die Karte ENTSCHÄRFT
##   (IGNORE + unsichtbar), (b) nach dem Settle liegt JEDES sichtbare
##   STOP-Control innerhalb der Kartenfläche, (c) ein Klick unterhalb der
##   Karte erreicht den Hintergrund, ein Klick auf die Karte trifft sie.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")

var _seq := 0


func _frisches_gs() -> Node:
	_seq += 1
	var dir := "user://w18_f1_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


## B1a: DERSELBE Node überlebt add_content nach Öffnen+Schließen (das
## Wiederverwendungs-Muster des DailyQuestService). Vor dem Fix war er nach
## dem 2. add_content queue_free-markiert und am Frame-Ende tot.
func test_panel_sheet_wiederverwendeter_inhalt_ueberlebt() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(sheet)
	var inhalt := Label.new()
	inhalt.text = "Wiederverwendungs-Probe"
	sheet.add_content(inhalt)
	sheet.open()
	await wait_frames(4)
	sheet.close()
	# Genug Frames, damit ein fälschliches queue_free WIRKEN würde.
	await wait_frames(8)
	assert_true(is_instance_valid(inhalt), "Inhalt überlebt Öffnen+Schließen")
	sheet.add_content(inhalt)
	sheet.open()
	await wait_frames(4)
	assert_true(is_instance_valid(inhalt), "Inhalt überlebt das 2. add_content")
	if is_instance_valid(inhalt):
		assert_false(inhalt.is_queued_for_deletion(), "Inhalt ist nicht löschmarkiert")
	var body := sheet.get_node("%SheetBody") as Control
	assert_eq(body.get_child_count(), 1, "Body trägt genau den einen Inhalt")
	# Fremd-Inhalt räumt weiterhin auf (das Aufräum-Verhalten bleibt).
	var neu := Label.new()
	neu.text = "Neuer Inhalt"
	sheet.add_content(neu)
	await wait_frames(2)
	assert_false(is_instance_valid(inhalt), "ANDERER Inhalt räumt den alten weg")
	assert_eq(body.get_child_count(), 1, "Body trägt nur den neuen Inhalt")
	sheet.close()
	await wait_frames(2)
	PanelStack.clear()
	host.queue_free()
	await wait_frames(1)


## B1b: das ECHTE Tagesquests-Blatt (DailyQuestService) hat auch beim
## zweiten Öffnen Quest-Zeilen — der Playtest-Blocker war „dauerhaft leer“.
func test_tagesquests_blatt_zweimal_oeffnen_hat_zeilen() -> void:
	var host := Node.new()
	tree.root.add_child(host)
	var gs := _frisches_gs()
	tree.root.add_child(gs)
	var service := DailyQuestService.attach_to(host, gs)
	await wait_frames(2)
	service.open_panel()
	await wait_frames(4)
	assert_true(is_instance_valid(service._panel), "1. Öffnen: Panel lebt")
	var zeilen_1 := (service._panel._rows as Dictionary).size()
	assert_true(zeilen_1 > 0, "1. Öffnen: Quest-Zeilen vorhanden (%d)" % zeilen_1)
	service._sheet.close()
	# Über das Frame-Ende hinaus warten — hier starb das Panel vor dem Fix.
	await wait_frames(8)
	service.open_panel()
	await wait_frames(4)
	assert_true(is_instance_valid(service._panel), "2. Öffnen: Panel lebt noch")
	if is_instance_valid(service._panel):
		var zeilen_2 := (service._panel._rows as Dictionary).size()
		assert_eq(zeilen_2, zeilen_1, "2. Öffnen: gleiche Quest-Zeilen wie beim 1.")
		assert_true(service._panel.get_child_count() > 0, "2. Öffnen: Blatt ist nicht leer")
		assert_false(service._panel.is_queued_for_deletion(), "Panel nicht löschmarkiert")
	service._sheet.close()
	await wait_frames(2)
	PanelStack.clear()
	host.queue_free()
	gs.queue_free()
	await wait_frames(1)


## E1a: Eingabe-Geometrie — solange die Autowrap-Minima stale sind, ist die
## Karte entschärft; nach dem Settle liegt jedes sichtbare STOP-Control
## INNERHALB der Kartenfläche (kein full-rect STOP außerhalb der Karte).
func test_wasnun_karte_stop_nur_auf_kartenflaeche() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	tree.root.add_child(layer)
	var hint := WhatsNextHint.new()
	layer.add_child(hint)
	await wait_frames(1)
	hint.show_suggestion({"id": "w18e1", "text_key": "quests.wasnun.quest", "args": {}})
	var karte := hint.get_node("WasNunKarte") as Control
	# Im Aufruf-Frame (stale Geometrie): entschärft — IGNORE + durchsichtig.
	assert_eq(int(karte.mouse_filter), int(Control.MOUSE_FILTER_IGNORE), "stale: Karte IGNORE")
	assert_almost(karte.modulate.a, 0.0, 1e-4, "stale: Karte unsichtbar")
	await wait_frames(6)
	# Gesettelt: scharf — und die STOP-Fläche ist exakt die Kartenfläche.
	assert_eq(int(karte.mouse_filter), int(Control.MOUSE_FILTER_STOP), "gesettelt: Karte STOP")
	# Pop-in blendet zeitbasiert ein — begrenzt warten, bis er durch ist.
	var deadline := Time.get_ticks_msec() + 2000
	while karte.modulate.a < 0.99 and Time.get_ticks_msec() < deadline:
		await wait_frames(1)
	assert_true(karte.modulate.a > 0.99, "gesettelt: Karte sichtbar (%f)" % karte.modulate.a)
	assert_eq(int(hint.mouse_filter), int(Control.MOUSE_FILTER_IGNORE), "Wurzel bleibt IGNORE")
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var kr := karte.get_global_rect()
	assert_true(kr.size.y < canvas.y * 0.5, "Karte ist nicht kilometerhoch (%s)" % kr)
	var karten_rect := kr.grow(1.0)
	for ctl: Control in _stop_controls(hint):
		assert_true(
			karten_rect.encloses(ctl.get_global_rect()),
			"STOP-Control %s (%s) ragt aus der Karte %s" % [ctl.name, ctl.get_global_rect(), kr]
		)
	hint.queue_free()
	layer.queue_free()
	await wait_frames(1)


## E1b: Ende-zu-Ende — ein Klick UNTERHALB der Karte (Tür-Projektion)
## erreicht den Hintergrund, nur der Klick AUF die Karte trifft die Karte.
func test_wasnun_karte_klick_hinter_karte_kommt_durch() -> void:
	var zaehler := {"hinter": 0, "karte": 0}
	var hinter := Button.new()
	hinter.name = "W18HinterKnopf"
	hinter.set_anchors_preset(Control.PRESET_FULL_RECT)
	hinter.pressed.connect(func() -> void: zaehler["hinter"] += 1)
	tree.root.add_child(hinter)
	var layer := CanvasLayer.new()
	layer.layer = 60
	tree.root.add_child(layer)
	var hint := WhatsNextHint.new()
	layer.add_child(hint)
	hint.tapped.connect(func(_s: Dictionary) -> void: zaehler["karte"] += 1)
	await wait_frames(1)
	hint.show_suggestion({"id": "w18e1b", "text_key": "quests.wasnun.quest", "args": {}})
	await wait_frames(8)
	var karte := hint.get_node("WasNunKarte") as Control
	var kr := karte.get_global_rect()
	var canvas := Vector2(tree.root.get_visible_rect().size)
	# Klar unter der Karte (mit Reserve für den Pop-in-Überschwinger).
	var unter := Vector2(kr.get_center().x, minf(kr.end.y + 120.0, canvas.y - 4.0))
	await _klick(unter)
	assert_eq(int(zaehler["hinter"]), 1, "Klick unter der Karte erreicht den Hintergrund")
	assert_eq(int(zaehler["karte"]), 0, "Klick unter der Karte trifft NICHT die Karte")
	await _klick(kr.get_center())
	assert_eq(int(zaehler["karte"]), 1, "Klick auf die Karte trifft die Karte")
	assert_eq(int(zaehler["hinter"]), 1, "Klick auf die Karte bleibt an der Karte hängen")
	hint.queue_free()
	layer.queue_free()
	hinter.queue_free()
	await wait_frames(1)


## E1c: geduckt eingeblendet (fremdes Sheet offen) settelt der Container
## nicht — beim Ent-Ducken muss die Karte FRISCH gesettelt zurückkommen,
## nicht mit der stale (kilometerhohen) STOP-Fläche von vorher.
func test_wasnun_karte_nach_entducken_frisch_gesettelt() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(sheet)
	sheet.open()
	await wait_frames(2)
	assert_true(PanelStack.count() > 0, "Vorbedingung: fremdes Sheet duckt die Karte")
	var layer := CanvasLayer.new()
	layer.layer = 60
	tree.root.add_child(layer)
	var hint := WhatsNextHint.new()
	layer.add_child(hint)
	await wait_frames(1)
	hint.show_suggestion({"id": "w18e1c", "text_key": "quests.wasnun.quest", "args": {}})
	await wait_frames(6)
	var karte := hint.get_node("WasNunKarte") as Control
	assert_false(karte.visible, "geduckt: Karte unsichtbar")
	sheet.close()
	await wait_frames(10)
	PanelStack.clear()
	await wait_frames(8)
	assert_true(karte.is_visible_in_tree(), "entduckt: Karte wieder sichtbar")
	assert_eq(int(karte.mouse_filter), int(Control.MOUSE_FILTER_STOP), "entduckt: Karte STOP")
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var kr := karte.get_global_rect()
	assert_true(kr.size.y < canvas.y * 0.5, "entduckt: Karte frisch gesettelt (%s)" % kr)
	hint.queue_free()
	layer.queue_free()
	host.queue_free()
	await wait_frames(1)


## Alle sichtbaren STOP-Controls im Teilbaum einsammeln.
func _stop_controls(wurzel: Node) -> Array[Control]:
	var out: Array[Control] = []
	if wurzel is Control:
		var ctl := wurzel as Control
		if ctl.is_visible_in_tree() and ctl.mouse_filter == Control.MOUSE_FILTER_STOP:
			out.append(ctl)
	for kind in wurzel.get_children():
		out.append_array(_stop_controls(kind))
	return out


## Headless-Klick: push_input mit LOKALEN Koordinaten (das Fenster meldet
## im Headless-Lauf 0×0 — globale Koordinaten verpuffen dann).
func _klick(pos: Vector2) -> void:
	var runter := InputEventMouseButton.new()
	runter.button_index = MOUSE_BUTTON_LEFT
	runter.pressed = true
	runter.position = pos
	runter.global_position = pos
	runter.button_mask = MOUSE_BUTTON_MASK_LEFT
	tree.root.push_input(runter, true)
	await wait_frames(1)
	var hoch := InputEventMouseButton.new()
	hoch.button_index = MOUSE_BUTTON_LEFT
	hoch.pressed = false
	hoch.position = pos
	hoch.global_position = pos
	tree.root.push_input(hoch, true)
	await wait_frames(1)
