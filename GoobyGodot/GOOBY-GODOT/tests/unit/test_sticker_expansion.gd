extends TestCase
## BACKLOG-REST — Sticker-Ausbau: 5 neue Sets (33 Sticker) + 3 Ereignis-
## Sticker, Asset-Budget <= 96 KiB je Content-Pack-Datei, die neuen
## special-Conds (Ranch/Stadt/Jahreszeiten) pure gegen den Save-State,
## Ereignis-Hook-Abdeckung und der Seiten-Fortschritt (page_progress).

const STICKERS_JSON := "res://content/stickers/data/stickers.json"
const PAGES_JSON := "res://content/stickers/data/sticker_pages.json"
const EVENTS_JSON := "res://content/events/data/events.json"
const PACK_ASSET_PREFIX := "res://content/stickers/assets/"
const BUDGET_BYTES := 96 * 1024

const NEW_SETS := {
	"ranch": 7,
	"multiplayer": 7,
	"stadtnacht": 6,
	"kueche": 7,
	"jahreszeiten": 6,
	"ereignisse": 4,
}
## Hooks, die Code/Events feuern — jeder braucht einen Katalog-Sticker.
const FIRED_HOOKS := [
	"robo_jagd",
	"wurm_freund",
	"karton_gooby",
	"gewitter_angst",
	"mehl_unfall",
	"nutella_nacht",
	"chess_win",
	"chess_matt",
	"chess_online",
	"chess_rematch",
]


func _load_items(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, path + " parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func test_neue_sets_vollstaendig_und_valide() -> void:
	var items := _load_items(STICKERS_JSON)
	var pages := _load_items(PAGES_JSON)
	assert_eq(items.size(), 144, "141 Bestand + 2 GvZ-Meilensteine + 1 Schüttel-Geheimsticker")
	var by_set := {}
	for def: Dictionary in items:
		var set_id := str(def.get("set", ""))
		by_set[set_id] = int(by_set.get(set_id, 0)) + 1
	for set_id: String in NEW_SETS:
		assert_eq(by_set.get(set_id, 0), NEW_SETS[set_id], "Set %s komplett" % set_id)
	assert_eq(StickerCatalog.validate(items, pages), [], "validate() ohne Befund")
	for page_id in ["ranch", "multiplayer", "stadtnacht", "kueche", "jahreszeiten"]:
		var found := false
		for page: Dictionary in pages:
			if str(page.get("id", "")) == page_id:
				found = true
		assert_true(found, "neue Seite %s existiert" % page_id)


func test_budget_je_pack_asset() -> void:
	var items := _load_items(STICKERS_JSON)
	var checked := 0
	for def: Dictionary in items:
		var image := str(def.get("image", ""))
		if not image.begins_with(PACK_ASSET_PREFIX):
			continue
		checked += 1
		assert_true(FileAccess.file_exists(image), "%s: Asset fehlt" % def.get("id"))
		var file := FileAccess.open(image, FileAccess.READ)
		assert_true(
			file != null and file.get_length() <= BUDGET_BYTES,
			"%s: %d B > 96 KiB" % [def.get("id"), file.get_length() if file else -1]
		)
	assert_true(checked >= 38, "alle 36 neuen + 2 Basis-Assets geprüft (%d)" % checked)


func test_ranch_specials() -> void:
	var state := {
		"ranch":
		{
			"gekauft": true,
			"hoftiere": [{"id": "kuh1"}, {"id": "schaf1"}, {"id": "huhn1"}],
			"ausbau": {"stall": 2, "koppel": 2, "reitplatz": 1},
			"tiere":
			{
				"pferde":
				{
					"p1": {"bindung": 44.0},
					"p2": {"bindung": 12.0},
				}
			},
			"wirtschaft": {"lager": {"heu": 8, "apfel": 4}},
		},
	}
	assert_true(
		StickerUnlocks.cond_met({"type": "special", "key": "ranchOwned", "count": 1}, state)
	)
	assert_true(
		StickerUnlocks.cond_met({"type": "special", "key": "horsesOwned", "count": 2}, state)
	)
	assert_false(
		StickerUnlocks.cond_met({"type": "special", "key": "horsesOwned", "count": 3}, state)
	)
	assert_true(
		StickerUnlocks.cond_met({"type": "special", "key": "horseBond", "count": 40}, state)
	)
	assert_true(
		StickerUnlocks.cond_met({"type": "special", "key": "ranchAusbau", "count": 5}, state)
	)
	assert_false(
		StickerUnlocks.cond_met({"type": "special", "key": "ranchAusbau", "count": 6}, state)
	)
	assert_true(
		StickerUnlocks.cond_met({"type": "special", "key": "ranchLager", "count": 12}, state)
	)
	assert_true(StickerUnlocks.cond_met({"type": "special", "key": "hoftiere", "count": 3}, state))
	# Leerer Save: nichts erfüllt, nichts crasht.
	assert_false(StickerUnlocks.cond_met({"type": "special", "key": "ranchOwned", "count": 1}, {}))
	assert_false(StickerUnlocks.cond_met({"type": "special", "key": "horseBond", "count": 1}, {}))


func test_stadt_und_saison_specials() -> void:
	var state := {
		"city":
		{"besucht": {"laden": true, "post": true, "doktor": true, "kino": true, "park": true}},
		"minigames": {"legacy": {"lastPlayDay": {"memoryMatch": "2026-07-26"}}},
		"daily": {"lastClaimDay": "2026-01-05"},
	}
	assert_true(
		StickerUnlocks.cond_met({"type": "special", "key": "cityVisits", "count": 5}, state)
	)
	assert_false(
		StickerUnlocks.cond_met({"type": "special", "key": "cityVisits", "count": 6}, state)
	)
	var sommer := {"type": "special", "key": "seasonPlay", "count": 1, "sub": {"season": "sommer"}}
	var winter := {"type": "special", "key": "seasonPlay", "count": 1, "sub": {"season": "winter"}}
	var herbst := {"type": "special", "key": "seasonPlay", "count": 1, "sub": {"season": "herbst"}}
	assert_true(StickerUnlocks.cond_met(sommer, state), "Minigame-Tag im Juli → Sommer")
	assert_true(StickerUnlocks.cond_met(winter, state), "Daily-Tag im Januar → Winter")
	assert_false(StickerUnlocks.cond_met(herbst, state), "kein Herbst-Tag im Save")
	# Saison-Grenzen + feindliche Strings crashen nicht.
	assert_eq(StickerUnlocks._season_of_day("2026-03-01"), "fruehling")
	assert_eq(StickerUnlocks._season_of_day("2026-05-31"), "fruehling")
	assert_eq(StickerUnlocks._season_of_day("2026-06-01"), "sommer")
	assert_eq(StickerUnlocks._season_of_day("2026-09-15"), "herbst")
	assert_eq(StickerUnlocks._season_of_day("2026-12-24"), "winter")
	assert_eq(StickerUnlocks._season_of_day("2026-02-02"), "winter")
	assert_eq(StickerUnlocks._season_of_day("quatsch"), "")
	assert_false(
		StickerUnlocks.cond_met(sommer, {"daily": {"lastClaimDay": 12}}), "Nicht-String-Tag"
	)


func test_jahresring_zaehlt_saison_sticker() -> void:
	var cond := {"type": "special", "key": "seasonsCollected", "count": 4}
	var state := {
		"stickers":
		{"unlocked": {"jz_fruehling": 1, "jz_sommer": 1, "jz_herbst": 1, "jz_winter": 1}}
	}
	assert_true(StickerUnlocks.cond_met(cond, state), "alle 4 Saisons → Jahresring")
	(state["stickers"]["unlocked"] as Dictionary).erase("jz_winter")
	assert_false(StickerUnlocks.cond_met(cond, state), "3 von 4 reichen nicht")


func test_jeder_gefeuerte_hook_hat_einen_sticker() -> void:
	var items := _load_items(STICKERS_JSON)
	var event_keys := {}
	for def: Dictionary in items:
		var cond: Dictionary = def.get("cond", {})
		if str(cond.get("type", "")) == "event":
			event_keys[str(cond.get("key", ""))] = true
	for hook: String in FIRED_HOOKS:
		assert_true(event_keys.has(hook), "Hook %s hat einen Katalog-Sticker" % hook)
	# Und umgekehrt: alle sticker_hooks im Events-Pack sind abgedeckt.
	var events := _load_items(EVENTS_JSON)
	for def: Dictionary in events:
		var hook := str(def.get("sticker_hook", ""))
		if not hook.is_empty():
			assert_true(event_keys.has(hook), "Event-Hook %s ohne Sticker" % hook)


func test_page_progress() -> void:
	var catalog := [
		{"id": "a", "page": "p1"},
		{"id": "b", "page": "p1"},
		{"id": "geheim", "page": "p1", "secret": true},
		{"id": "c", "page": "p2"},
	]
	var state := {"stickers": {"unlocked": {"a": 1}}}
	var progress := StickerUnlocks.page_progress(state, catalog, "p1")
	assert_eq(progress["unlocked"], 1)
	assert_eq(progress["total"], 2, "Geheim-Sticker zählt gesperrt nicht mit")
	state["stickers"]["unlocked"]["geheim"] = 1
	progress = StickerUnlocks.page_progress(state, catalog, "p1")
	assert_eq(progress["total"], 3, "freigeschalteter Geheim-Sticker zählt")
	assert_eq(progress["unlocked"], 2)
	assert_eq(StickerUnlocks.page_progress(state, catalog, "leer")["total"], 0)
