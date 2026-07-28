extends TestCase
## UIFINAL — Vertrags-Tests für die Schön-Runde:
## 1. „Was nun?“-Hinweis: Schließen-Knopf hat eine echte Tippfläche, das
##    Schließen-Icon ist gedeckelt, die Karte hält den Breiten-Deckel ein
##    und DUCKT sich, solange ein Panel/Sheet offen ist (PanelStack) —
##    die FB3-Regression (17 Audit-Befunde) darf nie zurückkommen.
## 2. GhostButton-Guardrail: `icon_max_width` im Theme (96-px-SVGs sprengen
##    sonst jeden Ghost-Knopf).
## 3. DialogBubble: OHNE Home-HUD bleibt die Szenen-Geometrie unangetastet
##    (Stadt-Dialoge rechnen mit ihr); die Schriften bleiben Theme-Sache.
## 4. Leerzustand (Freunde/Besuche): illustriert (Hase im Well) statt ASCII.
## 5. Toast weicht der „Was nun?“-Karte aus (beide wohnen in der Kopf-Zone —
##    bei Quest-Erfolg lag die Bubble sonst mitten AUF der Karte).


func _hint_suggestion() -> Dictionary:
	return {"id": "arcade", "text_key": "quests.wasnun.arcade", "aktion": "", "args": {}}


func test_hint_schliessen_hat_tippflaeche_und_icon_deckel() -> void:
	var hint := WhatsNextHint.new()
	tree.root.add_child(hint)
	hint.show_suggestion(_hint_suggestion())
	await wait_frames(3)
	var close := hint.find_child("WasNunSchliessen", true, false) as Button
	assert_true(close != null, "Schließen-Knopf existiert.")
	if close != null:
		var floor_px := UiScale.touch_px_per_pt(hint.get_viewport()) * WhatsNextHint.TOUCH_MIN_PT
		assert_true(
			close.custom_minimum_size.x >= floor_px - 0.5,
			"Tippfläche >= physischer Touch-Floor (%.1f px)." % floor_px
		)
		assert_true(
			close.get_theme_constant("icon_max_width") <= 40,
			"Schließen-Icon ist gedeckelt (96-px-SVG-Regression)."
		)
	hint.queue_free()
	await wait_frames(1)


func test_hint_karte_haelt_breiten_deckel() -> void:
	var hint := WhatsNextHint.new()
	tree.root.add_child(hint)
	hint.show_suggestion(_hint_suggestion())
	await wait_frames(4)
	var card := hint.find_child("WasNunKarte", true, false) as Control
	assert_true(card != null, "Karte existiert.")
	if card != null:
		var f := UiScale.for_viewport(hint.get_viewport())
		var canvas := Vector2(hint.get_viewport().get_visible_rect().size)
		var cap := minf(WhatsNextHint.MAX_WIDTH_PX * f, canvas.x - 24.0)
		assert_true(
			card.size.x <= cap + 1.0, "Karte %.0f px <= Deckel %.0f px." % [card.size.x, cap]
		)
	hint.queue_free()
	await wait_frames(1)


func test_hint_duckt_sich_unter_offenen_panels() -> void:
	var hint := WhatsNextHint.new()
	tree.root.add_child(hint)
	hint.show_suggestion(_hint_suggestion())
	await wait_frames(3)
	var card := hint.find_child("WasNunKarte", true, false) as Control
	assert_true(card != null and card.visible, "Karte anfangs sichtbar.")
	var panel := Control.new()
	tree.root.add_child(panel)
	PanelStack.push(panel)
	await wait_frames(2)
	assert_true(card != null and not card.visible, "Karte duckt sich unterm Panel.")
	PanelStack.remove(panel)
	await wait_frames(2)
	assert_true(card != null and card.visible, "Karte kommt nach dem Schließen wieder.")
	panel.queue_free()
	hint.queue_free()
	await wait_frames(1)


func test_ghost_button_icon_ist_gedeckelt() -> void:
	var theme: Theme = (load("res://themes/build_theme.gd") as GDScript).build()
	assert_eq(
		theme.get_constant("icon_max_width", "GhostButton"),
		22,
		"GhostButton-Guardrail gegen ungedeckelte 96-px-SVGs."
	)


func test_dialog_bubble_ohne_hud_behaelt_szenen_geometrie() -> void:
	var bubble := (load("res://scripts/ui/dialog_bubble.tscn") as PackedScene).instantiate()
	tree.root.add_child(bubble)
	await wait_frames(1)
	bubble.show_lines(["Hallo!"] as Array[String])
	await wait_frames(2)
	var panel := bubble.get_node("%Bubble") as Control
	assert_almost(
		panel.offset_bottom, -18.0, 0.01, "Ohne HUD bleibt die Stadt-Dialog-Geometrie stehen."
	)
	bubble.queue_free()
	await wait_frames(1)


func test_toast_weicht_wasnun_karte_aus() -> void:
	var toasts := ToastLayer.new()
	tree.root.add_child(toasts)
	await wait_frames(1)
	# Stellvertreter-Karte in der Gruppe der echten „Was nun?“-Karte — deckt
	# die komplette Kopf-Zone ab, in der der Toast normalerweise landet.
	var card := ColorRect.new()
	card.add_to_group(&"wasnun_karte")
	card.position = Vector2.ZERO
	card.size = Vector2(4000.0, 200.0)
	tree.root.add_child(card)
	toasts.show_toast("Erfolg: Test!")
	await wait_frames(3)
	var panel := toasts.find_child("ToastPanel", true, false) as Control
	assert_true(panel != null and panel.visible, "Toast sichtbar.")
	if panel != null:
		assert_true(
			panel.position.y >= card.get_global_rect().end.y - 0.5,
			"Toast rutscht unter die Karten-Unterkante (%.0f px)." % card.get_global_rect().end.y
		)
	card.queue_free()
	toasts.queue_free()
	await wait_frames(1)


func test_leerzustand_ist_illustriert() -> void:
	var empty := FriendListUi.build_empty_state("net.friends.empty_art", "net.friends.empty")
	tree.root.add_child(empty)
	await wait_frames(1)
	var art := _find_texture_rect(empty)
	assert_true(art != null, "Leerzustand trägt eine Illustration (kein ASCII).")
	if art != null:
		assert_true(art.texture != null, "Illustration hat eine Textur (rabbit.svg).")
	empty.queue_free()
	await wait_frames(1)


func _find_texture_rect(root: Node) -> TextureRect:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is TextureRect:
			return node
		stack.append_array(node.get_children())
	return null
