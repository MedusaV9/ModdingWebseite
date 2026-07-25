class_name RueckenBuilders
extends RefCounted
## Prozedurale Rückenteile (CONTENT-A). Maße im Rezept-Raum der Web-Referenz
## (`buildBackpackTiny` & Co.): der Anker sitzt zwischen den Schulterblättern,
## -z zeigt nach HINTEN, das Teil wächst also in den negativen z-Bereich.
##
## Bewegte Teile (Propeller, Ballon, Flügel) markieren ihren Dreh-/Schwenkknoten
## per `set_meta("animation", ...)` — `cosmetic_attach.gd` animiert ihn, falls
## die Szene das will. Ohne Animator sieht das Teil trotzdem korrekt aus.

## Höhe des Ankers in Weltkoordinaten (dickste Stelle des Rumpfes).
const ANKER_Y := KoerperForm.ANKER["ruecken"].y
## Rückseite des Körpers auf Ankerhöhe — dort liegt jedes Teil auf. Kommt aus
## dem gemessenen Körpermodell, nicht aus den Web-Zahlen: der 3D-Gooby ist so
## rund, dass ein Rucksack mit Web-Tiefe komplett im Rücken stecken würde.
const RUECKEN_Z := -KoerperForm.RUMPF_R / KoerperForm.RIG_SCALE


static func build(build_id: String, def: Dictionary) -> Node3D:
	match build_id:
		"rucksack":
			return rucksack(def)
		"ballon":
			return ballon(def)
		"propeller":
			return propeller(def)
		"panzer":
			return panzer(def)
		"fluegel":
			return fluegel(def)
		"brett":
			return brett(def)
		"jetpack":
			return jetpack(def)
		"schirm":
			return schirm(def)
		"rueckenschleife":
			return rueckenschleife(def)
		"schwert":
			return schwert(def)
		"gitarre":
			return gitarre(def)
		_:
			return null


## Kleiner Rucksack: Korpus, Deckelklappe, Vortasche, zwei Schultergurte.
static func rucksack(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#59C9B9"))
	var klappe := CosmeticParts.farbe_von(def, 1, stoff.darkened(0.22))
	var tasche := CosmeticParts.farbe_von(def, 2, Color("#FFD166"))
	var korpus := CosmeticParts.box(
		wurzel, Vector3(0.34, 0.34, 0.17), stoff, Vector3(0.0, 0.0, RUECKEN_Z - 0.03)
	)
	korpus.rotation.x = -0.08
	var deckel := CosmeticParts.box(
		wurzel, Vector3(0.32, 0.11, 0.19), klappe, Vector3(0.0, 0.14, RUECKEN_Z - 0.035)
	)
	deckel.rotation.x = -0.12
	CosmeticParts.box(
		wurzel, Vector3(0.2, 0.13, 0.07), tasche, Vector3(0.0, -0.08, RUECKEN_Z - 0.135)
	)
	CosmeticParts.kugel(wurzel, 0.02, tasche.lightened(0.3), Vector3(0.0, 0.105, RUECKEN_Z - 0.14))
	_gurte(wurzel, klappe.darkened(0.15))
	return wurzel


## Ballon am Bändel — `anzahl` > 1 macht eine Traube mit Farbwechsel.
static func ballon(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var anzahl := maxi(1, int(CosmeticParts.param(def, "anzahl", 1)))
	var schnur := Color("#DED3C2")
	var pivot := Node3D.new()
	pivot.name = "Schwenk"
	pivot.position = Vector3(0.12, 0.04, RUECKEN_Z + 0.02)
	pivot.set_meta("animation", "ballon")
	wurzel.add_child(pivot)
	for i in anzahl:
		var farbe := CosmeticParts.farbe_von(def, i, Color("#E0655F"))
		var seite := 0.0 if anzahl == 1 else (float(i) / float(anzahl - 1) - 0.5) * 0.34
		var hoehe := 0.78 + (0.0 if anzahl == 1 else absf(seite) * 0.42)
		# Bändel: gestapelte dünne Boxen statt Tube-Geometrie.
		for s in 8:
			var t := float(s) / 8.0
			CosmeticParts.box(
				pivot,
				Vector3(0.012, hoehe / 8.0 + 0.005, 0.012),
				schnur,
				Vector3(seite * t, (hoehe - 0.16) * (t + 0.06), 0.01)
			)
		var haut := CosmeticParts.kugel(
			pivot, 0.16, farbe, Vector3(seite, hoehe, 0.015), CosmeticParts.RAUH_LACK
		)
		haut.scale = Vector3(0.86, 1.14, 0.82)
		var knoten := CosmeticParts.kegel(
			pivot, 0.025, 0.055, farbe.darkened(0.25), Vector3(seite, hoehe - 0.18, 0.015)
		)
		knoten.rotation.x = PI
	return wurzel


## Propellerrucksack: Tank-Paar plus dauerdrehender Rotor.
static func propeller(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var pack := CosmeticParts.farbe_von(def, 0, Color("#B7C2CC"))
	var duese := CosmeticParts.farbe_von(def, 1, Color("#E0655F"))
	var blatt := CosmeticParts.farbe_von(def, 2, Color("#F7C948"))
	var korpus := CosmeticParts.box(
		wurzel, Vector3(0.28, 0.32, 0.14), pack, Vector3(0.0, 0.0, RUECKEN_Z - 0.02)
	)
	korpus.material_override = CosmeticParts.mat(pack, CosmeticParts.RAUH_LACK, 0.25)
	for sx: float in [-1.0, 1.0]:
		var tank := CosmeticParts.zyl(
			wurzel,
			0.055,
			0.065,
			0.3,
			pack.lightened(0.18),
			Vector3(sx * 0.12, -0.02, RUECKEN_Z - 0.05),
			CosmeticParts.RAUH_LACK
		)
		tank.material_override = CosmeticParts.mat(pack.lightened(0.18), 0.4, 0.48)
		var flamme := CosmeticParts.kegel(
			wurzel, 0.058, 0.1, duese, Vector3(sx * 0.12, -0.21, RUECKEN_Z - 0.05)
		)
		flamme.rotation.x = PI
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0.0, 0.08, RUECKEN_Z - 0.12)
	rotor.set_meta("animation", "propeller")
	wurzel.add_child(rotor)
	var nabe := CosmeticParts.zyl(rotor, 0.035, 0.035, 0.055, blatt)
	nabe.rotation.x = PI * 0.5
	nabe.material_override = CosmeticParts.mat(blatt, CosmeticParts.RAUH_LACK, 0.5)
	for rz: float in [0.0, PI * 0.5]:
		var fluegelblatt := CosmeticParts.box(
			rotor, Vector3(0.34, 0.045, 0.018), blatt, Vector3(0.0, 0.0, -0.035)
		)
		fluegelblatt.rotation.z = rz
	return wurzel


## Schildkrötenpanzer: flache Kuppel, Mittelplatte, Randplatten, Randwulst.
static func panzer(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var schale := CosmeticParts.farbe_von(def, 0, Color("#4F9C67"))
	var platte := CosmeticParts.farbe_von(def, 1, Color("#2E6846"))
	var rand := CosmeticParts.farbe_von(def, 2, Color("#E8C88A"))
	# Kuppel liegt AUF dem Rücken (flache Seite zum Körper), nicht als Scheibe
	# daneben: dom() steht auf y, also um −90° kippen und in z flach drücken.
	var kuppel := CosmeticParts.dom(wurzel, 0.4, schale, Vector3(0.0, 0.02, RUECKEN_Z + 0.02))
	kuppel.rotation.x = -PI * 0.5
	kuppel.scale = Vector3(1.0, 1.0, 0.75)
	var mitte := CosmeticParts.zyl(
		wurzel, 0.16, 0.2, 0.05, platte, Vector3(0.0, 0.02, RUECKEN_Z - 0.24)
	)
	mitte.rotation.x = PI * 0.5
	for i in 6:
		var winkel := TAU * float(i) / 6.0
		var feld := CosmeticParts.zyl(
			wurzel,
			0.085,
			0.105,
			0.04,
			platte.lightened(0.16 if i % 2 == 0 else 0.32),
			Vector3(cos(winkel) * 0.26, 0.02 + sin(winkel) * 0.26, RUECKEN_Z - 0.19)
		)
		feld.rotation.x = PI * 0.5
		feld.rotation.y = winkel
	var wulst := CosmeticParts.ring(wurzel, 0.39, 0.035, rand, Vector3(0.0, 0.02, RUECKEN_Z - 0.02))
	wulst.rotation.x = PI * 0.5
	return wurzel


## Flügelpaar. `form`: fee (transparent, 4 Flügel) | kaefer (Deckflügel) |
## engel (Federreihen).
static func fluegel(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var form := str(CosmeticParts.param(def, "form", "fee"))
	var haupt := CosmeticParts.farbe_von(def, 0, Color("#FFD4E4"))
	var ader := CosmeticParts.farbe_von(def, 1, Color("#B896E8"))
	for sx: float in [-1.0, 1.0]:
		var seite := Node3D.new()
		seite.name = "Fluegel"
		seite.position = Vector3(sx * 0.04, 0.04, RUECKEN_Z - 0.02)
		seite.scale.x = sx
		seite.set_meta("animation", "fluegel")
		wurzel.add_child(seite)
		match form:
			"kaefer":
				_kaeferfluegel(seite, haupt, ader)
			"engel":
				_engelfluegel(seite, haupt, ader)
			_:
				_feenfluegel(seite, haupt, ader)
	return wurzel


## Surfbrett, diagonal auf dem Rücken.
static func brett(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var deck := CosmeticParts.farbe_von(def, 0, Color("#FFFAF2"))
	var streifen := CosmeticParts.farbe_von(def, 1, Color("#55D7DF"))
	var finne := CosmeticParts.farbe_von(def, 2, Color("#FF7BA9"))
	var kiel := Node3D.new()
	kiel.name = "Brett"
	kiel.position = Vector3(0.0, -0.02, RUECKEN_Z - 0.04)
	kiel.rotation.z = -0.48
	wurzel.add_child(kiel)
	var korpus := CosmeticParts.kapsel(
		kiel, 0.11, 0.84, deck, Vector3.ZERO, CosmeticParts.RAUH_LACK
	)
	korpus.scale.z = 0.24
	# Streifen auf BEIDE Decks — sonst steckt er im Brett und man sieht nichts.
	for sz: float in [-1.0, 1.0]:
		CosmeticParts.box(kiel, Vector3(0.032, 0.74, 0.01), streifen, Vector3(0.0, 0.0, sz * 0.028))
	CosmeticParts.kegel(kiel, 0.06, 0.12, finne, Vector3(0.0, -0.34, -0.035)).scale.z = 0.35
	return wurzel


## Jetpack: zwei Tanks, Verstrebung, Flammen aus den Düsen.
static func jetpack(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var tank_farbe := CosmeticParts.farbe_von(def, 0, Color("#B7C2CC"))
	var flamme := CosmeticParts.farbe_von(def, 1, Color("#E0655F"))
	var kern := CosmeticParts.farbe_von(def, 2, Color("#FFD166"))
	CosmeticParts.box(
		wurzel, Vector3(0.16, 0.26, 0.08), tank_farbe.darkened(0.2), Vector3(0, 0.02, RUECKEN_Z)
	)
	for sx: float in [-1.0, 1.0]:
		var tank := CosmeticParts.kapsel(
			wurzel,
			0.085,
			0.36,
			tank_farbe,
			Vector3(sx * 0.15, 0.0, RUECKEN_Z - 0.06),
			CosmeticParts.RAUH_LACK
		)
		tank.material_override = CosmeticParts.mat(tank_farbe, 0.35, 0.4)
		CosmeticParts.ring(wurzel, 0.088, 0.014, flamme, Vector3(sx * 0.15, 0.06, RUECKEN_Z - 0.06))
		var duese := CosmeticParts.zyl(
			wurzel,
			0.06,
			0.075,
			0.06,
			tank_farbe.darkened(0.3),
			Vector3(sx * 0.15, -0.21, RUECKEN_Z - 0.06)
		)
		duese.scale = Vector3.ONE
		var strahl := CosmeticParts.kegel(
			wurzel, 0.055, 0.16, flamme, Vector3(sx * 0.15, -0.31, RUECKEN_Z - 0.06)
		)
		strahl.rotation.x = PI
		var docht := CosmeticParts.kegel(
			wurzel, 0.03, 0.09, kern, Vector3(sx * 0.15, -0.29, RUECKEN_Z - 0.06)
		)
		docht.rotation.x = PI
	_gurte(wurzel, tank_farbe.darkened(0.35))
	return wurzel


## Regenschirm, zusammengebunden quer über dem Rücken.
static func schirm(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var bespannung := CosmeticParts.farbe_von(def, 0, Color("#59C9B9"))
	var keil := CosmeticParts.farbe_von(def, 1, Color("#FFFAF2"))
	var holz := CosmeticParts.farbe_von(def, 2, Color("#7A5C4F"))
	var stiel := Node3D.new()
	stiel.name = "Schirm"
	stiel.position = Vector3(0.02, -0.02, RUECKEN_Z - 0.06)
	stiel.rotation.z = 0.42
	wurzel.add_child(stiel)
	CosmeticParts.zyl(stiel, 0.018, 0.018, 0.62, holz)
	for i in 8:
		var teil := CosmeticParts.kegel(
			stiel, 0.052, 0.3, bespannung if i % 2 == 0 else keil, Vector3(0.0, 0.16, 0.0)
		)
		teil.rotation.y = TAU * float(i) / 8.0
		teil.position += Vector3(
			cos(TAU * float(i) / 8.0) * 0.035, 0.0, sin(TAU * float(i) / 8.0) * 0.035
		)
	CosmeticParts.kugel(stiel, 0.028, holz.lightened(0.2), Vector3(0.0, 0.33, 0.0))
	# Griff: kurzer Haken aus drei Segmenten.
	for i in 3:
		var winkel := PI * 0.5 * float(i) / 2.0
		CosmeticParts.kugel(
			stiel,
			0.024,
			holz,
			Vector3(-0.055 + cos(winkel) * 0.055, -0.31 - sin(winkel) * 0.045, 0.0)
		)
	return wurzel


## Große Schleife im Kreuz (von hinten das schönste Geschenk).
static func rueckenschleife(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var stoff := CosmeticParts.farbe_von(def, 0, Color("#FF7BA9"))
	var knoten_farbe := CosmeticParts.farbe_von(def, 1, stoff.darkened(0.2))
	for sx: float in [-1.0, 1.0]:
		var schlaufe := CosmeticParts.zyl(
			wurzel, 0.2, 0.2, 0.07, stoff, Vector3(sx * 0.19, 0.03, RUECKEN_Z - 0.02)
		)
		schlaufe.rotation.x = PI * 0.5
		schlaufe.scale = Vector3(1.0, 1.0, 0.62)
		var innen := CosmeticParts.zyl(
			wurzel, 0.1, 0.1, 0.09, knoten_farbe, Vector3(sx * 0.21, 0.03, RUECKEN_Z - 0.02)
		)
		innen.rotation.x = PI * 0.5
		innen.scale = Vector3(1.0, 1.0, 0.62)
		var band := CosmeticParts.box(
			wurzel, Vector3(0.09, 0.28, 0.04), stoff, Vector3(sx * 0.12, -0.21, RUECKEN_Z - 0.02)
		)
		band.rotation.z = sx * 0.3
	CosmeticParts.box(
		wurzel, Vector3(0.11, 0.12, 0.09), knoten_farbe, Vector3(0.0, 0.03, RUECKEN_Z - 0.01)
	)
	return wurzel


## Holzschwert im Rückengurt.
static func schwert(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var klinge := CosmeticParts.farbe_von(def, 0, Color("#B98D62"))
	var griff := CosmeticParts.farbe_von(def, 1, Color("#7A5C4F"))
	var knauf := CosmeticParts.farbe_von(def, 2, Color("#F7C948"))
	var waffe := Node3D.new()
	waffe.name = "Schwert"
	waffe.position = Vector3(-0.02, -0.04, RUECKEN_Z - 0.05)
	waffe.rotation.z = -0.55
	wurzel.add_child(waffe)
	var blatt := CosmeticParts.box(waffe, Vector3(0.085, 0.5, 0.035), klinge, Vector3(0, 0.12, 0))
	blatt.scale = Vector3.ONE
	var spitze := CosmeticParts.kegel(waffe, 0.06, 0.1, klinge, Vector3(0.0, 0.42, 0.0))
	spitze.scale.z = 0.42
	CosmeticParts.box(waffe, Vector3(0.26, 0.045, 0.05), griff, Vector3(0.0, -0.15, 0.0))
	CosmeticParts.zyl(waffe, 0.032, 0.032, 0.17, griff.darkened(0.2), Vector3(0.0, -0.24, 0.0))
	CosmeticParts.kugel(waffe, 0.045, knauf, Vector3(0.0, -0.33, 0.0))
	_gurte(wurzel, griff)
	return wurzel


## Gitarre am Gurt (drei Akkorde, zwei davon gut).
static func gitarre(def: Dictionary) -> Node3D:
	var wurzel := _wurzel()
	var korpus_farbe := CosmeticParts.farbe_von(def, 0, Color("#E0655F"))
	var hals_farbe := CosmeticParts.farbe_von(def, 1, Color("#7A5C4F"))
	var decke := CosmeticParts.farbe_von(def, 2, Color("#FFF2D6"))
	var instrument := Node3D.new()
	instrument.name = "Gitarre"
	instrument.position = Vector3(0.0, -0.06, RUECKEN_Z - 0.05)
	instrument.rotation.z = 0.5
	wurzel.add_child(instrument)
	# Korpus: zwei Zylinder-Lappen (Taille) + Decke.
	for daten: Array in [[0.19, -0.1, 1.0], [0.145, 0.09, 0.92]]:
		var lappen := CosmeticParts.zyl(
			instrument,
			float(daten[0]),
			float(daten[0]),
			0.085,
			korpus_farbe,
			Vector3(0.0, float(daten[1]), 0.0),
			CosmeticParts.RAUH_LACK
		)
		lappen.rotation.x = PI * 0.5
		lappen.scale = Vector3(float(daten[2]), 1.0, 0.55)
	var loch := CosmeticParts.zyl(
		instrument, 0.055, 0.055, 0.02, hals_farbe.darkened(0.4), Vector3(0.0, 0.02, -0.05)
	)
	loch.rotation.x = PI * 0.5
	CosmeticParts.box(instrument, Vector3(0.075, 0.34, 0.04), hals_farbe, Vector3(0.0, 0.34, -0.01))
	var kopf := CosmeticParts.box(
		instrument, Vector3(0.1, 0.12, 0.035), hals_farbe.darkened(0.2), Vector3(0.0, 0.55, -0.01)
	)
	kopf.rotation.x = 0.12
	for i in 3:
		CosmeticParts.box(
			instrument,
			Vector3(0.012, 0.44, 0.012),
			decke,
			Vector3(-0.02 + 0.02 * float(i), 0.28, -0.032)
		)
	_gurte(wurzel, hals_farbe)
	return wurzel


static func _wurzel() -> Node3D:
	var node := Node3D.new()
	node.name = "Ruecken"
	return node


## Zwei Schultergurte, die AUF dem Körper über die Schulter nach vorn laufen —
## einzelne Glieder statt Torus, weil der Torus nicht der Körperform folgt.
static func _gurte(wurzel: Node3D, farbe: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		for i in 10:
			# Bogen: hinten am Pack → über die Schulter → auf die Brust.
			var t := float(i) / 9.0
			var hoehe := 0.02 + sin(t * PI * 0.85) * 0.3
			var winkel := sx * (PI - t * PI * 0.74)
			var glied := CosmeticParts.kugel(
				wurzel, 0.045, farbe, KoerperForm.punkt(ANKER_Y, hoehe, winkel, 0.025)
			)
			glied.scale = Vector3(0.75, 1.0, 0.75)


## Vier durchscheinende Feenflügel-Blätter je Seite.
static func _feenfluegel(seite: Node3D, haut: Color, ader: Color) -> void:
	var glas := CosmeticParts.mat(haut, 0.18, 0.0, 0.62)
	for sy: float in [1.0, -1.0]:
		var blatt_hoehe := 0.34 if sy > 0.0 else 0.25
		var blatt := CosmeticParts.kugel(
			seite, 0.16, haut, Vector3(0.17, 0.09 * sy + 0.03, 0.0), 0.18
		)
		blatt.material_override = glas
		blatt.scale = Vector3(1.15, blatt_hoehe / 0.32, 0.1)
		blatt.rotation.z = 0.42 if sy > 0.0 else -0.28
		var strebe := CosmeticParts.zyl(
			seite, 0.008, 0.012, blatt_hoehe, ader, Vector3(0.09, 0.09 * sy + 0.03, 0.008)
		)
		strebe.rotation.z = -0.5 if sy > 0.0 else -0.8


## Käfer: harter Deckflügel + hauchdünner Unterflügel.
static func _kaeferfluegel(seite: Node3D, deck: Color, punkt: Color) -> void:
	var schale := CosmeticParts.kugel(seite, 0.18, deck, Vector3(0.14, 0.0, 0.0), 0.42)
	schale.scale = Vector3(0.95, 1.25, 0.32)
	for pos: Vector3 in [
		Vector3(0.1, 0.12, 0.06), Vector3(0.19, -0.02, 0.05), Vector3(0.12, -0.14, 0.05)
	]:
		var fleck := CosmeticParts.kugel(seite, 0.036, punkt, pos)
		fleck.scale.z = 0.4
	var unter := CosmeticParts.kugel(seite, 0.15, Color("#FFFFFF"), Vector3(0.2, -0.03, -0.05))
	unter.material_override = CosmeticParts.mat(Color("#FFFFFF"), 0.2, 0.0, 0.4)
	unter.scale = Vector3(1.2, 0.85, 0.08)
	unter.rotation.z = -0.35


## Engel: geschlossenes Flügelblatt aus flachen Kugeln, unten Federspitzen.
static func _engelfluegel(seite: Node3D, feder: Color, schimmer: Color) -> void:
	for i in 3:
		var blatt := CosmeticParts.kugel(
			seite,
			0.17 - 0.018 * float(i),
			feder,
			Vector3(0.1 + 0.11 * float(i), 0.1 - 0.075 * float(i), 0.0)
		)
		blatt.scale = Vector3(1.0, 1.3, 0.14)
		blatt.rotation.z = -0.28 - 0.12 * float(i)
	for i in 5:
		var federchen := CosmeticParts.kapsel(
			seite,
			0.042,
			0.24 - 0.022 * float(i),
			schimmer if i % 2 == 0 else feder,
			Vector3(0.09 + 0.062 * float(i), -0.06 - 0.045 * float(i), 0.012)
		)
		federchen.rotation.z = -1.0 - 0.06 * float(i)
		federchen.scale.z = 0.34
