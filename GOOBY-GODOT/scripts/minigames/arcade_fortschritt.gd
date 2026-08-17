class_name ArcadeFortschritt
extends RefCounted
## Arcade-Fortschritt (W20 Top-10 #4) — pure, headless testbare Logik für
## die Kachel-Sterne, den Gesamt-Fortschritts-Kopf und die Kategorien-
## Reihen der Arcade-Wand. KEINE Node-/OS-Zugriffe: State + Registry-Meta
## kommen IMMER injiziert (AGENTS.md-Muster wie arcade_spotlight.gd).
##
## STERNE-REGEL (abgeleitet aus den VORHANDENEN v5-Save-Feldern — der
## Award-Pfad minigame_award.gd schreibt `minigames.plays[id]` und die
## §G5.7-4-Boards `minigames.legacy.best/bestByDiff/endlessBest/beaten`):
## - 0 Sterne — nie gespielt: kein plays-Zähler, keine Boards, kein beaten.
## - 1 Stern — einmal zu Ende gespielt: plays[id] > 0 (defensiv zählt auch
##   ein vorhandenes Board/beaten als „gespielt“, falls ein Alt-Save den
##   plays-Zähler nicht kennt — die Boards entstehen nur durch Spielen).
## - 2 Sterne — Ziel geschafft: legacy.beaten[id] enthält irgendeinen
##   true-Modus (easy/normal/hard — der Award-Pfad setzt den Eintrag ab
##   score >= target, Endlos setzt nie beaten).
## - 3 Sterne — gemeistert: beaten[id].hard == true (die harte Zielmarke,
##   zugleich die Spiel-Bedingung des Endlos-Locks §G5.5 — „Endless
##   freigeschaltet“ ist damit abgedeckt, der Level-Teil des Locks ist
##   global und gehört nicht zur Spiel-Kachel) ODER ein Timed-Board
##   (legacy.best / legacy.bestByDiff) erreicht REKORD_FAKTOR × target.
##   endlessBest zählt beim Rekord bewusst NICHT: Endlos-Scores wachsen
##   unbegrenzt und setzen beaten.hard ohnehin voraus.
##
## KATEGORIEN-REIHEN (die Registry/Manifeste kennen KEINE Kategorien —
## Zuordnung hier abgeleitet aus Spielprinzip + Titel, je Spiel GENAU eine
## Reihe; der W20-Wächter erzwingt Vollständigkeit für jede Registry-Id):
## - geschick „Geschick & Timing“: Zielen/Stapeln/Takt — teaParty
##   (Teestube-Einschenken), danceParty (Tanz-Takt), burgerBuild,
##   pancakeTower (Stapeln), veggieChop (Schnippeln), basketBounce
##   (Korbwurf), bubblePop (Tipp-Timing), trampoline (Trick-Timing).
## - action „Tempo & Action“: Rennen/Fangen/Ausweichen/Verteidigen —
##   carrotCatch, carrotGuard, gvz (Lane-Verteidigung), gardenRush,
##   ghostHunt, goalieGooby, harborHopper, rocketRescue, runner,
##   shoppingSurf, starHopper, bunnyHop.
## - fahren „Fahren & Liefern“: Fahrzeug/Zustellung — cityDrive,
##   deliveryRush, toyRacer, snailMail (Schneckenpost).
## - denken „Puzzle & Denken“: Merken/Knobeln — memoryMatch, goobySays,
##   pipeFlow, purblePlace, hideSeek (Suchbild), gobnom (Level-Puzzle).
## - ranch „Ranch & Turnier“: die 5 Ranch-Wettbewerbe — ranchHerde,
##   ranchParcours, ranchTonnen, ranchTurnier, ranchZeit.
## - ruhig „Ruhig & Gemütlich“: entspannte Spiele — fishingPond,
##   lanternFloat, miniGolf.
## Unbekannte (künftige) Ids fallen in FALLBACK_REIHE, damit jede Kachel
## IMMER eine Reihe hat — der Wächter zwingt neue Spiele trotzdem zur
## bewussten Zuordnung.

## 3-Sterne-Rekordschwelle: Timed-Best >= 1.5 × Zielwert des Spiels.
const REKORD_FAKTOR := 1.5

## Reihen-Reihenfolge der Wand (geschick zuerst: dort liegt teaParty, die
## erste Kachel der Registry — der Arcade-Einstieg bleibt wie gewohnt oben).
const REIHEN_ORDNUNG: Array[String] = ["geschick", "action", "fahren", "denken", "ranch", "ruhig"]
## Reihe für nicht zugeordnete (künftige) Spiele-Ids.
const FALLBACK_REIHE := "action"
## Explizite Zuordnung Spiel-Id → Reihe (Begründung: Datei-Kopf).
const REIHEN_IDS := {
	"geschick":
	[
		"teaParty",
		"danceParty",
		"burgerBuild",
		"pancakeTower",
		"veggieChop",
		"basketBounce",
		"bubblePop",
		"trampoline",
	],
	"action":
	[
		"carrotCatch",
		"carrotGuard",
		"gvz",
		"gardenRush",
		"ghostHunt",
		"goalieGooby",
		"harborHopper",
		"rocketRescue",
		"runner",
		"shoppingSurf",
		"starHopper",
		"bunnyHop",
	],
	"fahren": ["cityDrive", "deliveryRush", "toyRacer", "snailMail"],
	"denken": ["memoryMatch", "goobySays", "pipeFlow", "purblePlace", "hideSeek", "gobnom"],
	"ranch": ["ranchHerde", "ranchParcours", "ranchTonnen", "ranchTurnier", "ranchZeit"],
	"ruhig": ["fishingPond", "lanternFloat", "miniGolf"],
}
## I18n-Konvention der Reihen-Header (mg.arcade.reihe.<key>, DE/EN-paritätisch).
const REIHE_TITEL_PREFIX := "mg.arcade.reihe."


## Sterne (0..3) eines Spiels aus dem Save — Regel: Datei-Kopf. `meta` ist
## der Registry-Eintrag (braucht "id" + "target"). Wirft nie (kaputte
## Saves/Metas ergeben 0 Sterne statt Fehler).
static func sterne(state: Dictionary, meta: Dictionary) -> int:
	var id := str(meta.get("id", ""))
	if id.is_empty():
		return 0
	var mg := _dict(state.get("minigames"))
	var legacy := _dict(mg.get("legacy"))
	var beaten := _dict(_dict(legacy.get("beaten")).get(id))
	var best := bester_timed_score(legacy, id)
	var gespielt := (
		int(_num(_dict(mg.get("plays")).get(id))) > 0
		or best > 0
		or int(_num(_dict(legacy.get("endlessBest")).get(id))) > 0
		or _hat_true(beaten)
	)
	if not gespielt:
		return 0
	if not _hat_true(beaten):
		return 1
	var target := int(_num(meta.get("target"), -1.0))
	var rekord := target > 0 and best >= int(ceilf(float(target) * REKORD_FAKTOR))
	if beaten.get("hard", false) == true or rekord:
		return 3
	return 2


## Bester TIMED-Score über alle Boards (best = Mittel-Board, bestByDiff =
## easy/hard) — endlessBest bleibt draußen (Datei-Kopf).
static func bester_timed_score(legacy: Dictionary, id: String) -> int:
	var best := int(_num(_dict(legacy.get("best")).get(id)))
	for wert: Variant in _dict(_dict(legacy.get("bestByDiff")).get(id)).values():
		best = maxi(best, int(_num(wert)))
	return maxi(0, best)


## Gesamt-Fortschritt für die Kopfzeile: {"gespielt", "total", "sterne"}.
## total zählt nur öffenbare Spiele (ohne „Bald!“-Kacheln — die kann man
## nie spielen, sie würden das „n/38“ unehrlich machen).
static func gesamt(state: Dictionary, games: Array[Dictionary]) -> Dictionary:
	var gespielt := 0
	var summe := 0
	var total := 0
	for game in games:
		if bool(game.get("coming_soon", false)):
			continue
		total += 1
		var s := sterne(state, game)
		if s > 0:
			gespielt += 1
		summe += s
	return {"gespielt": gespielt, "total": total, "sterne": summe}


## Reihe einer Spiel-Id (unbekannte Ids → FALLBACK_REIHE, nie leer).
static func reihe_von(game_id: String) -> String:
	for key in REIHEN_ORDNUNG:
		if (REIHEN_IDS[key] as Array).has(game_id):
			return key
	return FALLBACK_REIHE


## Ist die Id EXPLIZIT zugeordnet? (Wächter-Frage — der Fallback fängt
## Unbekanntes zur Laufzeit, aber neue Spiele müssen bewusst einsortiert
## werden, sonst wird test_w20_arcade_fortschritt rot.)
static func ist_zugeordnet(game_id: String) -> bool:
	for key in REIHEN_ORDNUNG:
		if (REIHEN_IDS[key] as Array).has(game_id):
			return true
	return false


## Gruppiert die Registry-Spiele in beschriftete Reihen (Reihenfolge =
## REIHEN_ORDNUNG, innerhalb der Reihe bleibt die all_games()-Reihenfolge).
## Leere Reihen entfallen. Ergebnis-Einträge: {"key", "titel_key", "games"}.
static func reihen(games: Array[Dictionary]) -> Array[Dictionary]:
	var eimer := {}
	for key in REIHEN_ORDNUNG:
		eimer[key] = []
	for game in games:
		(eimer[reihe_von(str(game.get("id", "")))] as Array).append(game)
	var out: Array[Dictionary] = []
	for key in REIHEN_ORDNUNG:
		var liste: Array = eimer[key]
		if liste.is_empty():
			continue
		out.append({"key": key, "titel_key": REIHE_TITEL_PREFIX + key, "games": liste})
	return out


## Enthält das beaten-Board irgendeinen true-Modus?
static func _hat_true(beaten: Dictionary) -> bool:
	for wert: Variant in beaten.values():
		if wert == true:
			return true
	return false


static func _num(value: Variant, fallback := 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
