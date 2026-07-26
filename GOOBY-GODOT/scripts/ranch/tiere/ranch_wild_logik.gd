class_name RanchWildLogik
extends RefCounted
## Wildtier-Verhalten der Ranch-Region (RW-1) — PURE + headless-testbar.
## Jedes Tier ist ein Dictionary; `schritt()` ist der reine Simulations-
## Schritt (Tests treiben ihn ohne Szene). Verhalten: fressen / trinken /
## ruhen / wandern in kleinen Gruppen, dazu Flucht vor dem Reiter und
## Neugier (Fuchs). Tageszeit + Wetter entscheiden über Aktivität
## (`aktiv()`), das Budget respektiert „Leben reduziert“.

## Artenkatalog: Aktivfenster (Stunden, von>bis = über Mitternacht),
## Radien in m, Tempo m/s, Gruppengröße, Heimat-Radius.
const ARTEN := {
	"reh":
	{
		"aktiv": [[5.0, 11.0], [15.0, 23.0]],
		"flucht_m": 26.0,
		"neugier_m": 0.0,
		"tempo": 3.2,
		"gruppe": 3,
		"heim_radius": 55.0,
		"regen_scheu": true,
	},
	"fuchs":
	{
		"aktiv": [[20.0, 5.5]],
		"flucht_m": 11.0,
		"neugier_m": 30.0,
		"tempo": 2.8,
		"gruppe": 2,
		"heim_radius": 60.0,
		"regen_scheu": false,
	},
	"hase":
	{
		"aktiv": [[6.0, 21.5]],
		"flucht_m": 18.0,
		"neugier_m": 0.0,
		"tempo": 4.2,
		"gruppe": 4,
		"heim_radius": 45.0,
		"regen_scheu": true,
	},
	"ente":
	{
		"aktiv": [[0.0, 24.0]],
		"flucht_m": 9.0,
		"neugier_m": 0.0,
		"tempo": 1.6,
		"gruppe": 5,
		"heim_radius": 40.0,
		"regen_scheu": false,
	},
	"wildpferd":
	{
		"aktiv": [[6.0, 22.0]],
		"flucht_m": 40.0,
		"neugier_m": 0.0,
		"tempo": 5.0,
		"gruppe": 4,
		"heim_radius": 70.0,
		"regen_scheu": false,
	},
}

## Schwarm-/Partikel-Arten (kein Einzelverhalten, nur an/aus + Budget).
const SCHWARM_BUDGET := {"vogel": 22, "schmetterling": 14, "gluehwuermchen": 36}

## Flucht läuft mit diesem Faktor über dem Normaltempo.
const FLUCHT_FAKTOR := 2.2

## Neugier stoppt in diesem Abstand VOR dem Flucht-Radius.
const NEUGIER_STOP_M := 5.0


## Tier-Budget je Art (Instanzen in der Szene). „Leben reduziert“
## (city.lebenReduziert) halbiert Herden und schaltet Schwärme ab.
static func budget(leben_reduziert: bool) -> Dictionary:
	var out := {}
	for art: String in ARTEN:
		var gruppe := int(ARTEN[art]["gruppe"])
		out[art] = maxi(1, gruppe / 2) if leben_reduziert else gruppe
	for art: String in SCHWARM_BUDGET:
		out[art] = 0 if leben_reduziert else int(SCHWARM_BUDGET[art])
	return out


## Ist die Art zu Stunde + Wetter unterwegs? (Rehe/Hasen verstecken sich
## bei Regen/Gewitter; Schwärme haben eigene Regeln.)
static func aktiv(art: String, stunde: float, wetter_typ: String) -> bool:
	var h := fposmod(stunde, 24.0)
	match art:
		"vogel":
			return h >= 6.0 and h < 20.0 and not RanchWetter.REGEN_TYPEN.has(wetter_typ)
		"schmetterling":
			return h >= 9.0 and h < 18.5 and (wetter_typ == "sonne" or wetter_typ == "wolken")
		"gluehwuermchen":
			return (h >= 21.0 or h < 4.5) and wetter_typ != "regen" and wetter_typ != "gewitter"
	if not ARTEN.has(art):
		return false
	var daten: Dictionary = ARTEN[art]
	if bool(daten["regen_scheu"]) and (wetter_typ == "regen" or wetter_typ == "gewitter"):
		return false
	for fenster: Array in daten["aktiv"]:
		var von := float(fenster[0])
		var bis := float(fenster[1])
		if von <= bis:
			if h >= von and h < bis:
				return true
		elif h >= von or h < bis:
			return true
	return false


## Neues Tier an seinem Heimatpunkt (x/z als Vector2).
static func neues_tier(art: String, heim: Vector2, phase := 0.0) -> Dictionary:
	return {
		"art": art,
		"pos": heim,
		"heim": heim,
		"ziel": heim,
		"zustand": "ruhen",
		"timer": 1.0 + phase * 3.0,
		"phase": phase,
	}


## Reiner Verhaltens-Schritt: Zustand + Bewegung. `reiter` = Reiter-Position
## (x/z), `roll` = injizierter Zufall 0..1 für die nächste Beschäftigung.
static func schritt(tier: Dictionary, dt: float, reiter: Vector2, roll: float) -> Dictionary:
	var daten: Dictionary = ARTEN[str(tier["art"])]
	var pos: Vector2 = tier["pos"]
	var abstand := pos.distance_to(reiter)
	if abstand < float(daten["flucht_m"]):
		tier["zustand"] = "flucht"
		var weg := (pos - reiter).normalized() if abstand > 0.01 else Vector2.RIGHT
		tier["ziel"] = _heim_klammer(pos + weg * 34.0, tier, daten)
		tier["timer"] = 1.2
	elif (
		float(daten["neugier_m"]) > 0.0
		and abstand < float(daten["neugier_m"])
		and str(tier["zustand"]) != "flucht"
	):
		tier["zustand"] = "neugier"
		var stop := float(daten["flucht_m"]) + NEUGIER_STOP_M
		if abstand > stop:
			tier["ziel"] = pos + (reiter - pos).normalized() * (abstand - stop)
		else:
			tier["ziel"] = pos
	else:
		tier["timer"] = float(tier["timer"]) - dt
		if float(tier["timer"]) <= 0.0:
			_naechste_beschaeftigung(tier, daten, roll)
	return _bewege(tier, daten, dt)


## Fressen (häufig), Trinken/Wandern (mittel), Ruhen (selten) — kleine
## Ziele rund um den Heimatpunkt, damit Gruppen beisammen bleiben.
static func _naechste_beschaeftigung(tier: Dictionary, daten: Dictionary, roll: float) -> void:
	var heim: Vector2 = tier["heim"]
	var radius := float(daten["heim_radius"])
	var winkel := roll * TAU * 7.31
	if roll < 0.5:
		tier["zustand"] = "fressen"
		tier["ziel"] = heim + Vector2.from_angle(winkel) * radius * 0.35 * (0.3 + roll)
		tier["timer"] = 4.0 + roll * 5.0
	elif roll < 0.7:
		tier["zustand"] = "trinken"
		tier["ziel"] = heim + Vector2.from_angle(winkel) * radius * 0.2
		tier["timer"] = 3.0 + roll * 3.0
	elif roll < 0.9:
		tier["zustand"] = "wandern"
		tier["ziel"] = heim + Vector2.from_angle(winkel) * radius * (0.4 + roll * 0.6)
		tier["timer"] = 5.0 + roll * 4.0
	else:
		tier["zustand"] = "ruhen"
		tier["ziel"] = tier["pos"]
		tier["timer"] = 6.0 + roll * 6.0


static func _bewege(tier: Dictionary, daten: Dictionary, dt: float) -> Dictionary:
	var pos: Vector2 = tier["pos"]
	var ziel: Vector2 = tier["ziel"]
	var abstand := pos.distance_to(ziel)
	if abstand < 0.2:
		if str(tier["zustand"]) == "flucht":
			tier["zustand"] = "ruhen"
			tier["timer"] = 1.0
		return tier
	var tempo := float(daten["tempo"])
	if str(tier["zustand"]) == "flucht":
		tempo *= FLUCHT_FAKTOR
	elif str(tier["zustand"]) == "fressen" or str(tier["zustand"]) == "trinken":
		tempo *= 0.45
	tier["pos"] = pos + (ziel - pos).normalized() * minf(tempo * dt, abstand)
	return tier


## Bewegt sich das Tier gerade? (für Schritt-Animation)
static func laeuft(tier: Dictionary) -> bool:
	return (tier["pos"] as Vector2).distance_to(tier["ziel"]) > 0.25


static func _heim_klammer(ziel: Vector2, tier: Dictionary, daten: Dictionary) -> Vector2:
	var heim: Vector2 = tier["heim"]
	var radius := float(daten["heim_radius"]) * 1.4
	if heim.distance_to(ziel) <= radius:
		return ziel
	return heim + (ziel - heim).normalized() * radius
