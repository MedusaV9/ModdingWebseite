class_name RanchWetterController
extends Node3D
## Wetter-Fahrer der Ranch-Region (RW-1): verdrahtet den puren RanchWetter-
## Plan in die Szene — Himmel/Licht (Tag/Nacht-Kurve aus CityAmbiente,
## vom Wetter gedimmt), Nebel, Regen-/Blätter-/Staub-Partikel, Wolken,
## Sterne + Mond, Regenbogen, Pfützen und die Ambience-Loops
## (assets/ranch/audio/sfx/ambience_*.ogg). Andere Systeme docken an
## `wetter_changed` an. Alles Wetter ist deterministisch (Datum + Seed).

signal wetter_changed(zustand: Dictionary)

const AMBIENCE_PFAD := "res://assets/ranch/audio/sfx"

## Ambience-Loop-Dateien (Id → Datei).
const LOOPS := {
	"regen": "ambience_regen.ogg",
	"gewitter": "ambience_gewitter.ogg",
	"wind": "ambience_wind.ogg",
	"voegel": "ambience_voegel.ogg",
	"grillen": "ambience_grillen.ogg",
	"bach": "ambience_bach.ogg",
}

## Regenbogen-Bänder (außen → innen, Pastell).
const REGENBOGEN_FARBEN: Array[Color] = [
	Color(0.94, 0.42, 0.42, 0.30),
	Color(0.96, 0.65, 0.38, 0.28),
	Color(0.97, 0.88, 0.45, 0.26),
	Color(0.55, 0.83, 0.50, 0.26),
	Color(0.45, 0.66, 0.92, 0.28),
	Color(0.62, 0.50, 0.88, 0.26),
]

const WOLKEN_ANZAHL := 34
const STERNE_ANZAHL := 130

## Screenshots/Tests erzwingen eine Wetterlage ("" = Plan; zusätzlich
## "regenbogen" = Sonne + nasser Boden am Abend).
var wetter_override := ""
var seed_wert := 0
var datum := ""
var zustand: Dictionary = {}

var _env: Environment
var _sonne: DirectionalLight3D
var _terrain_mat: StandardMaterial3D
var _terrain_albedo := Color.WHITE
var _gras_shader: ShaderMaterial
var _regen: GPUParticles3D
var _blaetter: GPUParticles3D
var _staub: GPUParticles3D
var _wolken: MultiMeshInstance3D
var _wolken_mat: StandardMaterial3D
var _sterne: MultiMeshInstance3D
var _sterne_mat: StandardMaterial3D
var _mond: MeshInstance3D
var _regenbogen: Node3D
var _pfuetzen: MultiMeshInstance3D
var _loops: Dictionary = {}
var _zeit := 0.0
var _blitz_rest := 0.0
var _blitz_pause := 5.0
var _bach_naehe := 0.0
var _blitz_rng := RandomNumberGenerator.new()


## Verdrahtung: Environment + Sonne (+ optional Terrain-Material fürs
## Nass-Dunkeln, Gras-Shader für Wind). Baut alle Effekt-Knoten.
func einrichten(
	env: Environment,
	sonne: DirectionalLight3D,
	terrain_mat: StandardMaterial3D = null,
	gras_shader: ShaderMaterial = null
) -> void:
	_env = env
	_sonne = sonne
	_terrain_mat = terrain_mat
	if terrain_mat != null:
		_terrain_albedo = terrain_mat.albedo_color
	_gras_shader = gras_shader
	_blitz_rng.seed = seed_wert + 77
	_baue_regen()
	_baue_blaetter()
	_baue_staub()
	_baue_wolken()
	_baue_sterne_und_mond()
	_baue_regenbogen()
	_baue_pfuetzen()
	_baue_loops()


## Ein Wetter-Tick: Zustand berechnen, Effekte + Licht + Ton nachziehen.
## `fokus` = Reiter-/Kamera-Position (Partikel folgen ihr).
func tick(delta: float, stunde: float, fokus: Vector3) -> void:
	_zeit += delta
	var vorher_typ := str(zustand.get("typ", ""))
	zustand = _zustand_jetzt(stunde)
	if str(zustand["typ"]) != vorher_typ:
		wetter_changed.emit(zustand)
	_wende_licht_an(stunde)
	_wende_partikel_an(fokus)
	_wende_himmel_an(stunde, fokus)
	_wende_boden_an()
	_wende_ton_an(stunde, delta)
	if _gras_shader != null:
		_gras_shader.set_shader_parameter("wind", RanchWetter.boe(_zeit, float(zustand["wind"])))


## Bach-Nähe 0..1 (Szene misst den Abstand) — steuert den Bach-Loop.
func set_bach_naehe(wert: float) -> void:
	_bach_naehe = clampf(wert, 0.0, 1.0)


## ------------------------------------------------------------- Zustand


func _zustand_jetzt(stunde: float) -> Dictionary:
	if wetter_override.is_empty():
		return RanchWetter.zustand(datum, stunde, seed_wert)
	var typ := wetter_override
	var naesse := 0.0
	var regenbogen := false
	if typ == "regenbogen":
		typ = "sonne"
		naesse = 0.5
		regenbogen = true
	elif RanchWetter.REGEN_TYPEN.has(typ):
		naesse = 0.8
	return {
		"typ": typ,
		"vorher": typ,
		"blend": 1.0,
		"intensitaet": 0.85,
		"wind": 0.9 if typ == "gewitter" else 0.45,
		"bewoelkung": float(RanchWetter.BEWOELKUNG[typ]),
		"naesse": naesse,
		"regenbogen": regenbogen,
		"licht_faktor": float(RanchWetter.LICHT_FAKTOR[typ]),
		"nebel_dichte": 0.8 if typ == "nebel" else 0.0,
		"name_key": "rwelt.wetter.%s" % typ,
	}


## --------------------------------------------------------------- Licht


## Tageskurve aus CityAmbiente, vom Wetter gedimmt/entsättigt; Gewitter
## blitzt (kurzer Energie-Spike auf der Sonne).
func _wende_licht_an(stunde: float) -> void:
	if _env == null or _sonne == null:
		return
	var profil := CityAmbiente.licht_profil(stunde)
	var faktor := float(zustand["licht_faktor"])
	var grau := float(zustand["bewoelkung"]) * 0.55
	# Hoch stehende Sonne: steiler Einfall trifft den Boden ~3x härter als
	# das flache Abendlicht UND der warme Stadt-Ton kippt die Wiese ins
	# Gelbe — Energie elevation-kompensieren, Farbe Richtung Neutralweiß.
	var mittag := clampf((float(profil["elevation"]) - 25.0) / 30.0, 0.0, 1.0)
	_sonne.light_energy = (
		float(profil["sonnen_energie"]) * lerpf(1.0, faktor, 0.85) * 0.85 * lerpf(1.0, 0.62, mittag)
	)
	var farbe: Color = profil["sonnen_farbe"]
	farbe = farbe.lerp(Color(1.0, 0.99, 0.96), mittag * 0.85)
	_sonne.light_color = farbe.lerp(Color(0.82, 0.84, 0.88), grau)
	_sonne.rotation_degrees = Vector3(-float(profil["elevation"]), -35.0, 0.0)
	# Farb-Ambient (siehe RanchRegionScene._baue_licht): warm am Tag, kühles
	# Blau in der Nacht, bei Bewölkung grau getönt — Energie unter dem
	# Stadt-Profil (sonst brennt der Wiesen-Pastellton aus) und deutlich vom
	# Wetter gedimmt, sonst bleibt das Gewitter freundlich hell.
	var tag := CityAmbiente.tageslicht(stunde)
	var ambient := Color(0.88, 0.9, 0.86).lerp(Color(0.21, 0.25, 0.38), 1.0 - tag)
	_env.ambient_light_color = ambient.lerp(Color(0.56, 0.6, 0.68), grau * 0.7)
	_env.ambient_light_energy = (float(profil["ambient_energie"]) * lerpf(1.0, faktor, 0.75) * 0.7)
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	var wolke := Color(0.72, 0.75, 0.8)
	sky.sky_top_color = (profil["himmel_oben"] as Color).lerp(wolke * 0.7, grau)
	sky.sky_horizon_color = (profil["himmel_horizont"] as Color).lerp(wolke, grau)
	sky.ground_horizon_color = (profil["boden_horizont"] as Color).lerp(wolke * 0.8, grau)
	sky.ground_bottom_color = (profil["boden_unten"] as Color).lerp(wolke * 0.5, grau)
	_wende_nebel_an()
	_wende_blitz_an()


func _wende_nebel_an() -> void:
	var dichte := float(zustand["nebel_dichte"])
	_env.fog_enabled = dichte > 0.01
	_env.fog_light_color = Color(0.86, 0.89, 0.92)
	_env.fog_density = dichte * 0.012
	_env.fog_sky_affect = clampf(dichte * 0.85, 0.0, 1.0)


func _wende_blitz_an() -> void:
	if str(zustand["typ"]) != "gewitter" or float(zustand["blend"]) < 0.9:
		_blitz_rest = 0.0
		return
	_blitz_pause -= get_process_delta_time()
	if _blitz_pause <= 0.0:
		_blitz_rest = 0.16
		_blitz_pause = _blitz_rng.randf_range(3.5, 9.0)
	if _blitz_rest > 0.0:
		_blitz_rest -= get_process_delta_time()
		_sonne.light_energy = 2.6
		_sonne.light_color = Color(0.95, 0.96, 1.0)


## ------------------------------------------------------------ Partikel


func _wende_partikel_an(fokus: Vector3) -> void:
	var typ := str(zustand["typ"])
	var intensitaet := float(zustand["intensitaet"]) * float(zustand["blend"])
	var regnet := RanchWetter.REGEN_TYPEN.has(typ)
	_regen.emitting = regnet
	if regnet:
		_regen.global_position = fokus + Vector3(0.0, 26.0, 0.0)
		_regen.amount_ratio = clampf((0.25 if typ == "niesel" else 1.0) * intensitaet, 0.05, 1.0)
	var windig := RanchWetter.boe(_zeit, float(zustand["wind"])) > 0.55
	_blaetter.emitting = windig and not regnet
	if _blaetter.emitting:
		_blaetter.global_position = fokus + Vector3(0.0, 3.0, 0.0)
	var sonnig := typ == "sonne" and float(zustand["bewoelkung"]) < 0.3
	_staub.emitting = sonnig and _sonne != null and _sonne.light_energy > 0.5
	if _staub.emitting:
		_staub.global_position = fokus + Vector3(0.0, 2.2, 0.0)


func _wende_himmel_an(stunde: float, fokus: Vector3) -> void:
	var bewoelkung := float(zustand["bewoelkung"])
	_wolken.multimesh.visible_instance_count = int(round(bewoelkung * float(WOLKEN_ANZAHL)))
	_wolken.position.x = fposmod(_zeit * (2.0 + float(zustand["wind"]) * 6.0), 700.0) - 350.0
	var dunkel := clampf((bewoelkung - 0.55) * 1.6, 0.0, 1.0)
	_wolken_mat.albedo_color = Color(1, 1, 1, 0.82).lerp(Color(0.42, 0.44, 0.5, 0.9), dunkel)
	var nacht := 1.0 - CityAmbiente.tageslicht(stunde)
	var klar := 1.0 - bewoelkung
	_sterne_mat.albedo_color.a = clampf(nacht * klar, 0.0, 1.0) * 0.9
	_sterne.visible = _sterne_mat.albedo_color.a > 0.02
	_mond.visible = nacht > 0.35 and bewoelkung < 0.85
	_regenbogen.visible = bool(zustand["regenbogen"])
	if _regenbogen.visible:
		# Weit weg, damit der ganze Bogen (Scheitel ~27 Grad ueber dem
		# Horizont) in ein 62-Grad-FOV passt statt ueber der Kamera zu enden.
		_regenbogen.position = Vector3(fokus.x, 0.0, fokus.z - 380.0)


## Pfützen wachsen mit der Nässe; nasser Boden dunkelt leicht ab.
func _wende_boden_an() -> void:
	var naesse := float(zustand["naesse"])
	_pfuetzen.visible = naesse > 0.12
	if _pfuetzen.visible:
		var skala := clampf(naesse, 0.2, 1.0)
		_pfuetzen.scale = Vector3(skala, 1.0, skala)
	if _terrain_mat != null:
		_terrain_mat.albedo_color = _terrain_albedo.darkened(naesse * 0.18)


## ----------------------------------------------------------------- Ton


func _wende_ton_an(stunde: float, delta: float) -> void:
	var typ := str(zustand["typ"])
	var intensitaet := float(zustand["intensitaet"]) * float(zustand["blend"])
	var regnet := RanchWetter.REGEN_TYPEN.has(typ)
	var tag := CityAmbiente.tageslicht(stunde)
	var ziele := {
		"regen": (0.25 if typ == "niesel" else 0.8) * intensitaet if regnet else 0.0,
		"gewitter": 0.9 * intensitaet if typ == "gewitter" else 0.0,
		"wind": clampf(float(zustand["wind"]) - 0.25, 0.0, 1.0) * 0.7,
		"voegel": 0.6 * tag if not regnet else 0.0,
		"grillen": 0.55 * (1.0 - tag) if not regnet else 0.0,
		"bach": _bach_naehe * 0.85,
	}
	for id: String in _loops:
		var player: AudioStreamPlayer = _loops[id]
		var ziel := float(ziele.get(id, 0.0))
		var jetzt := db_to_linear(player.volume_db) if player.playing else 0.0
		var neu := lerpf(jetzt, ziel, minf(1.0, delta * 1.5))
		if neu < 0.01:
			if player.playing:
				player.stop()
			continue
		player.volume_db = linear_to_db(neu)
		if not player.playing:
			player.play()


## ------------------------------------------------------------------ Bau


func _baue_regen() -> void:
	_regen = GPUParticles3D.new()
	_regen.name = "Regen"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(34.0, 2.0, 34.0)
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 3.0
	mat.initial_velocity_min = 16.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3(0.0, -22.0, 0.0)
	_regen.process_material = mat
	_regen.amount = 1200
	_regen.lifetime = 1.6
	_regen.emitting = false
	# Default-visibility_aabb ist 8x8x8 m — der Knoten haengt aber 26 m
	# UEBER der Kamera: Box raus aus dem Frustum -> ALLE Tropfen gecullt.
	_regen.visibility_aabb = AABB(Vector3(-44.0, -34.0, -44.0), Vector3(88.0, 42.0, 88.0))
	var quad := QuadMesh.new()
	# Breit + kräftig genug, dass Tropfen auch auf 720p-Screens lesbar sind.
	quad.size = Vector2(0.07, 0.62)
	quad.material = _unlit(Color(0.62, 0.72, 0.88, 0.6), true)
	_regen.draw_pass_1 = quad
	add_child(_regen)


func _baue_blaetter() -> void:
	_blaetter = GPUParticles3D.new()
	_blaetter.name = "Blaetterwirbel"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(24.0, 3.0, 24.0)
	mat.direction = Vector3(1.0, 0.15, 0.3)
	mat.spread = 30.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0.0, -0.6, 0.0)
	mat.angular_velocity_min = -220.0
	mat.angular_velocity_max = 220.0
	_blaetter.process_material = mat
	_blaetter.amount = 46
	_blaetter.lifetime = 5.0
	_blaetter.emitting = false
	_blaetter.visibility_aabb = AABB(Vector3(-34.0, -10.0, -34.0), Vector3(68.0, 20.0, 68.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.16)
	quad.material = _unlit(Color(0.62, 0.72, 0.34, 0.9), true)
	_blaetter.draw_pass_1 = quad
	add_child(_blaetter)


func _baue_staub() -> void:
	_staub = GPUParticles3D.new()
	_staub.name = "Sonnenstaub"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(14.0, 3.0, 14.0)
	mat.direction = Vector3(0.2, 0.05, 0.0)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.5
	mat.gravity = Vector3(0.0, -0.02, 0.0)
	_staub.process_material = mat
	_staub.amount = 70
	_staub.lifetime = 7.0
	_staub.emitting = false
	_staub.visibility_aabb = AABB(Vector3(-18.0, -6.0, -18.0), Vector3(36.0, 12.0, 36.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = _unlit(Color(1.0, 0.95, 0.75, 0.35), true)
	_staub.draw_pass_1 = quad
	add_child(_staub)


func _baue_wolken() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert + 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 0.7
	puff.radial_segments = 10
	puff.rings = 5
	_wolken_mat = _unlit(Color(1, 1, 1, 0.82), false)
	puff.material = _wolken_mat
	mm.mesh = puff
	mm.instance_count = WOLKEN_ANZAHL
	for i in WOLKEN_ANZAHL:
		var pos := Vector3(
			rng.randf_range(-650.0, 650.0),
			rng.randf_range(105.0, 145.0),
			rng.randf_range(-620.0, 620.0)
		)
		var skala := Vector3(rng.randf_range(26.0, 60.0), rng.randf_range(7.0, 13.0), 0.0)
		skala.z = skala.x * rng.randf_range(0.55, 0.85)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(skala), pos))
	_wolken = MultiMeshInstance3D.new()
	_wolken.name = "Wolken"
	_wolken.multimesh = mm
	_wolken.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wolken)


func _baue_sterne_und_mond() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert + 9
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var punkt := SphereMesh.new()
	punkt.radius = 0.5
	punkt.height = 1.0
	punkt.radial_segments = 6
	punkt.rings = 3
	_sterne_mat = _unlit(Color(1.0, 0.98, 0.9, 0.9), false)
	punkt.material = _sterne_mat
	mm.mesh = punkt
	mm.instance_count = STERNE_ANZAHL
	for i in STERNE_ANZAHL:
		var winkel := rng.randf() * TAU
		var elevation := rng.randf_range(0.12, 1.35)
		var radius := 620.0
		var pos := Vector3(
			cos(winkel) * cos(elevation) * radius,
			sin(elevation) * radius * 0.55 + 60.0,
			sin(winkel) * cos(elevation) * radius
		)
		var s := rng.randf_range(0.7, 1.9)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), pos))
	_sterne = MultiMeshInstance3D.new()
	_sterne.name = "Sterne"
	_sterne.multimesh = mm
	_sterne.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sterne)
	_mond = MeshInstance3D.new()
	_mond.name = "Mond"
	var kugel := SphereMesh.new()
	kugel.radius = 14.0
	kugel.height = 28.0
	kugel.material = _unlit(Color(0.93, 0.94, 0.88, 0.95), false)
	_mond.mesh = kugel
	_mond.position = Vector3(320.0, 300.0, -420.0)
	_mond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mond)


## Regenbogen: halbrunde Pastell-Bänder als EIN Mesh (SurfaceTool).
func _baue_regenbogen() -> void:
	_regenbogen = Node3D.new()
	_regenbogen.name = "Regenbogen"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 190.0
	var band := 9.0
	for b in REGENBOGEN_FARBEN.size():
		var farbe := REGENBOGEN_FARBEN[b]
		var r_aussen := radius - float(b) * band
		var r_innen := r_aussen - band
		var schritte := 40
		for i in schritte:
			var w0 := PI * float(i) / float(schritte)
			var w1 := PI * float(i + 1) / float(schritte)
			var a0 := Vector3(cos(w0) * r_aussen, sin(w0) * r_aussen, 0.0)
			var a1 := Vector3(cos(w1) * r_aussen, sin(w1) * r_aussen, 0.0)
			var i0 := Vector3(cos(w0) * r_innen, sin(w0) * r_innen, 0.0)
			var i1 := Vector3(cos(w1) * r_innen, sin(w1) * r_innen, 0.0)
			st.set_color(farbe)
			for v: Vector3 in [a0, i0, a1, a1, i0, i1]:
				st.add_vertex(v)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	var mat := _unlit(Color.WHITE, false)
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_regenbogen.add_child(mi)
	_regenbogen.position = Vector3(0.0, 0.0, -40.0)
	_regenbogen.visible = false
	add_child(_regenbogen)


## Pfützen an den Karten-Positionen (flache Wasser-Scheiben, MultiMesh).
func _baue_pfuetzen() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var scheibe := CylinderMesh.new()
	scheibe.top_radius = 1.0
	scheibe.bottom_radius = 1.0
	scheibe.height = 0.02
	scheibe.radial_segments = 14
	var mat := _unlit(Color(0.55, 0.72, 0.86, 0.6), false)
	mat.roughness = 0.1
	scheibe.material = mat
	mm.mesh = scheibe
	var punkte: Array = RanchKarte.karte()["pfuetzen"]
	mm.instance_count = punkte.size()
	for i in punkte.size():
		var p: Array = punkte[i]
		var x := float(p[0])
		var z := float(p[1])
		var pos := Vector3(x, RanchGelaende.hoehe(x, z) + 0.06, z)
		var basis := Basis.from_scale(Vector3(2.6 + float(i % 3), 1.0, 1.8 + float(i % 2)))
		mm.set_instance_transform(i, Transform3D(basis, pos))
	_pfuetzen = MultiMeshInstance3D.new()
	_pfuetzen.name = "Pfuetzen"
	_pfuetzen.multimesh = mm
	_pfuetzen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pfuetzen.visible = false
	add_child(_pfuetzen)


func _baue_loops() -> void:
	for id: String in LOOPS:
		var pfad := "%s/%s" % [AMBIENCE_PFAD, LOOPS[id]]
		if not ResourceLoader.exists(pfad):
			continue
		var stream: AudioStream = load(pfad)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		var player := AudioStreamPlayer.new()
		player.name = "Loop_%s" % id
		player.stream = stream
		player.bus = &"Sfx"
		player.volume_db = -60.0
		add_child(player)
		_loops[id] = player


func _unlit(farbe: Color, billboard: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if farbe.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return mat
