extends TestCase
## RW-3 — Quest-Katalog + Content-Pack (content/ranch_quests): Umfang der
## Inhalte (10 Kapitel, >= 25 Nebenquests, Tagespool), Konsistenz jedes
## Eintrags, deterministische Tagesauswahl und die Pack-Merge-Semantik
## (Registry-Sicht schlaegt eingebaute Datei).


## Registry-Attrappe mit fester Item-Liste (Pack-Merge-Simulation).
class FakeRegistry:
	var items: Array = []

	func get_items(_domain: String) -> Array:
		return items


func _abschluss() -> void:
	RQuestKatalog.registry_override = null
	RQuestKatalog.reset_cache()


func test_hauptreihe_hat_10_kapitel_mit_titelkarten() -> void:
	var reihe := RQuestKatalog.hauptreihe()
	assert_eq(reihe.size(), 10, "Haupt-Questreihe hat 10 Kapitel")
	for i: int in reihe.size():
		var def: Dictionary = reihe[i]
		assert_eq(int(def.get("kapitel", 0)), i + 1, "Kapitel sortiert 1..10")
		var karte := str(def.get("titelkarte", ""))
		assert_true(
			FileAccess.file_exists(karte), "%s: Titelkarte fehlt (%s)" % [def.get("id"), karte]
		)
	_abschluss()


func test_mindestens_25_nebenquests_und_tagespool() -> void:
	assert_true(
		RQuestKatalog.nebenquests().size() >= 25,
		"nur %d Nebenquests" % RQuestKatalog.nebenquests().size()
	)
	assert_true(
		RQuestKatalog.tagespool().size() > RQuestKatalog.TAGES_SLOTS,
		"Tagespool groesser als die Slot-Zahl (Rotation moeglich)"
	)
	_abschluss()


func test_alle_quests_sind_konsistent() -> void:
	var npc_ids := RNpcKatalog.ids()
	var quest_ids := {}
	for def: Dictionary in RQuestKatalog.alle():
		quest_ids[str(def.get("id", ""))] = true
	for def: Dictionary in RQuestKatalog.alle():
		assert_eq(RQuestKatalog.quest_probleme(def), [], "Quest %s hat Probleme" % def.get("id"))
		assert_true(
			npc_ids.has(str(def.get("geber", ""))),
			"%s: Geber %s ist kein Katalog-NPC" % [def.get("id"), def.get("geber")]
		)
		var vor: Dictionary = (
			def.get("voraussetzungen") if def.get("voraussetzungen") is Dictionary else {}
		)
		for noetig: Variant in vor.get("quests", []):
			assert_true(
				quest_ids.has(str(noetig)),
				"%s: Voraussetzung %s unbekannt" % [def.get("id"), noetig]
			)
		for npc_id: Variant in vor.get("herzen") if vor.get("herzen") is Dictionary else {}:
			assert_true(
				npc_ids.has(str(npc_id)), "%s: Herz-Gate-NPC %s unbekannt" % [def.get("id"), npc_id]
			)
		for ziel: Dictionary in def.get("ziele", []):
			if str(ziel.get("typ", "")) == "sprich_mit":
				assert_true(
					npc_ids.has(str(ziel.get("npc", ""))),
					"%s: sprich_mit-NPC unbekannt" % def.get("id")
				)
	_abschluss()


func test_warte_quests_existieren_und_sind_nie_blockierend() -> void:
	var mit_warten := 0
	for def: Dictionary in RQuestKatalog.alle():
		for ziel: Dictionary in def.get("ziele", []):
			if str(ziel.get("typ", "")) == "warte_bis":
				mit_warten += 1
				assert_true(int(ziel.get("dauerMin", 0)) > 0, "%s: Wartezeit > 0" % def.get("id"))
	assert_true(mit_warten >= 4, "mehrere Warte-Quests (Fohlen/Sattel/Saat/Post): %d" % mit_warten)
	_abschluss()


func test_tagesaufgaben_deterministisch_pro_datum() -> void:
	var a := RQuestKatalog.tagesaufgaben("2026-07-26")
	var b := RQuestKatalog.tagesaufgaben("2026-07-26")
	assert_eq(a.size(), RQuestKatalog.TAGES_SLOTS)
	for i: int in a.size():
		assert_eq(a[i]["id"], b[i]["id"], "gleiches Datum = gleiche Auswahl")
	var ids_a: Array = []
	for def: Dictionary in a:
		assert_false(ids_a.has(def["id"]), "keine Duplikate am selben Tag")
		ids_a.append(def["id"])
	_abschluss()


func test_pack_merge_registry_schlaegt_eingebaute_datei() -> void:
	var fake := FakeRegistry.new()
	fake.items = [
		{
			"id": "update_quest",
			"typ": "neben",
			"geber": "rosi",
			"ziele": [{"typ": "gehe_zu", "ort": "stall"}],
		}
	]
	RQuestKatalog.registry_override = fake
	RQuestKatalog.reset_cache()
	assert_eq(RQuestKatalog.alle().size(), 1, "Registry-Sicht ersetzt die eingebaute Datei")
	assert_eq(RQuestKatalog.quest("update_quest")["geber"], "rosi")
	assert_true(RQuestKatalog.quest("haupt_01").is_empty(), "eingebaute Quest ueberschattet")
	_abschluss()
	assert_false(RQuestKatalog.quest("haupt_01").is_empty(), "nach Reset wieder eingebautes Pack")


func test_leere_registry_faellt_auf_pack_datei_zurueck() -> void:
	var fake := FakeRegistry.new()
	fake.items = []
	RQuestKatalog.registry_override = fake
	RQuestKatalog.reset_cache()
	assert_true(RQuestKatalog.alle().size() >= 40, "leere Registry-Domain = Fallback aufs Pack")
	_abschluss()


func test_katalog_liefert_kopien() -> void:
	var quest := RQuestKatalog.quest("haupt_01")
	quest["geber"] = "MANIPULIERT"
	assert_eq(RQuestKatalog.quest("haupt_01")["geber"], "rosi", "Aufrufer aendern nur Kopien")
	_abschluss()
