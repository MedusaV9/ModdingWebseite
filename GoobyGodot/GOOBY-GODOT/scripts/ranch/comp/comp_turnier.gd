class_name RanchCompTurnier
extends RefCounted
## Turniertag-Orchestrierung (RW-5) — PURE bis auf die Verbuchung ins
## GameState. Ablauf: Bots werden VOR dem Spielerlauf deterministisch
## simuliert (kein Gummiband), der Spielerlauf kommt aus der 3D-Szene,
## danach: Zielreihenfolge → Platz → Belohnung (Gold/XP/Schleife/Trophäe/
## Liga-Punkte) → Siegerehrung. Gold-Multiplikatoren: Klassenfaktor
## (Kap. 5.1), Turniertag-Bonus und defensiv RW-4s Tribünen-Bonus.

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")
const Bots := preload("res://scripts/ranch/comp/comp_bots.gd")
const Liga := preload("res://scripts/ranch/comp/comp_liga.gd")
const State := preload("res://scripts/ranch/comp/comp_state.gd")

const BOTS_JE_TURNIER := 5


## Bots eines Turniers vorsimulieren (deterministisch aus dem Seed).
## → Array aus Starter-Dicts + {"wert", "zeit_s", "detail"}.
static func bots_simulieren(
	balance: Dictionary, disziplin: String, klasse: String, seed_wert: int
) -> Array:
	var feld := Bots.starterfeld(balance, klasse, disziplin, seed_wert, BOTS_JE_TURNIER)
	for i in feld.size():
		var starter: Dictionary = feld[i]
		var lauf := Bots.simuliere_lauf(
			balance, disziplin, klasse, float(starter["koennen"]), seed_wert + 101 * (i + 1)
		)
		starter.merge(lauf, true)
	return feld


## Endstand: Spieler + Bots nach Wertungsrichtung sortiert.
## spieler = {"wert": float, "zeit_s": float} → Einträge tragen
## ist_spieler/name/pferd; Rückgabe ist die sortierte Liste.
static func endstand(
	balance: Dictionary, disziplin: String, bots: Array, spieler: Dictionary
) -> Array:
	var liste: Array = []
	for bot: Variant in bots:
		if bot is Dictionary:
			var eintrag := (bot as Dictionary).duplicate()
			eintrag["ist_spieler"] = false
			liste.append(eintrag)
	var selbst := spieler.duplicate()
	selbst["ist_spieler"] = true
	selbst["id"] = "spieler"
	liste.append(selbst)
	var kleiner_gewinnt := Katalog.zeit_gewinnt(balance, disziplin)
	liste.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var wa := _num(a.get("wert"), 0.0)
			var wb := _num(b.get("wert"), 0.0)
			return wa < wb if kleiner_gewinnt else wa > wb
	)
	return liste


## Platz (1-basiert) des Spielers im Endstand.
static func spieler_platz(stand: Array) -> int:
	for i in stand.size():
		if bool((stand[i] as Dictionary).get("ist_spieler", false)):
			return i + 1
	return stand.size()


## Belohnung eines Ergebnisses. optionen: {"turniertag": bool,
## "heim_gold_mult": float (RW-4-Tribüne, defensiv 1.0)}.
static func belohnung(
	balance: Dictionary, disziplin: String, klasse: String, platz: int, optionen: Dictionary = {}
) -> Dictionary:
	var gold := float(Katalog.gold_fuer_platz(balance, klasse, platz))
	if bool(optionen.get("turniertag", false)):
		gold *= Liga.bonus_gold_mult(balance)
	gold *= maxf(1.0, _num(optionen.get("heim_gold_mult"), 1.0))
	return {
		"gold": int(round(gold)),
		"xp": Katalog.xp_fuer_teilnahme(balance, klasse),
		"liga_punkte": Liga.punkte_fuer_platz(balance, platz),
		"schleife": Katalog.schleife_verdient(balance, platz),
		"trophaee": Liga.trophaee_fuer(disziplin, klasse, platz),
	}


## Turnier verbuchen: Liga-Punkte/Aufstieg, Schleife, Trophäe, Zähler in
## ranch.comp; Gold in economy.coins. → Bericht für die Siegerehrung:
## {"aufgestiegen", "neue_klasse", "schleife_neu", "trophaee_neu", "gold",
##  "xp", "liga_punkte"}.
static func verbuche(
	gs: Object, balance: Dictionary, disziplin: String, klasse: String, platz: int, lohn: Dictionary
) -> Dictionary:
	var comp := State.lese(gs)
	var punkte: Dictionary = comp["punkte"]
	punkte[klasse] = int(_num(punkte.get(klasse), 0.0)) + int(_num(lohn.get("liga_punkte"), 0.0))
	comp["teilnahmen"] = int(_num(comp.get("teilnahmen"), 0.0)) + 1
	if platz == 1:
		comp["siege"] = int(_num(comp.get("siege"), 0.0)) + 1
	var aufstieg := {"aufgestiegen": false, "klasse": str(comp["klasse"])}
	if klasse == str(comp["klasse"]):
		aufstieg = Liga.pruefe_aufstieg(balance, klasse, int(punkte[klasse]))
		if bool(aufstieg["aufgestiegen"]):
			comp["klasse"] = str(aufstieg["klasse"])
	var schleifen: Dictionary = comp["schleifen"]
	var schl_key := Liga.schleifen_key(disziplin, klasse)
	var schleife_neu := false
	if bool(lohn.get("schleife", false)):
		var bisher := int(_num(schleifen.get(schl_key), 99.0))
		if platz < bisher:
			schleifen[schl_key] = platz
			schleife_neu = true
	var trophaeen: Array = comp["trophaeen"]
	var trophaee := str(lohn.get("trophaee", ""))
	var trophaee_neu := trophaee != "" and not trophaeen.has(trophaee)
	if trophaee_neu:
		trophaeen.append(trophaee)
	State.schreibe(gs, comp)
	_gold_buchen(gs, int(_num(lohn.get("gold"), 0.0)))
	return {
		"aufgestiegen": bool(aufstieg["aufgestiegen"]),
		"neue_klasse": str(aufstieg["klasse"]),
		"schleife_neu": schleife_neu,
		"trophaee_neu": trophaee_neu,
		"gold": int(_num(lohn.get("gold"), 0.0)),
		"xp": int(_num(lohn.get("xp"), 0.0)),
		"liga_punkte": int(_num(lohn.get("liga_punkte"), 0.0)),
	}


## Pferde-XP fürs Turnier ans Pferd im Save buchen (RanchHorseLevels,
## Quelle "wettbewerb" — kein Tagesdeckel). → Buchungs-Bericht.
static func xp_an_pferd(gs: Object, pferd_id: String, menge: float, tag: String) -> Dictionary:
	if gs == null or pferd_id.is_empty():
		return {}
	var pferd: Variant = gs.get_value("ranch.tiere.pferde.%s" % pferd_id, null)
	if not (pferd is Dictionary):
		return {}
	var buchung := RanchHorseLevels.xp_buchen(pferd, menge, "wettbewerb", tag)
	gs.set_value("ranch.tiere.pferde.%s" % pferd_id, buchung["pferd"])
	return buchung


## Bestes Pferd im Stall (höchstes Level, dann höchste Bindung) —
## → {"id": String, "pferd": Dictionary} oder {} ohne Pferde.
static func bestes_pferd(gs: Object) -> Dictionary:
	if gs == null:
		return {}
	var pferde: Variant = gs.get_value("ranch.tiere.pferde", {})
	if not (pferde is Dictionary):
		return {}
	var beste_id := ""
	var bestes: Dictionary = {}
	var beste_wertung := -1.0
	for id: Variant in (pferde as Dictionary).keys():
		var pferd: Variant = (pferde as Dictionary)[id]
		if not (pferd is Dictionary):
			continue
		var wertung := (
			_num((pferd as Dictionary).get("level"), 1.0) * 1000.0
			+ _num((pferd as Dictionary).get("bindung"), 0.0)
		)
		if wertung > beste_wertung:
			beste_wertung = wertung
			beste_id = str(id)
			bestes = pferd
	if beste_id.is_empty():
		return {}
	return {"id": beste_id, "pferd": bestes}


## RW-4s Tribünen-Gold-Bonus defensiv lesen (ohne ranch.bau = 1.0).
static func heim_gold_mult(gs: Object) -> float:
	if gs == null:
		return 1.0
	var bau: Variant = gs.get_value("ranch.bau", null)
	if not (bau is Dictionary):
		return 1.0
	return RanchBauEffekte.heim_gold_mult(bau, RanchBauKatalog.load_balance())


static func _gold_buchen(gs: Object, gold: int) -> void:
	if gs == null or gold <= 0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			if state.get("economy") is Dictionary:
				var economy: Dictionary = state["economy"]
				economy["coins"] = int(economy.get("coins", 0)) + gold
	)


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
