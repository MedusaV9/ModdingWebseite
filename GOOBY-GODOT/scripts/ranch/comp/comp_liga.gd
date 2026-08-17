class_name RanchCompLiga
extends RefCounted
## Turnier-Liga (RW-5, IDEAS-1 E1 + IDEAS-3 Kap. 5.1) — PURE Regelwerk.
## Klassen Holz → Bronze → Silber → Gold → Sternenklasse; Aufstieg durch
## Liga-Punkte (Platzierungen), Abstieg gibt es NICHT (Wohlfühlspiel!).
## Starten darf, wer die Klasse in der Liga erreicht hat UND deren
## Pferde-Level-Gate erfüllt (Kap. 5.1). Turniertag: deterministischer
## Wochenplan (3 Disziplinen) mit Bonus-Gold — offline-first aus
## Datum + Seed, kein Server nötig.

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")

## Fallback (== comp_balance.json "liga_punkte_je_platz").
const PUNKTE_JE_PLATZ: Array[int] = [10, 7, 5, 3, 1]


## Liga-Punkte für eine Platzierung: 10/7/5/3, jede weitere Teilnahme 1
## (jeder nimmt IMMER etwas mit — Wohlfühl-Grundsatz).
static func punkte_fuer_platz(balance: Dictionary, platz: int) -> int:
	var tabelle: Variant = balance.get("liga_punkte_je_platz", PUNKTE_JE_PLATZ)
	if not (tabelle is Array) or (tabelle as Array).is_empty():
		tabelle = PUNKTE_JE_PLATZ
	var liste: Array = tabelle
	if platz < 1:
		return 0
	return int(_num(liste[mini(platz, liste.size()) - 1], 1.0))


## Punkte-Schwelle, ab der die Klasse in die nächste aufsteigt (0 = Dach).
static func aufstieg_ab(balance: Dictionary, klasse: String) -> int:
	return int(_num(Katalog.klasse(balance, klasse).get("aufstieg_punkte"), 0.0))


## Aufstiegs-Check: Punkte in der aktuellen Klasse gegen die Schwelle.
## → {"aufgestiegen": bool, "klasse": String} — es geht NUR nach oben.
static func pruefe_aufstieg(
	balance: Dictionary, klasse: String, punkte_in_klasse: int
) -> Dictionary:
	var schwelle := aufstieg_ab(balance, klasse)
	var danach := Katalog.klasse_danach(klasse)
	if schwelle > 0 and danach != "" and punkte_in_klasse >= schwelle:
		return {"aufgestiegen": true, "klasse": danach}
	return {"aufgestiegen": false, "klasse": klasse}


## Darf in dieser Klasse gestartet werden? Liga-Fortschritt UND
## Pferde-Level-Gate müssen beide passen.
static func start_erlaubt(
	balance: Dictionary, liga_klasse: String, start_klasse: String, pferde_level: int
) -> bool:
	if Katalog.klasse_index(start_klasse) > Katalog.klasse_index(liga_klasse):
		return false
	return Katalog.klasse_erlaubt(balance, start_klasse, pferde_level)


## Fortschritts-Anteil (0..1) zur nächsten Klasse (Sternenklasse = 1).
static func aufstieg_fortschritt(balance: Dictionary, klasse: String, punkte: int) -> float:
	var schwelle := aufstieg_ab(balance, klasse)
	if schwelle <= 0:
		return 1.0
	return clampf(float(punkte) / float(schwelle), 0.0, 1.0)


## Deterministischer Turniertag-Plan der Woche: 3 Disziplinen aus Datum
## ("YYYY-MM-DD") + Seed — offline-first, für alle Geräte gleich.
static func turniertag_plan(balance: Dictionary, datum: String, seed_wert: int) -> Dictionary:
	var anzahl := int(_num(_dict(balance, "turniertag").get("disziplinen_je_woche"), 3.0))
	var rng := GoobyRng.new(seed_wert + _wochen_hash(datum))
	var pool: Array = Katalog.DISZIPLINEN.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := int(rng.next() * (i + 1))
		var tausch: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tausch
	var plan: Array = pool.slice(0, clampi(anzahl, 1, pool.size()))
	return {"disziplinen": plan, "bonus_mult": bonus_gold_mult(balance)}


## Bonus-Gold-Multiplikator an Turniertagen (Plan-Disziplinen).
static func bonus_gold_mult(balance: Dictionary) -> float:
	return _num(_dict(balance, "turniertag").get("bonus_gold_mult"), 1.25)


## Schleifen-Schlüssel je Disziplin×Klasse (Boxenwand-Cosmetic).
static func schleifen_key(disziplin: String, klasse: String) -> String:
	return "%s_%s" % [disziplin, klasse]


## Trophäen-Id für die Ranch: erstes Podium je Klasse gibt den Pokal,
## ein Sternenklasse-SIEG je Disziplin den Stern ("" = nichts Neues).
static func trophaee_fuer(disziplin: String, klasse: String, platz: int) -> String:
	if platz == 1 and klasse == "sternenklasse":
		return "stern_%s" % disziplin
	if platz >= 1 and platz <= 3:
		return "pokal_%s" % klasse
	return ""


## Wochen-Hash eines Datums ("YYYY-MM-DD"): Jahr×54 + ISO-nahe Woche —
## stabil genug für den Wochenrhythmus, ohne Kalender-Bibliothek.
static func _wochen_hash(datum: String) -> int:
	var teile := datum.split("-")
	if teile.size() < 3:
		return 0
	var jahr := int(teile[0])
	var tag_im_jahr := (int(teile[1]) - 1) * 31 + (int(teile[2]) - 1)
	return jahr * 54 + tag_im_jahr / 7


static func _dict(source: Dictionary, key: String) -> Dictionary:
	return source[key] if source.get(key) is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
