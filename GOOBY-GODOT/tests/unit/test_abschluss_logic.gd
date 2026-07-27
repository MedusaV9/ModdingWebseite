extends TestCase
## FERTIG-1 („Rundes Ende“): AbschlussLogic — der sichtbare Spiel-Abschluss.
## Vier Komponenten (Level/Erfolge/Sticker/Arcade), floor-Prozent (100 % nur
## wenn WIRKLICH alles voll ist), Kappung defekter Werte.

const Leveling := preload("res://scripts/logic/leveling.gd")


func test_leerer_stand_hat_vier_komponenten() -> void:
	var teile := AbschlussLogic.komponenten({})
	assert_eq(teile.size(), 4, "genau vier Sammlungen")
	var ids: Array[String] = []
	for teil in teile:
		ids.append(str(teil["id"]))
		assert_true(int(teil["total"]) >= 1, "Total von '%s' ist > 0" % teil["id"])
		assert_true(int(teil["n"]) >= 0, "n von '%s' nie negativ" % teil["id"])
	assert_eq(ids, ["level", "erfolge", "sticker", "arcade"], "feste Reihenfolge")


func test_leerer_stand_ist_fast_null_prozent() -> void:
	# Level 1/40 ist die einzige Nicht-Null-Quote → deutlich unter 5 %.
	var p := AbschlussLogic.prozent({})
	assert_true(p >= 0 and p < 5, "leerer Stand ~0%% (ist %d)" % p)
	assert_false(AbschlussLogic.komplett({}), "leer ist nicht komplett")


func test_voller_stand_ist_hundert_prozent() -> void:
	var state := _voller_stand()
	assert_eq(AbschlussLogic.prozent(state), 100, "alles voll = 100 %")
	assert_true(AbschlussLogic.komplett(state), "komplett-Flag greift")


func test_fast_voll_bleibt_unter_hundert() -> void:
	# floor-Regel: EIN fehlendes Arcade-Spiel darf nie „100 %“ anzeigen.
	var state := _voller_stand()
	var plays: Dictionary = state["minigames"]["plays"]
	plays.erase(plays.keys()[0])
	assert_true(AbschlussLogic.prozent(state) < 100, "ein Spiel fehlt → <100 %")
	assert_false(AbschlussLogic.komplett(state), "nicht komplett")


func test_kaputte_werte_werden_gekappt() -> void:
	var state := {"progression": {"level": 999}, "minigames": {"plays": "kaputt"}}
	var teile := AbschlussLogic.komponenten(state)
	assert_eq(int(teile[0]["n"]), Leveling.MAX_LEVEL, "Level auf Kappe gekappt")
	assert_eq(int(teile[3]["n"]), 0, "kaputte plays zählen 0")


func _voller_stand() -> Dictionary:
	var erfolge := {}
	for def: Variant in AchievementsCatalog.all():
		if def is Dictionary:
			erfolge[str(def.get("id", ""))] = {"at": 1}
	var sticker := {}
	for def: Variant in StickerCatalog.all():
		if def is Dictionary:
			sticker[str(def.get("id", ""))] = {"at": 1}
	var plays := {}
	for game: Dictionary in MinigameRegistry.all_games():
		plays[str(game.get("id", ""))] = 3
	return {
		"progression": {"level": Leveling.MAX_LEVEL},
		"achievements": {"unlocked": erfolge},
		"stickers": {"unlocked": sticker},
		"minigames": {"plays": plays},
	}
