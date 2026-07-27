extends TestCase
## MP-E Tiefenpolitur — Kulissen-Bausteine der vier Sportspiele. Die Builder
## sind reine Deko (keine Mechanik); die Tests sichern, dass sie headless
## bauen, ihre Rückgabe-Knoten liefern und die Tick-Helfer sich benehmen.

const GolfScenery := preload("res://scripts/minigames/games/mini_golf/mini_golf_scenery.gd")
const BasketScenery := preload(
	"res://scripts/minigames/games/basket_bounce/basket_bounce_scenery.gd"
)
const GoalieScenery := preload("res://scripts/minigames/games/goalie_gooby/goalie_gooby_scenery.gd")
const FishingScenery := preload(
	"res://scripts/minigames/games/fishing_pond/fishing_pond_scenery.gd"
)


func test_golf_scenery_builds() -> void:
	var stage := Node3D.new()
	GolfScenery.build(stage)
	assert_true(stage.get_child_count() >= 8, "Anlage stellt Deko-Bahnen, Zaun, Kiosk usw.")
	stage.free()


func test_basket_scenery_returns_crowd() -> void:
	var stage := Node3D.new()
	var crowd := BasketScenery.build(stage)
	assert_ne(crowd, null, "Zuschauer-Knoten kommt zurück (für die Jubel-Animation)")
	assert_true(stage.is_ancestor_of(crowd), "Zuschauer hängen in der Bühne")
	assert_true(stage.get_child_count() >= 5, "Zaun, Lampen, Wolken, Ballständer, Bänke")
	stage.free()


func test_goalie_scenery_returns_crowd() -> void:
	var stage := Node3D.new()
	var crowd := GoalieScenery.build(stage)
	assert_ne(crowd, null, "Zuschauer-Knoten kommt zurück (für den Paraden-Hüpfer)")
	assert_true(stage.is_ancestor_of(crowd), "Zuschauer hängen in der Bühne")
	assert_true(stage.get_child_count() >= 6, "Vereinsheim, Flutlicht, Bande, Fahnen, Hütchen")
	stage.free()


func test_fishing_scenery_returns_ducks_and_bucket() -> void:
	var stage := Node3D.new()
	var deco := FishingScenery.build(stage)
	var ducks := deco["ducks"] as Node3D
	var bucket := deco["bucket"] as Node3D
	assert_eq(ducks.get_child_count(), FishingScenery.DUCK_SPOTS.size(), "eine Ente pro Platz")
	for duck: Node3D in ducks.get_children():
		assert_true(duck.has_meta("home") and duck.has_meta("phase"), "Paddel-Metadaten")
	assert_ne(bucket, null, "Fang-Eimer kommt zurück")
	stage.free()


func test_fishing_ducks_paddle() -> void:
	var stage := Node3D.new()
	var deco := FishingScenery.build(stage)
	var ducks := deco["ducks"] as Node3D
	var duck := ducks.get_child(0) as Node3D
	var home: Vector3 = duck.get_meta("home")
	FishingScenery.tick_ducks(ducks, 2.0)
	assert_true(absf(duck.position.x - home.x) > 0.01, "Ente paddelt seitlich um den Ruheplatz")
	assert_true(absf(duck.position.x - home.x) <= 0.45, "…aber bleibt in Ufernähe")
	assert_almost(duck.position.z, home.z, 1e-6, "Fahrrinne bleibt parallel zum Ufer")
	FishingScenery.tick_ducks(null, 1.0)
	stage.free()


func test_fishing_flight_lands_in_bucket() -> void:
	var stage := Node3D.new()
	var deco := FishingScenery.build(stage)
	var bucket := deco["bucket"] as Node3D
	var fins_before := bucket.get_child_count()
	var flyer := Node3D.new()
	stage.add_child(flyer)
	var flights: Array[Dictionary] = [
		{"node": flyer, "t": 0.0, "from": Vector3(0.0, -2.0, 0.0), "color": Color.ORANGE}
	]
	for _i in 12:
		FishingScenery.tick_flights(flights, bucket, 0.1)
	assert_true(flights.is_empty(), "Flug endet nach ~0,55 s im Eimer")
	assert_eq(bucket.get_child_count(), fins_before + 1, "eine Schwanzflosse pro Fang")
	assert_eq(int(bucket.get_meta("fins", 0)), 1, "Flossen-Zähler zählt mit")
	await wait_frames(1)
	stage.free()


func test_fishing_bucket_caps_trophies() -> void:
	var stage := Node3D.new()
	var deco := FishingScenery.build(stage)
	var bucket := deco["bucket"] as Node3D
	var fins_before := bucket.get_child_count()
	for _catch in 9:
		var flyer := Node3D.new()
		stage.add_child(flyer)
		var flights: Array[Dictionary] = [
			{"node": flyer, "t": 0.0, "from": Vector3.ZERO, "color": Color.RED}
		]
		for _i in 12:
			FishingScenery.tick_flights(flights, bucket, 0.1)
	assert_eq(bucket.get_child_count(), fins_before + 6, "Eimer läuft nicht über (Deckel bei 6)")
	await wait_frames(1)
	stage.free()
