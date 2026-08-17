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
##
## W19-Perf: Karten-Geometrie (Zonen-Features, Plateaus, Bach/Schlucht/
## Wege-Segmente) wird EINMAL in getypte Deskriptoren übersetzt (statt
## JSON-Dictionaries pro Aufruf zu scannen) — hoehe() läuft beim Chunk-Bau
## hunderttausendfach. Die Mathematik (Reihenfolge, Formeln, Vector2-
## Präzision) bleibt EXAKT die des Direktwegs — bit-identische Höhen.

## Zonen-Feature-Typen des Geo-Caches (Reihenfolge = Karten-Reihenfolge).
enum Feature { KAMM, SEE, TAL, BERG, RUINE, BUCHT, MOOR }

## Plateau-Typen des Geo-Caches.
enum Plateau { RECT, BERG }

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

## Sicherheits-Marge der Segment-AABBs (m) — großzügig, damit der
## Schnellverwurf NIE ein Segment ausschließt, das das Ergebnis trägt.
const AABB_MARGE_M := 1.0

static var _geo_cache: Dictionary = {}
static var _wege_cache: Strecken = null
static var _deck_cache: Array[Dictionary] = []


## Karten-Wege/Bänder als flache Segment-Arrays mit AABB-Schnellverwurf —
## die Distanz-Mathematik bleibt Vector2-exakt wie im Direktweg.
class Strecken:
	extends RefCounted
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	var halb := PackedFloat64Array()
	var min_x := PackedFloat64Array()
	var max_x := PackedFloat64Array()
	var min_z := PackedFloat64Array()
	var max_z := PackedFloat64Array()

	func fuege_hinzu(von: Vector2, bis: Vector2, halb_wert: float, rand: float) -> void:
		a.append(von)
		b.append(bis)
		halb.append(halb_wert)
		min_x.append(minf(von.x, bis.x) - rand)
		max_x.append(maxf(von.x, bis.x) + rand)
		min_z.append(minf(von.y, bis.y) - rand)
		max_z.append(maxf(von.y, bis.y) + rand)


## Bodenhöhe in Metern an Weltposition (x, z). Deterministisch.
static func hoehe(x: float, z: float) -> float:
	var geo := _geo()
	var h := BASIS_HOEHE + _grundhuegel(x, z) + _grossformen(x, z)
	h += _zonen_features(x, z, geo)
	h += feinstruktur(x, z)
	h = _plateaus(x, z, h, geo)
	h = _moor_pfannen(x, z, h, geo)
	h = _boden_und_rand(x, z, h, geo)
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
	_geo_cache = {}
	_wege_cache = null
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
	var s := _wege()
	var faktor := 1.0
	var p := Vector2(x, z)
	for i in s.a.size():
		if x < s.min_x[i] or x > s.max_x[i] or z < s.min_z[i] or z > s.max_z[i]:
			continue
		var d := _abstand_zu_strecke(p, s.a[i], s.b[i])
		var halb := s.halb[i]
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
	var h := hoehe(x, z)
	if h < WASSER_HOEHE:
		return true
	if bach_kerbe(x, z) >= BACH_WASSER_AB_M:
		return true
	var bergsee: Dictionary = _geo()["bergsee"]
	if not bergsee.is_empty():
		var d := Vector2(x, z).distance_to(bergsee["mitte"])
		if d < float(bergsee["radius16"]):
			return h < float(bergsee["wasser"])
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


## Zonen-Features in Karten-Reihenfolge (Summanden-Folge = Direktweg).
static func _zonen_features(x: float, z: float, geo: Dictionary) -> float:
	var p := Vector2(x, z)
	var h := 0.0
	for feature: Dictionary in geo["features"]:
		match int(feature["typ"]):
			Feature.KAMM:
				var d := _abstand_zu_strecke(p, feature["fuss"], feature["kopf"])
				h += 24.0 * exp(-pow(d / 130.0, 2.0))
			Feature.SEE:
				var d: float = p.distance_to(feature["mitte"])
				h += -7.0 * exp(-pow(d / float(feature["r09"]), 2.0))
			Feature.TAL:
				var d: float = p.distance_to(feature["mitte"])
				h += -3.2 * exp(-pow(d / 190.0, 2.0))
			Feature.BERG:
				h += _bergmassiv(x, z, geo)
			Feature.RUINE:
				var d: float = p.distance_to(feature["turm"])
				h += 14.0 * exp(-pow(d / 120.0, 2.0))
			Feature.BUCHT:
				var d: float = p.distance_to(feature["mitte"])
				h += -8.0 * exp(-pow(d / float(feature["r09"]), 2.0))
			Feature.MOOR:
				h += _moor_wanne(p, feature["rect"])
	return h


## Bergmassiv: drei Gauß-Grate (Hauptgrat ~90 m + zwei Schultern) und der
## Vorberg-Sattel, der den Aufstieg vom Hügelkamm anbindet.
static func _bergmassiv(x: float, z: float, geo: Dictionary) -> float:
	# Früher Ausstieg: südlich von z = -560 hat das Massiv keinen Einfluss
	# mehr (hoehe() läuft beim Chunk-Bau hunderttausendfach).
	if z > -560.0:
		return 0.0
	var p := Vector2(x, z)
	var h := 0.0
	for grat: Dictionary in geo["berg_grate"]:
		var d := _abstand_zu_strecke(p, grat["a"], grat["b"])
		h += float(grat["amp"]) * exp(-pow(d / float(grat["breite"]), 2.0))
	var vorberg: Dictionary = geo["vorberg"]
	var vd: float = p.distance_to(vorberg["mitte"])
	h += float(vorberg["amp"]) * exp(-pow(vd / float(vorberg["radius"]), 2.0))
	return h


## Moor: flache Wanne über das Zonen-Rechteck (innen voll, 45-m-Saum).
static func _moor_wanne(p: Vector2, rect: Rect2) -> float:
	if not rect.has_point(p):
		return 0.0
	var tiefe_x := minf(p.x - rect.position.x, rect.end.x - p.x)
	var tiefe_z := minf(p.y - rect.position.y, rect.end.y - p.y)
	var w := clampf(minf(tiefe_x, tiefe_z) / 45.0, 0.0, 1.0)
	return -MOOR_WANNE_M * w * w * (3.0 - 2.0 * w)


## Flache Bau-Zonen (Hof/Turnierplatz/Hufingen): Höhe wird im Rect auf die
## `hoehe_basis` der Zone gezogen, außen weich ausgeblendet. Das BERG-
## PLATEAU zieht radial auf Plateau-Höhe und senkt danach den BERGSEE ein.
static func _plateaus(x: float, z: float, h: float, geo: Dictionary) -> float:
	var p := Vector2(x, z)
	var out := h
	for plateau: Dictionary in geo["plateaus"]:
		if int(plateau["typ"]) == Plateau.RECT:
			var gewicht := _plateau_gewicht(p, plateau["rect"])
			if gewicht > 0.0:
				out = lerpf(out, float(plateau["basis"]), gewicht)
		else:
			out = _berg_plateau(p, out, plateau)
	return out


## Berg-Plateau: radiale Glättung auf Plateau-Höhe (Rundumblick), dann die
## Bergsee-Senke — der See liegt IM Plateau, sein Spiegel knapp darunter.
static func _berg_plateau(p: Vector2, h: float, plateau: Dictionary) -> float:
	var d: float = p.distance_to(plateau["mitte"])
	var radius: float = plateau["radius"]
	var out := h
	if d < radius + PLATEAU_RAND_M:
		var t := clampf((d - radius) / PLATEAU_RAND_M, 0.0, 1.0)
		var gewicht := 1.0 - t * t * (3.0 - 2.0 * t)
		out = lerpf(out, float(plateau["basis"]), gewicht)
	var sd: float = p.distance_to(plateau["see_mitte"])
	if sd < float(plateau["see_radius"]) * 2.4:
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
static func _moor_pfannen(x: float, z: float, h: float, geo: Dictionary) -> float:
	var moor: Dictionary = geo["moor"]
	if moor.is_empty() or not (moor["rect"] as Rect2).has_point(Vector2(x, z)):
		return h
	var out := h
	if out < MOOR_PFANNE_M:
		out = MOOR_PFANNE_M - (MOOR_PFANNE_M - out) * 0.12
	for mitte: Vector2 in moor["tuempel"]:
		var d := Vector2(x, z).distance_to(mitte)
		if d < TUEMPEL_RADIUS_M * 3.0:
			var g := exp(-pow(d / TUEMPEL_RADIUS_M, 2.0))
			out = lerpf(out, TUEMPEL_ZIEL_M, clampf(g * 1.2, 0.0, 1.0))
	return out


## Globaler Boden + Weltrand: außerhalb der echten Gewässer fällt nichts
## unter BODEN_MIN_M, und zum Kartenrand läuft das Land weich auf die
## Fernwiesen-Höhe aus (kein sichtbarer Weltrand-Sprung).
static func _boden_und_rand(x: float, z: float, h: float, geo: Dictionary) -> float:
	var out := h
	var p := Vector2(x, z)
	if out < BODEN_MIN_M and not _in_gewaesser_senke(p, geo):
		out = BODEN_MIN_M
	var grenzen: Rect2 = geo["grenzen"]
	var rand := minf(
		minf(p.x - grenzen.position.x, grenzen.end.x - p.x),
		minf(p.y - grenzen.position.y, grenzen.end.y - p.y)
	)
	if rand < RAND_BLENDE_M:
		var t := clampf(rand / RAND_BLENDE_M, 0.0, 1.0)
		out = lerpf(RAND_ZIEL_M, out, t * t * (3.0 - 2.0 * t))
	return out


static func _in_gewaesser_senke(p: Vector2, geo: Dictionary) -> bool:
	for senke: Dictionary in geo["senken"]:
		if p.distance_to(senke["mitte"]) < float(senke["radius"]):
			return true
	return false


## Bachbett: entlang der Polyline wird `tiefe` eingekerbt (weiche Ränder);
## an der Furt flacht die Kerbe ab, damit Reiter/Tiere durchs Wasser können.
static func bach_kerbe(x: float, z: float) -> float:
	var geo := _geo()
	var halb: float = geo["bach_halb"]
	var d := _strecken_abstand(x, z, geo["bach_strecken"])
	if d >= halb:
		return 0.0
	var tiefe: float = geo["bach_tiefe"]
	var furt_d := Vector2(x, z).distance_to(geo["bach_furt"])
	if furt_d < FURT_RADIUS_M:
		tiefe = lerpf(0.55, tiefe, furt_d / FURT_RADIUS_M)
	var t := 1.0 - d / halb
	return tiefe * t * t * (3.0 - 2.0 * t)


## Schlucht am Bergmassiv: tiefe Kerbe entlang der Karten-Polyline mit
## FELS-Steilwänden (steilere Rampe als das Bachbett — echte Wände).
static func schlucht_kerbe(x: float, z: float) -> float:
	if z > -560.0:
		return 0.0
	var geo := _geo()
	if geo["schlucht_strecken"] == null:
		return 0.0
	var halb: float = geo["schlucht_halb"]
	var d := _strecken_abstand(x, z, geo["schlucht_strecken"])
	if d >= halb:
		return 0.0
	var t := 1.0 - d / halb
	# Steilere S-Rampe: Wände fallen schnell, Sohle bleibt breit begehbar.
	var wand := clampf(t * 1.55, 0.0, 1.0)
	return float(geo["schlucht_tiefe"]) * wand * wand * (3.0 - 2.0 * wand)


## ------------------------------------------------------------- Geo-Cache


## Karten-Daten EINMAL in getypte Deskriptoren übersetzen (hoehe() läuft
## beim Chunk-Bau hunderttausendfach; JSON-Scans pro Aufruf waren der
## Löwenanteil der Weltaufbau-Zeit).
static func _geo() -> Dictionary:
	if not _geo_cache.is_empty():
		return _geo_cache
	var karte := RanchKarte.karte()
	var geo := {
		"features": _feature_liste(karte),
		"plateaus": _plateau_liste(karte),
		"berg_grate": _berg_grate(),
		"vorberg":
		{
			"mitte": Vector2(float(VORBERG[0]), float(VORBERG[1])),
			"amp": float(VORBERG[2]),
			"radius": float(VORBERG[3]),
		},
		"moor": _moor_daten(karte),
		"senken": _senken_liste(karte),
		"grenzen": RanchKarte.grenzen(),
		"bergsee": _bergsee_daten(karte),
	}
	_bach_daten(karte, geo)
	_schlucht_daten(karte, geo)
	_geo_cache = geo
	return _geo_cache


static func _feature_liste(karte: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zone: Dictionary in karte["zonen"]:
		match str(zone["id"]):
			"huegelkamm":
				var spitze: Array = zone["aussichtspunkt"]
				(
					out
					. append(
						{
							"typ": Feature.KAMM,
							"fuss": Vector2(float(spitze[0]) - 140.0, float(spitze[1]) + 220.0),
							"kopf": Vector2(float(spitze[0]) + 120.0, float(spitze[1]) - 60.0),
						}
					)
				)
			"see":
				var mitte: Array = zone["see_mitte"]
				(
					out
					. append(
						{
							"typ": Feature.SEE,
							"mitte": Vector2(float(mitte[0]), float(mitte[1])),
							"r09": float(zone["see_radius"]) * 0.9,
						}
					)
				)
			"weidetal":
				(
					out
					. append(
						{
							"typ": Feature.TAL,
							"mitte": RanchKarte.zone_rect(zone).get_center(),
						}
					)
				)
			"bergmassiv":
				out.append({"typ": Feature.BERG})
			"ruine":
				var turm: Array = zone["turm"]
				(
					out
					. append(
						{
							"typ": Feature.RUINE,
							"turm": Vector2(float(turm[0]), float(turm[1])),
						}
					)
				)
			"strand":
				var bucht: Array = zone["bucht_mitte"]
				(
					out
					. append(
						{
							"typ": Feature.BUCHT,
							"mitte": Vector2(float(bucht[0]), float(bucht[1])),
							"r09": float(zone["bucht_radius"]) * 0.9,
						}
					)
				)
			"moor":
				out.append({"typ": Feature.MOOR, "rect": RanchKarte.zone_rect(zone)})
	return out


static func _plateau_liste(karte: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zone: Dictionary in karte["zonen"]:
		var id := str(zone["id"])
		if id == "hof" or id == "turnierplatz" or id == "hufingen":
			(
				out
				. append(
					{
						"typ": Plateau.RECT,
						"rect": RanchKarte.zone_rect(zone),
						"basis": float(zone.get("hoehe_basis", 0.0)),
					}
				)
			)
		elif id == "bergmassiv":
			var mitte: Array = zone["plateau_mitte"]
			var see: Array = zone["bergsee_mitte"]
			(
				out
				. append(
					{
						"typ": Plateau.BERG,
						"mitte": Vector2(float(mitte[0]), float(mitte[1])),
						"radius": float(zone["plateau_radius"]),
						"basis": float(zone.get("hoehe_basis", 62.0)),
						"see_mitte": Vector2(float(see[0]), float(see[1])),
						"see_radius": float(zone["bergsee_radius"]),
					}
				)
			)
	return out


static func _berg_grate() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for grat: Array in BERG_GRATE:
		(
			out
			. append(
				{
					"a": Vector2(float(grat[0]), float(grat[1])),
					"b": Vector2(float(grat[2]), float(grat[3])),
					"amp": float(grat[4]),
					"breite": float(grat[5]),
				}
			)
		)
	return out


static func _moor_daten(karte: Dictionary) -> Dictionary:
	for zone: Dictionary in karte["zonen"]:
		if str(zone["id"]) != "moor":
			continue
		var tuempel := PackedVector2Array()
		for paar: Array in zone["tuempel"]:
			tuempel.append(Vector2(float(paar[0]), float(paar[1])))
		return {"rect": RanchKarte.zone_rect(zone), "tuempel": tuempel}
	return {}


static func _senken_liste(karte: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zone: Dictionary in karte["zonen"]:
		match str(zone["id"]):
			"see":
				var mitte: Array = zone["see_mitte"]
				(
					out
					. append(
						{
							"mitte": Vector2(float(mitte[0]), float(mitte[1])),
							"radius": 220.0,
						}
					)
				)
			"strand":
				var bucht: Array = zone["bucht_mitte"]
				(
					out
					. append(
						{
							"mitte": Vector2(float(bucht[0]), float(bucht[1])),
							"radius": 160.0,
						}
					)
				)
	return out


static func _bergsee_daten(karte: Dictionary) -> Dictionary:
	for zone: Dictionary in karte["zonen"]:
		if str(zone["id"]) != "bergmassiv":
			continue
		var mitte: Array = zone["bergsee_mitte"]
		return {
			"mitte": Vector2(float(mitte[0]), float(mitte[1])),
			"radius16": float(zone["bergsee_radius"]) * 1.6,
			"wasser": float(zone["bergsee_wasser"]),
		}
	return {}


static func _bach_daten(karte: Dictionary, geo: Dictionary) -> void:
	var bach: Dictionary = karte["bach"]
	var halb := float(bach["breite"]) / 2.0 + 2.0
	var furt: Array = bach["furt"]
	geo["bach_halb"] = halb
	geo["bach_tiefe"] = float(bach["tiefe"])
	geo["bach_furt"] = Vector2(float(furt[0]), float(furt[1]))
	geo["bach_strecken"] = _als_strecken(bach["punkte"], halb + AABB_MARGE_M)


static func _schlucht_daten(karte: Dictionary, geo: Dictionary) -> void:
	if not karte.has("schlucht"):
		geo["schlucht_strecken"] = null
		return
	var schlucht: Dictionary = karte["schlucht"]
	var halb := float(schlucht["breite"]) / 2.0 + 2.0
	geo["schlucht_halb"] = halb
	geo["schlucht_tiefe"] = float(schlucht["tiefe"])
	geo["schlucht_strecken"] = _als_strecken(schlucht["punkte"], halb + AABB_MARGE_M)


static func _als_strecken(punkte: Array, rand: float) -> Strecken:
	var s := Strecken.new()
	for i in punkte.size() - 1:
		var a: Array = punkte[i]
		var b: Array = punkte[i + 1]
		s.fuege_hinzu(
			Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])), 0.0, rand
		)
	return s


## Karten-Wege als flache Segment-Arrays (gecacht — hoehe() läuft beim
## Chunk-Bau hunderttausendfach; ohne Cache würde jeder Aufruf die
## JSON-Arrays neu parsen).
static func _wege() -> Strecken:
	if _wege_cache != null:
		return _wege_cache
	var s := Strecken.new()
	for weg: Dictionary in RanchKarte.wege():
		var halb := float(weg.get("breite", 4.0)) / 2.0 + 1.0
		var rand := halb + WEG_GLAETT_RAND_M
		var punkte: Array = weg["punkte"]
		for i in punkte.size() - 1:
			var a: Array = punkte[i]
			var b: Array = punkte[i + 1]
			s.fuege_hinzu(
				Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])), halb, rand
			)
	_wege_cache = s
	return _wege_cache


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


## ------------------------------------------------------------- Geometrie


## Kleinster Segment-Abstand einer Strecken-Liste; Segmente, deren AABB
## (inkl. Marge über der Relevanz-Grenze) den Punkt ausschließt, werden
## übersprungen — EXAKT, weil der Aufrufer alles >= Grenze auf 0 klemmt.
static func _strecken_abstand(x: float, z: float, s: Strecken) -> float:
	var best := INF
	var p := Vector2(x, z)
	for i in s.a.size():
		if x < s.min_x[i] or x > s.max_x[i] or z < s.min_z[i] or z > s.max_z[i]:
			continue
		best = minf(best, _abstand_zu_strecke(p, s.a[i], s.b[i]))
	return best


static func _abstand_zu_strecke(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var laenge2 := ab.length_squared()
	if laenge2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / laenge2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
