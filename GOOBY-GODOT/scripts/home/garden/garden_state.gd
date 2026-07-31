class_name GardenState
extends RefCounted
## Garten 2.0 — Save-Anbindung (Doc D §6). Additiv im bestehenden
## `home`-Slice unter `home.garden` (KEIN Save-Version-Bump, Doc D §1.4).
##
## Enthält die Spielzüge (pflanzen, gießen, ernten, bauen, erweitern,
## sammeln); die Regeln selbst liegen PURE in GardenGrid/GardenGrowth.
## Alle Funktionen nehmen das GameState per Duck-Typing (`gs`).
##
## ERNTE-DATENVERTRAG (Wochenmarkt = ORTE-Agent):
##   GardenState.ernte(gs) -> {cropId: menge}
##   GardenState.take_ernte(gs, crop_id, menge) -> bool
##   GardenCrops.base_price(crop_id) -> int
## Handoff: /tmp/gooby-godot/handoffs/HAUS-garden-api.md

## Erweiterungs-Stufen (Doc D §6.1) — Index = `home.garden.stufe`, Werte in
## Zellen à 1 m. Die Maximalstufe passt MIT 1 m Rand in den Garten-Raum
## (rooms.json `garden`: 28×24 Zellen à 0.5 m = 14×12 m), damit der Zaunring
## bei jeder Erweiterung sichtbar nach außen wandert, ohne die Tür-Zone zu
## überbauen.
const STUFEN: Array[Vector2i] = [Vector2i(6, 5), Vector2i(8, 6), Vector2i(10, 8), Vector2i(12, 10)]
## Preis für den Sprung auf Stufe i (Index 0 = Sprung auf Stufe 1).
const STUFEN_PREISE: Array[int] = [800, 2000, 5000]
## Sammel-Spots: so viele Stöcke liegen maximal gleichzeitig herum …
const SPOTS_MAX := 4
## … und so lange dauert es, bis ein abgesammelter Spot nachwächst (Sekunden).
const SPOT_RESPAWN_S := 3600.0
## Der eigene Baum: Sekunden bis erntereif + Holz-Ausbeute pro Ernte.
const BAUM_REIFE_S := 172800.0
const BAUM_HOLZ := 3


## Welt-Ursprung des Garten-Grids in einem Raum der Größe `raum_meter`:
## das Grid liegt IMMER mittig, damit eine Erweiterung nach allen Seiten
## wächst (PURE — GardenView und Tests rechnen mit derselben Formel).
static func world_origin(raum_meter: Vector2, size: Vector2i) -> Vector2:
	return Vector2(
		maxf(0.0, (raum_meter.x - size.x * GardenGrid.CELL_SIZE) * 0.5),
		maxf(0.0, (raum_meter.y - size.y * GardenGrid.CELL_SIZE) * 0.5)
	)


static func default_garden() -> Dictionary:
	return {
		"v": 1,
		"stufe": 0,
		"size": [STUFEN[0].x, STUFEN[0].y],
		"cells": [],
		"structures": [],
		"edges": [],
		"spots": [],
		"ernte": {},
		"baeume": {},
		"lastTickAt": 0.0,
	}


## Self-Heal (wird von HomeState.normalize_slice gerufen).
static func normalize(raw: Variant) -> Dictionary:
	var garden: Dictionary = raw if raw is Dictionary else default_garden()
	var defaults := default_garden()
	for key: String in defaults:
		if not garden.has(key):
			garden[key] = defaults[key]
	garden["stufe"] = clampi(int(garden.get("stufe", 0)), 0, STUFEN.size() - 1)
	var size: Vector2i = STUFEN[int(garden["stufe"])]
	garden["size"] = [size.x, size.y]
	for key: String in ["cells", "structures", "edges", "spots"]:
		if not (garden.get(key) is Array):
			garden[key] = []
	for key: String in ["ernte", "baeume"]:
		if not (garden.get(key) is Dictionary):
			garden[key] = {}
	return garden


static func slice(gs: Object) -> Dictionary:
	var raw: Variant = gs.get_value("home.garden", {})
	return raw if raw is Dictionary else default_garden()


static func grid(gs: Object) -> GardenGrid:
	return GardenGrid.from_save(slice(gs))


static func save_grid(gs: Object, garden_grid: GardenGrid) -> void:
	var payload := garden_grid.to_save()
	gs.update(
		func(state: Dictionary) -> void:
			var garden: Dictionary = state["home"]["garden"]
			for key: String in payload:
				garden[key] = payload[key]
	)
	gs.notify_slice_changed("home")


## Preis der nächsten Ausbaustufe (0 = maximal ausgebaut).
static func next_stufe_preis(gs: Object) -> int:
	var stufe := int(slice(gs).get("stufe", 0))
	if stufe >= STUFEN_PREISE.size():
		return 0
	return STUFEN_PREISE[stufe]


## Garten vergrößern (der Zaun-Ring wandert sichtbar nach außen).
## Der Aufrufer bucht die Münzen — hier passiert nur die Daten-Seite.
static func erweitern(gs: Object) -> bool:
	var stufe := int(slice(gs).get("stufe", 0))
	if stufe + 1 >= STUFEN.size():
		return false
	var next_size := STUFEN[stufe + 1]
	gs.update(
		func(state: Dictionary) -> void:
			var garden: Dictionary = state["home"]["garden"]
			garden["stufe"] = stufe + 1
			garden["size"] = [next_size.x, next_size.y]
	)
	gs.notify_slice_changed("home")
	return true


## Beet anlegen bzw. bepflanzen. Exoten nur im Gewächshaus (Doc D §6.2).
static func pflanzen(gs: Object, at: Vector2i, crop_id: String) -> bool:
	var garden_grid := grid(gs)
	var crop := GardenCrops.crop(crop_id)
	if crop.is_empty() or not garden_grid.in_bounds(at):
		return false
	if bool(crop["exot"]) and not garden_grid.greenhouse_cells().has(at):
		return false
	if not garden_grid.occupied_cells().is_empty() and _blockiert(garden_grid, at):
		return false
	var data := garden_grid.cell(at)
	if str(data.get("crop", "")) != "":
		return false
	(
		garden_grid
		. set_cell(
			at,
			{
				"kind": "plot",
				"crop": crop_id,
				"stage": 0,
				"progress_min": 0.0,
				"watered_until": float(data.get("watered_until", 0.0)),
			}
		)
	)
	save_grid(gs, garden_grid)
	# REST-2: Lebenszeit-Zähler für Quests/Sticker/Erinnerungen (der Key
	# existiert seit v1 im Schema, wurde aber nie gebucht).
	_bump_counter(gs, "plantings")
	return true


## Von Hand gießen (Eimer-Animation) — hält GIESS_STUNDEN.
static func giessen(gs: Object, at: Vector2i, jetzt_s: float) -> bool:
	var garden_grid := grid(gs)
	var data := garden_grid.cell(at)
	if data.is_empty():
		return false
	data["watered_until"] = jetzt_s + GardenGrowth.GIESS_STUNDEN * 3600.0
	garden_grid.set_cell(at, data)
	save_grid(gs, garden_grid)
	_bump_counter(gs, "waterings")
	return true


## Ernten: legt die Ausbeute in `home.garden.ernte` (Wochenmarkt-Vertrag)
## und – falls das Crop ein Food-Pendant hat – zusätzlich ins Essens-Inventar.
static func ernten(gs: Object, at: Vector2i) -> int:
	var garden_grid := grid(gs)
	var data := garden_grid.cell(at)
	if not GardenGrowth.ist_erntereif(data):
		return 0
	var crop := GardenCrops.crop(str(data["crop"]))
	var menge := int(crop["ernte"])
	var crop_id := str(data["crop"])
	(
		garden_grid
		. set_cell(
			at,
			{
				"kind": "plot",
				"crop": "",
				"stage": 0,
				"progress_min": 0.0,
				"watered_until": float(data.get("watered_until", 0.0)),
			}
		)
	)
	save_grid(gs, garden_grid)
	gs.update(
		func(state: Dictionary) -> void:
			var garden: Dictionary = state["home"]["garden"]
			var ernte: Dictionary = garden["ernte"]
			ernte[crop_id] = int(ernte.get(crop_id, 0)) + menge
			var food_id := str(crop["food"])
			if food_id != "":
				var food: Dictionary = state["inventory"]["food"]
				food[food_id] = int(food.get(food_id, 0)) + menge
			# W13/SAMMLUNG: jede Ernte füllt das veggies-Album-Set (Web
			# gardenInteractions.js); unmappte Crops sind ein No-Op.
			CollectionsLogic.award_in_state(
				state, "veggies", CollectionsLogic.veggie_entry_for_crop(crop_id)
			)
	)
	gs.notify_slice_changed("home")
	_bump_counter(gs, "harvests")
	return menge


## Wachstum aller Beete bis `jetzt_s` nachrechnen (Offline-Wachstum, Doc D
## §6.2). Läuft beim Betreten des Gartens; liefert, wie viele Beete eine
## Stufe weitergekommen sind. Der erste Aufruf setzt nur die Uhr.
static func tick(gs: Object, jetzt_s: float, regen := false) -> int:
	var garden_grid := grid(gs)
	var letzte := float(slice(gs).get("lastTickAt", 0.0))
	if letzte <= 0.0 or jetzt_s <= letzte:
		_stempel(gs, jetzt_s)
		return 0
	var minuten := (jetzt_s - letzte) / 60.0
	var schatten := GardenGrowth.schatten_zellen(garden_grid)
	var gewachsen := 0
	for at: Vector2i in garden_grid.plot_cells():
		var data := garden_grid.cell(at)
		if str(data.get("crop", "")) == "":
			continue
		var faktoren := GardenGrowth.faktoren(garden_grid, at, letzte, regen, schatten)
		var vorher := int(data.get("stage", 0))
		var nachher := GardenGrowth.advance(data, minuten, float(faktoren["rate"]))
		garden_grid.set_cell(at, data)
		if nachher > vorher:
			gewachsen += 1
	save_grid(gs, garden_grid)
	_stempel(gs, jetzt_s)
	return gewachsen


static func _stempel(gs: Object, jetzt_s: float) -> void:
	gs.update(func(state: Dictionary) -> void: state["home"]["garden"]["lastTickAt"] = jetzt_s)
	gs.notify_slice_changed("home")


## Erntelager (Wochenmarkt-Datenvertrag, ORTE-Agent).
static func ernte(gs: Object) -> Dictionary:
	var raw: Variant = slice(gs).get("ernte", {})
	return raw.duplicate() if raw is Dictionary else {}


## Nimmt Ernte heraus (Verkauf am Wochenmarkt). false = zu wenig da.
static func take_ernte(gs: Object, crop_id: String, menge := 1) -> bool:
	var have := int(ernte(gs).get(crop_id, 0))
	if menge <= 0 or have < menge:
		return false
	gs.update(
		func(state: Dictionary) -> void:
			var lager: Dictionary = state["home"]["garden"]["ernte"]
			if have == menge:
				lager.erase(crop_id)
			else:
				lager[crop_id] = have - menge
	)
	gs.notify_slice_changed("home")
	return true


static func _blockiert(garden_grid: GardenGrid, at: Vector2i) -> bool:
	var kind := str(garden_grid.occupied_cells().get(at, ""))
	return kind != "" and kind != "gewaechshaus"


## REST-2: Achievements-Zähler buchen + RewardHub anstoßen (Sticker/Quests
## werten Zähler-Bumps nur über note_action aus — Muster gooby_reactions.gd).
static func _bump_counter(gs: Object, key: String) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var counters: Dictionary = state.get("achievements", {}).get("counters", {})
			counters[key] = int(counters.get(key, 0)) + 1
	)
	RewardHub.note_action(gs)
