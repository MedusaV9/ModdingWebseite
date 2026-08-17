extends TestCase
## RW-3 — Dialog-Integritaet ALLER Ranch-NPCs (RNpcDialog + vorhandener
## OrtDialogRunner): jeder DE- und EN-Baum ist wohlgeformt (Pflicht-Knoten,
## Ziele existieren, erreichbar, Texte gefuellt), DE/EN sind strukturell
## paritaetisch, und die Kontext-Logik (Startknoten, Flags, Zeit-Slots,
## Geschenk-Einstiege) trifft die richtigen Knoten.


func _baum(pfad: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
	return parsed if parsed is Dictionary else {}


func _en_pfad(pfad: String) -> String:
	return pfad.get_base_dir().path_join("en").path_join(pfad.get_file())


func test_alle_dialogbaeume_de_und_en_sind_gesund() -> void:
	for def: Dictionary in RNpcKatalog.alle():
		var pfad := str(def.get("dialog", ""))
		for variante: String in [pfad, _en_pfad(pfad)]:
			var baum := _baum(variante)
			assert_false(baum.is_empty(), "%s parst nicht" % variante)
			assert_eq(RNpcDialog.baum_probleme(baum), [], "%s: Baum-Probleme" % variante)


func test_de_en_baeume_sind_strukturell_paritaetisch() -> void:
	for def: Dictionary in RNpcKatalog.alle():
		var pfad := str(def.get("dialog", ""))
		var de_nodes: Dictionary = _baum(pfad).get("nodes", {})
		var en_nodes: Dictionary = _baum(_en_pfad(pfad)).get("nodes", {})
		for id: String in de_nodes:
			assert_true(en_nodes.has(id), "%s: EN fehlt Knoten %s" % [def.get("id"), id])
		for id: String in en_nodes:
			assert_true(de_nodes.has(id), "%s: DE fehlt Knoten %s" % [def.get("id"), id])
		for id: String in de_nodes:
			if not en_nodes.has(id):
				continue
			var de_opt: Array = (de_nodes[id] as Dictionary).get("optionen", [])
			var en_opt: Array = (en_nodes[id] as Dictionary).get("optionen", [])
			assert_eq(
				en_opt.size(), de_opt.size(), "%s/%s: Optionszahl weicht ab" % [def.get("id"), id]
			)


func test_geschichten_gates_passen_zu_den_freischaltungen() -> void:
	# Jeder NPC schaltet geschichte_1/_2 ueber Herzen frei; die Knoten
	# muessen im Baum existieren (Katalog <-> Dialog-Konsistenz).
	for def: Dictionary in RNpcKatalog.alle():
		var nodes: Dictionary = _baum(str(def.get("dialog", ""))).get("nodes", {})
		for knoten: String in ["geschichte_1", "geschichte_2"]:
			assert_true(nodes.has(knoten), "%s: %s fehlt im Baum" % [def.get("id"), knoten])


func test_zeit_slots() -> void:
	assert_eq(RNpcDialog.zeit_slot(5.0), "morgen")
	assert_eq(RNpcDialog.zeit_slot(10.99), "morgen")
	assert_eq(RNpcDialog.zeit_slot(11.0), "tag")
	assert_eq(RNpcDialog.zeit_slot(17.0), "abend")
	assert_eq(RNpcDialog.zeit_slot(22.0), "nacht")
	assert_eq(RNpcDialog.zeit_slot(3.0), "nacht")


func test_start_knoten_prioritaet() -> void:
	var baum := _baum(str(RNpcKatalog.npc("rosi").get("dialog", "")))
	assert_eq(
		RNpcDialog.start_knoten(baum, {"stunde": 8.0, "wetter": "sonne", "herzen": 0}),
		"gruss_morgen"
	)
	assert_eq(
		RNpcDialog.start_knoten(baum, {"stunde": 8.0, "wetter": "regen", "herzen": 0}),
		"gruss_regen",
		"Regen schlaegt Uhrzeit"
	)
	assert_eq(
		RNpcDialog.start_knoten(baum, {"stunde": 8.0, "wetter": "sonne", "herzen": 4}),
		"gruss_freund",
		"Freundschaft schlaegt Uhrzeit"
	)
	assert_eq(
		RNpcDialog.start_knoten(baum, {"stunde": 8.0, "wetter": "regen", "herzen": 5}),
		"gruss_regen",
		"Regen schlaegt auch Freundschaft"
	)
	assert_eq(
		RNpcDialog.start_knoten(baum, {"stunde": 23.5, "wetter": "sonne", "herzen": 0}),
		"gruss_abend",
		"nachts greift der Abend-Gruss"
	)
	assert_eq(
		RNpcDialog.start_knoten({"start": "x", "nodes": {}}, {}),
		"x",
		"leerer Baum faellt auf den start-Eintrag zurueck"
	)


func test_kontext_flags() -> void:
	var def := RNpcKatalog.npc("rosi")
	var flags := (
		RNpcDialog
		. kontext_flags(
			def,
			{
				"stunde": 19.0,
				"wetter": "gewitter",
				"herzen": 2,
				"quest_vergabe": true,
				"geschichten_gehoert": [],
			}
		)
	)
	assert_true(flags.get("zeit_abend", false))
	assert_true(flags.get("regen", false), "Gewitter zaehlt als Regen-Gruss")
	assert_true(flags.get("herz1", false))
	assert_true(flags.get("herz2", false))
	assert_false(flags.has("herz3"))
	assert_true(flags.get("smalltalk_b", false), "Herz 2 = mittlerer Smalltalk")
	assert_true(flags.get("quest_vergabe", false))
	assert_false(flags.has("quest_abgabe"))


func test_geschichten_flags_folgen_herzen_und_gehoert() -> void:
	var def := RNpcKatalog.npc("rosi")
	var zu := RNpcDialog.kontext_flags(def, {"herzen": 1, "geschichten_gehoert": []})
	assert_false(zu.has("geschichte_1_frei"), "Herz 1 reicht nicht fuer die Geschichte")
	var auf := RNpcDialog.kontext_flags(def, {"herzen": 5, "geschichten_gehoert": []})
	assert_true(auf.get("geschichte_1_frei", false))
	assert_true(auf.get("geschichte_2_frei", false))
	var gehoert := RNpcDialog.kontext_flags(
		def, {"herzen": 5, "geschichten_gehoert": ["geschichte_1"]}
	)
	assert_false(gehoert.has("geschichte_1_frei"), "gehoerte Geschichten kommen nicht wieder")
	assert_true(gehoert.get("geschichte_2_frei", false))


func test_geschenk_knoten() -> void:
	var baum := _baum(str(RNpcKatalog.npc("rosi").get("dialog", "")))
	assert_eq(RNpcDialog.geschenk_knoten(baum, "liebt"), "geschenk_liebt")
	assert_eq(RNpcDialog.geschenk_knoten(baum, "mag"), "geschenk_mag")
	assert_eq(RNpcDialog.geschenk_knoten(baum, "unbekannt"), "geschenk_normal", "Fallback")


func test_runner_integration_laeuft_einen_dialog() -> void:
	# Der VORHANDENE OrtDialogRunner traegt meinen Baum: Start nach Kontext,
	# Optionen nach Flags gefiltert, next-Navigation funktioniert.
	var def := RNpcKatalog.npc("rosi")
	var runner := RNpcDialog.runner(
		def, {"stunde": 8.0, "wetter": "sonne", "herzen": 0, "quest_vergabe": true}
	)
	assert_eq(runner.aktuell, "gruss_morgen")
	runner.weiter()
	assert_eq(runner.aktuell, "hub", "Gruss fuehrt in die Options-Drehscheibe")
	var texte: Array[String] = []
	for option: Dictionary in runner.optionen():
		texte.append(str(option.get("next", "")))
	assert_true(texte.has("quest_vergabe"), "Quest-Option sichtbar (Flag gesetzt)")
	assert_false(texte.has("quest_abgabe"), "Abgabe-Option unsichtbar (Flag fehlt)")
