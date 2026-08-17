class_name RanchAtmosphaere
extends Node3D
## Atmosphären-Schicht der offenen Welt (WELT-1) — alles BILLIG:
##
## - MORGENNEBEL: weiche Nebel-Scheiben (Vertex-Alpha-Verlauf, EIN
##   MultiMesh) in den Senken (Moor-Tümpel, Weidetal-Mulde, Bachlauf,
##   Schluchtsohle, Bucht); Deckkraft fährt mit der Uhrzeit (PURE
##   Kurve `nebel_staerke`, Tests rechnen sie nach).
## - WOLKEN + WANDERNDE WOLKENSCHATTEN: sechs weiche Wolken-Blobs in
##   ~130 m Höhe + dunkle Boden-Scheiben, die dem Gelände folgen und
##   mit dem Wind über das Land ziehen (2 MultiMeshes, 6 hoehe()-Calls
##   je Tick).
## - LICHTSTRAHLEN: additive Schräg-Quads an der Wäldchen-Lichtung,
##   nur morgens/abends sichtbar (1 MultiMesh).
## - VOGELSCHWARM: 16 Dreiecks-Vögel als EIN MultiMesh, der Schwarm-
##   Anker fliegt eine große Acht über die Region.
## - ZONEN-AMBIENCE: leise Zusatz-Loops je Zonen-Charakter (Wind am
##   Berg, Grillen im Moor, Wasser am Strand, Vögel im Obstgarten) —
##   weich übergeblendet, ÜBER dem Wetter-Ambience (fremd, bleibt an).

const NEBEL_FARBE := Color(0.94, 0.97, 1.0)
const SCHATTEN_FARBE := Color(0.12, 0.14, 0.2)
const WOLKE_FARBE := Color(1.0, 1.0, 1.0)
const STRAHL_FARBE := Color(1.0, 0.95, 0.75)

## Nebel-Senken: [x, z, radius_m].
const NEBEL_SENKEN: Array[Array] = [
	[760.0, -60.0, 34.0],
	[830.0, -160.0, 40.0],
	[880.0, -90.0, 30.0],
	[770.0, -220.0, 30.0],
	[-470.0, 90.0, 55.0],
	[318.0, 0.0, 36.0],
	[60.0, -807.0, 30.0],
	[890.0, 260.0, 44.0],
]

## Wolken: Startpositionen [x, z] — driften mit WIND_MS nach Ost-Süd-Ost.
const WOLKEN_START: Array[Array] = [
	[-700.0, -900.0],
	[-200.0, -400.0],
	[300.0, -800.0],
	[-500.0, 300.0],
	[200.0, 500.0],
	[700.0, -100.0],
]
const WIND_MS := 4.0
const WOLKEN_HOEHE_M := 132.0

const ZONEN_AMBIENCE: Dictionary = {
	"bergmassiv": {"wind": 0.5},
	"ruine": {"wind": 0.35},
	"kornfeld": {"wind": 0.28},
	"moor": {"grillen": 0.45},
	"strand": {"bach": 0.4},
	"see": {"bach": 0.28},
	"blumenwiese": {"voegel": 0.4},
	"obstgarten": {"voegel": 0.45},
	"waeldchen": {"voegel": 0.32},
}
const AMBIENCE_PFAD := "res://assets/ranch/audio/sfx"
const AMBIENCE_DATEIEN: Dictionary = {
	"wind": "ambience_wind.ogg",
	"grillen": "ambience_grillen.ogg",
	"voegel": "ambience_voegel.ogg",
	"bach": "ambience_bach.ogg",
}

var _nebel_material: StandardMaterial3D
var _strahl_material: StandardMaterial3D
var _wolken_mm: MultiMesh
var _schatten_mm: MultiMesh
var _wolken_pos: Array[Vector2] = []
var _voegel: Node3D
var _vogel_zeit := 0.0
var _loops: Dictionary = {}


## Baut alle Schichten (deterministisch über `seed_wert`).
func einrichten(seed_wert: int) -> void:
	_baue_nebel()
	_baue_wolken(seed_wert)
	_baue_strahlen()
	_baue_voegel()
	_baue_ambience()


## Pro Frame aus der Region-Szene: Uhrzeit steuert Nebel/Strahlen, die
## Wolken ziehen, der Schwarm fliegt, die Zonen-Ambience blendet um.
func tick(delta: float, stunde: float, zone_id: String) -> void:
	if _nebel_material != null:
		_nebel_material.albedo_color = Color(
			NEBEL_FARBE.r, NEBEL_FARBE.g, NEBEL_FARBE.b, 0.55 * nebel_staerke(stunde)
		)
	if _strahl_material != null:
		_strahl_material.albedo_color = Color(
			STRAHL_FARBE.r, STRAHL_FARBE.g, STRAHL_FARBE.b, 0.4 * strahl_staerke(stunde)
		)
	_ziehe_wolken(delta)
	_fliege_schwarm(delta)
	_blende_ambience(delta, zone_id)


## Morgennebel-Deckkraft 0..1: dicht um 6 Uhr, weg ab ~9:30, abends Hauch.
static func nebel_staerke(stunde: float) -> float:
	var morgens := clampf(1.0 - absf(stunde - 6.0) / 3.5, 0.0, 1.0)
	var abends := clampf(1.0 - absf(stunde - 20.5) / 2.5, 0.0, 1.0) * 0.4
	return maxf(morgens * morgens, abends)


## Lichtstrahlen-Stärke 0..1: tief stehende Sonne morgens/abends.
static func strahl_staerke(stunde: float) -> float:
	var morgens := clampf(1.0 - absf(stunde - 7.5) / 2.5, 0.0, 1.0)
	var abends := clampf(1.0 - absf(stunde - 18.5) / 2.5, 0.0, 1.0)
	return maxf(morgens, abends)


## ------------------------------------------------------------------ Bau


func _baue_nebel() -> void:
	# BILLBOARD-Sprites statt flacher Scheiben: eine flache Scheibe ist
	# aus Reiter-Höhe eine unsichtbare Kante — der Kamera zugewandte
	# Radial-Verlauf-Fächer lesen sich aus JEDER Höhe als Nebelbank.
	_nebel_material = _weich_material(NEBEL_FARBE)
	_nebel_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_nebel_material.billboard_keep_scale = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _blob_mesh(_nebel_material, true)
	mm.instance_count = NEBEL_SENKEN.size() * 3
	for i in NEBEL_SENKEN.size():
		var senke: Array = NEBEL_SENKEN[i]
		var x := float(senke[0])
		var z := float(senke[1])
		var radius := float(senke[2])
		for j in 3:
			var versatz := Vector2.from_angle(x * 0.7 + float(j) * 2.1) * radius * 0.34
			var px := x + versatz.x
			var pz := z + versatz.y
			var sx := radius * (0.6 + 0.16 * float(j))
			var sy := radius * 0.2 + 2.5
			var y := RanchGelaende.hoehe(px, pz) + sy * 0.4 + 0.8
			var basis := Basis.IDENTITY.scaled(Vector3(sx, sy, 1.0))
			mm.set_instance_transform(i * 3 + j, Transform3D(basis, Vector3(px, y, pz)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Morgennebel"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.ignore_occlusion_culling = true
	add_child(mmi)


func _baue_wolken(seed_wert: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert + 555
	var wolken_material := _weich_material(Color(WOLKE_FARBE.r, WOLKE_FARBE.g, WOLKE_FARBE.b, 0.8))
	var schatten_material := _weich_material(
		Color(SCHATTEN_FARBE.r, SCHATTEN_FARBE.g, SCHATTEN_FARBE.b, 0.16)
	)
	_wolken_mm = MultiMesh.new()
	_wolken_mm.transform_format = MultiMesh.TRANSFORM_3D
	_wolken_mm.mesh = _blob_mesh(wolken_material)
	_wolken_mm.instance_count = WOLKEN_START.size()
	_schatten_mm = MultiMesh.new()
	_schatten_mm.transform_format = MultiMesh.TRANSFORM_3D
	_schatten_mm.mesh = _blob_mesh(schatten_material)
	_schatten_mm.instance_count = WOLKEN_START.size()
	for start: Array in WOLKEN_START:
		_wolken_pos.append(Vector2(float(start[0]) + rng.randf_range(-60.0, 60.0), float(start[1])))
	_setze_wolken_transforms()
	for paar: Array in [["Wolken", _wolken_mm], ["Wolkenschatten", _schatten_mm]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = str(paar[0])
		mmi.multimesh = paar[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.ignore_occlusion_culling = true
		add_child(mmi)


func _baue_strahlen() -> void:
	var lichtung: Array = RanchKarte.zone("waeldchen")["lichtung"]
	var lx := float(lichtung[0])
	var lz := float(lichtung[1])
	_strahl_material = _weich_material(STRAHL_FARBE)
	_strahl_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _strahl_material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 6
	for i in 6:
		var w := float(i) * 1.05
		var p := Vector2(lx, lz) + Vector2.from_angle(w) * (8.0 + 3.0 * float(i % 3))
		var y := RanchGelaende.hoehe(p.x, p.y) + 6.0
		var basis := Basis(Vector3.UP, w + 0.6)
		basis = basis.rotated(basis.x.normalized(), -0.85)
		basis = basis.scaled(Vector3(1.6 + 0.5 * float(i % 2), 14.0, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, y, p.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Lichtstrahlen"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 420.0
	add_child(mmi)


func _baue_voegel() -> void:
	_voegel = Node3D.new()
	_voegel.name = "Vogelschwarm"
	add_child(_voegel)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for punkt: Vector3 in [
		Vector3(-0.5, 0.0, 0.2),
		Vector3(0.5, 0.0, 0.2),
		Vector3(0.0, 0.08, -0.5),
	]:
		st.set_color(Color(0.2, 0.2, 0.26))
		st.set_normal(Vector3.UP)
		st.add_vertex(punkt)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 16
	for i in 16:
		var w := float(i) / 16.0 * TAU
		var lokal := Vector3(cos(w) * 7.0, sin(w * 3.0) * 1.6, sin(w) * 7.0)
		var basis := Basis(Vector3.UP, w).scaled(Vector3.ONE * 1.6)
		mm.set_instance_transform(i, Transform3D(basis, lokal))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Schwarm"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_voegel.add_child(mmi)


func _baue_ambience() -> void:
	for id: String in AMBIENCE_DATEIEN:
		var pfad := "%s/%s" % [AMBIENCE_PFAD, AMBIENCE_DATEIEN[id]]
		if not ResourceLoader.exists(pfad):
			continue
		var player := AudioStreamPlayer.new()
		player.name = "Ambience_%s" % id
		player.stream = load(pfad)
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		player.volume_db = -60.0
		player.autoplay = false
		add_child(player)
		_loops[id] = player


## -------------------------------------------------------------- Laufzeit


func _ziehe_wolken(delta: float) -> void:
	if _wolken_mm == null:
		return
	var grenzen := RanchKarte.grenzen().grow(150.0)
	var richtung := Vector2(1.0, 0.35).normalized()
	for i in _wolken_pos.size():
		var p := _wolken_pos[i] + richtung * WIND_MS * delta
		if p.x > grenzen.end.x:
			p.x = grenzen.position.x
			p.y = grenzen.position.y + fmod(absf(p.y) * 1.7, grenzen.size.y)
		if p.y > grenzen.end.y:
			p.y = grenzen.position.y
		_wolken_pos[i] = p
	_setze_wolken_transforms()


func _setze_wolken_transforms() -> void:
	for i in _wolken_pos.size():
		var p := _wolken_pos[i]
		var groesse := 60.0 + 14.0 * float(i % 3)
		var wolken_basis := Basis(Vector3.UP, float(i)).scaled(
			Vector3(groesse, 10.0, groesse * 0.7)
		)
		_wolken_mm.set_instance_transform(
			i, Transform3D(wolken_basis, Vector3(p.x, WOLKEN_HOEHE_M, p.y))
		)
		var boden := RanchGelaende.hoehe(p.x, p.y)
		var schatten_basis := Basis(Vector3.UP, float(i)).scaled(
			Vector3(groesse * 0.8, 1.0, groesse * 0.56)
		)
		_schatten_mm.set_instance_transform(
			i, Transform3D(schatten_basis, Vector3(p.x, boden + 0.6, p.y))
		)


func _fliege_schwarm(delta: float) -> void:
	if _voegel == null:
		return
	_vogel_zeit += delta * 0.045
	var t := _vogel_zeit
	var x := sin(t) * 640.0
	var z := sin(t * 2.0) * 420.0 - 160.0
	var y := RanchGelaende.hoehe(x, z) + 34.0 + sin(t * 3.1) * 6.0
	_voegel.position = Vector3(x, y, z)
	_voegel.rotation.y = -t * 2.0


func _blende_ambience(delta: float, zone_id: String) -> void:
	var ziele: Dictionary = ZONEN_AMBIENCE.get(zone_id, {})
	for id: String in _loops:
		var player: AudioStreamPlayer = _loops[id]
		var ziel := float(ziele.get(id, 0.0))
		var jetzt := db_to_linear(player.volume_db) if player.playing else 0.0
		var neu := lerpf(jetzt, ziel, minf(1.0, delta * 1.2))
		if neu < 0.01:
			if player.playing:
				player.stop()
			continue
		player.volume_db = linear_to_db(neu)
		if not player.playing:
			player.play()


## ------------------------------------------------------------- Werkzeug


## Weicher Blob: Dreiecks-Fächer, Mitte Alpha 1 → Rand Alpha 0 (der
## Verlauf steckt in den VERTEX-Farben — keine Textur nötig).
## `aufrecht` legt den Fächer in die XY-Ebene (für Billboard-Sprites).
func _blob_mesh(mat: Material, aufrecht := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var normale := Vector3.BACK if aufrecht else Vector3.UP
	for i in n:
		var w0 := TAU * float(i) / float(n)
		var w1 := TAU * float(i + 1) / float(n)
		var rand0 := Vector3(cos(w0), sin(w0), 0.0) if aufrecht else Vector3(cos(w0), 0.0, sin(w0))
		var rand1 := Vector3(cos(w1), sin(w1), 0.0) if aufrecht else Vector3(cos(w1), 0.0, sin(w1))
		st.set_color(Color(1, 1, 1, 1))
		st.set_normal(normale)
		st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1, 1, 1, 0))
		st.set_normal(normale)
		st.add_vertex(rand1)
		st.set_color(Color(1, 1, 1, 0))
		st.set_normal(normale)
		st.add_vertex(rand0)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## Unshaded + Vertex-Alpha + Material-Alpha (für die Tages-Steuerung).
func _weich_material(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = farbe
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = false
	return mat
