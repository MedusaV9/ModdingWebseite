extends TestCase
## REST-4 — Postkartenarchiv + Souvenirregal (EVAL Rang 15, P1 „Bald“):
## pure PostkartenLogic (deterministische Varianten, Junk-Normalisierung,
## Karten-Prozessor inkl. Idempotenz + FIFO-Deckel, Set-Bonus), die
## Vacation.tick-Integration, die 3D-Props (Wand-Karten, Regal-Minis,
## Katalog-`proc`-Hook) und der PostkartenScreen headless. Der P1-Pin:
## der Post-Schalter bietet jetzt einen echten Archiv-Knopf an.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")

const NOW := 1700000000000
const TAG := PostkartenLogic.MS_PER_DAY


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var slices_notified: Array[String] = []

	func _init() -> void:
		s = SaveSchema.default_state(1700000000000)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## --------------------------------------------------- Deterministik (pur)


func test_varianten_deterministisch_und_im_pool() -> void:
	for k in range(1, 12):
		var v1 := PostkartenLogic.variant_of("beach", NOW, k)
		var v2 := PostkartenLogic.variant_of("beach", NOW, k)
		assert_eq(v1, v2, "gleiche Eingaben, gleiche Variante (Tag %d)" % k)
		assert_true(v1 >= 1 and v1 <= PostkartenLogic.VARIANTS, "Variante im Pool (Tag %d)" % k)
	assert_ne(
		PostkartenLogic.trip_seed("beach", NOW),
		PostkartenLogic.trip_seed("space", NOW),
		"verschiedene Ziele, verschiedene Seeds"
	)
	assert_eq(
		PostkartenLogic.text_key({"destId": "beach", "variant": 3}),
		"postkarten.text.beach.3",
		"Textkey zeigt in den Pool"
	)
	for dest_id: String in PostkartenLogic.DEST_IDS:
		for variante in range(1, PostkartenLogic.VARIANTS + 1):
			var key := "postkarten.text.%s.%d" % [dest_id, variante]
			assert_ne(I18nService.t(key), key, "Postkartentext fehlt: %s" % key)


func test_normalize_archiv_klemmt_junk_und_deckel() -> void:
	var roh: Array = [
		{"destId": "beach", "dayIndex": 1, "variant": 2, "atMs": NOW},
		{"destId": "beach", "dayIndex": 1, "variant": 2, "atMs": NOW},
		{"destId": "atlantis", "dayIndex": 1, "variant": 1, "atMs": NOW},
		{"destId": "space", "dayIndex": 0, "variant": 1, "atMs": NOW},
		"quatsch",
		{"destId": "space", "dayIndex": 2, "variant": 99, "atMs": NOW - 1000},
	]
	var sauber := PostkartenLogic.normalize_archive(roh)
	assert_eq(sauber.size(), 2, "Junk + Duplikate fliegen raus")
	assert_eq(str(sauber[0]["destId"]), "space", "chronologisch sortiert")
	var viele: Array = []
	for i in PostkartenLogic.MAX_ARCHIVE + 10:
		viele.append({"destId": "beach", "dayIndex": i + 1, "variant": 1, "atMs": NOW + i})
	var gedeckelt := PostkartenLogic.normalize_archive(viele)
	assert_eq(gedeckelt.size(), PostkartenLogic.MAX_ARCHIVE, "FIFO-Deckel hält")
	assert_eq(int(gedeckelt[0]["dayIndex"]), 11, "die ÄLTESTEN fliegen zuerst")


func test_prozessor_generiert_und_bleibt_idempotent() -> void:
	var v := {
		"destId": "beach",
		"bookedAt": NOW,
		"returnAt": NOW + 5 * TAG,
		"archive": [],
		"lastPostcardDayProcessed": 0,
	}
	var nach_zwei := PostkartenLogic.process_postcards_up_to(v, NOW + 2 * TAG + 5000)
	assert_eq(int(nach_zwei["added"]), 2, "zwei volle Reisetage = zwei Karten")
	var archiv: Array = nach_zwei["archive"]
	assert_eq(int(archiv[0]["atMs"]), NOW + TAG, "Karte trägt ihre feste Ankunftszeit")
	assert_eq(int(archiv[1]["dayIndex"]), 2)
	v["archive"] = archiv
	v["lastPostcardDayProcessed"] = nach_zwei["lastPostcardDayProcessed"]
	var nochmal := PostkartenLogic.process_postcards_up_to(v, NOW + 2 * TAG + 5000)
	assert_eq(int(nochmal["added"]), 0, "idempotent: nichts doppelt")
	var nach_ende := PostkartenLogic.process_postcards_up_to(v, NOW + 99 * TAG)
	assert_eq((nach_ende["archive"] as Array).size(), 4, "5-Tage-Reise = maximal 4 Karten")
	var kaputt := PostkartenLogic.process_postcards_up_to({"destId": "nirgendwo"}, NOW)
	assert_eq(int(kaputt["added"]), 0, "unbekanntes Ziel erzeugt nichts")


func test_vacation_tick_fuellt_das_archiv() -> void:
	var state := SaveSchema.default_state(NOW)
	var v: Dictionary = state["vacation"]
	v["phase"] = "away"
	v["destId"] = "harbor"
	v["bookedAt"] = NOW
	v["returnAt"] = NOW + 4 * TAG
	var result := Vacation.tick(state, NOW + 3 * TAG + 60000)
	var changes: Dictionary = result["changes"]
	assert_false(changes.is_empty(), "tick meldet Änderungen")
	assert_eq((changes["archive"] as Array).size(), 3, "drei Reisetage, drei Karten")
	assert_eq(int(changes["lastPostcardDayProcessed"]), 3)
	state["vacation"] = changes
	var still := Vacation.tick(state, NOW + 3 * TAG + 60000)
	assert_true(still["changes"] == null, "gleiche Uhr, keine neuen Änderungen")


## --------------------------------------------------- Set-Bonus (pur)


func test_set_bonus_stufen_und_claim() -> void:
	var state := SaveSchema.default_state(NOW)
	var v: Dictionary = state["vacation"]
	v["visited"] = {"beach": true, "space": true, "bakery": true}
	var stufen := PostkartenLogic.set_stufen(state)
	assert_eq(stufen.size(), 3)
	assert_true(bool(stufen[0]["erreicht"]), "3 Ziele: Stufe 3 erreicht")
	assert_false(bool(stufen[1]["erreicht"]), "Stufe 6 noch nicht")
	assert_eq(PostkartenLogic.claim_set_bonus(state, 6, NOW), 0, "unerreichte Stufe zahlt 0")
	assert_eq(PostkartenLogic.claim_set_bonus(state, 3, NOW), 150, "Stufe 3 zahlt 150")
	assert_eq(PostkartenLogic.claim_set_bonus(state, 3, NOW), 0, "nur EINMAL je Stufe")
	assert_eq(PostkartenLogic.besucht_anzahl(state), 3)
	assert_eq(PostkartenLogic.souvenirs_von(state), ["beach", "space", "bakery"], "Katalog-Ordnung")


## --------------------------------------------------- 3D-Props + Katalog


func test_props_wand_und_regal() -> void:
	var archiv: Array = []
	for i in 8:
		archiv.append({"destId": "beach", "dayIndex": i + 1, "variant": 1, "atMs": NOW + i})
	var wand := PostkartenProps.postkartenwand_mit(archiv)
	var karten := 0
	for kind in wand.get_children():
		if str(kind.name).begins_with("Karte_"):
			karten += 1
	assert_eq(karten, PostkartenProps.WAND_MAX_KARTEN, "Wand deckelt auf 6 Karten")
	wand.free()
	var leer := PostkartenProps.postkartenwand_mit([])
	assert_true(leer.get_child_count() >= 5, "leere Wand hat Brett + Rahmen")
	leer.free()
	var regal := PostkartenProps.souvenirregal_mit(["beach", "space"])
	assert_true(regal.find_child("Souvenir_beach", true, false) != null, "Muschel steht")
	assert_true(regal.find_child("Souvenir_space", true, false) != null, "Mondstein steht")
	assert_true(regal.find_child("Souvenir_bakery", true, false) == null, "unbesucht bleibt leer")
	regal.free()


func test_katalog_kennt_wand_und_regal() -> void:
	FurnitureCatalog.reset_cache()
	for id: String in ["postkartenWand", "souvenirRegal"]:
		var def := FurnitureCatalog.def(id)
		assert_false(def.is_empty(), "Katalog-Eintrag fehlt: %s" % id)
		assert_eq(int(def["layer"]), GridData.Layer.WALL, "%s ist ein WALL-Item" % id)
		var node := FurnitureNode.create_wall(def, "N", 1, Vector2i(8, 8), "uid_%s" % id)
		assert_true(node != null, "proc-Modell baut: %s" % id)
		if node != null:
			node.free()


## --------------------------------------------------- Screen + P1-Pin


func test_postkarten_screen_archiv_souvenirs_claim() -> void:
	var gs := FakeGameState.new()
	gs.s["economy"]["coins"] = 10
	var v: Dictionary = gs.s["vacation"]
	v["archive"] = [
		{"destId": "beach", "dayIndex": 1, "variant": 2, "atMs": NOW},
		{"destId": "space", "dayIndex": 2, "variant": 4, "atMs": NOW + TAG},
	]
	v["visited"] = {"beach": true, "space": true, "harbor": true}
	var screen: PostkartenScreen = load("res://scripts/ui/postkarten/postkarten_screen.gd").new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	assert_eq(screen.karten_im_archiv(), 2, "beide Karten im Archiv")
	var karte := screen.find_child("Karte_space_2", true, false)
	assert_true(karte != null, "Weltraum-Karte wird gezeigt")
	var text: Label = karte.find_child("Text", true, false)
	assert_eq(
		text.text,
		I18nService.t("postkarten.text.space.4"),
		"handgeschriebene Zeile aus dem Varianten-Pool"
	)
	var chips := screen.souvenir_chips()
	assert_true(chips.has("Souvenir_beach"), "besuchtes Ziel steht im Regal")
	assert_true(chips.has("Offen_toyRoom"), "unbesuchtes Ziel bleibt offen")
	assert_eq(chips.size(), PostkartenLogic.DEST_IDS.size(), "alle 9 Slots sichtbar")
	assert_true(screen.find_child("Claim_3", true, false) != null, "Stufe 3 bietet den Claim an")
	assert_eq(screen.claim_jetzt(3), 150, "Claim zahlt 150 Münzen")
	assert_eq(int(gs.get_value("economy.coins", 0)), 160, "Münzen landen im Konto")
	assert_eq(screen.claim_jetzt(3), 0, "zweiter Claim zahlt nichts")
	assert_true(screen.find_child("Claim_3", true, false) == null, "Claim-Knopf verschwindet")
	screen.queue_free()
	await wait_frames(1)


func test_post_sheet_bietet_archiv_statt_bald() -> void:
	var gs := FakeGameState.new()
	var v: Dictionary = gs.s["vacation"]
	v["postcards"] = 2
	var sheet := PostSheet.new()
	sheet.gs = gs
	tree.root.add_child(sheet)
	await wait_frames(1)
	var knopf := sheet.find_child("ArchivAnsehen", true, false)
	assert_true(knopf != null, "P1-Fix: der Archiv-Klick führt ins echte Archiv")
	sheet.queue_free()
	await wait_frames(1)
