extends TestCase
## M2 HAUS — Garten 2.0 (Doc D §6): Grid mit Bauten/Kanten, Wachstums-
## Faktoren (Wasser/Wind/Schatten/Gewächshaus), Gewächshaus-Abdeckung,
## Ernte-Datenvertrag für den Wochenmarkt und die Ausbaustufen.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const JETZT_S := 1768478400.0

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://m2_garden_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _grid(size := Vector2i(10, 8)) -> GardenGrid:
	return GardenGrid.new(size)


# ── Katalog & Grid ───────────────────────────────────────────────────────────


func test_crops_normalisiert() -> void:
	assert_true(GardenCrops.ids().size() >= 5)
	for id: String in GardenCrops.ids():
		var crop := GardenCrops.crop(id)
		assert_true(GardenCrops.LICHT_ARTEN.has(str(crop["licht"])), "%s: Lichtart" % id)
		assert_true(int(crop["stufen"]) >= 1 and int(crop["ernte"]) >= 1, "%s: Stufen/Ernte" % id)
		assert_true(GardenCrops.base_price(id) > 0, "%s: Wochenmarkt-Preis" % id)
	var exoten := GardenCrops.plantable(false).size()
	assert_true(GardenCrops.plantable(true).size() > exoten, "Exoten nur im Gewächshaus")


func test_bauten_belegen_ihren_footprint() -> void:
	var grid := _grid()
	assert_eq(GardenGrid.structure_size("gewaechshaus"), Vector2i(2, 3))
	assert_eq(GardenGrid.structure_cells("shed", Vector2i(1, 1)).size(), 4)
	assert_eq(
		GardenGrid.structure_cells("werkstatt", Vector2i(0, 0), 1).size(),
		6,
		"Rotation tauscht Breite/Tiefe, Fläche bleibt"
	)
	assert_true(grid.place_structure("shed", Vector2i(0, 0))["ok"])
	var kollision := grid.place_structure("werkstatt", Vector2i(1, 1))
	assert_false(kollision["ok"])
	assert_eq(kollision["reason"], GardenGrid.REASON_OCCUPIED)
	assert_eq(
		grid.place_structure("shed", Vector2i(9, 7))["reason"],
		GardenGrid.REASON_OOB,
		"ragt aus dem Grid"
	)
	assert_eq(
		grid.place_structure("raumschiff", Vector2i(4, 4))["reason"], GardenGrid.REASON_UNKNOWN
	)
	assert_eq(str(grid.structure_at(Vector2i(1, 1))["kind"]), "shed")
	assert_true(grid.remove_structure(Vector2i(1, 1)))
	assert_true(grid.structures.is_empty())


func test_gewaechshaus_braucht_tuerzelle() -> void:
	var grid := _grid()
	assert_eq(
		grid.place_structure("gewaechshaus", Vector2i(2, 2), 0, Vector2i(9, 9))["reason"],
		GardenGrid.REASON_NEEDS_DOOR,
		"Tür muss im eigenen Footprint liegen"
	)
	assert_true(grid.place_structure("gewaechshaus", Vector2i(2, 2), 0, Vector2i(2, 2))["ok"])
	var innen := grid.greenhouse_cells()
	assert_eq(innen.size(), 5, "2×3 minus Tür-Zelle")
	assert_false(innen.has(Vector2i(2, 2)), "die Tür-Zelle zählt nicht als Innenraum")
	assert_true(innen.has(Vector2i(3, 4)))


func test_sprinkler_und_zaun_abdeckung() -> void:
	var grid := _grid()
	grid.place_structure("sprinkler", Vector2i(4, 4))
	var nass := grid.sprinkler_cells()
	assert_eq(nass.size(), 9, "3×3 rund um den Sprinkler")
	assert_true(nass.has(Vector2i(3, 3)) and nass.has(Vector2i(5, 5)))
	assert_false(nass.has(Vector2i(6, 4)))
	grid.edges.append({"from": Vector2i(0, 0), "dir": "E", "len": 4, "fence": "fence_wood"})
	var geschuetzt := grid.fence_shielded_cells()
	assert_true(geschuetzt.has(Vector2i(0, 0)) and geschuetzt.has(Vector2i(3, 2)))
	assert_false(geschuetzt.has(Vector2i(4, 0)), "hinter dem Zaunende endet der Schutz")


func test_save_roundtrip() -> void:
	var grid := _grid()
	grid.place_structure("gewaechshaus", Vector2i(1, 1), 0, Vector2i(1, 1))
	grid.edges.append({"from": Vector2i(0, 5), "dir": "S", "len": 2, "fence": "fence_wood"})
	grid.set_cell(
		Vector2i(5, 5),
		{"kind": "plot", "crop": "carrot", "stage": 1, "progress_min": 61.0, "watered_until": 9.0}
	)
	var kopie := GardenGrid.from_save(grid.to_save())
	assert_eq(kopie.size, grid.size)
	assert_eq(kopie.plot_cells(), grid.plot_cells())
	assert_eq(str(kopie.cell(Vector2i(5, 5))["crop"]), "carrot")
	assert_eq(kopie.greenhouse_cells().size(), 5)
	assert_eq(kopie.edges.size(), 1)
	assert_eq(int(kopie.edges[0]["len"]), 2)
	var kaputt := GardenGrid.from_save(
		{"size": [4, 4], "structures": [{"kind": "ufo", "at": [0, 0]}], "cells": [{"at": [9, 9]}]}
	)
	assert_true(kaputt.structures.is_empty(), "unbekannte Bauten fallen weg")
	assert_true(kaputt.cells.is_empty(), "Zellen außerhalb fallen weg")


# ── Wachstum ─────────────────────────────────────────────────────────────────


func test_wasser_faktor() -> void:
	assert_eq(GardenGrowth.wasser_faktor(0.0, 100.0, false, false, false), 0.0)
	assert_eq(GardenGrowth.wasser_faktor(200.0, 100.0, false, false, false), 1.0)
	assert_eq(GardenGrowth.wasser_faktor(0.0, 100.0, false, true, false), 1.0)
	assert_eq(GardenGrowth.wasser_faktor(0.0, 100.0, true, false, false), 1.0)
	assert_eq(
		GardenGrowth.wasser_faktor(0.0, 100.0, true, false, true),
		0.0,
		"im Gewächshaus regnet es nicht hinein"
	)


func test_wind_faktor_am_rand() -> void:
	var size := Vector2i(10, 8)
	assert_almost(GardenGrowth.wind_faktor(Vector2i(0, 0), size, {}, false), 0.85)
	assert_almost(GardenGrowth.wind_faktor(Vector2i(1, 3), size, {}, false), 0.85)
	assert_almost(GardenGrowth.wind_faktor(Vector2i(4, 4), size, {}, false), 1.0, 1e-6, "Mitte")
	assert_almost(
		GardenGrowth.wind_faktor(Vector2i(0, 0), size, {Vector2i(0, 0): true}, false),
		1.0,
		1e-6,
		"Zaun schirmt ab"
	)
	assert_almost(GardenGrowth.wind_faktor(Vector2i(0, 0), size, {}, true), 1.0, 1e-6, "drinnen")


func test_schatten_faktor_haengt_am_licht() -> void:
	assert_almost(GardenGrowth.schatten_faktor(false, "sonne"), 1.0)
	assert_almost(GardenGrowth.schatten_faktor(true, "sonne"), 0.75)
	assert_almost(GardenGrowth.schatten_faktor(true, "schatten"), 1.1)
	assert_almost(GardenGrowth.schatten_faktor(true, "neutral"), 1.0)


func test_schattenwurf_nach_norden() -> void:
	var grid := _grid()
	grid.place_structure("baum", Vector2i(4, 4))
	var schatten := GardenGrowth.schatten_zellen(grid)
	assert_true(schatten.has(Vector2i(4, 3)) and schatten.has(Vector2i(4, 2)))
	assert_false(schatten.has(Vector2i(4, 5)), "südlich bleibt es sonnig")
	grid.structures.clear()
	grid.place_structure("sprinkler", Vector2i(4, 4))
	assert_true(
		GardenGrowth.schatten_zellen(grid).is_empty(), "ein Sprinkler wirft keinen Schatten"
	)


func test_gesamtrate_und_faktoren_einer_zelle() -> void:
	var grid := _grid()
	grid.set_cell(
		Vector2i(4, 4),
		{"kind": "plot", "crop": "tomate", "stage": 0, "progress_min": 0.0, "watered_until": 0.0}
	)
	var trocken := GardenGrowth.faktoren(grid, Vector2i(4, 4), 100.0, false, {})
	assert_almost(float(trocken["rate"]), 0.0, 1e-6, "ohne Wasser wächst nichts")
	var nass := GardenGrowth.faktoren(grid, Vector2i(4, 4), 100.0, true, {})
	assert_almost(float(nass["rate"]), 1.0, 1e-6, "Regen + Mitte + kein Schatten")
	var schattig := GardenGrowth.faktoren(grid, Vector2i(4, 4), 100.0, true, {Vector2i(4, 4): true})
	assert_almost(float(schattig["rate"]), 0.75, 1e-6, "Sonnen-Crop im Schatten")
	assert_almost(GardenGrowth.rate(1.0, 0.85, 1.1, 1.25), 1.0 * 0.85 * 1.1 * 1.25)


func test_gewaechshaus_bonus_und_wetterschutz() -> void:
	var grid := _grid()
	grid.place_structure("gewaechshaus", Vector2i(3, 3), 0, Vector2i(3, 3))
	var innen := Vector2i(4, 5)
	grid.set_cell(
		Vector2i(4, 5),
		{"kind": "plot", "crop": "ananas", "stage": 0, "progress_min": 0.0, "watered_until": 0.0}
	)
	var regen := GardenGrowth.faktoren(grid, innen, 100.0, true, {innen: true})
	assert_almost(float(regen["wasser"]), 0.0, 1e-6, "Regen kommt nicht hinein")
	assert_almost(float(regen["wind"]), 1.0, 1e-6, "windstill")
	assert_almost(float(regen["schatten"]), 1.0, 1e-6, "kein Außenschatten")
	assert_almost(float(regen["gewaechshaus"]), 1.25)
	assert_true(
		grid.place_structure("sprinkler", Vector2i(5, 5))["ok"], "Anlage steht neben dem Haus"
	)
	var mit_anlage := GardenGrowth.faktoren(grid, innen, 100.0, false, {})
	assert_almost(float(mit_anlage["rate"]), 1.25, 1e-6, "Anlage gießt auch drinnen")


func test_advance_zaehlt_stufen_und_stirbt_nie() -> void:
	var crop := GardenCrops.crop("carrot")
	var pro_stufe := float(crop["minuten_pro_stufe"])
	var data := {"crop": "carrot", "stage": 0, "progress_min": 0.0}
	assert_eq(GardenGrowth.advance(data, pro_stufe, 1.0), 1)
	assert_eq(GardenGrowth.advance(data, pro_stufe, 0.0), 1, "ohne Wasser pausiert es nur")
	assert_eq(GardenGrowth.advance(data, pro_stufe * 10.0, 1.0), int(crop["stufen"]), "Deckel")
	assert_true(GardenGrowth.ist_erntereif(data))
	assert_false(GardenGrowth.ist_erntereif({"crop": "", "stage": 9}))


# ── State ────────────────────────────────────────────────────────────────────


func test_pflanzen_giessen_ernten() -> void:
	var gs := _fresh_gs()
	var beet := Vector2i(2, 2)
	assert_false(GardenState.pflanzen(gs, beet, "gibtsnicht"))
	assert_false(GardenState.pflanzen(gs, beet, "ananas"), "Exot braucht ein Gewächshaus")
	assert_true(GardenState.pflanzen(gs, beet, "carrot"))
	assert_false(GardenState.pflanzen(gs, beet, "salat"), "Beet ist belegt")
	assert_true(GardenState.giessen(gs, beet, JETZT_S))
	assert_true(
		float(GardenState.grid(gs).cell(beet)["watered_until"]) > JETZT_S, "Gießen hält vor"
	)
	assert_eq(GardenState.ernten(gs, beet), 0, "noch nicht reif")
	var minuten := GardenCrops.total_minutes("carrot")
	assert_true(GardenState.tick(gs, JETZT_S) == 0, "erster Tick stellt nur die Uhr")
	assert_true(GardenState.tick(gs, JETZT_S + minuten * 60.0) >= 1, "Beet wächst")
	assert_true(GardenGrowth.ist_erntereif(GardenState.grid(gs).cell(beet)))
	var menge := GardenState.ernten(gs, beet)
	assert_eq(menge, int(GardenCrops.crop("carrot")["ernte"]))
	assert_eq(int(GardenState.ernte(gs).get("carrot", 0)), menge, "Wochenmarkt-Lager gefüllt")
	assert_eq(str(GardenState.grid(gs).cell(beet)["crop"]), "", "Beet ist wieder frei")
	_teardown(gs)


func test_ernte_datenvertrag() -> void:
	var gs := _fresh_gs()
	var beet := Vector2i(2, 2)
	GardenState.pflanzen(gs, beet, "salat")
	GardenState.tick(gs, JETZT_S)
	GardenState.giessen(gs, beet, JETZT_S)
	GardenState.tick(gs, JETZT_S + GardenCrops.total_minutes("salat") * 60.0)
	var menge := GardenState.ernten(gs, beet)
	assert_true(menge > 0)
	assert_false(GardenState.take_ernte(gs, "salat", menge + 1), "mehr als da ist geht nicht")
	assert_true(GardenState.take_ernte(gs, "salat", menge))
	assert_false(GardenState.ernte(gs).has("salat"), "leere Zeile verschwindet")
	_teardown(gs)


func test_ausbaustufen_und_mitte() -> void:
	var gs := _fresh_gs()
	assert_eq(GardenState.slice(gs)["size"], [GardenState.STUFEN[0].x, GardenState.STUFEN[0].y])
	assert_eq(GardenState.next_stufe_preis(gs), GardenState.STUFEN_PREISE[0])
	assert_true(GardenState.erweitern(gs))
	assert_eq(int(GardenState.slice(gs)["stufe"]), 1)
	assert_eq(GardenState.grid(gs).size, GardenState.STUFEN[1])
	while GardenState.erweitern(gs):
		pass
	assert_eq(int(GardenState.slice(gs)["stufe"]), GardenState.STUFEN.size() - 1)
	assert_eq(GardenState.next_stufe_preis(gs), 0, "maximal ausgebaut")
	var raum := Vector2(14.0, 12.0)
	var ursprung := GardenState.world_origin(raum, GardenState.STUFEN[0])
	assert_almost(ursprung.x, (14.0 - GardenState.STUFEN[0].x) * 0.5)
	assert_almost(
		GardenState.world_origin(raum, GardenState.STUFEN.back()).x,
		(14.0 - GardenState.STUFEN.back().x) * 0.5,
		1e-6,
		"auch die größte Stufe bleibt mittig im Raum"
	)
	assert_true(
		GardenState.STUFEN.back().x * GardenGrid.CELL_SIZE <= raum.x,
		"größte Stufe passt in den Garten-Raum"
	)
	_teardown(gs)


func test_sammelspots_und_baum() -> void:
	var gs := _fresh_gs()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	GardenWorld.refresh_spots(gs, JETZT_S, rng)
	var spots := GardenWorld.offene_spots(gs)
	assert_eq(spots.size(), GardenState.SPOTS_MAX)
	var erster: Vector2i = spots[0]["at"]
	var material := GardenWorld.sammeln(gs, erster, JETZT_S)
	assert_true(GardenWorld.SPOT_MATERIALIEN.has(material))
	assert_eq(CraftState.material_count(gs, material), 1, "Material liegt im Inventar")
	assert_eq(GardenWorld.offene_spots(gs).size(), GardenState.SPOTS_MAX - 1)
	assert_eq(GardenWorld.sammeln(gs, erster, JETZT_S), "", "abgesammelt bleibt leer")
	GardenWorld.refresh_spots(gs, JETZT_S + GardenState.SPOT_RESPAWN_S, rng)
	assert_eq(GardenWorld.offene_spots(gs).size(), GardenState.SPOTS_MAX, "Spot wächst nach")
	GardenWorld.baum_stempeln(gs, Vector2i(3, 3), JETZT_S)
	assert_eq(GardenWorld.baum_ernten(gs, Vector2i(3, 3), JETZT_S), 0, "Baum ist noch jung")
	var holz := GardenWorld.baum_ernten(gs, Vector2i(3, 3), JETZT_S + GardenState.BAUM_REIFE_S)
	assert_eq(holz, GardenState.BAUM_HOLZ)
	assert_eq(CraftState.material_count(gs, "holz"), GardenState.BAUM_HOLZ)
	_teardown(gs)


func test_bauen_kostet_muenzen() -> void:
	var gs := _fresh_gs()
	gs.set_value("economy.coins", 100)
	var arm := GardenWorld.bauen(gs, "werkstatt", Vector2i(0, 0))
	assert_false(arm["ok"])
	assert_eq(str(arm["reason"]), "zu_teuer")
	var preis := CraftMaterials.baumarkt_preis("struktur", "werkstatt")
	gs.set_value("economy.coins", preis + 10)
	assert_true(GardenWorld.bauen(gs, "werkstatt", Vector2i(0, 0))["ok"])
	assert_eq(int(gs.get_value("economy.coins", 0)), 10, "Münzen sind weg")
	assert_true(CraftState.werkstatt_gebaut(gs))
	assert_false(GardenWorld.bauen(gs, "villa", Vector2i(2, 2))["ok"], "nur Kaufbares")
	_teardown(gs)


func test_zaun_verbraucht_lager_items() -> void:
	var gs := _fresh_gs()
	assert_false(GardenWorld.zaun_setzen(gs, Vector2i(0, 0), "E", 2), "keine Zaunteile im Lager")
	HomeState.store_item(gs, "fence_wood")
	HomeState.store_item(gs, "fence_wood")
	assert_false(GardenWorld.zaun_setzen(gs, Vector2i(0, 0), "X", 2), "Richtung muss E oder S sein")
	assert_true(GardenWorld.zaun_setzen(gs, Vector2i(0, 0), "E", 2))
	assert_eq(StorageLogic.count_of(HomeState.storage(gs), "fence_wood"), 0)
	assert_eq(GardenState.grid(gs).edges.size(), 1)
	_teardown(gs)
