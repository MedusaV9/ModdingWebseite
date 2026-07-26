extends RefCounted
## Rempel-Auflösung zwischen den Karts (FB-4, Bugfix „Rennen lässt alle
## ineinander fahren"). Die Rennmechanik in ToyRacerLogic bleibt UNANGETASTET
## (zahlengleich zum Web) — sie kennt schlicht keine Kart-gegen-Kart-Kollision.
## Diese Datei läuft als eigener Schritt NACH Logic.step_race und löst
## Überdeckungen sanft auf: kein Durchfahren, aber auch kein Frust —
## seitliche Abdrängung plus einmaliger Tempoverlust für den Auffahrenden.
##
## Alle Maße in Streckeneinheiten (wie `s`/`lateral` der Logik; ein Kart ist
## KART_W = 0,36 Einheiten breit). Verschiebt `s`, wandert `progress` um
## denselben Betrag mit — Runden-/Platzrechnung bleiben konsistent.

const Logic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")

## Mindestabstand längs (Kartlänge ~0,6 Einheiten im car-kit-Seitenverhältnis).
const LEN_MIN := 0.6
## Mindestabstand quer (Kartbreite 0,36 minus Wangenfreiheit).
const LAT_MIN := 0.3
## Seitliche Trenngeschwindigkeit (Einheiten/s) — spürbar, aber kein Schleudern.
const SIDE_PUSH := 1.7
## Längs-Trenngeschwindigkeit, wenn die Karts fast exakt hintereinander stecken.
const BACK_PUSH := 1.2
## Der Auffahrende behält beim ERSTEN Kontakt so viel Tempo (Tempoverlust 18 %).
const REAR_SPEED_KEEP := 0.82
## Der Vordere bekommt einen kleinen Schubs nach vorn.
const FRONT_SPEED_PUSH := 1.04
## Unter diesem Queranteil gilt der Treffer als Auffahren (längs trennen).
const HEAD_ON_LAT := 0.55


## Überdeckungen aller Kart-Paare auflösen. `contacts` gehört dem Aufrufer und
## merkt sich laufende Berührungen (Paar-Schlüssel), damit der Tempoverlust nur
## beim ERSTEN Kontakt zieht statt jeden Frame. Rückgabe: frische Rempler
## [{a, b, rear}] für Sound/Emote in der Spiel-Szene.
static func resolve(race: Dictionary, dt: float, contacts: Dictionary) -> Array[Dictionary]:
	var karts: Array = race["karts"]
	var track: Dictionary = race["track"]
	var lap_len := float(track["lapLen"])
	var tune: Dictionary = race["tune"]
	var hard := float(tune["LAT_HARD_MAX"])
	var events: Array[Dictionary] = []
	var seen := {}
	for i in karts.size():
		for j in range(i + 1, karts.size()):
			var a: Dictionary = karts[i]
			var b: Dictionary = karts[j]
			if bool(a["finished"]) or bool(b["finished"]):
				continue
			var ds := Logic.s_delta(float(b["s"]), float(a["s"]), lap_len)
			var dlat := float(b["lateral"]) - float(a["lateral"])
			if absf(ds) >= LEN_MIN or absf(dlat) >= LAT_MIN:
				continue
			var key := "%d:%d" % [i, j]
			seen[key] = true
			var fresh := not contacts.has(key)
			contacts[key] = true
			_bump(track, a, b, ds, dlat, dt, lap_len, hard, fresh)
			if fresh:
				events.append({"a": i, "b": j, "rear": i if ds >= 0.0 else j})
	for key: String in contacts.keys():
		if not seen.has(key):
			contacts.erase(key)
	return events


## Ein Paar trennen: quer auseinanderdrücken (außer im Looping — dort zwingt
## die Logik targetLateral auf 0, gegengedrückt gäbe das Zittern), längs nur
## bei fast voller Überdeckung; Tempoverlust einmalig beim frischen Kontakt.
static func _bump(
	track: Dictionary,
	a: Dictionary,
	b: Dictionary,
	ds: float,
	dlat: float,
	dt: float,
	lap_len: float,
	hard: float,
	fresh: bool
) -> void:
	var side_sign := 1.0 if dlat >= 0.0 else -1.0
	if absf(dlat) < 0.001:
		side_sign = 1.0 if (int(a["id"]) + int(b["id"])) % 2 == 0 else -1.0
	var in_loop: bool = (
		Logic.in_loop_zone(track, float(a["s"])) or Logic.in_loop_zone(track, float(b["s"]))
	)
	if not in_loop:
		var side := minf(LAT_MIN - absf(dlat), SIDE_PUSH * dt)
		a["lateral"] = clampf(float(a["lateral"]) - side_sign * side * 0.5, -hard, hard)
		b["lateral"] = clampf(float(b["lateral"]) + side_sign * side * 0.5, -hard, hard)
	var rear: Dictionary = a if ds >= 0.0 else b
	var front: Dictionary = b if ds >= 0.0 else a
	if fresh:
		rear["speed"] = float(rear["speed"]) * REAR_SPEED_KEEP
		front["speed"] = float(front["speed"]) * FRONT_SPEED_PUSH
	if absf(dlat) < LAT_MIN * HEAD_ON_LAT:
		var back := minf(LEN_MIN - absf(ds), BACK_PUSH * dt) * 0.5
		_shift(rear, -back, lap_len)
		_shift(front, back, lap_len)


## `s` verschieben und `progress` mitziehen (Runden-/Platzrechnung bleibt wahr).
static func _shift(kart: Dictionary, d: float, lap_len: float) -> void:
	kart["s"] = fposmod(float(kart["s"]) + d, lap_len)
	kart["progress"] = float(kart["progress"]) + d
