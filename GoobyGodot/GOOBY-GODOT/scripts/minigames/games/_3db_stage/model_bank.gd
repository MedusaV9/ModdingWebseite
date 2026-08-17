extends RefCounted
## Modell-Bank der 3D-Minispiele (Agent 3D-B) — gemeinsam genutzt von runner,
## shopping_surf, harbor_hopper, toy_racer und delivery_rush.
##
## Warum ein eigener Ordner statt fünf Kopien: die fünf Spiele teilen sich
## exakt dieselbe Aufgabe (Kenney-GLB laden, auf Sollbreite skalieren, Boden
## auf y = 0 ziehen, Mesh+Transform für MultiMesh herausziehen). Der Ordner
## `_3db_stage` gehört zu diesem Auftrag und enthält KEIN Spiel (kein
## game.json) — die Registry sieht ihn also nicht.
##
## Zwei Nutzungsarten:
##   node(path, width)  → fertig platziertes Node3D (Einzelstücke, z. B. Boot)
##   parts(path, width) → [{mesh, xform}] für MultiMeshInstance3D (Massenware)
##
## ALLES ist statisch gecacht: ein GLB wird pro Sitzung einmal geladen und
## einmal vermessen, egal wie viele Spiele/Runden es anfassen.

## path → PackedScene
static var _scenes: Dictionary = {}
## path → {aabb: AABB, parts: Array[{mesh, xform}]}
static var _baked: Dictionary = {}


## Roh-AABB des Modells (Modellkoordinaten, ohne Skalierung).
static func aabb(path: String) -> AABB:
	return _bake(path)["aabb"] as AABB


## Faktor, mit dem das Modell auf `target_w` Meter Breite (x) kommt.
static func fit_scale(path: String, target_w: float) -> float:
	var box := aabb(path)
	return target_w / maxf(0.001, box.size.x)


## Faktor, mit dem das Modell auf `target_h` Meter Höhe (y) kommt.
static func fit_height_scale(path: String, target_h: float) -> float:
	var box := aabb(path)
	return target_h / maxf(0.001, box.size.y)


## Breite (x), die entsteht, wenn die LÄNGSTE Kante `target` Meter misst.
## Das ist die Einpass-Regel der Web-Fassung (`fitModel`) und die einzige, die
## bei Fahrzeugen passt: ein Kutter ist viel länger als breit, „Breite 2,1 m"
## würde ihn auf Kanalbreite aufblasen.
static func width_for_max(path: String, target: float) -> float:
	var box := aabb(path)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	return box.size.x * (target / maxf(0.001, longest))


## Backe-Liste {mesh, xform} eines Modells, auf `target_w` Breite skaliert und
## mit der Unterkante auf y = 0 (für MultiMeshInstance3D-Ebenen).
static func parts(path: String, target_w := 0.0, ground_it := true) -> Array:
	var baked: Dictionary = _bake(path)
	var scale_f := 1.0 if target_w <= 0.0 else fit_scale(path, target_w)
	var box: AABB = baked["aabb"]
	var lift := -box.position.y * scale_f if ground_it else 0.0
	var base := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_f), Vector3(0.0, lift, 0.0))
	var out: Array = []
	for entry: Dictionary in baked["parts"]:
		out.append({"mesh": entry["mesh"], "xform": base * (entry["xform"] as Transform3D)})
	return out


## Dieselbe Liste, um `yaw` gedreht und DANACH auf `target_w` eingepasst.
##
## Für Kacheln mit gerichteter Textur: `road-straight` trägt die Fahrbahn quer
## im Modell, die Web-Fassung dreht sie mit `roadInner.rotation.y = PI/2` in die
## Korridorrichtung. Ohne diese Drehung wiederholt sich der Straßenquerschnitt
## alle acht Meter als Querstreifen — genau das sah nach „billigem 2D-Muster"
## aus. Gedreht wird VOR dem Einpassen, weil die Drehung die Breite ändert.
static func parts_yawed(path: String, yaw: float, target_w := 0.0, ground_it := true) -> Array:
	var baked: Dictionary = _bake(path)
	var spin := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	var turned: Array = []
	var box := AABB()
	var first := true
	for entry: Dictionary in baked["parts"]:
		var xform: Transform3D = spin * (entry["xform"] as Transform3D)
		turned.append({"mesh": entry["mesh"], "xform": xform})
		var world: AABB = xform * (entry["mesh"] as Mesh).get_aabb()
		box = world if first else box.merge(world)
		first = false
	var scale_f := 1.0 if target_w <= 0.0 else target_w / maxf(0.001, box.size.x)
	var lift := -box.position.y * scale_f if ground_it else 0.0
	var base := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_f), Vector3(0.0, lift, 0.0))
	var out: Array = []
	for entry: Dictionary in turned:
		out.append({"mesh": entry["mesh"], "xform": base * (entry["xform"] as Transform3D)})
	return out


## Dieselbe Liste, aber nach Höhe eingepasst (Bäume/Laternen).
static func parts_by_height(path: String, target_h: float, ground_it := true) -> Array:
	var baked: Dictionary = _bake(path)
	var scale_f := fit_height_scale(path, target_h)
	var box: AABB = baked["aabb"]
	var lift := -box.position.y * scale_f if ground_it else 0.0
	var base := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_f), Vector3(0.0, lift, 0.0))
	var out: Array = []
	for entry: Dictionary in baked["parts"]:
		out.append({"mesh": entry["mesh"], "xform": base * (entry["xform"] as Transform3D)})
	return out


## Einzelstück als echter Szenenknoten (wenn es sich bewegen/rotieren soll und
## MultiMesh zu umständlich wäre — z. B. der Kutter oder der Lieferwagen).
static func node(path: String, target_w := 0.0, ground_it := true) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Model"
	for entry: Dictionary in parts(path, target_w, ground_it):
		var mi := MeshInstance3D.new()
		mi.mesh = entry["mesh"]
		mi.transform = entry["xform"]
		holder.add_child(mi)
	return holder


## Skalierte Maße (Breite/Höhe/Tiefe) nach dem Einpassen auf `target_w`.
static func fitted_size(path: String, target_w: float) -> Vector3:
	return aabb(path).size * fit_scale(path, target_w)


static func _bake(path: String) -> Dictionary:
	if _baked.has(path):
		return _baked[path]
	var entry := {"aabb": AABB(), "parts": []}
	var packed: PackedScene = _scenes.get(path, null)
	if packed == null:
		packed = load(path) as PackedScene
		if packed == null:
			push_warning("[3db] Modell fehlt: %s" % path)
			_baked[path] = entry
			return entry
		_scenes[path] = packed
	var root_node: Node = packed.instantiate()
	var found: Array = []
	_collect(root_node, Transform3D.IDENTITY, found)
	var box := AABB()
	var first := true
	for item: Dictionary in found:
		var mesh: Mesh = item["mesh"]
		var world: AABB = (item["xform"] as Transform3D) * mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	root_node.free()
	entry["aabb"] = box
	entry["parts"] = found
	_baked[path] = entry
	return entry


static func _collect(node_in: Node, xform: Transform3D, out: Array) -> void:
	var here := xform
	if node_in is Node3D:
		here = xform * (node_in as Node3D).transform
	if node_in is MeshInstance3D and (node_in as MeshInstance3D).mesh != null:
		out.append({"mesh": (node_in as MeshInstance3D).mesh, "xform": here})
	for child in node_in.get_children():
		_collect(child, here, out)
