extends TestCase
## MP-B View-Smoke (Tiefenpolitur): sichert für bubblePop, carrotCatch,
## carrotGuard und gardenRush die POLITUR-Zusagen der Szenen ab — echte
## 3D-Bühne mit Kamera/Umgebung/Licht, dichte Kulisse (viel Geometrie),
## Gooby als echtes Rig IM Bild, HUD-Labels gefüllt und der Einsteiger-
## Hinweis blendet nach ein paar Sekunden aus. Beide Orientierungen laufen
## durch apply_view. Die MECHANIK (<id>_logic.gd) wird hier NICHT berührt.

const GAMES: Array[String] = ["bubblePop", "carrotCatch", "carrotGuard", "gardenRush"]
## Mindestzahl sichtbarer 3D-Geometrien: eine karge Bühne fällt durch.
const MIN_GEOMETRY := 20


static func _collect(node: Node, native_class: String) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current.is_class(native_class):
			out.append(current)
		for child in current.get_children():
			stack.append(child)
	return out


static func _has_gooby_rig(node: Node) -> bool:
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is GoobyRig:
			return true
		for child in current.get_children():
			stack.append(child)
	return false


func _mount(game_id: String) -> Node:
	var meta := MinigameRegistry.get_game(game_id)
	if meta.is_empty():
		fail_test("%s fehlt in der Registry" % game_id)
		return null
	var game: Node = (load(str(meta["scene"])) as PackedScene).instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.orientation = str(meta.get("orientation", "portrait"))
	ctx.run_seed = 4242
	tree.root.add_child(game)
	game.call("setup", ctx)
	await wait_frames(1)
	game.call("start")
	await wait_frames(2)
	return game


func _dismount(game: Node) -> void:
	game.queue_free()
	await wait_frames(1)


## Bühne mit Charakter: Kamera, Umgebung, Licht, DICHTE Kulisse und Gooby.
func test_stages_are_rich_and_star_gooby() -> void:
	for game_id: String in GAMES:
		var game := await _mount(game_id)
		if game == null:
			continue
		assert_true(_collect(game, "Camera3D").size() >= 1, "%s: keine Camera3D" % game_id)
		var envs := _collect(game, "WorldEnvironment")
		var has_env := false
		for we: WorldEnvironment in envs:
			has_env = has_env or we.environment != null
		assert_true(has_env, "%s: kein WorldEnvironment mit Environment" % game_id)
		assert_true(_collect(game, "Light3D").size() >= 1, "%s: kein 3D-Licht" % game_id)
		var geometry := _collect(game, "GeometryInstance3D").size()
		assert_true(
			geometry >= MIN_GEOMETRY,
			"%s: Kulisse zu karg (%d Geometrien < %d)" % [game_id, geometry, MIN_GEOMETRY]
		)
		assert_true(_has_gooby_rig(game), "%s: kein echtes GoobyRig im Bild" % game_id)
		await _dismount(game)


## Beide Orientierungen laufen über apply_view, HUD bleibt gefüllt.
func test_views_survive_both_orientations() -> void:
	for game_id: String in GAMES:
		var game := await _mount(game_id)
		if game == null:
			continue
		game.call("apply_view", Vector2(390.0, 844.0))
		await wait_frames(2)
		game.call("apply_view", Vector2(844.0, 390.0))
		await wait_frames(2)
		var time_label: Label = game.get("_time_label")
		assert_true(time_label != null, "%s: kein Zeit-Label" % game_id)
		if time_label != null:
			assert_false(time_label.text.is_empty(), "%s: Zeit-Label leer" % game_id)
		await _dismount(game)


## Der Einsteiger-Hinweis blendet nach ein paar Sekunden aus (Klarheit:
## das Spielfeld gehört dann dem Geschehen).
func test_hint_fades_out() -> void:
	for game_id: String in GAMES:
		var game := await _mount(game_id)
		if game == null:
			continue
		var hint: Label = game.get("_hint_label")
		assert_true(hint != null, "%s: kein Hinweis-Label" % game_id)
		if hint == null:
			await _dismount(game)
			continue
		assert_almost(hint.modulate.a, 1.0, 0.01, "%s: Hinweis startet unsichtbar" % game_id)
		# Spieluhr vorspulen (reine View-Variable) und einen Frame ticken.
		game.set("elapsed", 20.0)
		await wait_frames(2)
		assert_almost(hint.modulate.a, 0.0, 0.01, "%s: Hinweis bleibt stehen" % game_id)
		await _dismount(game)
