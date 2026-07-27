extends TestCase
## WELT-1 — Budget je Ansicht: die neuen Systeme bündeln konsequent in
## MultiMeshes (Zonen-Deko gedeckelt), das Gelände hat ZWEI LOD-Stufen je
## Chunk mit Sichtbarkeits-Umschaltung und ohne eigenen Schatten-Pass,
## die Atmosphäre kostet eine Handvoll Draw-Calls, Wegweiser-Labels
## tragen Distanz-Culling, und die Streu-Schätzung bleibt unter 400.
## Der ECHTE Nachweis sind die gemessenen Draw-Calls im Screenshot-Lauf.


func test_neue_zonen_deko_ist_gebuendelt() -> void:
	var wurzel := Node3D.new()
	var gruppen: Dictionary = RanchNeueZonen.new(RanchKarte.seed_wert()).baue(wurzel)
	assert_eq(gruppen.size(), 7, "sieben neue Zonen-Gruppen")
	for zone_id: String in gruppen:
		var gruppe: Node3D = gruppen[zone_id]
		var geometrie := gruppe.find_children("*", "GeometryInstance3D", true, false)
		assert_true(
			geometrie.size() <= 34,
			"%s: Deko gebündelt (%d Geometrien)" % [zone_id, geometrie.size()]
		)
		var multi := gruppe.find_children("*", "MultiMeshInstance3D", true, false)
		assert_true(multi.size() >= 1, "%s: nutzt MultiMesh" % zone_id)
	wurzel.free()


func test_terrain_chunks_haben_zwei_lod_stufen() -> void:
	var wurzel := Node3D.new()
	RanchTerrain.new().baue_chunks(wurzel)
	var erwartet := RanchTerrain.CHUNKS * RanchTerrain.CHUNKS
	var nah := 0
	var fern := 0
	for kind in wurzel.get_children():
		var mi := kind as MeshInstance3D
		assert_true(mi != null, "nur MeshInstances")
		assert_eq(
			mi.cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"Chunk ohne Schatten-Pass"
		)
		if str(mi.name).begins_with("ChunkFern_"):
			fern += 1
			assert_almost(
				mi.visibility_range_begin, RanchTerrain.LOD_WECHSEL_M, 0.001, "Fern ab LOD-Grenze"
			)
		else:
			nah += 1
			assert_almost(
				mi.visibility_range_end, RanchTerrain.LOD_WECHSEL_M, 0.001, "Nah bis LOD-Grenze"
			)
	assert_eq(nah, erwartet, "%d Nah-Chunks" % erwartet)
	assert_eq(fern, erwartet, "%d Fern-Chunks" % erwartet)
	wurzel.free()


func test_atmosphaere_ist_billig() -> void:
	var atmo := RanchAtmosphaere.new()
	atmo.einrichten(1)
	var geometrie := atmo.find_children("*", "GeometryInstance3D", true, false)
	assert_true(geometrie.size() <= 8, "Atmosphäre klein (%d Geometrien)" % geometrie.size())
	for kind in geometrie:
		assert_eq(
			(kind as GeometryInstance3D).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"Atmosphäre ohne Schatten"
		)
	atmo.tick(0.016, 6.0, "moor")
	atmo.free()


func test_nebel_und_strahlen_kurven_sind_deterministisch() -> void:
	assert_almost(RanchAtmosphaere.nebel_staerke(6.0), 1.0, 0.001, "6 Uhr = dichter Nebel")
	assert_true(RanchAtmosphaere.nebel_staerke(13.0) < 0.05, "mittags klar")
	assert_true(RanchAtmosphaere.nebel_staerke(20.5) > 0.3, "abends ein Hauch")
	assert_true(RanchAtmosphaere.strahl_staerke(7.5) > 0.9, "morgens Strahlen")
	assert_true(RanchAtmosphaere.strahl_staerke(12.5) < 0.05, "mittags keine")


func test_wegweiser_labels_haben_distanz_culling() -> void:
	var wurzel := Node3D.new()
	RanchWegenetz.baue(wurzel)
	var labels := wurzel.find_children("*", "Label3D", true, false)
	assert_true(labels.size() >= 10, "Wegweiser beschriftet (%d Labels)" % labels.size())
	for label in labels:
		assert_almost(
			(label as Label3D).visibility_range_end,
			RanchWegenetz.SICHT_M,
			0.001,
			"Label cullt auf Distanz"
		)
	wurzel.free()


func test_streu_schaetzung_bleibt_unter_budget() -> void:
	var plaene := RanchStreu.plaene(1.0)
	var schaetzung := RanchStreu.draw_call_schaetzung(plaene)
	assert_true(
		schaetzung <= RanchStreu.DRAW_CALL_BUDGET,
		"Streu-Schätzung %d <= %d" % [schaetzung, RanchStreu.DRAW_CALL_BUDGET]
	)


func test_flora_meshes_existieren_mit_erwarteter_hoehe() -> void:
	var katalog := WeltFlora.beschreibungen()
	assert_true(katalog.size() >= 6, "Flora-Katalog gefüllt")
	for id: String in katalog:
		var mesh := WeltFlora.mesh(id)
		assert_true(mesh != null, "Flora %s baut" % id)
		var hoch := mesh.get_aabb().size.y
		assert_true(
			absf(hoch - float(katalog[id])) < float(katalog[id]) * 0.45 + 0.05,
			"%s ~%.2f m hoch (ist %.2f)" % [id, float(katalog[id]), hoch]
		)


func test_kleinteil_culling_deckelt_nur_kleinteile() -> void:
	var wurzel := Node3D.new()
	var klein := _box(wurzel, Vector3(0.8, 0.8, 0.8))
	var mittel := _box(wurzel, Vector3(0.4, 3.4, 0.4))
	var gross := _box(wurzel, Vector3(12.0, 4.0, 8.0))
	var skaliert := _box(wurzel, Vector3(0.5, 0.5, 0.5))
	skaliert.scale = Vector3.ONE * 20.0
	var eigene := _box(wurzel, Vector3(0.5, 0.5, 0.5))
	eigene.visibility_range_end = 99.0
	var getroffen := WeltBudget.kleinteil_culling(wurzel)
	assert_eq(getroffen, 2, "genau klein + mittel gedeckelt")
	assert_almost(klein.visibility_range_end, WeltBudget.SICHT_KLEIN_M, 0.001, "klein cullt früh")
	assert_almost(
		mittel.visibility_range_end, WeltBudget.SICHT_MITTEL_M, 0.001, "mittel cullt später"
	)
	assert_almost(gross.visibility_range_end, 0.0, 0.001, "große Silhouette bleibt")
	assert_almost(skaliert.visibility_range_end, 0.0, 0.001, "Welt-Skala zählt")
	assert_almost(eigene.visibility_range_end, 99.0, 0.001, "eigene Ranges unangetastet")
	wurzel.free()


func _box(wurzel: Node3D, groesse: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mi.mesh = mesh
	wurzel.add_child(mi)
	return mi


func test_saison_von_datum_ist_pure() -> void:
	assert_eq(RanchTerrain.saison_von_datum("2026-01-15"), "winter")
	assert_eq(RanchTerrain.saison_von_datum("2026-04-01"), "fruehling")
	assert_eq(RanchTerrain.saison_von_datum("2026-07-26"), "sommer")
	assert_eq(RanchTerrain.saison_von_datum("2026-10-03"), "herbst")
	assert_eq(RanchTerrain.saison_von_datum("kaputt"), "sommer")
