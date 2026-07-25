class_name HomeState
extends RefCounted
## Home-Slice-Anbindung (W2a HOUSE) ans GameState (W1d) — via Slice-Registry
## (W1d-Handoff §2). Alle Funktionen sind static und nehmen das GameState als
## Duck-Typing-Objekt (`/root/GameState` oder Test-Instanz).
##
## Slice-Struktur (Superset des W1d-Platzhalters, Doc D §1.4):
##   home.v, home.rooms{id:{items:[...]}}, home.unlockedRooms[],
##   home.storage[], home.storageCapacity, home.movingDay,
##   home.nextUid (Instanz-uid-Zähler), home.flags{} (Erste-Male, z. B.
##   bedPlaced — Doc D §3.1 Bett-Bauquest).
##
## M2-ERWEITERUNG (additiv, KEIN Save-Version-Bump — Doc D §1.4):
##   home.materials{} (Crafting-Material-Inventar, CraftState),
##   home.blueprints[] (gekaufte Baupläne),
##   home.shedStufe (0–3, ShedLogic → Lagerkapazität),
##   home.garden{} (Garten 2.0, GardenState),
##   home.goobay{} (Verkaufs-Cooldowns + Tagesnachfrage, GoobayState),
##   home.lieferungen[] (bestellte Möbel, DeliveryCutscene).
## Alte Saves ohne diese Keys heilen beim nächsten Load über normalize_slice.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const EconomyLogic := preload("res://scripts/logic/economy.gd")

const SLICE_ID := "home"
const DEFAULT_UNLOCKED := ["hall", "living", "kitchen", "bathroom", "bedroom"]
const FLAG_BED_PLACED := "bedPlaced"

static var _registered := false


## Registriert den home-Slice in der W1d-SaveSchema-Registry (idempotent).
## MUSS vor GameState.initialize() laufen, damit frische Saves die
## home-Felder inklusive flags/nextUid bekommen; nachträglich heilt
## normalize_slice fehlende Keys beim nächsten Load.
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {
		"v": 1,
		"rooms": {},
		"unlockedRooms": DEFAULT_UNLOCKED.duplicate(),
		"storage": [],
		"storageCapacity": ShedLogic.BASIS_KAPAZITAET,
		"movingDay": false,
		"nextUid": 1,
		"flags": {},
		"materials": {},
		"blueprints": [],
		"shedStufe": 0,
		"garden": GardenState.default_garden(),
		"goobay": GoobayState.default_goobay(),
		"lieferungen": [],
	}


## Self-Heal (W1d-normalize ruft das NACH merge_defaults): repariert Typen,
## erhält gültige Daten VERBATIM (nie Daten verlieren, Doc D §1.4).
static func normalize_slice(raw: Variant) -> Dictionary:
	var home: Dictionary = raw if raw is Dictionary else default_slice()
	home["v"] = maxi(1, int(home.get("v", 1)))
	home["nextUid"] = maxi(1, int(home.get("nextUid", 1)))
	home["storageCapacity"] = maxi(0, int(home.get("storageCapacity", 100)))
	home["movingDay"] = bool(home.get("movingDay", false))
	if not (home.get("rooms") is Dictionary):
		home["rooms"] = {}
	if not (home.get("unlockedRooms") is Array):
		home["unlockedRooms"] = DEFAULT_UNLOCKED.duplicate()
	if not (home.get("storage") is Array):
		home["storage"] = []
	if not (home.get("flags") is Dictionary):
		home["flags"] = {}
	var storage: Array = home["storage"]
	for i in range(storage.size() - 1, -1, -1):
		if not (storage[i] is Dictionary) or str(storage[i].get("item", "")) == "":
			storage.remove_at(i)
	_normalize_m2(home)
	return home


## M2-Keys nachziehen (additiv): alte Saves kannten sie noch nicht.
## `storageCapacity` bleibt bewusst der gespeicherte Wert — nur ein
## Shed-Upgrade (upgrade_shed) schreibt die ShedLogic-Kapazität hinein.
static func _normalize_m2(home: Dictionary) -> void:
	if not (home.get("materials") is Dictionary):
		home["materials"] = {}
	for key: Variant in home["materials"].keys():
		home["materials"][key] = maxi(0, int(home["materials"][key]))
	if not (home.get("blueprints") is Array):
		home["blueprints"] = []
	if not (home.get("lieferungen") is Array):
		home["lieferungen"] = []
	home["shedStufe"] = ShedLogic.clamp_stufe(int(home.get("shedStufe", 0)))
	home["garden"] = GardenState.normalize(home.get("garden"))
	home["goobay"] = GoobayState.normalize(home.get("goobay"))


## Erstbezug/Umzugstag: leere home.rooms werden mit dem liebevollen
## Default-Layout gefüllt, das Start-Lager (inkl. Bett! Doc D §3.1) kommt
## dazu. Idempotent — läuft bei jedem Home-Betreten.
static func ensure_initialized(gs: Object) -> void:
	var rooms: Variant = gs.get_value("home.rooms", {})
	if rooms is Dictionary and not rooms.is_empty():
		return
	gs.update(
		func(state: Dictionary) -> void:
			var home: Dictionary = state[SLICE_ID]
			home["rooms"] = {}
			var next_uid := maxi(1, int(home.get("nextUid", 1)))
			for room_id: String in RoomDefs.ids():
				var items: Array = []
				for entry: Dictionary in RoomDefs.default_layout(room_id):
					var stamped: Dictionary = entry.duplicate(true)
					stamped["uid"] = "i-%06d" % next_uid
					next_uid += 1
					items.append(stamped)
				home["rooms"][room_id] = {"items": items}
			home["nextUid"] = next_uid
			if not (home.get("flags") is Dictionary):
				home["flags"] = {}
			var storage: Array = home.get("storage", [])
			for entry: Dictionary in RoomDefs.default_storage():
				for _i in maxi(1, int(entry.get("count", 1))):
					StorageLogic.add(
						storage, str(entry["item"]), str(entry.get("variant", "default"))
					)
			home["storage"] = storage
			var unlocked: Array = home.get("unlockedRooms", [])
			if not unlocked.has("garden"):
				unlocked.append("garden")
	)
	gs.notify_slice_changed(SLICE_ID)


## Baut das GridData eines Raums aus dem Save; Leftovers (unbekannte Items,
## Kollisionen nach Katalog-Update) wandern automatisch ins Lager.
static func load_room_grid(gs: Object, room_id: String) -> GridData:
	var entries: Variant = gs.get_value("home.rooms.%s.items" % room_id, [])
	var result := GridData.from_save(
		entries if entries is Array else [],
		FurnitureCatalog.defs(),
		RoomDefs.room(room_id).get("grid", Vector2i(8, 8)),
		RoomDefs.blocked_cells(RoomDefs.room(room_id)),
		RoomDefs.wall_door_spans(RoomDefs.room(room_id)),
		RoomDefs.exterior_walls(RoomDefs.room(room_id))
	)
	var leftovers: Array = result["leftovers"]
	if not leftovers.is_empty():
		gs.update(
			func(state: Dictionary) -> void:
				var storage: Array = state[SLICE_ID]["storage"]
				for entry: Variant in leftovers:
					if not (entry is Dictionary):
						continue
					var item_id := str(entry.get("item", ""))
					if FurnitureCatalog.def(item_id).is_empty():
						storage.append(
							{
								"item": StorageLogic.UNKNOWN_ITEM,
								"origId": item_id,
								"variant": "default",
								"count": 1
							}
						)
					else:
						StorageLogic.add(storage, item_id)
		)
		save_room_grid(gs, room_id, result["grid"])
	return result["grid"]


## Persistiert den Grid-Zustand eines Raums (nur items — Zellen werden nie
## gespeichert, Doc D §1.4).
static func save_room_grid(gs: Object, room_id: String, grid: GridData) -> void:
	gs.set_value("home.rooms.%s.items" % room_id, grid.to_items_array())
	gs.notify_slice_changed(SLICE_ID)


static func storage(gs: Object) -> Array:
	var raw: Variant = gs.get_value("home.storage", [])
	return raw if raw is Array else []


static func storage_capacity(gs: Object) -> int:
	return int(gs.get_value("home.storageCapacity", 100))


static func storage_points_used(gs: Object) -> int:
	return StorageLogic.points_used(storage(gs), FurnitureCatalog.defs())


## Legt ein Item ins Lager. false = Kapazität voll (UI zeigt Hinweis).
static func store_item(gs: Object, item_id: String) -> bool:
	var current := storage(gs)
	if not StorageLogic.can_add(current, item_id, FurnitureCatalog.defs(), storage_capacity(gs)):
		return false
	gs.update(
		func(state: Dictionary) -> void: StorageLogic.add(state[SLICE_ID]["storage"], item_id)
	)
	gs.notify_slice_changed(SLICE_ID)
	return true


## Nimmt ein Exemplar aus dem Lager (fürs Platzieren). false = nicht da.
static func take_from_storage(gs: Object, item_id: String) -> bool:
	if StorageLogic.count_of(storage(gs), item_id) <= 0:
		return false
	gs.update(
		func(state: Dictionary) -> void: StorageLogic.take(state[SLICE_ID]["storage"], item_id)
	)
	gs.notify_slice_changed(SLICE_ID)
	return true


static func shed_stufe(gs: Object) -> int:
	return ShedLogic.clamp_stufe(int(gs.get_value("home.shedStufe", 0)))


## Shed bauen/aufwerten (Doc D §2.3): kostet Münzen, hebt die Lagerkapazität.
## Der Aufrufer spielt die Bau-Animation; hier passiert nur die Daten-Seite.
## Liefert die neue Stufe (unverändert = zu teuer oder schon Maximum).
static func upgrade_shed(gs: Object) -> int:
	var stufe := shed_stufe(gs)
	var preis := ShedLogic.upgrade_preis(stufe)
	var muenzen := int(gs.get_value("economy.coins", 0))
	if not ShedLogic.kann_upgraden(stufe, muenzen):
		return stufe
	var ziel := stufe + 1
	gs.update(
		func(state: Dictionary) -> void:
			var econ: Dictionary = state["economy"]
			if not EconomyLogic.spend(econ, preis, "shed_upgrade"):
				return
			state[SLICE_ID]["shedStufe"] = ziel
			state[SLICE_ID]["storageCapacity"] = ShedLogic.kapazitaet(ziel)
	)
	gs.notify_slice_changed(SLICE_ID)
	return shed_stufe(gs)


## Nächste Instanz-uid ("i-000042"), Zähler wird persistiert.
static func next_uid(gs: Object) -> String:
	var value := maxi(1, int(gs.get_value("home.nextUid", 1)))
	gs.set_value("home.nextUid", value + 1)
	return "i-%06d" % value


static func flag(gs: Object, name: String) -> bool:
	return bool(gs.get_value("home.flags.%s" % name, false))


static func set_flag(gs: Object, name: String, value: bool) -> void:
	gs.set_value("home.flags.%s" % name, value)
	gs.notify_slice_changed(SLICE_ID)


static func is_room_unlocked(gs: Object, room_id: String) -> bool:
	if RoomDefs.room(room_id).is_empty():
		return false
	var unlocked: Variant = gs.get_value("home.unlockedRooms", DEFAULT_UNLOCKED)
	return (unlocked is Array and unlocked.has(room_id)) or room_id == "garden"


## Nur für Tests: Registry-Status zurücksetzen (SaveSchema.unregister_slice
## muss der Test selbst rufen, falls gewünscht).
static func reset_for_tests() -> void:
	_registered = false
