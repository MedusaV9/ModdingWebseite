class_name GoobyeLadenDeko
extends RefCounted
## „Goo und Bye“-Raum-Polish (G8-PT2 Spielgefühl-Befund: karger Laden —
## weiße Wände, keine Deko, Tür halb aus dem Bild/B12): EIN statischer
## Deko-Baustein für GoobyeLadenScene. Er baut Seitenwände samt OFFENER
## Ladentür (die Öffnung liegt um GoobyeLadenScene.TUER_POS.z zentriert —
## Kunden spawnen DRAUSSEN und laufen sichtbar durch die Tür ein),
## Regalzeilen an der Rückwand (bestückt), Kühl-Säule, Kisten-Ecke,
## Kassen-Deko, Pflanzen, Oberlichter, Straßen-Vignette vor der Tür und
## den „Goo und Bye“-Schriftzug (Label3D, Muster OrtGoobyman).
##
## Nur STATISCHE MeshInstance3D/GLB-Instanzen — keine Skripte, keine
## Physik, kein pro-Frame-Code (Performance-Regel der Ort-Dioramen).
## ASSET-SOURCE (W17-Import): CC0-Modelle aus assets/city/innen,
## assets/city/innen2, assets/city/essen und assets/city/strassenmoebel —
## Quellen/Lizenzen in docs/godot-rewrite/ASSET-CREDITS.md.

const INNEN := "res://assets/city/innen"
const INNEN2 := "res://assets/city/innen2"
const ESSEN := "res://assets/city/essen"
const STRASSE := "res://assets/city/strassenmoebel"

## Tür-Ausschnitt in der rechten Wand (Weltkoordinaten, Meter). WICHTIG:
## Der Kunden-Laufweg (TUER_POS → REGAL_STOP, z ≈ 0,2) muss DURCH die
## Öffnung führen — TUER_Z_HINTEN < TUER_POS.z < TUER_Z_VORN.
const WAND_X := 4.7
const TUER_Z_HINTEN := -0.6
const TUER_Z_VORN := 1.0
const TUER_HOEHE := 2.3
const WAND_HOEHE := 5.0
const WAND_DICKE := 0.3

const WAND_FARBE := Color(0.96, 0.90, 0.80)
const RAHMEN_FARBE := Color(0.55, 0.38, 0.24)
const GEHWEG_FARBE := Color(0.62, 0.63, 0.66)
const MATTE_FARBE := Color(0.60, 0.44, 0.30)
const TEPPICH_FARBE := Color(0.65, 0.82, 0.80)
const FENSTER_FARBE := Color(0.66, 0.84, 0.97)


## Einstieg: den kompletten Deko-Satz unter `raum` hängen.
static func ausstatten(raum: Node3D) -> void:
	_waende_und_tuer(raum)
	_rueckwand_regale(raum)
	_kisten_ecke(raum)
	_kassen_deko(raum)
	_pflanzen(raum)
	_aussen_vignette(raum)
	_oberlichter(raum)
	_schriftzug(raum)


## ------------------------------------------------------------ Wände & Tür


## Rechte Wand mit Tür-Ausschnitt (B12: Öffnung + Rahmen liegen KOMPLETT
## im 75°-Kamerakegel des Leitformats) plus linke Abschlusswand.
static func _waende_und_tuer(raum: Node3D) -> void:
	var mitte_z := (TUER_Z_HINTEN + TUER_Z_VORN) / 2.0
	var breite := TUER_Z_VORN - TUER_Z_HINTEN
	# Wand-Segmente: hinter der Tür, vor der Tür, Sturz über der Tür.
	_box(
		raum,
		Vector3(WAND_DICKE, WAND_HOEHE, 3.55),
		Vector3(WAND_X, WAND_HOEHE / 2.0, -2.375),
		WAND_FARBE
	)
	_box(
		raum,
		Vector3(WAND_DICKE, WAND_HOEHE, 3.6),
		Vector3(WAND_X, WAND_HOEHE / 2.0, 2.8),
		WAND_FARBE
	)
	_box(
		raum,
		Vector3(WAND_DICKE, WAND_HOEHE - TUER_HOEHE, breite),
		Vector3(WAND_X, TUER_HOEHE + (WAND_HOEHE - TUER_HOEHE) / 2.0, mitte_z),
		WAND_FARBE
	)
	_box(
		raum,
		Vector3(WAND_DICKE, WAND_HOEHE, 6.2),
		Vector3(-6.85, WAND_HOEHE / 2.0, -0.9),
		WAND_FARBE
	)
	# Holz-Rahmen: zwei Pfosten + Querbalken um die Öffnung.
	for pfosten_z in [TUER_Z_HINTEN + 0.07, TUER_Z_VORN - 0.07]:
		_box(
			raum,
			Vector3(0.36, TUER_HOEHE + 0.04, 0.14),
			Vector3(WAND_X, (TUER_HOEHE + 0.04) / 2.0, float(pfosten_z)),
			RAHMEN_FARBE
		)
	_box(
		raum, Vector3(0.36, 0.14, breite), Vector3(WAND_X, TUER_HOEHE + 0.07, mitte_z), RAHMEN_FARBE
	)
	_tuerblatt(raum)
	# Fußmatte innen — hier landet der Kundenstrom im Bild.
	_box(raum, Vector3(1.0, 0.03, 1.5), Vector3(4.15, 0.015, mitte_z), MATTE_FARBE)


## Offenes Türblatt in Gooby-Teal: am hinteren Pfosten angeschlagen und
## weit in den Laden geschwenkt (−125°) — es kreuzt den Kunden-Laufweg
## (z ≈ 0,2) NICHT und bleibt sichtbar im Kamerakegel.
static func _tuerblatt(raum: Node3D) -> void:
	var angel := Node3D.new()
	angel.name = "TuerAngel"
	angel.position = Vector3(WAND_X - 0.17, 0.0, TUER_Z_HINTEN + 0.14)
	angel.rotation_degrees.y = -125.0
	raum.add_child(angel)
	var blatt := MeshInstance3D.new()
	var blatt_mesh := BoxMesh.new()
	blatt_mesh.size = Vector3(0.07, TUER_HOEHE - 0.15, 1.32)
	var blatt_mat := StandardMaterial3D.new()
	blatt_mat.albedo_color = AcTokens.TEAL
	blatt_mesh.material = blatt_mat
	blatt.mesh = blatt_mesh
	blatt.position = Vector3(0.0, (TUER_HOEHE - 0.15) / 2.0, 0.66)
	angel.add_child(blatt)
	var griff := MeshInstance3D.new()
	var griff_mesh := BoxMesh.new()
	griff_mesh.size = Vector3(0.05, 0.34, 0.06)
	var griff_mat := StandardMaterial3D.new()
	griff_mat.albedo_color = AcTokens.TEAL_DARK
	griff_mesh.material = griff_mat
	griff.mesh = griff_mesh
	griff.position = Vector3(-0.06, 1.05, 1.18)
	angel.add_child(griff)


## ------------------------------------------------------- Rückwand-Regale


## Regalzeile an der Rückwand (Lücke fürs Spieler-Regal bleibt frei) +
## Kühl-Säule rechts. Brett-Oberkanten regal_gross: 0,30/0,58/0,87/1,15 m
## (gemessen, s. rehwei.gd) — ein paar Essen-Props füllen die Böden.
static func _rueckwand_regale(raum: Node3D) -> void:
	_prop(raum, "%s/regal_gross.glb" % INNEN2, Vector3(0.0, 0.0, -3.6), 0.0, 1.0)
	_prop(raum, "%s/regal_hoch.glb" % INNEN2, Vector3(-1.2, 0.0, -3.62), 0.0, 1.0)
	_prop(raum, "%s/regal_offen.glb" % INNEN2, Vector3(1.2, 0.0, -3.62), 0.0, 1.0)
	_prop(raum, "%s/shelf_papertowel_decorated.gltf" % INNEN2, Vector3(2.4, 2.2, -3.85), 0.0, 0.8)
	_prop(raum, "%s/kuehlschrank_hoch.glb" % INNEN2, Vector3(4.15, 0.0, -3.5), 0.0, 1.0)
	_prop(raum, "%s/apple.glb" % ESSEN, Vector3(-0.3, 0.87, -3.56), 0.0, 1.0)
	_prop(raum, "%s/bread.glb" % ESSEN, Vector3(0.28, 0.87, -3.56), 15.0, 1.0)
	_prop(raum, "%s/grapes.glb" % ESSEN, Vector3(-0.28, 0.58, -3.56), 10.0, 1.0)
	_prop(raum, "%s/cheese.glb" % ESSEN, Vector3(0.3, 0.58, -3.56), -20.0, 1.0)
	_prop(raum, "%s/chocolate.glb" % ESSEN, Vector3(-0.35, 1.15, -3.56), 14.0, 1.0)
	_prop(raum, "%s/cookie.glb" % ESSEN, Vector3(0.1, 1.15, -3.56), -8.0, 1.0)


## --------------------------------------------------------- Boden-Gruppen


## Kisten-Ecke links: neue W17-Kisten ergänzen die zwei Bestands-Kisten
## der Szene — eine Kiste GESTAPELT (Deckel-Oberkante ≈ 0,6 m bei 0,65).
static func _kisten_ecke(raum: Node3D) -> void:
	_prop(raum, "%s/crate_lettuce.gltf" % INNEN2, Vector3(-5.3, 0.0, -1.0), 20.0, 0.65)
	_prop(raum, "%s/crate_potatoes.gltf" % INNEN2, Vector3(-3.95, 0.6, -0.05), 28.0, 0.65)
	_prop(raum, "%s/crate_onions.gltf" % INNEN2, Vector3(-5.5, 0.0, 1.3), -18.0, 0.65)


## Kassen-Bereich: Mülleimer neben der Theke, Vorratsgläser AUF der Theke
## (Oberkante ≈ 0,85 m, s. rehwei.gd) und ein Teppich am Kassen-Stop.
static func _kassen_deko(raum: Node3D) -> void:
	_prop(raum, "%s/muelleimer_gruen.glb" % INNEN2, Vector3(3.2, 0.0, -1.6), -20.0, 1.0)
	_prop(raum, "%s/jar_A_large.gltf" % INNEN, Vector3(1.45, 0.85, -0.8), 15.0, 0.5)
	_prop(raum, "%s/jar_A_large.gltf" % INNEN, Vector3(2.4, 0.85, -1.7), -30.0, 0.5)
	_box(raum, Vector3(1.7, 0.02, 1.1), Vector3(1.9, 0.01, 0.35), TEPPICH_FARBE)


## Gruß-Pflanze an der Tür (rehwei-Muster) + breite Pflanze am Regal.
static func _pflanzen(raum: Node3D) -> void:
	_prop(raum, "%s/pflanze_laden_gross.glb" % INNEN2, Vector3(4.25, 0.0, -1.4), 0.0, 1.0)
	_prop(raum, "%s/pflanze_laden_klein.glb" % INNEN2, Vector3(-3.15, 0.0, -0.55), 35.0, 1.0)


## Straßen-Vignette VOR der offenen Tür (Blick durch die Öffnung):
## Gehweg-Platte, Laternen-Mast und Busch — verkauft den Kundeneinlauf
## von draußen (B12), alles hinter der Wand außer Sichtachse Tür.
static func _aussen_vignette(raum: Node3D) -> void:
	var mitte_z := (TUER_Z_HINTEN + TUER_Z_VORN) / 2.0
	_box(raum, Vector3(2.6, 0.04, 4.4), Vector3(6.05, 0.02, mitte_z), GEHWEG_FARBE)
	_prop(raum, "%s/laterne_einzel.glb" % STRASSE, Vector3(5.6, 0.0, -0.3), 0.0, 1.0)
	_prop(raum, "%s/bush.gltf" % STRASSE, Vector3(5.35, 0.0, -0.75), 0.0, 2.4)


## ------------------------------------------------------ Wand-Feinschliff


## Zwei „Oberlichter“ hoch an der Rückwand: Holzrahmen + Sprosse + leicht
## leuchtendes Himmels-Glas — Tageslicht-Gefühl ohne echtes Licht.
static func _oberlichter(raum: Node3D) -> void:
	for fenster_x: float in [-4.2, 4.2]:
		_box(raum, Vector3(1.7, 1.1, 0.06), Vector3(fenster_x, 3.3, -3.84), RAHMEN_FARBE)
		var glas := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.52, 0.92, 0.08)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FENSTER_FARBE
		mat.emission_enabled = true
		mat.emission = FENSTER_FARBE
		mat.emission_energy_multiplier = 0.9
		mesh.material = mat
		glas.mesh = mesh
		glas.position = Vector3(fenster_x, 3.3, -3.81)
		raum.add_child(glas)
		_box(raum, Vector3(0.06, 0.92, 0.1), Vector3(fenster_x, 3.3, -3.8), RAHMEN_FARBE)


## „Goo und Bye“-Schriftzug über den Regalen (Label3D statt Bild-Asset,
## Muster OrtGoobyman._baue_schriftzug) — i18n-Titel, Teal auf Tinte.
static func _schriftzug(raum: Node3D) -> void:
	var schild := Label3D.new()
	schild.name = "LadenSchild"
	schild.text = I18nService.t("dlc_goobye.laden.titel")
	schild.font_size = 110
	schild.pixel_size = 0.008
	schild.modulate = AcTokens.TEAL
	schild.outline_size = 24
	schild.outline_modulate = AcTokens.INK
	schild.position = Vector3(0.0, 3.35, -3.8)
	raum.add_child(schild)


## ---------------------------------------------------------------- Helfer


## GLB/GLTF-Requisite (Ort-Muster: still bei Fehlpfad, statische Instanz).
static func _prop(
	raum: Node3D, pfad: String, pos: Vector3, rot_grad: float, groesse: float
) -> void:
	if not ResourceLoader.exists(pfad):
		return
	var szene: PackedScene = load(pfad)
	if szene == null:
		return
	var node: Node3D = szene.instantiate()
	node.position = pos
	node.rotation_degrees.y = rot_grad
	node.scale = Vector3.ONE * groesse
	raum.add_child(node)


## Einfarbige Box (Wände, Rahmen, Matten) — EIN Mesh, EIN Material.
static func _box(raum: Node3D, groesse: Vector3, pos: Vector3, farbe: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	raum.add_child(mi)
