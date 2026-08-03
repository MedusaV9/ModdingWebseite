class_name CityMap
extends RefCounted
## Stadtplan-Datenmodell (W3a CITY, Doc E §1.1/§1.2): lädt + validiert
## `data/city_map.json` (15×12-Lattice, 20-m-Tiles, 5 Distrikte, Orte,
## Kreisel, Flughafen-Zubringer) und liefert PURE Helfer für Welt↔Tile,
## Straßen-Erkennung, Distrikt-/Energie-Lookup und Parkplatz-Positionen.
## Die Straßen-Stück-Klassifikation (GLB + Rotation aus Nachbarschaft) ist
## der 1:1-Port von cityBuilder.js `PIECE_PORTS`/`roadPieceFor` (Web-Referenz,
## Suchverfahren statt Sonderfall-Leiter).

const MAP_PATH := "res://scripts/city/data/city_map.json"

## TRUE geauthorte offene Port-Seiten der Kenney-Straßen-GLBs bei rot 0
## (Web-Referenz PIECE_PORTS, per Testszene verifiziert — NICHT raten).
const PIECE_PORTS := {
	"road-straight": ["W", "E"],
	"road-bend": ["S", "W"],
	"road-intersection": ["E", "S", "W"],
	"road-crossroad": ["N", "E", "S", "W"],
	"road-crossing": ["W", "E"],
	"road-end": ["W"],
}
## +90°-Y-Drehung mappt Ports N→W→S→E→N (Rechtssystem, +Z = Süden).
const PORT_TURN := {"N": "W", "W": "S", "S": "E", "E": "N"}
const SEARCH_PIECES: Array[String] = [
	"road-straight", "road-bend", "road-intersection", "road-crossroad", "road-end"
]

## Halbe Kantenlänge der Ort-Tile-Kollisionsquader (CityBau.baue_orte legt
## je Ort-Tile eine 15×15-m-AABB an — hier gespiegelt, damit der Parkplatz-
## Anker rechnerisch AUSSERHALB dieser Box bleibt).
const ORT_COLLIDER_HALB_M := 7.5

var daten: Dictionary = {}
var spalten := 15
var reihen := 12
var tile_m := 20.0

var _strassen: Dictionary = {}
var _kreisel: Dictionary = {}


## Karte aus JSON laden. Gibt bei kaputter Datei eine leere Karte zurück
## (Fehler via push_error) — Aufrufer prüfen `ist_geladen()`.
static func laden(pfad := MAP_PATH) -> CityMap:
	var karte := CityMap.new()
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("city_map.json kaputt: %s" % pfad)
		return karte
	karte.daten = json.data
	karte.spalten = int(karte.daten.get("grid_spalten", 15))
	karte.reihen = int(karte.daten.get("grid_reihen", 12))
	karte.tile_m = float(karte.daten.get("tile_m", 20.0))
	karte._baue_strassen()
	return karte


## Set-Drehung von Portlisten um q Vierteldrehungen (+90° je Schritt).
static func rotate_ports(ports: Array, quarter_turns: int) -> Array:
	var q := ((quarter_turns % 4) + 4) % 4
	var out: Array = []
	for p: String in ports:
		var side := p
		for _i in q:
			side = PORT_TURN[side]
		out.append(side)
	return out


## Straßen-GLB + Y-Rotation (Grad) für ein Tile aus seiner N/E/S/W-
## Nachbarschaft — deterministische Suche über PIECE_PORTS (Web-Port).
static func road_piece_for(n: bool, e: bool, s: bool, w: bool) -> Dictionary:
	var want: Array = []
	if n:
		want.append("N")
	if e:
		want.append("E")
	if s:
		want.append("S")
	if w:
		want.append("W")
	want.sort()
	var want_key := "".join(want)
	for piece in SEARCH_PIECES:
		for q in 4:
			var got: Array = rotate_ports(PIECE_PORTS[piece], q)
			got.sort()
			if "".join(got) == want_key:
				return {"piece": piece, "rot_grad": q * 90}
	return {"piece": "road-straight", "rot_grad": 90 if (n or s) else 0}


func ist_geladen() -> bool:
	return not daten.is_empty()


func ist_strasse(tile: Vector2i) -> bool:
	return _strassen.has(tile)


func ist_kreisel(tile: Vector2i) -> bool:
	return _kreisel.has(tile)


func strassen_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile: Vector2i in _strassen.keys():
		out.append(tile)
	return out


## Tile-Mitte (r, c — auch gebrochen für 2×2-Deko) → Welt-XZ, Karte zentriert.
func welt_von(r: float, c: float) -> Vector3:
	var x := (c - float(spalten - 1) / 2.0) * tile_m
	var z := (r - float(reihen - 1) / 2.0) * tile_m
	return Vector3(x, 0.0, z)


func tile_zu_welt(tile: Vector2i) -> Vector3:
	return welt_von(float(tile.x), float(tile.y))


## Welt-Position → Tile (r=x-Komponente des Vector2i, c=y-Komponente).
func welt_zu_tile(pos: Vector3) -> Vector2i:
	var c := roundi(pos.x / tile_m + float(spalten - 1) / 2.0)
	var r := roundi(pos.z / tile_m + float(reihen - 1) / 2.0)
	return Vector2i(r, c)


## Halbe Kartenbreite in Metern (Fahr-Grenzen).
func welt_halb() -> Vector2:
	return Vector2(float(spalten) * tile_m / 2.0, float(reihen) * tile_m / 2.0)


func distrikt_von(tile: Vector2i) -> String:
	var distrikte: Dictionary = daten.get("distrikte", {})
	for name: String in distrikte:
		for zone: Array in distrikte[name].get("zonen", []):
			var r0 := int(zone[0])
			var c0 := int(zone[1])
			var r1 := int(zone[2])
			var c1 := int(zone[3])
			if tile.x >= r0 and tile.x <= r1 and tile.y >= c0 and tile.y <= c1:
				return name
	return ""


## Energie-Kosten fürs BETRETEN eines Orts (Doc E §1.3): flache Tabelle je
## Distrikt; Fahren kostet NICHTS, nach Hause kostet NICHTS.
func energie_kosten(ort_id: String) -> int:
	if ort_id == "zuhause":
		return 0
	var eintrag := ort(ort_id)
	if eintrag.is_empty():
		return 0
	var distrikte: Dictionary = daten.get("distrikte", {})
	var distrikt: Dictionary = distrikte.get(str(eintrag.get("distrikt", "")), {})
	return int(distrikt.get("energie", 0))


func orte() -> Array:
	return daten.get("orte", [])


func ort(id: String) -> Dictionary:
	for eintrag: Dictionary in orte():
		if str(eintrag.get("id", "")) == id:
			return eintrag
	return {}


func zuhause_tile() -> Vector2i:
	return _tile_von(daten.get("zuhause", {}).get("tile", [9, 2]))


func _zuhause_strasse() -> Vector2i:
	return _tile_von(daten.get("zuhause", {}).get("strasse", [9, 1]))


## Hausausfahrt des Spielerhauses (FIX-5 „Fahrt startet am eigenen Haus"):
## Parkposition in der Einfahrt (zwischen Bordstein und Hausfassade), Blick
## zur Haustür, plus Ziel-Fahrtrichtung fürs Rückwärts-Ausparken auf die
## Straße. `einfahrt_m` steht in der Karte (Abstand von der Straßenmitte).
func zuhause_einfahrt() -> Dictionary:
	var strasse := tile_zu_welt(_zuhause_strasse())
	var haus := tile_zu_welt(zuhause_tile())
	var richtung := (haus - strasse).normalized()
	if richtung.length_squared() < 0.5:
		richtung = Vector3.RIGHT
	var abstand := float(daten.get("zuhause", {}).get("einfahrt_m", 11.5))
	# Straße läuft quer zur Einfahrt; als Ausparkziel nehmen wir die
	# Fahrtrichtung, die das Heading-Plus des Rückwärtsgangs erreicht.
	var quer := Vector3(richtung.z, 0.0, -richtung.x)
	var start_heading := atan2(richtung.x, richtung.z)
	return {
		"pos": strasse + richtung * abstand,
		"richtung_haus": richtung,
		"strasse_pos": strasse,
		"strasse_tile": _zuhause_strasse(),
		"heading": start_heading,
		"ziel_heading": CityCarFeel.wrap_angle(atan2(quer.x, quer.z)),
	}


## Parkplatz-Trigger-Position eines Orts: Mitte des STRASSENNÄCHSTEN
## Ort-Tiles, Richtung Straßen-Tile geschoben (Auto parkt am Bordstein).
## PT2-B3: trigger_offset_m (7,0) lag IN der 7,5-m-Collider-Halbkante —
## _kollidiere() warf das Auto zur Westkante (Flughafen/Post: quer durchs
## Gebäude, „Betreten“-Prompt flackerte). Der Offset ist deshalb auf
## Collider-Halbkante + Auto-Radius + Luft geklemmt, und beim Flughafen
## zählt das Tile am Zubringer statt tiles[0] (das liegt 2 Tiles tief).
func parkplatz_welt(ort_id: String) -> Vector3:
	var eintrag: Dictionary = ort(ort_id) if ort_id != "zuhause" else {}
	var tile := zuhause_tile()
	var strasse := _zuhause_strasse()
	if not eintrag.is_empty():
		strasse = _tile_von(eintrag.get("strasse", [0, 0]))
		tile = _naechstes_tile(eintrag.get("tiles", [[0, 0]]), strasse)
	var mitte := tile_zu_welt(tile)
	var richtung := (tile_zu_welt(strasse) - mitte).normalized()
	var offset := maxf(
		float(daten.get("parken", {}).get("trigger_offset_m", 7.0)),
		ORT_COLLIDER_HALB_M + CityCarFeel.CAR_RADIUS_M + 0.5
	)
	return mitte + richtung * offset


## Straßennächstes Tile eines Orts (PT2-B3): beim Flughafen liegt tiles[0]
## ZWEI Tiles vom Zubringer — der Anker gehört vor das Tile an der Straße,
## sonst zeigt er in die Gasse zwischen zwei Gebäude-Collidern.
static func _naechstes_tile(tiles: Array, strasse: Vector2i) -> Vector2i:
	var best := _tile_von(tiles[0] if not tiles.is_empty() else [0, 0])
	var best_d := (best - strasse).length_squared()
	for raw: Variant in tiles:
		var t := _tile_von(raw)
		var d := (t - strasse).length_squared()
		if d < best_d:
			best = t
			best_d = d
	return best


func park_radius() -> float:
	return float(daten.get("parken", {}).get("radius_m", 4.0))


func traffic_loops() -> Array:
	return daten.get("traffic_loops", [])


func deko() -> Array:
	return daten.get("deko", [])


func deko_seed() -> int:
	return int(daten.get("deko_seed", 1))


## Validierung fürs Testnetz: jede Ort-`strasse` ist wirklich Straße und
## grenzt an ein Ort-Tile; Distrikte decken alle Ort-Tiles ab.
func validieren() -> Array[String]:
	var fehler: Array[String] = []
	for eintrag: Dictionary in orte():
		var id := str(eintrag.get("id", "?"))
		var strasse := _tile_von(eintrag.get("strasse", [0, 0]))
		if not ist_strasse(strasse):
			fehler.append("%s: strasse %s ist keine Straße" % [id, strasse])
		if (
			distrikt_von(_tile_von(eintrag.get("tiles", [[0, 0]])[0]))
			!= str(eintrag.get("distrikt", ""))
		):
			fehler.append("%s: distrikt passt nicht zur Zone" % id)
		for tile_raw: Array in eintrag.get("tiles", []):
			var tile := _tile_von(tile_raw)
			if ist_strasse(tile):
				fehler.append("%s: Ort-Tile %s liegt auf einer Straße" % [id, tile])
	if not ist_strasse(_zuhause_strasse()):
		fehler.append("zuhause: strasse ist keine Straße")
	return fehler


func _baue_strassen() -> void:
	_strassen.clear()
	_kreisel.clear()
	var spec: Dictionary = daten.get("strassen", {})
	var rc: Array = spec.get("reihen_spalten", [1, 13])
	for r_raw: Variant in spec.get("reihen", []):
		for c in range(int(rc[0]), int(rc[1]) + 1):
			_strassen[Vector2i(int(r_raw), c)] = true
	var cr: Array = spec.get("spalten_reihen", [1, 10])
	for c_raw: Variant in spec.get("spalten", []):
		for r in range(int(cr[0]), int(cr[1]) + 1):
			_strassen[Vector2i(r, int(c_raw))] = true
	for extra: Array in spec.get("extra", []):
		_strassen[_tile_von(extra)] = true
	for kreisel: Array in spec.get("kreisel", []):
		_kreisel[_tile_von(kreisel)] = true


static func _tile_von(raw: Variant) -> Vector2i:
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO
