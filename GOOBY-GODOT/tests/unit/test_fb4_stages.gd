extends TestCase
## FB-4 DoD-Test „wirklich alles 3D": JEDE Kern-Spielszene (32 Spiele; die
## fünf Ranch-Spiele bauen ihre 3D-Bühne über RcompLauf erst nach Levelwahl
## und brauchen den GameState-Autoload — dort sichern die RW-Tests das 3D)
## enthält nach dem Mounten eine Camera3D, ein WorldEnvironment MIT
## Environment-Ressource und mindestens eine sichtbare 3D-Geometrie.
## Eine reine 2D-View fällt hier sofort durch.

## Die 16 FB-4-Umbauten (waren reine 2D-Views).
const CONVERTED := [
	"teaParty",
	"goobySays",
	"trampoline",
	"bunnyHop",
	"carrotCatch",
	"lanternFloat",
	"bubblePop",
	"carrotGuard",
	"danceParty",
	"gardenRush",
	"memoryMatch",
	"pancakeTower",
	"pipeFlow",
	"snailMail",
	"gobnom",
	"gvz",
]

## Die 16 früheren 3D-Umbauten (Bestandsschutz: bleiben 3D).
const ALREADY_3D := [
	"miniGolf",
	"basketBounce",
	"goalieGooby",
	"fishingPond",
	"ghostHunt",
	"runner",
	"toyRacer",
	"harborHopper",
	"shoppingSurf",
	"deliveryRush",
	"starHopper",
	"rocketRescue",
	"burgerBuild",
	"purblePlace",
	"hideSeek",
	"veggieChop",
]

## Level-Select-Spiele: id → [Methode, Argumente] für den Gefecht-Einstieg —
## geprüft wird der BATTLE-Pfad, nicht nur das Menü.
const LEVEL_ENTRY := {
	"gvz": ["open_level", [1]],
	"gobnom": ["open_level", ["campaign", 1]],
}


## Alle Knoten der gesuchten Klasse unterhalb von node (inkl. unsichtbarer).
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
	if LEVEL_ENTRY.has(game_id):
		var entry: Array = LEVEL_ENTRY[game_id]
		# WARN-SWEEP: duplicate() ist Pflicht — callv mit dem READ-ONLY-Array
		# aus dem const-Dictionary kopiert in Godot 4.4 alle Argumente durch
		# EINEN geteilten Puffer (alle Args werden zum letzten Element), der
		# Aufruf scheiterte still („Cannot convert argument 1 from int to
		# String“) und gobnom blieb im Level-Select statt im Battle-Pfad.
		game.callv(str(entry[0]), (entry[1] as Array).duplicate())
	await wait_frames(2)
	return game


func _assert_stage(game_id: String) -> void:
	var game := await _mount(game_id)
	if game == null:
		return
	var cameras := _collect(game, "Camera3D")
	assert_true(cameras.size() >= 1, "%s: keine Camera3D — noch 2D?" % game_id)
	var envs := _collect(game, "WorldEnvironment")
	assert_true(envs.size() >= 1, "%s: kein WorldEnvironment" % game_id)
	var has_env_resource := false
	for we: WorldEnvironment in envs:
		has_env_resource = has_env_resource or we.environment != null
	assert_true(has_env_resource, "%s: WorldEnvironment ohne Environment" % game_id)
	var geometry := _collect(game, "GeometryInstance3D")
	assert_true(geometry.size() >= 3, "%s: kaum 3D-Geometrie (%d)" % [game_id, geometry.size()])
	var lights := _collect(game, "Light3D")
	assert_true(lights.size() >= 1, "%s: kein 3D-Licht" % game_id)
	game.queue_free()
	await wait_frames(1)


## Jeder FB-4-Umbau ist eine echte 3D-Szene (Kamera + Umgebung + Geometrie).
func test_converted_games_are_3d() -> void:
	for game_id: String in CONVERTED:
		await _assert_stage(game_id)


## Die früheren 3D-Spiele bleiben 3D (Regressionsschutz).
func test_existing_3d_games_stay_3d() -> void:
	for game_id: String in ALREADY_3D:
		await _assert_stage(game_id)
