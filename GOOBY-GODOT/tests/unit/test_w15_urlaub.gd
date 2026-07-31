extends TestCase
## W15/URLAUB (User-Wunsch „Gooby im Urlaub begleiten“) — Besuchs-Feature:
## - Ziel→Archetyp-Mapping deckt ALLE 9 Katalog-Ziele (space → GOOB-1).
## - Besuchs-Gate: NUR während Phase away (returnReady/overdue/none = zu).
## - Routing: Route je Archetyp + idempotente Registrierung; space fährt
##   die BESTEHENDE Raumstation an.
## - Aktivitäten-Statemaschinen PUR: Tap-Spots (5, Doppel-Tipp zählt
##   nicht), Souvenir-Tagescooldown (zeitinjiziert), Bestell-Rotation.
## - Souvenir-Gutschrift additiv (Münzen + inventory.items, atomar).
## - Besuchs-Flags: additiv im vacation-Slice, überleben slice_of UND
##   Abholung; Phasen/Timestamps bleiben unangetastet.
## - Szenen-Smoke je Archetyp (Strand/Berge/Stadt) + Reise-App-Knopf.
## - Strings: DE↔EN-Parität, 8 Erzähl-Lines je Archetyp, Rotation.

const Vacation := preload("res://scripts/logic/vacation.gd")

const STRINGS_DE := "res://strings/de/urlaub.json"
const STRINGS_EN := "res://strings/en/urlaub.json"

## 2026-07-25 12:00:00 UTC — fixer Testzeitpunkt (Zeit IMMER injiziert).
const JETZT := 1784980800000


## GameState-Double (Muster test_w13b_raumstation): dotted get/set +
## update(mutator) + state().
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


## Router-Attrappe: merkt sich register_route/goto/back.
class FakeRouter:
	extends RefCounted
	var routen: Dictionary = {}
	var ziele: Array = []
	var zurueck := 0
	var busy := false

	func register_route(target: StringName, szene: String) -> void:
		routen[target] = szene

	func goto(target: StringName, params: Dictionary = {}) -> void:
		ziele.append({"target": target, "params": params})

	func back() -> bool:
		zurueck += 1
		return true

	func is_busy() -> bool:
		return busy


func _away_slice(dest_id: String, now_ms: int) -> Dictionary:
	var v := Vacation.default_slice()
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = dest_id
	v["bookedAt"] = now_ms - Vacation.MS_PER_DAY
	v["returnAt"] = now_ms + 2 * Vacation.MS_PER_DAY
	v["pickupBy"] = now_ms + 3 * Vacation.MS_PER_DAY
	return v


func _basis_state(dest_id := "beach", now_ms := JETZT) -> Dictionary:
	return {
		"vacation": _away_slice(dest_id, now_ms),
		"economy": {"coins": 100},
		"inventory": {"items": {}, "food": {}},
		"gooby": {"stats": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "fun": 50.0}},
		"buffs": {"aktiv": []},
		"city": {},
	}


## Für Baum-Tests (Szene/App laufen auf Systemzeit): away um JETZT_ECHT.
func _echt_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## ------------------------------------------------- Mapping + Gate + Route


func test_mapping_deckt_alle_neun_ziele() -> void:
	assert_eq(
		UrlaubsBesuch.ZIEL_ARCHETYP.size(),
		Vacation.CATALOG.size(),
		"Mapping hat genau einen Eintrag je Katalog-Ziel"
	)
	for ziel: String in Vacation.CATALOG:
		var archetyp := UrlaubsBesuch.archetyp_fuer(ziel)
		assert_ne(archetyp, "", "%s hat einen Archetyp" % ziel)
		if archetyp == UrlaubsBesuch.ARCHETYP_SPACE:
			continue
		assert_true(
			UrlaubsOrt.ARCHETYP_DATEN.has(archetyp), "%s: Archetyp %s baubar" % [ziel, archetyp]
		)
		assert_true(
			ResourceLoader.exists(str(UrlaubsBesuch.SZENEN[archetyp])),
			"%s: Szene existiert" % archetyp
		)
	assert_eq(UrlaubsBesuch.archetyp_fuer("space"), UrlaubsBesuch.ARCHETYP_SPACE)
	assert_eq(UrlaubsBesuch.archetyp_fuer("quatschziel"), "", "unbekanntes Ziel → leer")


func test_gate_nur_waehrend_urlaub() -> void:
	assert_false(UrlaubsBesuch.verfuegbar({}, JETZT), "frischer Save: kein Besuch")
	var daheim := {"vacation": Vacation.default_slice()}
	assert_false(UrlaubsBesuch.verfuegbar(daheim, JETZT), "phase none → zu")
	var weg := {"vacation": _away_slice("meadowTrip", JETZT)}
	assert_true(UrlaubsBesuch.verfuegbar(weg, JETZT), "away → Besuch möglich")
	assert_false(
		UrlaubsBesuch.verfuegbar(weg, JETZT + 2 * Vacation.MS_PER_DAY),
		"returnReady (wartet am Flughafen) → zu"
	)
	assert_false(UrlaubsBesuch.verfuegbar(weg, JETZT + 9 * Vacation.MS_PER_DAY), "overdue → zu")


func test_route_und_registrierung() -> void:
	assert_eq(UrlaubsBesuch.route_fuer("beach"), UrlaubsBesuch.ROUTEN["strand"])
	assert_eq(UrlaubsBesuch.route_fuer("nightSky"), UrlaubsBesuch.ROUTEN["berge"])
	assert_eq(UrlaubsBesuch.route_fuer("bakery"), UrlaubsBesuch.ROUTEN["stadt"])
	assert_eq(UrlaubsBesuch.route_fuer("space"), OrtRaumstation.ROUTE, "space → GOOB-1")
	var router := FakeRouter.new()
	UrlaubsBesuch.registriere_route(router, "harbor")
	UrlaubsBesuch.registriere_route(router, "harbor")
	assert_eq(
		str(router.routen.get(UrlaubsBesuch.ROUTEN["strand"], "")),
		str(UrlaubsBesuch.SZENEN["strand"]),
		"Strand-Route idempotent angemeldet"
	)
	UrlaubsBesuch.registriere_route(router, "space")
	assert_eq(
		str(router.routen.get(OrtRaumstation.ROUTE, "")),
		OrtRaumstation.SZENE,
		"space meldet die BESTEHENDE Raumstation an"
	)
	UrlaubsBesuch.registriere_route(null, "beach")  # darf nicht krachen


func test_besuche_startet_reise_nur_bei_offenem_gate() -> void:
	var gs := FakeGameState.new(_basis_state("meadowTrip"))
	var router := FakeRouter.new()
	assert_true(UrlaubsBesuch.besuche(gs, router, JETZT), "Gate offen → Reise")
	assert_eq(router.ziele.size(), 1, "genau ein goto")
	assert_eq(router.ziele[0]["target"], UrlaubsBesuch.ROUTEN["berge"])
	assert_eq(str(router.ziele[0]["params"].get("dest_id", "")), "meadowTrip")
	var daheim := FakeGameState.new({"vacation": Vacation.default_slice()})
	assert_false(UrlaubsBesuch.besuche(daheim, router, JETZT), "Gate zu → keine Reise")
	assert_eq(router.ziele.size(), 1, "kein zweites goto")
	router.busy = true
	assert_false(UrlaubsBesuch.besuche(gs, router, JETZT), "Router busy → warten")


## ------------------------------------------ Aktivitäten-Statemaschinen


func test_tap_spots_statemaschine() -> void:
	var zustand := UrlaubsAktivitaeten.tap_neu()
	assert_eq(int(zustand["gesamt"]), UrlaubsAktivitaeten.TAP_ANZAHL, "5 Spots")
	assert_false(UrlaubsAktivitaeten.tap_fertig(zustand), "frisch = nicht fertig")
	var erster := UrlaubsAktivitaeten.tap_tippe(zustand, 0)
	assert_true(bool(erster["ok"]))
	assert_eq(int(erster["rest"]), 4)
	var doppelt := UrlaubsAktivitaeten.tap_tippe(zustand, 0)
	assert_false(bool(doppelt["ok"]), "Doppel-Tipp zählt nicht")
	assert_eq(int(doppelt["rest"]), 4, "Zustand unberührt")
	assert_false(bool(UrlaubsAktivitaeten.tap_tippe(zustand, 99)["ok"]), "Index außerhalb")
	assert_false(bool(UrlaubsAktivitaeten.tap_tippe(zustand, -1)["ok"]), "negativer Index")
	for i in [1, 2, 3]:
		assert_false(bool(UrlaubsAktivitaeten.tap_tippe(zustand, i)["fertig"]), "noch nicht fertig")
	var letzter := UrlaubsAktivitaeten.tap_tippe(zustand, 4)
	assert_true(bool(letzter["ok"]))
	assert_true(bool(letzter["fertig"]), "5/5 → fertig")
	assert_true(UrlaubsAktivitaeten.tap_fertig(zustand))


func test_souvenir_tagescooldown_zeitinjiziert() -> void:
	var frisch := Vacation.default_slice()
	assert_true(UrlaubsAktivitaeten.souvenir_bereit(frisch, JETZT), "frischer Slice → bereit")
	frisch["souvenirTag"] = UrlaubsAktivitaeten.souvenir_tag(JETZT)
	assert_false(
		UrlaubsAktivitaeten.souvenir_bereit(frisch, JETZT + 3_600_000),
		"gleicher UTC-Tag → Cooldown"
	)
	assert_true(
		UrlaubsAktivitaeten.souvenir_bereit(frisch, JETZT + Vacation.MS_PER_DAY),
		"nächster Tag → wieder bereit"
	)


func test_souvenir_gutschrift_additiv_und_atomar() -> void:
	var gs := FakeGameState.new(_basis_state("beach"))
	var res := UrlaubsAktivitaeten.souvenir_einloesen(gs, "beach", JETZT)
	assert_true(bool(res["ok"]), "erster Fund klappt")
	assert_eq(str(res["item_id"]), "souvenir_beach")
	assert_eq(
		int(gs.get_value("economy.coins")),
		100 + UrlaubsAktivitaeten.SOUVENIR_COINS,
		"Münzen additiv"
	)
	assert_eq(int(gs.get_value("inventory.items.souvenir_beach")), 1, "Fundstück im Inventar")
	assert_true(gs.slices_notified.has("vacation"), "vacation-Slice gemeldet")
	var nochmal := UrlaubsAktivitaeten.souvenir_einloesen(gs, "beach", JETZT + 1000)
	assert_false(bool(nochmal["ok"]), "gleicher Tag → kein zweiter Fund")
	assert_eq(
		int(gs.get_value("economy.coins")),
		100 + UrlaubsAktivitaeten.SOUVENIR_COINS,
		"nichts doppelt gutgeschrieben"
	)
	var morgen := UrlaubsAktivitaeten.souvenir_einloesen(gs, "beach", JETZT + Vacation.MS_PER_DAY)
	assert_true(bool(morgen["ok"]), "am nächsten Tag wieder")
	assert_eq(UrlaubsAktivitaeten.souvenir_einloesen(null, "beach", JETZT)["ok"], false)


func test_bestellung_rotation() -> void:
	assert_eq(UrlaubsAktivitaeten.bestellung_index(0, 5), 0)
	assert_eq(UrlaubsAktivitaeten.bestellung_index(4, 5), 4)
	assert_eq(UrlaubsAktivitaeten.bestellung_index(5, 5), 0, "Rotation wickelt um")
	assert_eq(UrlaubsAktivitaeten.bestellung_index(7, 5), 2)
	assert_eq(UrlaubsAktivitaeten.bestellung_index(3, 0), -1, "leere Liste → -1")


func test_fun_bonus_clamp() -> void:
	var gs := FakeGameState.new(_basis_state())
	UrlaubsAktivitaeten.fun_bonus(gs, 4.0)
	assert_almost(float(gs.get_value("gooby.stats.fun")), 54.0, 1e-6, "kleiner Bonus")
	UrlaubsAktivitaeten.fun_bonus(gs, 999.0)
	assert_almost(float(gs.get_value("gooby.stats.fun")), 100.0, 1e-6, "clamp bei 100")
	UrlaubsAktivitaeten.fun_bonus(null, 4.0)  # darf nicht krachen


## ------------------------------------------------------- Besuchs-Flags


func test_besuchs_flag_ueberlebt_slice_of_und_abholung() -> void:
	var gs := FakeGameState.new(_basis_state("beach"))
	var vorher := Vacation.slice_of(gs.state())
	assert_true(UrlaubsBesuch.merke_besuch(gs, "beach"), "erster Besuch latcht")
	assert_false(UrlaubsBesuch.merke_besuch(gs, "beach"), "idempotent")
	assert_false(UrlaubsBesuch.merke_besuch(gs, "quatschziel"), "unbekanntes Ziel → nein")
	var v := Vacation.slice_of(gs.state())
	assert_true(bool(v["besuche"].get("beach", false)), "Flag überlebt slice_of")
	# Besuch ist eine ANSICHT: Phase/Timestamps/visited bleiben unberührt.
	assert_eq(str(v["phase"]), str(vorher["phase"]), "Phase unverändert")
	assert_eq(int(v["returnAt"]), int(vorher["returnAt"]), "returnAt unverändert")
	assert_eq(v["visited"], vorher["visited"], "Sammelpass unverändert")
	# Abholung normalisiert den Slice — die Erinnerung bleibt.
	var res := ReiseLogic.abholen(v, JETZT + 2 * Vacation.MS_PER_DAY + 1)
	assert_true(bool(res["ok"]), "Abholung klappt")
	assert_true(bool(res["vacation"]["besuche"].get("beach", false)), "Flag überlebt die Abholung")


## --------------------------------------------------------- Szenen-Smoke


func test_szenen_smoke_strand() -> void:
	var gs := FakeGameState.new(_basis_state("beach", _echt_now()))
	var ort: UrlaubsOrt = _instanziere("strand", gs)
	await wait_frames(3)
	assert_eq(ort.archetyp, "strand")
	assert_eq(ort.dest_id, "beach", "Fallback-Ziel des Archetyps")
	assert_eq(ort.ort_id, "urlaub_strand")
	for knoten in ["Meer", "Liegestuhl", "Sonnenschirm", "Sandburg", "SouvenirSpot", "Muschel0"]:
		assert_ne(ort.find_child(knoten, true, false), null, "%s steht" % knoten)
	assert_eq(ort.statisten.size(), 2, "2 Urlauber-Statisten")
	for knopf in ["Streicheln", "Foto", "MiniAktivitaet", "Souvenir"]:
		assert_ne(ort.find_child(knopf, true, false), null, "Knopf %s da" % knopf)
	assert_true(
		bool(Vacation.slice_of(gs.state())["besuche"].get("beach", false)),
		"Besuch beim Betreten gelatcht"
	)
	# Mini-Aktivität: 5 Tap-Spots, alle tippen → fertig, Ebene räumt ab.
	ort._on_mini()
	await wait_frames(2)
	assert_eq(ort.tap_knoepfe.size(), UrlaubsAktivitaeten.TAP_ANZAHL, "5 Tap-Knöpfe")
	var fun_vorher := float(gs.get_value("gooby.stats.fun"))
	for i in UrlaubsAktivitaeten.TAP_ANZAHL:
		ort._on_tap(i)
	assert_true(UrlaubsAktivitaeten.tap_fertig(ort.tap_zustand), "alle Spots getippt")
	assert_true(
		float(gs.get_value("gooby.stats.fun")) > fun_vorher, "Mini-Abschluss gibt Spaß-Bonus"
	)
	await wait_frames(2)
	assert_eq(ort.find_child("TapEbene", true, false), null, "Tap-Ebene abgeräumt")
	# Souvenir-Spot: Gutschrift läuft (souvenirTag 0 ≠ heute).
	ort._on_souvenir()
	assert_eq(int(gs.get_value("inventory.items.souvenir_beach", 0)), 1, "Fundstück da")
	ort.queue_free()
	await wait_frames(1)


func test_szenen_smoke_berge() -> void:
	var gs := FakeGameState.new(_basis_state("meadowTrip", _echt_now()))
	var ort: UrlaubsOrt = _instanziere("berge", gs, {"dest_id": "meadowTrip"})
	await wait_frames(3)
	assert_eq(ort.archetyp, "berge")
	assert_eq(ort.dest_id, "meadowTrip")
	for knoten in ["Zelt", "Lagerfeuer", "Berg", "SouvenirSpot"]:
		assert_ne(ort.find_child(knoten, true, false), null, "%s steht" % knoten)
	assert_eq(ort.statisten.size(), 2, "2 Urlauber-Statisten")
	# Streicheln: Spaß-Bonus über die bestehende Stats-Mathematik.
	var fun_vorher := float(gs.get_value("gooby.stats.fun"))
	ort._on_streicheln()
	assert_almost(
		float(gs.get_value("gooby.stats.fun")),
		fun_vorher + UrlaubsAktivitaeten.FUN_STREICHELN,
		1e-6,
		"Streicheln gibt Spaß"
	)
	ort.queue_free()
	await wait_frames(1)


func test_szenen_smoke_stadt_und_rueckweg() -> void:
	var gs := FakeGameState.new(_basis_state("bigCity", _echt_now()))
	var ort: UrlaubsOrt = _instanziere("stadt", gs, {"dest_id": "bigCity"})
	await wait_frames(3)
	assert_eq(ort.archetyp, "stadt")
	for knoten in ["CafeTerrasse", "Sehenswuerdigkeit", "Lichterkette", "SouvenirSpot"]:
		assert_ne(ort.find_child(knoten, true, false), null, "%s steht" % knoten)
	# Bestell-Gag: Rotation zählt hoch, Spaß-Bonus fließt.
	var fun_vorher := float(gs.get_value("gooby.stats.fun"))
	ort._on_mini()
	ort._on_mini()
	assert_eq(ort.bestell_zaehler, 2, "zwei Bestellungen rotiert")
	assert_true(float(gs.get_value("gooby.stats.fun")) > fun_vorher, "Bestellung gibt Spaß")
	# Rückweg: Besuch beendet → Router-back (KEIN Stadt-Spawn).
	var router: FakeRouter = ort.router_override
	ort._on_verlassen()
	assert_eq(router.zurueck, 1, "zurück zur vorherigen Szene")
	assert_eq(router.ziele.size(), 0, "kein goto nötig, back reicht")
	ort.queue_free()
	await wait_frames(1)


func _instanziere(archetyp: String, gs: FakeGameState, params: Dictionary = {}) -> UrlaubsOrt:
	var szene: PackedScene = load(str(UrlaubsBesuch.SZENEN[archetyp]))
	var ort: UrlaubsOrt = szene.instantiate()
	ort.game_state_override = gs
	ort.router_override = FakeRouter.new()
	if not params.is_empty():
		ort.receive_params(params)
	tree.root.add_child(ort)
	return ort


## --------------------------------------------------------- Reise-App


func test_reise_app_zeigt_besuchen_knopf_nur_wenn_weg() -> void:
	var weg := FakeGameState.new(_basis_state("beach", _echt_now()))
	var app := ReiseApp.new()
	app.gs = weg
	tree.root.add_child(app)
	await wait_frames(1)
	assert_ne(app.find_child("GoobyBesuchen", true, false), null, "away → Besuchen-Knopf")
	app.queue_free()
	await wait_frames(1)
	var daheim_state := _basis_state("beach", _echt_now())
	daheim_state["vacation"] = Vacation.default_slice()
	var daheim := FakeGameState.new(daheim_state)
	var app2 := ReiseApp.new()
	app2.gs = daheim
	tree.root.add_child(app2)
	await wait_frames(1)
	assert_eq(app2.find_child("GoobyBesuchen", true, false), null, "daheim → kein Knopf")
	app2.queue_free()
	await wait_frames(1)


## ------------------------------------------------- Strings + Erzählung


func _flach(node: Dictionary, prefix := "", out: Dictionary = {}) -> Dictionary:
	for key: String in node:
		var voll := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_flach(node[key], voll, out)
		else:
			out[voll] = node[key]
	return out


func test_strings_de_en_paritaet_und_acht_lines() -> void:
	var de: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_DE))
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_EN))
	assert_true(de is Dictionary and en is Dictionary, "Strings-Dateien lesbar")
	var de_keys := _flach(de).keys()
	var en_keys := _flach(en).keys()
	de_keys.sort()
	en_keys.sort()
	assert_eq(de_keys, en_keys, "DE↔EN-Parität der urlaub-Strings")
	for sprache: Dictionary in [de, en]:
		var bubble: Dictionary = sprache["urlaub"]["bubble"]
		for archetyp: String in UrlaubsOrt.ARCHETYP_DATEN:
			assert_eq((bubble[archetyp] as Array).size(), 8, "8 Lines je Archetyp")
		assert_true((sprache["urlaub"]["bestellung"] as Array).size() >= 4, "Bestell-Gag-Pool")
		var souvenirs: Dictionary = sprache["urlaub"]["souvenir"]
		for ziel: String in Vacation.CATALOG:
			assert_ne(str(souvenirs.get(ziel, "")), "", "Souvenir-Name für %s" % ziel)
	for key in ["urlaub.knopf.besuchen", "urlaub.titel.strand", "urlaub.toast.souvenir_leer"]:
		assert_ne(I18nService.t(key), key, "Key fehlt im Loader: %s" % key)


func test_sprueche_rotation_ohne_wiederholung() -> void:
	UrlaubsSprueche.reset_fuer_tests()
	var gesehen: Dictionary = {}
	for _i in 8:
		var line := UrlaubsSprueche.naechste("strand")
		assert_ne(line, "", "Line nie leer")
		assert_false(gesehen.has(line), "keine Wiederholung vor Ablauf aller 8")
		gesehen[line] = true
	var neunte := UrlaubsSprueche.naechste("strand")
	assert_true(gesehen.has(neunte), "danach beginnt die Rotation von vorn")
	assert_eq(UrlaubsSprueche.naechste("quatsch"), "", "unbekannter Archetyp → leer")
	UrlaubsSprueche.reset_fuer_tests()
