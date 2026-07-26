class_name RmpState
extends RefCounted
## Save-Anbindung des Ranch-Multiplayers (RW-6) — ADDITIV im bestehenden
## `ranch`-Slice unter `ranch.mp`, KEIN Version-Bump (Muster RanchCompState:
## fremde Schlüssel überleben RanchPlaySlices.normalize verbatim, geheilt
## wird beim LESEN). Es landen NUR Andenken/Statistik im Save — nie
## Wirtschafts-Werte (Rewards zahlt der aufrufende Code über EconomyService
## aus, hier wird nur idempotent verbucht, welche rewardIds schon da waren).
##
## Struktur:
##   ranch.mp = {
##     v,
##     statistik: {rennen: {teilnahmen, siege}, fangen: {...}, parcours: {...}},
##     verlauf: [{rewardId, mode, kurs, rank, zeitMs, ranked, datum}],  # max 20
##     gesehen: [rewardId, ...],                                        # max 60
##   }

const KEY := "ranch.mp"
const VERLAUF_MAX := 20
const GESEHEN_MAX := 60
const MODI: Array[String] = ["rennen", "fangen", "parcours"]


static func default_mp() -> Dictionary:
	var statistik := {}
	for mode in MODI:
		statistik[mode] = {"teilnahmen": 0, "siege": 0}
	return {"v": 1, "statistik": statistik, "verlauf": [], "gesehen": []}


static func lese(gs: Object) -> Dictionary:
	if gs == null:
		return default_mp()
	return normalize(gs.get_value(KEY, null))


static func schreibe(gs: Object, mp: Dictionary) -> void:
	if gs != null:
		gs.set_value(KEY, mp)


## Self-Heal: Typen reparieren, Deckel einhalten, nichts Fremdes verlieren.
static func normalize(raw: Variant) -> Dictionary:
	var mp: Dictionary = raw.duplicate(true) if raw is Dictionary else default_mp()
	mp["v"] = maxi(1, int(_num(mp.get("v"), 1.0)))
	var statistik_roh: Dictionary = mp.get("statistik") if mp.get("statistik") is Dictionary else {}
	var statistik := {}
	for mode in MODI:
		var eintrag: Dictionary = (
			statistik_roh.get(mode) if statistik_roh.get(mode) is Dictionary else {}
		)
		statistik[mode] = {
			"teilnahmen": maxi(0, int(_num(eintrag.get("teilnahmen"), 0.0))),
			"siege": maxi(0, int(_num(eintrag.get("siege"), 0.0))),
		}
	mp["statistik"] = statistik
	var verlauf_roh: Array = mp.get("verlauf") if mp.get("verlauf") is Array else []
	var verlauf: Array = []
	for eintrag: Variant in verlauf_roh:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("rewardId", "")) != "":
			verlauf.append(eintrag)
	mp["verlauf"] = verlauf.slice(maxi(0, verlauf.size() - VERLAUF_MAX))
	var gesehen_roh: Array = mp.get("gesehen") if mp.get("gesehen") is Array else []
	var gesehen: Array = []
	for id: Variant in gesehen_roh:
		if id is String and not gesehen.has(id):
			gesehen.append(id)
	mp["gesehen"] = gesehen.slice(maxi(0, gesehen.size() - GESEHEN_MAX))
	return mp


## Ergebnis idempotent verbuchen (rewardId-Dedupe, GoobyPal-Muster).
## true = neu verbucht, false = Duplikat (Reconnect-Wiederholung).
static func ergebnis_verbuchen(gs: Object, result: Dictionary) -> bool:
	var reward_id := str(result.get("rewardId", ""))
	if gs == null or reward_id.is_empty():
		return false
	var mp := lese(gs)
	if (mp["gesehen"] as Array).has(reward_id):
		return false
	(mp["gesehen"] as Array).append(reward_id)
	while (mp["gesehen"] as Array).size() > GESEHEN_MAX:
		(mp["gesehen"] as Array).pop_front()
	var mode := str(result.get("mode", ""))
	if MODI.has(mode):
		var eintrag: Dictionary = (mp["statistik"] as Dictionary)[mode]
		eintrag["teilnahmen"] = int(eintrag["teilnahmen"]) + 1
		if int(_num(result.get("rank"), 0.0)) == 1 and not bool(result.get("dnf", false)):
			eintrag["siege"] = int(eintrag["siege"]) + 1
	(
		(mp["verlauf"] as Array)
		. append(
			{
				"rewardId": reward_id,
				"mode": mode,
				"kurs": str(result.get("kurs", "")),
				"rank": int(_num(result.get("rank"), 0.0)),
				"zeitMs": int(_num(result.get("zeitMs"), 0.0)),
				"ranked": bool(result.get("ranked", false)),
				"datum": Time.get_date_string_from_system(),
			}
		)
	)
	while (mp["verlauf"] as Array).size() > VERLAUF_MAX:
		(mp["verlauf"] as Array).pop_front()
	schreibe(gs, mp)
	return true


static func statistik(gs: Object, mode: String) -> Dictionary:
	var eintrag: Variant = (lese(gs).get("statistik", {}) as Dictionary).get(mode)
	return eintrag if eintrag is Dictionary else {"teilnahmen": 0, "siege": 0}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
