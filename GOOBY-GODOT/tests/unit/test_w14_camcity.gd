extends TestCase
## W14/CAMCITY — Decken-Ausblendung der Haussicht + Stadt-Feinschliff.
## (a) Decken-Fade: Schwellen-Mathe pur (Höhe/Winkel→Alpha), CEILING-Item-
## Geister-Regel (Baumodus 30 % / sonst 0 % / Decken-Ebene voll), Reduced-
## Motion springt, DachInnen-Material-Fade, Kamera kollidiert NICHT mit der
## Decke (kein CollisionObject/SpringArm im Dach bzw. Rig).
## (b) Stadt: Fassaden-Nachtint deterministisch + Gruppen-neutral,
## Vorplatz-/Saum-Streu deterministisch und regelkonform (keine Straßen,
## Gebäude-Kerne frei), Laternen-Schein = genau 2 MultiMesh-Draw-Calls.

# ── (a) Decken-Fade: Schwellen-Mathe pur ─────────────────────────────────────


func test_ziel_alpha_normalspiel_bleibt_sichtbar() -> void:
	# Kamera unter der Wandkrone: voll sichtbar, egal wie steil der Blick.
	assert_almost(DeckenFade.ziel_alpha(2.0, 60.0), 1.0, 1e-6, "unter der Decke")
	# Kamera hoch, aber flacher/aufwärts gerichteter Blick: voll sichtbar.
	assert_almost(DeckenFade.ziel_alpha(6.0, 10.0), 1.0, 1e-6, "flacher Blick")
	assert_almost(DeckenFade.ziel_alpha(6.0, -20.0), 1.0, 1e-6, "Blick nach oben")


func test_ziel_alpha_von_oben_blendet_aus() -> void:
	assert_almost(DeckenFade.ziel_alpha(4.5, 45.0), 0.0, 1e-6, "hoch + steil = weg")
	# Im Übergangsband weder 0 noch 1 (sanfter Fade, kein Popping) …
	var mitte := DeckenFade.ziel_alpha(3.45, 30.0)
	assert_true(mitte > 0.01 and mitte < 0.99, "weiches Band (%f)" % mitte)
	# … und monoton: höher/steiler ⇒ durchsichtiger.
	assert_true(
		DeckenFade.ziel_alpha(3.8, 30.0) <= DeckenFade.ziel_alpha(3.2, 30.0), "monoton in Höhe"
	)
	assert_true(
		DeckenFade.ziel_alpha(3.45, 34.0) <= DeckenFade.ziel_alpha(3.45, 26.0), "monoton im Winkel"
	)


func test_ziel_alpha_braucht_beide_bedingungen() -> void:
	# Nur EINE Bedingung erfüllt reicht nicht (min-Verknüpfung).
	assert_almost(DeckenFade.ziel_alpha(9.0, 0.0), 1.0, 1e-6, "hoch allein reicht nicht")
	assert_almost(DeckenFade.ziel_alpha(0.5, 89.0), 1.0, 1e-6, "steil allein reicht nicht")


func test_blick_runter_grad() -> void:
	assert_almost(DeckenFade.blick_runter_grad(Vector3(0, -1, 0)), 90.0, 1e-4, "senkrecht runter")
	assert_almost(DeckenFade.blick_runter_grad(Vector3(0, 0, -1)), 0.0, 1e-4, "waagerecht")
	assert_almost(DeckenFade.blick_runter_grad(Vector3(0, 1, 0)), -90.0, 1e-4, "senkrecht hoch")
	assert_almost(DeckenFade.blick_runter_grad(Vector3(0, -1, 1)), 45.0, 1e-4, "45 Grad runter")
	assert_almost(DeckenFade.blick_runter_grad(Vector3.ZERO), 0.0, 1e-6, "Nullvektor = neutral")


# ── (a) CEILING-Item-Geister-Regel ───────────────────────────────────────────


func test_item_geister_regel_baumodus_30_prozent() -> void:
	# Decke weg + Baumodus: Items bleiben geisterhaft (30 %) sichtbar.
	assert_almost(DeckenFade.item_ziel_alpha(0.0, true, false), DeckenFade.GEIST_ALPHA_BAU)
	# Decke weg + KEIN Baumodus: Items verschwinden ganz.
	assert_almost(DeckenFade.item_ziel_alpha(0.0, false, false), 0.0)
	# Decke voll da: Items voll da (beide Modi).
	assert_almost(DeckenFade.item_ziel_alpha(1.0, true, false), 1.0)
	assert_almost(DeckenFade.item_ziel_alpha(1.0, false, false), 1.0)


func test_item_geister_regel_deckenebene_immer_voll() -> void:
	# Auf der Decken-Bau-Ebene wird an den Items gebaut: immer voll da.
	assert_almost(DeckenFade.item_ziel_alpha(0.0, true, true), 1.0)
	assert_almost(DeckenFade.item_ziel_alpha(0.5, true, true), 1.0)


func test_item_alpha_folgt_der_decke_sanft() -> void:
	# Zwischenwerte interpolieren zwischen Boden (Geist/0) und 1.
	var halb_bau := DeckenFade.item_ziel_alpha(0.5, true, false)
	assert_almost(halb_bau, lerpf(DeckenFade.GEIST_ALPHA_BAU, 1.0, 0.5), 1e-6)
	assert_almost(DeckenFade.item_ziel_alpha(0.5, false, false), 0.5, 1e-6)


# ── (a) Glättung + Reduced Motion ────────────────────────────────────────────


func test_schritt_reduced_motion_springt_sofort() -> void:
	assert_almost(DeckenFade.schritt(1.0, 0.0, 0.016, true), 0.0, 1e-6, "Reduced = Sprung")
	assert_almost(DeckenFade.schritt(0.2, 1.0, 0.016, true), 1.0, 1e-6)


func test_schritt_animiert_und_snappt_am_ziel() -> void:
	var neu := DeckenFade.schritt(1.0, 0.0, 0.016, false)
	assert_true(neu < 1.0 and neu > 0.0, "ein Frame fadet nur teilweise (%f)" % neu)
	# Nah am Ziel schnappt der Wert ein (kein ewiges Kriechen).
	assert_almost(DeckenFade.schritt(0.001, 0.0, 0.016, false), 0.0, 1e-6, "Snap-Fenster")


# ── (a) DachInnen-Material-Fade + Kamera-Kollision ───────────────────────────


func test_dachinnen_fade_macht_material_transparent() -> void:
	var dach := DachInnen.new()
	dach.baue("bedroom", Vector2(6.0, 5.0), {})
	tree.root.add_child(dach)
	await wait_frames(1)
	assert_true(dach.hat_schraege(), "Dachgeschoss hat Schräge")
	assert_almost(dach.fade_alpha(), 1.0, 1e-6, "startet voll sichtbar")
	dach.set_fade_alpha(0.5)
	assert_almost(dach.fade_alpha(), 0.5, 1e-6)
	var geometrie := dach.find_children("*", "GeometryInstance3D", true, false)
	assert_true(geometrie.size() >= 2, "Balken + Schräge vorhanden")
	for kind: Node in geometrie:
		assert_true((kind as GeometryInstance3D).visible, "halb gefadet bleibt sichtbar")
	dach.set_fade_alpha(0.0)
	for kind: Node in geometrie:
		assert_false((kind as GeometryInstance3D).visible, "ganz weg = Geometrie schläft")
	dach.set_fade_alpha(1.0)
	for kind: Node in geometrie:
		assert_true((kind as GeometryInstance3D).visible, "wieder voll da")
	# Das visible-Flag des DachInnen selbst gehört HausKontext — unberührt.
	assert_true(dach.visible, "DachInnen.visible bleibt beim Fade unangetastet")
	dach.queue_free()
	await wait_frames(1)


func test_kamera_kollidiert_nicht_mit_der_decke() -> void:
	# Das Dach hat KEINE Physik-Körper — nichts, worunter die freie
	# Pan-Kamera klemmen könnte …
	var dach := DachInnen.new()
	dach.baue("living", Vector2(6.0, 5.0), {})
	tree.root.add_child(dach)
	await wait_frames(1)
	assert_true(
		dach.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"Decke ohne Kollisions-Körper"
	)
	dach.queue_free()
	# … und das Kamera-Rig fährt ohne SpringArm (keine Kollisions-Maske,
	# die die Decke fangen könnte).
	var rig := HomeCameraRig.new()
	tree.root.add_child(rig)
	await wait_frames(1)
	assert_true(rig.find_children("*", "SpringArm3D", true, false).is_empty(), "Rig ohne SpringArm")
	assert_true(rig.camera is Camera3D, "Rig-Kamera vorhanden")
	rig.queue_free()
	await wait_frames(1)


func test_decken_fade_haengt_idempotent_am_raum() -> void:
	var raum := Node3D.new()
	var dach := Node3D.new()
	tree.root.add_child(raum)
	var erster := DeckenFade.attach_to(raum, dach)
	var zweiter := DeckenFade.attach_to(raum, dach)
	assert_true(erster == zweiter, "attach_to ist idempotent")
	assert_eq(erster.name, "DeckenFade")
	raum.queue_free()
	dach.free()
	await wait_frames(1)


# ── (b) Stadt: Fassaden-Nachtint ─────────────────────────────────────────────


func test_fassaden_tint_deterministisch_und_gruppen_neutral() -> void:
	var a := CityBau.fassaden_tint("gebaeude/building-a.glb", "", "gebaeude")
	var b := CityBau.fassaden_tint("gebaeude/building-a.glb", "", "gebaeude")
	assert_eq(a, b, "gleiche Sorte = gleicher Ton (Gruppen-neutral)")
	assert_true(CityBau.FASSADEN_NACHTINTS.has(a), "Ton aus der Pastell-Palette")
	# Vorhandene Tints bleiben unangetastet.
	assert_eq(CityBau.fassaden_tint("gebaeude/building-a.glb", "#CFD8E3", "gebaeude"), "#CFD8E3")
	# Nicht-Gebäude (Bäume, Möbel, Parker) bleiben tintlos.
	assert_eq(CityBau.fassaden_tint("natur/tree_oak.glb", "", "baum"), "")
	assert_eq(CityBau.fassaden_tint("autos/sedan.glb", "", "parkauto"), "")


func test_fassaden_tint_variiert_zwischen_sorten() -> void:
	var toene := {}
	for glb: String in [
		"gebaeude/building-a.glb",
		"gebaeude/building-b.glb",
		"gebaeude/building-c.glb",
		"gebaeude/building-d.glb",
		"gebaeude/building-e.glb",
		"gebaeude/building-f.glb",
	]:
		toene[CityBau.fassaden_tint(glb, "", "gebaeude")] = true
	assert_true(toene.size() >= 2, "mehrere Pastell-Töne im Einsatz (%d)" % toene.size())


# ── (b) Stadt: Vorplatz-/Saum-Streu ──────────────────────────────────────────


func test_vorplatz_streu_deterministisch_und_regelkonform() -> void:
	var karte := CityMap.laden()
	assert_true(karte.ist_geladen(), "Karte lädt")
	var a := CityGruen.vorplatz_plaene(karte, 4700)
	var b := CityGruen.vorplatz_plaene(karte, 4700)
	assert_true(a.size() > 20, "Vorplätze werden bestreut (%d)" % a.size())
	assert_eq(a.size(), b.size(), "deterministisch bei gleichem Seed")
	for i in mini(a.size(), 5):
		assert_eq(a[i]["pos"], b[i]["pos"], "gleiche Positionen")
	for eintrag: Dictionary in a:
		var pos: Vector3 = eintrag["pos"]
		var tile := karte.welt_zu_tile(pos)
		assert_false(karte.ist_strasse(tile), "%s liegt nie auf der Straße" % eintrag["glb"])
		var mitte := karte.tile_zu_welt(tile)
		assert_true(
			(
				Vector2(mitte.x, mitte.z).distance_to(Vector2(pos.x, pos.z))
				>= CityGruen.VORPLATZ_KERN_FREI_M - 0.01
			),
			"Gebäude-Kern bleibt frei"
		)


func test_saum_streu_deterministisch_und_nie_auf_strassen() -> void:
	var karte := CityMap.laden()
	var a := CityGruen.saum_plaene(karte, 5900)
	var b := CityGruen.saum_plaene(karte, 5900)
	assert_true(a.size() > 20, "Distrikt-Säume werden bestreut (%d)" % a.size())
	assert_eq(a.size(), b.size(), "deterministisch bei gleichem Seed")
	for eintrag: Dictionary in a:
		var tile := karte.welt_zu_tile(eintrag["pos"])
		assert_false(karte.ist_strasse(tile), "%s liegt nie auf der Straße" % eintrag["glb"])


func test_neue_streu_nutzt_nur_bekannte_gruen_sorten() -> void:
	# Draw-Call-Versprechen: die W14-Pools recyceln NUR Sorten, die das
	# Stadt-Grün ohnehin nutzt (test_world_budget wacht über die Gruppen).
	var bekannt := {}
	for sorte: Dictionary in CityGruen.PARK_STREU_POOL:
		bekannt[str(sorte["glb"])] = true
	bekannt["natur/plant_bush.glb"] = true  # Hecken (_plane_hecken_und_kaesten)
	bekannt["natur/flower_purpleA.glb"] = true  # Blumenkästen/BLUMEN_POOL
	for sorte: Dictionary in CityGruen.VORPLATZ_STREU_POOL + CityGruen.SAUM_STREU_POOL:
		assert_true(bekannt.has(str(sorte["glb"])), "%s ist eine Bestands-Sorte" % sorte["glb"])


# ── (b) Stadt: Laternen-Schein ───────────────────────────────────────────────


func test_laternen_schein_sind_genau_zwei_draw_calls() -> void:
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	var posten: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)),
		Transform3D(Basis.IDENTITY, Vector3(20, 0.4, 0)),
		Transform3D(Basis.IDENTITY, Vector3(40, 0.4, 20)),
	]
	CityAmbiente.laternen_schein(wurzel, posten, 5.0)
	assert_eq(wurzel.get_child_count(), 2, "Kegel + Flecken = 2 MultiMeshes")
	for kind: Node in wurzel.get_children():
		var mm := (kind as MultiMeshInstance3D).multimesh
		assert_eq(mm.instance_count, posten.size(), "eine Instanz je Laterne")
		assert_eq(
			(kind as MultiMeshInstance3D).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"Licht wirft keinen Schatten"
		)
	wurzel.queue_free()
	await wait_frames(1)


func test_laternen_schein_ohne_posten_baut_nichts() -> void:
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	CityAmbiente.laternen_schein(wurzel, [] as Array[Transform3D], 5.0)
	assert_eq(wurzel.get_child_count(), 0, "leere Straße = kein Schein")
	wurzel.queue_free()
	await wait_frames(1)
