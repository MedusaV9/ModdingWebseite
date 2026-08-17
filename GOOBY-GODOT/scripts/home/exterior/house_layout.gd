class_name HouseLayout
extends RefCounted
## Kanonischer Hausplan (HAUS-SICHT, User: „bei Räumen den Rest des Hauses
## spüren"). EINE Quelle für die Frage „wo im Haus liegt dieser Raum?" —
## damit derselbe Raum immer an derselben Stelle liegt und Fenster/Türen
## innen wie außen zusammenpassen.
##
## Haus-Kompass: Die STRASSE liegt im Norden des Hauses, der GARTEN im
## Süden (deckt sich mit rooms.json: die Außenwand `walls.N` jedes Raums
## zeigt auf seine Vista). Wohnzimmer + Küche liegen im Erdgeschoss,
## Schlafzimmer + Bad im Dachgeschoss (Dachschräge!). Der Garten ist das
## Grundstück hinter dem Haus — sein Nordrand IST die Südfassade.
##
## Alles static + pure (test_haussicht_layout.gd).

## Fassaden-Seite je Vista (rooms.json `walls.N`).
const FASSADE_STRASSE := "nord"
const FASSADE_GARTEN := "sued"

## Raum → Platz im Haus: fassade (nord = Straßenseite, sued = Gartenseite),
## etage (0 = Erdgeschoss, 1 = Dachgeschoss ⇒ Dachschräge) und spalte
## (Position auf der Fassade, 0 = West). MUSS zu rooms.json `walls` passen
## (CatalogSync-Gedanke — test_haussicht_layout.gd wacht darüber).
const RAUM_PLAN := {
	"living": {"fassade": "nord", "etage": 0, "spalte": 0},
	"kitchen": {"fassade": "sued", "etage": 0, "spalte": 0},
	"bedroom": {"fassade": "nord", "etage": 1, "spalte": 1},
	"bathroom": {"fassade": "sued", "etage": 1, "spalte": 1},
}

## Südfassaden-Fenster von HouseExterior (Plot-X), von West nach Ost —
## dieselben x wie in HouseExterior.build(). Jedes Fenster „gehört" dem
## Gartenseiten-Raum derselben Spalte (kitchen links, bathroom rechts).
const SUED_FENSTER_X: Array[float] = [4.2, 8.6]

## Abstand Garten-Nordkante → Südfassade des Hauses: klein genug, dass die
## begehbare RoomBase-Tür (steht bei z = 0) IN der Fassadenebene sitzt und
## als Haustür liest.
const HAUS_SCHWELLE := 0.18


static func plan(room_id: String) -> Dictionary:
	return RAUM_PLAN.get(room_id, {})


## Fassaden-Seite eines Raums ("nord"/"sued"; "" = kein Innenraum).
static func fassade(room_id: String) -> String:
	return str(plan(room_id).get("fassade", ""))


## 0 = Erdgeschoss (Deckenbalken), 1 = Dachgeschoss (Dachschräge).
static func etage(room_id: String) -> int:
	return int(plan(room_id).get("etage", 0))


## Räume der Südfassade (Gartenseite) von West nach Ost — für die
## Fenster-Zuordnung am Garten-Haus.
static func sued_fenster_raeume() -> Array[String]:
	var out: Array[String] = []
	for spalte in SUED_FENSTER_X.size():
		for room_id: String in RAUM_PLAN:
			var eintrag: Dictionary = RAUM_PLAN[room_id]
			if str(eintrag["fassade"]) == FASSADE_GARTEN and int(eintrag["spalte"]) == spalte:
				out.append(room_id)
	return out


## Offset, an dem HouseExterior.build() im GARTEN-Raum stehen muss:
## Haustür (HouseExterior.TUER_X) exakt über der Garten-Tür, Südfassade
## HAUS_SCHWELLE hinter der Garten-Nordkante (z = 0).
static func garten_haus_offset(garden_def: Dictionary) -> Vector3:
	var tuer_x := garten_tuer_x(garden_def)
	return Vector3(tuer_x - HouseExterior.TUER_X, 0.0, -HAUS_SCHWELLE - HouseExterior.FRONT_Z)


## Welt-X der Garten-Tür (Tür in der Nordwand des Gartens).
static func garten_tuer_x(garden_def: Dictionary) -> float:
	for door_def: Dictionary in garden_def.get("doors", []):
		if str(door_def.get("wall", "")) == "N":
			return RoomDefs.door_world_pos(garden_def, door_def).x
	return float(Vector2i(garden_def.get("grid", Vector2i(8, 8))).x) * GridData.CELL_SIZE * 0.5


## Wand-Öffnungen im RoomBase-Format für die Garten-Nordwand: wo die
## Hausfassade die Grundstücksgrenze IST, entfällt der Zaun.
static func zaun_oeffnungen(garden_def: Dictionary, hoehe: float) -> Array[Dictionary]:
	var luecke := garten_zaun_luecke(garden_def)
	if luecke[1] <= luecke[0]:
		return []
	return [{"von": luecke[0], "bis": luecke[1], "y0": 0.0, "y1": hoehe}]


## Zellen-Spanne [von, bis) der Garten-Nordwand, die das Haus einnimmt —
## dort entfällt der Garten-Zaun (die Fassade IST die Grundstücksgrenze).
static func garten_zaun_luecke(garden_def: Dictionary) -> Array[int]:
	var offset := garten_haus_offset(garden_def)
	var west := offset.x + HouseExterior.PLOT.x * 0.5 - HouseExterior.HAUS_BREITE * 0.5
	var ost := west + HouseExterior.HAUS_BREITE
	var breite := int(Vector2i(garden_def.get("grid", Vector2i(8, 8))).x)
	var von := clampi(int(floor(west / GridData.CELL_SIZE)), 0, breite)
	var bis := clampi(int(ceil(ost / GridData.CELL_SIZE)), 0, breite)
	return [von, bis]
