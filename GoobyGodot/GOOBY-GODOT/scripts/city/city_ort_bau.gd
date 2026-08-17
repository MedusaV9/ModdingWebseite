class_name CityOrtBau
extends RefCounted
## Baut die CityOrtArchitektur-Pläne als echte Nodes (GOOBY-WELT/STADT).
## Draw-Call-Budget ≤ 400: ALLE Primitive eines Orts werden per SurfaceTool
## je Material (Farbe+Glow) zu EINEM ArrayMesh verschmolzen — ein Ort kostet
## damit ~4–8 Draw-Calls statt ~30, und Frustum-Culling wirkt weiter pro Ort.
## GLB-Requisiten laufen über CityBau.lade_glb (+ optionaler Tint).
## Zusätzlich hängt jeder Ort mit Signaturfarbe eine NEON-Leiste über das
## Portal — die schaltet CityLicht nachts an (melde_neon).

## Verschmolzene Kleinteil-Meshes enden ab dieser Distanz (Fill-Budget).
const PRIM_SICHT_M := 150.0
## Elemente unter diesem Maß gelten als Kleinteil (Schatten aus lohnt nicht).
const KLEIN_MASS_M := 1.6

## Neon-Leiste überm Portal: Maß + Höhe (lokal, Meter).
const NEON_GROESSE := Vector3(3.6, 0.16, 0.16)
const NEON_HOEHE := 3.55

var _mat_cache: Dictionary = {}
## CityBau besitzt diesen Helfer. Die Rückkante muss schwach sein, sonst
## bilden zwei RefCounted-Objekte einen Zyklus und halten nach jedem
## Stadtbesuch sämtliche GLB-Meshes/Materialien bis zum Prozessende.
var _bau_ref: WeakRef


func _init(bau: CityBau) -> void:
	_bau_ref = weakref(bau)


## Kompletter Ort-Aufbau: Plan-Elemente + Neon-Leiste. Liefert die gebaute
## Neon-Node (oder null), damit CityBau sie bei CityLicht anmeldet.
func baue(wurzel: Node3D, ort_id: String, mitte: Vector3, richtung: Vector3) -> Node3D:
	var plan := CityOrtArchitektur.plan(ort_id)
	if plan.is_empty():
		return null
	var halter := Node3D.new()
	halter.name = "Ort_%s" % ort_id
	halter.position = mitte + Vector3(0.0, 0.05, 0.0)
	halter.rotation.y = atan2(richtung.x, richtung.z)
	wurzel.add_child(halter)
	# Primitive nach Material-Schlüssel sammeln (gross wirft Schatten,
	# klein nicht) — GLBs bleiben eigene Instanzen (eigene Materialien).
	var toepfe: Dictionary = {}
	for element in plan:
		if str(element.get("form", "box")) == "glb":
			_baue_glb(halter, element)
		else:
			_sammle_primitiv(toepfe, element)
	for key: String in toepfe:
		_baue_topf(halter, key, toepfe[key])
	return _baue_neon(halter, ort_id)


func _baue_glb(halter: Node3D, element: Dictionary) -> void:
	var bau := _bau_ref.get_ref() as CityBau
	if bau == null:
		return
	var node := bau.lade_glb(
		CityBau.glb_pfad(str(element["glb"])), float(element.get("scale", 3.0))
	)
	if node == null:
		return
	var tint := str(element.get("tint", ""))
	if not tint.is_empty():
		bau.faerbe(node, Color.from_string(tint, Color.WHITE), 0.65)
	node.position = element.get("off", Vector3.ZERO)
	node.rotation = _euler(element)
	halter.add_child(node)


func _sammle_primitiv(toepfe: Dictionary, element: Dictionary) -> void:
	var mass: Vector3 = element.get("size", Vector3.ONE)
	var klein := maxf(mass.x, maxf(mass.y, mass.z)) < KLEIN_MASS_M
	var key := (
		"%s|%.2f|%d"
		% [str(element.get("farbe", "#FFFFFF")), float(element.get("glow", 0.0)), int(klein)]
	)
	if not toepfe.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		toepfe[key] = st
	var st_topf: SurfaceTool = toepfe[key]
	var xform := Transform3D(Basis.from_euler(_euler(element)), element.get("off", Vector3.ZERO))
	st_topf.append_from(_primitiv_mesh(str(element.get("form", "box")), mass), 0, xform)


## Ein Material-Topf wird EIN MeshInstance3D (Kleinteile: kein Schatten +
## Distanz-Ende; Große: Schatten an, immer sichtbar).
func _baue_topf(halter: Node3D, key: String, st: SurfaceTool) -> void:
	var teile := key.split("|")
	var mi := MeshInstance3D.new()
	mi.name = "Prim_%s" % key.replace("#", "").replace("|", "_").replace(".", "")
	mi.mesh = st.commit()
	mi.material_override = _material(teile[0], float(teile[1]))
	if int(teile[2]) == 1:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = PRIM_SICHT_M
	halter.add_child(mi)


## Neon-Leiste überm Portal in Signaturfarbe (aus am Tag; CityLicht toggelt).
func _baue_neon(halter: Node3D, ort_id: String) -> Node3D:
	var farbe := CityOrtArchitektur.neon_farbe(ort_id)
	if farbe.is_empty():
		return null
	var neon := MeshInstance3D.new()
	neon.name = "Neon"
	var box := BoxMesh.new()
	box.size = NEON_GROESSE
	neon.mesh = box
	neon.material_override = CityAmbiente.leuchten_material(Color(farbe).lerp(Color.WHITE, 0.3))
	neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	neon.position = Vector3(0.0, NEON_HOEHE, CityOrtArchitektur.FRONT_Z + 0.3)
	neon.visible = false
	halter.add_child(neon)
	return neon


## Element-Rotation (Grad → Euler-Radiant, YXZ wie Node3D.rotation).
func _euler(element: Dictionary) -> Vector3:
	return Vector3(
		deg_to_rad(float(element.get("rot_x", 0.0))),
		deg_to_rad(float(element.get("rot", 0.0))),
		deg_to_rad(float(element.get("rot_z", 0.0)))
	)


## Frisches Primitiv-Mesh je Form+Maß — wird sofort in den Topf verschmolzen
## (kein Cache nötig; Segmentzahlen bewusst niedrig, Mobile-Budget).
func _primitiv_mesh(form: String, mass: Vector3) -> Mesh:
	match form:
		"zyl":
			var zyl := CylinderMesh.new()
			zyl.top_radius = mass.x
			zyl.bottom_radius = mass.z
			zyl.height = mass.y
			zyl.radial_segments = 12
			zyl.rings = 1
			return zyl
		"kugel":
			var kugel := SphereMesh.new()
			kugel.radius = mass.x
			kugel.height = mass.x * 2.0
			kugel.radial_segments = 12
			kugel.rings = 6
			return kugel
		"kapsel":
			var kapsel := CapsuleMesh.new()
			kapsel.radius = mass.x
			kapsel.height = mass.y
			kapsel.radial_segments = 12
			kapsel.rings = 4
			return kapsel
		"torus":
			var torus := TorusMesh.new()
			torus.inner_radius = maxf(0.02, mass.x - mass.y)
			torus.outer_radius = mass.x + mass.y
			torus.rings = 20
			torus.ring_segments = 8
			return torus
		_:
			var box := BoxMesh.new()
			box.size = mass
			return box


## Geteiltes Material je Farbe+Glow (Glow = dezente Emission, z. B. für
## Schaufenster-Scheiben — KEIN Environment-Glow-Pass, Mobile-Budget).
func _material(farbe_hex: String, glow: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [farbe_hex, glow]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_string(farbe_hex, Color.WHITE)
	mat.roughness = 0.82
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = glow
	_mat_cache[key] = mat
	return mat
