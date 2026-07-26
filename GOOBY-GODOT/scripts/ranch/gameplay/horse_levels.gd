class_name RanchHorseLevels
extends RefCounted
## Pferde-Level + Training (RW-2, RANCH-DLC-IDEAS-3 Kap. 2) — PURE
## Stat-Mathe in der stats.gd-Handschrift: alles static, Dictionaries
## rein, NEUE Dictionaries raus, Zeit/Tag kommen als Parameter.
##
## Zwei Achsen am Pferde-Dict (Felder additiv, RanchPlaySlices heilt):
##   Pferde-Level 1–30: `xp` (Gesamt), `level`; Kurve XP(L→L+1) = 30·L + L².
##   Training: 5 Werte je `Rassenbasis (stats) + trainiert (0–10)`, Deckel
##   20; Stat-XP fliesst durchs REITEN (Training durch Tun), Punkte werden
##   automatisch vergeben, sobald XP UND Level-Gate (⌈Level/3⌉) reichen.
## Trainingsfrische (Kap. 2.3) bremst Grind: 100/Tag je Wert, eine
## Einheit (~3 min) kostet 35 (fleissig 30), Faktor max(0,15; frische/100).

const LEVEL_MAX := 30
const STAT_KEYS: Array[String] = RanchRassen.STAT_KEYS

## Trainierte Punkte: Kosten 100·1,4^p, maximal +10 je Wert.
const PUNKT_KOSTEN_BASIS := 100.0
const PUNKT_KOSTEN_FAKTOR := 1.4
const PUNKTE_MAX := 10
## Level-Gate: max. trainierte Punkte je Wert = ceil(Level / 3).
const GATE_LEVEL_JE_PUNKT := 3.0

## Trainingsfrische je Wert und Tag.
const FRISCHE_MAX := 100.0
const FRISCHE_EINHEIT_S := 180.0
const FRISCHE_VERBRAUCH := 35.0
const FRISCHE_FAKTOR_MIN := 0.15
const HAFERMASH_FRISCHE := 25.0

## Stat-XP-Raten (Kap. 2.2: Training durch Tun).
const RATE_GALOPP_XP_JE_50M := 1.0
const RATE_AUSDAUER_XP_JE_MIN := 2.0
const RATE_SPRUNG_GUT := 4.0
const RATE_SPRUNG_PERFEKT := 8.0
const RATE_SLALOM_TOR := 2.0
const RATE_SCHRITT_LAUNE_JE_MIN := 3.0
const SCHRITT_LAUNE_AB := 60.0
## Fokussierte Aktivzeit je Einzelaktion (frisst Frische anteilig).
const AKTIV_S_JE_SPRUNG := 20.0
const AKTIV_S_JE_SLALOM_TOR := 12.0

## Pferde-XP-Quellen (Kap. 2.2).
const XP_RITT_PRO_MIN := 4.0
const XP_RITT_TAGES_DECKEL := 60.0
const XP_MINISPIEL_STERN := 20.0
const XP_ERSTE_PFLEGE := 5.0
const XP_FOHLEN_AUFGABE := 25.0
const XP_WETTBEWERB := {"holz": 60, "bronze": 90, "silber": 130, "gold": 180, "sternenklasse": 240}

## Jungpferde lernen schnell (×1,2), sind aber bei 15 gedeckelt (Kap. 4.4).
const JUNGPFERD_STAT_DECKEL := 15
const JUNGPFERD_STATXP_MULT := 1.2

## Meilenstein-Geschenke (Kap. 2.5) — Ids, die UI/Cosmetics ausspielen.
const MEILENSTEINE := {
	5: "schleife_jungstar",
	10: "maehnenfrisur",
	15: "sattel_gold",
	20: "fanpost_besuch",
	25: "namensschild_gold",
	30: "statue_legende",
}


## XP fuer den Uebergang L → L+1 (31, …, 1711; Σ 1→30 ≈ 21 600).
static func xp_fuer_level(level: int) -> float:
	var l := maxi(1, level)
	return 30.0 * l + float(l * l)


## Gesamt-XP, die noetig sind, um Level `level` zu ERREICHEN.
static func xp_summe_bis(level: int) -> float:
	var summe := 0.0
	for l in range(1, clampi(level, 1, LEVEL_MAX)):
		summe += xp_fuer_level(l)
	return summe


## Level (1–30) fuer eine Gesamt-XP-Zahl.
static func level_fuer_xp(xp: float) -> int:
	var rest := maxf(0.0, xp)
	var level := 1
	while level < LEVEL_MAX and rest >= xp_fuer_level(level):
		rest -= xp_fuer_level(level)
		level += 1
	return level


## Fortschritt im aktuellen Level: {"level", "im_level", "noetig", "anteil"}.
static func level_fortschritt(xp: float) -> Dictionary:
	var level := level_fuer_xp(xp)
	var im_level := maxf(0.0, xp) - xp_summe_bis(level)
	var noetig := xp_fuer_level(level)
	if level >= LEVEL_MAX:
		return {"level": level, "im_level": 0.0, "noetig": 0.0, "anteil": 1.0}
	return {
		"level": level,
		"im_level": im_level,
		"noetig": noetig,
		"anteil": clampf(im_level / noetig, 0.0, 1.0),
	}


## Pferde-XP buchen. quelle: "ritt" (unterliegt dem Tagesdeckel 60),
## "stern", "wettbewerb", "pflege", "fohlen", "direkt". Pure — liefert
## {"pferd": neues Dict, "gewinn": f, "levelUps": Array[int],
##  "meilensteine": Array[String]}.
static func xp_buchen(pferd: Dictionary, menge: float, quelle: String, tag: String) -> Dictionary:
	var p := pferd.duplicate(true)
	_tag_reset(p, tag)
	var gewinn := maxf(0.0, menge)
	if quelle == "ritt":
		var heute := _num(p.get("rittXpHeute"), 0.0)
		gewinn = minf(gewinn, maxf(0.0, XP_RITT_TAGES_DECKEL - heute))
		p["rittXpHeute"] = heute + gewinn
	if quelle == "stern" and _hat_zug(p, "verspielt"):
		gewinn *= _effekt(p, "stern_xp_mult", 1.0)
	var vorher := level_fuer_xp(_num(p.get("xp"), 0.0))
	var xp_max := xp_summe_bis(LEVEL_MAX)
	p["xp"] = minf(xp_max, _num(p.get("xp"), 0.0) + gewinn)
	var nachher := level_fuer_xp(_num(p.get("xp"), 0.0))
	p["level"] = nachher
	var ups: Array = []
	var geschenke: Array = []
	for l in range(vorher + 1, nachher + 1):
		ups.append(l)
		if MEILENSTEINE.has(l):
			geschenke.append(MEILENSTEINE[l])
	return {"pferd": p, "gewinn": gewinn, "levelUps": ups, "meilensteine": geschenke}


## Effektiver Trainingswert 1–20: Rassenbasis + trainierte Punkte;
## Jungpferde deckeln bei 15.
static func stat_wert(pferd: Dictionary, stat: String) -> int:
	var basis := int(_num(_dict(pferd, "stats").get(stat), 10.0))
	var punkte := int(_num(_dict(pferd, "trainiert").get(stat), 0.0))
	var deckel := 20
	if str(pferd.get("alter", "ausgewachsen")) == "jungpferd":
		deckel = JUNGPFERD_STAT_DECKEL
	return clampi(basis + punkte, 1, deckel)


## Alle 5 effektiven Werte auf einmal.
static func stats_effektiv(pferd: Dictionary) -> Dictionary:
	var out := {}
	for k in STAT_KEYS:
		out[k] = stat_wert(pferd, k)
	return out


## Level-Gate: maximal trainierbare Punkte je Wert bei diesem Level.
static func stat_gate(level: int) -> int:
	return mini(PUNKTE_MAX, int(ceil(clampi(level, 1, LEVEL_MAX) / GATE_LEVEL_JE_PUNKT)))


## Stat-XP-Kosten fuer den Punkt p → p+1 (p = schon trainierte Punkte).
static func punkt_kosten(p: int) -> float:
	return PUNKT_KOSTEN_BASIS * pow(PUNKT_KOSTEN_FAKTOR, maxi(0, p))


## Frische-Multiplikator auf Stat-XP: max(0,15; frische/100).
static func frische_faktor(frische: float) -> float:
	return maxf(FRISCHE_FAKTOR_MIN, frische / FRISCHE_MAX)


## Stat-XP buchen (Training durch Tun): wendet Frische-Faktor + Zuege an,
## verbraucht Frische anteilig (aktiv_s / 180 einer Einheit) und vergibt
## reife Punkte sofort (Ueberlauf gebankt, Deckel 1 Punkt Vorrat).
## Pure — {"pferd", "xp_effektiv", "neue_punkte": int}.
static func stat_xp_buchen(
	pferd: Dictionary, stat: String, xp_menge: float, aktiv_s: float, tag: String
) -> Dictionary:
	var p := pferd.duplicate(true)
	_tag_reset(p, tag)
	if not STAT_KEYS.has(stat):
		return {"pferd": p, "xp_effektiv": 0.0, "neue_punkte": 0}
	var frische: Dictionary = _dict(p, "frische")
	var faktor := frische_faktor(_num(frische.get(stat), FRISCHE_MAX))
	var mult := 1.0
	if stat == "gelassenheit" and _hat_zug(p, "stur"):
		mult *= _effekt(p, "gelassenheit_statxp_mult", 1.0)
	if str(p.get("alter", "ausgewachsen")) == "jungpferd":
		mult *= JUNGPFERD_STATXP_MULT
	var effektiv := maxf(0.0, xp_menge) * faktor * mult
	var statxp: Dictionary = _dict(p, "statXp")
	statxp[stat] = _num(statxp.get(stat), 0.0) + effektiv
	p["statXp"] = statxp
	var verbrauch := FRISCHE_VERBRAUCH
	if _hat_zug(p, "fleissig"):
		verbrauch = _effekt(p, "frische_verbrauch", FRISCHE_VERBRAUCH)
	var alt := _num(frische.get(stat), FRISCHE_MAX)
	var neu := alt - verbrauch * maxf(0.0, aktiv_s) / FRISCHE_EINHEIT_S
	frische[stat] = clampf(neu, 0.0, FRISCHE_MAX)
	p["frische"] = frische
	var punkte := _punkte_vergeben(p, stat)
	return {"pferd": p, "xp_effektiv": effektiv, "neue_punkte": punkte}


## Hafermash: +25 Frische auf EINEN Wert, 1×/Tag/Wert (kleine Gold-Senke).
## Pure — {"ok": bool, "pferd": Dictionary}.
static func hafermash(pferd: Dictionary, stat: String, tag: String) -> Dictionary:
	var p := pferd.duplicate(true)
	_tag_reset(p, tag)
	var mash_tag: Dictionary = _dict(p, "mashTag")
	if not STAT_KEYS.has(stat) or str(mash_tag.get(stat, "")) == tag:
		return {"ok": false, "pferd": p}
	mash_tag[stat] = tag
	p["mashTag"] = mash_tag
	var frische: Dictionary = _dict(p, "frische")
	frische[stat] = clampf(
		_num(frische.get(stat), FRISCHE_MAX) + HAFERMASH_FRISCHE, 0.0, FRISCHE_MAX
	)
	p["frische"] = frische
	return {"ok": true, "pferd": p}


## Reit-Telemetrie in Training + Pferde-XP uebersetzen. telemetrie:
## {"galopp_m", "galopp_s"?, "unterwegs_min", "sprung_gut",
##  "sprung_perfekt", "slalom_tore", "schritt_laune_min"}. Pure —
## {"pferd", "levelUps", "meilensteine", "neue_punkte": Dict je Stat}.
static func ritt_training(pferd: Dictionary, telemetrie: Dictionary, tag: String) -> Dictionary:
	var minuten := maxf(0.0, _num(telemetrie.get("unterwegs_min"), 0.0))
	var galopp_m := maxf(0.0, _num(telemetrie.get("galopp_m"), 0.0))
	var galopp_s := _num(telemetrie.get("galopp_s"), galopp_m / 8.5)
	var spruenge := (
		_num(telemetrie.get("sprung_gut"), 0.0) + _num(telemetrie.get("sprung_perfekt"), 0.0)
	)
	var schritt_min := maxf(0.0, _num(telemetrie.get("schritt_laune_min"), 0.0))
	# [stat, Stat-XP, fokussierte Aktivzeit in s (frisst Frische)]
	var buchungen := [
		["tempo", galopp_m / 50.0 * RATE_GALOPP_XP_JE_50M, galopp_s],
		["ausdauer", minuten * RATE_AUSDAUER_XP_JE_MIN, minuten * 60.0],
		[
			"sprungkraft",
			(
				_num(telemetrie.get("sprung_gut"), 0.0) * RATE_SPRUNG_GUT
				+ _num(telemetrie.get("sprung_perfekt"), 0.0) * RATE_SPRUNG_PERFEKT
			),
			spruenge * AKTIV_S_JE_SPRUNG,
		],
		[
			"wendigkeit",
			_num(telemetrie.get("slalom_tore"), 0.0) * RATE_SLALOM_TOR,
			_num(telemetrie.get("slalom_tore"), 0.0) * AKTIV_S_JE_SLALOM_TOR,
		],
		["gelassenheit", schritt_min * RATE_SCHRITT_LAUNE_JE_MIN, schritt_min * 60.0],
	]
	var p := pferd.duplicate(true)
	var punkte := {}
	for eintrag: Array in buchungen:
		var stat: String = eintrag[0]
		var xp: float = eintrag[1]
		if xp <= 0.0:
			continue
		var ergebnis := stat_xp_buchen(p, stat, xp, float(eintrag[2]), tag)
		p = ergebnis["pferd"]
		if int(ergebnis["neue_punkte"]) > 0:
			punkte[stat] = int(ergebnis["neue_punkte"])
	var xp_ergebnis := xp_buchen(p, minuten * XP_RITT_PRO_MIN, "ritt", tag)
	return {
		"pferd": xp_ergebnis["pferd"],
		"levelUps": xp_ergebnis["levelUps"],
		"meilensteine": xp_ergebnis["meilensteine"],
		"neue_punkte": punkte,
	}


## ------------------------------------------------------------------ intern


## Reife Punkte fuer einen Wert vergeben: solange XP + Gate + Deckel es
## erlauben; danach XP auf 1 Punkt Vorrat kappen. Gibt Anzahl neuer Punkte.
static func _punkte_vergeben(p: Dictionary, stat: String) -> int:
	var trainiert: Dictionary = _dict(p, "trainiert")
	var statxp: Dictionary = _dict(p, "statXp")
	var gate := stat_gate(int(_num(p.get("level"), 1.0)))
	var punkte := int(_num(trainiert.get(stat), 0.0))
	var xp := _num(statxp.get(stat), 0.0)
	var neu := 0
	while punkte < gate and punkte < PUNKTE_MAX and xp >= punkt_kosten(punkte):
		xp -= punkt_kosten(punkte)
		punkte += 1
		neu += 1
	statxp[stat] = minf(xp, punkt_kosten(punkte))
	trainiert[stat] = punkte
	p["trainiert"] = trainiert
	p["statXp"] = statxp
	return neu


## Tageswechsel (bondTag-Muster): Frische + Ritt-Deckel zuruecksetzen.
static func _tag_reset(p: Dictionary, tag: String) -> void:
	if str(p.get("frischeTag", "")) == tag:
		return
	p["frischeTag"] = tag
	var frische := {}
	for k in STAT_KEYS:
		frische[k] = FRISCHE_MAX
	p["frische"] = frische
	p["rittXpHeute"] = 0.0


static func _hat_zug(p: Dictionary, zug: String) -> bool:
	var charakter: Variant = p.get("charakter")
	return charakter is Array and (charakter as Array).has(zug)


## Effekt-Wert eines Charakterzugs des Pferds (erster Treffer gewinnt).
static func _effekt(p: Dictionary, key: String, fallback: float) -> float:
	var charakter: Variant = p.get("charakter")
	if charakter is Array:
		for zug: Variant in charakter:
			var effekte := RanchRassen.charakter_effekte(str(zug))
			if effekte.has(key):
				return _num(effekte.get(key), fallback)
	return fallback


static func _dict(p: Dictionary, key: String) -> Dictionary:
	var raw: Variant = p.get(key)
	return raw if raw is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
