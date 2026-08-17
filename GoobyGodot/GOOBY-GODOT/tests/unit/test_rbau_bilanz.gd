extends TestCase
## RW-4 — Wirtschafts-Bilanz-Test: die Gold-Senken (Bauten, Deko, Futter,
## Pferde, Zonen) bleiben in einem fairen Verhältnis zu den Gold-Quellen
## (Minispiele, Hof-Momente, Turniere, Ernte-Verkauf). Die Grenzen stehen
## als DATEN in bau_balance.json (wirtschaft_modell) — dieser Test hält
## die Bilanz ehrlich: reißt eine Preisänderung eine Grind-Grenze, wird
## es hier rot statt im Spielgefühl.


func _bal() -> Dictionary:
	return RanchBauKatalog.load_balance()


func _dorf() -> Dictionary:
	return DorfKatalog.load_balance()


func _grenze(bal: Dictionary, key: String) -> float:
	var modell := RanchBauKatalog.wirtschaft_modell(bal)
	var grenzen: Dictionary = (
		modell.get("grind_grenzen_stunden")
		if modell.get("grind_grenzen_stunden") is Dictionary
		else {}
	)
	return float(grenzen.get(key, 0.0))


func test_einnahmen_modell_ist_plausibel() -> void:
	var bal := _bal()
	var pro_stunde := RanchBauKatalog.einnahmen_pro_stunde(bal)
	assert_true(pro_stunde >= 200, "Einnahmen-Schätzung fehlt/zu klein: %d" % pro_stunde)
	assert_true(pro_stunde <= 1000, "Einnahmen-Schätzung unplausibel groß")


func test_deko_boden_zaun_sind_impulskaeufe() -> void:
	var bal := _bal()
	var stunde := float(RanchBauKatalog.einnahmen_pro_stunde(bal))
	var defs := RanchBauKatalog.defs(bal)
	var limits := {
		"deko": _grenze(bal, "deko") * stunde,
		"boden": _grenze(bal, "boden") * stunde,
		"zaun": _grenze(bal, "zaun_kante") * stunde,
	}
	for id: String in defs:
		var def: Dictionary = defs[id]
		var kategorie := str(def["kategorie"])
		if not limits.has(kategorie):
			continue
		assert_true(
			float(int(def["kosten"])) <= float(limits[kategorie]),
			(
				"%s (%d G) sprengt die %s-Grenze (%.0f G)"
				% [id, def["kosten"], kategorie, limits[kategorie]]
			)
		)


func test_anlagen_stufen_bleiben_erreichbar() -> void:
	var bal := _bal()
	var stunde := float(RanchBauKatalog.einnahmen_pro_stunde(bal))
	var start_limit := _grenze(bal, "anlage_stufe1") * stunde
	var stufen_limit := _grenze(bal, "anlage_stufe_max") * stunde
	for id: String in RanchBauKatalog.ids(bal, "anlage"):
		var stufen := RanchBauKatalog.stufen_kosten(bal, id)
		assert_true(stufen.size() >= 1, "%s hat keine Stufen" % id)
		assert_true(
			float(int(stufen[0])) <= start_limit,
			(
				"%s Stufe 1 (%s G) über der Einstiegs-Grenze (%.0f G)"
				% [id, str(stufen[0]), start_limit]
			)
		)
		for i in stufen.size():
			assert_true(
				float(int(stufen[i])) <= stufen_limit,
				(
					"%s Stufe %d (%s G) über der Stufen-Grenze (%.0f G)"
					% [id, i + 1, str(stufen[i]), stufen_limit]
				)
			)
			if i > 0:
				assert_true(
					int(stufen[i]) >= int(stufen[i - 1]),
					"%s: Stufenpreise sollen monoton steigen" % id
				)


func test_zonen_freischaltung_bleibt_erreichbar() -> void:
	var bal := _bal()
	var limit := _grenze(bal, "zone") * float(RanchBauKatalog.einnahmen_pro_stunde(bal))
	var zonen := RanchBauKatalog.zonen(bal)
	assert_true(zonen.has("start") and zonen.has("nord") and zonen.has("ost"))
	assert_eq(int(zonen["start"]["kosten"]), 0, "Start-Zone ist gratis")
	for id: String in zonen:
		assert_true(
			float(int(zonen[id]["kosten"])) <= limit,
			"Zone %s (%d G) über der Grenze (%.0f G)" % [id, zonen[id]["kosten"], limit]
		)


func test_pferdepreise_bleiben_erreichbar() -> void:
	var bal := _bal()
	var dorf := _dorf()
	var stunde := float(RanchBauKatalog.einnahmen_pro_stunde(bal))
	var guenstig_limit := _grenze(bal, "pferd_guenstig") * stunde
	var teuer_limit := _grenze(bal, "pferd_teuer") * stunde
	var pool := DorfKatalog.pferde_pool(dorf)
	assert_true(pool.size() >= 6, "Pool zu klein für eine spannende Rotation")
	var guenstigstes := 999999
	for eintrag: Dictionary in pool:
		var preis := int(eintrag.get("preis", 0))
		assert_true(preis > 0, "%s hat keinen Preis" % str(eintrag.get("id")))
		guenstigstes = mini(guenstigstes, preis)
		assert_true(
			float(preis) <= teuer_limit,
			(
				"%s (%d G) über der Pferd-Grenze (%.0f G)"
				% [str(eintrag.get("id")), preis, teuer_limit]
			)
		)
	assert_true(
		float(guenstigstes) <= guenstig_limit,
		(
			"Einsteiger-Pferd (%d G) über der Einstiegs-Grenze (%.0f G)"
			% [guenstigstes, guenstig_limit]
		)
	)


func test_kaufen_verkaufen_macht_nie_gewinn() -> void:
	var dorf := _dorf()
	# Futterhof: Ankaufspreis liegt UNTER jedem Heu-Einkaufspreis pro Ballen.
	var ankauf := DorfKatalog.futter_ankauf(dorf)
	var heu_ankauf := int(ankauf.get("heu", 0))
	assert_true(heu_ankauf > 0, "Heu-Ankauf fehlt")
	for ware: Dictionary in DorfKatalog.futter_waren(dorf):
		if not str(ware.get("id", "")).begins_with("heu"):
			continue
		var pro_ballen := float(ware.get("preis", 0)) / maxf(1.0, float(ware.get("menge", 1)))
		assert_true(
			float(heu_ankauf) < pro_ballen,
			"Heu-Ankauf (%d) muss unter dem Kaufpreis (%.1f) liegen" % [heu_ankauf, pro_ballen]
		)
	# Pferdehandel: Wiederverkauf ist ein ANTEIL < 1 des Kaufpreises.
	var anteil := DorfKatalog.verkauf_anteil(dorf)
	assert_true(anteil > 0.0 and anteil < 1.0, "verkauf_anteil muss in (0,1) liegen")
	# Abriss: Teilerstattung < 100 % (Bauen und Abreißen dupliziert kein Gold).
	var erstattung := RanchBauKatalog.abriss_erstattung(_bal())
	assert_true(erstattung > 0.0 and erstattung < 1.0, "Abriss-Erstattung in (0,1)")


func test_heulager_kapazitaet_traegt_das_heu_bund() -> void:
	# Der Basis-Vorrat (4 Ballen Start) + Heu-Bund (5) muss unter die
	# Basis-Kapazität passen — sonst schlägt der erste Bund-Kauf fehl.
	var bal := _bal()
	var basis := RanchBauEffekte.heu_kapazitaet(RanchBauState.default_bau(), bal)
	var start_heu := int(RanchPlaySlices.default_wirtschaft()["lager"]["heu"])
	var bund := 0
	for ware: Dictionary in DorfKatalog.futter_waren(_dorf()):
		if str(ware.get("id", "")) == "heu_bund":
			bund = int(ware.get("menge", 0))
	assert_true(bund > 0, "heu_bund fehlt im Futterhof")
	assert_true(
		start_heu + bund <= basis,
		(
			"Start-Heu (%d) + Bund (%d) passt nicht in die Basis-Kapazität (%d)"
			% [start_heu, bund, basis]
		)
	)
