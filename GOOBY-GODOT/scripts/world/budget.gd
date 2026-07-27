class_name WeltBudget
extends RefCounted
## Draw-Call-Budget-Werkzeug (WELT-1): ein Nachlauf-Pass über den fertigen
## Szenenbaum, der KLEINTEILEN eine Sichtweite gibt. Zäune, Pfosten,
## Eimer, Bänke, Tiere, Fundort-Details usw. sind aus 300+ m Entfernung
## sub-pixel-klein, kosten aber je einen Draw-Call — das Panorama einer
## großen Openworld summiert das auf Hunderte. Der Pass setzt
## `visibility_range_end` nach AABB-Größe (Welt-Skala eingerechnet) und
## lässt alles in Ruhe, was schon eigene Ranges hat (Terrain-LODs, Flora-
## MultiMeshes) oder groß genug ist, um die Silhouette zu tragen.

## Kleinteile (< KLEIN_MAX_M Kantenlänge) verschwinden ab hier.
const SICHT_KLEIN_M := 240.0

## Mittlere Teile (< MITTEL_MAX_M) verschwinden ab hier.
const SICHT_MITTEL_M := 380.0

const KLEIN_MAX_M := 1.6
const MITTEL_MAX_M := 6.0


## Setzt Sichtweiten auf alle Kleinteil-Geometrien unter `wurzel`.
## Rückgabe: Anzahl der neu gedeckelten Instanzen (für Tests/Diagnose).
static func kleinteil_culling(wurzel: Node) -> int:
	var getroffen := 0
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var knoten: Node = stapel.pop_back()
		for kind in knoten.get_children():
			stapel.append(kind)
		if knoten is MultiMeshInstance3D or knoten is GPUParticles3D:
			continue
		if not (knoten is GeometryInstance3D):
			continue
		var geo := knoten as GeometryInstance3D
		if geo.visibility_range_end > 0.0 or geo.visibility_range_begin > 0.0:
			continue
		var sicht := _sicht_fuer(geo)
		if sicht > 0.0:
			geo.visibility_range_end = sicht
			getroffen += 1
	return getroffen


## Sichtweite nach Welt-AABB: 0.0 = nicht deckeln (große Silhouette).
static func _sicht_fuer(geo: GeometryInstance3D) -> float:
	var groesse := geo.get_aabb().size
	var skala := (
		geo.global_transform.basis.get_scale().abs()
		if geo.is_inside_tree()
		else geo.transform.basis.get_scale().abs()
	)
	groesse = Vector3(groesse.x * skala.x, groesse.y * skala.y, groesse.z * skala.z)
	var kante := maxf(groesse.x, maxf(groesse.y, groesse.z))
	if kante < KLEIN_MAX_M:
		return SICHT_KLEIN_M
	if kante < MITTEL_MAX_M:
		return SICHT_MITTEL_M
	return 0.0
