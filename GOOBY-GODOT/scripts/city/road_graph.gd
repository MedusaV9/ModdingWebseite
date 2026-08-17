class_name CityRoadGraph
extends RefCounted
## A*-Wegenetz über die Straßen-Tiles der Stadt (Doc E §1.3): Knoten =
## Straßen-Tiles, Kanten = 4er-Nachbarschaft. PURE (keine Szene) — liefert
## Pfade für GPS-Pfeil, Traffic-Ziele und die GOOBERANDO-Fahrer-Simulation.
## Dazu Polyline-Helfer (Länge/Punkt-bei-Bogenlänge) als Port der puren
## cityBuilder.js-Mathematik.

var _nachbarn: Dictionary = {}


## Graph aus einer geladenen CityMap bauen.
static func aus_karte(karte: CityMap) -> CityRoadGraph:
	var graph := CityRoadGraph.new()
	for tile in karte.strassen_tiles():
		var kanten: Array[Vector2i] = []
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nachbar: Vector2i = tile + offset
			if karte.ist_strasse(nachbar):
				kanten.append(nachbar)
		graph._nachbarn[tile] = kanten
	return graph


## Gesamtlänge einer Welt-Polyline (m), optional geschlossen.
static func polyline_laenge(punkte: PackedVector3Array, geschlossen := false) -> float:
	var laenge := 0.0
	for i in range(1, punkte.size()):
		laenge += punkte[i].distance_to(punkte[i - 1])
	if geschlossen and punkte.size() > 1:
		laenge += punkte[0].distance_to(punkte[punkte.size() - 1])
	return laenge


## Punkt + Richtung bei Bogenlänge s entlang einer Polyline (geklammert;
## wickelt bei geschlossenen Loops). Rückgabe {"punkt": Vector3, "richtung": Vector3}.
static func punkt_bei_laenge(
	punkte: PackedVector3Array, s: float, geschlossen := false
) -> Dictionary:
	var gesamt := polyline_laenge(punkte, geschlossen)
	if geschlossen and gesamt > 0.0:
		s = fposmod(s, gesamt)
	else:
		s = clampf(s, 0.0, gesamt)
	var n := punkte.size()
	var segmente := n if geschlossen else n - 1
	var acc := 0.0
	for i in segmente:
		var a := punkte[i]
		var b := punkte[(i + 1) % n]
		var seg := a.distance_to(b)
		if acc + seg >= s or i == segmente - 1:
			var f := (s - acc) / seg if seg > 0.0 else 0.0
			var richtung := (b - a) / seg if seg > 0.0 else Vector3(1, 0, 0)
			return {"punkt": a.lerp(b, f), "richtung": richtung}
		acc += seg
	var letzter := punkte[n - 1] if n > 0 else Vector3.ZERO
	return {"punkt": letzter, "richtung": Vector3(1, 0, 0)}


func knoten_anzahl() -> int:
	return _nachbarn.size()


func ist_knoten(tile: Vector2i) -> bool:
	return _nachbarn.has(tile)


func nachbarn(tile: Vector2i) -> Array[Vector2i]:
	var kanten: Array[Vector2i] = []
	kanten.assign(_nachbarn.get(tile, []))
	return kanten


## A*-Pfad von→nach (inklusive beider Enden). Leeres Array = unerreichbar.
func pfad(von: Vector2i, nach: Vector2i) -> Array[Vector2i]:
	var leer: Array[Vector2i] = []
	if not ist_knoten(von) or not ist_knoten(nach):
		return leer
	if von == nach:
		var einer: Array[Vector2i] = [von]
		return einer
	var offen: Dictionary = {von: true}
	var g_score: Dictionary = {von: 0}
	var herkunft: Dictionary = {}
	while not offen.is_empty():
		var aktuell := _bester_knoten(offen, g_score, nach)
		if aktuell == nach:
			return _rekonstruiere(herkunft, aktuell)
		offen.erase(aktuell)
		for nachbar in nachbarn(aktuell):
			var neu: int = int(g_score[aktuell]) + 1
			if neu < int(g_score.get(nachbar, 1 << 30)):
				herkunft[nachbar] = aktuell
				g_score[nachbar] = neu
				offen[nachbar] = true
	return leer


## Nächstgelegenes Straßen-Tile zu einem beliebigen Tile (Manhattan-Suche).
## Tie-Break deterministisch: gleiche Reihe zuerst (Fassaden zeigen zur
## Spalten-Straße „davor“), dann lexikografisch kleinstes Tile.
func naechste_strasse(tile: Vector2i) -> Vector2i:
	if ist_knoten(tile):
		return tile
	var beste := Vector2i.ZERO
	var beste_score: Array = [1 << 30, 1, 1 << 30, 1 << 30]
	for knoten: Vector2i in _nachbarn.keys():
		var d: int = absi(knoten.x - tile.x) + absi(knoten.y - tile.y)
		var score: Array = [d, 0 if knoten.x == tile.x else 1, knoten.x, knoten.y]
		if score < beste_score:
			beste_score = score
			beste = knoten
	return beste


## Ecken-Liste → kompletter geschlossener Tile-Pfad (Traffic-Loops,
## Port von cityBuilder.js expandLoop).
func schleife(ecken: Array) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for i in ecken.size():
		var von := CityMap._tile_von(ecken[i])
		var nach := CityMap._tile_von(ecken[(i + 1) % ecken.size()])
		var dr := signi(nach.x - von.x)
		var dc := signi(nach.y - von.y)
		var aktuell := von
		while aktuell != nach:
			tiles.append(aktuell)
			aktuell += Vector2i(dr, dc)
	return tiles


func _bester_knoten(offen: Dictionary, g_score: Dictionary, ziel: Vector2i) -> Vector2i:
	var bester := Vector2i.ZERO
	var beste_f := 1 << 30
	for knoten: Vector2i in offen.keys():
		var f: int = int(g_score[knoten]) + absi(ziel.x - knoten.x) + absi(ziel.y - knoten.y)
		if f < beste_f:
			beste_f = f
			bester = knoten
	return bester


func _rekonstruiere(herkunft: Dictionary, ende: Vector2i) -> Array[Vector2i]:
	var weg: Array[Vector2i] = [ende]
	var aktuell := ende
	while herkunft.has(aktuell):
		aktuell = herkunft[aktuell]
		weg.push_front(aktuell)
	return weg
