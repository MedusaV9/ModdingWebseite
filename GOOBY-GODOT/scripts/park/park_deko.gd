class_name ParkDeko
extends RefCounted
## Funkelpark-Deko-Planer (GOOBY-WELT/STADT, EVAL B §4 „wirkt wie eine
## Whitebox") — PURE und headless-testbar: hier entstehen nur POSITIONEN/
## Farben/Transforms für Parkzaun, Wege-Muster, Wimpelketten, Konfetti,
## Ballon-Stand, Warteschlangen, Wiesen-Grün und die erweiterten
## Lichterketten. Gebaut wird alles von ParkDekoBau (MultiMesh/SurfaceTool,
## Draw-Call-Budget ≤ 400). Deterministisch über seed-Parameter.

## Zaun-Rechteck (Weltmeter) — die Wiese ist 64×56 um (0,-6); der Zaun
## bleibt ein Stück innerhalb, das Tor-Loch liegt an der Eingangsseite.
const ZAUN_MIN := Vector2(-30.0, -32.0)
const ZAUN_MAX := Vector2(30.0, 20.0)
const ZAUN_TOR_X := 5.0
const ZAUN_SCHRITT_M := 2.6

## Plaza-Wegmuster: Schachbrett-Platten auf dem 26×30-Weg um (0, 4).
const PLATTE_M := 2.0
const WEG_MITTE := Vector2(0.0, 4.0)
const WEG_HALB := Vector2(13.0, 15.0)

const KONFETTI_FARBEN: Array[Color] = [
	Color("#F781B0"),
	Color("#F2C14E"),
	Color("#9BD7E8"),
	Color("#8FD06C"),
	Color("#B58CE4"),
	Color("#E8524A"),
]

const WIMPEL_FARBEN: Array[Color] = [
	Color("#F781B0"), Color("#F2C14E"), Color("#9BD7E8"), Color("#8FD06C")
]

const BALLON_FARBEN: Array[Color] = [
	Color("#F781B0"),
	Color("#F2C14E"),
	Color("#9BD7E8"),
	Color("#8FD06C"),
	Color("#B58CE4"),
	Color("#E8524A"),
	Color("#FFD166"),
]

## Ballon-Stand neben dem Eingang (Wägelchen + Bündel + Verkäufer-Blob).
const BALLON_STAND := Vector3(5.6, 0.0, 13.2)

## Wimpelketten: Pfahl-zu-Pfahl über Plaza, Naschgasse und zur Arena.
const WIMPEL_KETTEN := [
	{"von": Vector3(-4.0, 4.3, 16.0), "bis": Vector3(-9.4, 3.1, 10.8)},
	{"von": Vector3(4.0, 4.3, 16.0), "bis": Vector3(10.0, 3.8, 2.4)},
	{"von": Vector3(-9.4, 3.1, 10.8), "bis": Vector3(0.2, 3.0, 9.6)},
	{"von": Vector3(10.0, 3.8, 2.4), "bis": Vector3(16.5, 2.6, 9.0)},
	{"von": Vector3(-16.0, 2.9, 4.0), "bis": Vector3(-9.4, 3.1, 10.8)},
]

## Warteschlangen (Pfosten-Reihen + Schild) vor Coaster-Station und Rad.
const SCHLANGEN := [
	{
		"posten":
		[
			Vector3(-3.6, 0.0, 1.6),
			Vector3(-4.8, 0.0, -0.2),
			Vector3(-6.0, 0.0, -2.0),
			Vector3(-7.2, 0.0, -3.8),
		],
		"schild": Vector3(-3.2, 0.0, 2.4),
	},
	{
		"posten": [Vector3(-10.6, 0.0, 4.4), Vector3(-12.4, 0.0, 2.8), Vector3(-14.2, 0.0, 1.2)],
		"schild": Vector3(-10.0, 0.0, 5.2),
	},
]

## Flanier-Punkte der Besucher-Blobs (deckt Plaza, Naschgasse, Rides ab).
const BESUCHER_PUNKTE: Array[Vector3] = [
	Vector3(-4.0, 0.0, 12.0),
	Vector3(4.5, 0.0, 8.0),
	Vector3(-9.0, 0.0, 6.5),
	Vector3(7.0, 0.0, 12.5),
	Vector3(-2.0, 0.0, 5.0),
	Vector3(11.0, 0.0, 7.0),
	Vector3(-6.5, 0.0, 13.5),
	Vector3(2.0, 0.0, 14.0),
	Vector3(-12.5, 0.0, 8.5),
	Vector3(13.5, 0.0, 11.0),
	Vector3(-1.5, 0.0, 9.0),
	Vector3(8.5, 0.0, 4.5),
]


## Zaun-Pfosten (Position) rund ums Parkgelände, Tor-Lücke am Eingang.
static func zaun_posten() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var breite := ZAUN_MAX.x - ZAUN_MIN.x
	var tiefe := ZAUN_MAX.y - ZAUN_MIN.y
	var n_x := int(breite / ZAUN_SCHRITT_M)
	var n_z := int(tiefe / ZAUN_SCHRITT_M)
	for i in n_x + 1:
		var x := ZAUN_MIN.x + breite * float(i) / float(n_x)
		out.append(Vector3(x, 0.0, ZAUN_MIN.y))
		if absf(x) > ZAUN_TOR_X:
			out.append(Vector3(x, 0.0, ZAUN_MAX.y))
	for i in range(1, n_z):
		var z := ZAUN_MIN.y + tiefe * float(i) / float(n_z)
		out.append(Vector3(ZAUN_MIN.x, 0.0, z))
		out.append(Vector3(ZAUN_MAX.x, 0.0, z))
	return out


## Zaun-Riegel: Transform je Nachbar-Paar — die Einheitsbox ist längs Z
## geauthort, also Z-Achse auf die Verbindung drehen und Z strecken.
static func zaun_riegel(posten: Array[Vector3]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in posten.size():
		for j in range(i + 1, posten.size()):
			var a := posten[i]
			var b := posten[j]
			var d := b - a
			if d.length() > ZAUN_SCHRITT_M * 1.3 or d.length() < 0.1:
				continue
			var mitte := (a + b) * 0.5 + Vector3(0.0, 0.62, 0.0)
			# LOKALE Z-Achse strecken (basis.scaled() skaliert global!).
			var basis := Basis(Vector3.UP, atan2(d.x, d.z))
			basis.z *= d.length()
			out.append(Transform3D(basis, mitte))
	return out


## Schachbrett-Platten des Plaza-Wegs: {pos, hell} — mit Fehlstellen-Jitter,
## damit das Muster handgelegt statt generiert wirkt.
static func weg_platten(seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	var n_x := int(WEG_HALB.x * 2.0 / PLATTE_M)
	var n_z := int(WEG_HALB.y * 2.0 / PLATTE_M)
	for ix in n_x:
		for iz in n_z:
			if rng.randf() < 0.08:
				continue
			var x := WEG_MITTE.x - WEG_HALB.x + (float(ix) + 0.5) * PLATTE_M
			var z := WEG_MITTE.y - WEG_HALB.y + (float(iz) + 0.5) * PLATTE_M
			out.append({"pos": Vector3(x, 0.02, z), "hell": (ix + iz) % 2 == 0})
	return out


## Wimpel-Dreiecke einer Kette: {pos, rot, farbe} — hängt mit leichtem
## Durchhang (Sinus-Bogen) zwischen den Endpunkten.
static func wimpel_dreiecke(kette: Dictionary, start_farbe: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var von: Vector3 = kette["von"]
	var bis: Vector3 = kette["bis"]
	var laenge := (bis - von).length()
	var anzahl := maxi(3, int(laenge / 0.85))
	# Yaw der Kettenrichtung — die Dreiecke hängen in der Ketten-Ebene.
	var rot := atan2(bis.x - von.x, bis.z - von.z)
	for i in anzahl:
		var t := (float(i) + 0.5) / float(anzahl)
		var pos := von.lerp(bis, t) + Vector3(0.0, -sin(t * PI) * laenge * 0.045, 0.0)
		(
			out
			. append(
				{
					"pos": pos,
					"rot": rot,
					"farbe": WIMPEL_FARBEN[(start_farbe + i) % WIMPEL_FARBEN.size()],
				}
			)
		)
	return out


## Alle Wimpel-Dreiecke aller Ketten (für EIN vertexgefärbtes Mesh).
static func alle_wimpel() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in WIMPEL_KETTEN.size():
		out.append_array(wimpel_dreiecke(WIMPEL_KETTEN[i], i))
	return out


## Konfetti-Tupfer auf Plaza + Naschgasse: {pos, farbe, rot}.
static func konfetti(seed_wert: int, anzahl := 90) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	for _i in anzahl:
		var pos := Vector3(
			WEG_MITTE.x + rng.randf_range(-WEG_HALB.x, WEG_HALB.x),
			0.045,
			WEG_MITTE.y + rng.randf_range(-WEG_HALB.y, WEG_HALB.y)
		)
		(
			out
			. append(
				{
					"pos": pos,
					"farbe": KONFETTI_FARBEN[rng.randi_range(0, KONFETTI_FARBEN.size() - 1)],
					"rot": rng.randf_range(0.0, TAU),
				}
			)
		)
	return out


## Ballon-Bündel am Stand: {off, farbe} — Trauben-Anordnung überm Wagen.
static func ballons(seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	for i in BALLON_FARBEN.size():
		var winkel := TAU * float(i) / float(BALLON_FARBEN.size())
		var radius := 0.42 + rng.randf_range(-0.08, 0.08)
		(
			out
			. append(
				{
					"off":
					Vector3(
						cos(winkel) * radius,
						2.5 + rng.randf_range(0.0, 0.5) + float(i % 2) * 0.3,
						sin(winkel) * radius
					),
					"farbe": BALLON_FARBEN[i],
				}
			)
		)
	return out


## Wiesen-Grün rund um die Plaza: {glb, pos, rot, scale} — Blumen/Gras aus
## dem Stadt-Naturkit, NIE auf dem Weg oder in den Fahrgeschäft-Zonen.
static func wiesen_gruen(seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	var pools: Array[String] = [
		"natur/flower_redA.glb",
		"natur/flower_yellowA.glb",
		"natur/flower_purpleA.glb",
		"natur/grass_large.glb",
	]
	var versuche := 0
	while out.size() < 26 and versuche < 200:
		versuche += 1
		var pos := Vector3(rng.randf_range(-29.0, 29.0), 0.0, rng.randf_range(-31.0, 19.0))
		if _liegt_frei(pos):
			continue
		(
			out
			. append(
				{
					"glb": pools[rng.randi_range(0, pools.size() - 1)],
					"pos": pos,
					"rot": rng.randf_range(0.0, TAU),
					"scale": rng.randf_range(2.0, 3.2),
				}
			)
		)
	return out


## Erweiterte Lichterketten-Punkte (Nacht): Portal, Naschgasse, Karussell-
## Ring, Arena-Ring und der Zaunbogen am Eingang.
static func lichter_punkte() -> Array[Vector3]:
	var punkte: Array[Vector3] = []
	for i in 14:
		var t := float(i) / 13.0
		punkte.append(Vector3(-4.2 + t * 8.4, 4.7 + sin(t * PI) * -0.35, 16.0))
	for i in 12:
		var t2 := float(i) / 11.0
		punkte.append(Vector3(-9.5 + t2 * 10.5, 3.1 + sin(t2 * 6.0) * 0.18, 10.6))
	# Karussell-Dachkranz (Mitte (10, 2), Radius 3.3).
	for i in 10:
		var w := TAU * float(i) / 10.0
		punkte.append(Vector3(10.0 + cos(w) * 3.3, 3.35, 2.0 + sin(w) * 3.3))
	# Autoscooter-Arena (Mitte (16.5, 9)).
	for i in 10:
		var w2 := TAU * float(i) / 10.0
		punkte.append(Vector3(16.5 + cos(w2) * 3.9, 2.5, 9.0 + sin(w2) * 3.1))
	# Wimpel-Pfahl-Linie längs des Eingangszauns.
	for i in 8:
		punkte.append(Vector3(-14.0 + float(i) * 4.0, 2.3, 19.6))
	return punkte


## true = Punkt kollidiert mit Weg/Fahrgeschäft (fürs Wiesen-Grün gesperrt).
static func _liegt_frei(pos: Vector3) -> bool:
	if (
		absf(pos.x - WEG_MITTE.x) < WEG_HALB.x + 1.0
		and absf(pos.z - WEG_MITTE.y) < WEG_HALB.y + 1.0
	):
		return true
	# Fahrgeschäft-Zonen: Coaster-Feld, Riesenrad, Karussell, Autoscooter.
	if pos.z < -8.0 and absf(pos.x - 2.0) < 22.0:
		return true
	if (pos - Vector3(-16.0, 0.0, 0.0)).length() < 6.0:
		return true
	if (pos - Vector3(10.0, 0.0, 2.0)).length() < 5.5:
		return true
	if absf(pos.x - 16.5) < 5.4 and absf(pos.z - 9.0) < 4.4:
		return true
	return false
