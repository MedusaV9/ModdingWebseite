extends TestCase
## RW-3 — NPC-Katalog + Content-Pack (content/ranch_quests, Domain
## ranch_npcs): Ensemble-Umfang (>= 12 inkl. aller Pflicht-Rollen),
## Konsistenz jedes Eintrags (Modell, Dialogdatei, Routine, Geschenke,
## Freischaltungen) und die Pack-Merge-Semantik.


## Registry-Attrappe mit fester Item-Liste (Pack-Merge-Simulation).
class FakeRegistry:
	var items: Array = []

	func get_items(_domain: String) -> Array:
		return items


func _abschluss() -> void:
	RNpcKatalog.registry_override = null
	RNpcKatalog.reset_cache()


func test_ensemble_umfang_und_pflicht_rollen() -> void:
	var ids := RNpcKatalog.ids()
	assert_true(ids.size() >= 12, "nur %d NPCs (Minimum 12)" % ids.size())
	for pflicht: String in RNpcKatalog.PFLICHT_IDS:
		assert_true(ids.has(pflicht), "Pflicht-NPC fehlt: %s" % pflicht)
	_abschluss()


func test_alle_npcs_sind_konsistent() -> void:
	for def: Dictionary in RNpcKatalog.alle():
		assert_eq(RNpcKatalog.npc_probleme(def), [], "NPC %s hat Probleme" % def.get("id"))
	_abschluss()


func test_routinen_nutzen_nur_bekannte_orte() -> void:
	var orte: Array = RNpcRoutine.bekannte_orte()
	for def: Dictionary in RNpcKatalog.alle():
		var vorher := -1.0
		for station: Dictionary in def.get("routine", []):
			assert_true(
				orte.has(str(station.get("ort", ""))),
				"%s: Routine-Ort %s unbekannt" % [def.get("id"), station.get("ort")]
			)
			var von := float(station.get("von", -1))
			assert_true(von > vorher, "%s: Routine-Stationen aufsteigend sortiert" % def.get("id"))
			vorher = von
	_abschluss()


func test_jeder_npc_hat_vorlieben_und_freischaltungen() -> void:
	for def: Dictionary in RNpcKatalog.alle():
		var geschenke: Dictionary = (
			def.get("geschenke") if def.get("geschenke") is Dictionary else {}
		)
		assert_false(
			(geschenke.get("liebt", []) as Array).is_empty(),
			"%s: keine Lieblings-Geschenke" % def.get("id")
		)
		var frei: Dictionary = (
			def.get("freischaltungen") if def.get("freischaltungen") is Dictionary else {}
		)
		assert_true(
			RNpcFreundschaft.freischaltungen_bis(def, RNpcFreundschaft.HERZ_MAX).size() >= 3,
			"%s: zu wenige Freischaltungen (%d Stufen belegt)" % [def.get("id"), frei.size()]
		)
		var geschichten := 0
		for stufe in range(1, RNpcFreundschaft.HERZ_MAX + 1):
			for eintrag: Variant in RNpcFreundschaft.freischaltungen_der_stufe(def, stufe):
				if (
					eintrag is Dictionary
					and str((eintrag as Dictionary).get("typ")) == "geschichte"
				):
					geschichten += 1
		assert_true(geschichten >= 2, "%s: braucht 2 persoenliche Geschichten" % def.get("id"))
	_abschluss()


func test_npc_probleme_findet_kaputte_eintraege() -> void:
	assert_false(RNpcKatalog.npc_probleme({}).is_empty(), "NPC ohne id")
	assert_false(
		RNpcKatalog.npc_probleme({"id": "fx", "modell": {"art": "hologramm"}}).is_empty(),
		"unbekannte Modell-Art"
	)
	assert_false(
		(
			RNpcKatalog
			. npc_probleme(
				{
					"id": "fx",
					"modell": {"art": "gooby"},
					"dialog": "res://gibt/es/nicht.json",
					"routine": [{"von": 8, "ort": "stall"}],
				}
			)
			. is_empty()
		),
		"fehlende Dialogdatei + zu kurze Routine"
	)
	_abschluss()


func test_pack_merge_registry_schlaegt_eingebaute_datei() -> void:
	var fake := FakeRegistry.new()
	fake.items = [{"id": "update_npc", "typ": "npc"}]
	RNpcKatalog.registry_override = fake
	RNpcKatalog.reset_cache()
	assert_eq(RNpcKatalog.ids(), ["update_npc"], "Registry-Sicht ersetzt die eingebaute Datei")
	assert_true(RNpcKatalog.npc("rosi").is_empty(), "eingebauter NPC ueberschattet")
	_abschluss()
	assert_false(RNpcKatalog.npc("rosi").is_empty(), "nach Reset wieder eingebautes Pack")


func test_katalog_liefert_kopien() -> void:
	var rosi := RNpcKatalog.npc("rosi")
	rosi["dialog"] = "MANIPULIERT"
	assert_ne(RNpcKatalog.npc("rosi")["dialog"], "MANIPULIERT", "Aufrufer aendern nur Kopien")
	_abschluss()
