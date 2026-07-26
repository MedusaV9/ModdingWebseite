extends TestCase
## FIX1 P0 „Zurück-Button funktioniert meist nicht“: DER gemeinsame
## Zurück-Pfad — SceneRouter-History + &"home"-Alias + PanelStack.
## Inklusive des geforderten 5-fach-verschachtelten Panel-Stack-Tests.

const ROUTER_SCRIPT := preload("res://scripts/core/scene_router.gd")
const FAKE_VEIL_SCRIPT := preload("res://tests/fixtures/fake_veil.gd")
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")

const ROOM_A := "res://tests/fixtures/room_a.tscn"
const ROOM_B := "res://tests/fixtures/room_b.tscn"


func test_home_alias_wird_automatisch_registriert() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	# Vorher: goto(&"home") schlug still fehl, weil Räume `home/<raum>`
	# heißen und &"home" NIE registriert war — der Kern des Zurück-Bugs.
	router.register_route(&"home/wohnzimmer", ROOM_A)
	var routes: Dictionary = router.get("_routes")
	assert_true(routes.has(&"home"), "erste home/-Route registriert den Alias mit")
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	router.goto(&"home")
	var done := await wait_until(func() -> bool: return finished.size() == 1)
	assert_true(done, 'goto(&"home") muss jetzt reisen')
	assert_eq(router.get_current_target(), &"home/wohnzimmer", "Alias löst auf den Raum auf")
	await _cleanup(ctx)


func test_back_reist_zum_vorherigen_ziel() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	assert_false(router.can_go_back(), "ohne History kein Zurück")
	router.goto(&"room_a")
	await wait_until(func() -> bool: return finished.size() == 1)
	assert_false(router.can_go_back(), "1 Eintrag reicht nicht für Zurück")
	router.goto(&"room_b")
	await wait_until(func() -> bool: return finished.size() == 2)
	assert_true(router.can_go_back(), "2 Einträge → Zurück möglich")
	assert_true(router.back(), "back() startet die Rückreise")
	await wait_until(func() -> bool: return finished.size() == 3)
	assert_eq(router.get_current_target(), &"room_a", "zurück beim vorherigen Ziel")
	assert_eq(router.get_history(), [&"room_a"] as Array[StringName], "History abgebaut")
	assert_false(router.back(), "unterste Ebene: kein weiteres Zurück")
	await _cleanup(ctx)


func test_home_alias_merkt_sich_letzten_raum() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	router.register_route(&"home/wohnzimmer", ROOM_A)
	router.register_route(&"home/kueche", ROOM_B)
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	router.goto(&"home/kueche")
	await wait_until(func() -> bool: return finished.size() == 1)
	router.goto(&"room_a")
	await wait_until(func() -> bool: return finished.size() == 2)
	router.goto(&"home")
	await wait_until(func() -> bool: return finished.size() == 3)
	assert_eq(
		router.get_current_target(), &"home/kueche", "Alias reist in den ZULETZT besuchten Raum"
	)
	await _cleanup(ctx)


func test_zurueck_schliesst_5_verschachtelte_panels_lifo() -> void:
	PanelStack.clear()
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var closed_order: Array = []
	var sheets: Array = []
	for i in 5:
		var sheet: PanelSheet = SHEET_SCENE.instantiate()
		sheet.name = "Sheet%d" % i
		host.add_child(sheet)
		sheet.set_title("Ebene %d" % i)
		var idx := i
		sheet.closed.connect(func() -> void: closed_order.append(idx))
		sheet.open()
		sheets.append(sheet)
	await wait_frames(1)
	assert_eq(PanelStack.count(), 5, "5 verschachtelte Panels auf dem Stack")
	# Escape/Back-Geste: handle_back_request schließt IMMER nur das oberste.
	for i in 5:
		assert_true(router.handle_back_request(), "Back-Anfrage %d konsumiert" % i)
	assert_eq(closed_order, [4, 3, 2, 1, 0] as Array, "LIFO: oberstes Panel zuerst")
	assert_eq(PanelStack.count(), 0, "Stack ist leer")
	assert_false(router.handle_back_request(), "ohne Panels + ohne History: nichts zu tun")
	host.queue_free()
	await _cleanup(ctx)


func test_back_request_bevorzugt_panels_vor_history() -> void:
	PanelStack.clear()
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	router.goto(&"room_a")
	await wait_until(func() -> bool: return finished.size() == 1)
	router.goto(&"room_b")
	await wait_until(func() -> bool: return finished.size() == 2)
	var host := Control.new()
	tree.root.add_child(host)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	host.add_child(sheet)
	sheet.open()
	await wait_frames(1)
	assert_true(router.handle_back_request(), "erste Anfrage konsumiert")
	assert_false(sheet.is_open(), "…und schließt das Panel, NICHT die Szene")
	assert_eq(router.get_current_target(), &"room_b", "Szene blieb stehen")
	assert_true(router.handle_back_request(), "zweite Anfrage konsumiert")
	await wait_until(func() -> bool: return finished.size() == 3)
	assert_eq(router.get_current_target(), &"room_a", "…und reist jetzt zurück")
	host.queue_free()
	await _cleanup(ctx)


func _make_router() -> Dictionary:
	var router: Node = ROUTER_SCRIPT.new()
	var veil: Node = FAKE_VEIL_SCRIPT.new()
	router.install_veil(veil)
	router.min_shown_ms = 0
	var mount := Node.new()
	tree.root.add_child(mount)
	tree.root.add_child(router)
	router.set_mount_point(mount)
	router.register_route(&"room_a", ROOM_A)
	router.register_route(&"room_b", ROOM_B)
	return {"router": router, "veil": veil, "mount": mount}


func _cleanup(ctx: Dictionary) -> void:
	(ctx["mount"] as Node).queue_free()
	(ctx["router"] as Node).queue_free()
	(ctx["veil"] as Node).free()
	await wait_frames(1)
