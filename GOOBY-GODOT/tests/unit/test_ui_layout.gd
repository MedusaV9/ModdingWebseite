extends W1cTestCase
## Layout-Wahl (hoch/quer), Bogen-Geometrie, Toast-Queue (pure) und
## HUD-Szenen-Smoke mit Node-Pfad-Asserts für BEIDE Layouts.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")


func test_pick_layout_sechs_aufloesungen() -> void:
	var cases := [
		[Vector2(390, 844), HudLayoutLogic.Layout.PORTRAIT],  # iPhone 14 hoch
		[Vector2(844, 390), HudLayoutLogic.Layout.LANDSCAPE],  # iPhone 14 quer
		[Vector2(768, 1024), HudLayoutLogic.Layout.PORTRAIT],  # iPad hoch
		[Vector2(1024, 768), HudLayoutLogic.Layout.LANDSCAPE],  # iPad quer
		[Vector2(720, 1280), HudLayoutLogic.Layout.PORTRAIT],  # Basis hoch
		[Vector2(1280, 720), HudLayoutLogic.Layout.LANDSCAPE],  # Basis quer
	]
	for c in cases:
		check_eq(HudLayoutLogic.pick_layout(c[0]), c[1], "pick_layout(%s)" % c[0])


func test_arc_winkel_gleichmaessig_und_monoton() -> void:
	var angles := HudLayoutLogic.arc_angles_deg(6)
	check_eq(angles.size(), 6, "6 Bogen-Winkel")
	check_approx(angles[0], HudLayoutLogic.ARC_START_DEG, "Start-Winkel")
	check_approx(angles[5], HudLayoutLogic.ARC_END_DEG, "End-Winkel")
	for i in range(1, angles.size()):
		check(angles[i] < angles[i - 1], "Winkel fallen monoton (%d)" % i)
	var single := HudLayoutLogic.arc_angles_deg(1)
	check_eq(single.size(), 1, "1 Button → 1 Winkel")
	check_eq(HudLayoutLogic.arc_angles_deg(0).size(), 0, "0 Buttons → leer")


func test_arc_punkte_um_die_ecke() -> void:
	var corner := Vector2(240, 240)
	var left := HudLayoutLogic.arc_point(corner, 150.0, 180.0)
	check_approx(left.x, 90.0, "180° liegt links vom Eck (x)")
	check_approx(left.y, 240.0, "180° liegt links vom Eck (y)")
	var top := HudLayoutLogic.arc_point(corner, 150.0, 90.0)
	check_approx(top.x, 240.0, "90° liegt überm Eck (x)")
	check_approx(top.y, 90.0, "90° liegt überm Eck (y)")
	for deg in [176.0, 160.0, 120.0, 94.0]:
		var p := HudLayoutLogic.arc_point(corner, 150.0, deg)
		check_approx(p.distance_to(corner), 150.0, "Radius konstant bei %s°" % deg)


func test_toast_queue_niemals_stapeln() -> void:
	var q := ToastQueue.new()
	check(q.is_idle(), "Queue startet leer")
	check(q.push("A"), "A angenommen")
	check(q.push("B"), "B angenommen")
	check_eq(q.current(), "", "nichts sichtbar vor advance")
	check_eq(q.advance(), "A", "A wird sichtbar")
	check_eq(q.current(), "A", "current == A")
	check(not q.push("A"), "identischer sichtbarer Toast wird verschluckt")
	check(q.push("C"), "C angenommen")
	check(not q.push("C"), "identischer Queue-Nachbar wird verschluckt")
	check_eq(q.advance(), "B", "B folgt auf A")
	check_eq(q.advance(), "C", "C folgt auf B")
	check_eq(q.advance(), "", "Queue leer → leerer String")
	for i in ToastQueue.MAX_PENDING:
		check(q.push("T%d" % i), "Cap-Füllung %d" % i)
	check(not q.push("Zuviel"), "Queue-Cap verwirft Überlauf")


func test_hud_layouts_reparenten_buttons() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	await tree.process_frame
	hud.apply_layout(HudLayoutLogic.Layout.PORTRAIT)
	for btn_name in ["BtnIgohbie", "BtnBau", "BtnReise", "BtnArcade", "BtnAlbum", "BtnProfil"]:
		check(
			hud.get_node_or_null("PortraitArc/" + btn_name) != null,
			"Hochkant: %s im Daumen-Bogen" % btn_name
		)
	check(hud.get_node("PortraitArc").visible, "Hochkant: Bogen sichtbar")
	check(not hud.get_node("LandscapeColumn").visible, "Hochkant: Spalte versteckt")
	check(
		hud.get_node_or_null("TopBar/TopBarBox/StatusRow/CoinChip") != null,
		"Hochkant: Coin-Chip in der Status-Zeile"
	)
	hud.apply_layout(HudLayoutLogic.Layout.LANDSCAPE)
	for btn_name in ["BtnBau", "BtnReise", "BtnArcade", "BtnAlbum", "BtnProfil", "BtnIgohbie"]:
		check(
			hud.get_node_or_null("LandscapeColumn/" + btn_name) != null,
			"Quer: %s in der Cockpit-Spalte" % btn_name
		)
	check(not hud.get_node("PortraitArc").visible, "Quer: Bogen versteckt")
	check(
		hud.get_node_or_null("LeftColumn/StatChipHunger") != null,
		"Quer: Hunger-Chip in der linken Spalte"
	)
	check(
		hud.get_node_or_null("LeftColumn/CoinChip") != null, "Quer: Coin-Chip in der linken Spalte"
	)
	hud.apply_layout(HudLayoutLogic.Layout.PORTRAIT)
	check(
		hud.get_node_or_null("TopBar/TopBarBox/StatusRow/StatChipHunger") != null,
		"Zurück zu Hochkant: Chips wieder oben"
	)
	unmount(hud)


func test_hud_setter_und_signale() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	await tree.process_frame
	hud.apply_layout(HudLayoutLogic.Layout.PORTRAIT)
	hud.set_stats({"hunger": 42.0, "energie": 13.0, "hygiene": 77.0, "spass": 5.0})
	var bar := hud.find_child("StatChipHunger", true, false).find_child("Bar", true, false)
	check_approx((bar as ProgressBar).value, 42.0, "Hunger-Bar übernimmt Wert")
	hud.set_coins(427)
	hud.set_level(12)
	var actions: Array[StringName] = []
	hud.action_pressed.connect(func(a: StringName) -> void: actions.append(a))
	(hud.get_node("PortraitArc/BtnReise") as Button).pressed.emit()
	check_eq(actions, [&"reise"] as Array[StringName], "Reise-Button feuert action_pressed")
	var eye_states: Array = []
	hud.eye_toggled.connect(func(on: bool) -> void: eye_states.append(on))
	var eye := hud.get_node("EyeButton") as Button
	eye.button_pressed = true
	check_eq(eye_states, [true], "Auge an → Signal true")
	hud._on_eye_timeout()
	check_eq(eye_states, [true, false], "Auto-Aus nach Timeout → Signal false")
	check(not eye.button_pressed, "Auge nach Timeout wieder aus")
	unmount(hud)
