extends TestCase
## W13B/STICKER — GvZ-Meilenstein-Sticker + Rarity-Effekte (H §3.3/3.4):
## (a) Katalog: die 2 neuen Meilenstein-Sticker (Zaunheld/Nutella-Kommandant)
##     sitzen valide im GvZ-Set, ihre Assets existieren, und sie sind über
##     die Welle-A-Hooks gvz_l5/gvz_l10 freischaltbar — inklusive echter
##     RewardHub-Simulation (fire_event_hook → note_action → Unlock+Feier).
## (b) Rarity→Feier-Mapping pur (normal/Silber/Gold), Gold-Jingle aus der
##     Bestands-SFX-Palette, Gold-Glitzer NUR bei Gold (episch), Reduced
##     Motion friert den Shimmer über motion_scale = 0 ein.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const STICKERS_JSON := "res://content/stickers/data/stickers.json"
const NOW_MS := 1768478400000

var _seq := 0


func _items() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STICKERS_JSON))
	assert_true(parsed is Dictionary, "stickers.json parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w13b_sticker/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


# ── (a) Katalog: neue Meilenstein-Sticker ────────────────────────────────────


func test_meilenstein_sticker_im_katalog_und_valide() -> void:
	var items := _items()
	var zaunheld := StickerCatalog.by_id(items, "gvz_zaunheld")
	var kommandant := StickerCatalog.by_id(items, "gvz_kommandant")
	assert_false(zaunheld.is_empty(), "gvz_zaunheld im Katalog")
	assert_false(kommandant.is_empty(), "gvz_kommandant im Katalog")
	assert_eq(str(zaunheld.get("set")), "gvz", "Zaunheld im GvZ-Set")
	assert_eq(str(kommandant.get("page")), "gvz", "Kommandant auf der GvZ-Seite")
	assert_eq(str(zaunheld.get("rarity")), "selten", "L5 = Silber")
	assert_eq(str(kommandant.get("rarity")), "episch", "L10 = Gold")
	# cond = exakt die Welle-A-Hooks (StickerUnlocks event-Vokabular).
	assert_eq(zaunheld.get("cond"), {"type": "event", "key": "gvz_l5"}, "L5-Hook-Cond")
	assert_eq(kommandant.get("cond"), {"type": "event", "key": "gvz_l10"}, "L10-Hook-Cond")


func test_katalog_integritaet_jeder_sticker_hat_asset() -> void:
	# Verschärfte Fassung des Bestands-Checks (test_album_catalog):
	# JEDER der 144 Sticker — inkl. der 2 neuen + Geheim-Sticker — hat ein existierendes
	# Asset und eine valide Rarity.
	var items := _items()
	assert_eq(items.size(), 144, "141 Bestand + 2 Meilensteine + 1 Schüttel-Geheimsticker")
	for def: Dictionary in items:
		var image := str(def.get("image", ""))
		assert_true(FileAccess.file_exists(image), "%s: Asset fehlt (%s)" % [def.get("id"), image])
		assert_true(
			StickerCatalog.RARITIES.has(str(def.get("rarity", ""))),
			"%s: Rarity bekannt" % def.get("id")
		)


func test_hooks_schalten_die_meilenstein_sticker_frei() -> void:
	# Pur: cond_met gegen den Save-State, den fire_event_hook real erzeugt.
	var items := _items()
	var state := {"stickers": {"unlocked": {}, "hooks": {}}}
	var l5: Dictionary = StickerCatalog.by_id(items, "gvz_zaunheld").get("cond")
	var l10: Dictionary = StickerCatalog.by_id(items, "gvz_kommandant").get("cond")
	assert_false(StickerUnlocks.cond_met(l5, state), "ohne Hook gesperrt")
	assert_false(StickerUnlocks.cond_met(l10, state), "ohne Hook gesperrt")
	state["stickers"]["hooks"]["gvz_l5"] = true
	assert_true(StickerUnlocks.cond_met(l5, state), "gvz_l5 schaltet Zaunheld frei")
	assert_false(StickerUnlocks.cond_met(l10, state), "L10 bleibt gesperrt")
	state["stickers"]["hooks"]["gvz_l10"] = true
	assert_true(StickerUnlocks.cond_met(l10, state), "gvz_l10 schaltet Kommandant frei")


func test_rewardhub_simulation_feiert_meilensteine() -> void:
	# Der echte Pfad aus gvz_game._book_sticker_progress: fire_event_hook →
	# note_action → StickerUnlocks-Auswertung → RewardHub-Feier.
	var gs := _fresh_gs()
	var host := Node.new()
	tree.root.add_child(host)
	var hub := RewardHub.attach_to(host, gs)
	await wait_frames(1)
	var celebrated: Array = []
	hub.sticker_celebrated.connect(
		func(def: Dictionary) -> void: celebrated.append(str(def.get("id", "")))
	)
	StickerUnlocks.fire_event_hook(gs, "gvz_l5")
	RewardHub.note_action(gs)
	assert_true(
		gs.get_value("stickers.unlocked", {}).has("gvz_zaunheld"),
		"gvz_l5-Hook schaltet Zaunheld sofort frei"
	)
	StickerUnlocks.fire_event_hook(gs, "gvz_l10")
	RewardHub.note_action(gs)
	assert_true(
		gs.get_value("stickers.unlocked", {}).has("gvz_kommandant"),
		"gvz_l10-Hook schaltet Kommandant sofort frei"
	)
	var gefeiert := await wait_until(
		func() -> bool: return celebrated.has("gvz_zaunheld") and celebrated.has("gvz_kommandant"),
		12000
	)
	assert_true(gefeiert, "beide Meilensteine gefeiert (Queue): %s" % [celebrated])
	host.queue_free()
	await wait_frames(1)
	gs.free()


# ── (b) Rarity → Feier (pur) ─────────────────────────────────────────────────


func test_rarity_feier_mapping_pur() -> void:
	var normal := StickerCard.celebration_for("haeufig")
	assert_eq(str(normal["tier"]), "normal")
	assert_eq(str(normal["sfx"]), "ui_sticker", "normal: bisheriger Pluck")
	assert_false(bool(normal["konfetti"]), "normal: kein Konfetti")
	assert_false(bool(normal["funkeln"]), "normal: kein Funkeln")
	assert_eq(str(normal["toast_key"]), "album.unlock_toast")

	var silber := StickerCard.celebration_for("selten")
	assert_eq(str(silber["tier"]), "silber")
	assert_true(bool(silber["funkeln"]), "Silber: kleines Funkeln")
	assert_false(bool(silber["konfetti"]), "Silber: kein Konfetti")
	assert_eq(str(silber["sfx"]), "ui_sticker")

	var gold := StickerCard.celebration_for("episch")
	assert_eq(str(gold["tier"]), "gold")
	assert_true(bool(gold["konfetti"]), "Gold: Konfetti")
	assert_eq(str(gold["sfx"]), "mg_win", "Gold: eigener Jingle aus der Palette")
	assert_eq(str(gold["toast_key"]), "album.unlock_toast_episch")

	assert_eq(str(StickerCard.celebration_for("geheim")["tier"]), "gold", "geheim feiert wie Gold")
	assert_eq(str(StickerCard.celebration_for("quatsch")["tier"]), "normal", "unbekannt → normal")


func test_gold_jingle_und_toast_keys_existieren() -> void:
	for tier_rarity in ["haeufig", "selten", "episch"]:
		var feier := StickerCard.celebration_for(tier_rarity)
		assert_false(SfxMap.entry(str(feier["sfx"])).is_empty(), "%s: SFX gemappt" % tier_rarity)
		assert_true(FileAccess.file_exists(SfxMap.path(str(feier["sfx"]))), "SFX-Datei existiert")
	I18nService.reset_cache()
	for locale in ["de", "en"]:
		var tbl := I18nService.table(locale)
		for key in [
			"album.unlock_toast_selten",
			"album.unlock_toast_episch",
			"album.rarity_haeufig",
			"album.rarity_selten",
			"album.rarity_episch",
			"album.rarity_geheim",
		]:
			assert_true(tbl.has(key), "%s fehlt in %s" % [key, locale])


# ── (b) Gold-Glitzer im Album ────────────────────────────────────────────────


func test_gold_glitzer_nur_bei_gold() -> void:
	assert_false(StickerCard.has_gold_glitter("haeufig"), "haeufig glitzert nicht")
	assert_false(StickerCard.has_gold_glitter("selten"), "Silber glitzert nicht")
	assert_true(StickerCard.has_gold_glitter("episch"), "Gold glitzert")
	assert_false(StickerCard.has_gold_glitter("geheim"), "geheim ohne Dauer-Shimmer")
	var card := Control.new()
	tree.root.add_child(card)
	assert_eq(StickerCard.attach_glitter(card, "selten", false), null, "Silber: kein Overlay")
	var overlay := StickerCard.attach_glitter(card, "episch", false)
	assert_true(overlay != null, "Gold: Shimmer-Overlay")
	assert_true(overlay.material is ShaderMaterial, "Shader sitzt")
	assert_almost(
		float((overlay.material as ShaderMaterial).get_shader_parameter("motion_scale")),
		1.0,
		1e-6,
		"volle Bewegung ohne Reduced Motion"
	)
	card.free()


func test_gold_glitzer_reduced_motion_statisch() -> void:
	var card := Control.new()
	tree.root.add_child(card)
	var overlay := StickerCard.attach_glitter(card, "episch", true)
	assert_true(overlay != null, "Reduced Motion behält den (statischen) Glanz")
	assert_almost(
		float((overlay.material as ShaderMaterial).get_shader_parameter("motion_scale")),
		0.0,
		1e-6,
		"motion_scale = 0 → statisch"
	)
	card.free()


func test_album_karte_traegt_gold_shimmer() -> void:
	# Album-Grid end-to-end: freigeschalteter Gold-Sticker trägt das
	# GoldShimmer-Overlay, der Silber-Nachbar nicht, gesperrtes Gold leakt
	# nichts (Mystery-Slot bleibt effektfrei).
	var gs := _fresh_gs()
	gs.update(
		func(state: Dictionary) -> void:
			state["stickers"] = {
				"unlocked": {"gold_frei": NOW_MS, "silber_frei": NOW_MS}, "seen": {}
			}
	)
	var katalog := [
		{
			"id": "gold_frei",
			"name_de": "Gold frei",
			"flavor_de": "x",
			"hint_de": "x",
			"set": "gvz",
			"page": "gvz",
			"rarity": "episch",
			"image": "res://assets/stickers/gvz_kommandant.png",
			"cond": {"type": "event", "key": "nie"},
		},
		{
			"id": "silber_frei",
			"name_de": "Silber frei",
			"flavor_de": "x",
			"hint_de": "x",
			"set": "gvz",
			"page": "gvz",
			"rarity": "selten",
			"image": "res://assets/stickers/gvz_zaunheld.png",
			"cond": {"type": "event", "key": "nie"},
		},
		{
			"id": "gold_zu",
			"name_de": "Gold zu",
			"flavor_de": "x",
			"hint_de": "x",
			"set": "gvz",
			"page": "gvz",
			"rarity": "episch",
			"image": "res://assets/stickers/gvz_sieg.png",
			"cond": {"type": "event", "key": "nie"},
		},
	]
	var pages := [{"id": "gvz", "title_de": "GvZ", "icon": "shield", "tint": "#D9CFF0"}]
	var screen := AlbumScreen.new()
	screen.auto_navigate = false
	screen.gs_override = gs
	screen.catalog_override = katalog
	screen.pages_override = pages
	tree.root.add_child(screen)
	await wait_frames(2)
	var gold_card := screen.find_child("Sticker_gold_frei", true, false)
	var silber_card := screen.find_child("Sticker_silber_frei", true, false)
	var zu_card := screen.find_child("Sticker_gold_zu", true, false)
	assert_true(gold_card != null and silber_card != null and zu_card != null, "3 Karten im Grid")
	assert_true(gold_card.find_child("GoldShimmer", true, false) != null, "Gold frei → Shimmer")
	assert_true(silber_card.find_child("GoldShimmer", true, false) == null, "Silber → kein Shimmer")
	assert_true(
		zu_card.find_child("GoldShimmer", true, false) == null, "gesperrtes Gold leakt nicht"
	)
	screen.free()
	gs.free()
