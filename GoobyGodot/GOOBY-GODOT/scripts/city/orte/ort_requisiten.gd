class_name OrtRequisiten
## W18 CC0-Requisiten-Helfer für die Läden (REHWEI, Baumarkt, GooUndBye):
## Ecke-Ursprung-Ausgleich der Kenney-Möbel + Gooby-Pastell-Tints nach dem
## Integrations-Plan (Kenney kräftig-bunt → aufgehellter albedo-Tint;
## Quaternius flache Farben → Value +12 %, Saturation −20 %).
##
## Audit-Erkenntnis (tools/audit/orientation_audit.gd, W18): Kenney-
## furniture-GLBs spannen (0..B, 0..H, −T..0) — der Ursprung liegt an der
## vorderen ECKE, nicht in der Footprint-Mitte. Wer sie wie zentrierte
## Props stellt, bekommt bei Rotationen wandernde Footprints.


## Versatz vom gewünschten Footprint-MITTELPUNKT zum Ecke-Ursprung eines
## Kenney-Möbels: `grund` = rohe (Breite, Tiefe) laut GLB-AABB, `groesse`
## = uniforme Skala, `rot_grad` = Y-Rotation des Props.
static func ecken_versatz(rot_grad: float, groesse: float, grund: Vector2) -> Vector3:
	var lokal := Vector3(-grund.x * 0.5, 0.0, grund.y * 0.5) * groesse
	return Basis(Vector3.UP, deg_to_rad(rot_grad)) * lokal


## Pastell-Tint auf ein instanziertes GLB (Muster OrtScene._tinte_npc):
## Surface-Override je Material, albedo Richtung Palette + leicht
## aufgehellt. `null`-tolerant (Prop kann bei fehlendem Import fehlen).
static func tinte(node: Node3D, farbe: Color, staerke: float) -> void:
	if node == null:
		return
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		if mi.mesh == null:
			continue
		var getoent := mi.mesh.duplicate() as Mesh
		var geaendert := false
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, staerke).lightened(0.08)
				getoent.surface_set_material(i, kopie)
				geaendert = true
		if geaendert:
			# Surface-Overrides lösen im Dummy-Renderer bei importierten GLBs
			# material_get_instance_shader_parameters(null) aus. Eine private
			# Mesh-Kopie bewahrt dieselben Surface-Materialien ohne Engine-ERROR.
			mi.mesh = getoent


## Importierte CC0-/GLB-Modelle dürfen einzelne materiallose Surfaces
## enthalten. Der Dummy-Renderer fragt deren Instanz-Shaderparameter ab und
## loggt dabei `Parameter "material" is null`; auf Geräten wären diese Flächen
## außerdem rendererabhängig. Vor dem Einhängen einen neutralen Fallback nur
## auf tatsächlich materiallose Surfaces legen.
static func materialien_absichern(node: Node3D) -> void:
	if node == null:
		return
	var fallback: StandardMaterial3D = null
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi == null or mi.mesh == null or mi.material_override != null:
			continue
		for surface in mi.mesh.get_surface_count():
			if (
				mi.get_surface_override_material(surface) != null
				or mi.mesh.surface_get_material(surface) != null
			):
				continue
			if fallback == null:
				fallback = StandardMaterial3D.new()
				fallback.albedo_color = Color.WHITE
				fallback.roughness = 0.85
			mi.set_surface_override_material(surface, fallback)


## Quaternius-Flachfarben aufpastellisieren (Plan W18: Value +12 %,
## Saturation −20 %) — für Crops/Tiere, deren Grundfarbe bleiben soll.
static func pastellisiere(node: Node3D) -> void:
	if node == null:
		return
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		if mi.mesh == null:
			continue
		var pastell := mi.mesh.duplicate() as Mesh
		var geaendert := false
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				var c: Color = kopie.albedo_color
				kopie.albedo_color = Color.from_hsv(c.h, c.s * 0.8, minf(c.v * 1.12, 1.0), c.a)
				pastell.surface_set_material(i, kopie)
				geaendert = true
		if geaendert:
			mi.mesh = pastell


## Idle-Autoplay für animierte Quaternius-Tiere (Plan W18): erster
## AnimationPlayer im GLB, „Idle“-Clip loopen, falls vorhanden.
static func spiele_idle(node: Node3D) -> void:
	if node == null:
		return
	var spieler := node.find_children("*", "AnimationPlayer", true, false)
	if spieler.is_empty():
		return
	var ap: AnimationPlayer = spieler[0]
	if ap.has_animation("Idle"):
		var clip := ap.get_animation("Idle")
		clip.loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")
