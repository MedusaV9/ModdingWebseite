extends TestCase
## REST-2 — WhatsNextAdvisor: der „Was nun?“-Vorschlag in verschiedenen
## Spielständen (Belohnung wartet > offene Quest > Pflege > Ranch > Level-
## Ziel > Arcade-Default).


func _state(level := 1, stats := {}) -> Dictionary:
	var gooby_stats := {"hunger": 80.0, "energy": 90.0, "hygiene": 85.0, "fun": 70.0}
	for key: String in stats:
		gooby_stats[key] = stats[key]
	return {
		"gooby": {"stats": gooby_stats},
		"progression": {"level": level, "xp": 0},
	}


func _row(
	id: String, progress: int, target: int, claimed := false, complete := false
) -> Dictionary:
	return {
		"def": {"id": id, "kategorie": "care"},
		"progress": progress,
		"target": target,
		"claimed": claimed,
		"complete": complete,
	}


func _ctx(claimable := 0, all_claimed := false) -> Dictionary:
	return {"ranch_level": 15, "claimable": claimable, "all_claimed": all_claimed}


func test_abholbereite_belohnung_gewinnt() -> void:
	var s := WhatsNextAdvisor.suggest(_state(), [_row("a", 3, 3, false, true)], _ctx(1))
	assert_eq(str(s["id"]), "abholen", "Claim-Hinweis zuerst")
	assert_eq(str(s["aktion"]), "quests", "tippen öffnet das Panel")


func test_offene_quest_mit_meistem_fortschritt() -> void:
	var board := [_row("kaum", 0, 4), _row("fast", 3, 4), _row("fertig", 4, 4, true, true)]
	var s := WhatsNextAdvisor.suggest(_state(), board, _ctx())
	assert_eq(str(s["id"]), "quest_fast", "die fast fertige Quest motiviert")
	assert_eq(str(s["text_key"]), "quests.wasnun.quest")
	assert_eq(str(s["args"]["titel_key"]), "quests.q.fast.titel", "Titel-Key wird mitgegeben")


func test_pflege_hinweis_bei_niedrigem_stat() -> void:
	var s := WhatsNextAdvisor.suggest(_state(1, {"hunger": 20.0}), [], _ctx())
	assert_eq(str(s["id"]), "pflege_hunger", "Hunger unter Schwelle")
	var s2 := WhatsNextAdvisor.suggest(_state(1, {"hunger": 30.0, "hygiene": 10.0}), [], _ctx())
	assert_eq(str(s2["id"]), "pflege_hygiene", "der schlechteste Stat gewinnt")


func test_ranch_ab_level_15() -> void:
	var s := WhatsNextAdvisor.suggest(_state(15), [], _ctx())
	assert_eq(str(s["id"]), "ranch", "Ranch-Ausblick ab Freischalt-Level (W13: 15)")


func test_level_ziel_wenn_alles_geschafft() -> void:
	var s := WhatsNextAdvisor.suggest(_state(7), [], _ctx(0, true))
	assert_eq(str(s["id"]), "level", "Fernziel nach fertigem Brett")
	assert_eq(int(s["args"]["level"]), 8, "nächstes Level als Zahl")


func test_arcade_default_bleibt_sanft() -> void:
	var s := WhatsNextAdvisor.suggest(_state(3), [], _ctx())
	assert_eq(str(s["id"]), "arcade", "Default lädt in die Arcade ein")
	assert_eq(str(s["aktion"]), "", "reiner Text, kein Zwang")
