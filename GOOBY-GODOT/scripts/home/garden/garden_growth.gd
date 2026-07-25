class_name GardenGrowth
extends RefCounted
## Wachstums-Simulation des Gartens (Doc D §6.2) — bewusst FLACH und in
## jedem Schritt erklärbar (Tooltip-Regel, Doc D §11 Risiko 4):
##
##   rate = wasser × wind × schatten × gewaechshaus
##
## Alles PURE static — keine Nodes, keine Uhr, kein GameState. Die Uhr wird
## als Unix-Sekunden hereingereicht, damit Tests deterministisch bleiben.

## Faktoren (einzige Quelle der Wahrheit; das UI zeigt sie 1:1 an).
const WASSER_TROCKEN := 0.0
const WASSER_NASS := 1.0
const WIND_MALUS := 0.85
const WIND_RING := 2
const SCHATTEN_SONNE := 0.75
const SCHATTEN_SCHATTEN := 1.1
const NEUTRAL := 1.0
const GEWAECHSHAUS_BONUS := 1.25
## Wie lange eine Handgießkanne hält (Stunden).
const GIESS_STUNDEN := 8.0
## Wie tief ein Bauwerk/Baum nach Norden Schatten wirft (Süd-Sonne).
const SCHATTEN_TIEFE := 2


## Wasser-Faktor. Reihenfolge: von Hand gegossen → Sprinkler → Regen.
## Im Gewächshaus gießt Regen NICHT (Doc D §6.2) — Anlage oder Hand nötig.
static func wasser_faktor(
	watered_until: float, jetzt_s: float, regen: bool, sprinkler: bool, im_gewaechshaus: bool
) -> float:
	if watered_until > jetzt_s:
		return WASSER_NASS
	if sprinkler:
		return WASSER_NASS
	if regen and not im_gewaechshaus:
		return WASSER_NASS
	return WASSER_TROCKEN


## Wind-Faktor: die äußeren WIND_RING Zellringe sind zugig, außer ein Zaun
## schirmt sie ab oder sie liegen im Gewächshaus.
static func wind_faktor(
	cell: Vector2i, size: Vector2i, geschuetzt: Dictionary, im_gewaechshaus: bool
) -> float:
	if im_gewaechshaus or geschuetzt.has(cell):
		return NEUTRAL
	var rand_abstand: int = mini(
		mini(cell.x, cell.y), mini(size.x - 1 - cell.x, size.y - 1 - cell.y)
	)
	return NEUTRAL if rand_abstand >= WIND_RING else WIND_MALUS


## Schatten-Faktor: Sonnen-Crops leiden im Schatten, Schatten-Crops mögen ihn.
static func schatten_faktor(im_schatten: bool, licht: String) -> float:
	if not im_schatten:
		return NEUTRAL
	match licht:
		"sonne":
			return SCHATTEN_SONNE
		"schatten":
			return SCHATTEN_SCHATTEN
	return NEUTRAL


static func gewaechshaus_faktor(im_gewaechshaus: bool) -> float:
	return GEWAECHSHAUS_BONUS if im_gewaechshaus else NEUTRAL


## Gesamt-Rate aus den vier Einzelfaktoren (das UI zeigt genau diese vier).
static func rate(wasser: float, wind: float, schatten: float, gewaechshaus: float) -> float:
	return maxf(0.0, wasser * wind * schatten * gewaechshaus)


## Alle Faktoren einer Beet-Zelle auf einmal — die EINE Stelle, die UI,
## Tick und Tooltip gemeinsam benutzen.
static func faktoren(
	grid: GardenGrid, at: Vector2i, jetzt_s: float, regen: bool, schatten_zellen: Dictionary
) -> Dictionary:
	var data := grid.cell(at)
	var im_gh: bool = grid.greenhouse_cells().has(at)
	var licht := str(GardenCrops.crop(str(data.get("crop", ""))).get("licht", "neutral"))
	var wasser := wasser_faktor(
		float(data.get("watered_until", 0.0)), jetzt_s, regen, grid.sprinkler_cells().has(at), im_gh
	)
	var wind := wind_faktor(at, grid.size, grid.fence_shielded_cells(), im_gh)
	var schatten := schatten_faktor(schatten_zellen.has(at) and not im_gh, licht)
	var gewaechshaus := gewaechshaus_faktor(im_gh)
	return {
		"wasser": wasser,
		"wind": wind,
		"schatten": schatten,
		"gewaechshaus": gewaechshaus,
		"rate": rate(wasser, wind, schatten, gewaechshaus),
	}


## Schattenwerfer: Bäume, Shed, Werkstatt und Gewächshaus werfen ihren
## Schatten nach Norden (Süd-Sonne, statisch berechnet).
static func schatten_zellen(grid: GardenGrid) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in grid.structures:
		var kind := str(entry["kind"])
		if kind == "sprinkler":
			continue
		for cell in GardenGrid.structure_cells(kind, entry["at"], int(entry.get("rot", 0))):
			for d in range(1, SCHATTEN_TIEFE + 1):
				var shaded := cell - Vector2i(0, d)
				if grid.in_bounds(shaded):
					out[shaded] = true
	return out


## Wachstum eines Beetes um `minuten` Spielminuten weiterdrehen (mutiert die
## Zell-Daten). Liefert die neue Stufe. Nichts stirbt je — ungegossen
## pausiert das Wachstum nur (kinderfreundlich, Doc D §6.2).
static func advance(cell_data: Dictionary, minuten: float, growth_rate: float) -> int:
	var crop := GardenCrops.crop(str(cell_data.get("crop", "")))
	if crop.is_empty() or minuten <= 0.0:
		return int(cell_data.get("stage", 0))
	var progress := float(cell_data.get("progress_min", 0.0)) + minuten * maxf(0.0, growth_rate)
	var stufen := int(crop["stufen"])
	var pro_stufe := float(crop["minuten_pro_stufe"])
	var stage := mini(stufen, int(floor(progress / pro_stufe)))
	cell_data["progress_min"] = minf(progress, stufen * pro_stufe)
	cell_data["stage"] = stage
	return stage


static func ist_erntereif(cell_data: Dictionary) -> bool:
	var crop := GardenCrops.crop(str(cell_data.get("crop", "")))
	if crop.is_empty():
		return false
	return int(cell_data.get("stage", 0)) >= int(crop["stufen"])
