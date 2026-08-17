extends TestCase
## W13B — CEILING-Layer + Girlanden/Spann-Deko (Doc D §1.2/§2.1, H §6.3):
## Decken-Kollisionsmatrix, Alt-Save-Normalisierung (WALL→CEILING, Fixture!),
## Ebenen-Umschalter-Zustände, Catenary-Mathe, Girlanden-Speicher-Roundtrip,
## Lichter-Budget (≤ 4 echte OmniLights) und Lager-Buchung (Gewicht 1).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const FIXTURE := "res://tests/fixtures/w13b_altsave_decke.json"
const NOW_MS := 1768478400000

var _seq := 0
var _pfad := ""


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w13b_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	_pfad = dir + "/save_v5.json"
	gs.initialize(_pfad)
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _open_room(gs: Node, scene_path: String) -> RoomBase:
	var scene: PackedScene = load(scene_path)
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	tree.root.add_child(room)
	await wait_frames(4)
	return room


func _cleanup_room(room: Node, gs: Node) -> void:
	if room != null:
		room.queue_free()
	await wait_frames(2)
	_teardown(gs)


func _def(id: String, w: int, h: int, layer: int, extra := {}) -> Dictionary:
	var def := {
		"id": id,
		"footprint": Vector2i(w, h),
		"layer": layer,
		"lagerwert": 1,
		"pflicht": "",
		"surface": false,
		"blocks_movement": layer == GridData.Layer.FLOOR,
		"wall_size": w,
		"fill": 1.0,
	}
	def.merge(extra, true)
	return def


func _lager_rein(gs: Node, item_id: String) -> void:
	gs.update(func(state: Dictionary) -> void: StorageLogic.add(state["home"]["storage"], item_id))


# ── (a) CEILING-Layer ────────────────────────────────────────────────────────


func test_ceiling_kollisionsmatrix() -> void:
	var grid := GridData.new(Vector2i(6, 6))
	var tisch := _def("tisch", 2, 2, GridData.Layer.FLOOR)
	var lampe := _def("lampe", 1, 1, GridData.Layer.CEILING)
	assert_true(grid.place(tisch, Vector2i(2, 2), 0, "t")["ok"])
	assert_true(grid.place(lampe, Vector2i(2, 2), 0, "l")["ok"], "Decke kollidiert NICHT mit Boden")
	var zweite := grid.place(lampe, Vector2i(2, 2), 0, "l2")
	assert_false(zweite["ok"], "Decke vs. Decke kollidiert")
	assert_eq(zweite["reason"], GridData.REASON_OCCUPIED)
	assert_eq(grid.item_at(Vector2i(2, 2), GridData.Layer.CEILING), "l")
	assert_eq(grid.item_at(Vector2i(2, 2), GridData.Layer.FLOOR), "t", "Boden bleibt belegt")
	var stuhl := _def("stuhl", 1, 1, GridData.Layer.FLOOR)
	assert_true(grid.place(lampe, Vector2i(4, 4), 0, "l3")["ok"])
	assert_true(
		bool(grid.can_place(stuhl, Vector2i(4, 4), 0)["ok"]), "Decken-Item blockt den Boden nicht"
	)
	var oob := grid.can_place(lampe, Vector2i(6, 0), 0)
	assert_eq(oob["reason"], GridData.REASON_OOB, "Decken-Raster hat dieselben Bounds")


func test_ceiling_ignoriert_tuerzonen() -> void:
	var zone := [Vector2i(2, 0), Vector2i(3, 0)]
	var grid := GridData.new(Vector2i(6, 6), zone)
	var lampe := _def("lampe", 1, 1, GridData.Layer.CEILING)
	assert_true(
		grid.place(lampe, Vector2i(2, 0), 0, "l")["ok"], "Tür-Freihaltezone gilt nicht an der Decke"
	)
	var regal := _def("regal", 1, 1, GridData.Layer.FLOOR)
	assert_eq(grid.can_place(regal, Vector2i(3, 0), 0)["reason"], GridData.REASON_BLOCKED)


func test_ceiling_saveformat_roundtrip() -> void:
	var lampen_def := _def("lampe", 1, 1, GridData.Layer.CEILING)
	var defs := {"lampe": lampen_def}
	var grid := GridData.new(Vector2i(6, 6))
	assert_true(grid.place(lampen_def, Vector2i(1, 2), 0, "i-1")["ok"])
	var result := GridData.from_save(grid.to_items_array(), defs, Vector2i(6, 6))
	assert_eq((result["leftovers"] as Array).size(), 0, "nichts verschwindet")
	var neu: GridData = result["grid"]
	assert_eq(neu.item_at(Vector2i(1, 2), GridData.Layer.CEILING), "i-1", "Position identisch")


func test_altsave_normalisierung_pur() -> void:
	var fixture: Dictionary = JsonFixtures.load_json(FIXTURE)
	assert_false(fixture.is_empty(), "Fixture lädt")
	var entries: Array = (fixture["items"] as Array).duplicate(true)
	var defs := FurnitureCatalog.defs()
	assert_true(
		HomeState.normalize_ceiling_entries(entries, defs, Vector2i(12, 10)),
		"Alt-Wand-Einträge wurden umgebucht"
	)
	assert_eq(entries.size(), 3, "kein Eintrag verschwindet")
	var lampe: Dictionary = entries[0]
	assert_eq(str(lampe["uid"]), "i-000901", "uid bleibt")
	assert_false(lampe.has("wall"), "kein Wand-Placement mehr")
	assert_eq(Vector2i(int(lampe["at"][0]), int(lampe["at"][1])), Vector2i(5, 0), "N:5 → Decke")
	var lampion: Dictionary = entries[1]
	assert_false(lampion.has("wall"))
	assert_eq(
		Vector2i(int(lampion["at"][0]), int(lampion["at"][1])),
		Vector2i(11, 3),
		"E:3 → Decken-Zelle an der Ostkante"
	)
	var stuhl: Dictionary = entries[2]
	assert_eq(
		Vector2i(int(stuhl["at"][0]), int(stuhl["at"][1])),
		Vector2i(4, 4),
		"Boden-Stuhl unangetastet"
	)
	assert_false(
		HomeState.normalize_ceiling_entries(entries, defs, Vector2i(12, 10)),
		"zweiter Lauf ist ein No-Op (idempotent)"
	)


func test_altsave_ladepfad_nichts_verschwindet() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	var fixture: Dictionary = JsonFixtures.load_json(FIXTURE)
	gs.set_value("home.rooms.living.items", fixture["items"])
	var lager_vorher: int = HomeState.storage(gs).size()
	var grid := HomeState.load_room_grid(gs, "living")
	assert_eq(
		grid.item_at(Vector2i(5, 0), GridData.Layer.CEILING),
		"i-000901",
		"Hängelampe an der Decke, Position erhalten"
	)
	assert_eq(grid.item_at(Vector2i(11, 3), GridData.Layer.CEILING), "i-000902", "Lampion auch")
	assert_eq(grid.item_at(Vector2i(4, 4), GridData.Layer.FLOOR), "i-000903", "Stuhl unangetastet")
	assert_eq(HomeState.storage(gs).size(), lager_vorher, "nichts ins Lager degradiert")
	var gespeichert: Array = gs.get_value("home.rooms.living.items")
	assert_eq(gespeichert.size(), 3, "Umbuchung persistiert, alle 3 Items im Save")
	for eintrag: Dictionary in gespeichert:
		assert_false(eintrag.has("wall"), "kein Alt-Wand-Eintrag mehr im Save")
	_teardown(gs)


func test_decken_katalog_migration() -> void:
	for id: String in ["lampSquareCeiling", "ceilingFan", "lampionHanging"]:
		var def := FurnitureCatalog.def(id)
		assert_false(def.is_empty(), id + " im Katalog")
		assert_eq(int(def["layer"]), GridData.Layer.CEILING, id + " hängt jetzt an der Decke")


func test_ebene_fuer_def() -> void:
	assert_eq(BuildMode.ebene_fuer_def({"layer": GridData.Layer.RUG}), BuildMode.Ebene.BODEN)
	assert_eq(BuildMode.ebene_fuer_def({"layer": GridData.Layer.FLOOR}), BuildMode.Ebene.BODEN)
	assert_eq(BuildMode.ebene_fuer_def({"layer": GridData.Layer.SURFACE}), BuildMode.Ebene.BODEN)
	assert_eq(BuildMode.ebene_fuer_def({"layer": GridData.Layer.WALL}), BuildMode.Ebene.WAND)
	assert_eq(BuildMode.ebene_fuer_def({"layer": GridData.Layer.CEILING}), BuildMode.Ebene.DECKE)
	assert_eq(BuildMode.ebene_fuer_def({}), BuildMode.Ebene.BODEN, "ohne layer → Boden")


func test_kamera_deckenblick() -> void:
	var kamera := BuildCamera.new()
	assert_false(kamera.ist_decken_blick())
	assert_almost(kamera.blick_ziel_y(), BuildCamera.BLICK_BODEN)
	kamera.set_decken_blick(true)
	assert_true(kamera.ist_decken_blick())
	assert_almost(kamera.pitch(), BuildCamera.PITCH_DECKE, 1e-6, "flachere Neigung → Blick hoch")
	assert_almost(kamera.blick_ziel_y(), BuildCamera.BLICK_DECKE, 1e-6, "look_at wandert zur Decke")
	kamera.set_decken_blick(false)
	assert_almost(kamera.pitch(), BuildCamera.PITCH_SCHRAEG)
	assert_almost(kamera.blick_ziel_y(), BuildCamera.BLICK_BODEN)
	kamera.set_draufsicht(true)
	kamera.set_decken_blick(true)
	assert_true(kamera.ist_draufsicht(), "Draufsicht bleibt trotz Deckenblick erhalten")
	kamera.set_draufsicht(false)
	assert_almost(kamera.pitch(), BuildCamera.PITCH_DECKE, 1e-6, "zurück in die Decken-Neigung")
	kamera.free()


# ── (b) Girlanden / Spann-Deko ───────────────────────────────────────────────


func test_catenary_symmetrie_und_endpunkte() -> void:
	assert_almost(CatenaryLogic.haengeform(0.0), 0.0, 1e-9, "Endpunkt A hängt nicht durch")
	assert_almost(CatenaryLogic.haengeform(1.0), 0.0, 1e-9, "Endpunkt B hängt nicht durch")
	assert_almost(CatenaryLogic.haengeform(0.5), 1.0, 1e-9, "Tiefpunkt in der Mitte")
	for t: float in [0.1, 0.25, 0.4]:
		assert_almost(
			CatenaryLogic.haengeform(t), CatenaryLogic.haengeform(1.0 - t), 1e-9, "symmetrisch"
		)
	var a := Vector3(0.0, 2.45, 0.0)
	var b := Vector3(3.0, 2.45, 2.0)
	var punkte := CatenaryLogic.punkte(a, b, 12)
	assert_eq(punkte.size(), 13, "segmente + 1 Punkte")
	assert_almost(punkte[0].distance_to(a), 0.0, 1e-6, "Endpunkt A exakt getroffen")
	assert_almost(punkte[12].distance_to(b), 0.0, 1e-6, "Endpunkt B exakt getroffen")
	var sag := CatenaryLogic.durchhang(a.distance_to(b))
	assert_almost(punkte[6].y, a.lerp(b, 0.5).y - sag, 1e-6, "Mitte hängt genau `durchhang` tief")
	for p: Vector3 in punkte:
		assert_true(p.y <= a.y + 1e-6, "nie über der Aufhängung")


func test_catenary_durchhang_waechst_mit_distanz() -> void:
	var vorher := -1.0
	for distanz: float in [0.0, 0.5, 1.0, 2.0, 4.0, 6.0]:
		var sag := CatenaryLogic.durchhang(distanz)
		assert_true(sag > vorher, "Durchhang wächst monoton mit der Spannweite")
		vorher = sag
	assert_almost(CatenaryLogic.durchhang(100.0), CatenaryLogic.DURCHHANG_MAX, 1e-9, "gedeckelt")


func test_girlanden_katalog_kontrakt() -> void:
	for id: String in ["girlande_wimpel", "girlande_lichter", "girlande_pompons"]:
		var def := FurnitureCatalog.def(id)
		assert_false(def.is_empty(), id + " im Katalog")
		assert_eq(int(def["layer"]), GridData.Layer.CEILING, id + " lebt an der Decke")
		assert_eq(int(def["lagerwert"]), 1, id + ": Lager-Gewicht 1 wie Möbel")
		assert_eq(str(def["kategorie"]), "girlanden")


func test_lichter_budget() -> void:
	assert_eq(Girlande.licht_indizes(13).size(), 4, "Budget voll ausgeschöpft")
	assert_true(Girlande.licht_indizes(50).size() <= Girlande.MAX_LICHTER, "nie mehr als 4")
	assert_eq(Girlande.licht_indizes(2).size(), 2, "weniger Punkte als Budget → weniger Lichter")
	assert_eq(Girlande.licht_indizes(0).size(), 0)
	assert_eq(Girlande.licht_indizes(13, 0).size(), 0, "Budget 0 → keine Lichter")
	for idx: int in Girlande.licht_indizes(13):
		assert_true(idx >= 0 and idx < 13, "Indizes in den Kurven-Bounds")
	var kette := Girlande.create(
		Girlande.TYP_LICHTER, Vector3(0.0, 2.45, 0.0), Vector3(4.0, 2.45, 0.0), 23.0
	)
	assert_true(kette.lichter_anzahl() > 0, "Lichterkette hat echte Lichter")
	assert_true(kette.lichter_anzahl() <= Girlande.MAX_LICHTER, "höchstens 4 echte OmniLights")
	kette.free()
	var wimpel := Girlande.create(
		Girlande.TYP_WIMPEL, Vector3(0.0, 2.45, 0.0), Vector3(4.0, 2.45, 0.0), 23.0
	)
	assert_eq(wimpel.lichter_anzahl(), 0, "Wimpel brauchen kein Licht-Budget")
	wimpel.free()


func test_lichter_nachts_an_tags_aus() -> void:
	assert_true(Girlande.ist_nacht(23.0), "23 Uhr ist Nacht")
	assert_false(Girlande.ist_nacht(12.0), "mittags nicht")
	var kette := Girlande.create(
		Girlande.TYP_LICHTER, Vector3(0.0, 2.45, 0.0), Vector3(3.0, 2.45, 0.0), 23.0
	)
	for licht: OmniLight3D in kette._lichter:
		assert_true(licht.visible, "nachts an (injizierte Stunde)")
	kette.wende_tageszeit_an(12.0)
	for licht: OmniLight3D in kette._lichter:
		assert_false(licht.visible, "tagsüber aus")
	kette.free()


func test_girlanden_speicher_roundtrip() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	_lager_rein(gs, "girlande_wimpel")
	assert_true(
		HomeState.add_girlande(gs, "living", "girlande_wimpel", Vector2i(2, 3), Vector2i(7, 3))
	)
	assert_true(gs.save_now(), "Save geht raus")
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW_MS)
	gs2.initialize(_pfad)
	var geladen := HomeState.girlanden(gs2, "living")
	assert_eq(geladen.size(), 1, "Girlande überlebt den Roundtrip")
	var eintrag: Dictionary = geladen[0]
	assert_eq(str(eintrag["typ"]), "girlande_wimpel")
	assert_eq(HomeState.girlande_zelle(eintrag, "zelle_a"), Vector2i(2, 3), "Zelle A identisch")
	assert_eq(HomeState.girlande_zelle(eintrag, "zelle_b"), Vector2i(7, 3), "Zelle B identisch")
	gs2.free()
	_teardown(gs)


func test_girlanden_lager_buchung() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	assert_false(
		HomeState.add_girlande(gs, "living", "girlande_lichter", Vector2i(0, 0), Vector2i(3, 0)),
		"nicht im Lager → kein Spannen"
	)
	_lager_rein(gs, "girlande_lichter")
	assert_false(
		HomeState.add_girlande(gs, "living", "girlande_lichter", Vector2i(2, 2), Vector2i(2, 2)),
		"A == B ist ungültig"
	)
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "girlande_lichter"),
		1,
		"ungültiger Spann verbraucht nichts"
	)
	assert_true(
		HomeState.add_girlande(gs, "living", "girlande_lichter", Vector2i(2, 2), Vector2i(6, 2))
	)
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "girlande_lichter"), 0, "1 Exemplar entnommen"
	)
	assert_false(HomeState.remove_girlande(gs, "living", 5), "Index daneben → nichts passiert")
	assert_true(HomeState.remove_girlande(gs, "living", 0))
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "girlande_lichter"), 1, "zurück im Lager"
	)
	assert_eq(HomeState.girlanden(gs, "living").size(), 0, "Liste wieder leer")
	_teardown(gs)


func test_normalize_girlanden_heilt_kaputte_eintraege() -> void:
	var healed := (
		HomeState
		. normalize_slice(
			{
				"rooms":
				{
					"living":
					{
						"items": [],
						"girlanden":
						[
							{"typ": "girlande_wimpel", "zelle_a": [1, 1], "zelle_b": [4, 1]},
							{"typ": "", "zelle_a": [0, 0], "zelle_b": [1, 1]},
							"müll",
							{"typ": "girlande_pompons", "zelle_a": [2, 2]},
						]
					}
				}
			}
		)
	)
	var liste: Array = healed["rooms"]["living"]["girlanden"]
	assert_eq(liste.size(), 1, "nur der gültige Eintrag überlebt")
	assert_eq(str((liste[0] as Dictionary)["typ"]), "girlande_wimpel", "und zwar verbatim")


# ── Szenen-Test: Ebenen-Umschalter + Girlanden-Flow durch die echte Kette ────


func test_ebenen_umschalter_und_girlanden_flow() -> void:
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/wohnzimmer.tscn")
	room.stunde_override = 23.0
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	_lager_rein(gs, "girlande_lichter")
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(4)
	assert_eq(build.ebene(), BuildMode.Ebene.BODEN, "Baumodus startet am Boden")
	build._on_ebene_gewaehlt(BuildMode.Ebene.DECKE)
	assert_eq(build.ebene(), BuildMode.Ebene.DECKE, "Umschalter → Decke")
	assert_true(build._build_camera.ist_decken_blick(), "Kamera neigt sich zur Decke")
	var flow: GirlandenBau = build._girlanden
	flow.starte("girlande_lichter")
	assert_true(flow.aktiv())
	assert_eq(flow.tippe_zelle(Vector2i(2, 2)), "punkt_a", "erster Tap setzt Punkt A")
	assert_eq(flow.tippe_zelle(Vector2i(2, 2)), "ungueltig", "A == B geht nicht")
	assert_eq(flow.tippe_zelle(Vector2i(7, 2)), "gespannt", "zweiter Tap spannt")
	assert_eq(HomeState.girlanden(gs, "living").size(), 1, "im Slice gelandet")
	await wait_frames(2)
	var girlanden_nodes := room.find_children("*", "Girlande", true, false)
	assert_eq(girlanden_nodes.size(), 1, "Girlande hängt sichtbar im Raum")
	var kette: Girlande = girlanden_nodes[0]
	assert_true(kette.lichter_anzahl() > 0 and kette.lichter_anzahl() <= Girlande.MAX_LICHTER)
	assert_true(kette._lichter[0].visible, "23 Uhr (stunde_override) → Lichter an")
	assert_eq(flow.entferne_an(Vector2i(9, 9)), "", "daneben getippt → nichts")
	assert_eq(flow.entferne_an(Vector2i(7, 2)), "entfernt", "Anker-Tap nimmt sie ab")
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "girlande_lichter"), 1, "zurück im Lager"
	)
	assert_eq(HomeState.girlanden(gs, "living").size(), 0)
	# Decken-Möbel aus dem Drawer: Auto-Umschalten + Platzieren an der Decke.
	build._on_ebene_gewaehlt(BuildMode.Ebene.BODEN)
	_lager_rein(gs, "lampSquareCeiling")
	build._begin_new(FurnitureCatalog.def("lampSquareCeiling"))
	assert_eq(build.ebene(), BuildMode.Ebene.DECKE, "Aufnehmen schaltet auf die Decke")
	build._ghost_state["at"] = Vector2i(3, 3)
	build._rebuild_ghost()
	build._confirm_ghost()
	assert_ne(
		room.grid.item_at(Vector2i(3, 3), GridData.Layer.CEILING), "", "Lampe hängt an der Decke"
	)
	build.close()
	assert_eq(build.ebene(), BuildMode.Ebene.BODEN, "Schließen holt die Ebene zurück")
	assert_false(build._build_camera.ist_decken_blick())
	await _cleanup_room(room, gs)
