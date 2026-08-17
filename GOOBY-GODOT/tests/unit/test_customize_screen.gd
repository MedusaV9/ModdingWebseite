extends TestCase
## HAUS-CUSTOM — Gestalten-Screen: Aufbau (Kategorien/Raum-Chips/Kacheln/
## Palette), Live-Vorschau wechselt Innen/Außen, Kauf-Flow über die UI
## (vormerken → kaufen → angewendet) und Zufall/Reset über die Knöpfe.

const GameStateScript := preload("res://scripts/state/game_state.gd")

var _dir_seq := 0


func _fresh_gs(coins := 1000) -> Node:
	HomeState.register_slice()
	_dir_seq += 1
	var dir := "user://hauscustom_tests/ui_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.update(func(state: Dictionary) -> void: state["economy"]["coins"] = coins)
	return gs


func _screen(gs: Node) -> CustomizeScreen:
	var screen := CustomizeScreen.new()
	screen.auto_navigate = false
	screen.game_state_override = gs
	tree.root.add_child(screen)
	return screen


func test_aufbau_und_vorschau_wechsel() -> void:
	var gs := _fresh_gs()
	var screen := _screen(gs)
	await wait_frames(2)
	var liste: Node = screen.find_child("KategorieListe", true, false)
	var knoepfe := 0
	for kind in liste.get_children():
		if kind is Button:
			knoepfe += 1
	assert_eq(knoepfe, CustomizeScreen.KATEGORIEN.size(), "alle Kategorien gelistet")
	assert_true(screen.find_child("Raum_living", true, false) != null, "Raum-Chips da")
	assert_true(screen.find_child("Raum_garden", true, false) == null, "Garten kein Innenraum")
	assert_eq(screen.preview().modus(), "innen", "Innen-Kategorie = Innen-Vorschau")
	assert_true(screen.find_child("Option_gebluemt", true, false) != null, "Options-Kacheln gebaut")
	screen.set_kategorie("fassade")
	await wait_frames(1)
	assert_eq(screen.preview().modus(), "aussen", "Haus-Kategorie = Außen-Vorschau")
	assert_true(
		screen.find_child("Farbe_rose", true, false) != null, "Fassade zeigt Palette-Swatches"
	)
	screen.set_kategorie("grund_boden")
	await wait_frames(1)
	assert_eq(screen.preview().modus(), "aussen", "Grundstück ebenfalls außen")
	screen.free()
	gs.free()


func test_farbwahl_schreibt_state() -> void:
	var gs := _fresh_gs()
	var screen := _screen(gs)
	await wait_frames(1)
	screen.set_kategorie("fassade")
	screen.select_farbe("himmel")
	assert_eq(
		str(HouseStyleState.style(gs)["haus"]["fassade"]), "himmel", "Farbwahl sofort im Save"
	)
	screen.set_kategorie("wand")
	screen.set_raum("kitchen")
	screen.select_farbe("mint")
	assert_eq(
		str(HouseStyleState.raum_style(gs, "kitchen")["wandFarbe"]), "mint", "Innen-Farbe pro Raum"
	)
	screen.free()
	gs.free()


func test_kauf_flow_ueber_ui() -> void:
	var gs := _fresh_gs(200)
	var screen := _screen(gs)
	await wait_frames(1)
	screen.set_kategorie("wand")
	screen.select_option("gebluemt")
	assert_eq(screen.pending_id(), "gebluemt", "nicht gekauft = vorgemerkt (Anprobe)")
	assert_eq(
		str(HouseStyleState.raum_style(gs, "living")["wand"]), "uni", "noch nichts gespeichert"
	)
	var kauf: Button = screen.find_child("KaufButton", true, false)
	assert_true(kauf.visible, "Kaufen-Knopf sichtbar")
	assert_eq(screen.buy_selected(), HouseStyleState.RESULT_OK, "Kauf klappt")
	assert_eq(screen.pending_id(), "", "Vormerkung aufgelöst")
	assert_eq(str(HouseStyleState.raum_style(gs, "living")["wand"]), "gebluemt", "angewendet")
	assert_eq(int(gs.get_value("economy.coins")), 20, "180 Münzen bezahlt")
	screen.select_option("rauten")
	assert_eq(screen.buy_selected(), HouseStyleState.RESULT_BROKE, "20 < 260")
	assert_eq(str(HouseStyleState.raum_style(gs, "living")["wand"]), "gebluemt", "unverändert")
	screen.free()
	gs.free()


func test_besitz_wird_sofort_angewendet() -> void:
	var gs := _fresh_gs()
	var screen := _screen(gs)
	await wait_frames(1)
	screen.set_kategorie("boden")
	screen.select_option("dielen_hell")
	assert_eq(screen.pending_id(), "", "Besitz braucht keine Vormerkung")
	screen.set_kategorie("zaun")
	screen.select_option("latten")
	assert_eq(str(HouseStyleState.style(gs)["grundstueck"]["zaun"]), "latten")
	screen.select_farbe("teal")
	assert_eq(str(HouseStyleState.style(gs)["grundstueck"]["zaunFarbe"]), "teal")
	screen.free()
	gs.free()


func test_zufall_reset_und_hausnummer() -> void:
	var gs := _fresh_gs()
	var screen := _screen(gs)
	await wait_frames(1)
	screen.set_kategorie("hausnummer")
	screen.set_hausnummer_zahl(3)
	assert_eq(int(HouseStyleState.style(gs)["haus"]["hausnummerZahl"]), 8, "5 + 3")
	screen.set_kategorie("fassade")
	screen.select_farbe("terracotta")
	screen.zufall()
	var fassade := str(HouseStyleState.style(gs)["haus"]["fassade"])
	assert_true(CustomizeCatalog.farb_wahl("fassade").has(fassade), "Zufall bleibt in Palette")
	screen.reset_aktuell()
	assert_eq(
		HouseStyleState.style(gs)["haus"], CustomizeCatalog.default_haus(), "Reset = Standard"
	)
	screen.free()
	gs.free()
