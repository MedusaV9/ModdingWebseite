extends RefCounted
## ASSET-ROT-Regelwerk (UserFeedback „alle Assets immer richtig rotiert und
## richtig rum"): pure, wiederverwendbare Analyse eines Szenenbaums auf
## Fehl-Orientierungs-Verdacht. Genutzt vom Audit-Werkzeug
## (tests/tools/asset_rot_audit.gd) und der Dauer-Wache
## (tests/unit/test_asset_orientation.gd). KEINE Nodes, kein Zustand —
## Eingabe ist ein instanzierter Baum, Ausgabe eine Befund-Liste.
##
## Geprüft werden PLATZIERUNGS-Wurzeln (das, was unser Code dreht/spiegelt):
##   - GLB-/GLTF-Szenen-Instanzen (scene_file_path endet auf .glb/.gltf) —
##     Quell-Assets sind per glTF-Spezifikation Y-up/-Z-forward, d. h. eine
##     korrekte Platzierung dreht praktisch nur um Y (Yaw).
##   - „Holder“-Node3D, deren direkte Kinder ArrayMesh-MeshInstance3D sind
##     (ModelBank-Muster: GLB-Teile gebacken, Holder trägt die Platzierung).
## Innerhalb einer GLB-Instanz wird NICHT geprüft (interne Transforms sind
## Autoren-Sache des Assets und rendern korrekt).
##
## Befund-Arten:
##   NEG_SCALE  Welt-Basis mit negativer Determinante → gespiegeltes Modell.
##   KOPFUEBER  Up-Vektor zeigt >150° von Welt-UP weg → steht auf dem Kopf.
##   KIPP_90    Up-Vektor 75°–105° gekippt (≈ ±90° um X/Z) → liegt auf der
##              Seite; ROT bei bekannten Richtungs-/Steh-Assets.
##   SCHIEF     15°–75° Neigung — nur Hinweis (lehnende Deko ist oft Absicht).
## ROT-Befunde ohne Whitelist-Eintrag lassen die Dauer-Wache fehlschlagen.

const WHITELIST_PFAD := "res://tests/fixtures/asset_rot_whitelist.json"

## Namens-Muster von Assets mit eindeutiger Vorder-/Oberseite (Autos, Möbel,
## Schilder, Geräte …) — bei denen ist ein Kipp praktisch nie Absicht.
const RICHTUNGS_MUSTER: Array[String] = [
	"sedan",
	"taxi",
	"suv",
	"van",
	"delivery",
	"police",
	"race",
	"hatchback",
	"tractor",
	"truck",
	"ambulance",
	"bench",
	"chair",
	"stool",
	"sofa",
	"couch",
	"bed",
	"television",
	"sign",
	"shelf",
	"shelves",
	"bookcase",
	"cabinet",
	"stove",
	"fridge",
	"oven",
	"sink",
	"toilet",
	"mirror",
	"desk",
	"piano",
	"wardrobe",
	"dresser",
	"lamp",
	"npc",
	"gooby",
	"horse",
	"pferd",
]

const SCHIEF_MIN_GRAD := 15.0
const KIPP_MIN_GRAD := 75.0
const KIPP_MAX_GRAD := 105.0
const KOPF_MIN_GRAD := 150.0


## Analysiert den Baum unter `wurzel` und liefert alle Befunde.
## `szene` ist der res://-Pfad der geprüften Szene (für Bericht/Whitelist).
## `stats` (optional) wird um "glb"/"holder"-Kandidatenzähler erhöht —
## damit Läufe belegen können, dass wirklich etwas geprüft wurde.
static func pruefe_baum(wurzel: Node, szene: String, stats: Dictionary = {}) -> Array[Dictionary]:
	var befunde: Array[Dictionary] = []
	_gehe(wurzel, wurzel, szene, befunde, stats)
	return befunde


## Schweregrad eines Befunds: "ROT" = muss gefixt oder gewhitelistet werden,
## "GELB" = Hinweis für die Sichtung.
static func stufe(befund: Dictionary) -> String:
	var art := str(befund.get("art", ""))
	if art == "NEG_SCALE" or art == "KOPFUEBER":
		return "ROT"
	if art == "KIPP_90" and bool(befund.get("richtung", false)):
		return "ROT"
	return "GELB"


## Whitelist laden (bewusste Ausnahmen). Fehlende Datei ⇒ leere Liste.
static func lade_whitelist() -> Array:
	if not FileAccess.file_exists(WHITELIST_PFAD):
		return []
	var text := FileAccess.get_file_as_string(WHITELIST_PFAD)
	var daten: Variant = JSON.parse_string(text)
	if not (daten is Dictionary):
		push_warning("[ASSET-ROT] Whitelist unlesbar: %s" % WHITELIST_PFAD)
		return []
	return (daten as Dictionary).get("eintraege", []) as Array


## true, wenn ein Whitelist-Eintrag den Befund abdeckt (szene exakt ODER
## leer, pfad_regex auf den Node-Pfad, art exakt ODER "*").
static func ist_erlaubt(befund: Dictionary, whitelist: Array) -> bool:
	for roh: Variant in whitelist:
		if not (roh is Dictionary):
			continue
		var eintrag := roh as Dictionary
		var szene := str(eintrag.get("szene", ""))
		if szene != "" and szene != str(befund.get("szene", "")):
			continue
		var art := str(eintrag.get("art", "*"))
		if art != "*" and art != str(befund.get("art", "")):
			continue
		var regex := RegEx.new()
		if regex.compile(str(eintrag.get("pfad_regex", ""))) != OK:
			push_warning("[ASSET-ROT] kaputte pfad_regex: %s" % str(eintrag))
			continue
		if regex.search(str(befund.get("pfad", ""))) != null:
			return true
	return false


## Nur die ROT-Befunde, die KEINE Whitelist-Ausnahme haben (Wache-Eingabe).
static func rote_befunde(befunde: Array[Dictionary], whitelist: Array) -> Array[Dictionary]:
	var rot: Array[Dictionary] = []
	for befund in befunde:
		if stufe(befund) == "ROT" and not ist_erlaubt(befund, whitelist):
			rot.append(befund)
	return rot


## Einzeiler fürs Log/den Fehlertext der Wache.
static func beschreibe(befund: Dictionary) -> String:
	return (
		"%s %s [%s] %s — Kipp %.0f°, det %.2f, rot %s"
		% [
			str(befund.get("art", "?")),
			"RICHTUNG" if bool(befund.get("richtung", false)) else "neutral",
			str(befund.get("szene", "?")),
			str(befund.get("pfad", "?")),
			float(befund.get("kipp_grad", 0.0)),
			float(befund.get("det", 1.0)),
			str(befund.get("rot_grad", "")),
		]
	)


# ── interne Baum-Analyse ──────────────────────────────────────────────────────


static func _gehe(
	node: Node, wurzel: Node, szene: String, out: Array[Dictionary], stats: Dictionary
) -> void:
	# Skelette/Partikel posieren ihre Kinder frei — dort ist nichts „falsch“.
	if node is Skeleton3D or node is GPUParticles3D:
		return
	if node is Node3D and (node as Node3D).is_visible_in_tree():
		if _ist_glb_wurzel(node) and node != wurzel:
			stats["glb"] = int(stats.get("glb", 0)) + 1
			_pruefe_kandidat(node as Node3D, wurzel, szene, "glb", out)
			return  # GLB-Innenleben ist Asset-Autorensache
		if _ist_holder(node):
			stats["holder"] = int(stats.get("holder", 0)) + 1
			_pruefe_kandidat(node as Node3D, wurzel, szene, "holder", out)
	for kind in node.get_children():
		_gehe(kind, wurzel, szene, out, stats)


static func _ist_glb_wurzel(node: Node) -> bool:
	var pfad := node.scene_file_path
	return pfad.ends_with(".glb") or pfad.ends_with(".gltf")


## ModelBank-/Handbau-Muster: Node3D, dessen direkte Kinder gebackene
## GLB-Teile (ArrayMesh) tragen — der Holder selbst hält die Platzierung.
static func _ist_holder(node: Node) -> bool:
	if not (node is Node3D) or node is MeshInstance3D:
		return false
	for kind in node.get_children():
		if kind is MeshInstance3D and (kind as MeshInstance3D).mesh is ArrayMesh:
			return true
	return false


static func _pruefe_kandidat(
	node: Node3D, wurzel: Node, szene: String, ebene: String, out: Array[Dictionary]
) -> void:
	var basis := node.global_transform.basis
	var det := basis.determinant()
	var up := (basis * Vector3.UP).normalized()
	var kipp := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	var art := ""
	if det < 0.0:
		art = "NEG_SCALE"
	elif kipp >= KOPF_MIN_GRAD:
		art = "KOPFUEBER"
	elif kipp >= KIPP_MIN_GRAD and kipp <= KIPP_MAX_GRAD:
		art = "KIPP_90"
	elif kipp >= SCHIEF_MIN_GRAD:
		art = "SCHIEF"
	if art == "":
		return
	var asset := _asset_name(node)
	(
		out
		. append(
			{
				"szene": szene,
				"pfad": str(wurzel.get_path_to(node)),
				"asset": asset,
				"art": art,
				"ebene": ebene,
				"richtung": _ist_richtungs_asset(asset, node.name),
				"kipp_grad": snappedf(kipp, 0.1),
				"det": snappedf(det, 0.001),
				"rot_grad": str(node.global_rotation_degrees.snappedf(0.1)),
				"pos": str(node.global_position.snappedf(0.01)),
			}
		)
	)


static func _asset_name(node: Node3D) -> String:
	if _ist_glb_wurzel(node):
		return node.scene_file_path.get_file()
	# Holder: Namen der gebackenen Teile mitnehmen (bestes verfügbares Indiz).
	for kind in node.get_children():
		if kind is MeshInstance3D and (kind as MeshInstance3D).mesh != null:
			var mesh_name := str(((kind as MeshInstance3D).mesh as Mesh).resource_name)
			if mesh_name != "":
				return mesh_name
	return str(node.name)


static func _ist_richtungs_asset(asset: String, node_name: String) -> bool:
	var probe := (asset + " " + node_name).to_lower()
	for muster in RICHTUNGS_MUSTER:
		if probe.contains(muster):
			return true
	return false
