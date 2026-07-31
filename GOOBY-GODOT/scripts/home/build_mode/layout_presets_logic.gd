class_name LayoutPresetsLogic
extends RefCounted
## Layout-Presets „Raum speichern“ (W13C, Doc D §10): pro Raum bis zu
## HomeState.PRESET_SLOTS benannte Grid-Snapshots (Items ALLER Ebenen +
## Girlanden) im Save unter `home.presets[room_id]` — ein Slot ist {} (frei)
## oder {"name", "items", "girlanden"}.
##
## Anwenden = Layout-TAUSCH mit Sicherheitsnetz (plan_apply ist PURE und
## ändert NICHTS am Eingang):
## - Preset-Möbel ohne Besitz (weder platziert noch im Lager) bleiben weg,
##   der Aufrufer zeigt den `fehlend`-Hinweis.
## - Aktuell platzierte Möbel, die das Preset nicht braucht, wandern ins
##   Lager — läuft das über die Kapazität, bricht ALLES ohne Änderung ab.
## - Alle platzierten Items bekommen frische uids (home.nextUid), damit
##   keine uid doppelt über mehrere Räume existiert.

## Ablehnungsgründe (stabile Strings für UI/Tests).
const REASON_LAGER_VOLL := "lager_voll"
const REASON_SLOT_UNGUELTIG := "slot_ungueltig"
const REASON_NAME_LEER := "name_leer"
const REASON_PRESET_LEER := "preset_leer"

const NAME_MAX := 24


## Die Preset-Slots eines Raums — immer genau PRESET_SLOTS Einträge,
## {} = freier Slot.
static func slots(gs: Object, room_id: String) -> Array:
	var raw: Variant = gs.get_value("home.presets.%s" % room_id, [])
	var out: Array = []
	for i in HomeState.PRESET_SLOTS:
		var slot: Variant = raw[i] if raw is Array and i < (raw as Array).size() else {}
		out.append(slot if slot is Dictionary else {})
	return out


## Mini-Vorschau-Info eines Slots: {"moebel": n, "girlanden": n}.
static func zusammenfassung(preset: Dictionary) -> Dictionary:
	var items: Variant = preset.get("items", [])
	var girlanden: Variant = preset.get("girlanden", [])
	return {
		"moebel": (items as Array).size() if items is Array else 0,
		"girlanden": (girlanden as Array).size() if girlanden is Array else 0,
	}


## Aktuelles Raum-Layout (Items ALLER Ebenen + Girlanden) als vollständige
## Snapshot-Kopie in `slot` speichern (überschreibt). "" = ok, sonst Grund.
static func save_slot(gs: Object, room_id: String, slot: int, name: String) -> String:
	if slot < 0 or slot >= HomeState.PRESET_SLOTS:
		return REASON_SLOT_UNGUELTIG
	var sauber := name.strip_edges().left(NAME_MAX)
	if sauber == "":
		return REASON_NAME_LEER
	var items: Variant = gs.get_value("home.rooms.%s.items" % room_id, [])
	var girlanden := HomeState.girlanden(gs, room_id)
	var preset := {
		"name": sauber,
		"items": (items as Array).duplicate(true) if items is Array else [],
		"girlanden": girlanden.duplicate(true),
	}
	_write_slot(gs, room_id, slot, preset)
	return ""


## Slot leeren. "" = ok, sonst Grund.
static func delete_slot(gs: Object, room_id: String, slot: int) -> String:
	if slot < 0 or slot >= HomeState.PRESET_SLOTS:
		return REASON_SLOT_UNGUELTIG
	_write_slot(gs, room_id, slot, {})
	return ""


## Preset anwenden: plant PURE (plan_apply), committet nur bei ok ALLES in
## einem Zug (Items + Girlanden + Lager + nextUid). Liefert das Plan-Dict
## ({"ok", "reason", "fehlend", ...}) fürs UI-Feedback.
static func apply_slot(gs: Object, room_id: String, slot: int) -> Dictionary:
	var liste := slots(gs, room_id)
	if slot < 0 or slot >= liste.size():
		return {"ok": false, "reason": REASON_SLOT_UNGUELTIG}
	var preset: Dictionary = liste[slot]
	if preset.is_empty():
		return {"ok": false, "reason": REASON_PRESET_LEER}
	var raum_def := RoomDefs.room(room_id)
	var items: Variant = gs.get_value("home.rooms.%s.items" % room_id, [])
	var plan := plan_apply(
		preset,
		items if items is Array else [],
		HomeState.girlanden(gs, room_id),
		HomeState.storage(gs),
		HomeState.storage_capacity(gs),
		FurnitureCatalog.defs(),
		raum_def.get("grid", Vector2i(8, 8)),
		RoomDefs.blocked_cells(raum_def),
		RoomDefs.wall_door_spans(raum_def),
		RoomDefs.exterior_walls(raum_def),
		int(gs.get_value("home.nextUid", 1))
	)
	if not bool(plan["ok"]):
		return plan
	gs.update(
		func(state: Dictionary) -> void:
			var home: Dictionary = state[HomeState.SLICE_ID]
			if not (home["rooms"].get(room_id) is Dictionary):
				home["rooms"][room_id] = {"items": []}
			var raum: Dictionary = home["rooms"][room_id]
			raum["items"] = plan["items"]
			raum["girlanden"] = plan["girlanden"]
			home["storage"] = plan["storage"]
			home["nextUid"] = plan["next_uid"]
	)
	gs.notify_slice_changed(HomeState.SLICE_ID)
	return plan


## PURE Tausch-Plan (mutiert KEINEN Eingang). Ergebnis bei ok:
## {"ok", "reason": "", "items", "girlanden", "storage", "fehlend",
##  "next_uid"} — bei Lager-Überlauf {"ok": false, "reason": "lager_voll"}.
static func plan_apply(
	preset: Dictionary,
	platzierte_items: Array,
	girlanden_aktuell: Array,
	storage: Array,
	capacity: int,
	defs: Dictionary,
	grid_size: Vector2i,
	blocked_cells: Array,
	doors: Dictionary,
	exterior_walls: Dictionary,
	next_uid: int
) -> Dictionary:
	# Verfügbar = Lager + alles, was gerade im Raum steht/hängt (der Tausch
	# räumt es ab). Erst DANACH bedient sich das Preset daraus.
	var pool: Array = storage.duplicate(true)
	for entry: Variant in platzierte_items:
		if entry is Dictionary and str((entry as Dictionary).get("item", "")) != "":
			StorageLogic.add(pool, str((entry as Dictionary)["item"]))
	for eintrag: Variant in girlanden_aktuell:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("typ", "")) != "":
			StorageLogic.add(pool, str((eintrag as Dictionary)["typ"]))
	var fehlend := 0
	var uid := next_uid
	var kandidaten: Array = []
	var preset_items: Variant = preset.get("items", [])
	if preset_items is Array:
		for entry: Variant in preset_items:
			if not (entry is Dictionary):
				continue
			var item_id := str((entry as Dictionary).get("item", ""))
			if item_id == "" or not StorageLogic.take(pool, item_id):
				fehlend += 1
				continue
			var gestempelt: Dictionary = (entry as Dictionary).duplicate(true)
			gestempelt["uid"] = "i-%06d" % uid
			uid += 1
			kandidaten.append(gestempelt)
	var result := GridData.from_save(
		kandidaten, defs, grid_size, blocked_cells, doors, exterior_walls
	)
	# Leftovers (Katalog-Update: Footprint passt nicht mehr, Item unbekannt)
	# bleiben weg — der Besitz wandert zurück in den Pool, nichts geht verloren.
	for leftover: Variant in result["leftovers"]:
		fehlend += 1
		if leftover is Dictionary and defs.has(str((leftover as Dictionary).get("item", ""))):
			StorageLogic.add(pool, str((leftover as Dictionary)["item"]))
	var neue_girlanden: Array = []
	var preset_girlanden: Variant = preset.get("girlanden", [])
	if preset_girlanden is Array:
		for eintrag: Variant in preset_girlanden:
			if not _girlande_anwendbar(eintrag, grid_size):
				fehlend += 1
				continue
			if not StorageLogic.take(pool, str((eintrag as Dictionary)["typ"])):
				fehlend += 1
				continue
			neue_girlanden.append((eintrag as Dictionary).duplicate(true))
	if StorageLogic.points_used(pool, defs) > capacity:
		return {"ok": false, "reason": REASON_LAGER_VOLL}
	return {
		"ok": true,
		"reason": "",
		"items": (result["grid"] as GridData).to_items_array(),
		"girlanden": neue_girlanden,
		"storage": pool,
		"fehlend": fehlend,
		"next_uid": uid,
	}


static func _girlande_anwendbar(eintrag: Variant, grid_size: Vector2i) -> bool:
	if not (eintrag is Dictionary) or str((eintrag as Dictionary).get("typ", "")) == "":
		return false
	var a := HomeState.girlande_zelle(eintrag, "zelle_a")
	var b := HomeState.girlande_zelle(eintrag, "zelle_b")
	if a == b:
		return false
	for zelle in [a, b]:
		if zelle.x < 0 or zelle.y < 0 or zelle.x >= grid_size.x or zelle.y >= grid_size.y:
			return false
	return true


static func _write_slot(gs: Object, room_id: String, slot: int, preset: Dictionary) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var home: Dictionary = state[HomeState.SLICE_ID]
			if not (home.get("presets") is Dictionary):
				home["presets"] = {}
			var liste: Variant = home["presets"].get(room_id)
			if not (liste is Array) or (liste as Array).size() != HomeState.PRESET_SLOTS:
				liste = []
				for _i in HomeState.PRESET_SLOTS:
					liste.append({})
				home["presets"][room_id] = liste
			liste[slot] = preset
	)
	gs.notify_slice_changed(HomeState.SLICE_ID)
