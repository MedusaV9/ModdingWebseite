extends TestCase
## REST-1 Rang 1 + P1-Fix: der Profil-Knopf öffnet den ECHTEN Profil-Screen
## (Route &"profil" → profil_screen.tscn, NICHT mehr den Social-Screen),
## und der Screen zeigt die Pass-/Statistik-/Lieblinge-/Erfolgs-/Sticker-/
## Freunde-Blöcke aus dem echten Save-State.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1_750_000_000_000

var _seq := 0


class FakeRouter:
	extends Node

	var routes: Dictionary = {}
	var went: Array = []

	func register_routes(new_routes: Dictionary) -> void:
		for key: Variant in new_routes:
			routes[key] = new_routes[key]

	func goto(target: StringName, params: Dictionary = {}) -> void:
		went.append({"target": target, "params": params})


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://rest1_tests/profil_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


## Echten SceneRouter kurz parken, FakeRouter einhängen (IkeaScreen-Muster).
func _mit_fake_router(callback: Callable) -> void:
	var echt := tree.root.get_node_or_null(NodePath("SceneRouter"))
	if echt != null:
		echt.name = "SceneRouterGeparkt"
	var router := FakeRouter.new()
	router.name = "SceneRouter"
	tree.root.add_child(router)
	callback.call(router)
	tree.root.remove_child(router)
	router.free()
	if echt != null:
		echt.name = "SceneRouter"


func test_hud_action_profil_oeffnet_profil_screen() -> void:
	_mit_fake_router(
		func(router: FakeRouter) -> void:
			assert_false(ProfilScreen.handle_hud_action(&"album"), "fremde Action bleibt liegen")
			assert_true(ProfilScreen.handle_hud_action(&"profil"), "profil wird konsumiert")
			assert_eq(
				str(router.routes.get(ProfilScreen.ROUTE, "")),
				"res://scripts/ui/profil/profil_screen.tscn",
				"Profil-Route angemeldet"
			)
			assert_true(
				router.routes.has(AchievementsScreen.ROUTE),
				"Erfolgs-Route gleich mit angemeldet (Vorschau-Sprung)"
			)
			assert_eq(router.went.size(), 1, "genau eine Reise")
			assert_eq(router.went[0]["target"], ProfilScreen.ROUTE, 'Ziel ist &"profil"')
			assert_ne(router.went[0]["target"], SocialScreen.ROUTE, "NICHT mehr der Social-Screen")
	)
	assert_true(
		ResourceLoader.exists(str(ProfilScreen.ROUTES[ProfilScreen.ROUTE])), "Profil-Szene da"
	)
	assert_true(
		ResourceLoader.exists(str(AchievementsScreen.ROUTES[AchievementsScreen.ROUTE])),
		"Erfolgs-Szene da"
	)


func test_profil_screen_zeigt_save_daten() -> void:
	var gs := _fresh_gs()
	tree.root.add_child(gs)
	gs.update(
		func(state: Dictionary) -> void:
			state["meta"]["goobyNickname"] = "Flauschi"
			state["achievements"]["counters"]["feeds"] = 12
			state["daily"]["streak"] = 5
			state["profile"]["playtimeMin"] = 125
			state["profile"]["distanceM"] = 4200
	)
	var screen := ProfilScreen.new()
	screen.auto_navigate = false
	screen.gs_override = gs
	tree.root.add_child(screen)
	await wait_frames(2)
	var name_label := screen.find_child("GoobyName", true, false) as Label
	assert_true(name_label != null, "Namenszeile da")
	if name_label != null:
		assert_eq(name_label.text, "Flauschi", "Gooby-Name aus meta")
	var serie := screen.find_child("RowSerie", true, false)
	assert_true(serie != null, "Serien-Zeile da (Rang 8: Anzeige im Profil)")
	if serie != null:
		var wert := serie.find_child("Wert", true, false) as Label
		assert_eq(wert.text, I18nService.t("profil.serie_wert", {"n": 5}), "Serie Tag 5")
	var spielzeit := screen.find_child("RowSpielzeit", true, false)
	if spielzeit != null:
		var wert := spielzeit.find_child("Wert", true, false) as Label
		assert_eq(wert.text, "2:05 h", "Spielzeit h:mm")
	var grid := screen.find_child("StatsGrid", true, false)
	assert_true(grid != null, "Statistik-Grid da")
	if grid != null:
		assert_eq(grid.get_child_count(), 17, "17 Statistik-Zellen")
	assert_true(screen.find_child("PassPortrait", true, false) is GoobyPreview, "ECHTES 3D-Porträt")
	assert_true(screen.find_child("XpBar", true, false) is ProgressBar, "Level-Balken da")
	var erfolge := screen.find_child("ErfolgeStand", true, false) as Label
	assert_true(erfolge != null, "Erfolgs-Vorschau da")
	if erfolge != null:
		assert_eq(
			erfolge.text,
			I18nService.t("profil.erfolge_stand", {"n": 0, "total": 44}),
			"0 von 44 auf frischem Save"
		)
	assert_true(screen.find_child("StickerBar", true, false) is ProgressBar, "Sticker-Balken da")
	assert_true(screen.find_child("FreundeLeer", true, false) != null, "Freunde-Leerzustand")
	assert_true(screen.find_child("FreundeBtn", true, false) is Button, "Sprung Freunde & Besuche")
	assert_true(screen.find_child("ErfolgeBtn", true, false) is Button, "Sprung Erfolgs-Screen")
	tree.root.remove_child(screen)
	screen.free()
	tree.root.remove_child(gs)
	gs.free()


func test_erfolgs_screen_kategorien_und_mystery() -> void:
	var gs := _fresh_gs()
	tree.root.add_child(gs)
	gs.update(
		func(state: Dictionary) -> void:
			state["achievements"]["counters"]["feeds"] = 3
			state["achievements"]["unlocked"]["firstFeed"] = NOW_MS
	)
	var screen := AchievementsScreen.new()
	screen.auto_navigate = false
	screen.gs_override = gs
	tree.root.add_child(screen)
	await wait_frames(2)
	assert_eq(screen.unlocked_count(), 1, "1 von 44 frei")
	var row := screen.find_child("Erfolg_firstFeed", true, false)
	assert_true(row != null, "firstFeed-Zeile da")
	if row != null:
		var name_label := row.find_child("Name", true, false) as Label
		assert_eq(
			name_label.text,
			I18nService.t("achievements.defs.firstFeed.name"),
			"freigeschaltet → echter Name"
		)
	var locked := screen.find_child("Erfolg_feed100", true, false)
	if locked != null:
		var name_label := locked.find_child("Name", true, false) as Label
		assert_eq(name_label.text, I18nService.t("achievements.geheim"), "gesperrt → ???")
		var bar := locked.find_child("Fortschritt", true, false) as ProgressBar
		assert_eq(int(bar.value), 3, "Fortschritt 3/100 aus dem Save")
		assert_eq(int(bar.max_value), 100, "Ziel 100")
	screen.show_category("garten")
	await wait_frames(1)
	var list := screen.find_child("Erfolg_firstHarvest", true, false)
	assert_true(list != null, "Garten-Kategorie zeigt firstHarvest")
	assert_true(
		screen.find_child("Erfolg_firstFeed", true, false) == null,
		"Pflege-Erfolg raus, wenn Garten gefiltert"
	)
	tree.root.remove_child(screen)
	screen.free()
	tree.root.remove_child(gs)
	gs.free()
