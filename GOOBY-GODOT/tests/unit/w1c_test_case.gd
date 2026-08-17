class_name W1cTestCase
extends RefCounted
## Mini-Testbasis für die W1c-UI-Tests (eigener Namensraum, kollidiert nicht
## mit dem W1a-Runner `tests/test_case.gd`). Ein Testfile = eine Klasse,
## Methoden mit `test_`-Präfix werden vom Runner (auch async) ausgeführt.

var tree: SceneTree
var failures: Array[String] = []
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s — erwartet %s, war %s" % [message, expected, actual])


func check_approx(actual: float, expected: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > 0.0001:
		failures.append("%s — erwartet %s, war %s" % [message, expected, actual])


## Node kurz in den Baum hängen (für Szenen-Smoke-Tests).
func mount(node: Node) -> void:
	tree.root.add_child(node)


func unmount(node: Node) -> void:
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()
