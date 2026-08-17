extends TestCase
## FERTIG-1 („Rundes Ende“): AbschlussLogic — der sichtbare Spiel-Abschluss.
## Vier Basis-Komponenten (Level/Erfolge/Basis-Sticker/Arcade), floor-Prozent
## (100 % nur wenn die Offline-Basis voll ist), Online-/DLC-Sticker separat,
## Kappung defekter Werte.

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


func test_offline_basis_ist_ohne_online_und_dlc_sticker_hundert_prozent() -> void:
	var state := _voller_stand()
	var unlocked: Dictionary = state["stickers"]["unlocked"]
	for def: Variant in StickerCatalog.all():
		if def is Dictionary and StickerCatalog.completion_scope(def) != "base":
			unlocked.erase(str(def.get("id", "")))
	assert_eq(AbschlussLogic.prozent(state), 100, "optionale Sticker blockieren Basis-100 % nie")
	assert_true(AbschlussLogic.komplett(state), "Offline-Basis ist komplett")
	var extras := AbschlussLogic.zusatz_komponenten(state)
	assert_eq(extras.size(), 2, "Online und DLC werden separat ausgewiesen")
	assert_eq([extras[0]["id"], extras[1]["id"]], ["sticker_online", "sticker_dlc"])
	assert_eq(int(extras[0]["n"]), 0, "Online darf offen bleiben")
	assert_eq(int(extras[1]["n"]), 0, "DLC darf offen bleiben")
	assert_true(int(extras[0]["total"]) > 0 and int(extras[1]["total"]) > 0)


func test_sticker_scopes_trennen_basis_online_und_dlc_explizit() -> void:
	var katalog := StickerCatalog.all()
	var basis := StickerCatalog.regular_for_scope(katalog, "base")
	var online := StickerCatalog.regular_for_scope(katalog, "online")
	var dlc := StickerCatalog.regular_for_scope(katalog, "dlc")
	assert_eq(basis.size() + online.size() + dlc.size(), StickerCatalog.regular_count(katalog))
	assert_eq(online.size(), 3, "nur wirklich netzpflichtige Sticker")
	assert_eq(dlc.size(), 7, "Ranch-Sticker sind DLC-Fortschritt")
	for def: Dictionary in online:
		assert_true(
			["chess_online", "chess_rematch", "briefe_verschickt"].has(
				str((def.get("cond", {}) as Dictionary).get("key", ""))
			),
			"Online-Scope darf keinen offline erspielbaren Sticker verschlucken"
		)
	for def: Dictionary in dlc:
		assert_eq(str(def.get("page", "")), "ranch", "DLC-Scope ist aktuell Ranch")


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
