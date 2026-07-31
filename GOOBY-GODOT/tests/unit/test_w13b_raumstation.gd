extends TestCase
## W13B/RAUMSTATION (Doc G §7 + Doc E §3.3) — Raumstation GOOB-1 +
## Urlaubs-Nutzen-Paket:
## - space-Ankunft: Ort nur mit `vacation.visited.space` freigeschaltet,
##   Szenen-Smoke (Terminals/Automat/Foto-Spot/Erde stehen im Baum).
## - Terminals starten die RICHTIGEN Spiele über die Arcade-Start-API und
##   biegen die &"arcade"-Rückroute auf die Station um.
## - Low-G-Hop: höher UND langsamer (reine Tween-Parameter).
## - Weltengooby erst bei 9/9 (8/9 = nein), Feier genau EINMAL.
## - Erholungs-Boost: Drain ×0,8 für 48 h, danach normal (zeitinjiziert).
## - GOOBY-FREE: Gate (nur mit gebuchtem Abflug), Kauf atomar, gfree_*-
##   Katalogeinträge exklusiv (preis 0) mit existierenden Assets.
## - Strings/Dialog: DE↔EN-Parität der neuen raumstation-Texte.

const Vacation := preload("res://scripts/logic/vacation.gd")

const RAUM_SZENE := "res://scenes/city/orte/raumstation.tscn"
const FLUG_SZENE := "res://scenes/city/orte/flughafen.tscn"
const EXTRA_JSON := "res://content/furniture/data/furniture_extra.json"
const DIALOG_DE := "res://scripts/city/data/dialoge/raumstation.json"
const DIALOG_EN := "res://scripts/city/data/dialoge/en/raumstation.json"
const STRINGS_DE := "res://strings/de/raumstation.json"
const STRINGS_EN := "res://strings/en/raumstation.json"

## 2026-07-25 12:00:00 UTC — fixer Testzeitpunkt (Zeit IMMER injiziert).
const JETZT := 1784980800000


## GameState-Double: dotted get/set + update(mutator) + state() wie
## /root/GameState (state() braucht der UrlaubsBonus/GOOBY-FREE-Pfad).
class FakeGameState:
	extends RefCounted
	var daten: Dictionary = {}
	var slices_notified: Array[String] = []

	func _init(start: Dictionary = {}) -> void:
		daten = start

	func state() -> Dictionary:
		return daten

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = daten
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = daten
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(daten)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## Router-Attrappe: merkt sich register_route + goto (Terminal-Tests).
class FakeRouter:
	extends RefCounted
	var routen: Dictionary = {}
	var ziele: Array = []

	func register_route(target: StringName, szene: String) -> void:
		routen[target] = szene

	func goto(target: StringName, params: Dictionary = {}) -> void:
		ziele.append({"target": target, "params": params})


func _basis_state() -> Dictionary:
	return {
		"vacation": Vacation.default_slice(),
		"buffs": {"aktiv": []},
		"economy": {"coins": 500},
		"inventory": {"items": {}, "food": {}},
		"home": {"storage": [], "storageCapacity": 100},
		"city": {},
	}


func _alle_ziele(ohne: String = "") -> Dictionary:
	var visited: Dictionary = {}
	for ziel: String in Vacation.CATALOG:
		if ziel != ohne:
			visited[ziel] = true
	return visited


## ---------------------------------------------------- Ankunft + Smoke


func test_freischaltung_nur_mit_space_besuch() -> void:
	assert_false(OrtRaumstation.freigeschaltet({}), "frischer Save: kein Weg zur GOOB-1")
	var acht := {"vacation": {"visited": _alle_ziele("space")}}
	assert_false(OrtRaumstation.freigeschaltet(acht), "8 Ziele ohne space reichen nicht")
	var mit_space := {"vacation": {"visited": {"space": true}}}
	assert_true(OrtRaumstation.freigeschaltet(mit_space), "space besucht → frei")


func test_route_wird_idempotent_angemeldet() -> void:
	var router := FakeRouter.new()
	OrtRaumstation.registriere_route(router)
	OrtRaumstation.registriere_route(router)
	assert_eq(str(router.routen.get(OrtRaumstation.ROUTE, "")), OrtRaumstation.SZENE)
	OrtRaumstation.registriere_route(null)  # darf nicht krachen


func test_szenen_smoke_und_terminals() -> void:
	assert_true(ResourceLoader.exists(RAUM_SZENE), "raumstation.tscn fehlt")
	var szene: PackedScene = load(RAUM_SZENE)
	var ort: OrtRaumstation = szene.instantiate()
	var gs := FakeGameState.new(_basis_state())
	gs.set_value("vacation.visited", {"space": true})
	ort.game_state_override = gs
	ort.router_override = FakeRouter.new()
	tree.root.add_child(ort)
	await wait_frames(3)
	assert_eq(ort.ort_id, "raumstation", "ort_id aus der Szene")
	assert_true(ort.terminals.has(OrtRaumstation.SPIEL_ROCKET), "Rocket-Terminal steht")
	assert_true(ort.terminals.has(OrtRaumstation.SPIEL_STAR), "Star-Terminal steht")
	assert_ne(ort.find_child("AstroAutomat", true, false), null, "Astro-Snack-Automat steht")
	assert_ne(ort.find_child("FotoSpot", true, false), null, "Sternenfoto-Spot markiert")
	assert_ne(ort.find_child("Erde", true, false), null, "Erd-Blick vorm Fenster")
	# Terminal-Interaktion: startet das RICHTIGE Spiel über die Arcade-API
	# und biegt die &"arcade"-Route zurück zur Station.
	var router: FakeRouter = ort.router_override
	ort.starte_spiel(OrtRaumstation.SPIEL_ROCKET)
	assert_eq(router.ziele.size(), 1, "genau ein goto")
	assert_eq(router.ziele[0]["target"], ArcadeScreen.ROUTE_PREGAME, "Start via Pregame")
	assert_eq(
		str(router.ziele[0]["params"].get("game_id", "")),
		OrtRaumstation.SPIEL_ROCKET,
		"Rocket-Terminal startet rocketRescue"
	)
	assert_eq(
		str(router.routen.get(ArcadeScreen.ROUTE_ARCADE, "")),
		OrtRaumstation.SZENE,
		'&"arcade" zeigt für den Rückweg auf die Station'
	)
	ort.starte_spiel(OrtRaumstation.SPIEL_STAR)
	assert_eq(
		str(router.ziele[1]["params"].get("game_id", "")),
		OrtRaumstation.SPIEL_STAR,
		"Star-Terminal startet starHopper"
	)
	ort.queue_free()
	await wait_frames(1)
	# Die echten Arcade-Routen sind nach dem Stations-_ready wieder aktiv
	# (register_routes ersetzt idempotent) — kein Aufräum-Rest im Router.


func test_beide_spiele_sind_registriert() -> void:
	for id in [OrtRaumstation.SPIEL_ROCKET, OrtRaumstation.SPIEL_STAR]:
		assert_false(MinigameRegistry.get_game(id).is_empty(), "%s fehlt in der Registry" % id)


## -------------------------------------------------------------- Low-G


func test_low_g_hop_hoeher_und_langsamer() -> void:
	var hop := OrtRaumstation.hop_parameter(0.22, 0.9)
	assert_almost(float(hop["hoehe"]), 0.22 * OrtRaumstation.LOW_G_HOEHE_MULT, 1e-9)
	assert_almost(float(hop["dauer"]), 0.9 * OrtRaumstation.LOW_G_DAUER_MULT, 1e-9)
	assert_true(float(hop["hoehe"]) > 0.22, "Low-G hüpft HÖHER")
	assert_true(float(hop["dauer"]) > 0.9, "Low-G hüpft LANGSAMER")


## -------------------------------------------------------- Weltengooby


func test_weltengooby_erst_bei_9_von_9() -> void:
	assert_false(Vacation.alle_ziele_besucht({"visited": _alle_ziele("space")}), "8/9 = nein")
	assert_true(Vacation.alle_ziele_besucht({"visited": _alle_ziele()}), "9/9 = ja")
	assert_false(Vacation.weltengooby({}), "ohne Latch kein Titel")
	assert_true(Vacation.weltengooby({"weltengoobyAt": JETZT}), "Latch = Titel")


func test_abholung_latcht_weltengooby_genau_einmal() -> void:
	# 8 besuchte Ziele + Rückkehr vom 9. (space) → Latch feuert.
	var v := Vacation.default_slice()
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = "space"
	v["bookedAt"] = JETZT - 3 * Vacation.MS_PER_DAY
	v["returnAt"] = JETZT - 1000
	v["pickupBy"] = JETZT + Vacation.PICKUP_WINDOW_MS
	v["visited"] = _alle_ziele("space")
	var res := ReiseLogic.abholen(v, JETZT)
	assert_true(bool(res["ok"]), "Abholung klappt")
	assert_true(bool(res["weltengooby_neu"]), "9/9 erreicht → Titel neu")
	assert_eq(int(res["vacation"]["weltengoobyAt"]), JETZT, "Latch-Zeitpunkt injiziert")
	# Zweite Reise danach: Titel bleibt, feuert aber nicht noch einmal.
	var v2: Dictionary = res["vacation"]
	v2["phase"] = Vacation.PHASE_AWAY
	v2["destId"] = "beach"
	v2["bookedAt"] = JETZT + 1000
	v2["returnAt"] = JETZT + 2000
	v2["pickupBy"] = JETZT + 2000 + Vacation.PICKUP_WINDOW_MS
	var res2 := ReiseLogic.abholen(v2, JETZT + 3000)
	assert_true(bool(res2["ok"]))
	assert_false(bool(res2["weltengooby_neu"]), "Latch feuert nur einmal")
	assert_eq(int(res2["vacation"]["weltengoobyAt"]), JETZT, "Latch bleibt stehen")


func test_abholung_mit_8_von_9_latcht_nicht() -> void:
	var v := Vacation.default_slice()
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = "beach"
	v["bookedAt"] = JETZT - 2 * Vacation.MS_PER_DAY
	v["returnAt"] = JETZT - 1000
	v["pickupBy"] = JETZT + Vacation.PICKUP_WINDOW_MS
	v["visited"] = {"beach": true, "harbor": true, "meadowTrip": true, "spookGarden": true}
	var res := ReiseLogic.abholen(v, JETZT)
	assert_true(bool(res["ok"]))
	assert_false(bool(res["weltengooby_neu"]), "unter 9/9 kein Titel")
	assert_eq(int(res["vacation"]["weltengoobyAt"]), 0)


## ---------------------------------------------------- Erholungs-Boost


func test_boost_mathe_drain_x08_fuer_48h() -> void:
	var v := Vacation.default_slice()
	assert_almost(Vacation.energie_drain_faktor(v, JETZT), 1.0, 1e-9, "ohne Urlaub normal")
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = "beach"
	v["bookedAt"] = JETZT - 2 * Vacation.MS_PER_DAY
	v["returnAt"] = JETZT - 1000
	v["pickupBy"] = JETZT + Vacation.PICKUP_WINDOW_MS
	var nach: Dictionary = ReiseLogic.abholen(v, JETZT)["vacation"]
	assert_eq(int(nach["erholtBis"]), JETZT + Vacation.ERHOLUNGS_BOOST_MS, "48 h gestempelt")
	assert_almost(Vacation.energie_drain_faktor(nach, JETZT + 1), 0.8, 1e-9, "im Boost ×0,8")
	assert_almost(
		Vacation.energie_drain_faktor(nach, JETZT + Vacation.ERHOLUNGS_BOOST_MS - 1),
		0.8,
		1e-9,
		"kurz vor Ablauf noch ×0,8"
	)
	assert_almost(
		Vacation.energie_drain_faktor(nach, JETZT + Vacation.ERHOLUNGS_BOOST_MS),
		1.0,
		1e-9,
		"nach 48 h wieder normal"
	)
	# Der Slice überlebt die Normalisierung (sonst würfe die nächste
	# Abholung den Latch weg).
	var normalisiert := Vacation.slice_of({"vacation": nach})
	assert_eq(int(normalisiert["erholtBis"]), JETZT + Vacation.ERHOLUNGS_BOOST_MS)


func test_urlaubs_bonus_sync_buff_und_feier_einmalig() -> void:
	var start := _basis_state()
	start["vacation"]["erholtBis"] = JETZT + Vacation.ERHOLUNGS_BOOST_MS
	start["vacation"]["weltengoobyAt"] = JETZT
	start["vacation"]["visited"] = _alle_ziele()
	var gs := FakeGameState.new(start)
	var res := UrlaubsBonus.sync(gs, JETZT + 1000)
	assert_true(bool(res["buff_gewaehrt"]), "Boost aktiv → Buff gewährt")
	assert_true(bool(res["weltengooby_gefeiert"]), "Titel neu → Feier")
	var aktiv: Array = gs.daten["buffs"]["aktiv"]
	assert_eq(aktiv.size(), 1, "genau ein Buff")
	assert_eq(str(aktiv[0]["id"]), UrlaubsBonus.BUFF_ID)
	assert_eq(str(aktiv[0]["stat"]), UrlaubsBonus.BUFF_STAT)
	assert_true(
		absi(int(aktiv[0]["until_ms"]) - int(start["vacation"]["erholtBis"])) <= 1000,
		"Buff endet (rundungsnah) mit erholtBis"
	)
	# Idempotent: zweiter sync grantet nicht neu und feiert nicht nochmal.
	var res2 := UrlaubsBonus.sync(gs, JETZT + 2000)
	assert_false(bool(res2["buff_gewaehrt"]), "kein Re-Grant")
	assert_false(bool(res2["weltengooby_gefeiert"]), "Feier nur einmal")
	assert_true(bool(gs.daten["vacation"]["weltengoobyGefeiert"]), "Feier-Latch sitzt")
	# Nach Ablauf des Boosts: kein Buff mehr nötig.
	var res3 := UrlaubsBonus.sync(gs, JETZT + Vacation.ERHOLUNGS_BOOST_MS + 1)
	assert_false(bool(res3["buff_gewaehrt"]), "abgelaufen → kein Buff")


## ------------------------------------------------------- GOOBY-FREE


func _mit_buchung(state: Dictionary, ziel := "space", status := TaxiLogic.STATE_GERUFEN) -> void:
	state["city"]["taxi"] = {
		"state": status,
		"gerufenAt": JETZT,
		"ankunftAt": JETZT + 300000,
		"zielId": ziel,
	}


func test_gooby_free_gate_nur_mit_gebuchtem_abflug() -> void:
	var state := _basis_state()
	assert_false(OrtFlughafen.gooby_free_offen(state), "ohne Buchung zu")
	_mit_buchung(state)
	assert_true(OrtFlughafen.gooby_free_offen(state), "Taxi GERUFEN + Urlaubsziel → offen")
	_mit_buchung(state, "beach", TaxiLogic.STATE_WARTET)
	assert_true(OrtFlughafen.gooby_free_offen(state), "Taxi WARTET zählt auch")
	_mit_buchung(state, "flughafen")
	assert_false(OrtFlughafen.gooby_free_offen(state), "Stadt-Taxi ist KEIN Abflug")
	_mit_buchung(state, "space", TaxiLogic.STATE_FAHRT)
	assert_false(OrtFlughafen.gooby_free_offen(state), "in der Fahrt ist der Stand zu")
	assert_false(OrtFlughafen.gooby_free_offen({}), "leerer State kracht nicht")


func test_gooby_free_kauf_moebel_und_snack() -> void:
	var state := _basis_state()
	_mit_buchung(state)
	var gs := FakeGameState.new(state)
	var moebel: Dictionary = OrtFlughafen.GOOBY_FREE_SORTIMENT[0]
	assert_eq(str(moebel["typ"]), "moebel", "erster Eintrag ist Deko")
	assert_eq(OrtFlughafen.kaufe_gfree(gs, moebel), OrtFlughafen.KAUF_OK, "Möbel-Kauf ok")
	assert_eq(int(gs.get_value("economy.coins")), 500 - int(moebel["preis"]), "Münzen abgezogen")
	var lager: Array = gs.get_value("home.storage")
	assert_eq(lager.size(), 1, "Deko liegt im Lager")
	assert_eq(str(lager[0]["item"]), str(moebel["id"]))
	assert_true(gs.slices_notified.has("home"), "home-Slice gemeldet")
	var snack := {"id": "cookie", "typ": "snack", "preis": 13}
	assert_eq(OrtFlughafen.kaufe_gfree(gs, snack), OrtFlughafen.KAUF_OK, "Snack-Kauf ok")
	assert_eq(int(gs.get_value("inventory.food.cookie")), 1, "Snack im Food-Inventar")


func test_gooby_free_kauf_ohne_buchung_und_ohne_geld() -> void:
	var zu := FakeGameState.new(_basis_state())
	var ware: Dictionary = OrtFlughafen.GOOBY_FREE_SORTIMENT[0]
	assert_eq(OrtFlughafen.kaufe_gfree(zu, ware), OrtFlughafen.KAUF_ZU, "ohne Buchung kein Kauf")
	assert_eq(int(zu.get_value("economy.coins")), 500, "nichts abgebucht")
	var pleite_state := _basis_state()
	pleite_state["economy"]["coins"] = 3
	_mit_buchung(pleite_state)
	var pleite := FakeGameState.new(pleite_state)
	assert_eq(OrtFlughafen.kaufe_gfree(pleite, ware), OrtFlughafen.KAUF_PLEITE, "pleite = pleite")
	assert_eq(int(pleite.get_value("economy.coins")), 3, "Kauf ist atomar")
	assert_eq((pleite.get_value("home.storage") as Array).size(), 0, "kein Möbel ohne Geld")
	assert_eq(OrtFlughafen.kaufe_gfree(null, ware), OrtFlughafen.KAUF_ZU, "null-gs kracht nicht")


func test_gfree_sortiment_ist_exklusiv_und_ueberteuert() -> void:
	var moebel_anzahl := 0
	var snack_anzahl := 0
	for ware: Dictionary in OrtFlughafen.GOOBY_FREE_SORTIMENT:
		assert_true(int(ware.get("preis", 0)) > 0, "%s hat einen Preis" % ware.get("id"))
		if str(ware["typ"]) == "moebel":
			moebel_anzahl += 1
			assert_true(str(ware["id"]).begins_with("gfree_"), "Deko nutzt gfree_*-Präfix")
		else:
			snack_anzahl += 1
	assert_true(moebel_anzahl >= 4 and moebel_anzahl <= 6, "4–6 exklusive Artikel")
	assert_true(snack_anzahl >= 1, "Reise-Snacks dabei")
	# „Leicht überteuert“: Snacks liegen ÜBER dem REHWEI-Preis derselben Id.
	var rehwei: Dictionary = {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://scripts/city/data/rehwei_sortiment.json")
	)
	for eintrag: Variant in parsed.get("waren", []):
		rehwei[str(eintrag["id"])] = int(eintrag.get("preis", 0))
	for ware: Dictionary in OrtFlughafen.GOOBY_FREE_SORTIMENT:
		if str(ware["typ"]) == "snack" and rehwei.has(str(ware["id"])):
			assert_true(
				int(ware["preis"]) > int(rehwei[str(ware["id"])]),
				"%s ist am Flughafen teurer" % ware["id"]
			)


func test_gfree_katalogeintraege_haben_assets() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXTRA_JSON))
	assert_true(parsed is Dictionary and parsed.get("items") is Array, "furniture_extra lesbar")
	var gefunden: Dictionary = {}
	for item: Variant in parsed["items"]:
		var id := str(item.get("id", ""))
		if not id.begins_with("gfree_"):
			continue
		gefunden[id] = true
		assert_eq(int(item.get("preis", -1)), 0, "%s: preis 0 = exklusiv (kein IKEA)" % id)
		assert_true(int(item.get("verkaufswert", 0)) > 0, "%s: verkaufswert" % id)
		assert_ne(str(item.get("name_en", "")), "", "%s: EN-Name" % id)
		var glb := "res://assets/furniture/%s" % str(item.get("glb", ""))
		assert_true(ResourceLoader.exists(glb), "%s: GLB fehlt (%s)" % [id, glb])
	for ware: Dictionary in OrtFlughafen.GOOBY_FREE_SORTIMENT:
		if str(ware["typ"]) != "moebel":
			continue
		var id := str(ware["id"])
		assert_true(gefunden.has(id), "%s steht im Möbel-Pack-Katalog" % id)
		# Duty-Free-Preis liegt ÜBER dem Wiederverkaufswert (überteuert).
		for item: Variant in parsed["items"]:
			if str(item.get("id", "")) == id:
				assert_true(
					int(ware["preis"]) > int(item.get("verkaufswert", 0)),
					"%s: Flughafen-Aufschlag" % id
				)


## -------------------------------------------------- Strings + Dialog


func _flach(node: Dictionary, prefix := "", out: Dictionary = {}) -> Dictionary:
	for key: String in node:
		var voll := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_flach(node[key], voll, out)
		else:
			out[voll] = node[key]
	return out


func test_strings_de_en_paritaet() -> void:
	var de: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_DE))
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_EN))
	assert_true(de is Dictionary and en is Dictionary, "Strings-Dateien lesbar")
	var de_keys := _flach(de).keys()
	var en_keys := _flach(en).keys()
	de_keys.sort()
	en_keys.sort()
	assert_eq(de_keys, en_keys, "DE↔EN-Parität der raumstation-Strings")
	for key: String in de_keys:
		assert_ne(str(_flach(de)[key]), "", "DE-Text leer: %s" % key)
	# Die Keys sind über den I18n-Loader erreichbar (kein Kollisionstod).
	for key in ["raumstation.automat.moehre", "gfree.titel", "rewards.food.weltraumMoehre"]:
		assert_ne(I18nService.t(key), key, "Key fehlt im Loader: %s" % key)


func test_dialog_hat_en_pendant_und_laeuft() -> void:
	var de: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIALOG_DE))
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIALOG_EN))
	assert_true(de is Dictionary and en is Dictionary, "Dialog-Dateien lesbar")
	var de_nodes: Dictionary = de.get("nodes", {})
	var en_nodes: Dictionary = en.get("nodes", {})
	var de_keys := de_nodes.keys()
	var en_keys := en_nodes.keys()
	de_keys.sort()
	en_keys.sort()
	assert_eq(de_keys, en_keys, "gleiche Knoten in DE und EN")
	for key: String in de_keys:
		var de_opt: Array = de_nodes[key].get("optionen", [])
		var en_opt: Array = en_nodes[key].get("optionen", [])
		assert_eq(de_opt.size(), en_opt.size(), "%s: gleich viele Optionen" % key)
		assert_eq(
			de_nodes[key].get("effekt", []),
			en_nodes[key].get("effekt", []),
			"%s: gleiche Effekte" % key
		)
	# Der Baum lädt im Runner und der Automat hängt am laden-Effekt.
	var runner := OrtDialogRunner.new(OrtDialogRunner.baum_laden(DIALOG_DE))
	assert_true(runner.ist_geladen(), "Dialog lädt im Runner")
	var hat_laden := false
	for key: String in de_nodes:
		if (de_nodes[key].get("effekt", []) as Array).has("laden"):
			hat_laden = true
	assert_true(hat_laden, "ein Knoten öffnet den Astro-Automaten")


## ----------------------------------------------- Flughafen-Verdrahtung


func test_flughafen_szene_zeigt_shuttle_nur_freigeschaltet() -> void:
	var szene: PackedScene = load(FLUG_SZENE)
	# Ohne space-Besuch: kein Shuttle-Knopf.
	var ohne: OrtFlughafen = szene.instantiate()
	ohne.game_state_override = FakeGameState.new(_basis_state())
	tree.root.add_child(ohne)
	await wait_frames(2)
	assert_eq(ohne.find_child("Shuttle", true, false), null, "ohne space kein Shuttle")
	assert_ne(ohne.find_child("GoobyFree", true, false), null, "GOOBY-FREE-Knopf steht")
	assert_ne(ohne.find_child("GoobyFreeStand", true, false), null, "Duty-Free-Stand steht")
	ohne.queue_free()
	await wait_frames(1)
	# Mit space-Besuch: Shuttle-Knopf da.
	var frei_state := _basis_state()
	frei_state["vacation"]["visited"] = {"space": true}
	var mit: OrtFlughafen = szene.instantiate()
	mit.game_state_override = FakeGameState.new(frei_state)
	tree.root.add_child(mit)
	await wait_frames(2)
	assert_ne(mit.find_child("Shuttle", true, false), null, "mit space: Shuttle-Knopf")
	mit.queue_free()
	await wait_frames(1)
