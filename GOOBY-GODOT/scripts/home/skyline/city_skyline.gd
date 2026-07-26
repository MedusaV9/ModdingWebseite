class_name CitySkyline
extends Node3D
## Stadt-Kulisse ums Haus (FIX-3, User: „beim Bauen die ganze Stadt sehen,
## mit fahrenden Autos und laufenden NPCs"). Ein Ringstraßen-Block um den
## Raum: Rasen-Grund, Straße (EIN MultiMesh für alle Geraden + 4 Kurven),
## Nachbarhäuser aus den Kenney-City-GLBs, 4 fahrende Autos, schlendernde
## Gooby-Passanten, Bäume als MultiMesh und Laternen.
##
## BEWUSST BILLIG: aktiv (sichtbar + _process) NUR im Baumodus — RoomBase
## schaltet über set_aktiv(). Fern-Deko trägt visibility_range_end (LOD),
## die Wiederhol-Geometrie läuft über MultiMesh. Budget-Test:
## test_fix3_skyline.gd, Draw-Call-Messung: fix3_perf_probe.gd.

const ASSETS := "res://assets/city"
const GOOBY_GLB := "res://assets/character/gooby.glb"
## Abstand Raumkante → Straßenmitte (m).
const RING := 4.2
## Kantenlänge einer Straßenkachel (m).
const KACHEL := 3.6
## Abstand Raumkante → Häuserfront (m).
const HAUS_RING := 9.0
const AUTO_TEMPO := 3.0
## Ziel-Höhe eines Autos in Metern — die GLBs kommen in Kit-Einheiten und
## werden per AABB normalisiert (Blanket-Scale machte sie hausgroß).
const AUTO_HOEHE := 1.45
## Passanten minimal kleiner als der Haus-Gooby (1.0) — Statisten-Optik.
const GOOBY_SCALE := 0.95
const NPC_ANZAHL := 4
const HAUS_GLBS: Array[String] = [
	"building-a",
	"building-b",
	"building-c",
	"building-d",
	"building-e",
	"building-f",
	"building-g",
	"building-h",
]
const AUTO_GLBS: Array[String] = ["sedan", "taxi", "suv", "hatchback-sports"]
## LOD: Deko verschwindet, wenn die Kamera weit draußen ist.
const LOD_DEKO_M := 70.0
const LOD_HAUS_M := 140.0

var _autos: Array[Dictionary] = []
var _npcs: Array[Dictionary] = []
var _ring_rect := Rect2()
var _zeit := 0.0


## Kulisse an einen Raum hängen (RoomBase ruft das im Aufbau).
## `world_size` = Raumgröße in Metern, `seed_wert` macht das Layout
## deterministisch (pro Raum stabil, Tests reproduzierbar).
static func attach_to(room: Node3D, world_size: Vector2, seed_wert: int) -> CitySkyline:
	var skyline := CitySkyline.new()
	skyline.name = "CitySkyline"
	skyline.baue(world_size, seed_wert)
	room.add_child(skyline)
	skyline.set_aktiv(false)
	return skyline


## Punkt auf dem Rechteck-Umfang bei Bogenlänge `t` (wrapt) — pure, für
## Autos auf dem Ring und den Test.
static func ring_punkt(rect: Rect2, t: float) -> Dictionary:
	var b := rect.size.x
	var h := rect.size.y
	var umfang := 2.0 * (b + h)
	var s := fposmod(t, umfang)
	var p := rect.position
	if s < b:
		return {"pos": Vector3(p.x + s, 0.0, p.y), "heading": PI * 0.5}
	s -= b
	if s < h:
		return {"pos": Vector3(p.x + b, 0.0, p.y + s), "heading": PI}
	s -= h
	if s < b:
		return {"pos": Vector3(p.x + b - s, 0.0, p.y + h), "heading": -PI * 0.5}
	s -= b
	return {"pos": Vector3(p.x, 0.0, p.y + h - s), "heading": 0.0}


func baue(world_size: Vector2, seed_wert: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	_ring_rect = Rect2(-RING, -RING, world_size.x + 2.0 * RING, world_size.y + 2.0 * RING)
	_baue_grund(world_size)
	_baue_strasse()
	_baue_haeuser(world_size, rng)
	_baue_natur(world_size, rng)
	_baue_laternen()
	_baue_autos(rng)
	_baue_npcs(world_size, rng)


## Aktiv = sichtbar + Verkehr läuft. Außerhalb des Baumodus schläft die
## Kulisse komplett (Budget!) — die Fenster-Dioramen übernehmen dort.
func set_aktiv(aktiv: bool) -> void:
	visible = aktiv
	set_process(aktiv)


func _process(delta: float) -> void:
	_zeit += delta
	for auto: Dictionary in _autos:
		auto["t"] = float(auto["t"]) + AUTO_TEMPO * delta * float(auto["richtung"])
		var bei := ring_punkt(auto["rect"], float(auto["t"]))
		var node: Node3D = auto["node"]
		node.position = (bei["pos"] as Vector3) + Vector3(0.0, 0.02, 0.0)
		node.rotation.y = float(bei["heading"]) + (0.0 if float(auto["richtung"]) > 0.0 else PI)
	for npc: Dictionary in _npcs:
		var punkt := _pingpong_punkt(npc, _zeit)
		var node: Node3D = npc["node"]
		node.position = punkt["pos"]
		node.rotation.y = float(punkt["heading"])


## Ping-Pong auf einer Gehweg-Strecke (wie CityFussgaenger, lokal gehalten).
func _pingpong_punkt(route: Dictionary, zeit: float) -> Dictionary:
	var von: Vector3 = route["von"]
	var nach: Vector3 = route["nach"]
	var laenge := maxf(0.001, von.distance_to(nach))
	var t := float(route["phase"]) * 2.0 + zeit * float(route["tempo"]) / laenge
	var zyklus := fposmod(t, 2.0)
	var hin := zyklus < 1.0
	var f := zyklus if hin else 2.0 - zyklus
	var richtung := (nach - von) if hin else (von - nach)
	return {"pos": von.lerp(nach, f), "heading": atan2(richtung.x, richtung.z)}


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _baue_grund(world_size: Vector2) -> void:
	var gras := MeshInstance3D.new()
	gras.name = "Rasen"
	var plane := PlaneMesh.new()
	plane.size = Vector2(world_size.x + 90.0, world_size.y + 90.0)
	gras.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8CBE6B")
	mat.roughness = 1.0
	gras.material_override = mat
	gras.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gras.position = Vector3(world_size.x * 0.5, -0.14, world_size.y * 0.5)
	add_child(gras)


## Ring aus Kenney-Straßenkacheln: alle GERADEN in einem MultiMesh, die
## vier Kurven als Einzel-GLBs an den Ecken.
func _baue_strasse() -> void:
	var transforms: Array[Transform3D] = []
	var rect := _ring_rect
	var laengs_x := int(floor((rect.size.x - KACHEL) / KACHEL))
	var laengs_z := int(floor((rect.size.y - KACHEL) / KACHEL))
	for i in laengs_x:
		var x := rect.position.x + KACHEL * (i + 1.0)
		transforms.append(_kachel_transform(Vector3(x, 0.0, rect.position.y), 0.0))
		transforms.append(_kachel_transform(Vector3(x, 0.0, rect.end.y), 0.0))
	for i in laengs_z:
		var z := rect.position.y + KACHEL * (i + 1.0)
		transforms.append(_kachel_transform(Vector3(rect.position.x, 0.0, z), PI * 0.5))
		transforms.append(_kachel_transform(Vector3(rect.end.x, 0.0, z), PI * 0.5))
	_multi_aus_glb("%s/strassen/road-straight.glb" % ASSETS, transforms, "Strasse")
	for ecke: Array in [
		[Vector3(rect.position.x, 0.0, rect.position.y), 0.0],
		[Vector3(rect.end.x, 0.0, rect.position.y), -PI * 0.5],
		[Vector3(rect.end.x, 0.0, rect.end.y), PI],
		[Vector3(rect.position.x, 0.0, rect.end.y), PI * 0.5],
	]:
		var kurve := _glb("%s/strassen/road-bend.glb" % ASSETS, KACHEL)
		if kurve == null:
			continue
		kurve.position = ecke[0]
		kurve.rotation.y = float(ecke[1])
		add_child(kurve)


func _kachel_transform(pos: Vector3, yaw: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * KACHEL)
	return Transform3D(basis, pos)


func _baue_haeuser(world_size: Vector2, rng: RandomNumberGenerator) -> void:
	var haeuser := Node3D.new()
	haeuser.name = "Haeuser"
	add_child(haeuser)
	var mitte := Vector3(world_size.x * 0.5, 0.0, world_size.y * 0.5)
	for seite in 4:
		var plaetze := _haus_plaetze(world_size, seite)
		for platz: Vector3 in plaetze:
			var glb_name: String = HAUS_GLBS[rng.randi_range(0, HAUS_GLBS.size() - 1)]
			var haus := _glb("%s/gebaeude/%s.glb" % [ASSETS, glb_name], 1.0)
			if haus == null:
				continue
			_fit_hoehe(haus, rng.randf_range(4.2, 6.8))
			haus.position = platz
			# Front zeigt zur Straße (= zum Raum hin).
			haus.rotation.y = atan2(mitte.x - platz.x, mitte.z - platz.z)
			_set_lod(haus, LOD_HAUS_M)
			haeuser.add_child(haus)


## Hausplätze einer Seite (0=N, 1=S, 2=W, 3=E) auf dem Häuser-Ring.
func _haus_plaetze(world_size: Vector2, seite: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var schritt := 6.5
	var laenge := world_size.x if seite < 2 else world_size.y
	var anzahl := maxi(2, int((laenge + 2.0 * HAUS_RING) / schritt) - 1)
	for i in anzahl:
		var entlang := -HAUS_RING + (i + 0.5) * (laenge + 2.0 * HAUS_RING) / anzahl
		match seite:
			0:
				out.append(Vector3(entlang, 0.0, -HAUS_RING))
			1:
				out.append(Vector3(entlang, 0.0, world_size.y + HAUS_RING))
			2:
				out.append(Vector3(-HAUS_RING, 0.0, entlang))
			3:
				out.append(Vector3(world_size.x + HAUS_RING, 0.0, entlang))
	return out


func _baue_natur(world_size: Vector2, rng: RandomNumberGenerator) -> void:
	var pfad := "%s/natur/tree_default.glb" % ASSETS
	var glb_hoehe := _glb_hoehe(pfad)
	if glb_hoehe <= 0.0001:
		return
	var transforms: Array[Transform3D] = []
	for _i in 14:
		var winkel := rng.randf() * TAU
		var radius := HAUS_RING + rng.randf_range(3.0, 14.0)
		var pos := Vector3(
			world_size.x * 0.5 + cos(winkel) * radius,
			0.0,
			world_size.y * 0.5 + sin(winkel) * radius
		)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		# Ziel-Höhe in Metern, AABB-normalisiert wie Häuser/Autos.
		basis = basis.scaled(Vector3.ONE * (rng.randf_range(2.8, 4.4) / glb_hoehe))
		transforms.append(Transform3D(basis, pos))
	_multi_aus_glb(pfad, transforms, "Baeume", LOD_DEKO_M)


func _baue_laternen() -> void:
	var rect := _ring_rect
	for pos: Vector3 in [
		Vector3(rect.position.x + 1.2, 0.0, rect.position.y + 1.2),
		Vector3(rect.end.x - 1.2, 0.0, rect.position.y + 1.2),
		Vector3(rect.position.x + 1.2, 0.0, rect.end.y - 1.2),
		Vector3(rect.end.x - 1.2, 0.0, rect.end.y - 1.2),
	]:
		var lampe := _glb("%s/deko/streetlight.gltf" % ASSETS, 1.0)
		if lampe == null:
			continue
		_fit_hoehe(lampe, 3.2)
		lampe.position = pos
		_set_lod(lampe, LOD_DEKO_M)
		add_child(lampe)


func _baue_autos(rng: RandomNumberGenerator) -> void:
	var umfang := 2.0 * (_ring_rect.size.x + _ring_rect.size.y)
	for i in AUTO_GLBS.size():
		var node := _glb("%s/autos/%s.glb" % [ASSETS, AUTO_GLBS[i]], 1.0)
		if node == null:
			continue
		_fit_hoehe(node, AUTO_HOEHE)
		add_child(node)
		# Zwei Spuren: außen im Uhrzeigersinn, innen dagegen.
		var richtung := 1.0 if i % 2 == 0 else -1.0
		var spur := _ring_rect.grow(0.85 if i % 2 == 0 else -0.85)
		(
			_autos
			. append(
				{
					"node": node,
					"rect": spur,
					"t": umfang * (float(i) / AUTO_GLBS.size()) + rng.randf_range(0.0, 3.0),
					"richtung": richtung,
				}
			)
		)
	_process(0.0)


## Gooby-Passanten wie in der Stadt (CityScene §Fußgänger): nur das GLB mit
## laufender walk-Animation — keine Rig-Maschinerie.
func _baue_npcs(world_size: Vector2, rng: RandomNumberGenerator) -> void:
	if not ResourceLoader.exists(GOOBY_GLB):
		return
	var szene: PackedScene = load(GOOBY_GLB)
	if szene == null:
		return
	var gehweg := RING + 1.6
	var strecken: Array[Array] = [
		[Vector3(-2.0, 0.0, -gehweg), Vector3(world_size.x + 2.0, 0.0, -gehweg)],
		[
			Vector3(-2.0, 0.0, world_size.y + gehweg),
			Vector3(world_size.x + 2.0, 0.0, world_size.y + gehweg)
		],
		[Vector3(-gehweg, 0.0, -2.0), Vector3(-gehweg, 0.0, world_size.y + 2.0)],
		[
			Vector3(world_size.x + gehweg, 0.0, -2.0),
			Vector3(world_size.x + gehweg, 0.0, world_size.y + 2.0)
		],
	]
	for i in NPC_ANZAHL:
		var node: Node3D = szene.instantiate()
		node.name = "PassantGooby%d" % i
		node.scale = Vector3.ONE * GOOBY_SCALE * rng.randf_range(0.85, 1.15)
		add_child(node)
		var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
		if player != null:
			for kandidat: String in ["walk", "walk-loop"]:
				if player.has_animation(kandidat):
					player.play(kandidat)
					break
		var strecke: Array = strecken[i % strecken.size()]
		(
			_npcs
			. append(
				{
					"node": node,
					"von": strecke[0],
					"nach": strecke[1],
					"tempo": rng.randf_range(0.8, 1.4),
					"phase": rng.randf(),
				}
			)
		)
	_process(0.0)


# ── GLB-Helfer ───────────────────────────────────────────────────────────────


func _glb(pfad: String, groesse: float) -> Node3D:
	if not ResourceLoader.exists(pfad):
		push_warning("Skyline-Asset fehlt: %s" % pfad)
		return null
	var szene: PackedScene = load(pfad)
	if szene == null:
		return null
	var node: Node3D = szene.instantiate()
	node.scale = Vector3.ONE * groesse
	return node


## LOD auf alle sichtbaren Teile eines GLB legen — die Wurzel eines
## instanzierten GLB ist ein plain Node3D, visibility_range_end lebt aber
## auf GeometryInstance3D.
static func _set_lod(node: Node, ende: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = ende
	for kind in node.get_children():
		_set_lod(kind, ende)


## Node uniform so skalieren, dass die AABB-Höhe `ziel` Meter beträgt.
func _fit_hoehe(node: Node3D, ziel: float) -> void:
	var aabb := _merged_aabb(node, Transform3D.IDENTITY)
	if aabb.size.y <= 0.0001:
		return
	node.scale = Vector3.ONE * (ziel / aabb.size.y)


## AABB-Höhe eines GLB in Kit-Einheiten (für MultiMesh-Normalisierung).
func _glb_hoehe(pfad: String) -> float:
	var node := _glb(pfad, 1.0)
	if node == null:
		return 0.0
	var aabb := _merged_aabb(node, Transform3D.IDENTITY)
	node.free()
	return aabb.size.y


## Alle MeshInstance3D eines GLB als MultiMesh instanziieren (eine
## MultiMeshInstance3D pro Quell-Mesh; deren lokale Transform wird in jede
## Instanz-Transform eingerechnet).
func _multi_aus_glb(
	pfad: String, transforms: Array[Transform3D], basis_name: String, lod_ende := 0.0
) -> void:
	if transforms.is_empty() or not ResourceLoader.exists(pfad):
		return
	var szene: PackedScene = load(pfad)
	if szene == null:
		return
	var vorlage: Node3D = szene.instantiate()
	var quellen: Array[Node] = vorlage.find_children("*", "MeshInstance3D", true, false)
	var index := 0
	for quelle: Node in quellen:
		var mesh_quelle := quelle as MeshInstance3D
		if mesh_quelle.mesh == null:
			continue
		var lokal := _relative_transform(mesh_quelle, vorlage)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh_quelle.mesh
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i] * lokal)
		var instanz := MultiMeshInstance3D.new()
		instanz.name = "%s%d" % [basis_name, index]
		instanz.multimesh = multi
		instanz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if lod_ende > 0.0:
			instanz.visibility_range_end = lod_ende
		add_child(instanz)
		index += 1
	vorlage.free()


func _relative_transform(node: Node3D, wurzel: Node3D) -> Transform3D:
	var out := node.transform
	var eltern := node.get_parent()
	while eltern is Node3D and eltern != wurzel:
		out = (eltern as Node3D).transform * out
		eltern = eltern.get_parent()
	return out


static func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var merged := AABB()
	var found := false
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		merged = local * (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		var sub := _merged_aabb(child, local)
		if sub.size != Vector3.ZERO or sub.position != Vector3.ZERO:
			merged = merged.merge(sub) if found else sub
			found = true
	return merged
