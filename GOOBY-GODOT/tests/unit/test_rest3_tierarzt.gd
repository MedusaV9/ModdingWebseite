extends TestCase
## REST-3 Rang 7 — Tierarztpraxis Dr. Dr. Möhrchen: Stadtkarten-Eintrag
## (additiv, validiert), Dialogbaum (Empfang → Untersuchung → Diagnose →
## Behandlung/Rezept/Ruhe → Nachsorge; Zustandsflags routen die Optionen),
## Kosten ueber Health.pay_vet (Web payVet) und die Rezept-Bruecke zum
## vorhandenen GOOBYTHEKE-Flow (flag rezept_tropfen → Gooby-Tropfen kaufbar).

const Health := preload("res://scripts/logic/health.gd")

const DIALOG_DE := "res://scripts/city/data/dialoge/tierarzt.json"
const DIALOG_EN := "res://scripts/city/data/dialoge/en/tierarzt.json"

const NOW_MS := 1768478400000


func _baum(pfad: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	assert_eq(json.parse(raw), OK, "Dialog-JSON parst: %s" % pfad)
	return json.data if json.data is Dictionary else {}


func _vet_state(health_state: String, coins: int) -> Dictionary:
	return {
		"gooby":
		{
			"stats": {"hunger": 50.0, "energy": 50.0, "hygiene": 50.0, "fun": 50.0},
			"health": {"state": health_state, "junkScore": 6.0, "neglectMin": 30.0},
			"weight": 50.0,
		},
		"economy":
		{
			"coins": coins,
			"coinsEarned": 0,
			"coinsSpent": 0,
			"dayCoins": 0,
			"dayCoinsDay": "",
			"endlessCoins": 0,
			"endlessCoinsDay": "",
		},
		"achievements": {"counters": {}},
	}


func test_tierarzt_steht_additiv_in_der_stadtkarte() -> void:
	var karte := CityMap.laden()
	var eintrag := OrtKatalog.eintrag("tierarzt", karte)
	assert_false(eintrag.is_empty(), "tierarzt fehlt in city_map.json")
	assert_eq(str(eintrag.get("typ", "")), "praxis")
	var name_key := str(eintrag.get("name_key", ""))
	assert_ne(I18nService.t(name_key), name_key, "Ortsname uebersetzt (%s)" % name_key)
	var szene := str(eintrag.get("szene", ""))
	assert_true(ResourceLoader.exists(szene), "Ort-Szene existiert (%s)" % szene)
	assert_true(OrtKatalog.betretbare_ids(karte).has("tierarzt"), "betretbar")
	assert_true(OrtKatalog.oeffnung("tierarzt", karte).is_empty(), "immer offen")
	# Der additive Eintrag darf die Karte nicht kaputt machen.
	assert_eq(karte.validieren(), [] as Array[String], "city_map.json bleibt valide")


func test_dialog_routet_nach_gesundheitszustand() -> void:
	var baum := _baum(DIALOG_DE)
	var gesund := OrtDialogRunner.new(baum, {"gesund": true})
	var texte_gesund: Array = gesund.optionen().map(func(o: Dictionary) -> String: return o["text"])
	assert_true(
		texte_gesund.any(func(t: String) -> bool: return t.begins_with("Gooby geht es")),
		"gesund: Lob-Option (got %s)" % [texte_gesund]
	)
	assert_false(
		texte_gesund.any(func(t: String) -> bool: return t.contains("krank")),
		"gesund: keine Krank-Optionen (got %s)" % [texte_gesund]
	)
	var krank := OrtDialogRunner.new(baum, {"krank": true})
	var ziele: Array = krank.optionen().map(func(o: Dictionary) -> String: return o["next"])
	assert_true(ziele.has("untersuchung"), "krank: Untersuchung angeboten (got %s)" % [ziele])
	var schwer := OrtDialogRunner.new(baum, {"schwer_krank": true})
	ziele = schwer.optionen().map(func(o: Dictionary) -> String: return o["next"])
	assert_true(ziele.has("untersuchung"), "schwer_krank: Untersuchung angeboten")


func test_dialog_untersuchung_diagnose_behandlung() -> void:
	var baum := _baum(DIALOG_DE)
	var runner := OrtDialogRunner.new(baum, {"krank": true})
	# Empfang → Untersuchung (Sequenz-Marker) → Auto-Weiter → Diagnose.
	var index := _option_index(runner, "untersuchung")
	assert_true(index >= 0, "Untersuchungs-Option sichtbar")
	assert_true(runner.waehlen(index), "Untersuchung waehlbar")
	assert_eq(runner.aktuell, "untersuchung")
	var effekte: Array = runner.effekte().map(func(e: Dictionary) -> String: return e["name"])
	assert_true(effekte.has("vet_untersuchung"), "Sequenz-Marker (got %s)" % [effekte])
	assert_true(runner.weiter(), "Auto-Weiter zur Diagnose")
	assert_eq(runner.aktuell, "diagnose")
	# Diagnose bietet Behandlung, Rezept und Ruhe an.
	var ziele: Array = runner.optionen().map(func(o: Dictionary) -> String: return o["next"])
	assert_true(ziele.has("behandlung"), "Behandlung (got %s)" % [ziele])
	assert_true(ziele.has("rezept"), "Rezept")
	assert_true(ziele.has("ruhe"), "Ruhe")
	# Behandlung traegt den vet_cure-Marker und muendet in die Nachsorge.
	assert_true(runner.waehlen(_option_index(runner, "behandlung")))
	effekte = runner.effekte().map(func(e: Dictionary) -> String: return e["name"])
	assert_true(effekte.has("vet_cure"), "vet_cure-Marker (got %s)" % [effekte])
	assert_true(runner.weiter(), "weiter zur Nachsorge")
	assert_eq(runner.aktuell, "nachsorge")
	assert_true(runner.ist_ende(), "Nachsorge beendet den Besuch")


func test_dialog_rezept_verbindet_zur_goobytheke() -> void:
	var baum := _baum(DIALOG_DE)
	var runner := OrtDialogRunner.new(baum, {"krank": true})
	runner.waehlen(_option_index(runner, "untersuchung"))
	runner.weiter()
	assert_true(runner.waehlen(_option_index(runner, "rezept")), "Rezept waehlbar ohne Flag")
	var effekte: Array = runner.effekte().map(func(e: Dictionary) -> String: return e["name"])
	assert_true(effekte.has("rezept_tropfen"), "setzt DAS GOOUHBUS/GOOBYTHEKE-Flag")
	assert_true(runner.flags.get("rezept_tropfen", false), "Flag lokal gespiegelt")
	# Mit Flag zeigt die Diagnose nur noch die Schon-da-Variante.
	var runner2 := OrtDialogRunner.new(baum, {"krank": true, "rezept_tropfen": true})
	runner2.waehlen(_option_index(runner2, "untersuchung"))
	runner2.weiter()
	var ziele: Array = runner2.optionen().map(func(o: Dictionary) -> String: return o["next"])
	assert_false(ziele.has("rezept"), "kein Doppel-Rezept (got %s)" % [ziele])
	assert_true(ziele.has("rezept_schon"), "freundlicher Hinweis stattdessen")
	# Und die GOOBYTHEKE loest genau dieses Flag ein (Sortiment + Dialog).
	var sortiment_raw := FileAccess.get_file_as_string(
		"res://scripts/city/data/goobytheke_sortiment.json"
	)
	assert_true(
		sortiment_raw.contains("braucht_rezept") and sortiment_raw.contains("medicine"),
		"GOOBYTHEKE fuehrt Rezept-Medizin"
	)
	var theke := _baum("res://scripts/city/data/dialoge/goobytheke.json")
	var theke_text := JSON.stringify(theke)
	assert_true(theke_text.contains("flag_weg:rezept_tropfen"), "GOOBYTHEKE loest das Rezept ein")
	assert_true(theke_text.contains("item:medicine"), "und gibt die Medizin ins Inventar")


func test_dialog_de_en_paritaet() -> void:
	var de := _baum(DIALOG_DE)
	var en := _baum(DIALOG_EN)
	var de_nodes: Dictionary = de.get("nodes", {})
	var en_nodes: Dictionary = en.get("nodes", {})
	assert_eq(en.get("start"), de.get("start"), "gleicher Startknoten")
	var de_keys := de_nodes.keys()
	de_keys.sort()
	var en_keys := en_nodes.keys()
	en_keys.sort()
	assert_eq(en_keys, de_keys, "gleiche Knoten-Ids")
	for key: String in de_keys:
		var de_node: Dictionary = de_nodes.get(key, {})
		var en_node: Dictionary = en_nodes.get(key, {})
		assert_eq(en_node.get("effekt", []), de_node.get("effekt", []), "%s: gleiche Effekte" % key)
		assert_eq(en_node.get("next", ""), de_node.get("next", ""), "%s: gleicher next" % key)
		assert_eq(en_node.get("ende", false), de_node.get("ende", false), "%s: gleiches ende" % key)
		var de_opt: Array = de_node.get("optionen", [])
		var en_opt: Array = en_node.get("optionen", [])
		assert_eq(en_opt.size(), de_opt.size(), "%s: gleich viele Optionen" % key)
		for i in mini(de_opt.size(), en_opt.size()):
			assert_eq(
				en_opt[i].get("cond", ""), de_opt[i].get("cond", ""), "%s[%d]: cond" % [key, i]
			)
			assert_eq(
				en_opt[i].get("next", ""), de_opt[i].get("next", ""), "%s[%d]: next" % [key, i]
			)


func test_behandlung_kostet_und_heilt() -> void:
	var state := _vet_state("sick", 200)
	var res := Health.pay_vet(state, "cure", NOW_MS)
	assert_true(bool(res["ok"]), "Behandlung klappt")
	assert_eq(int(res["total"]), Health.VET_CURE_PRICE, "Preis 120")
	assert_eq(int(state["economy"]["coins"]), 80, "Muenzen abgebucht")
	assert_eq(str(state["gooby"]["health"]["state"]), "healthy", "Vollheilung")
	assert_almost(float(state["gooby"]["health"]["junkScore"]), 0.0, 1e-6, "alle Druecke weg")
	assert_almost(float(state["gooby"]["stats"]["hunger"]), 60.0, 1e-6, "+10-Stat-Bonus")
	assert_almost(float(state["gooby"]["stats"]["energy"]), 60.0, 1e-6)
	assert_eq(int(state["achievements"]["counters"]["cures"]), 1, "cures-Zaehler")


func test_behandlung_sanft_bei_geldmangel_und_gesundheit() -> void:
	# Zu wenig Muenzen: nichts wird abgebucht, nichts geht kaputt.
	var pleite := _vet_state("sick", 50)
	var res := Health.pay_vet(pleite, "cure", NOW_MS)
	assert_false(bool(res["ok"]))
	assert_eq(str(res["reason"]), "coins")
	assert_eq(int(pleite["economy"]["coins"]), 50, "kein Cent weg")
	assert_eq(str(pleite["gooby"]["health"]["state"]), "sick", "Zustand unveraendert")
	# Gesund: keine Behandlung noetig, kein Geld abgenommen.
	var fit := _vet_state("healthy", 200)
	res = Health.pay_vet(fit, "cure", NOW_MS)
	assert_false(bool(res["ok"]))
	assert_eq(str(res["reason"]), "healthy")
	assert_eq(int(fit["economy"]["coins"]), 200)
	# Unbekannte Leistung: hoeflich abgelehnt.
	res = Health.pay_vet(fit, "goldzahn", NOW_MS)
	assert_eq(str(res["reason"]), "unknown")


func test_checkup_kostet_30_und_resettet_druecke() -> void:
	var state := _vet_state("healthy", 100)
	state["gooby"]["health"] = {
		"state": "healthy", "junkScore": 2.0, "neglectMin": 50.0, "tiredMin": 30.0, "chillMin": 9.0
	}
	var res := Health.pay_vet(state, "checkup", NOW_MS)
	assert_true(bool(res["ok"]))
	assert_eq(int(res["total"]), Health.VET_CHECKUP_PRICE, "Preis 30")
	assert_eq(int(state["economy"]["coins"]), 70)
	var h: Dictionary = state["gooby"]["health"]
	assert_almost(float(h["neglectMin"]), 0.0, 1e-6, "neglect-Reset")
	assert_almost(float(h["tiredMin"]), 0.0, 1e-6, "tired-Reset")
	assert_almost(float(h["chillMin"]), 0.0, 1e-6, "chill-Reset")
	assert_almost(float(h["junkScore"]), 2.0, 1e-6, "junkScore bleibt (kein Freifahrtschein)")


func _option_index(runner: OrtDialogRunner, ziel: String) -> int:
	var sichtbar := runner.optionen()
	for i in sichtbar.size():
		if str(sichtbar[i]["next"]) == ziel:
			return i
	return -1
