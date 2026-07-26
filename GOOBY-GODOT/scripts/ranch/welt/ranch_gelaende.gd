class_name RanchGelaende
extends RefCounted
## Höhenmodell der Ranch-Region (RW-1) — PURE + headless-testbar. Die Höhe
## ist eine deterministische Funktion von (x, z) + den Karten-Daten
## (RanchKarte): sanfte Grundhügel (Sinus-Oktaven, kein RNG), darüber
## Zonen-Features (Hügelkamm-Rücken, See-Senke, Weidetal-Mulde), dann
## Plateau-Glättung (Hof/Turnierplatz/Hufingen bleiben bebaubar-flach)
## und ZULETZT das eingeschnittene Bachbett (der Bach existiert immer).
##
## Vertrag für andere Agents (RW1-welt-api.md): `hoehe(x, z)` ist DIE
## Bodenhöhe für Reiter/Tiere/Gebäude; Wasser liegt bei WASSER_HOEHE.

## Wasserspiegel des SEES in Metern — muss zu ranch_karte.json passen.
const WASSER_HOEHE := -1.1

## Grundniveau der Wiesen: hebt das Land über den See-Wasserspiegel.
const BASIS_HOEHE := 3.0

## Plateau-Falloff: so viele Meter um eine flache Zone wird weich geblendet.
const PLATEAU_RAND_M := 60.0

## Furt: in diesem Radius um die Furt flacht das Bachbett zum Durchreiten ab.
const FURT_RADIUS_M := 14.0

## Ab dieser Kerbentiefe führt das Bachbett Wasser (Furt bleibt seichter).
const BACH_WASSER_AB_M := 0.9


## Bodenhöhe in Metern an Weltposition (x, z). Deterministisch.
static func hoehe(x: float, z: float) -> float:
	var karte := RanchKarte.karte()
	var h := BASIS_HOEHE + _grundhuegel(x, z)
	h += _zonen_features(x, z, karte)
	h = _plateaus(x, z, h, karte)
	h -= bach_kerbe(x, z)
	return h


## Oberflächen-Normale (zentrale Differenzen) — für Ausrichtung/Shading.
static func normale(x: float, z: float) -> Vector3:
	var e := 1.5
	var dx := hoehe(x + e, z) - hoehe(x - e, z)
	var dz := hoehe(x, z + e) - hoehe(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Führt die Position Wasser? See = unter dem Wasserspiegel; Bach = die
## Kerbe ist tief genug (die Furt bleibt seicht und damit begehbar).
static func ist_wasser(x: float, z: float) -> bool:
	if hoehe(x, z) < WASSER_HOEHE:
		return true
	return bach_kerbe(x, z) >= BACH_WASSER_AB_M


## Wasserspiegel des Bachs an (x, z): Bodenhöhe + Restkerbe bis knapp
## unter die Uferkante (fürs Platzieren der Wasserbänder in der Szene).
static func bach_wasserspiegel(x: float, z: float) -> float:
	return hoehe(x, z) + maxf(0.0, bach_kerbe(x, z) - 0.45)


## ------------------------------------------------------------ Bausteine


## Sanfte Grundhügel: zwei Sinus-Oktaven, Amplitude ~3 m — „kein flaches
## Brett“, aber reitbar ohne Klippen.
static func _grundhuegel(x: float, z: float) -> float:
	var a := sin(x * 0.011 + 1.7) * cos(z * 0.009 + 0.4) * 2.2
	var b := sin(x * 0.027 - 0.8) * sin(z * 0.023 + 2.1) * 0.9
	return a + b


static func _zonen_features(x: float, z: float, karte: Dictionary) -> float:
	var h := 0.0
	for zone: Dictionary in karte["zonen"]:
		match str(zone["id"]):
			"huegelkamm":
				h += _kamm(x, z, zone)
			"see":
				h += _see_senke(x, z, zone)
			"weidetal":
				h += _tal_mulde(x, z, zone)
	return h


## Hügelkamm: Gauß-Rücken entlang der Zonen-Mitte Richtung Aussichtspunkt.
static func _kamm(x: float, z: float, zone: Dictionary) -> float:
	var spitze: Array = zone["aussichtspunkt"]
	var fuss := Vector2(float(spitze[0]) - 140.0, float(spitze[1]) + 220.0)
	var kopf := Vector2(float(spitze[0]) + 120.0, float(spitze[1]) - 60.0)
	var d := _abstand_zu_strecke(Vector2(x, z), fuss, kopf)
	return 24.0 * exp(-pow(d / 130.0, 2.0))


## See: runde Senke — Ufer fällt weich ab, Mitte liegt ~4 m unter Wasser.
static func _see_senke(x: float, z: float, zone: Dictionary) -> float:
	var mitte: Array = zone["see_mitte"]
	var radius := float(zone["see_radius"])
	var d := Vector2(x, z).distance_to(Vector2(float(mitte[0]), float(mitte[1])))
	return -7.0 * exp(-pow(d / (radius * 0.9), 2.0))


## Weidetal: breite weiche Mulde in Zonenmitte (bleibt über Wasser).
static func _tal_mulde(x: float, z: float, zone: Dictionary) -> float:
	var rect := RanchKarte.zone_rect(zone)
	var mitte := rect.get_center()
	var d := Vector2(x, z).distance_to(mitte)
	return -3.2 * exp(-pow(d / 190.0, 2.0))


## Flache Bau-Zonen (Hof/Turnierplatz/Hufingen): Höhe wird im Rect auf die
## `hoehe_basis` der Zone gezogen, außen weich ausgeblendet.
static func _plateaus(x: float, z: float, h: float, karte: Dictionary) -> float:
	var out := h
	for zone: Dictionary in karte["zonen"]:
		var id := str(zone["id"])
		if id != "hof" and id != "turnierplatz" and id != "hufingen":
			continue
		var gewicht := _plateau_gewicht(Vector2(x, z), RanchKarte.zone_rect(zone))
		if gewicht > 0.0:
			out = lerpf(out, float(zone.get("hoehe_basis", 0.0)), gewicht)
	return out


## 1.0 im Rect, weicher Abfall über PLATEAU_RAND_M außen, 0.0 weiter weg.
static func _plateau_gewicht(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
	var d := Vector2(dx, dz).length()
	return clampf(1.0 - d / PLATEAU_RAND_M, 0.0, 1.0)


## Bachbett: entlang der Polyline wird `tiefe` eingekerbt (weiche Ränder);
## an der Furt flacht die Kerbe ab, damit Reiter/Tiere durchs Wasser können.
static func bach_kerbe(x: float, z: float) -> float:
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var p := Vector2(x, z)
	var d := _abstand_zu_polyline(p, bach["punkte"])
	var halb := float(bach["breite"]) / 2.0 + 2.0
	if d >= halb:
		return 0.0
	var tiefe := float(bach["tiefe"])
	var furt: Array = bach["furt"]
	var furt_d := p.distance_to(Vector2(float(furt[0]), float(furt[1])))
	if furt_d < FURT_RADIUS_M:
		tiefe = lerpf(0.55, tiefe, furt_d / FURT_RADIUS_M)
	var t := 1.0 - d / halb
	return tiefe * t * t * (3.0 - 2.0 * t)


## ------------------------------------------------------------- Geometrie


static func _abstand_zu_polyline(p: Vector2, punkte: Array) -> float:
	var best := INF
	for i in punkte.size() - 1:
		var a: Array = punkte[i]
		var b: Array = punkte[i + 1]
		var d := _abstand_zu_strecke(
			p, Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1]))
		)
		best = minf(best, d)
	return best


static func _abstand_zu_strecke(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var laenge2 := ab.length_squared()
	if laenge2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / laenge2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
