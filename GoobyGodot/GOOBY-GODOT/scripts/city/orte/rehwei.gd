class_name OrtRehwei
extends OrtScene
## REHWEI — Lebensmittelladen (Doc E §2.3): Frau Rehwald an der Kasse,
## Sortiment aus rehwei_sortiment.json. G7-P55 „Läden lebendig“: dazu
## Ambient-Kunden (OrtLeben), Kassen-Verhalten (KassenNpc, piept bei jedem
## Kauf), Tür-Glöckchen und leises Marktgemurmel.
## W18 CC0-Umbau (Integrations-Plan „Quick-Win“): die Kisten-Provisorien
## weichen echten Möbeln — getintete Regal-Wand (Kenney furniture),
## Frischetheken aus Fantasy-Town-Marktständen mit Quaternius-Crop-Auslage,
## Karton-Lagerecke und der Hirsch als Maskottchen (Reh-Wortspiel).
## W19 Welle C (Goo-und-Bye-DLC, Doc §4.2): Händler-Rampe rechts hinten
## neben der Karton-Warenannahme — der sichtbare Anker der
## Großmarkt-Fahrten (s. _baue_rampe).

const INNEN := "res://assets/city/innen"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"
const CC0_STADT := "res://assets/models/cc0/kenney_fantasy_town"
const CC0_CROPS := "res://assets/models/cc0/quaternius_crops"
const CC0_TIERE := "res://assets/models/cc0/quaternius_animals"

## Rohe Footprints (Breite, Tiefe) der Ecke-Ursprung-Möbel laut GLB-AABB.
const GRUND_REGAL := Vector2(0.4, 0.25)
const GRUND_KARTON := Vector2(0.212, 0.212)

## Gooby-Pastell-Palette des Ladens: Regale grün, Theken warm-sand.
const TINT_REGAL := Color("#A9D8B3")
const TINT_THEKE := Color("#F2CE94")

## Marktstand-Skala (Kenney-Stand 0.37 m roh → 0.77 m Theken-Höhe).
const STAND_SKALA := 2.1
## Theken-Oberkante = Stand-Höhe (Crop-Auslage sitzt darauf).
const THEKE_Y := 0.366 * STAND_SKALA

## W19 Welle C — Händler-Rampe (Goo-und-Bye-Großmarkt, §4.2): X-Mitte der
## Rolltor-Ecke, Podest-Höhe, Puls-Takt der Fahrt-Sichtbarkeit (die Fahrt
## ist eine reine Save-Funktion der Uhr — der Puls liest nur ab).
## Rechts hinten statt links: die Kühlschrank-Zeile (x −5.2) verdeckt die
## linke Ecke aus der Ort-Kamera komplett, rechts ist die Warenannahme
## (Karton-Ecke + Hirsch) nachweislich frei im Bild.
const RAMPE_X := 6.3
const RAMPE_PODEST_Y := 0.35
const RAMPE_PULS_SEC := 2.0
const TINT_ROLLTOR := Color("#B9C4CE")
const TINT_LAMELLE := Color("#97A4B0")

## Fahrt-Requisiten (Lieferwagen + Kisten) — nur sichtbar, wenn gerade
## eine Goo-und-Bye-Großmarkt-Fahrt läuft (Test-Hook: rampe_aktualisieren).
var rampen_fahrt: Node3D


func _baue_innenraum() -> void:
	# KayKit-Bestand bleibt: Kasse, Kühltheken, Tafel, Gläser (~2-m-Basen,
	# Skalen klein halten). Kisten-Provisorien: s. W18-Blöcke darunter.
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-0.2, 0.0, -1.2), 90.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(2.2, 0.0, -3.4), 0.0, 1.6)
	_prop("%s/fridge_A.gltf" % INNEN, Vector3(-5.2, 0.0, -3.2), 0.0, 0.9)
	_prop("%s/fridge_A.gltf" % INNEN, Vector3(-5.2, 0.0, -0.9), 0.0, 0.9)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-0.2, 0.85, -0.6), 15.0, 0.5)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-0.15, 0.85, -1.8), -30.0, 0.5)
	# W18: Regal-Wand hinter der Kasse — zwei getintete bookcase-Paare
	# flankieren Frau Rehwald (Wand bei z = −4, Korpus-Tiefe 0.43).
	for x: float in [-2.8, -2.05, 0.9, 1.65]:
		var regal := _cc0(
			"%s/bookcase_closed.glb" % CC0_MOEBEL, Vector3(x, 0.0, -3.6), 0.0, 1.7, GRUND_REGAL
		)
		OrtRequisiten.tinte(regal, TINT_REGAL, 0.45)
	# W18: Frischetheken — Fantasy-Town-Stände quer, Auslage obenauf.
	# Positionen halten die Ambient-Wegpunkte (s. _leben_konfig) frei.
	var stand_links := _prop(
		"%s/stall.glb" % CC0_STADT, Vector3(-3.2, 0.0, -1.5), 90.0, STAND_SKALA
	)
	OrtRequisiten.tinte(stand_links, TINT_THEKE, 0.4)
	var stand_rechts := _prop(
		"%s/stall.glb" % CC0_STADT, Vector3(3.4, 0.0, -1.4), 90.0, STAND_SKALA
	)
	OrtRequisiten.tinte(stand_rechts, TINT_THEKE, 0.4)
	_baue_auslage()
	# W18: Karton-Lagerecke rechts hinten (Warenannahme).
	_cc0(
		"%s/cardboard_box_closed.glb" % CC0_MOEBEL, Vector3(4.6, 0.0, -3.5), 8.0, 1.9, GRUND_KARTON
	)
	_cc0(
		"%s/cardboard_box_closed.glb" % CC0_MOEBEL,
		Vector3(4.65, 0.534, -3.45),
		36.0,
		1.9,
		GRUND_KARTON
	)
	_cc0(
		"%s/cardboard_box_open.glb" % CC0_MOEBEL, Vector3(5.35, 0.0, -3.1), -18.0, 1.9, GRUND_KARTON
	)
	# W18: Maskottchen-Spot — der große Bruder von reh_gooby (Wortspiel!),
	# Quaternius-Tiere sind riesig (5.4 m roh) → Skala 0.24, Idle-Loop.
	var hirsch := _prop("%s/stag.glb" % CC0_TIERE, Vector3(5.7, 0.0, -2.6), -35.0, 0.24)
	OrtRequisiten.pastellisiere(hirsch)
	OrtRequisiten.spiele_idle(hirsch)
	# W19 Welle C: Händler-Rampe rechts hinten (Goo-und-Bye-Anker, §4.2).
	_baue_rampe()


## W19 Welle C (Goo-und-Bye-DLC, §4.2): Rolltor-Ecke mit Laderampe rechts
## hinten NEBEN der W18-Karton-Lagerecke — REHWEIs Warenannahme ist IMMER
## da (baulicher Anker); der „Goo und Bye“-Lieferwagen samt Kisten steht
## NUR dort, wenn gerade eine Großmarkt-Fahrt läuft (GoobyeTransport-
## Zeitmodell, reine Save-Funktion — ein 2-s-Puls liest die Sichtbarkeit
## nur ab, kein eigener Zustand). Alle Positionen halten die Sichtlinie
## zum Hirsch-Maskottchen und die Ambient-Wegpunkte (_leben_konfig) frei.
func _baue_rampe() -> void:
	# Rolltor an der Rückwand (Panel + 4 Lamellen-Fugen), auf Podest-Höhe.
	var tor := _rampen_block(
		Vector3(1.3, 1.6, 0.08), Vector3(RAMPE_X, RAMPE_PODEST_Y + 0.8, -3.8), TINT_ROLLTOR
	)
	tor.name = "RampenTor"
	for stufe in 4:
		_rampen_block(
			Vector3(1.3, 0.05, 0.02),
			Vector3(RAMPE_X, RAMPE_PODEST_Y + 0.35 + stufe * 0.3, -3.75),
			TINT_LAMELLE
		)
	# Laderampe: Podest an der Wand + flache Auffahrt Richtung Ladenboden.
	_rampen_block(
		Vector3(1.4, RAMPE_PODEST_Y, 1.1),
		Vector3(RAMPE_X, RAMPE_PODEST_Y / 2.0, -3.4),
		TINT_LAMELLE
	)
	var auffahrt := _rampen_block(
		Vector3(1.4, 0.05, 1.15), Vector3(RAMPE_X, 0.16, -2.3), TINT_ROLLTOR
	)
	auffahrt.rotation_degrees.x = 17.0
	# Fahrt-Requisiten: Lieferwagen quer vor der Rampe + Kisten-Trio.
	rampen_fahrt = Node3D.new()
	rampen_fahrt.name = "RampenFahrt"
	add_child(rampen_fahrt)
	var van := GoobyeLadenBausteine.lieferwagen_modell(0.85)
	van.position = Vector3(5.95, 0.0, -1.65)
	van.rotation.y = -PI / 2.0
	rampen_fahrt.add_child(van)
	_rampen_kiste(
		"%s/cardboard_box_closed.glb" % CC0_MOEBEL, Vector3(6.0, RAMPE_PODEST_Y, -3.35), 12.0
	)
	_rampen_kiste("%s/cardboard_box_closed.glb" % CC0_MOEBEL, Vector3(5.15, 0.0, -2.45), -24.0)
	_rampen_kiste("%s/cardboard_box_open.glb" % CC0_MOEBEL, Vector3(5.3, 0.0, -1.15), 40.0)
	rampe_aktualisieren()
	var puls := Timer.new()
	puls.name = "RampenPuls"
	puls.wait_time = RAMPE_PULS_SEC
	puls.autostart = true
	puls.timeout.connect(rampe_aktualisieren)
	add_child(puls)


## Fahrt-Sichtbarkeit nachziehen (öffentlich: Tests/Flows rufen direkt).
func rampe_aktualisieren() -> void:
	if rampen_fahrt == null:
		return
	rampen_fahrt.visible = not GoobyeTransport.unterwegs_von(game_state()).is_empty()


func _rampen_block(groesse: Vector3, pos: Vector3, farbe: Color) -> MeshInstance3D:
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mesh.material = mat
	block.mesh = mesh
	block.position = pos
	add_child(block)
	return block


## Karton in den Fahrt-Container (Kenney-Ecke-Ursprung → Versatz wie _cc0).
func _rampen_kiste(pfad: String, mitte: Vector3, rot_grad: float) -> void:
	if not ResourceLoader.exists(pfad):
		return
	var szene: PackedScene = load(pfad)
	if szene == null:
		return
	var kiste: Node3D = szene.instantiate()
	kiste.position = mitte + OrtRequisiten.ecken_versatz(rot_grad, 1.9, GRUND_KARTON)
	kiste.rotation_degrees.y = rot_grad
	kiste.scale = Vector3.ONE * 1.9
	rampen_fahrt.add_child(kiste)


## Crop-Auslage auf den Frischetheken (Quaternius, XZ-zentrierte Ursprünge;
## einige Modelle ragen unter y = 0 → Ablage-Höhe kompensiert min-Y).
func _baue_auslage() -> void:
	# Gemüse-Theke links (Theken-Fläche x −4.25..−2.15, z −2.19..−0.82).
	_auslage("%s/lettuce_crop.glb" % CC0_CROPS, Vector3(-3.9, THEKE_Y + 0.02, -1.75), 10.0, 0.9)
	_auslage("%s/lettuce_crop.glb" % CC0_CROPS, Vector3(-3.75, THEKE_Y + 0.02, -1.15), -35.0, 0.9)
	_auslage("%s/carrot_1.glb" % CC0_CROPS, Vector3(-3.05, THEKE_Y, -1.7), 55.0, 1.1)
	_auslage("%s/tomato_1.glb" % CC0_CROPS, Vector3(-2.7, THEKE_Y, -1.1), 0.0, 1.6)
	_auslage("%s/tomato_1.glb" % CC0_CROPS, Vector3(-2.55, THEKE_Y, -1.4), 80.0, 1.6)
	_auslage(
		"%s/pumpkin_harvested.glb" % CC0_CROPS, Vector3(-3.45, THEKE_Y + 0.03, -1.45), 20.0, 0.5
	)
	# Obst-Theke rechts (x 2.35..4.45).
	_auslage(
		"%s/watermelon_harvested.glb" % CC0_CROPS, Vector3(2.9, THEKE_Y + 0.12, -1.6), 20.0, 0.55
	)
	_auslage("%s/apple_crop.glb" % CC0_CROPS, Vector3(3.6, THEKE_Y + 0.12, -1.2), 0.0, 1.5)
	_auslage("%s/apple_crop.glb" % CC0_CROPS, Vector3(3.85, THEKE_Y + 0.12, -1.7), 140.0, 1.5)
	_auslage("%s/corn_2.glb" % CC0_CROPS, Vector3(4.15, THEKE_Y, -1.15), -15.0, 0.8)


func _auslage(pfad: String, pos: Vector3, rot_grad: float, groesse: float) -> void:
	OrtRequisiten.pastellisiere(_prop(pfad, pos, rot_grad, groesse))


## W13B (Doc F §3.2): REHWEI führt neben den Lebensmitteln auch die
## Geschichten-Bücher — gleiche HaendlerSheet-UI, plus Bücher-Abschnitt
## (gekaufte Bücher stehen ausgegraut „im Regal“). W15/CROPS: dazu der
## Saatgut-Abschnitt für die vier neuen Garten-Crops (Muster Bücher).
func oeffne_laden() -> void:
	var inhalt := HaendlerSheet.new()
	inhalt.gs = game_state()
	inhalt.waren = CitySortiment.laden(_sortiment_pfad())
	inhalt.saatgut = CitySortiment.saatgut(_sortiment_pfad())
	inhalt.buecher = CitySortiment.buecher(_sortiment_pfad())
	# G7-P55: jeder Kauf piept an der Kasse — Frau Rehwald kassiert sichtbar.
	inhalt.gekauft.connect(_on_leben_kunde_zahlt)
	zeige_sheet(I18nService.t("city.laden.titel"), inhalt)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/rehwei.json"


func _sortiment_pfad() -> String:
	return CitySortiment.REHWEI_PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#F2B5D4"), "emotion": "happy", "pos": Vector3(-0.2, 0.0, -2.2)}


## G7-P55: Ambient-Leben — 3 Kunden schlendern zwischen Kisten und
## Kühltheke, Frau Rehwald bekommt das Kassen-Verhalten, dazu Glöckchen
## beim Betreten und leises Marktgemurmel.
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		"punkte":
		[
			Vector3(-3.4, 0.0, -0.6),
			Vector3(-1.6, 0.0, 1.2),
			Vector3(3.0, 0.0, -0.5),
			Vector3(1.4, 0.0, 1.6),
			Vector3(-4.8, 0.0, -2.0),
		],
		"sprueche": "laden",
		"blick": Vector3(0.0, 0.0, -4.0),
		"gemurmel": true,
		"tuer_glocke": true,
		"kasse": true,
	}
