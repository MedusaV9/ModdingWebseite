class_name ArcContainer
extends Container
## Container, der seine Kinder auf einem Viertelbogen um seine RECHTE
## UNTERE Ecke anordnet — der „Daumen-Bogen“ des Hochkant-HUDs (H §1.3).
## Geometrie kommt aus der puren `HudLayoutLogic` (testbar ohne Szene).

## Luft zwischen Rand-Buttons und dem eigenen Rect (= Bildschirmkante).
const CORNER_PADDING := 6.0

@export var radius: float = HudLayoutLogic.ARC_RADIUS:
	set(value):
		radius = value
		queue_sort()

@export var start_deg: float = HudLayoutLogic.ARC_START_DEG:
	set(value):
		start_deg = value
		queue_sort()

@export var end_deg: float = HudLayoutLogic.ARC_END_DEG:
	set(value):
		end_deg = value
		queue_sort()

## Zick-Zack-Staffelung (H §1.3-ASCII): jeder 2. Button rückt nach außen,
## damit sich 72px-Buttons auf dem Daumenradius nicht überdecken.
@export var stagger: float = HudLayoutLogic.ARC_STAGGER:
	set(value):
		stagger = value
		queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()


func _get_minimum_size() -> Vector2:
	var max_child := 0.0
	for child in _visible_children():
		var ms := (child as Control).get_combined_minimum_size()
		max_child = maxf(max_child, maxf(ms.x, ms.y))
	# Vom Eck aus gemessen: Ecken-Einzug (halber Button + Padding) +
	# äußerster Radius (radius+stagger) + halber Button — sonst clippt der
	# oberste/linkeste Button genau um CORNER_PADDING (E5-F2).
	var extent := radius + stagger + max_child + CORNER_PADDING
	return Vector2(extent, extent)


func _sort_children() -> void:
	var children := _visible_children()
	var angles := HudLayoutLogic.arc_angles_deg(children.size(), start_deg, end_deg)
	# Ecke so einrücken, dass die Rand-Buttons (fast 180°/90°) mit ihrer
	# halben Breite nicht aus dem eigenen Rect (= Bildschirmkante) ragen.
	var max_child := 0.0
	for child in children:
		var ms := (child as Control).get_combined_minimum_size()
		max_child = maxf(max_child, maxf(ms.x, ms.y))
	var inset := max_child / 2.0 + CORNER_PADDING
	var corner := size - Vector2(inset, inset)
	for i in children.size():
		var child := children[i] as Control
		var child_size := child.get_combined_minimum_size()
		var child_radius := radius + (stagger if i % 2 == 1 else 0.0)
		var center := HudLayoutLogic.arc_point(corner, child_radius, angles[i])
		fit_child_in_rect(child, Rect2(center - child_size / 2.0, child_size))


func _visible_children() -> Array[Control]:
	var result: Array[Control] = []
	for child in get_children():
		if child is Control and (child as Control).visible:
			result.append(child)
	return result
