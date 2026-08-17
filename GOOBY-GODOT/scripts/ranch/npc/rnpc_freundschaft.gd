class_name RNpcFreundschaft
extends RefCounted
## Freundschafts-Mathematik des NPC-Ensembles (RW-3, C2 — expliziter
## User-Wunsch) — PURE + static: arbeitet nur auf dem Freund-Dictionary
## (RQuestSlices.neuer_freund-Form) + NPC-Definition (RNpcKatalog-Form).
##
## Design: Punkte 0..100 → Herzen 0..5 über HERZ_SCHWELLEN. Steigerung
## durch Reden (1x täglich voll), Geschenke (Vorlieben zählen doppelt,
## 1 Geschenk-Bonus pro Tag), Quests (Abgabe beim Questgeber). Verfall ist
## GEBREMST: erst nach KARENZ_TAGE Abwesenheit, dann VERFALL_PRO_TAG,
## gedeckelt auf VERFALL_MAX — und NIE unter die Schwelle der erreichten
## Herz-Stufe (Freischaltungen gehen nie wieder verloren; Anti-Tamagotchi,
## §5-Nicht-Ziele). Es gibt keinerlei negative Aktionen: das schlechteste
## Geschenk gibt +1 („höfliches Nicken“), nie Abzug.

## Punkte-Schwellen für Herz 0..5 (Index = Herz).
const HERZ_SCHWELLEN: Array[int] = [0, 10, 25, 45, 70, 100]
const HERZ_MAX := 5

const REDEN_PUNKTE := 3.0
const REDEN_TROST := 0.5
const GESCHENK_LIEBT := 12.0
const GESCHENK_MAG := 6.0
const GESCHENK_NORMAL := 3.0
const GESCHENK_TROST := 1.0
const QUEST_PUNKTE := 8.0

const KARENZ_TAGE := 7
const VERFALL_PRO_TAG := 1.0
const VERFALL_MAX := 10.0
const MS_PRO_TAG := 86_400_000


## Herz-Stufe (0..5) zu einem Punktestand.
static func herzen(punkte: float) -> int:
	var stufe := 0
	for i in HERZ_SCHWELLEN.size():
		if punkte >= float(HERZ_SCHWELLEN[i]):
			stufe = i
	return stufe


## Punkte bis zur nächsten Herz-Stufe (0 bei Herz 5) — fürs UI.
static func punkte_bis_naechste(punkte: float) -> float:
	var stufe := herzen(punkte)
	if stufe >= HERZ_MAX:
		return 0.0
	return maxf(0.0, float(HERZ_SCHWELLEN[stufe + 1]) - punkte)


## Gebremster Verfall: erst nach KARENZ_TAGE ohne Begegnung, dann
## VERFALL_PRO_TAG pro weiterem Tag, höchstens VERFALL_MAX — und nie
## unter die Schwelle der bereits erreichten Herz-Stufe.
static func punkte_nach_verfall(punkte: float, letzte_begegnung_ms: int, now_ms: int) -> float:
	if letzte_begegnung_ms <= 0 or now_ms <= letzte_begegnung_ms:
		return punkte
	var tage := float(now_ms - letzte_begegnung_ms) / float(MS_PRO_TAG)
	if tage <= float(KARENZ_TAGE):
		return punkte
	var verfall := minf((tage - float(KARENZ_TAGE)) * VERFALL_PRO_TAG, VERFALL_MAX)
	var boden := float(HERZ_SCHWELLEN[herzen(punkte)])
	return maxf(boden, punkte - verfall)


## Gespräch buchen → neuer Freund-Stand (Kopie). Erstes Gespräch des Tages
## gibt REDEN_PUNKTE, weitere nur REDEN_TROST (kein Spam-Grind).
static func reden(freund: Dictionary, tag: String, now_ms: int) -> Dictionary:
	var neu := _frisch(freund, now_ms)
	var gewinn := REDEN_PUNKTE if str(neu.get("geredetTag", "")) != tag else REDEN_TROST
	neu["geredetTag"] = tag
	neu["punkte"] = clampf(float(neu["punkte"]) + gewinn, 0.0, 100.0)
	return neu


## Geschenk buchen → neuer Freund-Stand. Reaktion (liebt/mag/normal) hängt
## an den Vorlieben der NPC-Definition; nur das erste Geschenk des Tages
## zählt voll, weitere geben GESCHENK_TROST.
static func geschenk(
	freund: Dictionary, npc_def: Dictionary, item: String, tag: String, now_ms: int
) -> Dictionary:
	var neu := _frisch(freund, now_ms)
	var gewinn := GESCHENK_TROST
	if str(neu.get("geschenkTag", "")) != tag:
		gewinn = _geschenk_punkte(npc_def, item)
	neu["geschenkTag"] = tag
	neu["punkte"] = clampf(float(neu["punkte"]) + gewinn, 0.0, 100.0)
	return neu


## Reaktions-Kategorie eines Geschenks ("liebt"/"mag"/"normal") — steuert
## auch den Dialog-Einstieg (RNpcDialog.geschenk_knoten).
static func geschenk_reaktion(npc_def: Dictionary, item: String) -> String:
	var vorlieben: Dictionary = (
		npc_def.get("geschenke") if npc_def.get("geschenke") is Dictionary else {}
	)
	if (vorlieben.get("liebt", []) as Array).has(item):
		return "liebt"
	if (vorlieben.get("mag", []) as Array).has(item):
		return "mag"
	return "normal"


## Quest-Abgabe beim Questgeber buchen (+ direkte Herz-Punkte aus der
## Belohnung bucht der Aufrufer über bonus()).
static func quest_abgeschlossen(freund: Dictionary, now_ms: int) -> Dictionary:
	return bonus(freund, QUEST_PUNKTE, now_ms)


## Freie Punkte-Gutschrift (Quest-Belohnungen `herzen`) — verfallt vorher.
static func bonus(freund: Dictionary, punkte: float, now_ms: int) -> Dictionary:
	var neu := _frisch(freund, now_ms)
	neu["punkte"] = clampf(float(neu["punkte"]) + maxf(0.0, punkte), 0.0, 100.0)
	return neu


## Freischaltungen GENAU einer Stufe (Liste aus der NPC-Definition).
static func freischaltungen_der_stufe(npc_def: Dictionary, stufe: int) -> Array:
	var alle: Dictionary = (
		npc_def.get("freischaltungen") if npc_def.get("freischaltungen") is Dictionary else {}
	)
	var raw: Variant = alle.get(str(stufe), [])
	return raw if raw is Array else []


## Alle bis inkl. `stufe` freigeschalteten Einträge.
static func freischaltungen_bis(npc_def: Dictionary, stufe: int) -> Array:
	var out: Array = []
	for i in range(1, mini(stufe, HERZ_MAX) + 1):
		out.append_array(freischaltungen_der_stufe(npc_def, i))
	return out


## Was zwischen zwei Punktestände NEU freigeschaltet wurde (für Toasts).
static func neue_freischaltungen(
	npc_def: Dictionary, punkte_vorher: float, punkte_nachher: float
) -> Array:
	var out: Array = []
	for stufe in range(herzen(punkte_vorher) + 1, herzen(punkte_nachher) + 1):
		out.append_array(freischaltungen_der_stufe(npc_def, stufe))
	return out


## Verfall anwenden + Begegnung stempeln (jede Interaktion zählt als
## Begegnung — der Verfall-Zähler startet neu).
static func _frisch(freund: Dictionary, now_ms: int) -> Dictionary:
	var neu: Dictionary = freund.duplicate(true)
	neu["punkte"] = punkte_nach_verfall(
		float(neu.get("punkte", 0.0)), int(neu.get("letzteBegegnungAt", 0)), now_ms
	)
	neu["letzteBegegnungAt"] = now_ms
	return neu


static func _geschenk_punkte(npc_def: Dictionary, item: String) -> float:
	match geschenk_reaktion(npc_def, item):
		"liebt":
			return GESCHENK_LIEBT
		"mag":
			return GESCHENK_MAG
		_:
			return GESCHENK_NORMAL
