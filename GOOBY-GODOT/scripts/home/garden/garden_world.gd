class_name GardenWorld
extends RefCounted
## Garten-„Weltzustand“ (Doc D §5.1/§6.1): Sammel-Spots für Stöcke/Blätter,
## der eigene Baum (Holz-Quelle) und der Kauf von Garten-Bauten
## (Werkstatt/Gewächshaus/Bewässerungsanlage/Shed).
##
## Trennung zu GardenState: dort liegen Beete/Ernte/Erweiterung, hier alles,
## was Material bringt oder Münzen kostet. Beide schreiben in `home.garden`.

const Economy := preload("res://scripts/logic/economy.gd")

## Diese Bauten kann man kaufen (Preise: CraftMaterials.baumarkt_angebot()).
const KAUFBAR: Array[String] = ["werkstatt", "gewaechshaus", "sprinkler", "baum"]
## Was auf einem Sammel-Spot liegen kann (Doc D §5.1).
const SPOT_MATERIALIEN: Array[String] = ["stock", "stock", "stock", "blatt"]


## W13/WETTER-FX: Sichtbares Wetter im Garten — hängt die geteilte
## WetterFx-Komponente an den Garten-Raum (idempotent, nur room_id
## "garden"). Der Plan kommt IMMER aus SoulWetter (deterministisch; Datum/
## Stunde für Tests injizierbar, sonst Systemuhr bzw. das
## `stunde_override` des Raums). Der Garten NUTZT Regen schon fürs Gießen
## (GardenGrowth.wasser_faktor) — jetzt sieht man ihn auch.
## Aufruf-Wiring: GardenHost.setup (Request, s. W13-requests.md).
static func wetter_fx_anhaengen(room: Node, datum := "", stunde := -1.0) -> WetterFx:
	if room == null or str(room.get("room_id")) != "garden":
		return null
	var vorhanden := room.get_node_or_null("WetterFx")
	if vorhanden is WetterFx:
		return vorhanden
	var tag := datum if not datum.is_empty() else RanchWetter.datum_heute()
	var h := stunde
	if h < 0.0 and room.get("stunde_override") != null:
		h = float(room.get("stunde_override"))
	if h < 0.0:
		var jetzt := Time.get_time_dict_from_system()
		h = float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0
	var zellen: Vector2i = RoomDefs.room("garden").get("grid", Vector2i(28, 24))
	var groesse := Vector2(zellen.x * GridData.CELL_SIZE, zellen.y * GridData.CELL_SIZE)
	var fx := WetterFx.new()
	fx.name = "WetterFx"
	fx.extents = Vector3(groesse.x * 0.6, 2.0, groesse.y * 0.6)
	fx.hoehe = 12.0
	fx.seed_wert = RanchWetter.tages_seed(tag, SoulWetter.HOME_SEED)
	room.add_child(fx)
	fx.position = Vector3(groesse.x * 0.5, 0.0, groesse.y * 0.5)
	fx.wende_zustand_an(SoulWetter.zustand(tag, h))
	return fx


## Spawnt fehlende Sammel-Spots auf freien Zellen und lässt abgesammelte
## nachwachsen. Idempotent — läuft bei jedem Garten-Betreten.
static func refresh_spots(gs: Object, jetzt_s: float, rng: RandomNumberGenerator) -> void:
	var garden_grid := GardenState.grid(gs)
	var frei := garden_grid.free_cells()
	if frei.is_empty():
		return
	gs.update(
		func(state: Dictionary) -> void:
			var garden: Dictionary = state["home"]["garden"]
			var spots: Array = garden["spots"]
			for entry: Variant in spots:
				if entry is Dictionary and bool(entry.get("leer", false)):
					if float(entry.get("ready_at", 0.0)) <= jetzt_s:
						entry["leer"] = false
						entry["material"] = SPOT_MATERIALIEN[rng.randi_range(
							0, SPOT_MATERIALIEN.size() - 1
						)]
			var belegt: Dictionary = {}
			for entry: Variant in spots:
				if entry is Dictionary:
					belegt[str(entry.get("at", []))] = true
			while spots.size() < GardenState.SPOTS_MAX and not frei.is_empty():
				var cell: Vector2i = frei[rng.randi_range(0, frei.size() - 1)]
				var key := str([cell.x, cell.y])
				if belegt.has(key):
					frei.erase(cell)
					continue
				belegt[key] = true
				(
					spots
					. append(
						{
							"at": [cell.x, cell.y],
							"material":
							SPOT_MATERIALIEN[rng.randi_range(0, SPOT_MATERIALIEN.size() - 1)],
							"leer": false,
							"ready_at": 0.0,
						}
					)
				)
	)
	gs.notify_slice_changed("home")


## Alle aktuell sichtbaren Spots ([{at: Vector2i, material: String}]).
static func offene_spots(gs: Object) -> Array:
	var out: Array = []
	for entry: Variant in GardenState.slice(gs).get("spots", []):
		if not (entry is Dictionary) or bool(entry.get("leer", false)):
			continue
		var at: Array = entry.get("at", [0, 0])
		out.append(
			{
				"at": Vector2i(int(at[0]), int(at[1])),
				"material": str(entry.get("material", "stock"))
			}
		)
	return out


## Spot aufsammeln (Gooby-Bück-Animation) — legt das Material ins
## Material-Inventar und startet den Respawn-Timer. "" = da lag nichts.
static func sammeln(gs: Object, at: Vector2i, jetzt_s: float) -> String:
	var gefunden := ""
	for entry: Dictionary in offene_spots(gs):
		if entry["at"] == at:
			gefunden = str(entry["material"])
			break
	if gefunden == "":
		return ""
	gs.update(
		func(state: Dictionary) -> void:
			for entry: Variant in state["home"]["garden"]["spots"]:
				if not (entry is Dictionary):
					continue
				var spot_at: Array = entry.get("at", [0, 0])
				if Vector2i(int(spot_at[0]), int(spot_at[1])) == at:
					entry["leer"] = true
					entry["ready_at"] = jetzt_s + GardenState.SPOT_RESPAWN_S
			CraftLogic.add(state["home"]["materials"], gefunden, 1)
	)
	gs.notify_slice_changed("home")
	return gefunden


## Baut ein Garten-Bauwerk gegen Münzen (Bau-Animation macht der Aufrufer).
## Liefert {"ok", "reason"} — reason wie GardenGrid plus "zu_teuer".
static func bauen(
	gs: Object, kind: String, at: Vector2i, rot := 0, door := Vector2i(-1, -1)
) -> Dictionary:
	if not KAUFBAR.has(kind):
		return {"ok": false, "reason": GardenGrid.REASON_UNKNOWN}
	var garden_grid := GardenState.grid(gs)
	var check := garden_grid.can_place_structure(kind, at, rot, door)
	if not check["ok"]:
		return check
	var preis := CraftMaterials.baumarkt_preis("struktur", kind)
	if int(gs.get_value("economy.coins", 0)) < preis:
		return {"ok": false, "reason": "zu_teuer"}
	garden_grid.place_structure(kind, at, rot, door)
	GardenState.save_grid(gs, garden_grid)
	gs.update(
		func(state: Dictionary) -> void:
			Economy.spend(state["economy"], preis, "garten_bau")
			if kind == "baum":
				state["home"]["garden"]["baeume"][_key(at)] = 0.0
	)
	gs.notify_slice_changed("home")
	return {"ok": true, "reason": GardenGrid.REASON_OK}


## Frisch gepflanzter/geernteter Baum: Reifezeit läuft ab `jetzt_s`.
static func baum_stempeln(gs: Object, at: Vector2i, jetzt_s: float) -> void:
	gs.update(
		func(state: Dictionary) -> void: state["home"]["garden"]["baeume"][_key(at)] = jetzt_s
	)
	gs.notify_slice_changed("home")


static func baum_reif(gs: Object, at: Vector2i, jetzt_s: float) -> bool:
	var baeume: Variant = GardenState.slice(gs).get("baeume", {})
	if not (baeume is Dictionary) or not baeume.has(_key(at)):
		return false
	return jetzt_s - float(baeume[_key(at)]) >= GardenState.BAUM_REIFE_S


## Holz ernten (kein Fällen — der Baum wächst nach). 0 = noch nicht reif.
static func baum_ernten(gs: Object, at: Vector2i, jetzt_s: float) -> int:
	if not baum_reif(gs, at, jetzt_s):
		return 0
	gs.update(
		func(state: Dictionary) -> void:
			CraftLogic.add(state["home"]["materials"], "holz", GardenState.BAUM_HOLZ)
			state["home"]["garden"]["baeume"][_key(at)] = jetzt_s
	)
	gs.notify_slice_changed("home")
	return GardenState.BAUM_HOLZ


## Zaun-Kante setzen (verbraucht ein `fence`-Item aus dem Lager).
static func zaun_setzen(
	gs: Object, from: Vector2i, dir: String, laenge: int, fence := "fence_wood"
) -> bool:
	if laenge <= 0 or not ["E", "S"].has(dir):
		return false
	if StorageLogic.count_of(HomeState.storage(gs), fence) < laenge:
		return false
	var garden_grid := GardenState.grid(gs)
	if not garden_grid.in_bounds(from):
		return false
	garden_grid.edges.append({"from": from, "dir": dir, "len": laenge, "fence": fence})
	GardenState.save_grid(gs, garden_grid)
	gs.update(
		func(state: Dictionary) -> void:
			for _i in laenge:
				StorageLogic.take(state["home"]["storage"], fence)
	)
	gs.notify_slice_changed("home")
	return true


static func _key(at: Vector2i) -> String:
	return "%d,%d" % [at.x, at.y]
