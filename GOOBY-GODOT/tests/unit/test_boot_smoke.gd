extends TestCase
## Szenen-Smoke-Test-Muster (W1a; GODOT-PLAN §2-Regel: UI-Szenen headless
## instanzieren, Node-Pfade asserten, keine Script-Errors). Andere Agents
## kopieren dieses Muster für ihre Szenen.

const MAIN_SCENE := preload("res://scripts/boot/main.tscn")
const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")


func test_main_scene_instantiates_with_expected_nodes() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	tree.root.add_child(main)
	await wait_frames(2)
	assert_true(main.get_node_or_null("World") != null, "World fehlt.")
	assert_true(main.get_node_or_null("UILayer") != null, "UILayer fehlt.")
	assert_true(main.get_node_or_null("UILayer/PlaceholderHome") != null, "PlaceholderHome fehlt.")
	var title: Label = main.get_node("UILayer/PlaceholderHome/Center/Box/Title")
	assert_eq(title.text, "GOOBY")
	var subtitle: Label = main.get_node("UILayer/PlaceholderHome/Center/Box/Subtitle")
	assert_true(subtitle.text.length() > 0, "Subtitle leer.")
	main.queue_free()
	await wait_frames(1)


func test_loading_veil_scene_node_paths() -> void:
	var veil: CanvasLayer = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	await wait_frames(1)
	assert_eq(veil.layer, 100, "Veil muss auf Layer 100 liegen (immer oben).")
	var root: Control = veil.get_node("Root")
	assert_eq(root.mouse_filter, Control.MOUSE_FILTER_STOP, "Blocker muss Input fressen.")
	assert_true(veil.get_node_or_null("Root/Backdrop") != null, "Backdrop fehlt.")
	assert_true(veil.get_node_or_null("Root/Spinner") != null, "Spinner fehlt.")
	veil.queue_free()
	await wait_frames(1)
