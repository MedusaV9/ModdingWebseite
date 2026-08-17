extends TestCase
## RANCH-2 — Save-Unterschlüssel (RanchPlaySlices) + Minispiel-Fortschritt
## (RanchSpieleProgress): Defaults, Self-Heal kaputter Daten, VERBATIM-Schutz
## fremder (RANCH-1-)Schlüssel und die Sterne/Best/Cleared-Buchhaltung über
## einen GameState-Test-Double.

const Slices := preload("res://scripts/ranch/data/ranch_play_slices.gd")
const Progress := preload("res://scripts/ranch/data/spiele_progress.gd")


class FakeGameState:
	extends RefCounted
	## Duck-Typing-Double für RanchSpieleProgress: get_value (Punkt-Pfade),
	## update (Mutator auf dem State-Dict), notify_slice_changed (Zähler).

	var state: Dictionary = {"ranch": RanchPlaySlices.default_slice()}
	var notified: Array = []

	func get_value(path: String, default_value: Variant = null) -> Variant:
		var cursor: Variant = state
		for teil in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(teil):
				cursor = cursor[teil]
			else:
				return default_value
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(slice_id: String) -> void:
		notified.append(slice_id)


func test_default_slice_hat_alle_unterschluessel() -> void:
	var slice := Slices.default_slice()
	assert_eq(int(slice["v"]), 1)
	assert_eq(slice["tiere"]["pferde"], {})
	assert_almost(float(slice["tiere"]["stall"]["sauberkeit"]), 100.0)
	assert_eq(int(slice["wirtschaft"]["lager"]["heu"]), 4, "Start-Heu")
	assert_eq(int(slice["wirtschaft"]["ausbau"]["boxen"]), 1)
	assert_eq((slice["wirtschaft"]["felder"]["baeume"] as Array).size(), 3)
	assert_eq(slice["spiele"]["parcours"]["stars"], {})
	assert_eq(slice["spiele"]["herde"]["cleared"], {})


func test_normalize_erhaelt_fremde_schluessel_verbatim() -> void:
	var roh := {
		"gekauft": true,
		"hoftiere": [{"id": "huhn1"}],
		"tiere": Slices.default_tiere(),
	}
	var heil := Slices.normalize_slice(roh)
	assert_eq(heil["gekauft"], true, "RANCH-1-Schlüssel überleben")
	assert_eq((heil["hoftiere"] as Array).size(), 1)
	assert_true(heil["wirtschaft"] is Dictionary, "fehlende eigene Schlüssel entstehen")
	assert_true(heil["spiele"] is Dictionary)


func test_neues_pferd_und_farb_fallback() -> void:
	var pferd := Slices.neues_pferd("Luna", "palomino")
	assert_eq(pferd["name"], "Luna")
	assert_eq(pferd["farbe"], "palomino")
	assert_almost(float(pferd["werte"]["hunger"]), 80.0)
	assert_eq(pferd["ausruestung"], {"sattel": null, "decke": null, "halfter": null})
	assert_eq(Slices.neues_pferd("X", "neonpink")["farbe"], "braun", "unbekannte Farbe → braun")


func test_normalize_tiere_heilt_kaputte_pferde() -> void:
	var tiere := (
		Slices
		. normalize_tiere(
			{
				"pferde":
				{
					"p1":
					{
						"name": "Blitz",
						"farbe": "schwarz",
						"werte": {"hunger": 500, "durst": -3},
						"bindung": 250,
						"kaufpreis": 800,
					},
					"kaputt": "kein Dict",
				},
				"stall": {"sauberkeit": 180.0},
				"lastTickAt": -5,
			}
		)
	)
	var p1: Dictionary = tiere["pferde"]["p1"]
	assert_eq(tiere["pferde"].keys(), ["p1"], "Nicht-Dict-Pferde fliegen raus")
	assert_almost(float(p1["werte"]["hunger"]), 100.0, 1e-6, "geklemmt")
	assert_almost(float(p1["werte"]["durst"]), 0.0)
	assert_almost(float(p1["bindung"]), 100.0)
	assert_eq(int(p1["kaufpreis"]), 800, "fremde Zusatz-Schlüssel am Pferd überleben")
	assert_almost(float(tiere["stall"]["sauberkeit"]), 100.0)
	assert_eq(int(tiere["lastTickAt"]), 0)


func test_normalize_wirtschaft_dedupliziert_gear() -> void:
	var w := (
		Slices
		. normalize_wirtschaft(
			{
				"lager": {"heu": -2, "apfel": 3.7},
				"ausbau": {"boxen": 9, "reitplatz": "ja"},
				"gear": {"owned": ["sattel_rot", "sattel_rot", 42, "decke_blau"]},
				"felder": {"baeume": [5]},
			}
		)
	)
	assert_eq(int(w["lager"]["heu"]), 0, "negatives Lager geklemmt")
	assert_eq(int(w["lager"]["apfel"]), 3)
	assert_eq(int(w["ausbau"]["boxen"]), 3, "Boxen auf 1..3 geklemmt")
	assert_eq(w["ausbau"]["reitplatz"], false, "Nicht-Bool wird false")
	assert_eq(w["gear"]["owned"], ["sattel_rot", "decke_blau"], "dedupliziert + nur Strings")
	assert_eq((w["felder"]["baeume"] as Array).size(), 3, "immer 3 Bäume")


func test_normalize_spiele_repariert_struktur() -> void:
	var spiele := Slices.normalize_spiele({"parcours": {"stars": "kaputt"}})
	assert_eq(spiele["parcours"]["stars"], {})
	assert_eq(spiele["herde"]["best"], {})


func test_altes_pferd_wird_zu_level_1_puschelhufer_geheilt() -> void:
	# Save von VOR dem Pferde-DLC: nur Pflege-Felder — additive Heilung.
	var tiere := Slices.normalize_tiere({"pferde": {"p1": {"name": "Oldie", "farbe": "braun"}}})
	var p1: Dictionary = tiere["pferde"]["p1"]
	assert_eq(str(p1["rasse"]), "puschelhufer")
	assert_eq(int(p1["level"]), 1)
	assert_almost(float(p1["xp"]), 0.0)
	assert_eq(str(p1["alter"]), "ausgewachsen")
	for k in RanchRassen.STAT_KEYS:
		assert_eq(int(p1["stats"][k]), 10, "%s: neutraler Basiswert" % k)
		assert_almost(float(p1["frische"][k]), 100.0, 1e-6, "%s: Frische voll" % k)
		assert_eq(int(p1["trainiert"][k]), 0)


func test_dlc_felder_werden_geklemmt_und_level_folgt_xp() -> void:
	var roh := {
		"name": "Hack",
		"rasse": "wolkentraber",
		"stats": {"tempo": 99, "ausdauer": -4},
		"trainiert": {"tempo": 99},
		"frische": {"tempo": 900.0},
		"groesse": 9.0,
		"stimmPitch": 0.1,
		"xp": RanchHorseLevels.xp_summe_bis(5) + 1.0,
		"level": 30,
		"alter": "embryo",
		"charakter": ["mutig", 42, "stur"],
	}
	var p: Dictionary = Slices.normalize_tiere({"pferde": {"p1": roh}})["pferde"]["p1"]
	assert_eq(str(p["rasse"]), "wolkentraber", "Rasse bleibt")
	assert_eq(int(p["stats"]["tempo"]), 20, "Stat auf 1..20 geklemmt")
	assert_eq(int(p["stats"]["ausdauer"]), 1)
	assert_eq(int(p["trainiert"]["tempo"]), 10, "Trainingspunkte auf 0..10 geklemmt")
	assert_almost(float(p["frische"]["tempo"]), 100.0, 1e-6)
	assert_almost(float(p["groesse"]), 1.6, 1e-6, "Groesse geklemmt")
	assert_almost(float(p["stimmPitch"]), 0.6, 1e-6)
	assert_eq(int(p["level"]), 5, "Level wird aus der XP ABGELEITET (Anti-Manipulation)")
	assert_eq(str(p["alter"]), "ausgewachsen", "unbekannte Phase faellt zurueck")
	assert_eq(p["charakter"], ["mutig", "stur"], "nur String-Zuege ueberleben")


func test_neues_pferd_uebernimmt_individuum() -> void:
	var individuum := RanchRassen.neues_individuum("sternschnuppler", 9, RanchRassen.load_balance())
	var pferd := Slices.neues_pferd("Funkel", "braun", individuum)
	assert_eq(str(pferd["rasse"]), "sternschnuppler")
	assert_eq(str(pferd["farbe"]), str(individuum["farbe"]), "Farbe kommt aus den Genen")
	assert_eq(pferd["stats"], individuum["stats"])
	assert_almost(float(pferd["werte"]["hunger"]), 80.0, 1e-6, "Pflege-Startwerte bleiben")
	assert_eq(int(pferd["level"]), 1)


func test_normalize_zucht_heilt_struktur() -> void:
	assert_eq(Slices.normalize_zucht("kaputt"), Slices.default_zucht())
	var z := (
		Slices
		. normalize_zucht(
			{
				"traechtigkeiten":
				{
					"s1":
					{
						"startAt": -5,
						"checkpoints": 9,
						"letzterCheckpoint": 77,
						"seed": 3,
						"vater": {"name": "Papa"}
					},
					"kaputt": 42,
				},
				"ruhezeitBis": {"s2": -100, "s3": 5},
			}
		)
	)
	var t: Dictionary = z["traechtigkeiten"]
	assert_eq(t.keys(), ["s1"], "Nicht-Dict-Eintraege fliegen raus")
	assert_eq(int(t["s1"]["startAt"]), 0, "negativ geklemmt")
	assert_eq(int(t["s1"]["checkpoints"]), 5, "auf 0..5 geklemmt")
	assert_eq(int(t["s1"]["letzterCheckpoint"]), 4)
	assert_eq(str(t["s1"]["vater"]["name"]), "Papa", "Vater-Snapshot bleibt")
	assert_eq(int(z["ruhezeitBis"]["s2"]), 0)
	assert_eq(int(z["ruhezeitBis"]["s3"]), 5)


func test_progress_defaults_ohne_gamestate() -> void:
	assert_eq(Progress.level_stars(null, "parcours", 1), 0)
	assert_eq(Progress.level_best(null, "herde", 1), 0)
	assert_false(Progress.is_cleared(null, "parcours", 1))
	assert_eq(Progress.max_unlocked(null, "parcours"), 1, "ohne Save ist nur Level 1 offen")


func test_record_win_bucht_und_verbessert_nur() -> void:
	var gs := FakeGameState.new()
	var erster := Progress.record_win(gs, "parcours", 1, 2, 120)
	assert_true(erster["first_clear"])
	assert_true(erster["new_best"])
	assert_eq(Progress.level_stars(gs, "parcours", 1), 2)
	assert_eq(Progress.level_best(gs, "parcours", 1), 120)
	assert_true(Progress.is_cleared(gs, "parcours", 1))
	assert_eq(gs.notified, ["ranch"], "Slice-Änderung gemeldet")
	var schlechter := Progress.record_win(gs, "parcours", 1, 1, 80)
	assert_false(schlechter["first_clear"])
	assert_false(schlechter["new_best"])
	assert_eq(Progress.level_stars(gs, "parcours", 1), 2, "Sterne fallen nie")
	assert_eq(Progress.level_best(gs, "parcours", 1), 120, "Best fällt nie")
	var besser := Progress.record_win(gs, "parcours", 1, 3, 200)
	assert_true(besser["new_best"])
	assert_eq(Progress.level_stars(gs, "parcours", 1), 3)
	assert_eq(Progress.level_best(gs, "parcours", 1), 200)


func test_max_unlocked_und_total_stars() -> void:
	var gs := FakeGameState.new()
	assert_eq(Progress.max_unlocked(gs, "herde"), 1)
	Progress.record_win(gs, "herde", 1, 3, 100)
	Progress.record_win(gs, "herde", 2, 1, 90)
	assert_eq(Progress.max_unlocked(gs, "herde"), 3, "1+2 geschafft → 3 offen")
	assert_eq(Progress.total_stars(gs, "herde"), 4)
	assert_eq(Progress.total_stars(gs, "parcours"), 0, "Spiele sind getrennt")
	for id in range(1, 11):
		Progress.record_win(gs, "herde", id, 3, 100)
	assert_eq(Progress.max_unlocked(gs, "herde"), 10, "alles geschafft deckelt bei 10")
