extends RefCounted
## Bauteile der 3D-Bühne (Agent 3D-A): Pastell-Materialien, Grundkörper und
## die Kenney-Modellbank.
##
## Reine Fabrik, kein Zustand. Die GLB-Bank lädt und vermisst jedes Modell
## EINMAL pro Sitzung (statischer Cache) und gibt danach fertig eingepasste
## Instanzen oder {mesh, xform}-Listen für MultiMeshInstance3D aus — Massenware
## (Bäume, Büsche, Gräber) kostet so einen Draw-Call je Teilmesh statt einen
## je Objekt. Das ist der Grund, warum die Spiele trotz voller Kulisse unter
## dem 250-Draw-Call-Budget bleiben.

## Kantenlänge der erzeugten Weichzeichnerscheibe.
const DISC_SIZE := 64

## Umfärbung der Kenney-Kit-Materialien auf die GOOBY-Pastellpalette.
##
## Die Kits bringen ihre Farbe im Material MIT (kein Texturatlas), und ihr Laub
## ist türkis (`leafsGreen` = 0.16, 0.79, 0.67). Neben einer warmen Wiese wirkt
## das wie ein Fremdkörper. Der Schlüssel ist der glTF-Materialname, der über
## alle Kits hinweg gleich heißt — eine Tabelle reicht also für alle fünf
## Spiele.
const NATURE := {
	"leafsGreen": Color(0.45, 0.72, 0.42),
	"leafsDark": Color(0.32, 0.58, 0.37),
	"leafsFall": Color(0.95, 0.62, 0.3),
	"grass": Color(0.48, 0.74, 0.45),
	"woodBark": Color(0.64, 0.46, 0.33),
	"woodBarkDark": Color(0.53, 0.38, 0.29),
	"woodInner": Color(0.93, 0.82, 0.66),
	"wood": Color(0.86, 0.67, 0.46),
	"woodDark": Color(0.69, 0.51, 0.36),
	"dirt": Color(0.72, 0.58, 0.44),
	"stone": Color(0.79, 0.8, 0.81),
	"colorRed": Color(0.9, 0.36, 0.38),
	"colorYellow": Color(0.99, 0.79, 0.35),
	"colorPurple": Color(0.7, 0.6, 0.95),
	"_defaultMat": Color(0.96, 0.94, 0.9),
}

## path → PackedScene
static var _scenes: Dictionary = {}
## Erzeugte Weichzeichnerscheibe (siehe `disc`).
static var _disc: ImageTexture = null
## path → {"aabb": AABB, "parts": Array[{mesh, xform}]}
static var _baked: Dictionary = {}


## Matter Pastell-Standard der GOOBY-Welt.
static func flat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	return mat


## Leuchtendes Material (Ringe, Laternen, Marker) — trägt den Glow-Puls.
static func glow(color: Color, energy := 1.5) -> StandardMaterial3D:
	var mat := flat(color, 0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


## Durchscheinende Fläche (Wasser, Netz, Geisterlaken).
static func glass(color: Color, unshaded := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.25
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Weiche runde ALPHA-Scheibe, einmal pro Sitzung erzeugt.
##
## Sie wird gerechnet statt geladen, weil die üblichen Partikel-PNGs die
## Rundung nur in der HELLIGKEIT tragen (weißer Fleck auf Schwarz, Alpha
## überall 1). Als Schattenmaske malt so ein Bild ein sattes RECHTECK auf den
## Boden — genau das soll die Maske ja verhindern.
static func disc() -> ImageTexture:
	if _disc != null:
		return _disc
	var image := Image.create_empty(DISC_SIZE, DISC_SIZE, false, Image.FORMAT_RGBA8)
	var mid := (DISC_SIZE - 1) * 0.5
	for y in DISC_SIZE:
		for x in DISC_SIZE:
			var d := Vector2(x - mid, y - mid).length() / mid
			var a := clampf(1.0 - smoothstep(0.45, 1.0, d), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_disc = ImageTexture.create_from_image(image)
	return _disc


static func mesh_node(mesh: Mesh, at := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Waagerechte Platte (Wiese, Parkett, Wasser).
static func ground(size: Vector2, mat: Material, y := 0.0) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.material = mat
	var mi := mesh_node(plane, Vector3(0.0, y, 0.0), false)
	return mi


## Quader (Banden, Bretter, Stege). `size` ist die volle Kantenlänge.
static func box(size: Vector3, mat: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	return mesh_node(mesh, at)


static func cylinder(
	radius: float, height: float, mat: Material, at := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.material = mat
	return mesh_node(mesh, at)


static func sphere(radius: float, mat: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = mat
	return mesh_node(mesh, at)


## Ring (Korbring, Trefferring). Liegt waagerecht, wenn man ihn um −90° um x
## kippt; roh steht er senkrecht.
static func torus(radius: float, tube: float, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - tube)
	mesh.outer_radius = radius + tube
	mesh.rings = 20
	mesh.ring_segments = 8
	mesh.material = mat
	return mesh_node(mesh, Vector3.ZERO, false)


## Weicher Kontaktschatten unter Figuren/Bällen. Er braucht die runde
## Alpha-Maske — ein nacktes Quad malt sonst ein schwarzes RECHTECK auf den
## Boden. Der Sonnenschatten allein verliert auf Distanz die Bodenhaftung.
static func blob_shadow(radius: float, strength := 0.3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.24, 0.24, 0.26, strength)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = disc()
	quad.material = mat
	var mi := mesh_node(quad, Vector3(0.0, 0.02, 0.0), false)
	mi.rotation_degrees.x = -90.0
	return mi


## Immer zur Kamera gedrehtes Leuchtplättchen (Halo, Mond, Fackelschein).
static func halo(radius: float, color: Color) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	# Nebel auf einem ADDITIVEN Plättchen legt die Nebelfarbe über das GANZE
	# Quadrat — aus dem weichen Schein wird ein leuchtender Kasten, und ferne
	# Halos (Mond) ersaufen komplett.
	mat.disable_fog = true
	mat.albedo_texture = disc()
	quad.material = mat
	return mesh_node(quad, Vector3.ZERO, false)


# ------------------------------------------------------------- Modellbank


## Roh-AABB eines GLB in Modellkoordinaten.
static func aabb(path: String) -> AABB:
	return _bake(path)["aabb"] as AABB


## Instanz, eingepasst auf `target` Meter HÖHE (0 = Originalgröße);
## die Unterkante liegt auf y = 0.
static func model(path: String, target := 0.0) -> Node3D:
	var holder := Node3D.new()
	var packed := _scene(path)
	if packed == null:
		return holder
	var node := packed.instantiate()
	holder.add_child(node)
	var box_aabb := aabb(path)
	var factor := 1.0
	if target > 0.0:
		factor = target / maxf(0.001, box_aabb.size.y)
	node.scale = Vector3.ONE * factor
	var center := box_aabb.get_center() * factor
	node.position = Vector3(-center.x, -box_aabb.position.y * factor, -center.z)
	return holder


## Instanz OHNE Umzentrieren — für Modelle, deren Nullpunkt schon stimmt
## (Kenney-Kacheln, Fahnen mit Mast auf x = 0).
static func raw(path: String, scale := 1.0) -> Node3D:
	var holder := Node3D.new()
	var packed := _scene(path)
	if packed == null:
		return holder
	var node := packed.instantiate()
	(node as Node3D).scale = Vector3.ONE * scale
	holder.add_child(node)
	return holder


## {mesh, xform, mat}-Liste für MultiMeshInstance3D, auf `target` Meter Höhe
## skaliert und auf y = 0 gestellt. Jede OBERFLÄCHE wird ein eigener Eintrag
## (Stamm und Laub getrennt) — nur so lässt sich ein Kenney-Baum umfärben,
## ohne ihn einfarbig zu machen. `remap` bildet Materialnamen auf Farben ab.
static func parts(path: String, target := 0.0, remap := {}) -> Array:
	var baked := _bake(path)
	var box_aabb: AABB = baked["aabb"]
	var factor := 1.0
	if target > 0.0:
		factor = target / maxf(0.001, box_aabb.size.y)
	var center := box_aabb.get_center() * factor
	var base := Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * factor),
		Vector3(-center.x, -box_aabb.position.y * factor, -center.z)
	)
	var out: Array = []
	for entry: Dictionary in baked["parts"]:
		var mat: StandardMaterial3D = entry["mat"]
		if remap.has(mat.resource_name):
			mat = flat(remap[mat.resource_name], 0.88)
		out.append(
			{"mesh": entry["mesh"], "xform": base * (entry["xform"] as Transform3D), "mat": mat}
		)
	return out


## Massen-Requisite: EIN Modell, viele feste Posen, ein Draw-Call je Oberfläche.
static func swarm(parts_list: Array, poses: Array, cull_margin := 24.0) -> Node3D:
	var holder := Node3D.new()
	if poses.is_empty():
		return holder
	for entry: Dictionary in parts_list:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry["mesh"]
		mm.instance_count = poses.size()
		for i in poses.size():
			mm.set_instance_transform(
				i, (poses[i] as Transform3D) * (entry["xform"] as Transform3D)
			)
		mm.visible_instance_count = poses.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.extra_cull_margin = cull_margin
		if entry.has("mat"):
			mmi.material_override = entry["mat"]
		holder.add_child(mmi)
	return holder


## Wie `swarm`, aber aus einem einzelnen Mesh (Prozedur-Massenware).
static func swarm_mesh(mesh: Mesh, poses: Array, cull_margin := 24.0) -> Node3D:
	return swarm([{"mesh": mesh, "xform": Transform3D.IDENTITY}], poses, cull_margin)


## Pose-Helfer für die Schwärme.
static func pose(at: Vector3, yaw := 0.0, scale := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), at)


## Ein Kenney-Modell als Kranz um `center` streuen (Kulissen aller fünf
## Spiele). `jitter` streut den Radius, `phase` verdreht den Kranz gegen die
## anderen Sorten, `skip` blendet Posen aus (z. B. die Sichtschneise der
## Kamera). Ergebnis ist EIN Knoten mit einem MultiMesh je Materialfläche.
static func scatter(
	path: String,
	height: float,
	count: int,
	radius: float,
	center := Vector3.ZERO,
	jitter := 0.0,
	phase := 0.0,
	skip := Callable()
) -> Node3D:
	var poses: Array = []
	for i in count:
		var a := TAU * (float(i) + phase) / float(count)
		var r := radius + jitter * sin(float(i) * 2.7 + phase)
		var at := center + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if skip.is_valid() and bool(skip.call(at)):
			continue
		poses.append(pose(at, a * 1.7 + float(i), 0.86 + 0.28 * absf(sin(float(i) * 1.9))))
	return swarm(parts(path, height, NATURE), poses)


## Alle Materialien einer Instanz umfärben (Pastell-Angleich der Kenney-Kits).
## Greift auch auf MultiMeshInstance3D — die Kenney-Palette ist stellenweise
## knallig türkis und würde den warmen GOOBY-Look sprengen.
static func tint(node: Node, color: Color, emission := 0.0) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = (
			glow(color, emission) if emission > 0.0 else flat(color)
		)
	for child in node.get_children():
		tint(child, color, emission)


static func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path)
	if packed == null:
		push_warning("Props3D: Modell fehlt: %s" % path)
	_scenes[path] = packed
	return packed


## Kenney-Material in den GOOBY-Look ziehen.
##
## Die Kits liefern ihre Farbe als `baseColorFactor` MIT `metallicFactor: 1` —
## in Godot sieht das stumpf und metallisch aus, und die Laubfarbe der
## Nature-Kits ist ein knalliges Türkis (0.16, 0.79, 0.67). Diese Funktion
## nimmt jedem Kit-Material das Metall, gibt ihm matte Rauheit und erlaubt es,
## einzelne Materialnamen (`leafsGreen`, `woodBark`, …) auf die Pastellpalette
## des Spiels umzubiegen.
static func pastel(source: Material, remap: Dictionary) -> StandardMaterial3D:
	var color := Color(0.85, 0.85, 0.85)
	var name := ""
	if source is BaseMaterial3D:
		var base := source as BaseMaterial3D
		color = base.albedo_color
		name = base.resource_name
	if name.is_empty() and source != null:
		name = source.resource_name
	if remap.has(name):
		color = remap[name]
	var mat := flat(color, 0.88)
	mat.resource_name = name
	return mat


## Alle Oberflächen einer Instanz entmetallisieren/umfärben (siehe `pastel`).
static func repaint(node: Node, remap := {}) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, pastel(mi.mesh.surface_get_material(i), remap))
	for child in node.get_children():
		repaint(child, remap)


static func _bake(path: String) -> Dictionary:
	if _baked.has(path):
		return _baked[path]
	var result := {"aabb": AABB(Vector3.ZERO, Vector3.ONE), "parts": []}
	var packed := _scene(path)
	if packed != null:
		var root := packed.instantiate()
		var collected: Array = []
		_collect(root, Transform3D.IDENTITY, collected)
		var box_aabb := AABB()
		var first := true
		for entry: Dictionary in collected:
			var part := (entry["xform"] as Transform3D) * (entry["mesh"] as Mesh).get_aabb()
			box_aabb = part if first else box_aabb.merge(part)
			first = false
		if not first:
			result = {"aabb": box_aabb, "parts": collected}
		root.free()
	_baked[path] = result
	return result


## Jede Oberfläche als eigenes Ein-Flächen-Mesh sammeln — Voraussetzung für
## das getrennte Umfärben (Stamm ≠ Laub) und für ein MultiMesh je Farbe.
static func _collect(node: Node, xform: Transform3D, out: Array) -> void:
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	if mesh != null:
		for i in mesh.get_surface_count():
			var single := ArrayMesh.new()
			single.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
			out.append(
				{"mesh": single, "xform": here, "mat": pastel(mesh.surface_get_material(i), {})}
			)
	for child in node.get_children():
		_collect(child, here, out)
