extends TestCase
## W13C GOOBYMAN — Zahnbürsten-Haltbarkeit (Zustandsmaschine, deterministischer
## RNG), Zähneputz-Blocker + Entsperren durch Neukauf, Migration (Bestands-
## Saves starten mit intakter Standard-Bürste), Pflaster-Cap 1/Tag
## (zeitinjiziert), Schlafmaske (einmalig, −10 % Vorlese-Wörter), Umhang-Gag
## (5+ Artikel, genau einmal), Sortiment-/Ort-Daten (Schema, Szene, Dialoge
## DE↔EN, Karte) und die Balance-Pack-Chance inkl. Pack-Override.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const SORTIMENT_JSON := "res://scripts/city/data/goobyman_sortiment.json"
const DIALOG_DE := "res://scripts/city/data/dialoge/goobyman.json"
const DIALOG_EN := "res://scripts/city/data/dialoge/en/goobyman.json"
const SZENE := "res://scenes/city/orte/goobyman.tscn"
const REGISTRY_BASE := "user://w13c_goobyman_registry"
const NOW_MS := 1769860800000

const KATEGORIEN := ["zahnbuerste", "pflaster", "einmalig"]

var _dir_seq := 0


func _fresh_game_state() -> Node:
	ZahnbuersteState.register_slice()
	GoobymanKatalog.register_slice()
	CityState.register_slice()
	_dir_seq += 1
	var dir := "user://w13c_tests/goobyman_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _sortiment() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SORTIMENT_JSON))
	assert_true(parsed is Dictionary, "goobyman_sortiment.json parst")
	return parsed.get("waren", []) if parsed is Dictionary else []


func _gib_coins(gs: Node, coins: int) -> void:
	gs.update(func(state: Dictionary) -> void: state["economy"]["coins"] = coins)


# ── Haltbarkeits-Zustandsmaschine (pure, deterministisch) ────────────────────


func test_zustandsmaschine() -> void:
	# Standard (haltbarkeit 3): neu → benutzt → ausgefranst → gebrochen.
	assert_eq(ZahnbuersteState.zustand(0, 3), "neu")
	assert_eq(ZahnbuersteState.zustand(1, 3), "benutzt")
	assert_eq(ZahnbuersteState.zustand(2, 3), "ausgefranst")
	assert_eq(ZahnbuersteState.zustand(3, 3), "gebrochen")
	assert_eq(ZahnbuersteState.zustand(99, 3), "gebrochen", "über Max bleibt gebrochen")
	# Turbo (haltbarkeit 8) hält länger durch.
	assert_eq(ZahnbuersteState.zustand(1, 8), "benutzt")
	assert_eq(ZahnbuersteState.zustand(7, 8), "ausgefranst")
	assert_eq(ZahnbuersteState.zustand(8, 8), "gebrochen")
	# Feindliche Werte werden geklemmt.
	assert_eq(ZahnbuersteState.zustand(-5, 3), "neu", "negative Abnutzung = neu")
	assert_eq(ZahnbuersteState.zustand(1, 0), "gebrochen", "haltbarkeit min. 1")


func test_abnutzung_deterministischer_rng() -> void:
	# Gleiche Clamp-Semantik wie BadState.brush_breaks: roll < chance nutzt ab.
	assert_eq(ZahnbuersteState.naechste_abnutzung(0, 0.0, 0.02), 1, "Roll unter Chance")
	assert_eq(ZahnbuersteState.naechste_abnutzung(0, 0.02, 0.02), 0, "Roll auf Chance nicht")
	assert_eq(ZahnbuersteState.naechste_abnutzung(2, 0.5, -1.0), 2, "Chance wird geclampt")
	assert_eq(ZahnbuersteState.naechste_abnutzung(2, 0.999, 2.0), 3, "Chance > 1 = sicher")


func test_haltbarkeit_aus_sortiment() -> void:
	var waren := _sortiment()
	assert_eq(ZahnbuersteState.haltbarkeit_von("standard", waren), 3)
	assert_eq(ZahnbuersteState.haltbarkeit_von("flausch", waren), 5)
	assert_eq(ZahnbuersteState.haltbarkeit_von("turbo", waren), 8)
	assert_eq(
		ZahnbuersteState.haltbarkeit_von("gibts_nicht", waren),
		ZahnbuersteState.HALTBARKEIT_FALLBACK,
		"unbekannter Typ fällt weich"
	)


func test_putz_session_respektiert_chance() -> void:
	var gs := _fresh_game_state()
	# Chance 0 (Remote-Config könnte den Bruch komplett abdrehen): nie Abrieb.
	for _i in 20:
		var ohne := ZahnbuersteState.putz_session(gs, 0.0, 0.0)
		assert_false(bool(ohne["abgenutzt"]), "Chance 0 nutzt nie ab")
	assert_eq(int(gs.get_value("zahnbuerste.abnutzung", -1)), 0)
	# Chance 1: jede Session ein Punkt — Standard bricht nach genau 3.
	var zustaende: Array[String] = []
	for _i in 3:
		var session := ZahnbuersteState.putz_session(gs, 0.5, 1.0)
		zustaende.append(str(session["zustand"]))
	assert_eq(zustaende, ["benutzt", "ausgefranst", "gebrochen"], "Leiter in Session-Folge")
	assert_true(ZahnbuersteState.ist_gebrochen(gs), "nach 3 Treffern gebrochen")
	# Gebrochen bleibt gebrochen (kein weiterer Abrieb, kein Crash).
	var danach := ZahnbuersteState.putz_session(gs, 0.5, 1.0)
	assert_true(bool(danach["gebrochen"]))
	assert_false(bool(danach["abgenutzt"]))
	gs.free()


func test_erster_bruch_info_genau_einmal() -> void:
	var gs := _fresh_game_state()
	var letzte := {}
	for _i in 3:
		letzte = ZahnbuersteState.putz_session(gs, 0.0, 1.0)
	assert_true(bool(letzte["erster_bruch"]), "erster Bruch meldet die Erste-Male-Info")
	# Neue Bürste rein, wieder kaputt putzen: Info kommt NICHT nochmal.
	gs.update(
		func(state: Dictionary) -> void: state["inventory"]["items"]["zahnbuerste_standard"] = 1
	)
	assert_eq(ZahnbuersteState.aktiviere_ersatz(gs), "standard")
	for _i in 3:
		letzte = ZahnbuersteState.putz_session(gs, 0.0, 1.0)
	assert_true(bool(letzte["gebrochen"]))
	assert_false(bool(letzte["erster_bruch"]), "Latch: Info nur beim allerersten Bruch")
	gs.free()


# ── Blocker + Entsperren durch Neukauf ───────────────────────────────────────


func test_blocker_und_entsperren_durch_neukauf() -> void:
	var gs := _fresh_game_state()
	for _i in 3:
		ZahnbuersteState.putz_session(gs, 0.0, 1.0)
	assert_true(ZahnbuersteState.ist_gebrochen(gs), "Bürste gebrochen = Putzen blockiert")
	assert_eq(ZahnbuersteState.aktiviere_ersatz(gs), "", "ohne Ersatz bleibt blockiert")
	assert_true(ZahnbuersteState.ist_gebrochen(gs))
	# Kauf beim GOOBYMAN (echter Sheet-Kaufpfad → inventory.items).
	_gib_coins(gs, 200)
	var sheet := GoobymanSheet.new()
	sheet.gs = gs
	sheet.waren = _sortiment()
	sheet.tag_override = "2026-01-31"
	var flausch := GoobymanKatalog.ware(sheet.waren, "zahnbuerste_flausch")
	assert_true(sheet.kaufe(flausch), "Kauf klappt")
	assert_eq(int(gs.get_value("inventory.items.zahnbuerste_flausch", 0)), 1, "Ersatz im Inventar")
	assert_eq(int(gs.get_value("economy.coins", 0)), 200 - 18, "Münzen abgezogen")
	# Aktivieren entsperrt: bester Ersatz wird eingespannt, Item verbraucht.
	assert_eq(ZahnbuersteState.aktiviere_ersatz(gs), "flausch")
	assert_false(ZahnbuersteState.ist_gebrochen(gs), "neue Bürste = entsperrt")
	assert_eq(int(gs.get_value("zahnbuerste.abnutzung", -1)), 0, "frisch eingespannt")
	assert_eq(str(gs.get_value("zahnbuerste.typ", "")), "flausch")
	assert_eq(int(gs.get_value("inventory.items.zahnbuerste_flausch", 0)), 0, "Item verbraucht")
	sheet.free()
	gs.free()


func test_aktivieren_nimmt_beste_buerste() -> void:
	var gs := _fresh_game_state()
	gs.update(
		func(state: Dictionary) -> void:
			state["inventory"]["items"]["zahnbuerste_standard"] = 2
			state["inventory"]["items"]["zahnbuerste_turbo"] = 1
	)
	assert_eq(ZahnbuersteState.aktiviere_ersatz(gs), "turbo", "höchste Haltbarkeit gewinnt")
	assert_eq(int(gs.get_value("inventory.items.zahnbuerste_standard", 0)), 2, "Rest bleibt")
	gs.free()


# ── Migration: Bestands-Saves starten mit intakter Standard-Bürste ───────────


func test_migration_bestandssave_intakte_buerste() -> void:
	# Bestands-Save OHNE zahnbuerste-Slice (v5 vor W13C): Default greift —
	# intakte Standard-Bürste, KEIN Soft-Lock.
	var slice := ZahnbuersteState.slice_of({})
	assert_eq(str(slice["typ"]), "standard")
	assert_eq(int(slice["abnutzung"]), 0)
	assert_eq(ZahnbuersteState.zustand(int(slice["abnutzung"]), 3), "neu")
	# Auch am echten GameState: Slice hart entfernen → weiter nicht blockiert.
	var gs := _fresh_game_state()
	gs.update(func(state: Dictionary) -> void: state.erase("zahnbuerste"))
	assert_false(ZahnbuersteState.ist_gebrochen(gs), "Bestands-Save nie blockiert")
	gs.free()
	# Feindliche Saves: normalize klemmt.
	var junk := ZahnbuersteState.normalize_slice(
		{"typ": "", "abnutzung": -7, "bruchInfoGesehen": 1}
	)
	assert_eq(str(junk["typ"]), "standard")
	assert_eq(int(junk["abnutzung"]), 0)
	assert_false(bool(junk["bruchInfoGesehen"]), "nur echtes true zählt")
	assert_eq(ZahnbuersteState.normalize_slice("kaputt")["typ"], "standard", "Junk → Default")


# ── Pflaster: heilt 5 sofort, Cap 1/Tag (zeitinjiziert) ──────────────────────


func test_pflaster_cap_pro_tag() -> void:
	var gs := _fresh_game_state()
	gs.update(func(state: Dictionary) -> void: state["gooby"]["health"]["junkScore"] = 7.0)
	var waren := _sortiment()
	var pflaster := GoobymanKatalog.ware(waren, "goobyman_pflaster")
	assert_eq(int(pflaster.get("heilt", 0)), 5, "Pflaster heilt 5")
	assert_true(GoobymanKatalog.pflaster_frei(gs.state(), "2026-01-31"))
	assert_true(GoobymanKatalog.pflaster_anwenden(gs, pflaster, "2026-01-31"), "1. Pflaster wirkt")
	assert_almost(float(gs.get_value("gooby.health.junkScore", -1.0)), 2.0, 1e-6, "7 − 5 = 2")
	# Cap: am selben Tag kein zweites.
	assert_false(GoobymanKatalog.pflaster_frei(gs.state(), "2026-01-31"))
	assert_false(GoobymanKatalog.pflaster_anwenden(gs, pflaster, "2026-01-31"), "Cap 1/Tag")
	assert_almost(float(gs.get_value("gooby.health.junkScore", -1.0)), 2.0, 1e-6, "unverändert")
	# Nächster (injizierter) Tag: wieder frei, Boden bei 0.
	assert_true(GoobymanKatalog.pflaster_anwenden(gs, pflaster, "2026-02-01"), "morgen wieder")
	assert_almost(float(gs.get_value("gooby.health.junkScore", -1.0)), 0.0, 1e-6, "Boden 0")
	gs.free()


func test_pflaster_kauf_im_sheet_zeitinjiziert() -> void:
	var gs := _fresh_game_state()
	_gib_coins(gs, 100)
	var sheet := GoobymanSheet.new()
	sheet.gs = gs
	sheet.waren = _sortiment()
	sheet.tag_override = "2026-01-31"
	var pflaster := GoobymanKatalog.ware(sheet.waren, "goobyman_pflaster")
	assert_true(sheet.kann_kaufen(pflaster))
	assert_true(sheet.kaufe(pflaster), "Kauf wendet das Pflaster sofort an")
	assert_eq(int(gs.get_value("economy.coins", 0)), 90, "10 Münzen bezahlt")
	assert_false(sheet.kann_kaufen(pflaster), "heute gesperrt (Cap)")
	assert_false(sheet.kaufe(pflaster), "kein Doppelkauf am selben Tag")
	assert_eq(int(gs.get_value("economy.coins", 0)), 90, "keine Münzen verloren")
	sheet.tag_override = "2026-02-01"
	assert_true(sheet.kann_kaufen(pflaster), "morgen wieder kaufbar")
	sheet.free()
	gs.free()


# ── Schlafmaske: einmalig, +10 % schnelleres Einschlafen ─────────────────────


func test_schlafmaske_einmalig_und_wirkung() -> void:
	var gs := _fresh_game_state()
	_gib_coins(gs, 200)
	var sheet := GoobymanSheet.new()
	sheet.gs = gs
	sheet.waren = _sortiment()
	sheet.tag_override = "2026-01-31"
	var maske := GoobymanKatalog.ware(sheet.waren, "schlafmaske")
	assert_false(GoobymanKatalog.schlafmaske_gekauft(gs.state()))
	assert_true(sheet.kaufe(maske), "Erstkauf klappt")
	assert_true(GoobymanKatalog.schlafmaske_gekauft(gs.state()))
	assert_false(sheet.kann_kaufen(maske), "einmalig: kein Zweitkauf")
	assert_false(sheet.kaufe(maske))
	# Wirkung: 10 % weniger Vorlese-Wörter, Boden = StoryBooks.WORDS_MIN.
	assert_eq(GoobymanKatalog.schlafmaske_woerter(6, false), 6, "ohne Maske unverändert")
	assert_eq(GoobymanKatalog.schlafmaske_woerter(6, true), 5, "6 → 5")
	assert_eq(GoobymanKatalog.schlafmaske_woerter(9, true), 8, "9 → 8")
	assert_eq(GoobymanKatalog.schlafmaske_woerter(3, true), StoryBooks.WORDS_MIN, "Boden 3")
	sheet.free()
	gs.free()


# ── Umhang-Gag: 5+ Artikel auf einmal, genau einmal pro Besuch ───────────────


func test_umhang_gag_ab_fuenf_artikeln() -> void:
	assert_false(GoobymanKatalog.umhang_gag_faellig(4), "4 Artikel: kein Gag")
	assert_true(GoobymanKatalog.umhang_gag_faellig(5), "ab 5 Artikeln fällig")
	var gs := _fresh_game_state()
	_gib_coins(gs, 500)
	var sheet := GoobymanSheet.new()
	sheet.gs = gs
	sheet.waren = _sortiment()
	sheet.tag_override = "2026-01-31"
	var gag_zaehler := {"n": 0}
	sheet.umhang_gag.connect(func() -> void: gag_zaehler["n"] += 1)
	var standard := GoobymanKatalog.ware(sheet.waren, "zahnbuerste_standard")
	for i in 6:
		assert_true(sheet.kaufe(standard), "Kauf %d klappt" % (i + 1))
		var erwartet := 1 if i + 1 >= GoobymanKatalog.UMHANG_GAG_AB else 0
		assert_eq(gag_zaehler["n"], erwartet, "Gag-Stand nach Kauf %d" % (i + 1))
	assert_eq(gag_zaehler["n"], 1, "Gag feuert GENAU einmal pro Besuch")
	assert_eq(sheet.im_besuch_gekauft, 6, "Besuchs-Zähler zählt weiter")
	sheet.free()
	gs.free()


# ── Sortiment-Schema + Ort-Registrierung + Assets ────────────────────────────


func test_sortiment_schema_valide() -> void:
	var waren := _sortiment()
	assert_true(waren.size() >= 5, "mind. 3 Bürsten + Pflaster + Schlafmaske")
	var ids := {}
	var buersten: Array = []
	for ware: Dictionary in waren:
		var id := str(ware.get("id", ""))
		assert_false(id.is_empty(), "Ware hat id")
		assert_false(ids.has(id), "Id eindeutig: %s" % id)
		ids[id] = true
		assert_false(str(ware.get("name_de", "")).is_empty(), id + ": name_de")
		assert_true(int(ware.get("preis", 0)) > 0, id + ": preis > 0")
		assert_true(KATEGORIEN.has(str(ware.get("kategorie", ""))), id + ": kategorie bekannt")
		assert_false(str(ware.get("glyph", "")).is_empty(), id + ": glyph (prozedurales Icon)")
		var glb := str(ware.get("glb", ""))
		if not glb.is_empty():
			assert_true(ResourceLoader.exists(glb), id + ": glb existiert")
		if str(ware.get("kategorie", "")) == "zahnbuerste":
			assert_false(str(ware.get("inventar", "")).is_empty(), id + ": inventar")
			assert_true(
				str(ware.get("inventar", "")).begins_with(ZahnbuersteState.ITEM_PREFIX),
				id + ": inventar-Präfix für ZahnbuersteState"
			)
			buersten.append(ware)
	assert_eq(buersten.size(), 3, "3 Bürsten-Qualitäten")
	# Bessere (teurere) Bürste = mehr Haltbarkeit.
	buersten.sort_custom(func(a, b): return int(a["preis"]) < int(b["preis"]))
	for i in buersten.size() - 1:
		assert_true(
			int(buersten[i + 1]["haltbarkeit"]) > int(buersten[i]["haltbarkeit"]),
			"Haltbarkeit steigt mit dem Preis"
		)
	var pflaster := GoobymanKatalog.ware(waren, "goobyman_pflaster")
	assert_eq(int(pflaster.get("heilt", 0)), 5, "Pflaster: heilt 5")
	var maske := GoobymanKatalog.ware(waren, "schlafmaske")
	assert_eq(str(maske.get("kategorie", "")), "einmalig", "Schlafmaske einmalig")


func test_ort_in_karte_und_assets_existieren() -> void:
	var karte := CityMap.laden()
	var eintrag := OrtKatalog.eintrag("goobyman", karte)
	assert_false(eintrag.is_empty(), "goobyman steht in city_map.json")
	assert_eq(karte.validieren().size(), 0, "Karte bleibt konsistent")
	assert_true(OrtKatalog.betretbare_ids(karte).has("goobyman"), "betretbar")
	assert_true(OrtKatalog.oeffnung("goobyman", karte).is_empty(), "immer offen")
	assert_eq(karte.energie_kosten("goobyman"), 4, "Zentrum = 4 Energie")
	assert_eq(str(eintrag.get("szene", "")), SZENE)
	assert_true(ResourceLoader.exists(SZENE), "Szene existiert")
	var name_key := str(eintrag.get("name_key", ""))
	assert_ne(I18nService.t(name_key), name_key, "Ortsname übersetzt")
	# Dialoge: DE + EN-Pendant, gleiche Knoten-Struktur (E6 P2-13).
	var de: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIALOG_DE))
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIALOG_EN))
	assert_true(de is Dictionary and en is Dictionary, "Dialoge parsen")
	var de_nodes: Dictionary = de.get("nodes", {})
	var en_nodes: Dictionary = en.get("nodes", {})
	assert_eq(de_nodes.keys(), en_nodes.keys(), "Dialog-Knoten DE↔EN paritätisch")
	# Der Laden-Einstieg (effekt "laden") existiert.
	var laden: Dictionary = de_nodes.get("laden", {})
	assert_true((laden.get("effekt", []) as Array).has("laden"), "Dialog öffnet den Laden")
	# Strings, die die Skripte nutzen, sind übersetzt (DE-Tabelle).
	for key: String in [
		"goobyman.zahnputz.blockiert",
		"goobyman.zahnputz.neue_buerste",
		"goobyman.bruch_info.titel",
		"goobyman.bruch_info.text",
		"goobyman.bruch_info.ok",
		"goobyman.umhang.gag",
		"goobyman.laden.claim",
		"goobyman.laden.erstes_mal",
		"city.ort.goobyman",
	]:
		assert_true(I18nService.has_key(key), "String fehlt: %s" % key)


func test_ort_szene_baut_headless() -> void:
	var gs := _fresh_game_state()
	var szene: PackedScene = load(SZENE)
	var ort: Node3D = szene.instantiate()
	ort.game_state_override = gs
	tree.root.add_child(ort)
	await wait_frames(2)
	assert_eq(str(ort.ort_id), "goobyman", "ort_id aus der Szene")
	assert_true(ort.ist_erstbesuch, "erster Besuch wird gebucht")
	assert_true(OrtKatalog.schon_besucht(gs, "goobyman"), "Besuch im city-Slice")
	# Laden öffnen: GoobymanSheet hängt im Sheet, Umhang-Gag ist verdrahtet.
	ort.oeffne_laden()
	await wait_frames(1)
	var sheet := _finde_goobyman_sheet(ort)
	assert_true(sheet != null, "GoobymanSheet im PanelSheet")
	if sheet != null:
		assert_true(sheet.umhang_gag.is_connected(ort._spiele_umhang_gag), "Gag verdrahtet")
	tree.root.remove_child(ort)
	ort.free()
	gs.free()
	# Ausklingen lassen (Echtzeit, headless läuft uncapped): Dialog-Babble +
	# Sheet-Pluck sind One-Shot-Player/SceneTreeTimer am Tree — ohne die
	# Wartezeit meldet der Einzeltest-Exit sonst Audio-/Timer-„Leaks“.
	await tree.create_timer(0.5).timeout


func _finde_goobyman_sheet(wurzel: Node) -> GoobymanSheet:
	for kind in wurzel.find_children("*", "VBoxContainer", true, false):
		if kind is GoobymanSheet:
			return kind
	return null


# ── Balance-Pack-Chance: Fallback + Remote-Override ──────────────────────────


func test_balance_chance_und_pack_override() -> void:
	# Eingebautes Balance-Pack führt den Key (remote-config-Basis).
	var balance: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/balance/data/balance.json")
	)
	assert_true(balance is Dictionary, "balance.json parst")
	var values: Dictionary = balance.get("values", {})
	assert_true(values.has("zahnbuersten_bruch_chance"), "Chance-Key im Balance-Pack")
	# Override-Test: ein (Remote-)Pack mit höherer Priorität ändert die
	# Chance UND kann die goobyman-Sortiment-Domain überschatten.
	_wipe(REGISTRY_BASE)
	_write_json(
		REGISTRY_BASE + "/content/w13c_test/pack.json",
		{"id": "w13c_test", "version": "9.9.9", "priority": 900, "domains": ["balance"]}
	)
	_write_json(
		REGISTRY_BASE + "/content/w13c_test/data/balance.json",
		{"schema": 1, "values": {"zahnbuersten_bruch_chance": 0.5}}
	)
	_write_json(
		REGISTRY_BASE + "/content/w13c_test/data/goobyman.json",
		{
			"schema": 1,
			"items":
			[
				{
					"id": "zahnbuerste_standard",
					"name_de": "Zahnbürste Standard (Remote)",
					"preis": 8,
					"inventar": "zahnbuerste_standard",
					"kategorie": "zahnbuerste",
					"haltbarkeit": 4,
					"glyph": "🪥"
				}
			],
		}
	)
	var registry := ContentRegistryService.new()
	registry.auto_reload = false
	registry.content_root = REGISTRY_BASE + "/content"
	registry.packs_dir = REGISTRY_BASE + "/packs"
	registry.reload()
	assert_almost(
		float(registry.get_balance("zahnbuersten_bruch_chance", 0.02)),
		0.5,
		1e-9,
		"Pack-Override der Bruch-Chance kommt an"
	)
	var remote_waren := registry.get_items("goobyman")
	assert_eq(remote_waren.size(), 1, "goobyman-Domain aus dem Pack")
	assert_eq(
		ZahnbuersteState.haltbarkeit_von("standard", remote_waren),
		4,
		"Remote-Sortiment ändert die Haltbarkeit"
	)
	# Die Zustandsmaschine respektiert die (geänderte) Chance deterministisch.
	assert_eq(ZahnbuersteState.naechste_abnutzung(0, 0.49, 0.5), 1, "Roll 0.49 < 0.5 nutzt ab")
	assert_eq(ZahnbuersteState.naechste_abnutzung(0, 0.51, 0.5), 0, "Roll 0.51 nicht")
	registry.free()
	_wipe(REGISTRY_BASE)


func _write_json(pfad: String, daten: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pfad.get_base_dir()))
	var f := FileAccess.open(pfad, FileAccess.WRITE)
	f.store_string(JSON.stringify(daten))
	f.close()


func _wipe(pfad: String) -> void:
	var absolut := ProjectSettings.globalize_path(pfad)
	if DirAccess.dir_exists_absolute(absolut):
		_wipe_rekursiv(absolut)


func _wipe_rekursiv(absolut: String) -> void:
	var dir := DirAccess.open(absolut)
	if dir == null:
		return
	dir.list_dir_begin()
	var eintrag := dir.get_next()
	while eintrag != "":
		var voll := absolut.path_join(eintrag)
		if dir.current_is_dir():
			_wipe_rekursiv(voll)
		else:
			DirAccess.remove_absolute(voll)
		eintrag = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolut)
