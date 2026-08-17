class_name RmpKurse
extends RefCounted
## Kurs-Katalog der Ranch-Minispiele (RW-6) — PURE. MUSS mit
## GOOBY-SERVER/src/ranchmp.js (KURSE + kursHash) synchron bleiben: der
## Client schickt kurs_hash() in MG_READY, der Server markiert bei Mismatch
## den Lauf `unranked` (spielbar bleibt er — Doc RANCH-DLC-IDEAS-4 §2.2).
## Positionen sind Ranch-Welt-Koordinaten (RanchKarte-Zonen: Weidetal für
## die Grasbahn, Hof-Reitplatz für den Parcours, Weide fürs Fangen).

const VERSION := "v1"

## Modus-Ids (Server MODES) + Spielerzahlen.
const MODI: Array[String] = ["besuch", "ausritt", "rennen", "fangen", "parcours"]
const MATCH_MODI: Array[String] = ["rennen", "fangen", "parcours"]
const MAX_SPIELER := {"besuch": 2, "ausritt": 4, "rennen": 4, "fangen": 4, "parcours": 4}

## Gangart-Ids fürs Pose-Relay (Index = `gait` in MG_POSE) — deckungsgleich
## mit RanchCompGhost.GANGARTEN (RW-5-Kontrakt).
const GANGARTEN: Array[String] = ["stand", "schritt", "trab", "toelt", "galopp"]

## Live-Kurse (Spiegel von ranchmp.js KURSE — NICHT umsortieren!).
const KURSE := {
	"grasbahn":
	{
		"mode": "rennen",
		"checkpoints":
		[
			[-330.0, 60.0],
			[-356.0, 102.0],
			[-420.0, 120.0],
			[-484.0, 102.0],
			[-510.0, 60.0],
			[-484.0, 18.0],
			[-420.0, 0.0],
			[-356.0, 18.0],
		],
		"radius": 14.0,
	},
	"hof_parcours":
	{
		"mode": "parcours",
		"checkpoints":
		[
			[60.0, -40.0],
			[90.0, 0.0],
			[60.0, 40.0],
			[90.0, 80.0],
			[60.0, 120.0],
			[20.0, 150.0],
			[-20.0, 120.0],
			[-40.0, 80.0],
		],
		"radius": 10.0,
	},
	"weide_fangen":
	{
		"mode": "fangen",
		"checkpoints": [],
		"arena": [-380.0, 90.0, 70.0],
		"tag_radius": 3.0,
	},
}
const STANDARD_KURS := {"rennen": "grasbahn", "parcours": "hof_parcours", "fangen": "weide_fangen"}

## Asynchrone RW-5-Bestenlisten (Server RW5_WERTUNGEN): richtung "ab" =
## kleinerer Wert gewinnt (Zeit in ms), "auf" = größerer (Punkte).
const RW5_WERTUNGEN := {
	"rw5_springen": "auf",
	"rw5_dressur": "auf",
	"rw5_gelaende": "ab",
	"rw5_rennen": "ab",
	"rw5_trail": "auf",
	"rw5_schau": "auf",
	"rw5_tonnen": "ab",
	"rw5_zeit": "ab",
}


## Sync-Kontrakt mit dem Server: "<kursId>:v1:<checkpointAnzahl>".
static func kurs_hash(kurs_id: String) -> String:
	if not KURSE.has(kurs_id):
		return ""
	var checkpoints: Array = (KURSE[kurs_id] as Dictionary).get("checkpoints", [])
	return "%s:%s:%d" % [kurs_id, VERSION, checkpoints.size()]


static func kurs(kurs_id: String) -> Dictionary:
	return KURSE.get(kurs_id, {}) if KURSE.get(kurs_id) is Dictionary else {}


static func standard_kurs(mode: String) -> String:
	return str(STANDARD_KURS.get(mode, ""))


## Checkpoint-Weltposition (y = 0; Gelände-Höhe setzt die Szene).
static func checkpoint_pos(kurs_id: String, idx: int) -> Vector3:
	var checkpoints: Array = kurs(kurs_id).get("checkpoints", [])
	if idx < 0 or idx >= checkpoints.size():
		return Vector3.ZERO
	var punkt: Array = checkpoints[idx]
	return Vector3(float(punkt[0]), 0.0, float(punkt[1]))


static func checkpoint_anzahl(kurs_id: String) -> int:
	return (kurs(kurs_id).get("checkpoints", []) as Array).size()


static func checkpoint_radius(kurs_id: String) -> float:
	return float(kurs(kurs_id).get("radius", 10.0))


## Ist der Reiter nah genug am Checkpoint `idx`? (XZ-Distanz, Doc §2.7.)
static func checkpoint_erreicht(kurs_id: String, idx: int, pos: Vector3) -> bool:
	var ziel := checkpoint_pos(kurs_id, idx)
	if ziel == Vector3.ZERO and checkpoint_anzahl(kurs_id) == 0:
		return false
	return Vector2(pos.x - ziel.x, pos.z - ziel.z).length() <= checkpoint_radius(kurs_id)


## Startaufstellung: Plätze nebeneinander hinter Checkpoint 0, quer zur
## Laufrichtung (deterministisch aus der Platznummer).
static func start_position(kurs_id: String, platz: int, anzahl: int) -> Vector3:
	var start := checkpoint_pos(kurs_id, 0)
	if checkpoint_anzahl(kurs_id) < 2:
		var arena: Array = kurs(kurs_id).get("arena", [0.0, 0.0, 20.0])
		var winkel := TAU * float(platz) / maxf(1.0, float(anzahl))
		var radius := float(arena[2]) * 0.5
		return Vector3(
			float(arena[0]) + cos(winkel) * radius, 0.0, float(arena[1]) + sin(winkel) * radius
		)
	var richtung := (checkpoint_pos(kurs_id, 1) - start).normalized()
	var quer := Vector3(-richtung.z, 0.0, richtung.x)
	var versatz := (float(platz) - (float(anzahl) - 1.0) * 0.5) * 3.0
	return start - richtung * 6.0 + quer * versatz


## Gangart-Id → Index fürs Pose-Relay (unbekannt → 0 = stand).
static func gait_index(gangart: String) -> int:
	return maxi(0, GANGARTEN.find(gangart))


static func gait_name(index: int) -> String:
	return GANGARTEN[clampi(index, 0, GANGARTEN.size() - 1)]


## Gewinnt bei diesem Bestenlisten-Schlüssel der kleinere Wert?
static func kleiner_gewinnt(kurs_id: String) -> bool:
	if KURSE.has(kurs_id):
		return true
	return str(RW5_WERTUNGEN.get(kurs_id, "ab")) == "ab"


## Alle Bestenlisten-Schlüssel (Live-Kurse ohne Fangen + RW-5).
static func bestenlisten_kurse() -> Array[String]:
	var liste: Array[String] = []
	for kurs_id: String in KURSE:
		if str((KURSE[kurs_id] as Dictionary).get("mode", "")) != "fangen":
			liste.append(kurs_id)
	for rw5_id: String in RW5_WERTUNGEN:
		liste.append(rw5_id)
	return liste
