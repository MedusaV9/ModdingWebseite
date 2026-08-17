extends TestCase
## W18/B1 (FIX-G2) — Wächter: der Ranch-Kauf frisst keine Münzen mehr.
## Befund: `RanchState.register_slice()` lief in KEINEM Produktionspfad
## (Goobye/McGooby registrieren in ihren Szenen — der Ranch-KAUF läuft aber
## im Hub/an der Landstraße, bevor je eine Ranch-Szene lud). `kaufe` buchte
## erst ab und crashte dann am harten `state["ranch"]`-Zugriff: 2500 ᴳ weg,
## kein Kauf-Flag, Hub bot erneut an. Wachen:
##   (a) Produktions-Boot (OHNE manuellen register_slice): Münzen −Preis
##       GENAU einmal, gekauft, Start-Tiere da, Hub bietet NICHT erneut an,
##       Kauf überlebt den Save-Reload;
##   (b) Kauf ganz ohne Registrierung + ohne ranch-Key → atomar (nie Geld
##       ohne Leistung), Pleite-Fall ändert nichts;
##   (c) „Später kaufen“/„Gesehen“ ohne Slice → fehlerfrei, Flags gesetzt;
##   (d) Doppel-Kauf (zweiter Klick + Stale-check-Rennen) → einmal gebucht;
##   (e) Registrierungs-Loch-Runde: Boot-Registry deckt alle bekannten
##       Slices ab (ranch inklusive), DLC-Schreibpfade überleben fehlende
##       Slice-Keys (Ensure-Muster).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _dir_seq := 0


class FakeRegistry:
	extends RefCounted
	## Minimal-Pack: 1 Start-Pferd + 1 Start-Kuh, Preis/Level wie im Spiel.

	var items: Array = [
		{
			"id": "pferd_karamell",
			"typ": "tier",
			"art": "pferd",
			"start": true,
			"name_key": "ranch.tiere.karamell",
			"farbe": "#D9A066",
			"fell_id": "braun",
		},
		{"id": "kuh_flecki", "typ": "tier", "art": "kuh", "start": true, "farbe": "#F5EFE4"},
	]
	var balance: Dictionary = {"ranch.preis": 2500, "ranch.freischalt_level": 15}

	func get_items(_domain: String) -> Array:
		return items

	func get_balance(key: String, default_value: Variant = null) -> Variant:
		return balance.get(key, default_value)


class StaleCheckDouble:
	extends RefCounted
	## Simuliert das Doppel-Klick-Rennen: check() liest noch „nicht gekauft“
	## (veralteter UI-Stand), der State IST aber schon gekauft — der
	## In-Block-Besitz-Check muss die zweite Abbuchung verhindern.

	var state: Dictionary = {}
	var notified: Array = []

	func get_value(path: String, default: Variant = null) -> Variant:
		if path == "ranch.gekauft":
			return false
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and node.has(part):
				node = node[part]
			else:
				return default
		return node

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(id: String) -> void:
		notified.append(id)


## GameState EXAKT wie im Produktions-Boot: nur initialize() — bewusst OHNE
## manuellen RanchState.register_slice()-Aufruf (das war Befund B1).
func _produktions_gs(level: int, coins: int, pfad := "") -> Node:
	_dir_seq += 1
	var dir := "user://w18g2_tests/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(pfad if pfad != "" else dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _mit_pack() -> void:
	RanchKatalog.registry_override = FakeRegistry.new()
	RanchKatalog.reset_cache()


func _teardown(gs: Node) -> void:
	if gs != null:
		gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()
	RanchKatalog.registry_override = null
	RanchKatalog.reset_cache()


## Simulierter Registrierungs-Ausfall: Registrierung weg + ranch-Key aus dem
## geladenen State löschen — exakt der W18/B1-Produktionszustand vor dem Fix.
func _simuliere_fehlende_registrierung(gs: Node) -> void:
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	gs.update(func(state: Dictionary) -> void: state.erase(RanchState.SLICE_ID))


## (a) Kauf auf frischem Save über den Produktions-Boot.
func test_a_produktionskauf_bucht_genau_einmal_und_registriert() -> void:
	_mit_pack()
	_dir_seq += 1
	var dir := "user://w18g2_tests/a_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var pfad := dir + "/save_v5.json"
	var gs := _produktions_gs(15, RanchKatalog.preis() + 777, pfad)
	assert_true(
		SaveSchema.registered_slice_ids().has(RanchState.SLICE_ID),
		"Boot registriert den ranch-Slice selbst (DEFAULT_SLICE_SCRIPTS)"
	)
	var spent_vor := int(gs.get_value("economy.coinsSpent", 0))
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK, "Kauf klappt ohne manuelle Registrierung")
	assert_eq(int(gs.get_value("economy.coins", -1)), 777, "GENAU der Preis, GENAU einmal weg")
	assert_eq(
		int(gs.get_value("economy.coinsSpent", 0)) - spent_vor,
		RanchKatalog.preis(),
		"Abbuchung steht im Spent-Buch"
	)
	assert_eq(gs.get_value("ranch.gekauft"), true, "Kauf ist registriert")
	var hoftiere: Array = gs.get_value("ranch.hoftiere", [])
	assert_eq(hoftiere.size(), 1, "Start-Kuh zieht ein")
	var pferde: Dictionary = gs.get_value("ranch.tiere.pferde", {})
	assert_eq(pferde.keys(), ["pferd_karamell"], "Start-Pferd zieht ein")
	assert_false(RanchOffer.sollte_zeigen(gs), "Hub/Recap bieten den Kauf NICHT erneut an")
	assert_eq(RanchKauf.check(gs), RanchKauf.RESULT_OWNED, "zweiter Kauf ist gesperrt")
	assert_eq(
		DlcKatalog.status_fuer({"id": "ranch", "status": "verfuegbar"}, gs),
		DlcKatalog.STATUS_INSTALLIERT,
		"DLC-Hub-Karte zeigt installiert statt kaufbar"
	)
	assert_true(gs.save_now(), "Save schreibt")
	gs.free()
	var gs2: Node = GameStateScript.new()
	gs2.initialize(pfad)
	assert_eq(gs2.get_value("ranch.gekauft"), true, "Kauf überlebt den Save-Reload")
	assert_eq(int(gs2.get_value("economy.coins", -1)), 777, "Münzstand überlebt den Reload")
	_teardown(gs2)


## (b) Kauf komplett OHNE Slice-Registrierung: atomar, nie Geld ohne Leistung.
func test_b_kauf_ohne_registrierung_verliert_kein_geld() -> void:
	_mit_pack()
	var gs := _produktions_gs(15, RanchKatalog.preis() + 111)
	_simuliere_fehlende_registrierung(gs)
	var vorher := int(gs.get_value("economy.coins", -1))
	var ergebnis := RanchKauf.kaufe(gs)
	var abgebucht := int(gs.get_value("economy.coins", -1)) != vorher
	var gekauft := bool(gs.get_value("ranch.gekauft", false))
	assert_eq(abgebucht, gekauft, "Invariante: Geld weg NUR mit Kauf-Registrierung")
	assert_eq(ergebnis, RanchKauf.RESULT_OK, "ensure_slice heilt den fehlenden Slice im Block")
	assert_eq(int(gs.get_value("economy.coins", -1)), 111, "genau einmal abgebucht")
	assert_eq(gs.get_value("ranch.gekauft"), true)
	assert_eq((gs.get_value("ranch.hoftiere", []) as Array).size(), 1, "Start-Tiere trotzdem da")
	_teardown(gs)


## (b2) Pleite-Fall ohne Registrierung: ehrliches RESULT, nichts verändert.
func test_b2_pleite_ohne_registrierung_aendert_nichts() -> void:
	_mit_pack()
	var gs := _produktions_gs(15, RanchKatalog.preis() - 1)
	_simuliere_fehlende_registrierung(gs)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_BROKE, "ehrliches Ergebnis statt OK")
	assert_eq(int(gs.get_value("economy.coins", -1)), RanchKatalog.preis() - 1, "unangetastet")
	assert_eq(gs.get_value("ranch.gekauft", false), false, "nicht gekauft")
	_teardown(gs)


## (c) „Später kaufen“/„Gesehen“ ohne Slice: fehlerfrei, Flags gesetzt
## (vorher: SCRIPT ERROR ranch_state.gd:98, Flags gingen verloren).
func test_c_spaeter_kaufen_ohne_slice_ohne_error() -> void:
	_mit_pack()
	var gs := _produktions_gs(15, 0)
	_simuliere_fehlende_registrierung(gs)
	RanchState.angebot_verschieben(gs)
	assert_eq(gs.get_value("ranch.angebotGesehen"), true, "gesehen gemerkt")
	assert_eq(gs.get_value("ranch.angebotVerschoben"), true, "verschoben gemerkt")
	assert_false(RanchOffer.sollte_zeigen(gs), "Auto-Angebot kommt nicht erneut")
	gs.update(func(state: Dictionary) -> void: state.erase(RanchState.SLICE_ID))
	RanchState.angebot_gesehen(gs)
	assert_eq(gs.get_value("ranch.angebotGesehen"), true, "„Jetzt losfahren“-Pfad fehlerfrei")
	assert_eq(gs.get_value("ranch.angebotVerschoben"), false)
	_teardown(gs)


## (d) Doppel-Kauf: zweiter Klick blockiert, GENAU eine Abbuchung.
func test_d_doppel_kauf_bucht_genau_einmal() -> void:
	_mit_pack()
	var gs := _produktions_gs(15, RanchKatalog.preis() * 2)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK)
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OWNED, "zweiter Klick blockiert")
	assert_eq(int(gs.get_value("economy.coins", -1)), RanchKatalog.preis(), "einmal gebucht")
	_teardown(gs)


## (d2) Stale-check-Rennen: check() sieht „nicht gekauft“, der State ist es
## schon — der In-Block-Besitz-Check verhindert die zweite Abbuchung.
func test_d2_stale_check_rennen_bucht_nicht_doppelt() -> void:
	_mit_pack()
	var double := StaleCheckDouble.new()
	double.state = {
		"economy": {"coins": 5000, "coinsSpent": 2500},
		"progression": {"level": 15},
		"ranch": RanchState.normalize_slice({"gekauft": true}),
	}
	assert_eq(RanchKauf.kaufe(double), RanchKauf.RESULT_OWNED, "ehrliches OWNED statt OK")
	assert_eq(int(double.state["economy"]["coins"]), 5000, "keine zweite Abbuchung")
	assert_true(double.notified.is_empty(), "kein slice_changed ohne echten Kauf")
	_teardown(null)


## (e) Registrierungs-Loch-Runde über die Module: die Boot-Registry deckt
## alle bekannten Produktions-Slices ab (ranch inklusive), und die
## DLC-Schreibpfade überleben fehlende Slice-Keys im geladenen State.
func test_e_registrierungs_loch_runde() -> void:
	GameStateScript.register_default_slices()
	for id: String in GameStateScript.DEFAULT_SLICE_SCRIPTS:
		assert_true(SaveSchema.registered_slice_ids().has(id), "Slice '%s' registriert" % id)
	assert_true(
		GameStateScript.DEFAULT_SLICE_SCRIPTS.has("ranch"),
		"ranch gehört zur Boot-Registry (W18/B1-Kern)"
	)
	# Goobye (Kauf läuft ebenfalls im Hub): Ensure-Muster hält ohne Slice-Key.
	var gs := _produktions_gs(15, 0)
	gs.update(func(state: Dictionary) -> void: state.erase(GoobyeState.SLICE_ID))
	GoobyeState.angebot_verschieben(gs)
	assert_eq(
		gs.get_value("dlc.goobye.angebotVerschoben"),
		true,
		"GoobyeState.ensure_goobye heilt den fehlenden dlc-Slice"
	)
	# McGooby (Welle A, kein Kauf): set_value-Pfad legt Zwischen-Dicts an.
	gs.update(func(state: Dictionary) -> void: state.erase(McGoobyState.SLICE_ID))
	McGoobyState.setze_intro_gesehen(gs)
	assert_eq(gs.get_value("mcgooby.introGesehen"), true, "McGooby-Pfad crasht nicht")
	_teardown(gs)
