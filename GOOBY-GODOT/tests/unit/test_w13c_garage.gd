extends TestCase
## W13C — Garage mit Rolltor (Doc D §7) + Layout-Presets „Raum speichern"
## (Doc D §10): Kauf-Gate + Save-Roundtrip, Rolltor-Zustandsmaschine,
## Auto-in-Garage folgt dem Autohaus-Save, Preset-Roundtrip (identisches
## Layout), Sicherheitsnetz (fehlender Besitz, Lager-Überlauf → Abbruch ohne
## Datenverlust) und Preset-Normalisierung — plus zwei Szenen-Flows durch
## Garten (bauen/Tor/Abfahrt) und Baumodus (Preset-Sheet).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000

var _seq := 0
var _pfad := ""


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w13c_garage_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	_pfad = dir + "/save_v5.json"
	gs.initialize(_pfad)
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	HomeState.reset_for_tests()
	CityState.reset_for_tests()


func _open_room(gs: Node, scene_path: String) -> RoomBase:
	var scene: PackedScene = load(scene_path)
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	tree.root.add_child(room)
	await wait_frames(4)
	return room


func _cleanup_room(room: Node, gs: Node) -> void:
	if room != null:
		room.queue_free()
	await wait_frames(2)
	_teardown(gs)


## Save-Einträge für ein Wohnzimmer-Layout über alle Ebenen (Positionen
## mittig, weit weg von Tür-Freihaltezonen des 12×10-living-Grids).
func _wohn_layout() -> Array:
	return [
		{"uid": "i-000001", "item": "chair", "at": [5, 5], "rot": 0},
		{"uid": "i-000002", "item": "sideTable", "at": [7, 5], "rot": 0},
		{"uid": "i-000003", "item": "plantSmall1", "at": [7, 5], "rot": 0},
		{"uid": "i-000004", "item": "lampSquareCeiling", "at": [5, 3], "rot": 0},
	]


## Vergleichbarer Layout-Fingerabdruck (uid-frei: die werden neu gestempelt).
func _layout_signatur(items: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in items:
		out.append("%s@%s r%d" % [entry["item"], str(entry["at"]), int(entry.get("rot", 0))])
	out.sort()
	return out


# ── (a) Garage: Zustandsmaschine, Kauf-Gate, Save-Roundtrip ─────────────────


func test_rolltor_zustandsmaschine() -> void:
	assert_eq(GarageLogic.rolltor_toggle(GarageLogic.ROLLTOR_ZU), GarageLogic.ROLLTOR_OEFFNET)
	assert_eq(GarageLogic.rolltor_toggle(GarageLogic.ROLLTOR_OFFEN), GarageLogic.ROLLTOR_SCHLIESST)
	assert_eq(
		GarageLogic.rolltor_toggle(GarageLogic.ROLLTOR_OEFFNET),
		GarageLogic.ROLLTOR_SCHLIESST,
		"Toggle mitten im Öffnen kehrt um"
	)
	assert_eq(
		GarageLogic.rolltor_toggle(GarageLogic.ROLLTOR_SCHLIESST),
		GarageLogic.ROLLTOR_OEFFNET,
		"Toggle mitten im Schließen kehrt um"
	)
	assert_eq(GarageLogic.rolltor_ende(GarageLogic.ROLLTOR_OEFFNET), GarageLogic.ROLLTOR_OFFEN)
	assert_eq(GarageLogic.rolltor_ende(GarageLogic.ROLLTOR_SCHLIESST), GarageLogic.ROLLTOR_ZU)
	assert_eq(
		GarageLogic.rolltor_ende(GarageLogic.ROLLTOR_ZU),
		GarageLogic.ROLLTOR_ZU,
		"Ruhezustände bleiben liegen"
	)
	assert_almost(GarageLogic.rolltor_ziel_anteil(GarageLogic.ROLLTOR_OEFFNET), 1.0)
	assert_almost(GarageLogic.rolltor_ziel_anteil(GarageLogic.ROLLTOR_OFFEN), 1.0)
	assert_almost(GarageLogic.rolltor_ziel_anteil(GarageLogic.ROLLTOR_SCHLIESST), 0.0)
	assert_almost(GarageLogic.rolltor_ziel_anteil(GarageLogic.ROLLTOR_ZU), 0.0)
	assert_true(GarageLogic.rolltor_ist_offen(GarageLogic.ROLLTOR_OFFEN))
	assert_false(
		GarageLogic.rolltor_ist_offen(GarageLogic.ROLLTOR_OEFFNET), "erst GANZ offen zählt"
	)


func test_garage_kauf_gate() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	assert_eq(GarageLogic.footprint(), Vector2i(2, 3), "2×3 wie im GardenGrid registriert")
	assert_false(GarageLogic.gebaut(gs), "frisch: keine Garage")
	gs.set_value("economy.coins", GarageLogic.PREIS - 1)
	var zu_teuer := GarageLogic.kaufen(gs, Vector2i(0, 0))
	assert_false(zu_teuer["ok"])
	assert_eq(str(zu_teuer["reason"]), GarageLogic.REASON_ZU_TEUER)
	assert_false(GarageLogic.gebaut(gs), "abgelehnter Kauf platziert nichts")
	gs.set_value("economy.coins", GarageLogic.PREIS + 300)
	var oob := GarageLogic.kaufen(gs, Vector2i(90, 0))
	assert_eq(str(oob["reason"]), GardenGrid.REASON_OOB, "Platz-Prüfung greift VOR dem Geld")
	assert_eq(int(gs.get_value("economy.coins", 0)), GarageLogic.PREIS + 300, "nichts abgebucht")
	assert_true(GarageLogic.kaufen(gs, Vector2i(0, 0))["ok"])
	assert_true(GarageLogic.gebaut(gs))
	assert_eq(int(gs.get_value("economy.coins", 0)), 300, "Preis exakt abgebucht")
	assert_eq(GarageLogic.struktur(gs).get("at", Vector2i(-1, -1)), Vector2i(0, 0))
	var nochmal := GarageLogic.kaufen(gs, Vector2i(3, 0))
	assert_false(nochmal["ok"])
	assert_eq(str(nochmal["reason"]), GarageLogic.REASON_SCHON_GEBAUT, "einmaliges Upgrade")
	assert_eq(int(gs.get_value("economy.coins", 0)), 300, "zweiter Versuch kostet nichts")
	_teardown(gs)


func test_garage_save_roundtrip() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	gs.set_value("economy.coins", GarageLogic.PREIS)
	assert_true(GarageLogic.kaufen(gs, Vector2i(1, 1))["ok"])
	assert_true(gs.save_now(), "Save geht raus")
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW_MS)
	gs2.initialize(_pfad)
	assert_true(GarageLogic.gebaut(gs2), "Garage überlebt den Roundtrip")
	var eintrag := GarageLogic.struktur(gs2)
	assert_eq(str(eintrag.get("kind", "")), GarageLogic.KIND)
	assert_eq(eintrag.get("at", Vector2i(-1, -1)), Vector2i(1, 1), "Position identisch")
	gs2.free()
	_teardown(gs)


func test_auto_in_garage_folgt_autohaus_save() -> void:
	var gs := _fresh_gs()
	var start_id := AutoKatalog.start_auto_id()
	var prop := GarageProp.create(gs)
	assert_eq(prop.auto_id(), start_id, "ohne Kauf parkt der Start-Wagen")
	assert_true(prop.auto_node() != null, "Auto steht sichtbar drin")
	assert_true(prop.rolltor() != null, "Rolltor-Node existiert (GLB oder Fallback)")
	prop.free()
	AutoKatalog.eintragen(gs, "suv", "#4FBF8B")
	var prop2 := GarageProp.create(gs)
	assert_eq(prop2.auto_id(), "suv", "Kauf macht den Neuen aktiv — Garage folgt")
	prop2.free()
	AutoKatalog.waehle(gs, start_id)
	var prop3 := GarageProp.create(gs)
	assert_eq(prop3.auto_id(), start_id, "Wechsel im Autohaus wechselt das Garagen-Auto")
	prop3.free()
	_teardown(gs)


func test_garage_prop_rolltor_und_reduzierte_abfahrt() -> void:
	var gs := _fresh_gs()
	var prop := GarageProp.create(gs)
	tree.root.add_child(prop)
	await wait_frames(1)
	assert_true(
		tree.get_first_node_in_group(GarageProp.GRUPPE) == prop,
		"Prop meldet sich in der Gruppe (Abfahrt-Hook findet ihn)"
	)
	prop.set_rolltor_anteil(0.0)
	assert_almost(prop.rolltor().scale.y, 1.0, 1e-6, "zu = Blatt voll ausgefahren")
	prop.set_rolltor_anteil(1.0)
	assert_almost(
		prop.rolltor().scale.y, GarageProp.TOR_MIN_SCALE, 1e-6, "offen = aufgerollt (Restwickel)"
	)
	prop.set_rolltor_anteil(0.0)
	var z_vorher: float = prop.auto_node().position.z
	await prop.abfahrt_spielen(true)
	assert_almost(
		prop.rolltor().scale.y, GarageProp.TOR_MIN_SCALE, 1e-6, "Reduced Motion: Tor sofort offen"
	)
	assert_true(prop.auto_node().position.z > z_vorher, "Auto ist rausgefahren")
	assert_false(prop.abfahrt_laeuft(), "Sequenz sauber beendet")
	prop.queue_free()
	await wait_frames(2)
	_teardown(gs)


func test_abfahrt_hook_ohne_garage_noop() -> void:
	var gs := _fresh_gs()
	var kontext := Node.new()
	tree.root.add_child(kontext)
	await GarageAbfahrt.vielleicht_abspielen(kontext, gs)
	assert_false(GarageLogic.gebaut(gs), "kein Kauf durch den Hook")
	await GarageAbfahrt.vielleicht_abspielen(null, gs)
	await GarageAbfahrt.vielleicht_abspielen(kontext, null)
	kontext.queue_free()
	await wait_frames(2)
	_teardown(gs)


# ── (b) Layout-Presets: Roundtrip, Sicherheitsnetz, Normalisierung ──────────


func test_preset_save_apply_roundtrip() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	gs.set_value("home.rooms.living.items", _wohn_layout())
	gs.set_value("home.nextUid", 10)
	gs.update(
		func(state: Dictionary) -> void:
			StorageLogic.add(state["home"]["storage"], "girlande_wimpel")
	)
	assert_true(
		HomeState.add_girlande(gs, "living", "girlande_wimpel", Vector2i(2, 2), Vector2i(6, 2))
	)
	assert_eq(
		LayoutPresetsLogic.save_slot(gs, "living", 0, "  Wohnstube  "), "", "Speichern klappt"
	)
	var slot: Dictionary = LayoutPresetsLogic.slots(gs, "living")[0]
	assert_eq(str(slot["name"]), "Wohnstube", "Name getrimmt")
	var kurz := LayoutPresetsLogic.zusammenfassung(slot)
	assert_eq(int(kurz["moebel"]), 4, "Mini-Vorschau: 4 Möbel")
	assert_eq(int(kurz["girlanden"]), 1, "Mini-Vorschau: 1 Girlande")
	var vorher := _layout_signatur(gs.get_value("home.rooms.living.items", []))
	# ensure_initialized legt Starter-Möbel ins Lager — netto muss der Tausch
	# daran nichts ändern (alles Preset-Material kommt aus dem Raum selbst).
	var punkte_vorher := StorageLogic.points_used(HomeState.storage(gs), FurnitureCatalog.defs())
	var plan := LayoutPresetsLogic.apply_slot(gs, "living", 0)
	assert_true(plan["ok"], "Anwenden aufs identische Layout klappt")
	assert_eq(int(plan["fehlend"]), 0, "nichts fehlt")
	var nachher_items: Array = gs.get_value("home.rooms.living.items", [])
	assert_eq(_layout_signatur(nachher_items), vorher, "identisches Grid über ALLE Ebenen")
	for entry: Dictionary in nachher_items:
		assert_true(int(str(entry["uid"]).trim_prefix("i-")) >= 10, "uids frisch gestempelt")
	assert_true(int(gs.get_value("home.nextUid", 0)) >= 14, "uid-Zähler weitergedreht")
	var girlanden := HomeState.girlanden(gs, "living")
	assert_eq(girlanden.size(), 1, "Girlande wieder gespannt")
	assert_eq(HomeState.girlande_zelle(girlanden[0], "zelle_a"), Vector2i(2, 2))
	assert_eq(HomeState.girlande_zelle(girlanden[0], "zelle_b"), Vector2i(6, 2))
	assert_eq(
		StorageLogic.points_used(HomeState.storage(gs), FurnitureCatalog.defs()),
		punkte_vorher,
		"Lager netto unverändert (alles wieder verbaut)"
	)
	assert_true(gs.save_now())
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW_MS)
	gs2.initialize(_pfad)
	var slot2: Dictionary = LayoutPresetsLogic.slots(gs2, "living")[0]
	assert_eq(str(slot2.get("name", "")), "Wohnstube", "Preset überlebt den Save-Roundtrip")
	gs2.free()
	_teardown(gs)


func test_preset_fehlender_besitz_bleibt_weg() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	(
		gs
		. set_value(
			"home.rooms.living.items",
			[
				{"uid": "i-000001", "item": "chair", "at": [5, 5], "rot": 0},
				{"uid": "i-000002", "item": "sideTable", "at": [7, 5], "rot": 0},
			]
		)
	)
	assert_eq(LayoutPresetsLogic.save_slot(gs, "living", 1, "Duo"), "")
	# Beistelltisch „verkauft": raus aus dem Raum, NICHT ins Lager.
	gs.set_value(
		"home.rooms.living.items", [{"uid": "i-000001", "item": "chair", "at": [5, 5], "rot": 0}]
	)
	var plan := LayoutPresetsLogic.apply_slot(gs, "living", 1)
	assert_true(plan["ok"], "Tausch läuft trotz Lücke durch")
	assert_eq(int(plan["fehlend"]), 1, "genau 1 Teil fehlt (Hinweis fürs UI)")
	var items: Array = gs.get_value("home.rooms.living.items", [])
	assert_eq(_layout_signatur(items), ["chair@[5, 5] r0"], "Stuhl steht, Tisch bleibt weg")
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "sideTable"), 0, "kein Phantom-Besitz im Lager"
	)
	_teardown(gs)


func test_preset_lager_ueberlauf_abbruch_ohne_datenverlust() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	gs.set_value(
		"home.rooms.living.items", [{"uid": "i-000001", "item": "chair", "at": [5, 5], "rot": 0}]
	)
	assert_eq(LayoutPresetsLogic.save_slot(gs, "living", 0, "NurStuhl"), "")
	# Jetzt steht MEHR im Raum als das Preset braucht — der Rest müsste ins
	# Lager, aber die Kapazität ist 0 → Abbruch, NICHTS ändert sich.
	var voller_raum := [
		{"uid": "i-000001", "item": "chair", "at": [5, 5], "rot": 0},
		{"uid": "i-000002", "item": "sideTable", "at": [7, 5], "rot": 0},
	]
	gs.set_value("home.rooms.living.items", voller_raum.duplicate(true))
	gs.set_value("home.storageCapacity", 0)
	var uid_vorher := int(gs.get_value("home.nextUid", 1))
	var lager_vorher := str(HomeState.storage(gs))
	var plan := LayoutPresetsLogic.apply_slot(gs, "living", 0)
	assert_false(plan["ok"], "Überlauf bricht ab")
	assert_eq(str(plan["reason"]), LayoutPresetsLogic.REASON_LAGER_VOLL)
	assert_eq(
		_layout_signatur(gs.get_value("home.rooms.living.items", [])),
		_layout_signatur(voller_raum),
		"Raum unangetastet — kein Datenverlust"
	)
	assert_eq(str(HomeState.storage(gs)), lager_vorher, "Lager unangetastet")
	assert_eq(int(gs.get_value("home.nextUid", 1)), uid_vorher, "uid-Zähler unangetastet")
	_teardown(gs)


func test_preset_slots_namen_und_loeschen() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	assert_eq(LayoutPresetsLogic.slots(gs, "living").size(), HomeState.PRESET_SLOTS)
	assert_eq(
		LayoutPresetsLogic.save_slot(gs, "living", -1, "X"),
		LayoutPresetsLogic.REASON_SLOT_UNGUELTIG
	)
	assert_eq(
		LayoutPresetsLogic.save_slot(gs, "living", HomeState.PRESET_SLOTS, "X"),
		LayoutPresetsLogic.REASON_SLOT_UNGUELTIG,
		"nur 3 Slots pro Raum"
	)
	assert_eq(
		LayoutPresetsLogic.save_slot(gs, "living", 0, "   "),
		LayoutPresetsLogic.REASON_NAME_LEER,
		"Name ist Pflicht"
	)
	var lang := "X".repeat(LayoutPresetsLogic.NAME_MAX + 10)
	assert_eq(LayoutPresetsLogic.save_slot(gs, "living", 2, lang), "")
	var slot: Dictionary = LayoutPresetsLogic.slots(gs, "living")[2]
	assert_eq(str(slot["name"]).length(), LayoutPresetsLogic.NAME_MAX, "Name gekappt")
	assert_eq(
		str(LayoutPresetsLogic.apply_slot(gs, "living", 0)["reason"]),
		LayoutPresetsLogic.REASON_PRESET_LEER,
		"leeren Slot anwenden geht nicht"
	)
	assert_eq(LayoutPresetsLogic.delete_slot(gs, "living", 2), "")
	assert_true(
		(LayoutPresetsLogic.slots(gs, "living")[2] as Dictionary).is_empty(), "Slot wieder frei"
	)
	assert_eq(
		LayoutPresetsLogic.delete_slot(gs, "living", 9), LayoutPresetsLogic.REASON_SLOT_UNGUELTIG
	)
	_teardown(gs)


func test_preset_normalisierung_heilt_kaputte_daten() -> void:
	var healed := (
		HomeState
		. normalize_slice(
			{
				"presets":
				{
					"living":
					[
						{
							"name": "Ok",
							"items": [{"item": "chair", "at": [1, 1]}, "müll", {"kein_item": 1}],
							"girlanden":
							[
								{"typ": "girlande_wimpel", "zelle_a": [1, 1], "zelle_b": [4, 1]},
								{"typ": "", "zelle_a": [0, 0], "zelle_b": [1, 1]},
							]
						},
						{"items": "kein_array"},
						"müll",
						{"name": "ZuViel"},
					],
					"bedroom": "kein_array",
				}
			}
		)
	)
	var presets: Dictionary = healed["presets"]
	var living: Array = presets["living"]
	assert_eq(living.size(), HomeState.PRESET_SLOTS, "überzählige Slots gekappt")
	var ok_slot: Dictionary = living[0]
	assert_eq(str(ok_slot["name"]), "Ok")
	assert_eq((ok_slot["items"] as Array).size(), 1, "nur der gültige Item-Eintrag überlebt")
	assert_eq((ok_slot["girlanden"] as Array).size(), 1, "nur die gültige Girlande überlebt")
	assert_true((living[1] as Dictionary).is_empty(), "Slot ohne Namen → frei")
	var bedroom: Array = presets["bedroom"]
	assert_eq(bedroom.size(), HomeState.PRESET_SLOTS, "kaputter Raum → 3 freie Slots")
	for slot: Dictionary in bedroom:
		assert_true(slot.is_empty())
	var ohne := HomeState.normalize_slice({"presets": "müll"})
	assert_true(ohne["presets"] is Dictionary and (ohne["presets"] as Dictionary).is_empty())
	assert_true(HomeState.default_slice()["presets"] is Dictionary, "Default-Slice hat presets")


func test_plan_apply_mutiert_eingaenge_nicht() -> void:
	var defs := FurnitureCatalog.defs()
	var preset := {
		"name": "P",
		"items": [{"uid": "i-000001", "item": "chair", "at": [2, 2], "rot": 0}],
		"girlanden": [{"typ": "girlande_wimpel", "zelle_a": [0, 0], "zelle_b": [3, 0]}],
	}
	var platziert: Array = [{"uid": "i-000009", "item": "sideTable", "at": [4, 4], "rot": 0}]
	var girlanden: Array = []
	var storage: Array = [{"item": "chair", "count": 1, "variant": "default"}]
	var kopien := [str(preset), str(platziert), str(girlanden), str(storage)]
	var plan := LayoutPresetsLogic.plan_apply(
		preset, platziert, girlanden, storage, 100, defs, Vector2i(8, 8), [], {}, {}, 50
	)
	assert_true(plan["ok"])
	assert_eq(
		int(plan["fehlend"]), 1, "Girlande ohne Besitz im Pool fehlt — Möbel-Tausch läuft trotzdem"
	)
	assert_eq(int(plan["next_uid"]), 51, "genau 1 uid verbraucht")
	assert_eq(str(preset), kopien[0], "PURE: Preset unangetastet")
	assert_eq(str(platziert), kopien[1], "PURE: platzierte Items unangetastet")
	assert_eq(str(girlanden), kopien[2], "PURE: Girlanden unangetastet")
	assert_eq(str(storage), kopien[3], "PURE: Lager unangetastet")
	var kaputt := LayoutPresetsLogic.plan_apply(
		{
			"name": "G",
			"items": [],
			"girlanden": [{"typ": "girlande_wimpel", "zelle_a": [0, 0], "zelle_b": [99, 0]}]
		},
		[],
		[{"typ": "girlande_wimpel", "zelle_a": [0, 0], "zelle_b": [3, 0]}],
		[],
		100,
		defs,
		Vector2i(8, 8),
		[],
		{},
		{},
		1
	)
	assert_true(kaputt["ok"])
	assert_eq(int(kaputt["fehlend"]), 1, "Girlande außerhalb der Bounds bleibt weg")
	assert_eq((kaputt["girlanden"] as Array).size(), 0)


# ── Szenen-Flows: Garten (bauen/Tor/Abfahrt) + Baumodus (Preset-Sheet) ───────


func test_garten_szene_garage_bauen_rolltor_abfahrt() -> void:
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/garten.tscn")
	var host: GardenHost = room.get_node("GardenHost")
	gs.set_value("economy.coins", GarageLogic.PREIS + 500)
	var grid := GardenState.grid(gs)
	var frei := Vector2i(-1, -1)
	for y in grid.size.y:
		for x in grid.size.x:
			if bool(grid.can_place_structure(GarageLogic.KIND, Vector2i(x, y))["ok"]):
				frei = Vector2i(x, y)
				break
		if frei.x >= 0:
			break
	assert_true(frei.x >= 0, "Default-Garten hat Platz für die 2×3-Garage")
	host.select_cell(frei)
	assert_true(await host.garage_bauen(), "Kauf-Flow inkl. Bau-Animation läuft durch")
	assert_true(GarageLogic.gebaut(gs), "Garage im Save")
	await wait_frames(2)
	var props := room.find_children("*", "GarageProp", true, false)
	assert_true(props.size() >= 1, "Baukörper steht im Garten")
	assert_eq(host.rolltor_zustand(), GarageLogic.ROLLTOR_ZU, "Tor startet zu")
	host.select_cell(frei)
	assert_eq(host.rolltor_zustand(), GarageLogic.ROLLTOR_OEFFNET, "Tap aufs Tor öffnet")
	assert_true(
		await wait_until(
			func() -> bool: return host.rolltor_zustand() == GarageLogic.ROLLTOR_OFFEN, 4000
		),
		"Roll-Animation endet im Zustand offen"
	)
	host.rolltor_toggle()
	assert_eq(host.rolltor_zustand(), GarageLogic.ROLLTOR_SCHLIESST, "zweiter Tap schließt")
	assert_true(
		await wait_until(
			func() -> bool: return host.rolltor_zustand() == GarageLogic.ROLLTOR_ZU, 4000
		)
	)
	# „Freie Fahrt"-Hook (home_entry ruft exakt das hier vor dem Stadt-Wechsel).
	# Prop NEU greifen: die select_cell-Refreshes haben die View neu gebaut.
	var prop: GarageProp = null
	for node in tree.get_nodes_in_group(GarageProp.GRUPPE):
		if node is GarageProp and not node.is_queued_for_deletion():
			prop = node
	assert_true(prop != null, "lebender Garage-Prop im Baum")
	var z_vorher: float = prop.auto_node().position.z
	await GarageAbfahrt.vielleicht_abspielen(room, gs)
	assert_true(prop.auto_node().position.z > z_vorher, "Abfahrt: Auto fährt raus")
	assert_false(prop.abfahrt_laeuft())
	await _cleanup_room(room, gs)


func test_preset_sheet_im_baumodus() -> void:
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/wohnzimmer.tscn")
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	gs.set_value("home.rooms.living.items", _wohn_layout())
	gs.set_value("home.nextUid", 50)
	var build: BuildMode = room.get_node("BuildMode")
	build.reload_grid_from_save()
	assert_eq(room.grid.item_at(Vector2i(5, 5), GridData.Layer.FLOOR), "i-000001", "Grid geladen")
	build.open()
	await wait_frames(4)
	build._open_presets()
	await wait_frames(2)
	var sheets := room.find_children("*", "PresetSheet", true, false)
	assert_eq(sheets.size(), 1, "Preset-Sheet liegt im UI-Layer")
	var sheet: PresetSheet = sheets[0]
	assert_false(sheet.speichern(0), "ohne Namen kein Speichern")
	sheet._name_feld.text = "Wohnstube"
	assert_true(sheet.speichern(0), "mit Namen klappt es")
	var slot: Dictionary = LayoutPresetsLogic.slots(gs, "living")[0]
	assert_eq(str(slot["name"]), "Wohnstube")
	var angewendet_fehlend := [-1]
	sheet.angewendet.connect(func(fehlend: int) -> void: angewendet_fehlend[0] = fehlend)
	assert_true(sheet.anwenden(0), "Anwenden läuft durch")
	await wait_frames(2)
	assert_eq(angewendet_fehlend[0], 0, "Signal meldet 0 fehlende Teile")
	assert_ne(
		room.grid.item_at(Vector2i(5, 5), GridData.Layer.FLOOR),
		"",
		"Stuhl steht nach dem Tausch wieder (In-Place-Reload)"
	)
	assert_ne(
		room.grid.item_at(Vector2i(5, 3), GridData.Layer.CEILING),
		"",
		"Deckenlampe hängt wieder (alle Ebenen)"
	)
	assert_ne(
		room.grid.item_at(Vector2i(5, 5), GridData.Layer.FLOOR), "i-000001", "uid frisch gestempelt"
	)
	build.close()
	await _cleanup_room(room, gs)
