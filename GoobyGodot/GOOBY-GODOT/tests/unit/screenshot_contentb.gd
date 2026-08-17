extends SceneTree
## CONTENT-B-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Möbel-Ausstellung („IKEA“) und einen mit den NEUEN Möbeln voll eingerichteten
## Raum als Review-Artefakte. Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_contentb.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/CONTENTB"
const SETTLE_FRAMES := 24
const WINDOW := Vector2i(1280, 800)

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Möbel für den eingerichteten Raum (alle NEU aus dieser Welle), grob in der
## Reihenfolge, in der sie im Wohnzimmer Platz finden sollen.
const RAUM_MOEBEL: Array[String] = [
	"rugRounded",
	"loungeDesignSofa",
	"armchairCosy",
	"tableCoffeeGlass",
	"cabinetTelevision",
	"bookshelfTall",
	"deskOffice",
	"chairBistro",
	"monsteraPlant",
	"plantBushLarge",
	"lampStandingArc",
	"sideTableDrawers",
	"stoolWood",
	"crateWood",
	"pictureFrameWall",
	"chalkboardMenu",
	"lampionHanging",
	"televisionModern",
	"radioRetro",
	"bookStack",
	"dekoBird",
	"cactusPot",
	"toaster",
	"kitchenCoffeeMachine",
	"partyCake",
	"lampSquareTable",
]

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	await _shot_ausstellung()
	await _shot_raum()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


# ── Ausstellung ─────────────────────────────────────────────────────────


func _shot_ausstellung() -> void:
	var gs := _fresh_gs(4200)
	var screen := IkeaScreen.new()
	screen.game_state_override = gs
	screen.auto_navigate = false
	root.add_child(screen)
	await process_frame
	var showcase := screen.showcase()
	showcase.set_spin_enabled(false)

	# 1) Übersicht: großes Möbel, gedreht, mit sichtbarer Feldplatte.
	screen.select_item("loungeDesignSofa")
	showcase.set_pose(0.95, 0.38)
	showcase.set_zoom(0.95)
	await _snap("ikea_uebersicht_sofa_gedreht.png")

	# 2) Farbvariante: dasselbe Möbel in Mint, andere Drehung.
	screen.select_variant("mint")
	showcase.set_pose(-0.7, 0.3)
	await _snap("ikea_variante_mint.png")

	# 3) Kategorie-Ansicht Küche + Deko-Artikel (Toaster) in der Vitrine.
	screen.set_kategorie("kueche")
	await process_frame
	screen.select_item("toaster")
	showcase.set_pose(0.7, 0.45)
	showcase.set_zoom(0.85)
	await _snap("ikea_kategorie_kueche_toaster.png")

	# 4) Suche + Farbmuster eines Polstermöbels (Stoff-Varianten).
	screen.set_kategorie(IkeaScreen.CATEGORY_ALL)
	screen.set_search("sessel")
	await process_frame
	screen.select_item("armchairCosy")
	screen.select_variant("rose")
	showcase.set_pose(0.5, 0.35)
	await _snap("ikea_suche_und_stofffarbe.png")

	screen.queue_free()
	await process_frame
	await process_frame
	_drop_gs(gs)


# ── Eingerichteter Raum ─────────────────────────────────────────────────


func _shot_raum() -> void:
	var gs := _fresh_gs()
	var scene: PackedScene = load(str(RoomDefs.room("living")["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	root.add_child(room)
	await process_frame
	var gesetzt := _einrichten(room)
	room.rebuild_furniture()
	room.gooby().set_wander_enabled(false)
	for _i in 120:
		await process_frame
	print("  eingerichtet: %d neue Möbel" % gesetzt)
	await _snap("raum_voll_eingerichtet.png")
	room.queue_free()
	await process_frame
	await process_frame
	_drop_gs(gs)


## Stellt so viele der neuen Möbel wie möglich in den Raum (Boden/Fläche) und
## hängt Wandbilder auf. Liefert die Anzahl tatsächlich platzierter Stücke.
func _einrichten(room: RoomBase) -> int:
	var gesetzt := 0
	var wand_offset := 1
	for item_id in RAUM_MOEBEL:
		var def := FurnitureCatalog.def(item_id)
		if def.is_empty():
			push_warning("Screenshot: unbekanntes Möbel %s" % item_id)
			continue
		if int(def["layer"]) == GridData.Layer.WALL:
			if room.grid.place_wall(def, "N", wand_offset, "shot_%d" % gesetzt)["ok"]:
				wand_offset += int(def["wall_size"]) + 1
				gesetzt += 1
			continue
		var at := _freie_zelle(room.grid, def)
		if at.x < 0:
			continue
		if room.grid.place(def, at, 0, "shot_%d" % gesetzt)["ok"]:
			gesetzt += 1
	return gesetzt


func _freie_zelle(grid: GridData, def: Dictionary) -> Vector2i:
	for y in grid.size.y:
		for x in grid.size.x:
			var at := Vector2i(x, y)
			if bool(grid.can_place(def, at, 0)["ok"]):
				return at
	return Vector2i(-1, -1)


# ── Infrastruktur ───────────────────────────────────────────────────────


func _fresh_gs(coins := 1000) -> Node:
	_seq += 1
	var dir := "user://contentb_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


func _drop_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
