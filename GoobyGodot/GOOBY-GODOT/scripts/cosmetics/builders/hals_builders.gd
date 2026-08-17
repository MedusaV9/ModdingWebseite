class_name HalsBuilders
extends RefCounted
## Prozedurale Halsteile (CONTENT-A). Maße im Rezept-Raum; der Anker sitzt auf
## der Kopf-/Körper-Naht (Welt y 0.452), +z = vorn.
##
## WICHTIG: Der 3D-Gooby ist deutlich runder als die Web-Vorlage — mit den
## Web-Radien (0.33) steckt jedes Halsband im Bauch. Alle Radien kommen
## deshalb aus `KoerperForm`, dem am Mesh gemessenen Kugelmodell:
## `_r(y)` liefert den Oberflächenradius auf lokaler Höhe `y`, `_auf(y, winkel)`
## direkt einen Punkt darauf. So sitzt auch ein tief hängendes Schalende noch
## auf dem Bauch statt darin — der Körper wird nach unten hin ja breiter.

## Höhe des Ankers in Weltkoordinaten (für die Radiusabfragen).
const ANKER_Y := KoerperForm.ANKER["hals"].y
## Stoffdicke: so weit liegt ein Teil über der Haut.
const LUFT := 0.035


static func build(build_id: String, def: Dictionary) -> Node3D:
	match build_id:
		"schal":
			return schal(def)
		"fliege":
			return fliege(def)
		"tuch":
			return tuch(def)
		"halsband":
			return halsband(def)
		"umhang":
			return umhang(def)
		"krawatte":
			return krawatte(def)
		"kragen":
			return kragen(def)
		"kopfhoerer":
			return kopfhoerer(def)
		_:
			return null


## Schal-Familie: einfarbig, gestreift, dick (Winter), flauschig (Boa).
static func schal(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var haupt := CosmeticParts.farbe_von(def, 0, Color("#E0655F"))
	var zweit := CosmeticParts.farbe_von(def, 1, haupt.darkened(0.2))
	var dick := bool(CosmeticParts.param(def, "dick", false))
	var flausch := bool(CosmeticParts.param(def, "flausch", false))
	var tube := 0.075 if dick else 0.058
	if flausch:
		for i in 18:
			var winkel := TAU * float(i) / 18.0
			CosmeticParts.kugel(
				wurzel, 0.085, haupt if i % 2 == 0 else zweit, _auf(-0.04, winkel, tube * 0.4)
			)
		return wurzel
	var farben: Array = (
		[haupt, zweit] if bool(CosmeticParts.param(def, "streifen", false)) else [haupt]
	)
	_kringel(wurzel, -0.02, tube, farben, 20)
	_schal_ende(wurzel, -1.0, haupt, zweit)
	_schal_ende(wurzel, 1.0, zweit, haupt)
	# Knoten vorn, wo die beiden Enden herauskommen.
	CosmeticParts.box(wurzel, Vector3(0.14, 0.09, 0.07), haupt, _auf(-0.03, 0.0, tube * 0.5))
	return wurzel


## Fliege / Riesenschleife.
static func fliege(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#E0655F"))
	var knoten_farbe := CosmeticParts.farbe_von(def, 1, stoff.darkened(0.22))
	var gross := bool(CosmeticParts.param(def, "gross", false))
	var skala := 1.7 if gross else 1.15
	_kringel(wurzel, -0.01, 0.022, [knoten_farbe], 24)
	var vorn := _r(-0.03) + 0.02
	for sx: float in [-1.0, 1.0]:
		var fluegel := CosmeticParts.box(
			wurzel,
			Vector3(0.125 * skala, 0.082 * skala, 0.05),
			stoff,
			Vector3(sx * 0.08 * skala, -0.02, vorn)
		)
		fluegel.rotation.z = sx * 0.14
		fluegel.rotation.x = -0.2
		if gross:
			var band_ende := CosmeticParts.box(
				wurzel, Vector3(0.055, 0.15, 0.035), stoff, Vector3(sx * 0.06, -0.16, vorn - 0.02)
			)
			band_ende.rotation.z = sx * 0.35
	var knoten := CosmeticParts.box(
		wurzel,
		Vector3(0.055 * skala, 0.065 * skala, 0.06),
		knoten_farbe,
		Vector3(0.0, -0.02, vorn + 0.02)
	)
	knoten.rotation.x = -0.2
	return wurzel


## Halstuch: Band + dreieckiger Zipfel auf der Brust.
static func tuch(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#FF7BA9"))
	var punkt := CosmeticParts.farbe_von(def, 1, stoff.darkened(0.2))
	_kringel(wurzel, -0.01, 0.04, [stoff], 22)
	var zipfel := CosmeticParts.kegel(wurzel, 0.15, 0.24, stoff, Vector3(0.0, -0.13, _r(-0.13)))
	zipfel.rotation.x = PI + 0.16
	zipfel.scale = Vector3(1.0, 1.0, 0.3)
	for i in 3:
		var hoehe := -0.09 - 0.045 * float(i % 2)
		CosmeticParts.kugel(
			wurzel, 0.02, punkt, Vector3(-0.055 + 0.055 * float(i), hoehe, _r(hoehe) + 0.035)
		)
	return wurzel


## Halsband/Kette mit Anhänger oder Perlen.
static func halsband(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var band := CosmeticParts.farbe_von(def, 0, Color("#E0655F"))
	var deko := CosmeticParts.farbe_von(def, 1, Color("#F7C948"))
	var metall := float(CosmeticParts.param(def, "metallic", 0.0))
	var perlen := int(CosmeticParts.param(def, "perlen", 0))
	if perlen > 0:
		var gross := bool(CosmeticParts.param(def, "blueten", false))
		for i in perlen:
			# Kette hängt vorn durch: außen hoch, in der Mitte tiefer.
			var t := float(i) / float(maxi(perlen - 1, 1))
			var winkel := PI * (-0.62 + 1.24 * t)
			var hoehe := -0.03 - sin(PI * t) * 0.07
			var kugel := CosmeticParts.kugel(
				wurzel,
				0.04 if gross else 0.03,
				band if i % 2 == 0 else deko,
				_auf(hoehe, winkel, 0.03)
			)
			kugel.material_override = CosmeticParts.mat(band if i % 2 == 0 else deko, 0.4, metall)
	else:
		_kringel(wurzel, -0.02, 0.026, [band], 22)
	_anhaenger(wurzel, str(CosmeticParts.param(def, "anhaenger", "")), deko, metall)
	return wurzel


## Heldenumhang: Kragen + wehendes Tuch auf dem Rücken.
static func umhang(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#E0655F"))
	var futter := CosmeticParts.farbe_von(def, 1, Color("#FFD166"))
	_kringel(wurzel, 0.01, 0.045, [futter], 20)
	for i in 5:
		var hoehe := -0.06 - 0.16 * float(i)
		var bahn := CosmeticParts.box(
			wurzel,
			Vector3(_r(hoehe) * 1.65, 0.19, 0.035),
			stoff if i % 2 == 0 else stoff.darkened(0.07),
			Vector3(0.0, hoehe, -_r(hoehe) - 0.04)
		)
		bahn.rotation.x = -0.1
	for sx: float in [-1.0, 1.0]:
		CosmeticParts.kugel(wurzel, 0.035, futter, _auf(-0.02, sx * 0.55, 0.03))
	return wurzel


## Krawatte: Knoten + langer Zipfel.
static func krawatte(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#438AC9"))
	var dunkel := CosmeticParts.farbe_von(def, 1, stoff.darkened(0.25))
	_kringel(wurzel, 0.0, 0.024, [dunkel], 22)
	var knoten := CosmeticParts.box(
		wurzel, Vector3(0.08, 0.08, 0.06), dunkel, Vector3(0.0, -0.03, _r(-0.03) + 0.02)
	)
	knoten.rotation.x = -0.14
	for i in 3:
		var hoehe := -0.13 - 0.1 * float(i)
		CosmeticParts.box(
			wurzel, Vector3(0.115, 0.11, 0.035), stoff, Vector3(0.0, hoehe, _r(hoehe) + 0.015)
		)
	var spitze := CosmeticParts.kegel(
		wurzel, 0.08, 0.1, stoff, Vector3(0.0, -0.4, _r(-0.4) + 0.015)
	)
	spitze.rotation.x = PI
	spitze.scale.z = 0.35
	return wurzel


## Kragen: Rüschen (barock) oder Hemdkragen.
static func kragen(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#FFFAF2"))
	var schatten := CosmeticParts.farbe_von(def, 1, stoff.darkened(0.12))
	if bool(CosmeticParts.param(def, "ruesche", true)):
		for i in 14:
			var winkel := TAU * float(i) / 14.0
			var falte := CosmeticParts.kugel(
				wurzel, 0.105, stoff if i % 2 == 0 else schatten, _auf(-0.03, winkel, 0.045)
			)
			falte.scale = Vector3(1.0, 0.55, 1.0)
		return wurzel
	_kringel(wurzel, 0.01, 0.03, [stoff], 20)
	for sx: float in [-1.0, 1.0]:
		var lasche := CosmeticParts.box(
			wurzel, Vector3(0.17, 0.14, 0.045), stoff, _auf(-0.07, sx * 0.42, 0.02)
		)
		lasche.rotation.z = sx * 0.5
		lasche.rotation.x = -0.12
	return wurzel


## Kopfhörer, die um den Nacken hängen.
static func kopfhoerer(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var schale := CosmeticParts.farbe_von(def, 0, Color("#3A3A44"))
	var polster := CosmeticParts.farbe_von(def, 1, Color("#FF7BA9"))
	_kringel(wurzel, 0.0, 0.026, [schale], 20)
	for sx: float in [-1.0, 1.0]:
		var sitz := _auf(-0.03, sx * PI * 0.5, 0.02)
		var muschel := CosmeticParts.zyl(
			wurzel, 0.08, 0.08, 0.055, schale, sitz, CosmeticParts.RAUH_LACK
		)
		muschel.rotation.z = PI * 0.5
		var pad := CosmeticParts.zyl(
			wurzel, 0.062, 0.062, 0.035, polster, sitz - Vector3(sx * 0.03, 0.0, 0.0)
		)
		pad.rotation.z = PI * 0.5
	return wurzel


# ── Helfer ───────────────────────────────────────────────────────────────────


static func _wurzel() -> Node3D:
	var node := Node3D.new()
	node.name = "Hals"
	return node


## Oberflächenradius auf lokaler Höhe `y` (plus Stoffdicke).
static func _r(y: float, luft := LUFT) -> float:
	return KoerperForm.radius(ANKER_Y, y, luft)


## Punkt auf der Oberfläche: `winkel` 0 = vorn, wachsend Richtung +x.
static func _auf(y: float, winkel: float, luft := LUFT) -> Vector3:
	return KoerperForm.punkt(ANKER_Y, y, winkel, luft)


## Ring aus einzelnen Gliedern, der der Körperform folgt. Godot-Torusse sind
## starr rund — der Hals ist es nicht, und gestreifte Schals brauchen ohnehin
## Segmente.
static func _kringel(wurzel: Node3D, y: float, tube: float, farben: Array, segmente: int) -> void:
	for i in segmente:
		var winkel := TAU * float(i) / float(segmente)
		var glied := CosmeticParts.kugel(
			wurzel, tube * 1.25, farben[i % farben.size()], _auf(y, winkel, tube * 0.35)
		)
		glied.scale.y = 0.85


## Hängendes Schalende (gestapelte Segmente + Fransen), das dem Bauch folgt.
static func _schal_ende(wurzel: Node3D, sx: float, farbe: Color, zweit: Color) -> void:
	for i in 4:
		var hoehe := -0.1 - 0.085 * float(i)
		CosmeticParts.box(
			wurzel,
			Vector3(0.1, 0.09, 0.05),
			farbe if i % 2 == 0 else zweit,
			Vector3(sx * 0.07, hoehe, _r(hoehe) + 0.01)
		)
	for fx: float in [-0.032, 0.0, 0.032]:
		var hoehe := -0.46
		CosmeticParts.box(
			wurzel,
			Vector3(0.022, 0.04, 0.035),
			zweit,
			Vector3(sx * 0.07 + fx, hoehe, _r(hoehe) + 0.01)
		)


## Anhänger an einer Kette/einem Halsband.
static func _anhaenger(wurzel: Node3D, art: String, farbe: Color, metall: float) -> void:
	var hoehe := -0.13
	var vorn := _r(hoehe) + 0.02
	match art:
		"gloeckchen":
			var glocke := CosmeticParts.kugel(wurzel, 0.055, farbe, Vector3(0.0, hoehe, vorn))
			glocke.material_override = CosmeticParts.mat(farbe, CosmeticParts.RAUH_LACK, 0.45)
			CosmeticParts.box(
				wurzel,
				Vector3(0.05, 0.014, 0.014),
				farbe.darkened(0.35),
				Vector3(0.0, hoehe - 0.04, vorn)
			)
		"medaille":
			var scheibe := CosmeticParts.zyl(
				wurzel, 0.08, 0.08, 0.02, farbe, Vector3(0.0, hoehe - 0.03, vorn)
			)
			scheibe.rotation.x = PI * 0.5
			scheibe.material_override = CosmeticParts.mat(farbe, CosmeticParts.RAUH_LACK, metall)
			CosmeticParts.stern(
				wurzel, 0.042, farbe.lightened(0.35), Vector3(0.0, hoehe - 0.03, vorn + 0.014)
			)
		"muschel":
			var muschel := CosmeticParts.kugel(wurzel, 0.062, farbe, Vector3(0.0, hoehe, vorn))
			muschel.scale = Vector3(1.0, 0.9, 0.35)
			for i in 4:
				var rippe := CosmeticParts.box(
					wurzel,
					Vector3(0.009, 0.072, 0.012),
					farbe.darkened(0.2),
					Vector3(-0.03 + 0.02 * float(i), hoehe, vorn + 0.018)
				)
				rippe.rotation.z = -0.3 + 0.2 * float(i)
		"herz":
			CosmeticParts.herz(wurzel, 0.058, farbe, Vector3(0.0, hoehe - 0.02, vorn))
		"ausweis":
			var tief := -0.26
			var karte := CosmeticParts.box(
				wurzel,
				Vector3(0.1, 0.13, 0.014),
				Color("#FFFAF2"),
				Vector3(0.0, tief, _r(tief) + 0.02)
			)
			karte.rotation.x = -0.12
			CosmeticParts.box(
				wurzel,
				Vector3(0.065, 0.022, 0.016),
				farbe,
				Vector3(0.0, tief + 0.03, _r(tief) + 0.03)
			)
			for sx: float in [-1.0, 1.0]:
				var schnur := CosmeticParts.box(
					wurzel, Vector3(0.024, 0.22, 0.022), farbe, Vector3(sx * 0.12, -0.12, _r(-0.12))
				)
				schnur.rotation.z = sx * 0.42
