class_name RanchWelt
extends RefCounted
## Weltdaten der Gooby Ranch (RANCH-1) — PURE + headless-testbar (Muster
## CityKulisse): hier entstehen nur PLATZIERUNGEN (was steht wo, wie groß,
## wie gedreht, welche Farbe) für die Überlandfahrt und das Riesenfeld.
## Die Meshes hängt RanchBau als MultiMesh-Gruppen/Primitive ein.
##
## Quelldaten: der `welt`-Eintrag des Ranch-Content-Packs (RanchKatalog);
## fehlt das Pack, gelten die Defaults hier. Seed-deterministisch — gleiche
## Daten ⇒ gleiche Welt (Weltdaten-Integritätstest rechnet den Plan nach).

## Koordinaten: Straße der Überlandfahrt läuft auf x=0 entlang +z
## (heading 0 des CarControllers). Spurmitte = ±LANE_OFFSET (Rechtsverkehr).
const STRASSE_X := 0.0
const FELD_FARBEN: Array[Color] = [
	Color("#E8D48A"),
	Color("#9FCB73"),
	Color("#C9A176"),
	Color("#B5D98A"),
	Color("#D9C27E"),
	Color("#8FC98A"),
]


## Welt-Parameter aus dem Pack (+ Defaults für alle Pflichtfelder).
static func welt_daten() -> Dictionary:
	var pack := RanchKatalog.welt()
	return {
		"feld_breite_m": float(pack.get("feld_breite_m", 480.0)),
		"feld_tiefe_m": float(pack.get("feld_tiefe_m", 380.0)),
		"strasse_laenge_m": float(pack.get("strasse_laenge_m", 520.0)),
		"strasse_breite_m": float(pack.get("strasse_breite_m", 10.0)),
		"schild_km": int(pack.get("schild_km", 8)),
		"deko_seed": int(pack.get("deko_seed", 20260726)),
	}


## ---------------------------------------------------------- Überlandfahrt


## Plan der Landstraße Stadt→Ranch: Felder, Zäune, Heuballen, Bäume,
## Windrad, Bachbrücke, Weidetiere, Schilder, Tor-Position.
static func fahrt_plan(daten := welt_daten()) -> Dictionary:
	var laenge := float(daten["strasse_laenge_m"])
	var halb := laenge / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(daten["deko_seed"])
	var plan := {
		"laenge": laenge,
		"strasse_breite": float(daten["strasse_breite_m"]),
		"spawn_z": -halb + 16.0,
		"tor_z": halb - 12.0,
		"bach_z": halb * 0.35,
		"windrad_pos": Vector3(-42.0, 0.0, -halb * 0.25),
		"schild_km": int(daten["schild_km"]),
		"start_schild_pos": Vector3(7.5, 0.0, -halb + 30.0),
		"felder": [],
		"heuballen": [],
		"baeume": [],
		"zaun_z_bereiche": [],
		"kuehe": [],
		"schafe": [],
	}
	_fahrt_felder(plan, rng, halb)
	_fahrt_deko(plan, rng, halb)
	return plan


static func _fahrt_felder(plan: Dictionary, rng: RandomNumberGenerator, halb: float) -> void:
	var z := -halb + 30.0
	var i := 0
	while z < halb - 40.0:
		var tiefe := rng.randf_range(46.0, 64.0)
		for seite: float in [-1.0, 1.0]:
			var breite := rng.randf_range(52.0, 78.0)
			var abstand := 14.0
			(
				plan["felder"]
				. append(
					{
						"pos": Vector3(seite * (abstand + breite / 2.0), 0.0, z + tiefe / 2.0),
						"groesse": Vector2(breite, tiefe - 6.0),
						"farbe": FELD_FARBEN[(i + (1 if seite > 0.0 else 0)) % FELD_FARBEN.size()],
						"korn": rng.randf() < 0.35,
					}
				)
			)
			i += 1
		z += tiefe
	# Zaunlatten links+rechts der Straße — mit Lücken an Bach und Tor.
	plan["zaun_z_bereiche"] = [
		Vector2(-halb + 24.0, plan["bach_z"] - 8.0),
		Vector2(plan["bach_z"] + 8.0, halb - 26.0),
	]


static func _fahrt_deko(plan: Dictionary, rng: RandomNumberGenerator, halb: float) -> void:
	for _i in 10:
		var seite := -1.0 if rng.randf() < 0.5 else 1.0
		plan["heuballen"].append(
			Vector3(
				seite * rng.randf_range(16.0, 60.0), 0.0, rng.randf_range(-halb + 40.0, halb - 50.0)
			)
		)
	var z := -halb + 36.0
	while z < halb - 30.0:
		for seite: float in [-1.0, 1.0]:
			if rng.randf() < 0.7:
				plan["baeume"].append(
					Vector3(
						seite * rng.randf_range(80.0, 110.0), 0.0, z + rng.randf_range(-8.0, 8.0)
					)
				)
		z += 26.0
	for _i in 2:
		plan["kuehe"].append(
			Vector3(rng.randf_range(-58.0, -24.0), 0.0, rng.randf_range(-halb * 0.6, -halb * 0.2))
		)
	for _i in 3:
		plan["schafe"].append(
			Vector3(rng.randf_range(24.0, 58.0), 0.0, rng.randf_range(halb * 0.45, halb * 0.75))
		)


## ------------------------------------------------------------- Riesenfeld


## Plan des Ranch-Geländes: Gebäude, Koppeln, Reitplatz, Wege, Deko,
## Tier-Startplätze. Rects: position = Min-Ecke (x, z), size = (Breite, Tiefe).
static func hof_plan(daten := welt_daten()) -> Dictionary:
	var breite := float(daten["feld_breite_m"])
	var tiefe := float(daten["feld_tiefe_m"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(daten["deko_seed"]) + 7
	var plan := {
		"breite": breite,
		"tiefe": tiefe,
		"tor_pos": Vector3(0.0, 0.0, tiefe / 2.0 - 6.0),
		"gebaeude":
		[
			{"id": "haus", "pos": Vector3(-46.0, 0.0, 24.0), "rot_grad": 14.0},
			{"id": "scheune", "pos": Vector3(38.0, 0.0, -18.0), "rot_grad": -8.0},
			{"id": "stall", "pos": Vector3(40.0, 0.0, 44.0), "rot_grad": 0.0},
			{"id": "heulager", "pos": Vector3(74.0, 0.0, 10.0), "rot_grad": 4.0},
		],
		"trog_pos": Vector3(20.0, 0.0, 58.0),
		"windrad_pos": Vector3(-132.0, 0.0, -36.0),
		"teich_pos": Vector3(138.0, 0.0, 44.0),
		"reitplatz": Rect2(-118.0, -104.0, 76.0, 52.0),
		"koppeln":
		[
			{"id": "pferde", "rect": Rect2(-6.0, -150.0, 132.0, 96.0), "tor_seite": "sued"},
			{"id": "weide", "rect": Rect2(-190.0, -20.0, 96.0, 76.0), "tor_seite": "ost"},
		],
		"wege":
		[
			{
				"von": Vector3(0.0, 0.0, tiefe / 2.0 - 6.0),
				"bis": Vector3(0.0, 0.0, 34.0),
				"breite": 7.0
			},
			{"von": Vector3(0.0, 0.0, 40.0), "bis": Vector3(-40.0, 0.0, 30.0), "breite": 5.0},
			{"von": Vector3(0.0, 0.0, 40.0), "bis": Vector3(34.0, 0.0, 44.0), "breite": 5.0},
			{"von": Vector3(6.0, 0.0, 42.0), "bis": Vector3(56.0, 0.0, -12.0), "breite": 4.0},
		],
		"pferde":
		[
			Vector3(30.0, 0.0, -96.0),
			Vector3(58.0, 0.0, -118.0),
			Vector3(86.0, 0.0, -84.0),
		],
		"kuehe": [Vector3(-160.0, 0.0, 8.0), Vector3(-128.0, 0.0, 30.0)],
		"schafe":
		[
			Vector3(-170.0, 0.0, 36.0),
			Vector3(-146.0, 0.0, 44.0),
			Vector3(-118.0, 0.0, 12.0),
		],
		"huehner": [Vector3(28.0, 0.0, 52.0), Vector3(34.0, 0.0, 60.0)],
		"baeume": [],
		"gras_zonen": [],
	}
	_hof_deko(plan, rng, breite, tiefe)
	return plan


static func _hof_deko(
	plan: Dictionary, rng: RandomNumberGenerator, breite: float, tiefe: float
) -> void:
	# Baumgürtel am Rand + einzelne Hof-Bäume.
	for _i in 46:
		var rand_seite := rng.randi_range(0, 3)
		var pos := Vector3.ZERO
		match rand_seite:
			0:
				pos = Vector3(
					rng.randf_range(-breite / 2.0, breite / 2.0), 0.0, -tiefe / 2.0 + 14.0
				)
			1:
				pos = Vector3(rng.randf_range(-breite / 2.0, breite / 2.0), 0.0, tiefe / 2.0 - 14.0)
			2:
				pos = Vector3(-breite / 2.0 + 14.0, 0.0, rng.randf_range(-tiefe / 2.0, tiefe / 2.0))
			_:
				pos = Vector3(breite / 2.0 - 14.0, 0.0, rng.randf_range(-tiefe / 2.0, tiefe / 2.0))
		pos.x += rng.randf_range(-8.0, 8.0)
		pos.z += rng.randf_range(-8.0, 8.0)
		if absf(pos.x) < 30.0 and pos.z > tiefe / 2.0 - 40.0:
			continue
		plan["baeume"].append(pos)
	for _i in 8:
		plan["baeume"].append(
			Vector3(rng.randf_range(-90.0, 130.0), 0.0, rng.randf_range(60.0, tiefe / 2.0 - 30.0))
		)
	# Gras-/Blumen-Zonen: Weideflächen + freie Ränder (MultiMesh-Streuung).
	plan["gras_zonen"] = [
		Rect2(-breite / 2.0 + 10.0, -tiefe / 2.0 + 10.0, breite - 20.0, tiefe - 20.0),
	]


## Zaunpfosten-Transformationen rund um ein Rect (Pfostenabstand `schritt`,
## optionale Tor-Lücke `luecke` m mittig auf einer Seite: nord/sued/ost/west).
static func zaun_ring(rect: Rect2, schritt: float, tor_seite := "", luecke := 6.0) -> Array:
	var out: Array = []
	var seiten := [
		{"id": "nord", "von": Vector2(rect.position.x, rect.position.y), "achse": "x"},
		{"id": "sued", "von": Vector2(rect.position.x, rect.end.y), "achse": "x"},
		{"id": "west", "von": Vector2(rect.position.x, rect.position.y), "achse": "z"},
		{"id": "ost", "von": Vector2(rect.end.x, rect.position.y), "achse": "z"},
	]
	for seite: Dictionary in seiten:
		var achse: String = seite["achse"]
		var laenge := rect.size.x if achse == "x" else rect.size.y
		var mitte := laenge / 2.0
		var hat_tor: bool = str(seite["id"]) == tor_seite
		var d := 0.0
		while d < laenge - schritt * 0.5:
			var segment_mitte := d + schritt / 2.0
			d += schritt
			if hat_tor and absf(segment_mitte - mitte) < luecke / 2.0:
				continue
			var von: Vector2 = seite["von"]
			var pos := Vector3.ZERO
			var rot := 0.0
			if achse == "x":
				pos = Vector3(von.x + segment_mitte, 0.0, von.y)
				rot = 0.0
			else:
				pos = Vector3(von.x, 0.0, von.y + segment_mitte)
				rot = PI / 2.0
			out.append({"pos": pos, "rot": rot})
	return out


## ------------------------------------------------- Integritäts-Prüfungen


## Weltdaten-Integrität (leere Liste = alles gut): alles im Feld, keine
## Gebäude-Überlappungen, Tiere in ihren Koppeln, Weg erreicht das Tor.
static func plan_probleme(plan: Dictionary) -> Array[String]:
	var probleme: Array[String] = []
	var feld := Rect2(
		-float(plan["breite"]) / 2.0,
		-float(plan["tiefe"]) / 2.0,
		float(plan["breite"]),
		float(plan["tiefe"])
	)
	var boxen: Array[Rect2] = []
	for geb: Dictionary in plan["gebaeude"]:
		var groesse := gebaeude_groesse(str(geb["id"]))
		var pos: Vector3 = geb["pos"]
		var box := Rect2(pos.x - groesse.x / 2.0, pos.z - groesse.z / 2.0, groesse.x, groesse.z)
		if not feld.encloses(box):
			probleme.append("Gebäude %s ragt aus dem Feld" % geb["id"])
		for andere in boxen:
			if box.intersects(andere):
				probleme.append("Gebäude %s überlappt ein anderes" % geb["id"])
		boxen.append(box.grow(2.0))
	for koppel: Dictionary in plan["koppeln"]:
		var rect: Rect2 = koppel["rect"]
		if not feld.encloses(rect):
			probleme.append("Koppel %s ragt aus dem Feld" % koppel["id"])
		for box in boxen:
			if rect.intersects(box):
				probleme.append("Koppel %s überlappt ein Gebäude" % koppel["id"])
	if not feld.encloses(Rect2(plan["reitplatz"])):
		probleme.append("Reitplatz ragt aus dem Feld")
	var pferde_koppel: Rect2 = plan["koppeln"][0]["rect"]
	for pferd: Vector3 in plan["pferde"]:
		if not pferde_koppel.has_point(Vector2(pferd.x, pferd.z)):
			probleme.append("Pferd außerhalb der Pferdekoppel")
	var weide: Rect2 = plan["koppeln"][1]["rect"]
	for tier: Vector3 in plan["kuehe"] + plan["schafe"]:
		if not weide.has_point(Vector2(tier.x, tier.z)):
			probleme.append("Weidetier außerhalb der Weide")
	var tor: Vector3 = plan["tor_pos"]
	var erster_weg: Dictionary = plan["wege"][0]
	if (erster_weg["von"] as Vector3).distance_to(tor) > 1.0:
		probleme.append("Hauptweg startet nicht am Tor")
	return probleme


## Fahrt-Integrität: Felder überlappen die Straße nicht, Tor liegt hinter
## dem Spawn, Zaun-Lücke deckt die Bachbrücke ab.
static func fahrt_probleme(plan: Dictionary) -> Array[String]:
	var probleme: Array[String] = []
	var strasse_halb := float(plan["strasse_breite"]) / 2.0
	for feld: Dictionary in plan["felder"]:
		var pos: Vector3 = feld["pos"]
		var groesse: Vector2 = feld["groesse"]
		if absf(pos.x) - groesse.x / 2.0 < strasse_halb + 1.0:
			probleme.append("Feld überlappt die Straße (x=%.1f)" % pos.x)
	if float(plan["tor_z"]) <= float(plan["spawn_z"]):
		probleme.append("Tor liegt nicht hinter dem Spawn")
	var bach_frei := false
	for bereich: Vector2 in plan["zaun_z_bereiche"]:
		if float(plan["bach_z"]) >= bereich.x and float(plan["bach_z"]) <= bereich.y:
			bach_frei = false
			break
		bach_frei = true
	if not bach_frei:
		probleme.append("Zaun läuft durch die Bachbrücke")
	return probleme


## Fußabdruck (Breite, Höhe, Tiefe in m) der prozeduralen Hof-Gebäude —
## EINE Quelle für Bau (RanchBau) und Integritätstest.
static func gebaeude_groesse(id: String) -> Vector3:
	match id:
		"scheune":
			return Vector3(20.0, 13.0, 26.0)
		"stall":
			return Vector3(26.0, 7.5, 12.0)
		"haus":
			return Vector3(18.0, 9.0, 13.0)
		"heulager":
			return Vector3(14.0, 6.5, 10.0)
		_:
			return Vector3(8.0, 5.0, 8.0)
