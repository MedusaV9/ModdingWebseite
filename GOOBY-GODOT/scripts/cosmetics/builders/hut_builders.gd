class_name HutBuilders
extends RefCounted
## Prozedurale Hüte (CONTENT-A) — Kenney/GOOBY-Stil aus Godot-Primitiven,
## keine externen 3D-Modelle. Alle Maße im Rezept-Raum der Web-Referenz
## (`GOOBY/src/character/outfitAttach.js`), Umrechnung macht der Anker.
##
## OHREN-REGEL: Goobys Ohren stehen bei x = ±0.13 (Radius 0.085) und beginnen
## knapp UNTER dem Hut-Anker. Deshalb sitzt jeder Hut nach vorn versetzt
## (`_aufsetzen`, z ≈ 0.1) und nach vorn gekippt, und breite Kronen werden in
## x/z gestaucht — so bleiben die Ohren frei. Neue Hüte bitte immer mit den
## Screenshots aus `tests/unit/screenshot_cosmetics.gd` gegenprüfen.

## Vorwärtsversatz + Kippung der Hutgruppe (gegen Ohren-Clipping).
const SITZ_Z := 0.1
const SITZ_Y := -0.014
const SITZ_KIPP := 0.24
## Kronen breiter als das werden in x gestaucht, damit sie zwischen den Ohren
## durchpassen statt sie zu durchdringen.
const KRONE_MAX_X := 0.098
## OHRLÖCHER: Ab diesem Krempen-Außenradius (Rezept) wächst die Krempe in die
## Ohren — dann wird der Ohr-Sektor ausgeschnitten statt durchdrungen.
## Die Zahlen sind AM MESH GEMESSEN (Vertex-Sweep über die Ohr-Bones auf
## Krempenhöhe): das rechte Ohr belegt dort x 0.06…0.22 und z −0.10…0.06 im
## Anker-Rezeptraum. Um die um SITZ_Z nach vorn versetzte Hutachse sind das
## 100.6°…163.4°, also Mitte 132° ± 31.4° (+ etwas Luft).
## Krempen wirken auf dem breiten 3D-Kopf schnell zu knapp — die Web-Radien
## sind für einen viel schmaleren Kopf eingemessen. Ein globaler Faktor ist
## billiger (und einheitlicher) als 30 Einzelwerte im JSON. Die Ohrlöcher
## bleiben davon unberührt: ihr Winkel hängt an der Ohrposition, nicht am
## Krempenradius.
const KREMPE_WEITE := 1.28
const OHR_FREI_R := 0.15
const OHR_MITTE := deg_to_rad(132.0)
const OHR_HALB := deg_to_rad(35.0)


static func build(build_id: String, def: Dictionary) -> Node3D:
	match build_id:
		"kegel":
			return kegel(def)
		"kappe":
			return kappe(def)
		"zylinder":
			return zylinder(def)
		"krone":
			return krone(def)
		"chefhut":
			return chefhut(def)
		"kranz":
			return kranz(def)
		"dreispitz":
			return dreispitz(def)
		"helm":
			return helm(def)
		"kuerbis":
			return kuerbis(def)
		"torte":
			return torte(def)
		"ananas":
			return ananas(def)
		_:
			return null


## Spitzhut: Partyhut, Zauberhut, Nikolaus-/Zipfel-/Hexenhut.
static func kegel(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var haupt := CosmeticParts.farbe_von(def, 0, Color("#FF7BA9"))
	var deko := CosmeticParts.farbe_von(def, 1, Color("#FFD166"))
	var hoehe := float(CosmeticParts.param(def, "hoehe", 0.19))
	var radius := float(CosmeticParts.param(def, "radius", 0.105))
	var krempe_r := float(CosmeticParts.param(def, "krempe_r", 0.0))
	var kipp := float(CosmeticParts.param(def, "kipp", 0.0))
	var basis := 0.012
	if krempe_r > 0.0:
		_krempe(hut, krempe_r, haupt.darkened(0.18), 0.0, 0.0)
	CosmeticParts.kegel(hut, radius, hoehe, haupt, Vector3(0.0, basis + hoehe * 0.5, 0.0))
	var spitze_y := basis + hoehe
	var spitze_x := 0.0
	if kipp > 0.0:
		# Geknickte Spitze: zweiter, kleinerer Kegel lehnt sich zur Seite.
		var tip := CosmeticParts.kegel(
			hut, radius * 0.42, hoehe * 0.62, haupt, Vector3(radius * 0.28, spitze_y + 0.02, 0.0)
		)
		tip.rotation.z = -kipp
		spitze_x = radius * 0.28 + sin(kipp) * hoehe * 0.34
		spitze_y += cos(kipp) * hoehe * 0.34
	if bool(CosmeticParts.param(def, "manschette", false)):
		var manschette := CosmeticParts.ring(hut, radius * 1.02, 0.028, deko, Vector3(0, basis, 0))
		manschette.scale.z = 0.85
	if bool(CosmeticParts.param(def, "band", false)):
		CosmeticParts.ring(hut, radius * 0.96, 0.018, deko, Vector3(0, basis + 0.022, 0)).scale.z = 0.9
	if bool(CosmeticParts.param(def, "bommel", true)):
		CosmeticParts.kugel(hut, radius * 0.36, deko, Vector3(spitze_x, spitze_y, 0.0))
	for i in int(CosmeticParts.param(def, "sterne", 0)):
		var hoch := hoehe * (0.22 + 0.24 * float(i))
		CosmeticParts.stern(
			hut, 0.028, deko, Vector3(0.0, basis + hoch, radius * (0.82 - 0.3 * float(i)))
		)
	return _aufsetzen(hut, def)


## Kappen-Familie: Beanie, Cap, Barett, Kapitänsmütze, Tiermütze.
static func kappe(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var haupt := CosmeticParts.farbe_von(def, 0, Color("#59C9B9"))
	var deko := CosmeticParts.farbe_von(def, 1, Color("#FFF9EC"))
	var art := str(CosmeticParts.param(def, "kappe", "beanie"))
	var dom := CosmeticParts.dom(hut, 0.113, haupt, Vector3(0.0, 0.004, 0.0))
	dom.scale = Vector3(1.0, 1.9, 1.0) if art == "barett" else Vector3(1.0, 1.75, 1.0)
	match art:
		"beanie":
			var brim := CosmeticParts.ring(
				hut, 0.108, 0.028, haupt.darkened(0.16), Vector3(0, 0.012, 0)
			)
			brim.scale.z = 0.85
			CosmeticParts.kugel(hut, 0.04, deko, Vector3(0.0, 0.125, 0.0))
		"schirm":
			CosmeticParts.kugel(hut, 0.02, deko, Vector3(0.0, 0.105, 0.0))
			_schirm(hut, 0.115, haupt.darkened(0.1))
		"barett":
			var scheibe := CosmeticParts.zyl(hut, 0.128, 0.116, 0.026, haupt, Vector3(0, 0.03, 0))
			scheibe.scale.z = 0.92
			CosmeticParts.kapsel(hut, 0.012, 0.05, haupt.darkened(0.2), Vector3(0, 0.075, -0.01))
		"kapitaen":
			var deckel := CosmeticParts.zyl(hut, 0.12, 0.112, 0.02, deko, Vector3(0, 0.088, 0))
			deckel.scale.z = 0.92
			CosmeticParts.ring(hut, 0.112, 0.016, haupt.darkened(0.25), Vector3(0, 0.03, 0)).scale.z = 0.9
			CosmeticParts.box(
				hut, Vector3(0.05, 0.03, 0.012), Color("#F7C948"), Vector3(0, 0.048, 0.104)
			)
			_schirm(hut, 0.108, haupt.darkened(0.3))
		"tier":
			for sx in [-1.0, 1.0]:
				CosmeticParts.kugel(hut, 0.042, deko, Vector3(sx * 0.058, 0.096, 0.03))
				CosmeticParts.kugel(hut, 0.02, Color("#26262E"), Vector3(sx * 0.058, 0.1, 0.066))
			_schirm(hut, 0.108, haupt.darkened(0.12))
	return _aufsetzen(hut, def)


## Krempenhut: Zylinder, Strohhut, Sombrero, Fedora, Melone, Cowboyhut.
static func zylinder(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var haupt := CosmeticParts.farbe_von(def, 0, Color("#3A3A44"))
	var band_farbe := CosmeticParts.farbe_von(def, 1, Color("#E0655F"))
	var krone_h := float(CosmeticParts.param(def, "krone_h", 0.2))
	var krone_r := float(CosmeticParts.param(def, "krone_r", 0.096))
	var krempe_r := float(CosmeticParts.param(def, "krempe_r", 0.145))
	_krempe(hut, krempe_r, haupt, float(CosmeticParts.param(def, "krempe_kipp", 0.0)), 0.008)
	if bool(CosmeticParts.param(def, "kuppel", false)):
		var dom := CosmeticParts.dom(hut, krone_r, haupt, Vector3(0.0, 0.014, 0.0))
		dom.scale = Vector3(1.0, krone_h / krone_r * 1.6, 0.94)
	else:
		var krone := CosmeticParts.zyl(
			hut, krone_r * 0.94, krone_r, krone_h, haupt, Vector3(0.0, 0.014 + krone_h * 0.5, 0.0)
		)
		krone.scale.z = 0.94
		var deckel := CosmeticParts.dom(
			hut, krone_r * 0.94, haupt, Vector3(0.0, 0.014 + krone_h, 0.0)
		)
		deckel.scale = Vector3(1.0, 0.5, 0.94)
	if bool(CosmeticParts.param(def, "delle", false)):
		# Eingedrückte Krone (Fedora/Cowboy): schmale Kerbe längs oben drauf.
		var kerbe := CosmeticParts.box(
			hut,
			Vector3(krone_r * 0.5, krone_h * 0.4, krone_r * 2.0),
			haupt.darkened(0.22),
			Vector3(0.0, 0.014 + krone_h * 0.92, 0.0)
		)
		kerbe.scale.z = 0.9
	CosmeticParts.ring(hut, krone_r * 1.02, 0.016, band_farbe, Vector3(0.0, 0.04, 0.0)).scale.z = 0.94
	return _aufsetzen(hut, def)


## Krone/Krönchen: Reif + Zacken + Juwelen.
static func krone(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var gold := CosmeticParts.farbe_von(def, 0, Color("#F7C948"))
	var juwel := CosmeticParts.farbe_von(def, 1, Color("#FF7BA9"))
	var metall := float(CosmeticParts.param(def, "metallic", 0.5))
	var radius := float(CosmeticParts.param(def, "radius", 0.092))
	var hoehe := float(CosmeticParts.param(def, "hoehe", 0.08))
	var zacken := int(CosmeticParts.param(def, "zacken", 6))
	var reif := CosmeticParts.zyl(
		hut, radius, radius + 0.007, hoehe, gold, Vector3(0, hoehe * 0.5, 0)
	)
	reif.material_override = CosmeticParts.mat(gold, CosmeticParts.RAUH_LACK, metall)
	reif.scale.z = 0.92
	for i in zacken:
		var winkel := TAU * float(i) / float(zacken) - PI * 0.5
		var pos := Vector3(cos(winkel) * radius, hoehe + 0.024, sin(winkel) * radius * 0.92)
		var zacke := CosmeticParts.kegel(hut, 0.026, 0.055, gold, pos)
		zacke.material_override = CosmeticParts.mat(gold, CosmeticParts.RAUH_LACK, metall)
		CosmeticParts.kugel(hut, 0.016, juwel, pos + Vector3(0.0, 0.036, 0.0))
	return _aufsetzen(hut, def)


## Kochmütze/Kochhaube: Band + Puff-Wolke.
static func chefhut(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var weiss := CosmeticParts.farbe_von(def, 0, Color("#FFFAF2"))
	var schatten := CosmeticParts.farbe_von(def, 1, Color("#F6EAD8"))
	var hoehe := float(CosmeticParts.param(def, "hoehe", 0.1))
	var puffs := int(CosmeticParts.param(def, "puffs", 5))
	CosmeticParts.zyl(hut, 0.095, 0.088, hoehe, weiss, Vector3(0.0, hoehe * 0.5, 0.0)).scale.z = 0.94
	CosmeticParts.zyl(hut, 0.0965, 0.0965, 0.02, schatten, Vector3(0.0, 0.012, 0.0)).scale.z = 0.94
	for i in puffs:
		var winkel := TAU * float(i) / float(puffs)
		CosmeticParts.kugel(
			hut, 0.052, weiss, Vector3(cos(winkel) * 0.058, hoehe + 0.018, sin(winkel) * 0.052)
		)
	CosmeticParts.kugel(hut, 0.072, weiss, Vector3(0.0, hoehe + 0.042, 0.0)).scale.z = 0.94
	return _aufsetzen(hut, def)


## Kranz: Blumenkranz oder Lorbeerkranz.
static func kranz(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var gruen := CosmeticParts.farbe_von(def, 0, Color("#8FD06C"))
	var blueten := [
		CosmeticParts.farbe_von(def, 1, Color("#FFD1E8")),
		CosmeticParts.farbe_von(def, 2, Color("#FFD166")),
		CosmeticParts.farbe_von(def, 0, Color("#8FD06C")),
	]
	var blaetter := bool(CosmeticParts.param(def, "blaetter", false))
	CosmeticParts.ring(hut, 0.102, 0.02, gruen, Vector3(0.0, 0.02, 0.0)).scale.z = 0.94
	for i in 6:
		var winkel := TAU * float(i) / 6.0 + PI / 6.0
		var pos := Vector3(cos(winkel) * 0.104, 0.03, sin(winkel) * 0.098)
		if blaetter:
			var blatt := CosmeticParts.kugel(hut, 0.036, blueten[i % 2], pos)
			blatt.scale = Vector3(0.5, 0.35, 1.2)
			blatt.rotation.y = -winkel
		else:
			CosmeticParts.kugel(hut, 0.03, blueten[i % 3], pos).scale.y = 0.8
			CosmeticParts.kugel(hut, 0.016, blueten[(i + 1) % 3], pos + Vector3(0, 0.026, 0))
	return _aufsetzen(hut, def)


## Piraten-Dreispitz: flache Krone + hochgeschlagene Krempe + Totenkopf.
static func dreispitz(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#26262E"))
	var deko := CosmeticParts.farbe_von(def, 1, Color("#FFFAF2"))
	CosmeticParts.dom(hut, 0.106, stoff, Vector3(0.0, 0.012, 0.0)).scale = Vector3(1.0, 1.3, 0.94)
	for i in 3:
		var winkel := TAU * float(i) / 3.0 + PI * 0.5
		var flanke := CosmeticParts.kegel(
			hut, 0.075, 0.11, stoff, Vector3(cos(winkel) * 0.1, 0.045, sin(winkel) * 0.095)
		)
		flanke.rotation.x = -cos(winkel) * 0.0
		flanke.rotation.z = -cos(winkel) * 0.9
		flanke.rotation.x = sin(winkel) * 0.9
		flanke.scale = Vector3(1.0, 1.0, 0.55)
	CosmeticParts.kugel(hut, 0.026, deko, Vector3(0.0, 0.055, 0.098)).scale = Vector3(1.0, 1.1, 0.5)
	for sx in [-1.0, 1.0]:
		CosmeticParts.kugel(hut, 0.008, stoff, Vector3(sx * 0.011, 0.062, 0.118))
	return _aufsetzen(hut, def)


## Helme: Wikinger (Hörner), Weltraum (Glaskuppel), Bau, Ritter.
static func helm(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var schale := CosmeticParts.farbe_von(def, 0, Color("#B7C2CC"))
	var deko := CosmeticParts.farbe_von(def, 1, Color("#FFF2D6"))
	var art := str(CosmeticParts.param(def, "helm", "hoerner"))
	var glas := art == "glas"
	# Ein Helm umschließt den Schädel — er darf deutlich breiter und tiefer
	# sitzen als eine Mütze, sonst wirkt er wie ein Fingerhut auf dem Kopf.
	# Der Schädel misst auf Höhe -0.075 rund 0.211 Rezept-Einheiten (Messung s.
	# KoerperForm) — ein Helm mit r 0.15 wäre schmaler als der Kopf und säße
	# wie ein Töpfchen obendrauf. Die Glaskuppel bleibt schmaler: sie ist eine
	# Blase ZWISCHEN den Ohren, kein Helm über sie hinweg.
	var r := 0.168 if glas else 0.215
	var basis := -0.05 if glas else -0.075
	var dom := CosmeticParts.dom(hut, r, schale, Vector3(0.0, basis, 0.0))
	dom.scale = Vector3(1.0, 1.5 if glas else 0.85, 1.0)
	if glas:
		dom.material_override = CosmeticParts.mat(schale, 0.15, 0.0, 0.32)
		CosmeticParts.ring(hut, r * 0.98, 0.02, deko, Vector3(0.0, -0.052, 0.0))
		CosmeticParts.box(hut, Vector3(0.05, 0.02, 0.03), deko, Vector3(0.0, 0.05, -0.15))
		return _aufsetzen(hut, def, 0.06)
	CosmeticParts.ring(hut, r * 0.99, 0.016, deko, Vector3(0.0, -0.062, 0.0)).scale.z = 0.94
	match art:
		"hoerner":
			# Ansatz AUSSEN an der Helmschale (r 0.215), sonst stecken die
			# Hörner in der Kuppel und lugen nur als Splitter hinter den Ohren
			# hervor.
			for sx in [-1.0, 1.0]:
				var horn := CosmeticParts.kegel(
					hut, 0.042, 0.19, deko, Vector3(sx * 0.185, -0.018, -0.01)
				)
				horn.rotation.z = -sx * 1.15
				horn.rotation.x = -0.25
		"bau":
			CosmeticParts.box(
				hut, Vector3(0.026, 0.032, 0.36), schale.darkened(0.15), Vector3(0.0, 0.052, 0.0)
			)
			_schirm(hut, 0.19, schale)
		"ritter":
			CosmeticParts.box(
				hut, Vector3(0.26, 0.024, 0.02), Color("#26262E"), Vector3(0.0, -0.04, 0.198)
			)
			CosmeticParts.kegel(hut, 0.032, 0.1, deko, Vector3(0.0, 0.1, 0.0))
			CosmeticParts.kugel(hut, 0.026, deko, Vector3(0.0, 0.145, 0.0))
	return _aufsetzen(hut, def)


## Kürbishut: gerippte Kugel + Stiel + Blatt.
static func kuerbis(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var orange := CosmeticParts.farbe_von(def, 0, Color("#F28C3A"))
	var gruen := CosmeticParts.farbe_von(def, 1, Color("#4F9C67"))
	for i in 5:
		var winkel := TAU * float(i) / 5.0
		var rippe := CosmeticParts.kugel(
			hut, 0.062, orange, Vector3(cos(winkel) * 0.042, 0.05, sin(winkel) * 0.04)
		)
		rippe.scale = Vector3(1.0, 0.85, 1.0)
	CosmeticParts.kugel(hut, 0.07, orange.darkened(0.08), Vector3(0.0, 0.05, 0.0)).scale.y = 0.9
	CosmeticParts.kapsel(hut, 0.014, 0.05, gruen, Vector3(0.0, 0.115, 0.0)).rotation.z = 0.3
	var blatt := CosmeticParts.kugel(hut, 0.03, gruen, Vector3(0.038, 0.1, 0.012))
	blatt.scale = Vector3(1.0, 0.25, 0.6)
	return _aufsetzen(hut, def)


## Törtchenhut: Papierförmchen + Sahne + Kirsche.
static func torte(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var foermchen := CosmeticParts.farbe_von(def, 0, Color("#FFD1E8"))
	var sahne := CosmeticParts.farbe_von(def, 1, Color("#FFF9EC"))
	var kirsche := CosmeticParts.farbe_von(def, 2, Color("#E0655F"))
	CosmeticParts.zyl(hut, 0.098, 0.078, 0.06, foermchen, Vector3(0.0, 0.032, 0.0)).scale.z = 0.94
	for i in 6:
		var winkel := TAU * float(i) / 6.0
		CosmeticParts.kugel(
			hut, 0.038, sahne, Vector3(cos(winkel) * 0.05, 0.078, sin(winkel) * 0.046)
		)
	CosmeticParts.kugel(hut, 0.046, sahne, Vector3(0.0, 0.108, 0.0))
	CosmeticParts.kugel(hut, 0.024, kirsche, Vector3(0.0, 0.148, 0.0))
	var streusel: Array[Color] = [kirsche, Color("#FFD166"), Color("#59C9B9")]
	for i in 7:
		var winkel := TAU * float(i) / 7.0 + 0.4
		var korn := CosmeticParts.box(
			hut,
			Vector3(0.008, 0.006, 0.022),
			streusel[i % 3],
			Vector3(cos(winkel) * 0.052, 0.098, sin(winkel) * 0.05)
		)
		korn.rotation.y = -winkel
	return _aufsetzen(hut, def)


## Ananashut: gerastertes Ei + Blattkrone.
static func ananas(def: Dictionary) -> Node3D:
	var hut := Node3D.new()
	var frucht := CosmeticParts.farbe_von(def, 0, Color("#FFD166"))
	var gruen := CosmeticParts.farbe_von(def, 1, Color("#4F9C67"))
	var koerper := CosmeticParts.kugel(hut, 0.085, frucht, Vector3(0.0, 0.075, 0.0))
	koerper.scale = Vector3(1.0, 1.35, 0.95)
	for reihe in 3:
		for i in 7:
			var winkel := TAU * float(i) / 7.0 + float(reihe) * 0.4
			var hoch := 0.03 + float(reihe) * 0.045
			var schuppe := CosmeticParts.box(
				hut,
				Vector3(0.024, 0.024, 0.014),
				frucht.darkened(0.18),
				Vector3(cos(winkel) * 0.082, hoch, sin(winkel) * 0.078)
			)
			schuppe.rotation.y = -winkel
			schuppe.rotation.z = 0.7
	for i in 6:
		var winkel := TAU * float(i) / 6.0
		var blatt := CosmeticParts.kegel(
			hut, 0.022, 0.09, gruen, Vector3(cos(winkel) * 0.026, 0.185, sin(winkel) * 0.026)
		)
		blatt.rotation.z = -cos(winkel) * 0.5
		blatt.rotation.x = sin(winkel) * 0.5
	return _aufsetzen(hut, def)


## Krempe (flache Scheibe, optional nach unten gebogen).
## Aussparungen für die beiden Ohren — leer, solange die Krempe schmal genug
## ist, um ohnehin zwischen ihnen durchzupassen.
static func ohr_luecken(radius: float) -> Array:
	if radius <= OHR_FREI_R:
		return []
	return [
		Vector2(OHR_MITTE - OHR_HALB, OHR_MITTE + OHR_HALB),
		Vector2(-(OHR_MITTE + OHR_HALB), -(OHR_MITTE - OHR_HALB)),
	]


## Krempe mit ECHTEN Ohrlöchern (siehe OHR_MITTE/OHR_HALB oben).
## `radius` ist der Außenradius; innen schließt sie an die Krone an.
static func _krempe(
	hut: Node3D, roh_radius: float, farbe: Color, kipp: float, hoehe: float
) -> void:
	var radius := roh_radius * KREMPE_WEITE
	var luecken := ohr_luecken(radius)
	var innen := maxf(0.04, radius * 0.55)
	CosmeticParts.teller(hut, innen, radius, 0.016, farbe, luecken, Vector3(0.0, hoehe, 0.0))
	if kipp > 0.0:
		var rand := CosmeticParts.teller(
			hut,
			radius * 0.9,
			radius * 1.02,
			0.03,
			farbe,
			luecken,
			Vector3(0.0, hoehe - kipp * 0.05, 0.0)
		)
		rand.rotation.x = 0.0


## Halbrunder Schirm über den Augen (Cap, Bauhelm, Kapitänsmütze).
static func _schirm(hut: Node3D, radius: float, farbe: Color) -> void:
	var schirm := CosmeticParts.zyl(hut, radius, radius, 0.012, farbe, Vector3(0.0, 0.012, 0.062))
	schirm.scale = Vector3(0.92, 1.0, 1.25)
	schirm.rotation.x = -0.22
	# Hintere Hälfte des Schirms verstecken: der Zylinder steckt im Kopf.
	schirm.position.z = 0.07


## Setzt die Hutgruppe nach vorn versetzt und gekippt auf den Kopf.
static func _aufsetzen(hut: Node3D, def: Dictionary, z_extra := 0.0) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Hut"
	wurzel.add_child(hut)
	hut.position = Vector3(0.0, SITZ_Y, SITZ_Z + z_extra)
	hut.rotation.x = SITZ_KIPP + float(CosmeticParts.param(def, "sitz_kipp", 0.0))
	return wurzel
