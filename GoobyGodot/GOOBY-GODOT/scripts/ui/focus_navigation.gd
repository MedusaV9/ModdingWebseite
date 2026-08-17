class_name FocusNavigation
extends RefCounted
## Gemeinsame Tastatur-/Controller-Fokusnavigation für dynamisch gebaute UI.
## Interaktive Controls bleiben per Tab/Shift-Tab erreichbar; Pfeile folgen
## derselben stabilen Reihenfolge. Versteckte und deaktivierte Controls werden
## ausgelassen, damit Fokus nie in einer unsichtbaren Karte hängen bleibt.


static func focusable(root: Node) -> Array[Control]:
	var controls: Array[Control] = []
	_collect(root, controls)
	return controls


static func wire(root: Node, horizontal := false, wrap := true) -> Array[Control]:
	var controls := focusable(root)
	wire_controls(controls, horizontal, wrap)
	return controls


static func wire_controls(controls: Array[Control], horizontal := false, wrap := true) -> void:
	if controls.is_empty():
		return
	for index in controls.size():
		var control := controls[index]
		var previous_index := index - 1
		var next_index := index + 1
		if wrap:
			previous_index = posmod(previous_index, controls.size())
			next_index = posmod(next_index, controls.size())
		var previous: Control = controls[previous_index] if previous_index >= 0 else null
		var next: Control = controls[next_index] if next_index < controls.size() else null
		control.focus_previous = _path_to(control, previous)
		control.focus_next = _path_to(control, next)
		if horizontal:
			control.focus_neighbor_left = _path_to(control, previous)
			control.focus_neighbor_right = _path_to(control, next)
		else:
			control.focus_neighbor_top = _path_to(control, previous)
			control.focus_neighbor_bottom = _path_to(control, next)


static func grab_first(root: Node) -> Control:
	var controls := wire(root)
	if controls.is_empty():
		return null
	controls[0].grab_focus()
	return controls[0]


static func grab_first_deferred(root: Node) -> void:
	if root != null and is_instance_valid(root):
		# Ein deferred Call darf kein kurzlebiges Node-Argument halten:
		# wird ein Dialog im selben Frame geschlossen, versucht Godot sonst
		# den bereits freigegebenen Object-Parameter zu konvertieren und loggt
		# einen SCRIPT ERROR, bevor der Funktions-Guard laufen kann.
		_grab_deferred.call_deferred(weakref(root))


static func _grab_deferred(root_ref: WeakRef) -> void:
	var root := root_ref.get_ref() as Node
	if root != null and is_instance_valid(root) and root.is_inside_tree():
		grab_first(root)


static func _collect(node: Node, controls: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		if (
			control.focus_mode == Control.FOCUS_ALL
			and control.is_visible_in_tree()
			and not (control is BaseButton and (control as BaseButton).disabled)
		):
			controls.append(control)
	for child in node.get_children():
		_collect(child, controls)


static func _path_to(from: Control, target: Control) -> NodePath:
	if target == null:
		return NodePath()
	return from.get_path_to(target)
