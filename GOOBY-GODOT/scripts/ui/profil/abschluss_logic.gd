class_name AbschlussLogic
extends RefCounted
## FERTIG-1 (EVAL „Rundes Ende“): der SPIEL-ABSCHLUSS als sichtbares
## Langzeit-Ziel. Vier klar begrenzte Sammlungen bilden zusammen einen
## Prozentwert — Level (Kappe 40), Erfolge (44), BASIS-Sticker und „jedes
## Arcade-Spiel mindestens einmal gespielt“. 100 % ist vollständig offline
## erreichbar; Online- und DLC-Sticker werden separat ausgewiesen und
## blockieren den Basis-Abschluss nicht.
## Reine Logik (kein Node) — vom Profil-Screen gerendert, im Runner testbar.

const Leveling := preload("res://scripts/logic/leveling.gd")


## Die vier Abschluss-Komponenten als [{id, n, total}] — Reihenfolge fix
## (Anzeige-Reihenfolge im Profil). `n` ist immer auf `total` gekappt.
static func komponenten(state: Dictionary) -> Array[Dictionary]:
	var erfolge_katalog := AchievementsCatalog.all()
	var sticker_katalog := StickerCatalog.all()
	var basis_sticker := StickerCatalog.regular_for_scope(sticker_katalog, "base")
	var spiele := MinigameRegistry.all_games()
	return [
		_komponente("level", _level(state), Leveling.MAX_LEVEL),
		_komponente(
			"erfolge",
			AchievementsEngine.unlocked_count(state, erfolge_katalog),
			erfolge_katalog.size()
		),
		_komponente(
			"sticker", StickerUnlocks.unlocked_count(state, basis_sticker), basis_sticker.size()
		),
		_komponente("arcade", _gespielte_spiele(state, spiele), spiele.size()),
	]


## Optionaler Fortschritt außerhalb des Basis-100-%-Werts. Reihenfolge ist
## Anzeigevertrag: Online zuerst, danach DLC.
static func zusatz_komponenten(state: Dictionary) -> Array[Dictionary]:
	var sticker_katalog := StickerCatalog.all()
	var online := StickerCatalog.regular_for_scope(sticker_katalog, "online")
	var dlc := StickerCatalog.regular_for_scope(sticker_katalog, "dlc")
	return [
		_komponente("sticker_online", StickerUnlocks.unlocked_count(state, online), online.size()),
		_komponente("sticker_dlc", StickerUnlocks.unlocked_count(state, dlc), dlc.size()),
	]


## Gesamt-Abschluss in Prozent (0–100): Mittel der Komponenten-Quoten.
## floor statt round — „100 %“ steht erst da, wenn alle BASIS-Ziele voll sind.
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
