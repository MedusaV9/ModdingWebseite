extends TestCase
## HAUS-SICHT — HouseLayout (Hausplan): Der Plan deckt alle Innenräume ab
## und stimmt mit den Vistas aus rooms.json überein (Sync-Wächter wie
## CatalogSync), die Haus-Platzierung im Garten richtet die Haustür exakt
## über der Garten-Tür aus, und die Zaun-Lücke deckt genau die Fassade.


func test_plan_deckt_alle_innenraeume() -> void:
	for room_id: String in RoomDefs.rooms():
		var room_def := RoomDefs.room(room_id)
		if bool(room_def.get("outdoor", false)):
			assert_true(
				HouseLayout.plan(room_id).is_empty(),
				"%s: Outdoor-Raum hat keinen Platz IM Haus" % room_id
			)
			continue
		assert_false(HouseLayout.plan(room_id).is_empty(), "%s fehlt im RAUM_PLAN" % room_id)


func test_fassade_passt_zur_vista_aus_rooms_json() -> void:
	# Kompass-Invariante: `walls.N` = strasse ⇒ Nordfassade, = garten ⇒
	# Südfassade. Bricht das, zeigen Dioramen/Dachschräge in falsche Richtung.
	for room_id: String in HouseLayout.RAUM_PLAN:
		var vista := str(RoomDefs.exterior_walls(RoomDefs.room(room_id)).get("N", ""))
		var erwartet := (
			HouseLayout.FASSADE_STRASSE if vista == "strasse" else HouseLayout.FASSADE_GARTEN
		)
		assert_eq(
			HouseLayout.fassade(room_id),
			erwartet,
			"%s: Vista %s gehört zur Fassade %s" % [room_id, vista, erwartet]
		)


func test_etagen_sind_konsistent() -> void:
	assert_eq(HouseLayout.etage("living"), 0, "Wohnzimmer im Erdgeschoss")
	assert_eq(HouseLayout.etage("kitchen"), 0, "Küche im Erdgeschoss")
	assert_eq(HouseLayout.etage("bedroom"), 1, "Schlafzimmer im Dachgeschoss")
	assert_eq(HouseLayout.etage("bathroom"), 1, "Bad im Dachgeschoss")


func test_sued_fenster_gehoeren_den_gartenraeumen() -> void:
	var raeume := HouseLayout.sued_fenster_raeume()
	assert_eq(raeume.size(), HouseLayout.SUED_FENSTER_X.size(), "Jedes Fenster hat einen Raum")
	for room_id: String in raeume:
		assert_eq(
			HouseLayout.fassade(room_id),
			HouseLayout.FASSADE_GARTEN,
			"%s liegt auf der Gartenseite" % room_id
		)


func test_haustuer_steht_ueber_der_gartentuer() -> void:
	var garden_def := RoomDefs.room("garden")
	var offset := HouseLayout.garten_haus_offset(garden_def)
	var tuer_x := HouseLayout.garten_tuer_x(garden_def)
	assert_true(
		absf(offset.x + HouseExterior.TUER_X - tuer_x) < 0.001,
		"Haustür-X = Garten-Tür-X (%.2f)" % tuer_x
	)
	# Südfassade liegt HAUS_SCHWELLE hinter der Garten-Nordkante (z = 0).
	assert_true(
		absf(offset.z + HouseExterior.FRONT_Z + HouseLayout.HAUS_SCHWELLE) < 0.001,
		"Fassadenebene sitzt an der Schwelle (z=%.2f)" % (offset.z + HouseExterior.FRONT_Z)
	)


func test_zaun_luecke_deckt_die_fassade() -> void:
	var garden_def := RoomDefs.room("garden")
	var luecke := HouseLayout.garten_zaun_luecke(garden_def)
	var breite := int(Vector2i(garden_def.get("grid", Vector2i(8, 8))).x)
	assert_true(luecke[0] >= 0 and luecke[1] <= breite, "Lücke bleibt im Wandmaß")
	var luecke_m := (luecke[1] - luecke[0]) * GridData.CELL_SIZE
	assert_true(
		luecke_m >= HouseExterior.HAUS_BREITE,
		"Lücke (%.1fm) ist mindestens hausbreit (%.1fm)" % [luecke_m, HouseExterior.HAUS_BREITE]
	)
	# Die Garten-Tür (in der Fassade) liegt innerhalb der Lücke.
	var tuer_zelle := int(HouseLayout.garten_tuer_x(garden_def) / GridData.CELL_SIZE)
	assert_true(
		tuer_zelle > luecke[0] and tuer_zelle < luecke[1], "Tür liegt in der Fassaden-Lücke"
	)
