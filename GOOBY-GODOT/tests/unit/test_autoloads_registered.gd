extends TestCase
## W1a-Canary: die drei Kern-Autoloads aus project.godot müssen unter
## /root/ existieren (Autoloads laden auch unter `--script run_tests.gd`).
## Fängt Tippfehler in Autoload-Pfaden headless ab. Prüft NUR W1a-eigene
## Autoloads — fremde (GameState, ThemeService, …) werden hier NIE gelistet.


func test_core_autoloads_are_registered() -> void:
	for autoload_name in ["AppSettings", "OrientationService", "SceneRouter"]:
		var node := tree.root.get_node_or_null(NodePath(autoload_name))
		assert_true(node != null, "Autoload %s fehlt unter /root." % autoload_name)


func test_scene_router_autoload_owns_a_veil() -> void:
	var router := tree.root.get_node_or_null(NodePath("SceneRouter"))
	assert_true(router != null, "SceneRouter fehlt.")
	if router == null:
		return
	var veil_found := false
	for child in router.get_children():
		if child.has_method("cover") and child.has_method("reveal"):
			veil_found = true
	assert_true(veil_found, "SceneRouter muss sein LoadingVeil selbst instanzieren.")
