extends SceneTree
## ASSET-ROT-Screenshot-Treiber (KEIN Test): fotografiert Welt-/Ort-Szenen
## für die visuelle Orientierungs-Sichtung (UserFeedback „alle Assets richtig
## rotiert/richtig rum"). Pro Szene: 2 Übersichten (diagonal von oben) plus
## automatische Nahaufnahmen der dichtesten Cluster von RICHTUNGS-Assets
## (Autos, Möbel, Schilder … — Muster aus asset_rot_regeln.gd), denn falsche
## Yaw-Drehungen (Rückseite zur Straße/Wand) sieht nur das Auge.
##
## Aufruf (echter Renderer nötig; immer Lock + Isolations-Wrapper):
##   flock -w 7200 /tmp/gooby_godot_global.lock \
##     tools/ci/run_godot_isolated.sh xvfb-run -a godot --path GOOBY-GODOT \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1280x720 \
##     --script res://tests/tools/asset_rot_screens.gd -- [nur=<teilstring>]

const Regeln := preload("res://tests/tools/asset_rot_regeln.gd")

const OUT_DIR := "/tmp/gooby-godot/artifacts/ASSET-ROT/screens"
const SETTLE_FRAMES := 40
const MAX_CLUSTER_SHOTS := 4
const CLUSTER_RADIUS := 6.0

const SZENEN: Array[String] = [
	"res://scenes/home/schlafzimmer.tscn",
	"res://scenes/home/wohnzimmer.tscn",
	"res://scenes/home/kueche.tscn",
	"res://scenes/home/bad.tscn",
	"res://scenes/home/garten.tscn",
	"res://scenes/city/city_scene.tscn",
	"res://scenes/city/orte/autohaus.tscn",
	"res://scenes/city/orte/baumarkt.tscn",
	"res://scenes/city/orte/flughafen.tscn",
	"res://scenes/city/orte/goobyman.tscn",
	"res://scenes/city/orte/goobytheke.tscn",
	"res://scenes/city/orte/gouhbus.tscn",
	"res://scenes/city/orte/post.tscn",
	"res://scenes/city/orte/pow.tscn",
	"res://scenes/city/orte/raumstation.tscn",
	"res://scenes/city/orte/rehwei.tscn",
	"res://scenes/city/orte/tierarzt.tscn",
	"res://scenes/city/orte/wochenmarkt.tscn",
	"res://scenes/city/urlaub/urlaub_berge.tscn",
	"res://scenes/city/urlaub/urlaub_stadt.tscn",
	"res://scenes/city/urlaub/urlaub_strand.tscn",
	"res://scenes/park/funkelpark.tscn",
	"res://scenes/ranch/ranch_hof.tscn",
	"res://scenes/ranch/dorf/hufingen.tscn",
	"res://scripts/dlc/goobye/laden_scene.tscn",
]

var _cam: Camera3D
var _filter := ""


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("nur="):
			_filter = arg.trim_prefix("nur=")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.near = 0.05
	_cam.far = 4000.0
	root.add_child(_cam)
	for pfad in SZENEN:
		if _filter != "" and not pfad.contains(_filter):
			continue
		await _fotografiere(pfad)
	print("[ASSET-ROT-SCREENS] fertig -> %s" % OUT_DIR)
	quit(0)


func _fotografiere(pfad: String) -> void:
	var packed: PackedScene = load(pfad)
	if packed == null:
		print("[ASSET-ROT-SCREENS] lädt nicht: %s" % pfad)
		return
	var szene: Node = packed.instantiate()
	root.add_child(szene)
	for _i in SETTLE_FRAMES:
		await process_frame
	_verstecke_ui(szene)
	await process_frame
	var kurz := pfad.get_file().get_basename()
	# Ground-Truth zuerst: die szeneneigene (Spieler-)Kamera, falls vorhanden.
	var eigene := _finde_kamera(szene)
	if eigene != null:
		eigene.current = true
		for _i in 10:
			await process_frame
		var bild := root.get_texture().get_image()
		bild.save_png("%s/%s_spieler_sicht.png" % [OUT_DIR, kurz])
		print("[ASSET-ROT-SCREENS] %s_spieler_sicht.png" % kurz)
	var box := _mesh_aabb(szene)
	if box.size == Vector3.ZERO:
		print("[ASSET-ROT-SCREENS] keine Meshes: %s" % pfad)
	else:
		var mitte := box.get_center()
		var radius := maxf(box.size.x, box.size.z) * 0.62 + 2.0
		var hoehe := mitte.y + box.size.y * 0.9 + radius * 0.55
		for blick: Array in [[1.0, 1.0, "a"], [-1.0, -1.0, "b"]]:
			var pos := Vector3(
				mitte.x + radius * float(blick[0]), hoehe, mitte.z + radius * float(blick[1])
			)
			await _schuss(pos, mitte, "%s_uebersicht_%s.png" % [kurz, str(blick[2])])
		if maxf(box.size.x, box.size.z) < 40.0:
			# Innenraum-Blicke (Läden/Zimmer): Augenhöhe aus den Raumecken.
			var boden := box.position.y + 1.55
			for ecke: Array in [[0.26, 0.26, "c"], [0.74, 0.74, "d"]]:
				var innen := Vector3(
					box.position.x + box.size.x * float(ecke[0]),
					boden,
					box.position.z + box.size.z * float(ecke[1])
				)
				var ziel_mitte := Vector3(mitte.x, boden - 0.35, mitte.z)
				await _schuss(innen, ziel_mitte, "%s_innen_%s.png" % [kurz, str(ecke[2])])
		var ziele := _richtungs_cluster(szene)
		for i in mini(ziele.size(), MAX_CLUSTER_SHOTS):
			var ziel: Vector3 = ziele[i]
			for seite: Array in [[1.0, "a"], [-1.0, "b"]]:
				var vorzeichen := float(seite[0])
				var cam_pos := ziel + Vector3(7.5 * vorzeichen, 4.5, 7.5 * vorzeichen)
				var datei := "%s_detail_%d%s.png" % [kurz, i, str(seite[1])]
				await _schuss(cam_pos, ziel + Vector3(0, 0.6, 0), datei)
	szene.queue_free()
	await process_frame
	await process_frame


func _finde_kamera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for kind in node.get_children():
		var treffer := _finde_kamera(kind)
		if treffer != null:
			return treffer
	return null


## Blendet HUD/Dialoge/Karten aus, damit die 3D-Platzierung sichtbar wird.
func _verstecke_ui(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is Control:
		(node as Control).visible = false
		return
	for kind in node.get_children():
		_verstecke_ui(kind)


## Cluster-Zentren der Richtungs-Assets, dichteste zuerst.
func _richtungs_cluster(szene: Node) -> Array[Vector3]:
	var punkte: Array[Vector3] = []
	_sammle_richtungs_punkte(szene, punkte)
	var cluster: Array[Dictionary] = []
	for punkt in punkte:
		var gefunden := false
		for eintrag in cluster:
			if (eintrag["mitte"] as Vector3).distance_to(punkt) < CLUSTER_RADIUS:
				eintrag["summe"] = (eintrag["summe"] as Vector3) + punkt
				eintrag["n"] = int(eintrag["n"]) + 1
				eintrag["mitte"] = (eintrag["summe"] as Vector3) / float(eintrag["n"])
				gefunden = true
				break
		if not gefunden:
			cluster.append({"mitte": punkt, "summe": punkt, "n": 1})
	cluster.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) > int(b["n"])
	)
	var out: Array[Vector3] = []
	for eintrag in cluster:
		out.append(eintrag["mitte"])
	return out


func _sammle_richtungs_punkte(node: Node, out: Array[Vector3]) -> void:
	if node is Skeleton3D:
		return
	if node is Node3D and (node as Node3D).is_visible_in_tree():
		var pfad := node.scene_file_path
		if pfad.ends_with(".glb") or pfad.ends_with(".gltf"):
			var probe := (pfad.get_file() + " " + str(node.name)).to_lower()
			for muster: String in Regeln.RICHTUNGS_MUSTER:
				if probe.contains(muster):
					out.append((node as Node3D).global_position)
					break
	for kind in node.get_children():
		_sammle_richtungs_punkte(kind, out)


func _mesh_aabb(szene: Node) -> AABB:
	var box := AABB()
	var erster := true
	var stapel: Array[Node] = [szene]
	while not stapel.is_empty():
		var node: Node = stapel.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree():
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var welt: AABB = mi.global_transform * mi.get_aabb()
				box = welt if erster else box.merge(welt)
				erster = false
		for kind in node.get_children():
			stapel.append(kind)
	return box


func _schuss(pos: Vector3, ziel: Vector3, datei: String) -> void:
	_cam.current = true
	_cam.global_position = pos
	if pos.distance_to(ziel) > 0.01:
		_cam.look_at(ziel)
	for _i in 14:
		await process_frame
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("[ASSET-ROT-SCREENS] %s" % datei)
