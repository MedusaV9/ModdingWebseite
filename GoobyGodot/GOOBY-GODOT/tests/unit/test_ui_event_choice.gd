extends W1cTestCase
## W18/E3a-Wächter: die Event-Choice-Karte (Herbert/Nutella/Karton) liegt in
## BEIDEN Leitformaten in der freien Bubble-Lane ÜBER der HUD-Bodenmöblierung
## (vorher: PRESET_CENTER_BOTTOM + fester Offset — hochkant lagen die Knöpfe
## unterm Dock, nur ein rosa Streifen war sichtbar). Pure Rect-Geometrie
## (EventProps.choice_rect) + Szenen-Smoke mit echtem HUD in hoch UND quer.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")


func test_choice_rect_hochformat_ueber_dock() -> void:
	var lane := {"top": 1040.0, "width": 680.0}
	var rect := EventProps.choice_rect(Vector2(720, 1280), 20.0, lane, Vector2(320, 180), [])
	check_approx(rect.end.y, 1040.0 - EventProps.CHOICE_GAP, "Unterkante mit Luft überm Dock")
	check_approx(rect.position.x, (720.0 - 320.0) / 2.0, "mittig zentriert")
	check(rect.position.y >= 20.0, "unter der Safe-Area-Oberkante")


func test_choice_rect_querformat_deckelt_breite() -> void:
	var lane := {"top": 640.0, "width": 500.0}
	var rect := EventProps.choice_rect(Vector2(1280, 720), 8.0, lane, Vector2(620, 160), [])
	check_approx(rect.size.x, 500.0, "Breite auf die Lane gedeckelt")
	check_approx(rect.end.y, 640.0 - EventProps.CHOICE_GAP, "Unterkante an der Lane-Oberkante")


func test_choice_rect_uebersteigt_bubble() -> void:
	var lane := {"top": 1040.0, "width": 680.0}
	var bubble := Rect2(Vector2(60, 860), Vector2(600, 170))
	var rect := EventProps.choice_rect(Vector2(720, 1280), 20.0, lane, Vector2(320, 180), [bubble])
	check(
		rect.end.y <= bubble.position.y - EventProps.CHOICE_GAP + 0.001,
		"Karte rutscht ÜBER die Gooby-Bubble statt sie zu überlappen"
	)


func test_choice_rect_klemmt_an_safe_top() -> void:
	var lane := {"top": 200.0, "width": 400.0}
	var rect := EventProps.choice_rect(Vector2(400, 240), 24.0, lane, Vector2(300, 400), [])
	check_approx(rect.position.y, 24.0, "Oberkante klemmt an der Safe-Area (nie offscreen)")


## Echtes HUD, beide Formate: Karte bleibt im Canvas, ÜBER der Lane-Oberkante
## und schneidet die HUD-Bodenmöblierung nicht; die Bottom-Zone wird
## reserviert und beim Abräumen wieder freigegeben.
func test_choice_karte_mit_echtem_hud_beide_formate() -> void:
	UiAnchors.reset_for_tests()
	var alte_groesse: Vector2i = tree.root.size
	var hud: Hud = HUD_SCENE.instantiate()
	mount(hud)
	var layer := CanvasLayer.new()
	mount(layer)
	# HOCHKANT: echtes Hochformat-Canvas + Dock-Layout.
	tree.root.size = Vector2i(720, 1280)
	hud.apply_layout(HudLayoutLogic.Layout.PORTRAIT)
	await tree.process_frame
	var karte := EventProps.show_choice(layer, _optionen(), _ignoriere)
	await tree.process_frame
	await tree.process_frame
	_pruefe_format(hud, karte, hud.get_node("PortraitDock") as Control, "Hochkant")
	check(UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).has(karte), "Karte reserviert Bottom-Zone")
	# QUERFORMAT: Canvas drehen — size_changed zieht die Karte automatisch um.
	tree.root.size = Vector2i(1280, 720)
	hud.apply_layout(HudLayoutLogic.Layout.LANDSCAPE)
	await tree.process_frame
	await tree.process_frame
	(karte as EventProps.ChoiceCard).relayout()
	_pruefe_format(hud, karte, hud.get_node("LandscapeColumn") as Control, "Quer")
	unmount(layer)
	await tree.process_frame
	check(UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).is_empty(), "Zone nach Abräumen frei")
	unmount(hud)
	tree.root.size = alte_groesse
	await tree.process_frame
	UiAnchors.reset_for_tests()


func _pruefe_format(hud: Hud, karte: Control, moebel: Control, format: String) -> void:
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var lane: Dictionary = hud.bubble_lane()
	var rect := karte.get_global_rect()
	check(
		rect.end.y <= float(lane["top"]) + 0.5,
		"%s: Karte ÜBER der Lane-Oberkante (%.1f vs %.1f)" % [format, rect.end.y, lane["top"]]
	)
	check(
		rect.position.y >= 0.0 and rect.end.y <= canvas.y, "%s: Karte vertikal im Canvas" % format
	)
	check(
		rect.position.x >= 0.0 and rect.end.x <= canvas.x, "%s: Karte horizontal im Canvas" % format
	)
	if moebel != null and moebel.visible:
		check(
			not rect.intersects(moebel.get_global_rect()),
			"%s: Karte schneidet die HUD-Bodenmöblierung nicht" % format
		)


func _optionen() -> Array:
	return [
		{"key": "events.wurm.draussen", "variation": &"BtnTeal"},
		{"key": "events.wurm.giessen", "variation": &"BtnPink"},
	]


func _ignoriere(_option: Dictionary) -> void:
	pass
