extends TestCase
## FIX-5 „Die Stadt ist leer" — Kulissen-Planer: Dichte (jeder freie Block
## wird bebaut/begrünt), Determinismus, Kategorien-Vielfalt, Platzierungen
## bleiben auf der Karte und weg von Straße/Orten, Draw-Call-Budget der
## MultiMesh-Gruppen, Nacht-Fenster und die Hausausfahrt.


func test_kulisse_ist_dicht_und_deterministisch() -> void:
	var karte := CityMap.laden()
	var a := CityKulisse.plaene(karte, 4242)
	var b := CityKulisse.plaene(karte, 4242)
	assert_true(a.size() >= 250, "dichte Stadt: %d Platzierungen (soll ≥ 250)" % a.size())
	assert_eq(a.size(), b.size(), "gleicher Seed ⇒ gleicher Plan")
	for i in mini(a.size(), b.size()):
		assert_eq(a[i]["glb"], b[i]["glb"], "Eintrag %d gleiches GLB" % i)
		assert_eq(a[i]["pos"], b[i]["pos"], "Eintrag %d gleiche Position" % i)
	var c := CityKulisse.plaene(karte, 9)
	assert_ne(c, a, "anderer Seed ⇒ andere Kulisse")


func test_kulisse_fuellt_alle_freien_distrikt_tiles() -> void:
	var karte := CityMap.laden()
	var plaene := CityKulisse.plaene(karte, karte.deko_seed())
	# Jedes FREIE Distrikt-Tile (gewerbe/zentrum/wohnen/park) muss mindestens
	# eine Platzierung in Tile-Nähe bekommen — DAS war die „leere Stadt".
	# Orte-/Deko-/Zuhause-Tiles tragen bereits „echte" Gebäude (CityScene
	# baut sie separat) — die Kulisse füllt exakt den Rest.
	var belegt := {}
	for eintrag in plaene:
		var tile := karte.welt_zu_tile(eintrag["pos"])
		belegt[tile] = true
	var schon_bebaut := CityKulisse._belegte_tiles(karte)
	var offen: Array[String] = []
	for r in karte.reihen:
		for c in karte.spalten:
			var tile := Vector2i(r, c)
			if karte.ist_strasse(tile) or schon_bebaut.has(tile):
				continue
			if karte.distrikt_von(tile).is_empty():
				continue
			if not belegt.has(tile):
				offen.append(str(tile))
	assert_true(offen.is_empty(), "leere Distrikt-Tiles: %s" % ", ".join(offen))


func test_kulisse_hat_alle_kategorien() -> void:
	var karte := CityMap.laden()
	var plaene := CityKulisse.plaene(karte, karte.deko_seed())
	var kategorien := {}
	for eintrag in plaene:
		kategorien[str(eintrag.get("kategorie", ""))] = (
			int(kategorien.get(str(eintrag.get("kategorie", "")), 0)) + 1
		)
	for muss: String in ["gebaeude", "haus", "moebel", "gruen", "parkauto", "zaun"]:
		assert_true(int(kategorien.get(muss, 0)) > 0, "Kategorie fehlt: %s" % muss)
	assert_true(int(kategorien.get("parkauto", 0)) >= 8, "genug Bordstein-Parker")
	# Die Karte hat 13 freie Gewerbe/Zentrums-Tiles (der Rest trägt Orte
	# und Karten-Deko-Gebäude) — die Kulisse muss sie ALLE bebauen.
	assert_true(int(kategorien.get("gebaeude", 0)) >= 12, "genug Häuserzeilen")


func test_kulisse_bleibt_auf_der_karte_und_weg_von_strassenmitte() -> void:
	var karte := CityMap.laden()
	var halb := karte.welt_halb()
	for eintrag in CityKulisse.plaene(karte, 7):
		var pos: Vector3 = eintrag["pos"]
		assert_true(absf(pos.x) <= halb.x + 10.0, "%s: x auf der Karte" % eintrag["glb"])
		assert_true(absf(pos.z) <= halb.y + 10.0, "%s: z auf der Karte" % eintrag["glb"])
		# Gebäude/Häuser stehen NIE auf einem Straßen-Tile.
		var kategorie := str(eintrag.get("kategorie", ""))
		if kategorie == "gebaeude" or kategorie == "haus":
			var tile := karte.welt_zu_tile(pos)
			assert_false(karte.ist_strasse(tile), "%s steht auf Straße %s" % [eintrag["glb"], tile])


func test_draw_call_budget_wird_eingehalten() -> void:
	var karte := CityMap.laden()
	var plaene := CityKulisse.plaene(karte, karte.deko_seed())
	var schaetzung := CityKulisse.draw_call_schaetzung(plaene)
	assert_true(
		schaetzung <= CityKulisse.DRAW_CALL_BUDGET,
		"Draw-Call-Schätzung %d über Budget %d" % [schaetzung, CityKulisse.DRAW_CALL_BUDGET]
	)
	# Die Gruppierung muss WIRKLICH bündeln: deutlich weniger Gruppen als
	# Platzierungen, sonst ist das MultiMesh-Versprechen gebrochen.
	var gruppen := CityKulisse.gruppen(plaene)
	assert_true(
		gruppen.size() * 3 < plaene.size(),
		"%d Gruppen für %d Platzierungen" % [gruppen.size(), plaene.size()]
	)
	for key: String in gruppen:
		var transforms: Array = gruppen[key]["transforms"]
		assert_true(transforms.size() > 0, "leere Gruppe %s" % key)


func test_fenster_leuchten_an_den_fassaden() -> void:
	var gebaeude: Array[Dictionary] = [
		{"pos": Vector3(0, 0.05, 0), "rot_grad": 0.0, "scale": 10.0},
		{"pos": Vector3(40, 0.05, 20), "rot_grad": 90.0, "scale": 7.0},
	]
	var a := CityKulisse.fenster_transforms(gebaeude, 1)
	var b := CityKulisse.fenster_transforms(gebaeude, 1)
	assert_true(a.size() >= 2, "es leuchten Fenster (%d)" % a.size())
	assert_eq(a.size(), b.size(), "deterministisch bei gleichem Seed")
	for xform in a:
		var lokal_ok := false
		for haus in gebaeude:
			var abstand: float = (xform.origin - haus["pos"]).length()
			if abstand <= float(haus["scale"]) * 0.9:
				lokal_ok = true
		assert_true(lokal_ok, "Fenster klebt an einer Fassade: %s" % xform.origin)
	assert_eq(
		CityKulisse.fenster_transforms([] as Array[Dictionary], 1).size(),
		0,
		"ohne Gebäude keine Fenster"
	)


func test_hausausfahrt_liegt_zwischen_haus_und_strasse() -> void:
	var karte := CityMap.laden()
	var einfahrt := karte.zuhause_einfahrt()
	var strasse: Vector3 = einfahrt["strasse_pos"]
	var haus := karte.tile_zu_welt(karte.zuhause_tile())
	var pos: Vector3 = einfahrt["pos"]
	var d_strasse := Vector2(pos.x, pos.z).distance_to(Vector2(strasse.x, strasse.z))
	var d_haus := Vector2(pos.x, pos.z).distance_to(Vector2(haus.x, haus.z))
	assert_true(d_strasse > 6.0, "Einfahrt liegt NICHT auf der Fahrbahn (%f m)" % d_strasse)
	assert_true(d_haus < 20.0, "Einfahrt gehört zum Haus (%f m)" % d_haus)
	assert_false(
		karte.ist_strasse(karte.welt_zu_tile(pos)), "Einfahrt-Position ist kein Straßen-Tile"
	)
	# Geparkt wird mit der Nase ZUM Haus (Rückwärts-Ausparken, Haus im Blick).
	var blick := Vector3(sin(float(einfahrt["heading"])), 0.0, cos(float(einfahrt["heading"])))
	assert_true(blick.dot(einfahrt["richtung_haus"]) > 0.9, "geparkte Blickrichtung zeigt zum Haus")
	# Der Kulissen-Plan enthält die sichtbare Einfahrt-Platte.
	var gefunden := false
	for eintrag in CityKulisse.plaene(karte, 1):
		if str(eintrag["glb"]).find("driveway") >= 0:
			gefunden = true
			var d: float = (Vector3(eintrag["pos"]) - pos).length()
			assert_true(d < 8.0, "Einfahrt-Platte liegt unterm Auto (%f m)" % d)
	assert_true(gefunden, "Einfahrt-Platte im Kulissen-Plan")
