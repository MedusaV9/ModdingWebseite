extends W1cTestCase
## W4/POLISH-4: HUD-Feinschliff — Level-Ring statt Text-Pill, Status-Sheet
## per Kapsel-Tap (inkl. Buff-Anzeige aus dem W3d-buffs-Slice), Badge-Pulse
## bei Stat < 25, Safe-Area-Insets (Notch-Simulation) und Coins-Zählen.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")


## GameState-Double für die Buff-Abfrage (Duck-Typing auf get_value).
class FakeGs:
	var buffs := {"aktiv": [{"id": "b1", "stat": "fun", "wert": 5.0, "until_ms": 10_000}]}

	func get_value(key: String, default_value: Variant = null) -> Variant:
		return buffs if key == "buffs" else default_value


func test_safe_insets_pure_notch_simulation() -> void:
	var ohne := HudLayoutLogic.safe_insets(Vector2(844, 390), Rect2(0, 0, 844, 390))
	for side in ["left", "top", "right", "bottom"]:
		check_approx(float(ohne[side]), 0.0, "ohne Notch: %s = 0" % side)
	# iPhone-Notch quer: Safe-Area beginnt bei x=59 und endet 59 vor rechts.
	var quer := HudLayoutLogic.safe_insets(Vector2(844, 390), Rect2(59, 0, 726, 369))
	check_approx(float(quer["left"]), 59.0, "Notch links")
	check_approx(float(quer["right"]), 59.0, "Notch rechts")
	check_approx(float(quer["bottom"]), 21.0, "Home-Indicator unten")
	# Hochkant: Notch oben.
	var hoch := HudLayoutLogic.safe_insets(Vector2(390, 844), Rect2(0, 59, 390, 751))
	check_approx(float(hoch["top"]), 59.0, "Notch oben")
	check_approx(float(hoch["bottom"]), 34.0, "Home-Indicator")
	# Degenerierte Eingaben → alles 0, nie Negativwerte.
	var kaputt := HudLayoutLogic.safe_insets(Vector2.ZERO, Rect2(59, 0, 726, 369))
	check_approx(float(kaputt["left"]), 0.0, "Null-Fenster → 0")
	var leer := HudLayoutLogic.safe_insets(Vector2(844, 390), Rect2())
	check_approx(float(leer["right"]), 0.0, "leere Safe-Area → 0")


func test_level_ring_statt_text_pill() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	await tree.process_frame
	var ring := hud.find_child("LevelRing", true, false)
	check(ring is HudProgressRing, "Level-Ring existiert im Level-Chip")
	hud.set_level(12, 0.5)
	check_approx((ring as HudProgressRing).ratio, 0.5, "XP-Ratio am Ring")
	var value := hud.find_child("LevelValue", true, false)
	check_eq((value as Label).text, "12", "Level-Zahl im Ring")
	hud.set_level(40, 9.9)
	check_approx((ring as HudProgressRing).ratio, 1.0, "Ratio wird geclampt")
	unmount(hud)


func test_badge_pulse_unter_25() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	await tree.process_frame
	hud.set_stats({"hunger": 80.0, "energie": 20.0, "hygiene": 50.0, "spass": 24.9})
	check(not hud.is_stat_alerting("hunger"), "Hunger 80 → kein Alarm")
	check(hud.is_stat_alerting("energie"), "Energie 20 → Kapsel pulsiert")
	check(hud.is_stat_alerting("spass"), "Spaß 24.9 → Kapsel pulsiert")
	hud.set_stats({"energie": 60.0})
	check(not hud.is_stat_alerting("energie"), "erholt → Puls stoppt")
	var chip := hud.find_child("StatChipEnergie", true, false) as Control
	check_eq(chip.modulate, Color.WHITE, "Chip-Tint zurückgesetzt")
	check_eq(chip.scale, Vector2.ONE, "Chip-Scale zurückgesetzt")
	unmount(hud)


func test_coins_zaehl_animation_endet_exakt() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	await tree.process_frame
	var label := hud.find_child("CoinValue", true, false) as Label
	check_eq(label.text, "0", "Start bei 0")
	hud.set_coins(300)
	check_eq(label.text, "0", "Zählt an, statt hart zu springen")
	var frames := 0
	while label.text != "300" and frames < 240:
		await tree.process_frame
		frames += 1
	check_eq(label.text, "300", "Zählanimation endet exakt beim Zielwert")
	check(frames > 0, "Es wurde wirklich animiert (mind. 1 Frame)")
	unmount(hud)


func test_status_sheet_inhalt_4_stats_mit_buff() -> void:
	var stats := {"hunger": 42.0, "energie": 90.0, "hygiene": 10.0, "spass": 55.0}
	var content := HudStatusSheet.build_content(stats, {"spass": 5.0})
	check_eq(content.get_child_count(), 4, "4 Stat-Zeilen")
	var hunger_row := content.get_node("RowHunger")
	check_approx((hunger_row.get_node("SheetBar") as ProgressBar).value, 42.0, "Balken-Wert")
	check_eq((hunger_row.get_node("Value") as Label).text, "42", "Zahlwert")
	check(hunger_row.get_node_or_null("BuffHunger") == null, "Hunger ohne Buff-Chip")
	var spass_row := content.get_node("RowSpass")
	check(spass_row.get_node_or_null("BuffSpass") != null, "Spaß-Buff-Chip da")
	var buff_label := spass_row.get_node("BuffSpass/BuffValue") as Label
	check(buff_label.text.contains("+5"), "Buff-Wert lesbar: %s" % buff_label.text)
	check(HudStatusSheet.title_text() != "", "Sheet-Titel vorhanden")
	content.free()


func test_status_sheet_buffs_aus_slice() -> void:
	check_eq(HudStatusSheet.stat_boni(null, 0), {}, "ohne GameState keine Boni")
	var gs := FakeGs.new()
	var boni := HudStatusSheet.stat_boni(gs, 5_000)
	check_approx(float(boni.get("spass", 0.0)), 5.0, "fun-Buff landet auf HUD-Id spass")
	check_eq(HudStatusSheet.stat_boni(gs, 20_000), {}, "abgelaufener Buff zählt nicht")


func test_kapsel_tap_oeffnet_sheet() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	await tree.process_frame
	hud.set_stats({"hunger": 61.0, "energie": 72.0, "hygiene": 83.0, "spass": 94.0})
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	hud._on_chip_input(tap)
	var sheet := hud.find_child("PanelSheet", true, false)
	check(sheet is PanelSheet, "Sheet hängt unterm HUD")
	check((sheet as PanelSheet).is_open(), "Sheet ist offen")
	var rows := hud.find_child("StatRows", true, false)
	check(rows != null and rows.get_child_count() == 4, "Sheet zeigt die 4 Stats")
	check_approx(
		(rows.get_node("RowHunger/SheetBar") as ProgressBar).value, 61.0, "Live-Wert im Sheet"
	)
	(sheet as PanelSheet).close()
	PanelStack.clear()
	unmount(hud)


func test_safe_area_override_verschiebt_raender() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	await tree.process_frame
	var canvas := Vector2(hud.get_viewport().get_visible_rect().size)
	hud.safe_area_override = Rect2(59.0, 0.0, canvas.x - 118.0, canvas.y - 21.0)
	hud.refresh_safe_area()
	var top_bar := hud.get_node("TopBar") as MarginContainer
	# FIX1: nur noch EDGE_PAD (8) Schattenluft statt 16 — Stats bündig am Rand.
	check_eq(top_bar.get_theme_constant("margin_left"), 67, "TopBar weicht der Notch aus (8+59)")
	check_eq(top_bar.get_theme_constant("margin_right"), 67, "TopBar rechts symmetrisch")
	check_approx(
		(hud.get_node("LeftColumn") as Control).offset_left, 67.0, "Cockpit-Stats rücken ein"
	)
	check_approx(
		(hud.get_node("PortraitDock") as Control).offset_bottom,
		-29.0,
		"Daumen-Dock überm Home-Indicator (-8-21)"
	)
	hud.safe_area_override = Rect2()
	hud.refresh_safe_area()
	check_eq(top_bar.get_theme_constant("margin_left"), 8, "ohne Notch wieder Standard (EDGE_PAD)")
	check_approx((hud.get_node("PortraitDock") as Control).offset_bottom, -8.0, "Dock-Standard")
	unmount(hud)
