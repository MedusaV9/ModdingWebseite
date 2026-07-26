extends TestCase
## FB3 — Geräteformat-Matrix für die UI-Screens (P0 „UI klebt am Rand und
## skaliert nicht mit der Gerätegröße“): jeder geprüfte Screen wird in
## 4 Formaten (iPhone quer ×2, iPhone hoch, iPad quer) MIT simulierter
## Notch/Home-Indicator aufgebaut und muss:
## - alle Bedienelemente INNERHALB des sicheren Bereichs halten,
## - Tippflächen ≥ 44 pt (physisch) bieten,
## - überlappungsfrei sein (Button × Button).

## [Label, Fenster-px, screen_scale, Insets in PUNKTEN [l, t, r, b]]
const FORMATS: Array = [
	["quer_2556x1179", Vector2i(2556, 1179), 3.0, [59.0, 0.0, 59.0, 21.0]],
	["quer_1792x828", Vector2i(1792, 828), 2.0, [48.0, 0.0, 48.0, 21.0]],
	["hoch_1179x2556", Vector2i(1179, 2556), 3.0, [0.0, 59.0, 0.0, 34.0]],
	["ipad_2360x1640", Vector2i(2360, 1640), 2.0, [0.0, 24.0, 0.0, 20.0]],
]
const MIN_TAP_PT := 44.0
const TAP_TOLERANCE_PT := 0.5

var _saved_root_size := Vector2i.ZERO
## Kontext des aktuellen Formats (setzt _enter_format).
var _safe_rect := Rect2()
var _canvas := Vector2.ZERO
var _px_per_pt := 1.0


func _enter_format(format: Array) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	var win: Vector2i = format[1]
	var scale: float = format[2]
	UiScale.screen_scale_override = scale
	DisplayServer.window_set_size(win)
	tree.root.size = win
	await wait_frames(2)
	_canvas = Vector2(tree.root.get_visible_rect().size)
	var pt_short := minf(float(win.x), float(win.y)) / scale
	_px_per_pt = minf(_canvas.x, _canvas.y) / pt_short
	var insets_pt: Array = format[3]
	var l := float(insets_pt[0]) * _px_per_pt
	var t := float(insets_pt[1]) * _px_per_pt
	var r := float(insets_pt[2]) * _px_per_pt
	var b := float(insets_pt[3]) * _px_per_pt
	_safe_rect = Rect2(l, t, _canvas.x - l - r, _canvas.y - t - b)
	UiScale.insets_override = Rect2(_safe_rect)


func _leave_formats() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		DisplayServer.window_set_size(_saved_root_size)
		_saved_root_size = Vector2i.ZERO
	await wait_frames(2)


## Sichtbare Bedienelemente unterm Screen (ohne SubViewport-Inhalte).
func _interactive_controls(screen: Node) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is SubViewport:
			continue
		stack.append_array(node.get_children())
		if (node is Button or node is LineEdit) and (node as Control).is_visible_in_tree():
			out.append(node)
	return out


func _effective_rect(ctl: Control) -> Rect2:
	var rect := ctl.get_global_rect()
	var node: Node = ctl.get_parent()
	while node != null and node is Control:
		var parent := node as Control
		if parent.clip_contents or parent is ScrollContainer:
			rect = rect.intersection(parent.get_global_rect())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				return Rect2()
		node = parent.get_parent()
	return rect


func _check_screen(screen: Node, label: String) -> void:
	var controls := _interactive_controls(screen)
	assert_true(controls.size() > 0, "%s: Bedienelemente gefunden" % label)
	for ctl in controls:
		var rect := _effective_rect(ctl)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		assert_true(
			_safe_rect.grow(2.0).encloses(rect),
			(
				"%s: %s(%s) bleibt im sicheren Bereich (rect=%s safe=%s)"
				% [label, ctl.name, ctl.get_class(), rect, _safe_rect]
			)
		)
		if ctl is Button and not (ctl as Button).disabled:
			# Tippfläche = ECHTE Knopfgröße (ungeclippt): teilweise aus dem
			# Scroll-Fenster gescrollte Kacheln sind kein Größen-Verstoß.
			var own := ctl.get_global_rect()
			var short_pt := minf(own.size.x, own.size.y) / _px_per_pt
			assert_true(
				short_pt >= MIN_TAP_PT - TAP_TOLERANCE_PT,
				"%s: %s Tippfläche %.1f pt ≥ %d pt" % [label, ctl.name, short_pt, MIN_TAP_PT]
			)
	for i in controls.size():
		if not (controls[i] is Button):
			continue
		for j in range(i + 1, controls.size()):
			if not (controls[j] is Button):
				continue
			if controls[i].is_ancestor_of(controls[j]) or controls[j].is_ancestor_of(controls[i]):
				continue
			var overlap := _effective_rect(controls[i]).intersection(_effective_rect(controls[j]))
			assert_false(
				overlap.size.x > 4.0 and overlap.size.y > 4.0,
				"%s: %s überlappt %s (%s)" % [label, controls[i].name, controls[j].name, overlap]
			)


func test_friends_screen_in_vier_formaten() -> void:
	for format: Array in FORMATS:
		await _enter_format(format)
		var screen := FriendsScreen.new()
		screen.auto_navigate = false
		tree.root.add_child(screen)
		await wait_frames(3)
		_check_screen(screen, "friends/%s" % format[0])
		screen.free()
	await _leave_formats()


func test_arcade_screen_in_vier_formaten() -> void:
	for format: Array in FORMATS:
		await _enter_format(format)
		var screen: Control = (
			(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
		)
		screen.set("auto_navigate", false)
		tree.root.add_child(screen)
		await wait_frames(3)
		_check_screen(screen, "arcade/%s" % format[0])
		screen.free()
	await _leave_formats()


func test_pregame_in_vier_formaten() -> void:
	for format: Array in FORMATS:
		await _enter_format(format)
		var screen: Control = (
			(load("res://scripts/minigames/pregame.tscn") as PackedScene).instantiate()
		)
		screen.set("auto_navigate", false)
		screen.call("receive_params", {"game_id": "teaParty"})
		tree.root.add_child(screen)
		await wait_frames(3)
		_check_screen(screen, "pregame/%s" % format[0])
		screen.free()
	await _leave_formats()


func test_results_in_vier_formaten() -> void:
	for format: Array in FORMATS:
		await _enter_format(format)
		var screen: MinigameResults = (
			(load("res://scripts/minigames/results.tscn") as PackedScene).instantiate()
		)
		tree.root.add_child(screen)
		await wait_frames(1)
		screen.show_results(
			{"score": 123, "coins": 8, "best": 200, "xp": 12}, {"title_key": "mg.teaParty.title"}
		)
		await wait_frames(3)
		_check_screen(screen, "results/%s" % format[0])
		screen.free()
	await _leave_formats()


func test_pause_modal_in_vier_formaten_kompakt() -> void:
	for format: Array in FORMATS:
		await _enter_format(format)
		var modal := MinigamePauseModal.new()
		modal.hint_key = "mg.teaParty.hint"
		tree.root.add_child(modal)
		await wait_frames(1)
		modal.open()
		await wait_frames(3)
		_check_screen(modal, "pause/%s" % format[0])
		var card: Control = modal.get("_card")
		var rect := card.get_global_rect()
		assert_true(
			rect.size.x <= _canvas.x * 0.62 + 1.0,
			"pause/%s: Karte kompakt (%.0f px)" % [format[0], rect.size.x]
		)
		assert_true(
			rect.get_center().distance_to(_safe_rect.get_center()) <= _canvas.y * 0.05,
			"pause/%s: Karte mittig in der Safe-Area" % format[0]
		)
		modal.hide_modal()
		modal.free()
	await _leave_formats()


func test_hud_in_vier_formaten() -> void:
	for format: Array in FORMATS:
		await _enter_format(format)
		var hud: Control = (load("res://scripts/ui/hud.tscn") as PackedScene).instantiate()
		tree.root.add_child(hud)
		await wait_frames(3)
		_check_screen(hud, "hud/%s" % format[0])
		hud.free()
	await _leave_formats()
