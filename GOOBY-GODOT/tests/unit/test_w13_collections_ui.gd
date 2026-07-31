extends TestCase
## W13/SAMMLUNG — Sammlungssets sichtbar machen (Web-Parität zu
## GOOBY/src/systems/collections.js + ui/albumScreen.js):
## Logik pur (Set-Definitionen/Belohnungen Web-verbatim, Vollständigkeit,
## Claim einmalig + exakte Buchung, kaputte Slices normalisiert) und
## UI-Smoke (Album zeigt den Sammlungs-Chip, 4 Set-Karten, Slot- und
## Claim-Knopf-Zustände, Claim über den Knopf).

const GameStateScript := preload("res://scripts/state/game_state.gd")

## Injizierte Test-Zeit (Zeit kommt IMMER als Parameter — kein Uhr-Zugriff).
const NOW_MS := 1_234_567

var _dir_seq := 0

# ── Logik pur ─────────────────────────────────────────────────────────────────


func test_set_definitionen_web_verbatim() -> void:
	var sets := CollectionsLogic.sets()
	assert_eq(sets.size(), 4, "4 Sammlungssets (§C6)")
	var expected := {
		"fish": [8, 200, "proc:goldfishBowl"],
		"veggies": [8, 150, "proc:goldenWateringCan"],
		"landmarks": [6, 150, "proc:toyCity"],
		"treats": [10, 150, "proc:candyJar"],
	}
	var order: Array[String] = []
	for def: Dictionary in sets:
		order.append(str(def["id"]))
	assert_eq(order, ["fish", "veggies", "landmarks", "treats"], "§C6-Reihenfolge")
	for set_id: String in expected:
		var want: Array = expected[set_id]
		var def := CollectionsLogic.set_def(set_id)
		assert_eq((def["entries"] as Array).size(), int(want[0]), "%s-Setgröße" % set_id)
		var reward := CollectionsLogic.reward_of(set_id)
		assert_eq(int(reward["coins"]), int(want[1]), "%s-Münzen web-verbatim" % set_id)
		assert_eq(str(reward["furniture"]), str(want[2]), "%s-Deko web-verbatim" % set_id)
		assert_eq(int(reward["xp"]), 50, "%s: +50 XP (§C5.2)" % set_id)


func test_normalize_heilt_kaputte_slices() -> void:
	var healed := CollectionsLogic.normalize_slice(null)
	assert_eq(healed, {"entries": {}, "claimedSets": {}}, "null → leerer Slice")
	healed = CollectionsLogic.normalize_slice({"entries": [1, 2], "claimedSets": "kaputt"})
	assert_eq(healed, {"entries": {}, "claimedSets": {}}, "falsche Typen → geheilt")
	healed = (
		CollectionsLogic
		. normalize_slice(
			{
				"entries": {"fish.pinkKoi": 2, "fish.nightEel": 0, "": 3, "fish.blueDace": "x"},
				"claimedSets": {"fish": true, "veggies": 99, "": 1},
			}
		)
	)
	assert_eq(healed["entries"], {"fish.pinkKoi": 2}, "nur Counts >= 1 mit echtem Key")
	assert_true(healed["claimedSets"].has("fish"), "Claim-Key bleibt (nie ent-claimen)")
	assert_eq(int(healed["claimedSets"]["veggies"]), 99, "Zeitstempel bleibt erhalten")
	assert_false(healed["claimedSets"].has(""), "leerer Claim-Key fliegt raus")


func test_vollstaendigkeit_und_fortschritt() -> void:
	var c := {"entries": {}, "claimedSets": {}}
	assert_false(CollectionsLogic.is_set_complete(c, "landmarks"), "leer ≠ komplett")
	assert_false(CollectionsLogic.is_set_complete(c, "gibtsnicht"), "unbekanntes Set nie komplett")
	for entry_id: String in ["shop", "vetClinic", "fountain", "skyTower", "parkGazebo"]:
		c["entries"][CollectionsLogic.entry_key("landmarks", entry_id)] = 1
	var p := CollectionsLogic.set_progress(c, "landmarks")
	assert_eq(p, {"have": 5, "total": 6}, "5/6 gesammelt")
	assert_false(CollectionsLogic.is_set_complete(c, "landmarks"), "5/6 ≠ komplett")
	c["entries"]["landmarks.windmillCafe"] = 3
	assert_true(CollectionsLogic.is_set_complete(c, "landmarks"), "6/6 = komplett")
	var total := CollectionsLogic.total_progress(c)
	assert_eq(total, {"have": 6, "total": 32}, "Gesamt 6/32")
	assert_eq(CollectionsLogic.count_of(c, "landmarks", "windmillCafe"), 3, "×n-Zähler")


func test_award_pur_web_semantik() -> void:
	var c := {"entries": {}, "claimedSets": {"fish": 123}}
	var first := CollectionsLogic.award(c, "fish", "pinkKoi")
	assert_true(bool(first["first"]), "erstes Exemplar → first=true (Toast-Signal)")
	assert_eq(CollectionsLogic.count_of(first["c"], "fish", "pinkKoi"), 1, "Zähler = 1")
	assert_eq(int(first["c"]["claimedSets"]["fish"]), 123, "claimedSets bleibt erhalten")
	assert_eq(c["entries"].size(), 0, "pure: Eingabe-Slice unverändert")
	var again := CollectionsLogic.award(first["c"], "fish", "pinkKoi", 2)
	assert_false(bool(again["first"]), "Wiederholung → first=false")
	assert_eq(CollectionsLogic.count_of(again["c"], "fish", "pinkKoi"), 3, "n=2 addiert auf 3")
	var noop := CollectionsLogic.award(c, "fish", "pinkKoi", 0)
	assert_false(bool(noop["first"]), "n<=0 → first=false")
	assert_true(noop["c"] == c, "n<=0 → selbe Slice-Referenz (Web-verbatim)")
	var leer := CollectionsLogic.award(c, "", "pinkKoi")
	assert_false(bool(leer["first"]), "leere setId → abgelehnt")


func test_claim_pur_einmalig() -> void:
	var c := _full_set_slice("fish")
	var denied := CollectionsLogic.claim_set({"entries": {}, "claimedSets": {}}, "fish", NOW_MS)
	assert_false(bool(denied["ok"]), "unvollständig → kein Claim")
	var res := CollectionsLogic.claim_set(c, "fish", NOW_MS)
	assert_true(bool(res["ok"]), "volles Set → Claim ok")
	assert_eq(int(res["c"]["claimedSets"]["fish"]), NOW_MS, "Zeitstempel = injizierte Zeit")
	assert_eq(int(res["reward"]["coins"]), 200, "Fisch-Belohnung 200 Münzen")
	assert_eq(c.get("claimedSets", {}).size(), 0, "pure: Eingabe-Slice unverändert")
	var again := CollectionsLogic.claim_set(res["c"], "fish", NOW_MS + 5)
	assert_false(bool(again["ok"]), "zweiter Claim verweigert")


func test_apply_claim_bucht_web_belohnung() -> void:
	var gs := _fresh_gs()
	_seed_full_set(gs, "fish")
	var coins_before := int(gs.get_value("economy.coins", 0))
	var reward := CollectionsLogic.apply_claim(gs, "fish", NOW_MS, "2026-07-31")
	assert_eq(int(reward.get("coins", 0)), 200, "Belohnung zurückgereicht")
	assert_eq(int(gs.get_value("economy.coins", 0)), coins_before + 200, "genau +200 Münzen (Web)")
	assert_eq(int(gs.get_value("progression.xp", 0)), 50, "+50 XP (§C5.2)")
	assert_eq(int(gs.get_value("collections.claimedSets.fish", -1)), NOW_MS, "Claim persistiert")
	var storage: Array = gs.get_value("home.storage", [])
	assert_eq(StorageLogic.count_of(storage, "proc:goldfishBowl"), 1, "Deko liegt im Hauslager")
	# Idempotenz: zweiter Claim zahlt NICHTS doppelt.
	var second := CollectionsLogic.apply_claim(gs, "fish", NOW_MS + 99, "2026-07-31")
	assert_true(second.is_empty(), "zweiter Claim liefert {}")
	assert_eq(int(gs.get_value("economy.coins", 0)), coins_before + 200, "keine Doppel-Münzen")
	assert_eq(
		StorageLogic.count_of(gs.get_value("home.storage", []), "proc:goldfishBowl"),
		1,
		"keine Doppel-Deko"
	)
	assert_eq(
		int(gs.get_value("collections.claimedSets.fish", -1)), NOW_MS, "Zeitstempel unverändert"
	)
	gs.queue_free()
	await wait_frames(1)


func test_apply_claim_verweigert_unvollstaendig() -> void:
	var gs := _fresh_gs()
	gs.update(
		func(state: Dictionary) -> void: state["collections"]["entries"]["veggies.carrot"] = 1
	)
	var coins_before := int(gs.get_value("economy.coins", 0))
	var reward := CollectionsLogic.apply_claim(gs, "veggies", NOW_MS)
	assert_true(reward.is_empty(), "1/8 → kein Claim")
	assert_eq(int(gs.get_value("economy.coins", 0)), coins_before, "keine Münzen gebucht")
	var claimed: Dictionary = gs.get_value("collections.claimedSets", {})
	assert_false(claimed.has("veggies"), "kein Claim-Eintrag")
	gs.queue_free()
	await wait_frames(1)


# ── UI-Smoke ──────────────────────────────────────────────────────────────────


func test_album_zeigt_sammlungs_bereich() -> void:
	var ctx := await _open_album()
	var album: AlbumScreen = ctx["album"]
	var chip := album._rail_box.get_node_or_null("PageChip_%s" % AlbumScreen.COLLECTIONS_PAGE)
	assert_true(chip is Button, "Sammlungs-Chip hängt in der Rail")
	assert_true((chip as Button).text.contains("0/32"), "Chip zeigt 0/32: " + (chip as Button).text)
	album.show_page(AlbumScreen.COLLECTIONS_PAGE)
	await wait_frames(2)
	var view: CollectionsView = album._collections_view
	assert_true(view.visible, "Sammlungs-View sichtbar")
	assert_false(album._grid_scroll.visible, "Sticker-Grid versteckt")
	var cards := 0
	for def: Dictionary in CollectionsLogic.sets():
		var card := view.find_child("SetCard_%s" % str(def["id"]), true, false)
		if card != null:
			cards += 1
			var grid := card.find_child("EntryGrid", true, false)
			assert_eq(
				grid.get_child_count(),
				(def["entries"] as Array).size(),
				"%s: ein Slot je Eintrag" % def["id"]
			)
			var claim := card.find_child("ClaimButton", true, false) as Button
			assert_true(claim.disabled, "%s: Claim gesperrt ohne volles Set" % def["id"])
	assert_eq(cards, 4, "4 Set-Karten")
	var slot := view.find_child("Slot_sunnyCarp", true, false)
	assert_true(slot != null, "Fisch-Slot existiert")
	assert_true(
		slot.find_child("MysteryMark", true, false) != null, "fehlender Eintrag = ?-Silhouette"
	)
	# Zurück zur Sticker-Seite: Grid wieder an, View wieder weg.
	album.show_page("testset")
	await wait_frames(1)
	assert_true(album._grid_scroll.visible, "Grid zurück")
	assert_false(view.visible, "Sammlungs-View versteckt")
	await _close_album(ctx)


func test_claim_knopf_im_album() -> void:
	var ctx := await _open_album()
	var album: AlbumScreen = ctx["album"]
	var gs: Node = ctx["gs"]
	_seed_full_set(gs, "fish")
	album.show_page(AlbumScreen.COLLECTIONS_PAGE)
	await wait_frames(2)
	var view: CollectionsView = album._collections_view
	var card := view.find_child("SetCard_fish", true, false)
	var slot := card.find_child("Slot_sunnyCarp", true, false)
	assert_true(slot.find_child("MysteryMark", true, false) == null, "gesammelter Eintrag ohne ?")
	var claim := card.find_child("ClaimButton", true, false) as Button
	assert_false(claim.disabled, "volles Set → Claim-Knopf aktiv")
	assert_eq(claim.text, I18nService.t("collections.claim"), "Knopf-Text: Belohnung abholen")
	var coins_before := int(gs.get_value("economy.coins", 0))
	claim.pressed.emit()
	await wait_frames(2)
	assert_eq(int(gs.get_value("economy.coins", 0)), coins_before + 200, "Klick → +200 Münzen")
	card = view.find_child("SetCard_fish", true, false)
	claim = card.find_child("ClaimButton", true, false) as Button
	assert_true(claim.disabled, "nach Claim gesperrt")
	assert_eq(claim.text, I18nService.t("collections.claimed"), "Knopf zeigt Abgeholt!")
	var chip := album._rail_box.get_node("PageChip_%s" % AlbumScreen.COLLECTIONS_PAGE) as Button
	assert_true(chip.text.contains("8/32"), "Chip zählt 8/32: " + chip.text)
	await _close_album(ctx)


# ── Aufbau/Helfer ─────────────────────────────────────────────────────────────


func _full_set_slice(set_id: String) -> Dictionary:
	var c := {"entries": {}, "claimedSets": {}}
	for entry_id: String in CollectionsLogic.set_def(set_id).get("entries", []):
		c["entries"][CollectionsLogic.entry_key(set_id, entry_id)] = 1
	return c


func _seed_full_set(gs: Node, set_id: String) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var entries: Dictionary = state["collections"]["entries"]
			for entry_id: String in CollectionsLogic.set_def(set_id).get("entries", []):
				entries[CollectionsLogic.entry_key(set_id, entry_id)] = 1
	)
	gs.notify_slice_changed("collections")


func _fresh_gs() -> Node:
	_dir_seq += 1
	var dir := "user://w13_tests/gs_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	return gs


func _open_album() -> Dictionary:
	var gs := _fresh_gs()
	var album := AlbumScreen.new()
	album.auto_navigate = false
	album.gs_override = gs
	album.catalog_override = _mini_catalog()
	album.pages_override = [
		{"id": "testset", "title_de": "Testset", "icon": "star", "tint": "#CDE6BE", "order": 0}
	]
	tree.root.add_child(album)
	await wait_frames(2)
	return {"album": album, "gs": gs}


func _close_album(ctx: Dictionary) -> void:
	(ctx["album"] as Node).queue_free()
	(ctx["gs"] as Node).queue_free()
	await wait_frames(2)


## Mini-Sticker-Katalog wie test_sticker_album_ui — hält den Album-Aufbau
## klein und unabhängig vom echten Content-Pack.
func _mini_catalog() -> Array:
	return [
		{
			"id": "st_a",
			"name_de": "Alpha-Sticker",
			"flavor_de": "A.",
			"hint_de": "Zähler A.",
			"set": "testset",
			"page": "testset",
			"rarity": "haeufig",
			"image": "res://content/stickers/assets/ranch_neuer_hof.png",
			"cond": {"type": "counter", "key": "alpha_zaehler", "count": 1},
		},
	]
