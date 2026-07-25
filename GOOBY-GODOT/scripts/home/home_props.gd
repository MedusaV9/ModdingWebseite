class_name HomeProps
extends RefCounted
## Prozedurale Haus-/Garten-Props (Doc D §9): Fenster-Modul, Werkbank,
## Shed L1–L3, Werkstatt-Hütte, Gewächshaus, Sprinkler, Sammel-Stock,
## Klemmbrett und Hammer. Alles aus Godot-Primitiven zusammengesetzt — die
## Kenney-Kits liefern diese Teile nicht, und ein Blender-Export wäre für
## solche Kisten-mit-Dach-Formen unnötiger Ballast.
##
## FARBEN: eine EINZIGE Palette hier (aus den AC-Theme-Tokens abgeleitet) —
## kein Prop definiert eigene Farben. UI-Farben kommen weiterhin
## ausschließlich aus dem globalen Theme.

const PALETTE := {
	"holz": Color("#B98D62"),
	"holz_dunkel": Color("#8A6642"),
	"anstrich": AcTokens.PAPER,
	"glas": AcTokens.SKY_SOFT,
	"rahmen": AcTokens.BG_CREAM,
	"metall": AcTokens.INK_SOFT,
	"blatt": AcTokens.LEAF,
	"dach": AcTokens.TEAL,
	"akzent": AcTokens.PINK,
	"gold": AcTokens.GOLD,
}


## Flaches, weiches Material in einer Paletten-Farbe.
static func material(farbe_id: String, alpha := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var farbe: Color = PALETTE.get(farbe_id, AcTokens.PAPER)
	farbe.a = alpha
	mat.albedo_color = farbe
	mat.roughness = 0.9
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


static func box(size: Vector3, farbe_id: String, alpha := 1.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(farbe_id, alpha)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


static func zylinder(radius: float, hoehe: float, farbe_id: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = hoehe
	mesh.mesh = shape
	mesh.material_override = material(farbe_id, 1.0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## Fenster-Modul (Doc D §1.2): Rahmen aus vier Leisten + Glasscheibe.
## `durchsichtig` (Außenfenster) lässt das Straßen-Diorama hinter der Wand
## durchscheinen — der Rahmen ist deshalb bewusst KEINE geschlossene Platte.
static func fenster(breite_zellen: int, durchsichtig := false) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Fenster"
	var breite := breite_zellen * 0.5
	var hoehe := 0.95
	var leiste := 0.06
	for x: float in [-(breite + leiste) * 0.5, (breite + leiste) * 0.5]:
		var pfosten := box(Vector3(leiste, hoehe + leiste * 2.0, 0.07), "rahmen")
		pfosten.position.x = x
		wurzel.add_child(pfosten)
	for y: float in [-(hoehe + leiste) * 0.5, (hoehe + leiste) * 0.5]:
		var riegel := box(Vector3(breite + leiste * 2.0, leiste, 0.07), "rahmen")
		riegel.position.y = y
		wurzel.add_child(riegel)
	var glas := box(Vector3(breite, hoehe, 0.02), "glas", 0.16 if durchsichtig else 1.0)
	glas.name = "Glas"
	glas.position.z = 0.035
	wurzel.add_child(glas)
	var sprosse := box(Vector3(0.04, hoehe, 0.03), "rahmen")
	sprosse.position.z = 0.05
	wurzel.add_child(sprosse)
	var bank := box(Vector3(breite + 0.2, 0.06, 0.14), "rahmen")
	bank.position = Vector3(0.0, -(hoehe + 0.12) * 0.5, 0.05)
	wurzel.add_child(bank)
	return wurzel


## Werkbank (fest verbaut in der Werkstatt).
static func werkbank() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Werkbank"
	var platte := box(Vector3(1.4, 0.1, 0.7), "holz_dunkel")
	platte.position.y = 0.75
	wurzel.add_child(platte)
	for x in [-0.6, 0.6]:
		for z in [-0.26, 0.26]:
			var bein := box(Vector3(0.1, 0.75, 0.1), "holz")
			bein.position = Vector3(x, 0.375, z)
			wurzel.add_child(bein)
	var schraubstock := box(Vector3(0.22, 0.16, 0.2), "metall")
	schraubstock.position = Vector3(0.5, 0.88, 0.0)
	wurzel.add_child(schraubstock)
	return wurzel


## Shed in einer der drei Stufen (Doc D §2.3) — sichtbar größer und schöner.
static func shed(stufe: int) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Shed"
	var modell := ShedLogic.modell(stufe)
	var hoehe := float(modell["hoehe"])
	if hoehe <= 0.0:
		return wurzel
	var breite := 1.8 + 0.2 * stufe
	var farbe := "anstrich" if bool(modell["anstrich"]) else "holz"
	var korpus := box(Vector3(breite, hoehe, breite), farbe)
	korpus.position.y = hoehe * 0.5
	wurzel.add_child(korpus)
	var dach := box(Vector3(breite + 0.25, 0.14, breite + 0.25), "dach")
	dach.position.y = hoehe + 0.07
	wurzel.add_child(dach)
	var tuer_breite := 0.5 if stufe < 3 else 0.9
	var tuer := box(Vector3(tuer_breite, hoehe * 0.7, 0.06), "holz_dunkel")
	tuer.position = Vector3(0.0, hoehe * 0.35, breite * 0.5 + 0.03)
	wurzel.add_child(tuer)
	if bool(modell["fenster"]):
		var luke := box(Vector3(0.35, 0.35, 0.05), "glas")
		luke.position = Vector3(breite * 0.28, hoehe * 0.65, breite * 0.5 + 0.03)
		wurzel.add_child(luke)
		var kasten := box(Vector3(0.45, 0.12, 0.14), "blatt")
		kasten.position = Vector3(breite * 0.28, hoehe * 0.45, breite * 0.5 + 0.08)
		wurzel.add_child(kasten)
	if bool(modell["wetterhahn"]):
		var stange := zylinder(0.02, 0.35, "metall")
		stange.position.y = hoehe + 0.25
		wurzel.add_child(stange)
		var hahn := box(Vector3(0.24, 0.12, 0.02), "gold")
		hahn.position.y = hoehe + 0.42
		wurzel.add_child(hahn)
	return wurzel


## Werkstatt-Hütte (3×2 Garten-Zellen) mit Schornstein — Tap öffnet drinnen
## das Crafting-Panel.
static func werkstatt() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Werkstatt"
	var korpus := box(Vector3(2.8, 2.0, 1.8), "holz")
	korpus.position.y = 1.0
	wurzel.add_child(korpus)
	var dach := box(Vector3(3.1, 0.16, 2.1), "akzent")
	dach.position.y = 2.08
	wurzel.add_child(dach)
	var tuer := box(Vector3(0.7, 1.4, 0.08), "holz_dunkel")
	tuer.position = Vector3(-0.6, 0.7, 0.94)
	wurzel.add_child(tuer)
	var fensterchen := box(Vector3(0.6, 0.5, 0.06), "glas")
	fensterchen.position = Vector3(0.7, 1.25, 0.94)
	wurzel.add_child(fensterchen)
	var schornstein := box(Vector3(0.24, 0.6, 0.24), "holz_dunkel")
	schornstein.position = Vector3(1.0, 2.4, -0.4)
	wurzel.add_child(schornstein)
	var schild := box(Vector3(0.8, 0.3, 0.04), "rahmen")
	schild.position = Vector3(0.0, 1.75, 0.95)
	wurzel.add_child(schild)
	return wurzel


## Gewächshaus (2×3 Zellen, transparentes Dach, Tür-Modul).
static func gewaechshaus(tuer_offset: Vector3) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Gewaechshaus"
	var sockel := box(Vector3(2.0, 0.18, 3.0), "holz_dunkel")
	sockel.position.y = 0.09
	wurzel.add_child(sockel)
	var glas := box(Vector3(1.9, 1.7, 2.9), "glas", 0.35)
	glas.position.y = 1.0
	wurzel.add_child(glas)
	var dach := box(Vector3(2.05, 0.3, 3.05), "glas", 0.45)
	dach.position.y = 1.95
	wurzel.add_child(dach)
	for x in [-0.95, 0.95]:
		for z in [-1.45, 1.45]:
			var pfosten := box(Vector3(0.08, 1.9, 0.08), "anstrich")
			pfosten.position = Vector3(x, 0.95, z)
			wurzel.add_child(pfosten)
	var tuer := box(Vector3(0.7, 1.5, 0.08), "anstrich")
	tuer.position = tuer_offset + Vector3(0.0, 0.75, 0.0)
	wurzel.add_child(tuer)
	return wurzel


## Bewässerungsanlage: Sprinkler-Kopf auf kurzem Rohr (3×3-Reichweite).
static func sprinkler() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Sprinkler"
	var rohr := zylinder(0.05, 0.5, "metall")
	rohr.position.y = 0.25
	wurzel.add_child(rohr)
	var kopf := zylinder(0.12, 0.12, "dach")
	kopf.position.y = 0.55
	wurzel.add_child(kopf)
	for winkel in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var arm := box(Vector3(0.34, 0.03, 0.05), "metall")
		arm.position = Vector3(cos(winkel) * 0.17, 0.6, sin(winkel) * 0.17)
		arm.rotation.y = -winkel
		wurzel.add_child(arm)
	return wurzel


## Sammel-Spot: ein Stöckchen bzw. ein Blatt, das im Garten herumliegt.
static func sammel_spot(material_id: String) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Spot_%s" % material_id
	if material_id == "blatt":
		var blatt := box(Vector3(0.3, 0.02, 0.2), "blatt")
		blatt.position.y = 0.02
		blatt.rotation.y = 0.4
		wurzel.add_child(blatt)
		return wurzel
	for i in 2:
		var stock := zylinder(0.035, 0.5, "holz_dunkel")
		stock.rotation.z = PI / 2.0
		stock.rotation.y = 0.6 * i
		stock.position.y = 0.04
		wurzel.add_child(stock)
	return wurzel


## Klemmbrett für die Liefer-Cutscene (Doc D §3.2).
static func klemmbrett() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Klemmbrett"
	var brett := box(Vector3(0.24, 0.32, 0.02), "holz")
	wurzel.add_child(brett)
	var papier := box(Vector3(0.2, 0.26, 0.01), "rahmen")
	papier.position = Vector3(0.0, -0.01, 0.016)
	wurzel.add_child(papier)
	var klammer := box(Vector3(0.1, 0.04, 0.02), "metall")
	klammer.position = Vector3(0.0, 0.15, 0.02)
	wurzel.add_child(klammer)
	return wurzel


## Umzugs-/Lieferkarton.
static func karton(kante := 0.42) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Karton"
	var kiste := box(Vector3(kante, kante, kante), "holz")
	kiste.position.y = kante * 0.5
	wurzel.add_child(kiste)
	var band := box(Vector3(kante * 0.16, kante + 0.01, kante + 0.01), "anstrich")
	band.position.y = kante * 0.5
	wurzel.add_child(band)
	return wurzel
