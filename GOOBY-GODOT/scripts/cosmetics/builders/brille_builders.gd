class_name BrilleBuilders
extends RefCounted
## Prozedurale Brillen/Gesichtsteile (CONTENT-A). Maße im Rezept-Raum der
## Web-Referenz; der Anker sitzt auf Augenhöhe vor dem Gesicht (+z = vorn).
##
## Gläser sind flache Zylinder statt Kreisscheiben — in Godot bleibt eine
## einzelne Fläche sonst je nach Blickwinkel unsichtbar.

## Augenabstand des Rigs (Rezept-Raum): Gläser sitzen genau darüber.
const AUGE_X := 0.112
const GLAS_Z := 0.012
## Kopf-Ellipsoid, umgerechnet aus KoerperForm in DIESEN Anker (der Brillen-
## Anker steht 0.2113 vor und 0.0282 über dem Kopfmittelpunkt; alles geteilt
## durch KOPF_SCALE 0.7044). Gebraucht für alles, was den Schädel umrundet.
const KOPF_Y := -0.040
const KOPF_Z := -0.280
const KOPF_R := 0.315
const KOPF_RY := 0.276
## Bandhöhe der Schutzbrillen: knapp unter der Glasmitte, wie im echten Leben.
const BAND_Y := -0.02


static func build(build_id: String, def: Dictionary) -> Node3D:
	match build_id:
		"brille":
			return brille(def)
		"goggles":
			return goggles(def)
		"monokel":
			return monokel(def)
		"augenklappe":
			return augenklappe(def)
		"scherzbrille":
			return scherzbrille(def)
		"visier":
			return visier(def)
		_:
			return null


## Schädelradius auf lokaler Höhe `y` (Rezept-Raum dieses Ankers).
static func _kopf_radius(y: float) -> float:
	var dy := clampf((y - KOPF_Y) / KOPF_RY, -1.0, 1.0)
	return KOPF_R * sqrt(1.0 - dy * dy)


## Standardbrille in acht Glasformen (`params.form`).
static func brille(def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Brille"
	var gestell := CosmeticParts.farbe_von(def, 0, Color("#7A5C4F"))
	var glas := CosmeticParts.farbe_von(def, 1, Color("#BFE3FF"))
	var glas2 := CosmeticParts.farbe_von(def, 2, glas)
	var form := str(CosmeticParts.param(def, "form", "rund"))
	var dick := 0.018 if bool(CosmeticParts.param(def, "dick", false)) else 0.011
	var zweifarbig := bool(CosmeticParts.param(def, "zweifarbig", false))
	for sx: float in [-1.0, 1.0]:
		var pos := Vector3(sx * AUGE_X, 0.0, GLAS_Z)
		var farbe := glas2 if (zweifarbig and sx > 0.0) else glas
		_glasform(wurzel, form, pos, gestell, farbe, dick, sx)
	_gestell(wurzel, gestell, form == "halb")
	return wurzel


## Schutzbrillen mit Band: Flieger-, Taucher-, Skibrille.
static func goggles(def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Brille"
	var rahmen := CosmeticParts.farbe_von(def, 0, Color("#7A5C4F"))
	var glas := CosmeticParts.farbe_von(def, 1, Color("#BFE3FF"))
	var band := CosmeticParts.farbe_von(def, 2, rahmen.darkened(0.25))
	var breit := bool(CosmeticParts.param(def, "breit", false))
	if bool(CosmeticParts.param(def, "einscheibe", false)):
		var schale := CosmeticParts.box(
			wurzel,
			Vector3(0.29 if breit else 0.25, 0.115, 0.05),
			rahmen,
			Vector3(0.0, 0.0, 0.004),
			CosmeticParts.RAUH_LACK
		)
		schale.scale = Vector3(1.0, 1.0, 1.0)
		var scheibe := CosmeticParts.box(
			wurzel, Vector3(0.245 if breit else 0.205, 0.08, 0.02), glas, Vector3(0.0, 0.0, 0.035)
		)
		scheibe.material_override = CosmeticParts.mat(glas, 0.12, 0.0, 0.72)
	else:
		for sx: float in [-1.0, 1.0]:
			var becher := CosmeticParts.zyl(
				wurzel,
				0.072,
				0.066,
				0.05,
				rahmen,
				Vector3(sx * AUGE_X, 0.0, 0.01),
				CosmeticParts.RAUH_LACK
			)
			becher.rotation.x = PI * 0.5
			var linse := CosmeticParts.zyl(
				wurzel, 0.058, 0.058, 0.012, glas, Vector3(sx * AUGE_X, 0.0, 0.036)
			)
			linse.rotation.x = PI * 0.5
			linse.material_override = CosmeticParts.mat(glas, 0.12, 0.0, 0.7)
		CosmeticParts.box(wurzel, Vector3(0.075, 0.03, 0.03), rahmen, Vector3(0.0, 0.0, 0.01))
	# Band WAAGERECHT um den Kopf (nicht als Heiligenschein über den Schädel).
	# Der Kopf ist im Querschnitt RUND — ein in z gestauchter Ring schneidet
	# vorn/hinten ein und steht seitlich als Untertasse ab. Also: exakt der
	# Schädelradius auf Bandhöhe, nur der Schlauch wird flachgedrückt.
	var riemen := CosmeticParts.ring(
		wurzel, _kopf_radius(BAND_Y), 0.017, band, Vector3(0.0, BAND_Y, KOPF_Z)
	)
	riemen.scale.y = 0.62
	return wurzel


## Monokel: ein Glas + Kette.
static func monokel(def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Brille"
	var gold := CosmeticParts.farbe_von(def, 0, Color("#F7C948"))
	var glas := CosmeticParts.farbe_von(def, 1, Color("#BFE3FF"))
	var rand := CosmeticParts.ring(wurzel, 0.064, 0.011, gold, Vector3(AUGE_X, 0.0, GLAS_Z))
	rand.rotation.x = PI * 0.5
	rand.material_override = CosmeticParts.mat(gold, CosmeticParts.RAUH_LACK, 0.5)
	var scheibe := CosmeticParts.zyl(wurzel, 0.058, 0.058, 0.008, glas, Vector3(AUGE_X, 0.0, 0.008))
	scheibe.rotation.x = PI * 0.5
	scheibe.material_override = CosmeticParts.mat(glas, 0.12, 0.0, 0.35)
	for i in range(1, 8):
		var t := float(i) / 7.0
		CosmeticParts.kugel(
			wurzel,
			0.0075,
			gold,
			Vector3(AUGE_X + t * 0.075 + sin(t * PI) * 0.012, -0.055 - t * 0.075, 0.004)
		)
	return wurzel


## Augenklappe: Schild + Band.
static func augenklappe(def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Brille"
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#26262E"))
	var band := CosmeticParts.farbe_von(def, 1, stoff.lightened(0.1))
	var schild := CosmeticParts.kugel(wurzel, 0.062, stoff, Vector3(-AUGE_X, 0.004, 0.016))
	schild.scale = Vector3(1.0, 1.05, 0.32)
	var riemen := CosmeticParts.ring(wurzel, 0.17, 0.012, band, Vector3(0.0, 0.03, -0.07))
	riemen.rotation.x = PI * 0.5
	riemen.rotation.z = 0.16
	riemen.scale = Vector3(1.0, 1.1, 1.0)
	return wurzel


## Scherzbrille mit Nase und Augenbrauen.
static func scherzbrille(def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Brille"
	var gestell := CosmeticParts.farbe_von(def, 0, Color("#3A2E2E"))
	var nase := CosmeticParts.farbe_von(def, 1, Color("#F6A8B8"))
	for sx: float in [-1.0, 1.0]:
		var rand := CosmeticParts.ring(
			wurzel, 0.062, 0.014, gestell, Vector3(sx * AUGE_X, 0.0, GLAS_Z)
		)
		rand.rotation.x = PI * 0.5
		var braue := CosmeticParts.box(
			wurzel, Vector3(0.1, 0.026, 0.02), gestell, Vector3(sx * AUGE_X, 0.072, 0.012)
		)
		braue.rotation.z = -sx * 0.16
	var zinken := CosmeticParts.kugel(wurzel, 0.05, nase, Vector3(0.0, -0.052, 0.045))
	zinken.scale = Vector3(0.9, 1.0, 1.25)
	CosmeticParts.box(wurzel, Vector3(0.06, 0.016, 0.02), gestell, Vector3(0.0, 0.012, 0.01))
	_gestell(wurzel, gestell, false)
	return wurzel


## Laservisier: durchgehender Balken mit Glühstreifen.
static func visier(def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Brille"
	var schale := CosmeticParts.farbe_von(def, 0, Color("#B7C2CC"))
	var glut := CosmeticParts.farbe_von(def, 1, Color("#E0655F"))
	CosmeticParts.box(
		wurzel,
		Vector3(0.28, 0.062, 0.045),
		schale,
		Vector3(0.0, 0.0, 0.012),
		CosmeticParts.RAUH_LACK
	)
	var streifen := CosmeticParts.box(
		wurzel, Vector3(0.235, 0.022, 0.02), glut, Vector3(0.0, 0.0, 0.04)
	)
	var leucht := StandardMaterial3D.new()
	leucht.albedo_color = glut
	leucht.emission_enabled = true
	leucht.emission = glut
	leucht.emission_energy_multiplier = 2.2
	streifen.material_override = leucht
	for sx: float in [-1.0, 1.0]:
		var arm := CosmeticParts.box(
			wurzel, Vector3(0.014, 0.02, 0.16), schale, Vector3(sx * 0.14, 0.008, -0.06)
		)
		arm.rotation.y = -sx * 0.3
	return wurzel


## Ein Glas in der gewünschten Form (Rand + Füllung).
static func _glasform(
	wurzel: Node3D, form: String, pos: Vector3, gestell: Color, glas: Color, dick: float, sx: float
) -> void:
	match form:
		"eckig", "pixel":
			var kasten := CosmeticParts.box(
				wurzel, Vector3(0.125, 0.095, 0.022), gestell, pos, CosmeticParts.RAUH_LACK
			)
			if form == "pixel":
				kasten.scale = Vector3(1.05, 0.62, 1.0)
			var fuellung := CosmeticParts.box(
				wurzel, Vector3(0.105, 0.075, 0.014), glas, pos + Vector3(0, 0, 0.012)
			)
			fuellung.material_override = CosmeticParts.mat(glas, 0.14, 0.0, 0.86)
			if form == "pixel":
				fuellung.scale = Vector3(1.0, 0.6, 1.0)
		"herz":
			CosmeticParts.herz(wurzel, 0.075, gestell, pos)
			CosmeticParts.herz(wurzel, 0.06, glas, pos + Vector3(0, 0, 0.012))
		"stern":
			CosmeticParts.stern(wurzel, 0.085, gestell, pos)
			CosmeticParts.stern(wurzel, 0.066, glas, pos + Vector3(0, 0, 0.012))
		"blume":
			for i in 6:
				var winkel := TAU * float(i) / 6.0
				var blatt := CosmeticParts.kugel(
					wurzel,
					0.028,
					gestell,
					pos + Vector3(cos(winkel) * 0.046, sin(winkel) * 0.046, 0.0)
				)
				blatt.scale.z = 0.4
			CosmeticParts.zyl(wurzel, 0.05, 0.05, 0.012, glas, pos + Vector3(0, 0, 0.008)).rotation.x = (
				PI * 0.5
			)
		"halb":
			var buegel := CosmeticParts.box(
				wurzel, Vector3(0.13, 0.016, 0.018), gestell, pos + Vector3(0, 0.03, 0)
			)
			buegel.rotation.z = -sx * 0.06
			var scheibe := CosmeticParts.zyl(
				wurzel, 0.055, 0.055, 0.01, glas, pos + Vector3(0, -0.012, 0.004)
			)
			scheibe.rotation.x = PI * 0.5
			scheibe.material_override = CosmeticParts.mat(glas, 0.14, 0.0, 0.45)
		"katze":
			var rand := CosmeticParts.ring(wurzel, 0.062, dick, gestell, pos)
			rand.rotation.x = PI * 0.5
			rand.scale = Vector3(1.12, 1.0, 0.85)
			var spitze := CosmeticParts.kegel(
				wurzel, 0.03, 0.07, gestell, pos + Vector3(sx * 0.075, 0.05, 0.0)
			)
			spitze.rotation.z = -sx * 0.9
			spitze.scale.z = 0.35
			_fuellung(wurzel, pos, glas, 0.056)
		_:
			var kreis := CosmeticParts.ring(wurzel, 0.062, dick, gestell, pos)
			kreis.rotation.x = PI * 0.5
			_fuellung(wurzel, pos, glas, 0.058)


static func _fuellung(wurzel: Node3D, pos: Vector3, glas: Color, radius: float) -> void:
	var scheibe := CosmeticParts.zyl(wurzel, radius, radius, 0.01, glas, pos - Vector3(0, 0, 0.004))
	scheibe.rotation.x = PI * 0.5
	scheibe.material_override = CosmeticParts.mat(glas, 0.15, 0.0, 0.55)


## Brücke über der Nase + zwei Bügel zu den Ohren.
static func _gestell(wurzel: Node3D, farbe: Color, tief: bool) -> void:
	var bruecke := CosmeticParts.zyl(
		wurzel, 0.009, 0.009, 0.07, farbe, Vector3(0.0, 0.02 if not tief else 0.03, 0.005)
	)
	bruecke.rotation.z = PI * 0.5
	for sx: float in [-1.0, 1.0]:
		var arm := CosmeticParts.box(
			wurzel, Vector3(0.011, 0.011, 0.17), farbe, Vector3(sx * 0.205, 0.02, -0.065)
		)
		arm.rotation.y = -sx * 0.38
