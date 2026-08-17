extends TestCase
## FB-2 — Draw-Call-Budget (≤ 400 je Ansicht): die neuen Szenerie-Systeme
## (Streu, Stadt-Grün, Fernsicht) bleiben in den gemessenen Budgets.
## Heuristik-Zahlen (Sockel je Ansicht) kommen aus den xvfb-Messläufen;
## der echte Nachweis sind die Draw-Call-Zahlen im Screenshot-Lauf.


func test_ranch_streu_bleibt_im_budget() -> void:
	var plaene := RanchStreu.plaene(1.0)
	var schaetzung := RanchStreu.draw_call_schaetzung(plaene)
	assert_true(
		schaetzung <= RanchStreu.DRAW_CALL_BUDGET,
		"Ranch-Ansicht: %d <= %d" % [schaetzung, RanchStreu.DRAW_CALL_BUDGET]
	)


func test_stadt_kulisse_plus_gruen_bleibt_im_budget() -> void:
	var karte := CityMap.laden()
	var plaene := CityKulisse.plaene(karte, karte.deko_seed())
	var nur_kulisse := CityKulisse.gruppen(plaene).size()
	plaene.append_array(CityGruen.plaene(karte, karte.deko_seed() + 917))
	var schaetzung := CityKulisse.draw_call_schaetzung(plaene)
	assert_true(
		schaetzung <= CityKulisse.DRAW_CALL_BUDGET,
		"Stadt-Ansicht: %d <= %d" % [schaetzung, CityKulisse.DRAW_CALL_BUDGET]
	)
	# Das Grün teilt sich die MultiMesh-Gruppen mit der Kulisse: nur ganz
	# wenige NEUE Mesh-Sorten (= zusätzliche Draw-Calls) sind erlaubt.
	var mit_gruen := CityKulisse.gruppen(plaene).size()
	assert_true(
		mit_gruen - nur_kulisse <= 3,
		"Stadt-Grün kostet kaum neue Gruppen (%d -> %d)" % [nur_kulisse, mit_gruen]
	)


func test_fernsicht_ist_billig() -> void:
	# Drei Berg-Ringe + Fernwiese = 4 unshaded Meshes ohne Schatten.
	var fernsicht := WeltFernsicht.new()
	fernsicht.einrichten(1)
	assert_eq(fernsicht.get_child_count(), WeltFernsicht.RINGE.size() + 1, "4 Draw-Calls gesamt")
	for kind in fernsicht.get_children():
		var mi := kind as MeshInstance3D
		assert_true(mi != null, "nur MeshInstances")
		assert_eq(
			mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "kein Schatten-Pass"
		)
	fernsicht.free()


func test_streu_kleinteile_tragen_sichtweiten_flag() -> void:
	# Kleinteile (Blumen/Büsche/Gras) müssen als „klein" markiert sein,
	# damit der Bau ihnen die Distanz-Ausblendung (KLEINTEIL_SICHT_M ×
	# Sichtweiten-Faktor) verpasst — Bäume/Großfelsen bleiben immer da.
	var klein := 0
	var gross := 0
	for sorte: Dictionary in RanchStreu.SORTEN:
		if bool(sorte["klein"]):
			klein += 1
		else:
			gross += 1
	assert_true(klein >= 6, "genug Kleinteil-Sorten (%d)" % klein)
	assert_true(gross >= 3, "Bäume/Felsen ohne Distanz-Culling (%d)" % gross)


func test_himmel_kostet_keine_texturen() -> void:
	# Kern der Shader-Entscheidung: der Himmel braucht NULL Texturen —
	# alle Stimmungen sind Uniform-Sätze (Panoramen hätten ~50 MB+ belegt).
	var shader: Shader = load(GoobyHimmel.SHADER_PFAD)
	assert_true(shader != null, "Sky-Shader lädt")
	assert_false(shader.code.contains("sampler2D"), "keine Textur-Uniforms im Sky-Shader")
