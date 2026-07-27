class_name AbschlussLogic
extends RefCounted
## FERTIG-1 (EVAL „Rundes Ende“): der SPIEL-ABSCHLUSS als sichtbares
## Langzeit-Ziel. Vier klar begrenzte Sammlungen bilden zusammen einen
## Prozentwert — Level (Kappe 40), Erfolge (44), Sticker-Album und
## „jedes Arcade-Spiel mindestens einmal gespielt“. 100 % = das Spiel ist
## KOMPLETT erlebt; der Profil-Screen feiert das mit einer Abschluss-Zeile.
## Reine Logik (kein Node) — vom Profil-Screen gerendert, im Runner testbar.

const Leveling := preload("res://scripts/logic/leveling.gd")


## Die vier Abschluss-Komponenten als [{id, n, total}] — Reihenfolge fix
## (Anzeige-Reihenfolge im Profil). `n` ist immer auf `total` gekappt.
static func komponenten(state: Dictionary) -> Array[Dictionary]:
	var erfolge_katalog := AchievementsCatalog.all()
	var sticker_katalog := StickerCatalog.all()
	var spiele := MinigameRegistry.all_games()
	return [
		_komponente("level", _level(state), Leveling.MAX_LEVEL),
		_komponente(
			"erfolge",
			AchievementsEngine.unlocked_count(state, erfolge_katalog),
			erfolge_katalog.size()
		),
		_komponente(
			"sticker",
			StickerUnlocks.unlocked_count(state, sticker_katalog),
			StickerCatalog.regular_count(sticker_katalog)
		),
		_komponente("arcade", _gespielte_spiele(state, spiele), spiele.size()),
	]


## Gesamt-Abschluss in Prozent (0–100): Mittel der Komponenten-Quoten.
## floor statt round — „100 %“ steht erst da, wenn WIRKLICH alles voll ist.
static func prozent(state: Dictionary) -> int:
	var teile := komponenten(state)
	if teile.is_empty():
		return 0
	var summe := 0.0
	for teil in teile:
		summe += float(teil["n"]) / float(maxi(int(teil["total"]), 1))
	return int(floor(summe / float(teile.size()) * 100.0))


static func komplett(state: Dictionary) -> bool:
	return prozent(state) >= 100


static func _komponente(id: String, n: int, total: int) -> Dictionary:
	var t := maxi(total, 1)
	return {"id": id, "n": clampi(n, 0, t), "total": t}


static func _level(state: Dictionary) -> int:
	var prog: Variant = state.get("progression")
	if not (prog is Dictionary):
		return 1
	return clampi(int((prog as Dictionary).get("level", 1)), 1, Leveling.MAX_LEVEL)


## Wie viele der registrierten Spiele wurden mindestens einmal gespielt?
static func _gespielte_spiele(state: Dictionary, spiele: Array[Dictionary]) -> int:
	var mg: Variant = state.get("minigames")
	if not (mg is Dictionary):
		return 0
	var plays: Variant = (mg as Dictionary).get("plays")
	if not (plays is Dictionary):
		return 0
	var n := 0
	for game in spiele:
		if int((plays as Dictionary).get(str(game.get("id", "")), 0)) > 0:
			n += 1
	return n
