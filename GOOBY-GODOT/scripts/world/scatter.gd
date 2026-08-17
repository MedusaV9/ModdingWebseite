class_name WeltStreu
extends RefCounted
## Streu-Bibliothek aller GOOBY-Welten (FB-2) — PURE + headless-testbar.
## Verteilt Deko (Bäume, Büsche, Blumen, Gräser, Steine, Farne, Stümpfe)
## REGELBASIERT statt gleichverteilt: Cluster um Streuzentren, Mindest-
## abstand zwischen Instanzen, Abstand zu Wegen/Sperrflächen, Höhenlage,
## Zufallsrotation und -skalierung — deterministisch über den Seed.
## Rückgabe sind fertige Transform3D-Listen; die Szenen hängen sie als
## MultiMesh ein (RanchBau.baue_multimesh / CityBau-Muster: ein Draw-Call
## je Mesh-Sorte, nicht je Exemplar).
##
## Regeln (alle optional außer `rect` + `anzahl`):
## - rect: Rect2                Streufläche (x/z-Weltmeter)
## - anzahl: int                Ziel-Anzahl (Rejection kann weniger liefern)
## - cluster: {anzahl, radius}  Cluster statt Gleichverteilung
## - min_abstand: float         Mindestabstand zwischen Instanzen (m)
## - meide_segmente: [{a, b, abstand}]  Wege/Bänder freihalten
## - meide_rects: [Rect2]       Sperrflächen (Plateaus, Arenen …)
## - meide_kreise: [{mitte, radius}]    runde Sperrflächen (See …)
## - hoehe_min / hoehe_max      erlaubte Höhenlage (über hoehe_fn)
## - hoehe_fn: Callable(x, z) -> float  Bodenhöhe (Default 0)
## - frei_fn: Callable(Vector2) -> bool zusätzliches Veto (Wasser …)
## - skala_min / skala_max      Zufallsskalierung (Default 1..1)
## - einsenken: float           Y-Versatz (Wurzeln in den Boden)

## Rejection-Budget: so viele Versuche pro gewünschter Instanz.
const VERSUCHE_JE_INSTANZ := 6


## Deterministische Streuung nach Regeln; gleiche Regeln + Seed ⇒ gleiche
## Transform-Liste auf jedem Gerät.
static func verteile(regeln: Dictionary, seed_wert: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var rect: Rect2 = regeln.get("rect", Rect2())
	var anzahl := int(regeln.get("anzahl", 0))
	if anzahl <= 0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	var zentren := _cluster_zentren(regeln, rng)
	var min_abstand := float(regeln.get("min_abstand", 0.0))
	var raster: Dictionary = {}
	var versuche := anzahl * VERSUCHE_JE_INSTANZ
	while out.size() < anzahl and versuche > 0:
		versuche -= 1
		var p := _kandidat(regeln, rng, zentren)
		if not rect.has_point(p):
			continue
		if not _erlaubt(regeln, p):
			continue
		if min_abstand > 0.0 and _zu_nah(raster, p, min_abstand):
			continue
		if min_abstand > 0.0:
			_merke(raster, p, min_abstand)
		out.append(_transform(regeln, rng, p))
	return out


## Abstand Punkt→Strecke (öffentlich — Anwender bauen damit Weg-Regeln).
static func segment_abstand(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var laenge2 := ab.length_squared()
	if laenge2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / laenge2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Karten-Wege (RanchKarte-Schema) → meide_segmente-Regel.
static func weg_segmente(wege: Array, abstand: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for weg: Dictionary in wege:
		var punkte: Array = weg["punkte"]
		for i in punkte.size() - 1:
			var a: Array = punkte[i]
			var b: Array = punkte[i + 1]
			(
				out
				. append(
					{
						"a": Vector2(float(a[0]), float(a[1])),
						"b": Vector2(float(b[0]), float(b[1])),
						"abstand": abstand + float(weg.get("breite", 0.0)) / 2.0,
					}
				)
			)
	return out


## ------------------------------------------------------------------ intern


## Cluster-Zentren: liegen selbst regelkonform in der Fläche ([] = keine
## Cluster-Regel ⇒ Gleichverteilung).
static func _cluster_zentren(regeln: Dictionary, rng: RandomNumberGenerator) -> Array[Vector2]:
	var zentren: Array[Vector2] = []
	if not (regeln.get("cluster") is Dictionary):
		return zentren
	var cluster: Dictionary = regeln["cluster"]
	var rect: Rect2 = regeln["rect"]
	var soll := maxi(1, int(cluster.get("anzahl", 1)))
	var versuche := soll * VERSUCHE_JE_INSTANZ * 2
	while zentren.size() < soll and versuche > 0:
		versuche -= 1
		var p := Vector2(
			rng.randf_range(rect.position.x, rect.end.x),
			rng.randf_range(rect.position.y, rect.end.y)
		)
		if _erlaubt(regeln, p):
			zentren.append(p)
	return zentren


static func _kandidat(
	regeln: Dictionary, rng: RandomNumberGenerator, zentren: Array[Vector2]
) -> Vector2:
	if zentren.is_empty():
		var rect: Rect2 = regeln["rect"]
		return Vector2(
			rng.randf_range(rect.position.x, rect.end.x),
			rng.randf_range(rect.position.y, rect.end.y)
		)
	var cluster: Dictionary = regeln["cluster"]
	var radius := float(cluster.get("radius", 20.0))
	var zentrum := zentren[rng.randi_range(0, zentren.size() - 1)]
	# sqrt-Verteilung: gleichmäßig in der Kreisfläche, dichter Kern.
	return zentrum + Vector2.from_angle(rng.randf() * TAU) * (radius * sqrt(rng.randf()))


static func _erlaubt(regeln: Dictionary, p: Vector2) -> bool:
	for sperr_rect: Rect2 in regeln.get("meide_rects", [] as Array[Rect2]):
		if sperr_rect.has_point(p):
			return false
	for kreis: Dictionary in regeln.get("meide_kreise", [] as Array[Dictionary]):
		if p.distance_to(kreis["mitte"]) < float(kreis["radius"]):
			return false
	for segment: Dictionary in regeln.get("meide_segmente", [] as Array[Dictionary]):
		if segment_abstand(p, segment["a"], segment["b"]) < float(segment["abstand"]):
			return false
	var hoehe := _hoehe(regeln, p)
	if hoehe < float(regeln.get("hoehe_min", -INF)) or hoehe > float(regeln.get("hoehe_max", INF)):
		return false
	var frei: Variant = regeln.get("frei_fn")
	if frei is Callable and not (frei as Callable).call(p):
		return false
	return true


static func _hoehe(regeln: Dictionary, p: Vector2) -> float:
	var fn: Variant = regeln.get("hoehe_fn")
	if fn is Callable:
		return float((fn as Callable).call(p.x, p.y))
	return 0.0


static func _transform(regeln: Dictionary, rng: RandomNumberGenerator, p: Vector2) -> Transform3D:
	var skala := rng.randf_range(
		float(regeln.get("skala_min", 1.0)), float(regeln.get("skala_max", 1.0))
	)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * skala)
	var y := _hoehe(regeln, p) + float(regeln.get("einsenken", 0.0))
	return Transform3D(basis, Vector3(p.x, y, p.y))


## Nachbarschafts-Raster (Zellgröße = min_abstand): nur 9 Zellen prüfen.
static func _zelle(p: Vector2, weite: float) -> Vector2i:
	return Vector2i(floori(p.x / weite), floori(p.y / weite))


static func _zu_nah(raster: Dictionary, p: Vector2, min_abstand: float) -> bool:
	var zelle := _zelle(p, min_abstand)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var nachbarn: Variant = raster.get(zelle + Vector2i(dx, dz))
			if nachbarn == null:
				continue
			for andere: Vector2 in nachbarn:
				if p.distance_to(andere) < min_abstand:
					return true
	return false


static func _merke(raster: Dictionary, p: Vector2, min_abstand: float) -> void:
	var zelle := _zelle(p, min_abstand)
	if not raster.has(zelle):
		raster[zelle] = [] as Array[Vector2]
	(raster[zelle] as Array[Vector2]).append(p)
