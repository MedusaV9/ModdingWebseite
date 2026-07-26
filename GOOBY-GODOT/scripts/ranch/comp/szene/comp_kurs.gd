class_name RcompKurs
extends RefCounted
## Kurs-Layouts der Wettbewerbe (RW-5) — PURE Geometrie, deterministisch
## (Seeds), damit Treiber UND Tests dieselben Kurse sehen. Koordinaten
## sind lokale Arena-Meter (Mitte am Ursprung, passend zu RcompArena).

const WSpringen := preload("res://scripts/ranch/comp/wertung/wertung_springen.gd")
const WGelaende := preload("res://scripts/ranch/comp/wertung/wertung_gelaende.gd")

## Sandplatz + erweitertes Reitfeld (== RcompArena, dupliziert um PURE
## zu bleiben — der Sync-Test sichert die Gleichheit).
const ARENA := Rect2(-30.0, -18.0, 60.0, 36.0)
const FELD := Rect2(-95.0, -70.0, 190.0, 140.0)

## Grasbahn-Oval: Geraden bei z = ±RENNEN_RZ, Halbkreise um (±RENNEN_RX, 0).
const RENNEN_RX := 26.0
const RENNEN_RZ := 16.0

## Tonnen-Kleeblatt (Kap. 5.2 Nr. 7): Start Süd, rechts → links → hinten.
const TONNEN_START := Vector3(0.0, 0.0, 13.0)
const TONNEN_POSITIONEN: Array[Vector3] = [
	Vector3(9.0, 0.0, -2.0), Vector3(-9.0, 0.0, -2.0), Vector3(0.0, 0.0, -13.0)
]

## Trail-Stationen (Kap. 5.2 Nr. 5): 6 Korridore im Sandplatz.
## breite = halbe lichte Weite; sauber hindurch = volle Punkte.
const TRAIL_STATIONEN: Array[Dictionary] = [
	{"id": "tor", "pos": Vector3(-20.0, 0.0, 8.0), "winkel": 0.0, "breite": 1.6},
	{"id": "rueckwaerts_l", "pos": Vector3(-10.0, 0.0, -8.0), "winkel": 0.9, "breite": 1.3},
	{"id": "slalom", "pos": Vector3(0.0, 0.0, 8.0), "winkel": 0.0, "breite": 1.1},
	{"id": "bruecke", "pos": Vector3(10.0, 0.0, -8.0), "winkel": -0.9, "breite": 1.4},
	{"id": "plane", "pos": Vector3(20.0, 0.0, 8.0), "winkel": 0.0, "breite": 1.6},
	{"id": "kreisel", "pos": Vector3(0.0, 0.0, 0.0), "winkel": 0.5, "breite": 1.2},
]
const TRAIL_LAENGE_M := 6.0


## Springparcours: Hindernisse in Schlangenlinien-Reihen durch den
## Sandplatz. → [{pos, quer (Querachse des Hindernisses), heading}].
static func springen(klasse: String) -> Array[Dictionary]:
	var anzahl := WSpringen.hindernis_anzahl(klasse)
	var reihen := 3
	var je_reihe := int(ceil(float(anzahl) / reihen))
	var kurs: Array[Dictionary] = []
	for i in anzahl:
		var reihe := i / je_reihe
		var spalte := i % je_reihe
		var links_nach_rechts := reihe % 2 == 0
		var t := (float(spalte) + 0.5) / je_reihe
		var x := lerpf(-22.0, 22.0, t if links_nach_rechts else 1.0 - t)
		var z := lerpf(11.0, -11.0, float(reihe) / maxf(1.0, reihen - 1.0))
		# RideController-Konvention: Fahrtrichtung = −(sin h, cos h).
		var heading := -PI * 0.5 if links_nach_rechts else PI * 0.5
		(
			kurs
			. append(
				{
					"pos": Vector3(x, 0.0, z),
					"quer": Vector3(0.0, 0.0, 1.0),
					"heading": heading,
				}
			)
		)
	return kurs


## Geländeritt: Flaggentore auf einer Ellipse über die Wiese (leichtes
## Zittern aus dem Seed). → [{pos, quer}]; Start/Ziel am Südtor der Arena.
static func gelaende(klasse: String, seed_wert: int) -> Array[Dictionary]:
	var anzahl := WGelaende.tor_anzahl(klasse)
	var rng := GoobyRng.new(seed_wert)
	var tore: Array[Dictionary] = []
	for i in anzahl:
		var winkel := TAU * (float(i) + 0.5) / anzahl + PI * 0.5
		var rx := 66.0 + rng.next() * 18.0
		var rz := 44.0 + rng.next() * 12.0
		var pos := Vector3(cos(winkel) * rx, 0.0, sin(winkel) * rz)
		var tangente := Vector3(-sin(winkel) * rx, 0.0, cos(winkel) * rz).normalized()
		var quer := Vector3(-tangente.z, 0.0, tangente.x)
		tore.append({"pos": pos, "quer": quer})
	return tore


## Zeitrennen (Arcade): Zickzack-Tore vom Süd- zum Nordrand des Felds.
static func zeit_route(level: int, seed_wert: int) -> Array[Dictionary]:
	var anzahl := clampi(6 + level, 7, 16)
	var rng := GoobyRng.new(seed_wert + level * 977)
	var tore: Array[Dictionary] = []
	var vorher := Vector3(0.0, 0.0, 58.0)
	for i in anzahl:
		var t := (float(i) + 1.0) / anzahl
		var x := (rng.next() * 2.0 - 1.0) * (26.0 + 26.0 * t)
		var z := lerpf(44.0, -58.0, t)
		var pos := Vector3(x, 0.0, z)
		var tangente := (pos - vorher).normalized()
		var quer := Vector3(-tangente.z, 0.0, tangente.x)
		tore.append({"pos": pos, "quer": quer})
		vorher = pos
	return tore


## Grasbahn-Oval: Punkt bei Bogenlänge s (m, gegen den Uhrzeigersinn,
## Start = Mitte der Süd-Geraden bei (0, +RENNEN_RZ)).
static func rennen_umfang() -> float:
	return 4.0 * RENNEN_RX + TAU * RENNEN_RZ


static func rennen_punkt(s: float) -> Vector3:
	var u := fposmod(s, rennen_umfang())
	var gerade := 2.0 * RENNEN_RX
	var bogen := PI * RENNEN_RZ
	if u < gerade * 0.5:
		return Vector3(u, 0.0, RENNEN_RZ)
	u -= gerade * 0.5
	if u < bogen:
		var w := u / RENNEN_RZ
		return Vector3(RENNEN_RX + sin(w) * RENNEN_RZ, 0.0, cos(w) * RENNEN_RZ)
	u -= bogen
	if u < gerade:
		return Vector3(RENNEN_RX - u, 0.0, -RENNEN_RZ)
	u -= gerade
	if u < bogen:
		var w := u / RENNEN_RZ
		return Vector3(-RENNEN_RX - sin(w) * RENNEN_RZ, 0.0, -cos(w) * RENNEN_RZ)
	u -= bogen
	return Vector3(-RENNEN_RX + u, 0.0, RENNEN_RZ)


## Bahn-Bogenlänge (s), die einer Weltposition am nächsten liegt —
## grob über Abtastung (für Runden-/Windschatten-Logik völlig genug).
static func rennen_s_bei(pos: Vector3, schritt := 1.0) -> float:
	var beste_s := 0.0
	var beste_d := INF
	var s := 0.0
	var umfang := rennen_umfang()
	while s < umfang:
		var d := rennen_punkt(s).distance_squared_to(pos)
		if d < beste_d:
			beste_d = d
			beste_s = s
		s += schritt
	return beste_s


## Dressur-Programm (Kap. 5.2 Nr. 2): 5 Figuren mit Soll-Gangart und
## Wegpunkten (in Reihenfolge zu beruehren, Toleranz beim Treiber).
static func dressur_figuren() -> Array[Dictionary]:
	var figuren: Array[Dictionary] = []
	var zirkel: Array = []
	for i in 10:
		var w := TAU * i / 10.0
		zirkel.append(Vector3(cos(w) * 9.0, 0.0, sin(w) * 9.0))
	figuren.append({"id": "zirkel", "gangart": "trab", "punkte": zirkel})
	var acht: Array = []
	for i in 8:
		var w := TAU * i / 8.0
		acht.append(Vector3(-8.0 + cos(w) * 6.0, 0.0, sin(w) * 6.0))
	for i in 8:
		var w := PI - TAU * i / 8.0
		acht.append(Vector3(8.0 + cos(w) * 6.0, 0.0, sin(w) * 6.0))
	figuren.append({"id": "acht", "gangart": "trab", "punkte": acht})
	var schlange: Array = []
	for i in 9:
		var t := float(i) / 8.0
		schlange.append(Vector3(lerpf(-20.0, 20.0, t), 0.0, sin(t * PI * 3.0) * 8.0))
	figuren.append({"id": "schlangenlinie", "gangart": "galopp", "punkte": schlange})
	(
		figuren
		. append(
			{
				"id": "halten",
				"gangart": "schritt",
				"punkte": [Vector3(20.0, 0.0, 8.0), Vector3(8.0, 0.0, 12.0)],
			}
		)
	)
	(
		figuren
		. append(
			{
				"id": "rueckwaerts",
				"gangart": "schritt",
				"punkte": [Vector3(-4.0, 0.0, 12.0), Vector3(-16.0, 0.0, 12.0)],
			}
		)
	)
	return figuren


## Abstand eines Punkts zur Strecke a→b (Ideallinien-Abweichung).
static func abstand_zur_strecke(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var laenge2 := ab.length_squared()
	if laenge2 <= 0.0001:
		return ap.length()
	var t := clampf(ap.dot(ab) / laenge2, 0.0, 1.0)
	return (ap - ab * t).length()


## Hat die Strecke vorher→jetzt die Tor-Ebene (pos, quer) durchquert
## UND lag der Schnitt innerhalb der halben Breite?
static func tor_durchritten(
	vorher: Vector3, jetzt: Vector3, pos: Vector3, quer: Vector3, halbe_breite: float
) -> bool:
	var normale := Vector2(-quer.z, quer.x)
	var a := Vector2(vorher.x - pos.x, vorher.z - pos.z)
	var b := Vector2(jetzt.x - pos.x, jetzt.z - pos.z)
	var da := a.dot(normale)
	var db := b.dot(normale)
	if da == 0.0 and db == 0.0:
		return false
	if (da < 0.0) == (db < 0.0):
		return false
	var t := da / (da - db)
	var schnitt := a.lerp(b, t)
	return absf(schnitt.dot(Vector2(quer.x, quer.z))) <= halbe_breite
