extends TestCase
## W19/MITBRINGSEL — Mitbring-Momente (Doc E §3.2 Rückkehr + §3.3/3):
## - Abholung stempelt die Heimkehr-Latches (Ziel/Abflug/Abhol-Zeitpunkt),
##   sie überleben slice_of („Rückkehr steht aus“ im Save).
## - Reunion-Trigger GENAU EINMAL: feiern latcht + schenkt das Mitbringsel
##   additiv in inventory.items; zweiter Aufruf ist ein No-op.
## - Mitbringsel-DETERMINISMUS: seeded RNG aus Ziel + Abflug-Timestamp —
##   gleicher Urlaub, gleiches Mitbringsel; Seeds streuen über die Typen.
## - 24-h-GOOBY-FREE-Fenster öffnet/schließt mit INJIZIERTER Uhr; das
##   Fenster-Sortiment ist komplementär (die zwei NICHT mitgebrachten
##   Varianten) und exklusiv (fremde/abgelaufene Waren → zu).
## - Overlay-Dirigent-Einreihung (W18/J1): Heimkehr-Prio schlägt den
##   Tagesbonus, öffnet genau einmal, hinfällige Tickets verfallen still.
## - Strings: DE↔EN-Parität der heimkehr-Domain, alle Varianten benannt.

const Vacation := preload("res://scripts/logic/vacation.gd")

const STRINGS_DE := "res://strings/de/heimkehr.json"
const STRINGS_EN := "res://strings/en/heimkehr.json"

## 2026-07-25 12:00:00 UTC — fixer Testzeitpunkt (Zeit IMMER injiziert).
const JETZT := 1784980800000
const STUNDE_MS := 3_600_000


## Injizierbare Uhr (Muster game_state.clock — `"clock" in gs` wird wahr).
class FakeClock:
	extends RefCounted
	var jetzt := 0

	func now_ms() -> int:
		return jetzt


## GameState-Double (Muster test_w15_urlaub): dotted get/set +
## update(mutator) + state() + injizierte Uhr.
class FakeGameState:
	extends RefCounted
	var daten: Dictionary = {}
	var clock := FakeClock.new()
	var slices_notified: Array[String] = []

	func _init(start: Dictionary = {}, jetzt := 0) -> void:
		daten = start
		clock.jetzt = jetzt

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

	func update(mutator: Callable) -> void:
		mutator.call(daten)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## Raum-Attrappe fürs Reunion-Glue: game_state()/gooby()/say().
class FakeRoom:
	extends Node3D
	var gs_ref: Object = null
	var gooby_node: Node3D = null
	var gesagt: Array[String] = []

	func game_state() -> Object:
		return gs_ref

	func gooby() -> Node3D:
		return gooby_node

	func say(text: String) -> void:
		gesagt.append(text)


## Abgeholter vacation-Slice über den ECHTEN Abhol-Pfad (ReiseLogic).
func _abgeholte_vacation(dest_id: String, abhol_ms: int) -> Dictionary:
	var v := Vacation.default_slice()
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = dest_id
	v["bookedAt"] = abhol_ms - 3 * Vacation.MS_PER_DAY
	v["returnAt"] = abhol_ms - STUNDE_MS
	v["pickupBy"] = abhol_ms + 23 * STUNDE_MS
	var res := ReiseLogic.abholen(v, abhol_ms)
	return res["vacation"]


func _heimkehr_state(dest_id := "beach", abhol_ms := JETZT) -> Dictionary:
	return {
		"vacation": _abgeholte_vacation(dest_id, abhol_ms),
		"economy": {"coins": 200},
		"inventory": {"items": {}, "food": {}},
		"gooby": {"stats": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "fun": 50.0}},
		"city": {},
	}


## ---------------------------------------------------- Latches + Trigger


func test_abholen_stempelt_heimkehr_latches() -> void:
	var abflug := JETZT - 3 * Vacation.MS_PER_DAY
	var v := _abgeholte_vacation("harbor", JETZT)
	assert_eq(str(v["heimkehrZiel"]), "harbor", "Ziel gestempelt")
	assert_eq(int(v["heimkehrAbflug"]), abflug, "Abflug-Timestamp = bookedAt")
	assert_eq(int(v["heimkehrAt"]), JETZT, "Abhol-Zeitpunkt gestempelt")
	assert_false(bool(v["heimkehrGefeiert"]), "Reunion steht aus")
	# „Rückkehr steht aus“ überlebt die slice_of-Normalisierung (Save-Pfad).
	var nochmal := Vacation.slice_of({"vacation": v})
	assert_eq(str(nochmal["heimkehrZiel"]), "harbor", "Ziel überlebt slice_of")
	assert_eq(int(nochmal["heimkehrAbflug"]), abflug, "Abflug überlebt slice_of")
	assert_eq(int(nochmal["heimkehrAt"]), JETZT, "Abholung überlebt slice_of")
	assert_false(bool(nochmal["heimkehrGefeiert"]), "Latch überlebt slice_of")


func test_ausstehend_gate() -> void:
	assert_false(HeimkehrLogik.ausstehend({}), "frischer Save: nichts ausstehend")
	assert_false(
		HeimkehrLogik.ausstehend({"vacation": Vacation.default_slice()}),
		"ohne Abholung: nichts ausstehend"
	)
	var state := _heimkehr_state("beach")
	assert_true(HeimkehrLogik.ausstehend(state), "nach Abholung: Reunion steht aus")
	var gefeiert: Dictionary = Vacation.slice_of(state)
	gefeiert["heimkehrGefeiert"] = true
	assert_false(HeimkehrLogik.ausstehend({"vacation": gefeiert}), "gefeiert → nichts mehr")
	# Wieder verreist (neue Buchung VOR dem Heimbesuch): Gooby ist nicht
	# daheim — der Moment wartet bzw. wird von der nächsten Abholung ersetzt.
	var wieder_weg := ReiseLogic.buchen(Vacation.slice_of(state), "space", JETZT + STUNDE_MS)
	assert_true(bool(wieder_weg["ok"]), "Neu-Buchung klappt")
	assert_false(
		HeimkehrLogik.ausstehend({"vacation": wieder_weg["vacation"]}),
		"wieder verreist → kein Reunion-Moment im leeren Raum"
	)


func test_feiern_genau_einmal_und_item_additiv() -> void:
	var gs := FakeGameState.new(_heimkehr_state("beach"), JETZT)
	var erwartet := HeimkehrLogik.mitbringsel("beach", JETZT - 3 * Vacation.MS_PER_DAY)
	var res := HeimkehrLogik.feiern(gs)
	assert_true(bool(res["ok"]), "erste Feier klappt")
	assert_eq(str(res["item_id"]), str(erwartet["item_id"]), "deterministisches Geschenk")
	assert_eq(str(res["ziel_id"]), "beach", "Ziel im Ergebnis")
	assert_true(str(res["spruch_key"]).begins_with("heimkehr.spruch."), "Spruch-Key dabei")
	assert_eq(
		int(gs.get_value("inventory.items.%s" % str(res["item_id"]))),
		1,
		"Mitbringsel additiv im Inventar"
	)
	assert_true(bool(Vacation.slice_of(gs.state())["heimkehrGefeiert"]), "Latch gestempelt")
	assert_true(gs.slices_notified.has("vacation"), "vacation-Slice gemeldet")
	assert_true(gs.slices_notified.has("inventory"), "inventory-Slice gemeldet")
	var nochmal := HeimkehrLogik.feiern(gs)
	assert_false(bool(nochmal["ok"]), "zweite Feier ist ein No-op")
	assert_eq(
		int(gs.get_value("inventory.items.%s" % str(res["item_id"]))), 1, "nichts doppelt geschenkt"
	)
	assert_false(bool(HeimkehrLogik.feiern(null)["ok"]), "null-gs kracht nicht")


## ------------------------------------------------------- Determinismus


func test_mitbringsel_determinismus_pro_ziel_und_seed() -> void:
	var typ := HeimkehrLogik.mitbringsel_typ("beach", JETZT)
	for _i in 10:
		assert_eq(HeimkehrLogik.mitbringsel_typ("beach", JETZT), typ, "gleicher Seed, gleicher Typ")
	for ziel: String in Vacation.CATALOG:
		var wahl := HeimkehrLogik.mitbringsel_typ(ziel, JETZT)
		assert_true(HeimkehrLogik.TYPEN.has(wahl), "%s: Typ aus dem Pool" % ziel)
		assert_eq(
			str(HeimkehrLogik.mitbringsel(ziel, JETZT)["item_id"]),
			HeimkehrLogik.mitbringsel_id(ziel, wahl),
			"%s: Item-Id passt zum Typ" % ziel
		)
	# Der Seed streut wirklich: über 40 Abflug-Zeitpunkte fallen
	# mindestens zwei verschiedene Varianten.
	var gesehen: Dictionary = {}
	for i in 40:
		gesehen[HeimkehrLogik.mitbringsel_typ("beach", JETZT + i * STUNDE_MS)] = true
	assert_true(gesehen.size() >= 2, "Seeds streuen über die Typen (%d)" % gesehen.size())
	# Wiedersehens-Spruch: deterministisch und aus dem Pool.
	var spruch := HeimkehrLogik.spruch_key("beach", JETZT)
	assert_eq(HeimkehrLogik.spruch_key("beach", JETZT), spruch, "Spruch deterministisch")
	var nummer := int(spruch.trim_prefix("heimkehr.spruch."))
	assert_true(nummer >= 1 and nummer <= HeimkehrLogik.SPRUCH_ANZAHL, "Spruch-Nummer im Pool")


## ---------------------------------------------------- 24-h-Fenster


func test_fenster_oeffnet_und_schliesst_mit_injizierter_uhr() -> void:
	var state := _heimkehr_state("bigCity", JETZT)
	assert_false(HeimkehrLogik.fenster_offen({}, JETZT), "frischer Save: zu")
	assert_false(HeimkehrLogik.fenster_offen(state, JETZT - 1), "vor der Abholung: zu")
	assert_true(HeimkehrLogik.fenster_offen(state, JETZT), "direkt nach der Abholung: offen")
	assert_true(
		HeimkehrLogik.fenster_offen(state, JETZT + HeimkehrLogik.FENSTER_MS - 1),
		"kurz vor Ablauf: noch offen"
	)
	assert_false(
		HeimkehrLogik.fenster_offen(state, JETZT + HeimkehrLogik.FENSTER_MS), "nach 24 h: wieder zu"
	)
	assert_eq(HeimkehrLogik.fenster_rest_h(state, JETZT), 24, "frisch: 24 Rest-Stunden")
	assert_eq(
		HeimkehrLogik.fenster_rest_h(state, JETZT + HeimkehrLogik.FENSTER_MS - STUNDE_MS / 2),
		1,
		"kurz vor Ablauf: 1 Rest-Stunde (aufgerundet)"
	)
	assert_eq(
		HeimkehrLogik.fenster_rest_h(state, JETZT + HeimkehrLogik.FENSTER_MS),
		0,
		"zu: 0 Rest-Stunden"
	)


func test_fenster_sortiment_komplementaer_und_exklusiv() -> void:
	var state := _heimkehr_state("space", JETZT)
	var mitgebracht := HeimkehrLogik.mitbringsel_typ("space", JETZT - 3 * Vacation.MS_PER_DAY)
	var sortiment := HeimkehrLogik.fenster_sortiment(state, JETZT)
	assert_eq(sortiment.size(), HeimkehrLogik.TYPEN.size() - 1, "genau die zwei anderen")
	for ware: Dictionary in sortiment:
		assert_ne(str(ware["mitbringsel_typ"]), mitgebracht, "Mitgebrachtes nicht im Regal")
		assert_eq(str(ware["typ"]), "mitbringsel", "Fenster-Waren-Typ")
		assert_eq(str(ware["ziel_id"]), "space", "Ziel-Bezug")
		assert_eq(
			int(ware["preis"]),
			int(HeimkehrLogik.TYP_PREISE[str(ware["mitbringsel_typ"])]),
			"Preis aus der Tabelle"
		)
	assert_eq(
		HeimkehrLogik.fenster_sortiment(state, JETZT + HeimkehrLogik.FENSTER_MS).size(),
		0,
		"zu → leeres Regal"
	)


func test_kaufe_nur_im_fenster_und_atomar() -> void:
	var gs := FakeGameState.new(_heimkehr_state("beach", JETZT), JETZT)
	var sortiment := HeimkehrLogik.fenster_sortiment(gs.state(), JETZT)
	var ware: Dictionary = sortiment[0]
	assert_eq(HeimkehrLogik.kaufe(gs, ware, JETZT), HeimkehrLogik.KAUF_OK, "Fenster-Kauf ok")
	assert_eq(int(gs.get_value("economy.coins")), 200 - int(ware["preis"]), "Münzen abgebucht")
	assert_eq(int(gs.get_value("inventory.items.%s" % str(ware["id"]))), 1, "Ware im Inventar")
	assert_true(gs.slices_notified.has("inventory"), "inventory-Slice gemeldet")
	assert_eq(
		HeimkehrLogik.kaufe(gs, ware, JETZT + HeimkehrLogik.FENSTER_MS),
		HeimkehrLogik.KAUF_ZU,
		"nach 24 h: zu"
	)
	assert_eq(
		HeimkehrLogik.kaufe(gs, {"id": "gfree_shuttle", "preis": 1}, JETZT),
		HeimkehrLogik.KAUF_ZU,
		"fremde Ware ist NICHT Fenster-exklusiv kaufbar"
	)
	var pleite := FakeGameState.new(_heimkehr_state("beach", JETZT), JETZT)
	pleite.daten["economy"]["coins"] = 3
	assert_eq(HeimkehrLogik.kaufe(pleite, ware, JETZT), HeimkehrLogik.KAUF_PLEITE, "pleite")
	assert_eq(HeimkehrLogik.kaufe(null, ware, JETZT), HeimkehrLogik.KAUF_ZU, "null-gs kracht nicht")


func test_taxi_gate_bleibt_vom_fenster_unberuehrt() -> void:
	# Das Heimkehr-Fenster öffnet den Stand über den NEUEN Pfad — das
	# W13B-Taxi-Gate (gooby_free_offen) bleibt ohne Buchung geschlossen.
	var state := _heimkehr_state("beach", JETZT)
	assert_false(OrtFlughafen.gooby_free_offen(state), "Taxi-Gate bleibt zu")
	assert_true(HeimkehrLogik.fenster_offen(state, JETZT), "Fenster parallel offen")


## ------------------------------------------- Dirigent + Karte (Szene)


func test_overlay_dirigent_einreihung_und_genau_einmal() -> void:
	var gs := FakeGameState.new(_heimkehr_state("beach"), JETZT + STUNDE_MS)
	var room := FakeRoom.new()
	room.gs_ref = gs
	var gooby := Node3D.new()
	room.gooby_node = gooby
	room.add_child(gooby)
	tree.root.add_child(room)
	var dirigent := OverlayDirigent.new()
	dirigent.pause_s = 0.0
	tree.root.add_child(dirigent)
	dirigent.set_process(false)
	# Konkurrenz-Ticket (Tagesbonus-Attrappe, Prio 10) meldet sich ZUERST.
	var bonus := {"geoeffnet": 0}
	var bonus_oeffner := func() -> Control:
		bonus["geoeffnet"] += 1
		return null
	dirigent.anfordern("tagesbonus", OverlayDirigent.PRIO_TAGESBONUS, bonus_oeffner)
	HeimkehrMoment.attach_to(room)
	assert_true(dirigent.belegt(), "Heimkehr-Ticket eingereiht")
	dirigent.tick(1.0)
	assert_eq(dirigent.aktiv_id(), "", "Vorlauf armiert erst (Morgen-Ritual-Geist)")
	dirigent.tick(1.0)
	assert_eq(dirigent.aktiv_id(), "heimkehr", "Heimkehr-Prio schlägt den Tagesbonus")
	assert_eq(int(bonus["geoeffnet"]), 0, "Tagesbonus wartet hinter dem Herzmoment")
	await wait_frames(2)
	var karte := tree.root.find_child("HeimkehrKarte", true, false)
	assert_ne(karte, null, "Übergabe-Karte steht")
	assert_true(bool(Vacation.slice_of(gs.state())["heimkehrGefeiert"]), "beim Öffnen gelatcht")
	var item_id := str(
		HeimkehrLogik.mitbringsel("beach", JETZT - 3 * Vacation.MS_PER_DAY)["item_id"]
	)
	assert_eq(int(gs.get_value("inventory.items.%s" % item_id)), 1, "Geschenk übergeben")
	assert_eq(room.gesagt.size(), 1, "genau ein Wiedersehens-Spruch")
	assert_ne(room.gesagt[0], "", "Spruch nie leer")
	assert_ne(room.find_child("HeimkehrGepaeck", true, false), null, "Koffer + Tüte stehen")
	# Genau-einmal: erneutes attach_to reiht NICHTS mehr ein (Latch zu).
	HeimkehrMoment.attach_to(room)
	assert_eq(dirigent._queue.size(), 1, "nur das wartende Tagesbonus-Ticket, kein Doppel")
	# Karte schließen → Sequenz läuft weiter, nichts wird doppelt gefeiert.
	karte.close()
	await wait_frames(3)
	dirigent.tick(1.0)
	assert_eq(int(bonus["geoeffnet"]), 1, "Tagesbonus kommt NACH dem Herzmoment dran")
	assert_eq(dirigent.aktiv_id(), "", "Karte zu → Sequenz frei")
	assert_eq(int(gs.get_value("inventory.items.%s" % item_id)), 1, "kein zweites Geschenk")
	PanelStack.clear()
	dirigent.queue_free()
	room.queue_free()
	await wait_frames(2)


func test_karte_direkt_ohne_dirigent_mit_fenster_hinweis() -> void:
	var gs := FakeGameState.new(_heimkehr_state("bigCity"), JETZT + STUNDE_MS)
	var room := FakeRoom.new()
	room.gs_ref = gs
	tree.root.add_child(room)
	# Kein Dirigent im Baum → attach_to öffnet direkt (Alt-Pfad der Tests).
	HeimkehrMoment.attach_to(room)
	await wait_frames(2)
	var karte := tree.root.find_child("HeimkehrKarte", true, false)
	assert_ne(karte, null, "Karte öffnet direkt")
	# W19-Playtest-Fund: die Karte MUSS über dem Home-HUD (UiLayer 10)
	# liegen, sonst bleiben HUD-Knöpfe über dem Schleier sichtbar+tappbar.
	var layer_node: Node = karte
	while layer_node != null and not (layer_node is CanvasLayer):
		layer_node = layer_node.get_parent()
	assert_ne(layer_node, null, "Karte lebt auf einem eigenen CanvasLayer")
	assert_eq(
		(layer_node as CanvasLayer).layer,
		HeimkehrMoment.KARTEN_LAYER,
		"Karten-Layer ist der dokumentierte KARTEN_LAYER"
	)
	assert_true((layer_node as CanvasLayer).layer > 10, "Karte liegt ÜBER dem Home-HUD (10)")
	var tuete := karte.find_child("HeimkehrTuete", true, false) as Label
	assert_ne(tuete, null, "Tüten-Zeile steht")
	var typ := HeimkehrLogik.mitbringsel_typ("bigCity", JETZT - 3 * Vacation.MS_PER_DAY)
	assert_true(
		tuete.text.contains(HeimkehrLogik.mitbringsel_name(typ, "bigCity")),
		"Tüten-Zeile nennt das deterministische Mitbringsel"
	)
	var hinweis := karte.find_child("HeimkehrGfreeHinweis", true, false)
	assert_ne(hinweis, null, "dezenter GOOBY-FREE-Fenster-Hinweis steht (Uhr injiziert)")
	var knopf := karte.find_child("HeimkehrUmarmen", true, false) as Button
	assert_ne(knopf, null, "Umarmen-Knopf steht")
	knopf.pressed.emit()
	await wait_frames(3)
	assert_eq(
		tree.root.find_child("HeimkehrKarte", true, false), null, "Umarmen schließt die Karte"
	)
	PanelStack.clear()
	room.queue_free()
	await wait_frames(2)


## ---------------------------------------------------------- Strings


func _flach(node: Dictionary, prefix := "", out: Dictionary = {}) -> Dictionary:
	for key: String in node:
		var voll := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		if node[key] is Dictionary:
			_flach(node[key], voll, out)
		else:
			out[voll] = node[key]
	return out


func test_strings_de_en_paritaet_und_varianten() -> void:
	var de: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_DE))
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_EN))
	assert_true(de is Dictionary and en is Dictionary, "Strings-Dateien lesbar")
	var de_keys := _flach(de).keys()
	var en_keys := _flach(en).keys()
	de_keys.sort()
	en_keys.sort()
	assert_eq(de_keys, en_keys, "DE↔EN-Parität der heimkehr-Strings")
	for sprache: Dictionary in [de, en]:
		var typen: Dictionary = sprache["heimkehr"]["mitbringsel"]["typ"]
		for typ: String in HeimkehrLogik.TYPEN:
			assert_ne(str(typen.get(typ, "")), "", "Variante %s benannt" % typ)
		var sprueche: Dictionary = sprache["heimkehr"]["spruch"]
		assert_eq(sprueche.size(), HeimkehrLogik.SPRUCH_ANZAHL, "Spruch-Pool vollständig")
	for key in ["heimkehr.titel", "heimkehr.knopf.umarmen", "heimkehr.gfree.hinweis"]:
		assert_ne(I18nService.t(key), key, "Key fehlt im Loader: %s" % key)
	# Mitbringsel-Namen formatieren den lokalisierten Zielnamen hinein.
	var name := HeimkehrLogik.mitbringsel_name("schneekugel", "beach")
	assert_true(name.contains(I18nService.t("travel.ziel.beach")), "Zielname im Item-Namen")
