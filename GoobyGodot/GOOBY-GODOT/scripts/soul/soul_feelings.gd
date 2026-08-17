class_name SoulFeelings
extends RefCounted
## FEEL-AC — Ereignis → Gefühl (PURE Statics, Zeit/Zufall werden IMMER
## hereingereicht, headless testbar). Entscheidet deterministisch, WANN eine
## der 12 inszenierten FeelEmotions gespielt werden darf:
##  - EREIGNISSE mappt echte Spielereignisse (Donner, Fund, Ertappt, Rekord,
##    Lieblingsessen, Dunkelheit, Gruß, Kitzeln, …) auf Emotion + Priorität.
##  - Eigene Frequenzbremse NACH dem SoulTriggers-Muster: Mindestabstand,
##    Tagesdeckel, Abstand JE Emotion — Gefühle bleiben besonders, nie Spam.
##  - Tages-Gates für Zustands-Gefühle (Dunkelheit, Müdigkeit, Traurigkeit):
##    höchstens 1× pro Tag, sonst nölt Gooby die ganze Nacht durch.
## Der Zustand lebt als additives "feelings"-Feld im Soul-Slice (SoulState).

## Bremse: Mindestabstand zwischen ZWEI inszenierten Gefühlen …
const MIN_GAP_MS := 20_000
## … Tagesdeckel …
const MAX_PRO_TAG := 25
## … und Abstand, bevor DIESELBE Emotion wieder gespielt wird.
const JE_EMOTION_GAP_MS := 240_000

## Donner-Takt im Gewitter (Sekunden, Zufall wird hereingereicht).
const DONNER_MIN_S := 25.0
const DONNER_MAX_S := 70.0

## Energie-Schwelle, unter der Gooby sichtbar müde wird.
const MUEDE_ENERGIE := 25.0
## Nachtstunden für das Dunkelheits-Gefühl.
const DUNKEL_AB_H := 22
const DUNKEL_BIS_H := 6

## Ereignis → {emotion, prio, gate}. prio: 1 = ambient (unterbricht nie),
## 2 = bemerkenswert, 3 = stark (darf den Mindestabstand UND eine laufende
## schwächere Emotion überstimmen). gate "tag" = höchstens 1× pro Tag.
const EREIGNISSE := {
	"donner": {"emotion": "schreck", "prio": 3, "gate": ""},
	"umgefallen": {"emotion": "schreck", "prio": 3, "gate": ""},
	"fund": {"emotion": "ueberraschung", "prio": 2, "gate": ""},
	"geschenk": {"emotion": "ueberraschung", "prio": 2, "gate": ""},
	"ertappt": {"emotion": "verlegenheit", "prio": 2, "gate": ""},
	"rekord": {"emotion": "stolz", "prio": 3, "gate": ""},
	"lieblingsessen": {"emotion": "verliebtheit", "prio": 3, "gate": ""},
	"essen": {"emotion": "freude", "prio": 1, "gate": ""},
	"dunkelheit": {"emotion": "angst", "prio": 1, "gate": "tag"},
	"gruss_gefreut": {"emotion": "freude", "prio": 2, "gate": ""},
	"gruss_vermisst": {"emotion": "begeisterung", "prio": 2, "gate": ""},
	"gruss_eingeschnappt": {"emotion": "trotz", "prio": 2, "gate": ""},
	"kitzeln": {"emotion": "begeisterung", "prio": 1, "gate": ""},
	"streichel_bonus": {"emotion": "freude", "prio": 1, "gate": ""},
	"muede": {"emotion": "muedigkeit", "prio": 1, "gate": "tag"},
	"vernachlaessigt": {"emotion": "traurigkeit", "prio": 2, "gate": "tag"},
	"neues_moebel": {"emotion": "neugier", "prio": 1, "gate": ""},
}


static func kennt(ereignis: String) -> bool:
	return EREIGNISSE.has(ereignis)


static func emotion_fuer(ereignis: String) -> String:
	return str(EREIGNISSE.get(ereignis, {}).get("emotion", ""))


static func prio(ereignis: String) -> int:
	return int(EREIGNISSE.get(ereignis, {}).get("prio", 0))


# ── Bremsen-Zustand (Soul-Slice "feelings") ───────────────────────────────────


static func default_feelings() -> Dictionary:
	return {"day": "", "count": 0, "lastAt": 0, "je": {}, "gates": {}, "bestMax": 0}


## Self-Heal wie SoulState.normalize_slice — kaputte Typen fallen auf Defaults.
static func normalize(raw: Variant) -> Dictionary:
	var feelings: Dictionary = raw if raw is Dictionary else {}
	var out := default_feelings()
	if feelings.get("day") is String:
		out["day"] = feelings["day"]
	out["count"] = maxi(0, int(_num(feelings.get("count"))))
	out["lastAt"] = maxi(0, int(_num(feelings.get("lastAt"))))
	out["bestMax"] = maxi(0, int(_num(feelings.get("bestMax"))))
	for key: String in ["je", "gates"]:
		if feelings.get(key) is Dictionary:
			out[key] = (feelings[key] as Dictionary).duplicate(true)
	return out


## Darf dieses Ereignis JETZT ein Gefühl auslösen? Prüft Mindestabstand
## (prio 3 überstimmt ihn), Tagesdeckel, Je-Emotion-Abstand und Tages-Gate.
static func erlaubt(feelings: Dictionary, ereignis: String, now_ms: int, today: String) -> bool:
	if not EREIGNISSE.has(ereignis):
		return false
	var def: Dictionary = EREIGNISSE[ereignis]
	var last := int(_num(feelings.get("lastAt")))
	if int(def["prio"]) < 3 and last > 0 and now_ms - last < MIN_GAP_MS:
		return false
	var count := int(_num(feelings.get("count"))) if str(feelings.get("day", "")) == today else 0
	if count >= MAX_PRO_TAG:
		return false
	var je: Dictionary = feelings.get("je", {}) if feelings.get("je") is Dictionary else {}
	var emotion := str(def["emotion"])
	var emotion_last := int(_num(je.get(emotion)))
	if emotion_last > 0 and now_ms - emotion_last < JE_EMOTION_GAP_MS:
		return false
	if str(def["gate"]) == "tag":
		var gates: Dictionary = (
			feelings.get("gates", {}) if feelings.get("gates") is Dictionary else {}
		)
		if str(gates.get(ereignis, "")) == today:
			return false
	return true


## Buchung nach dem Auslösen (neuer Tag setzt den Zähler zurück) — gibt den
## NEUEN feelings-Zustand zurück (Aufrufer persistiert ihn im Slice).
static func buche(feelings: Dictionary, ereignis: String, now_ms: int, today: String) -> Dictionary:
	var out := normalize(feelings)
	if str(out["day"]) != today:
		out["day"] = today
		out["count"] = 0
	out["count"] = int(out["count"]) + 1
	out["lastAt"] = now_ms
	var def: Dictionary = EREIGNISSE.get(ereignis, {})
	if not def.is_empty():
		out["je"][str(def["emotion"])] = now_ms
		if str(def["gate"]) == "tag":
			out["gates"][ereignis] = today
	return out


# ── Deterministische Ereignis-Erkennung ───────────────────────────────────────


## Nächster Donnerschlag im Gewitter (Sekunden; zufall01 wird hereingereicht).
static func donner_intervall_s(zufall01: float) -> float:
	return lerpf(DONNER_MIN_S, DONNER_MAX_S, clampf(zufall01, 0.0, 1.0))


## Nacht = Dunkelheits-Gefühl möglich (Stunde 0..23).
static func ist_dunkel(hour: int) -> bool:
	return hour >= DUNKEL_AB_H or hour < DUNKEL_BIS_H


## Sichtbar müde? (Energie-Stat unter der Schwelle.)
static func ist_muede(stats: Dictionary) -> bool:
	return float(_num(stats.get("energy", 100.0))) < MUEDE_ENERGIE


## Bester Minispiel-Wert über alle Bestwert-Boards (Rekord-Erkennung:
## steigt dieser Wert über feelings.bestMax, ist das ein NEUER Rekord).
static func rekord_max(state: Dictionary) -> int:
	var legacy: Variant = state.get("minigames", {}).get("legacy", {})
	if not legacy is Dictionary:
		return 0
	var top := 0
	for board: String in ["best", "endlessBest"]:
		var eintraege: Variant = legacy.get(board, {})
		if eintraege is Dictionary:
			for spiel: String in eintraege:
				top = maxi(top, int(_num(eintraege[spiel])))
	var by_diff: Variant = legacy.get("bestByDiff", {})
	if by_diff is Dictionary:
		for spiel: String in by_diff:
			var stufen: Variant = by_diff[spiel]
			if stufen is Dictionary:
				for stufe: String in stufen:
					top = maxi(top, int(_num(stufen[stufe])))
	return top


## Ist dieses Essen das Lieblingsessen? (Genug Fütterungen UND meistgegeben —
## dieselbe Regel wie der Lieblingsessen-Kommentar des Runners.)
static func ist_lieblingsessen(food_given: Dictionary, food_id: String, min_anzahl: int) -> bool:
	var anzahl := int(_num(food_given.get(food_id)))
	if anzahl < min_anzahl:
		return false
	for anderes: String in food_given:
		if int(_num(food_given[anderes])) > anzahl:
			return false
	return true


static func _num(value: Variant) -> float:
	if value is float or value is int or value is bool:
		return float(value)
	return 0.0
