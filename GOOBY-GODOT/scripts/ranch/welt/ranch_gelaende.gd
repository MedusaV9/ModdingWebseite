class_name RanchGelaende
extends RefCounted
## Höhenmodell der Ranch-Region (RW-1, massiv ausgebaut von WELT-1) — PURE +
## headless-testbar. Die Höhe ist eine deterministische Funktion von (x, z) +
## den Karten-Daten (RanchKarte), aufgebaut als MEHRSTUFIGES Rauschen:
##
##   1. GROSSFORMEN  (~700-m-Wellen, ±6,5 m) — nur außerhalb des alten
##      Kern-Rechtecks eingeblendet, damit Bestandszonen stabil bleiben.
##   2. GRUNDHÜGEL   (~100-m-Wellen, ±3 m) — Bestand.
##   3. ZONEN-FEATURES — Hügelkamm-Rücken, See-Senke, Weidetal-Mulde,
##      BERGMASSIV (drei Gauß-Grate bis ~90 m + Vorberg-Sattel), Ruinen-
##      Hügel, Strand-Bucht, Moor-Wanne.
##   4. FEINSTRUKTUR (FB-2: Bodenwellen + Unebenheit, auf Wegen geglättet).
##   5. PLATEAUS     — Hof/Turnierplatz/Hufingen (Rect) + Berg-PLATEAU
##      (radial, Rundumblick + Bergsee-Senke).
##   6. MOOR-PFANNEN (weiche Klammer auf ~-0,4 m + Tümpel-Dellen),
##      GLOBALER BODEN (nichts fällt versehentlich unter den Wasserspiegel),
##      WELTRAND-BLENDE (Gelände läuft weich in die Fernwiese aus).
##   7. KERBEN       — Bachbett (Furt bleibt flach) + SCHLUCHT (13 m tief,
##      die Hängebrücke quert sie — reit_hoehe kennt das Brückendeck).
##
## Vertrag für andere Agents (RW1-welt-api.md): `hoehe(x, z)` ist DIE
## Bodenhöhe für Reiter/Tiere/Gebäude; `reit_hoehe(x, z)` liegt darüber,
## wo ein Brückendeck (Karte `bruecken`) die Schlucht quert. Wasser liegt
## bei WASSER_HOEHE (See/Bucht), im Bachbett und im BERGSEE (eigener
## Spiegel auf Plateau-Höhe).

## Wasserspiegel von SEE und STRAND-BUCHT in Metern (ranch_karte.json).
const WASSER_HOEHE := -1.1

## Grundniveau der Wiesen: hebt das Land über den See-Wasserspiegel.
const BASIS_HOEHE := 3.0

## Plateau-Falloff: so viele Meter um eine flache Zone wird weich geblendet.
const PLATEAU_RAND_M := 60.0

## Furt: in diesem Radius um die Furt flacht das Bachbett zum Durchreiten ab.
const FURT_RADIUS_M := 14.0

## Ab dieser Kerbentiefe führt das Bachbett Wasser (Furt bleibt seichter).
const BACH_WASSER_AB_M := 0.9

## Feinstruktur-Grenzen (FB-2): Bodenwellen ±0,4 m + Rauigkeit ±0,2 m.
const FEIN_MAX_M := 0.62

## Wege bleiben glatt reitbar: so viele Meter neben der Wegkante blendet
## die Feinstruktur weich wieder ein.
const WEG_GLAETT_RAND_M := 5.0

## Rest-Feinstruktur AUF dem Weg (kleine Unebenheit bleibt spürbar).
const WEG_REST_ANTEIL := 0.15

## Altes Kern-Rechteck (Welt vor dem Ausbau): hier bleiben die Großformen
## draußen, damit Bestandszonen/-tests ihr Profil behalten.
const KERN_RECT := Rect2(-700.0, -650.0, 1400.0, 1300.0)

## Großformen: Rampe (m) bis zur vollen Amplitude außerhalb des Kerns.
const GROSSFORM_RAMPE_M := 240.0
const GROSSFORM_AMP_M := 6.5

## Weltrand: über diese Breite läuft das Gelände in die Fernwiese aus.
const RAND_BLENDE_M := 80.0
const RAND_ZIEL_M := 1.2

## Globaler Boden außerhalb der Gewässer (knapp ÜBER dem Wasserspiegel).
const BODEN_MIN_M := -1.02

## Moor: weiche Pfannen-Klammer + Tümpel-Dellen.
const MOOR_PFANNE_M := -0.4
const MOOR_WANNE_M := 2.4
const TUEMPEL_ZIEL_M := -0.85
const TUEMPEL_RADIUS_M := 10.0

## Bergmassiv-Grate: [fuss, kopf, amplitude, breite] (deterministisch).
const BERG_GRATE: Array[Array] = [
	[-280.0, -1050.0, 140.0, -1120.0, 88.0, 150.0],
	[180.0, -1040.0, 340.0, -950.0, 48.0, 120.0],
	[-330.0, -950.0, -180.0, -850.0, 36.0, 110.0],
]

## Vorberg-Sattel: sanfter Anstieg vom Hügelkamm zum Massiv.
const VORBERG := [100.0, -745.0, 14.0, 130.0]

## Brückendeck: so hoch liegen die Planken über den Anker-Böden.
const DECK_HOEHE_M := 0.3

static var _weg_cache: Array[Dictionary] = []
static var _deck_cache: Array[Dictionary] = []


## Bodenhöhe in Metern an Weltposition (x, z). Deterministisch.
static func hoehe(x: float, z: float) -> float:
	var karte := RanchKarte.karte()
	var h := BASIS_HOEHE + _grundhuegel(x, z) + _grossformen(x, z)
	h += _zonen_features(x, z, karte)
	h += feinstruktur(x, z)
	h = _plateaus(x, z, h, karte)
	h = _moor_pfannen(x, z, h, karte)
	h = _boden_und_rand(x, z, h, karte)
	h -= bach_kerbe(x, z)
	h -= schlucht_kerbe(x, z)
	return h


## Reit-Höhe: wie `hoehe`, aber Brückendecks (Karte `bruecken`) tragen —
## der Reiter quert die Schlucht auf der Hängebrücke statt hindurchzufallen.
static func reit_hoehe(x: float, z: float) -> float:
	var h := hoehe(x, z)
	var p := Vector2(x, z)
	for deck: Dictionary in _decks():
		if (
			p.x < float(deck["min_x"])
			or p.x > float(deck["max_x"])
			or p.y < float(deck["min_z"])
			or p.y > float(deck["max_z"])
		):
			continue
		var a: Vector2 = deck["a"]
		var b: Vector2 = deck["b"]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) > float(deck["halb"]):
			continue
		var deck_y := lerpf(float(deck["ya"]), float(deck["yb"]), t) + DECK_HOEHE_M
		# Leichter Durchhang in der Mitte — Hängebrücke, kein Steg.
		deck_y -= sin(t * PI) * 0.55
		h = maxf(h, deck_y)
	return h


## Test-Hook: Caches verwerfen (nach RanchKarte.reset_for_tests).
static func reset_for_tests() -> void:
	_weg_cache = []
	_deck_cache = []


## Feinstruktur (FB-2 „der Boden ist zu glatt"): sanfte Bodenwellen
## (~30 m) + kleine Unebenheiten (~10 m), deterministisch aus Sinus-
## Oktaven. Auf Karten-Wegen stark gedämpft (weg_glaettung), damit
## Feldwege glatt reitbar bleiben; die Plateau-Glättung downstream hält
## Bau-Zonen flach.
static func feinstruktur(x: float, z: float) -> float:
	var wellen := sin(x * 0.19 + sin(z * 0.23) * 1.3) * sin(z * 0.17 - sin(x * 0.13) * 1.1) * 0.4
	var rau := sin(x * 0.53 + 2.3) * cos(z * 0.47 - 0.8) * 0.14
	rau += sin((x + z) * 0.71 + 1.1) * 0.08
	return (wellen + rau) * weg_glaettung(x, z)


## Dämpfungsfaktor der Feinstruktur: WEG_REST_ANTEIL auf dem Weg, 1.0 im
## freien Land, weiche Rampe über WEG_GLAETT_RAND_M neben der Wegkante.
static func weg_glaettung(x: float, z: float) -> float:
	var faktor := 1.0
	for segment: Dictionary in _weg_segmente():
		if (
			x < float(segment["min_x"])
			or x > float(segment["max_x"])
			or z < float(segment["min_z"])
			or z > float(segment["max_z"])
		):
			continue
		var d := _abstand_zu_strecke(Vector2(x, z), segment["a"], segment["b"])
		var halb := float(segment["halb"])
		if d >= halb + WEG_GLAETT_RAND_M:
			continue
		var t := clampf((d - halb) / WEG_GLAETT_RAND_M, 0.0, 1.0)
		faktor = minf(faktor, lerpf(WEG_REST_ANTEIL, 1.0, t * t * (3.0 - 2.0 * t)))
	return faktor


## Oberflächen-Normale (zentrale Differenzen) — für Ausrichtung/Shading.
static func normale(x: float, z: float) -> Vector3:
	var e := 1.5
	var dx := hoehe(x + e, z) - hoehe(x - e, z)
	var dz := hoehe(x, z + e) - hoehe(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Führt die Position Wasser? See/Bucht = unter dem Wasserspiegel; Bach =
## die Kerbe ist tief genug (die Furt bleibt seicht und damit begehbar);
## Bergsee = eigener Spiegel auf Plateau-Höhe.
static func ist_wasser(x: float, z: float) -> bool:
	if hoehe(x, z) < WASSER_HOEHE:
		return true
	if bach_kerbe(x, z) >= BACH_WASSER_AB_M:
		return true
	var berg := RanchKarte.zone("bergmassiv")
	if not berg.is_empty():
		var mitte: Array = berg["bergsee_mitte"]
		var d := Vector2(x, z).distance_to(Vector2(float(mitte[0]), float(mitte[1])))
		if d < float(berg["bergsee_radius"]) * 1.6:
			return hoehe(x, z) < float(berg["bergsee_wasser"])
	return false


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


## Großformen (~700-m-Wellen): geben der ERWEITERTEN Welt echtes
## Höhenspiel; im alten Kern-Rechteck bleiben sie ausgeblendet.
static func _grossformen(x: float, z: float) -> float:
	var maske := grossform_maske(x, z)
	if maske <= 0.0:
		return 0.0
	var a := sin(x * 0.004 + 2.1) * cos(z * 0.0035 - 1.3)
	var b := 0.4 * sin((x + z) * 0.006 - 0.5)
	return (a + b) * GROSSFORM_AMP_M * maske


## 0 im alten Kern, weiche Rampe auf 1 über GROSSFORM_RAMPE_M außerhalb —
## PURE, damit Tests die Ausblendung prüfen können.
static func grossform_maske(x: float, z: float) -> float:
	var dx := maxf(maxf(KERN_RECT.position.x - x, x - KERN_RECT.end.x), 0.0)
	var dz := maxf(maxf(KERN_RECT.position.y - z, z - KERN_RECT.end.y), 0.0)
	var d := Vector2(dx, dz).length()
	if d <= 0.0:
		return 0.0
	var t := clampf(d / GROSSFORM_RAMPE_M, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


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
			"bergmassiv":
				h += _bergmassiv(x, z)
			"ruine":
				h += _ruinen_huegel(x, z, zone)
			"strand":
				h += _bucht_senke(x, z, zone)
			"moor":
				h += _moor_wanne(x, z, zone)
	return h


## Hügelkamm: Gauß-Rücken entlang der Zonen-Mitte Richtung Aussichtspunkt.
static func _kamm(x: float, z: float, zone: Dictionary) -> float:
	var spitze: Array = zone["aussichtspunkt"]
	var fuss := Vector2(float(spitze[0]) - 140.0, float(spitze[1]) + 220.0)
	var kopf := Vector2(float(spitze[0]) + 120.0, float(spitze[1]) - 60.0)
	var d := _abstand_zu_strecke(Vector2(x, z), fuss, kopf)
	return 24.0 * exp(-pow(d / 130.0, 2.0))


## Bergmassiv: drei Gauß-Grate (Hauptgrat ~90 m + zwei Schultern) und der
## Vorberg-Sattel, der den Aufstieg vom Hügelkamm anbindet.
static func _bergmassiv(x: float, z: float) -> float:
	# Früher Ausstieg: südlich von z = -560 hat das Massiv keinen Einfluss
	# mehr (hoehe() läuft beim Chunk-Bau zehntausendfach).
	if z > -560.0:
		return 0.0
	var p := Vector2(x, z)
	var h := 0.0
	for grat: Array in BERG_GRATE:
		var d := _abstand_zu_strecke(
			p, Vector2(float(grat[0]), float(grat[1])), Vector2(float(grat[2]), float(grat[3]))
		)
		h += float(grat[4]) * exp(-pow(d / float(grat[5]), 2.0))
	var vd := p.distance_to(Vector2(float(VORBERG[0]), float(VORBERG[1])))
	h += float(VORBERG[2]) * exp(-pow(vd / float(VORBERG[3]), 2.0))
	return h


## See: runde Senke — Ufer fällt weich ab, Mitte liegt ~4 m unter Wasser.
static func _see_senke(x: float, z: float, zone: Dictionary) -> float:
	var mitte: Array = zone["see_mitte"]
	var radius := float(zone["see_radius"])
	var d := Vector2(x, z).distance_to(Vector2(float(mitte[0]), float(mitte[1])))
	return -7.0 * exp(-pow(d / (radius * 0.9), 2.0))


## Strand-Bucht: Lagunen-Senke am Ostrand — Mitte unter Wasser, weicher
## Sandsaum außen.
static func _bucht_senke(x: float, z: float, zone: Dictionary) -> float:
	var mitte: Array = zone["bucht_mitte"]
	var radius := float(zone["bucht_radius"])
	var d := Vector2(x, z).distance_to(Vector2(float(mitte[0]), float(mitte[1])))
	return -8.0 * exp(-pow(d / (radius * 0.9), 2.0))


## Ruine: runder Sagen-Hügel — der alte Turm bekommt seinen Aussichtsplatz.
static func _ruinen_huegel(x: float, z: float, zone: Dictionary) -> float:
	var turm: Array = zone["turm"]
	var d := Vector2(x, z).distance_to(Vector2(float(turm[0]), float(turm[1])))
	return 14.0 * exp(-pow(d / 120.0, 2.0))


## Moor: flache Wanne über das Zonen-Rechteck (innen voll, 45-m-Saum).
static func _moor_wanne(x: float, z: float, zone: Dictionary) -> float:
	var rect := RanchKarte.zone_rect(zone)
	if not rect.grow(0.0).has_point(Vector2(x, z)):
		return 0.0
	var tiefe_x := minf(x - rect.position.x, rect.end.x - x)
	var tiefe_z := minf(z - rect.position.y, rect.end.y - z)
	var w := clampf(minf(tiefe_x, tiefe_z) / 45.0, 0.0, 1.0)
	return -MOOR_WANNE_M * w * w * (3.0 - 2.0 * w)


## Weidetal: breite weiche Mulde in Zonenmitte (bleibt über Wasser).
static func _tal_mulde(x: float, z: float, zone: Dictionary) -> float:
	var rect := RanchKarte.zone_rect(zone)
	var mitte := rect.get_center()
	var d := Vector2(x, z).distance_to(mitte)
	return -3.2 * exp(-pow(d / 190.0, 2.0))


## Flache Bau-Zonen (Hof/Turnierplatz/Hufingen): Höhe wird im Rect auf die
## `hoehe_basis` der Zone gezogen, außen weich ausgeblendet. Das BERG-
## PLATEAU zieht radial auf Plateau-Höhe und senkt danach den BERGSEE ein.
static func _plateaus(x: float, z: float, h: float, karte: Dictionary) -> float:
	var out := h
	for zone: Dictionary in karte["zonen"]:
		var id := str(zone["id"])
		if id == "hof" or id == "turnierplatz" or id == "hufingen":
			var gewicht := _plateau_gewicht(Vector2(x, z), RanchKarte.zone_rect(zone))
			if gewicht > 0.0:
				out = lerpf(out, float(zone.get("hoehe_basis", 0.0)), gewicht)
		elif id == "bergmassiv":
			out = _berg_plateau(x, z, out, zone)
	return out


## Berg-Plateau: radiale Glättung auf Plateau-Höhe (Rundumblick), dann die
## Bergsee-Senke — der See liegt IM Plateau, sein Spiegel knapp darunter.
static func _berg_plateau(x: float, z: float, h: float, zone: Dictionary) -> float:
	var mitte: Array = zone["plateau_mitte"]
	var p := Vector2(x, z)
	var d := p.distance_to(Vector2(float(mitte[0]), float(mitte[1])))
	var radius := float(zone["plateau_radius"])
	var out := h
	if d < radius + PLATEAU_RAND_M:
		var t := clampf((d - radius) / PLATEAU_RAND_M, 0.0, 1.0)
		var gewicht := 1.0 - t * t * (3.0 - 2.0 * t)
		out = lerpf(out, float(zone.get("hoehe_basis", 62.0)), gewicht)
	var see: Array = zone["bergsee_mitte"]
	var sd := p.distance_to(Vector2(float(see[0]), float(see[1])))
	if sd < float(zone["bergsee_radius"]) * 2.4:
		out -= 6.5 * exp(-pow(sd / 22.0, 2.0))
	return out


## 1.0 im Rect, weicher Abfall über PLATEAU_RAND_M außen, 0.0 weiter weg.
static func _plateau_gewicht(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
	var d := Vector2(dx, dz).length()
	return clampf(1.0 - d / PLATEAU_RAND_M, 0.0, 1.0)


## Moor-Pfannen: unterhalb der Pfannen-Höhe wird weich geklammert (nasse,
## fast ebene Flächen), die Tümpel ZIEHEN das Gelände auf TUEMPEL_ZIEL_M
## (unter die Wasser-Scheiben bei -0,66 m, aber ÜBER dem echten Wasser-
## spiegel — seicht genug zum Durchwaten, KEIN Blockier-Wasser).
static func _moor_pfannen(x: float, z: float, h: float, karte: Dictionary) -> float:
	var moor := {}
	for zone: Dictionary in karte["zonen"]:
		if str(zone["id"]) == "moor":
			moor = zone
			break
	if moor.is_empty() or not RanchKarte.zone_rect(moor).has_point(Vector2(x, z)):
		return h
	var out := h
	if out < MOOR_PFANNE_M:
		out = MOOR_PFANNE_M - (MOOR_PFANNE_M - out) * 0.12
	for paar: Array in moor["tuempel"]:
		var d := Vector2(x, z).distance_to(Vector2(float(paar[0]), float(paar[1])))
		if d < TUEMPEL_RADIUS_M * 3.0:
			var g := exp(-pow(d / TUEMPEL_RADIUS_M, 2.0))
			out = lerpf(out, TUEMPEL_ZIEL_M, clampf(g * 1.2, 0.0, 1.0))
	return out


## Globaler Boden + Weltrand: außerhalb der echten Gewässer fällt nichts
## unter BODEN_MIN_M, und zum Kartenrand läuft das Land weich auf die
## Fernwiesen-Höhe aus (kein sichtbarer Weltrand-Sprung).
static func _boden_und_rand(x: float, z: float, h: float, karte: Dictionary) -> float:
	var out := h
	var p := Vector2(x, z)
	if out < BODEN_MIN_M and not _in_gewaesser_senke(p, karte):
		out = BODEN_MIN_M
	var grenzen := RanchKarte.grenzen()
	var rand := minf(
		minf(p.x - grenzen.position.x, grenzen.end.x - p.x),
		minf(p.y - grenzen.position.y, grenzen.end.y - p.y)
	)
	if rand < RAND_BLENDE_M:
		var t := clampf(rand / RAND_BLENDE_M, 0.0, 1.0)
		out = lerpf(RAND_ZIEL_M, out, t * t * (3.0 - 2.0 * t))
	return out


static func _in_gewaesser_senke(p: Vector2, karte: Dictionary) -> bool:
	for zone: Dictionary in karte["zonen"]:
		match str(zone["id"]):
			"see":
				var mitte: Array = zone["see_mitte"]
				if p.distance_to(Vector2(float(mitte[0]), float(mitte[1]))) < 220.0:
					return true
			"strand":
				var bucht: Array = zone["bucht_mitte"]
				if p.distance_to(Vector2(float(bucht[0]), float(bucht[1]))) < 160.0:
					return true
	return false


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


## Schlucht am Bergmassiv: tiefe Kerbe entlang der Karten-Polyline mit
## FELS-Steilwänden (steilere Rampe als das Bachbett — echte Wände).
static func schlucht_kerbe(x: float, z: float) -> float:
	var karte := RanchKarte.karte()
	if not karte.has("schlucht"):
		return 0.0
	if z > -560.0:
		return 0.0
	var schlucht: Dictionary = karte["schlucht"]
	var p := Vector2(x, z)
	var d := _abstand_zu_polyline(p, schlucht["punkte"])
	var halb := float(schlucht["breite"]) / 2.0 + 2.0
	if d >= halb:
		return 0.0
	var t := 1.0 - d / halb
	# Steilere S-Rampe: Wände fallen schnell, Sohle bleibt breit begehbar.
	var wand := clampf(t * 1.55, 0.0, 1.0)
	return float(schlucht["tiefe"]) * wand * wand * (3.0 - 2.0 * wand)


## ------------------------------------------------------------- Geometrie


## Karten-Wege als flache Segment-Liste mit AABB (gecacht — hoehe() läuft
## beim Chunk-Bau zehntausendfach; ohne Cache würde jeder Aufruf die
## JSON-Arrays neu parsen).
static func _weg_segmente() -> Array[Dictionary]:
	if not _weg_cache.is_empty():
		return _weg_cache
	for weg: Dictionary in RanchKarte.wege():
		var halb := float(weg.get("breite", 4.0)) / 2.0 + 1.0
		var rand := halb + WEG_GLAETT_RAND_M
		var punkte: Array = weg["punkte"]
		for i in punkte.size() - 1:
			var a: Array = punkte[i]
			var b: Array = punkte[i + 1]
			var av := Vector2(float(a[0]), float(a[1]))
			var bv := Vector2(float(b[0]), float(b[1]))
			(
				_weg_cache
				. append(
					{
						"a": av,
						"b": bv,
						"halb": halb,
						"min_x": minf(av.x, bv.x) - rand,
						"max_x": maxf(av.x, bv.x) + rand,
						"min_z": minf(av.y, bv.y) - rand,
						"max_z": maxf(av.y, bv.y) + rand,
					}
				)
			)
	return _weg_cache


## Brückendecks der Karte (gecacht, inkl. Anker-Bodenhöhen).
static func _decks() -> Array[Dictionary]:
	if not _deck_cache.is_empty():
		return _deck_cache
	var karte := RanchKarte.karte()
	for eintrag: Dictionary in karte.get("bruecken", []):
		var a: Array = eintrag["a"]
		var b: Array = eintrag["b"]
		var av := Vector2(float(a[0]), float(a[1]))
		var bv := Vector2(float(b[0]), float(b[1]))
		var halb := float(eintrag.get("breite", 4.0)) / 2.0
		(
			_deck_cache
			. append(
				{
					"a": av,
					"b": bv,
					"halb": halb,
					"ya": hoehe(av.x, av.y),
					"yb": hoehe(bv.x, bv.y),
					"min_x": minf(av.x, bv.x) - halb,
					"max_x": maxf(av.x, bv.x) + halb,
					"min_z": minf(av.y, bv.y) - halb,
					"max_z": maxf(av.y, bv.y) + halb,
				}
			)
		)
	return _deck_cache


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
