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

## Permanenter Fern-Dunst (FB-2 Fernsicht): Quelle ist die kalibrierte
## Außen-Dichte (LichtKalibrierung.NEBEL_DICHTE_DRAUSSEN, ausgelegt auf
## Garten-/Stadt-Sichtweiten), skaliert auf die Kilometer-Blickachsen der
## Ranch. Faktor empirisch: volle Dichte söffe die Bergketten komplett ab;
## 0.13 (~0.0011) wusch die Übersicht grau aus, 0.07 (~0.0006) ließ die
## Ketten noch zu ~50 % in Nebelfarbe absaufen -> 0.035 (~0.0003).
const FERN_NEBEL_SKALIERUNG := 0.035

## Screenshots/Tests erzwingen eine Wetterlage ("" = Plan; zusätzlich
## "regenbogen" = Sonne + nasser Boden am Abend).
var wetter_override := ""
var seed_wert := 0
var datum := ""
var zustand: Dictionary = {}

## FB-2: eigener Sky-Fahrer (prozeduraler Shader). Wenn gesetzt, färbt er
## den Himmel statt des ProceduralSkyMaterial-Fallbacks — Wetter-Signale
## und Himmel-Stimmung bleiben dadurch synchron.
var himmel: GoobyHimmel

var _env: Environment
var _sonne: DirectionalLight3D
var _terrain_mat: StandardMaterial3D
var _terrain_albedo := Color.WHITE
var _terrain_rauheit := 0.95
## Weitere Boden-Materialien (Wege/Trampelpfade), die bei Nässe dunkeln
## und glänzen — Liste aus [material, basis_albedo, basis_rauheit].
var _nass_mats: Array[Array] = []
var _gras_shader: ShaderMaterial
var _regen: GPUParticles3D
var _regen_fern: GPUParticles3D
var _spritzer: GPUParticles3D
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
	gras_shader: ShaderMaterial = null,
	nass_mats: Array[StandardMaterial3D] = []
) -> void:
	_env = env
	_sonne = sonne
	_terrain_mat = terrain_mat
	if terrain_mat != null:
		_terrain_albedo = terrain_mat.albedo_color
		_terrain_rauheit = terrain_mat.roughness
	for mat in nass_mats:
		_nass_mats.append([mat, mat.albedo_color, mat.roughness])
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
	var boee := RanchWetter.boe(_zeit, float(zustand["wind"]))
	if _gras_shader != null:
		_gras_shader.set_shader_parameter("wind", boee)
	# VIS-1: Billboard-Flora (Korn/Lavendel) wogt mit derselben Böe, die
	# Wasserflächen kräuseln bei Nässe (Regen-Uniform im wasser.gdshader).
	for mat in WeltFlora.wind_materialien():
		mat.set_shader_parameter("wind", boee)
	var naesse := float(zustand["naesse"])
	for mat in WeltWasser.materialien():
		mat.set_shader_parameter("regen", naesse)


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
		float(profil["sonnen_energie"]) * lerpf(1.0, faktor, 0.85) * 0.66 * lerpf(1.0, 0.44, mittag)
	)
	var farbe: Color = profil["sonnen_farbe"]
	farbe = farbe.lerp(Color(1.0, 0.99, 0.96), mittag * 0.85)
	_sonne.light_color = farbe.lerp(Color(0.82, 0.84, 0.88), grau)
	_sonne.rotation_degrees = Vector3(-float(profil["elevation"]), -35.0, 0.0)
	# Farb-Ambient (siehe RanchRegionScene._baue_licht): warm am Tag, kühles
	# Blau in der Nacht, bei Bewölkung grau getönt — die TAGES-Energie folgt
	# dem kalibrierten Außen-Budget (Lens B: Farb-Ambient 0,77 hob die
	# Pastell-Wiese auf 0,69 Luma; Budget 0,36 = Profil-Spitze 1,1 × 0,33
	# holt sie ins Zielfenster), nachts bleibt der alte Spielbarkeits-Boden
	# (NACHT_LUMA_MIN). Wetter dimmt weiter, sonst bleibt Gewitter zu hell.
	var tag := CityAmbiente.tageslicht(stunde)
	var ambient := Color(0.88, 0.9, 0.86).lerp(Color(0.21, 0.25, 0.38), 1.0 - tag)
	_env.ambient_light_color = ambient.lerp(Color(0.56, 0.6, 0.68), grau * 0.7)
	var ambient_skala := lerpf(0.7, LichtKalibrierung.BUDGET_DRAUSSEN_AMBIENT_TAG / 1.1, tag)
	_env.ambient_light_energy = (
		float(profil["ambient_energie"]) * lerpf(1.0, faktor, 0.75) * ambient_skala
	)
	if himmel != null:
		himmel.wende_an(stunde, zustand)
	else:
		var sky := _env.sky.sky_material as ProceduralSkyMaterial
		var wolke := Color(0.72, 0.75, 0.8)
		sky.sky_top_color = (profil["himmel_oben"] as Color).lerp(wolke * 0.7, grau)
		sky.sky_horizon_color = (profil["himmel_horizont"] as Color).lerp(wolke, grau)
		sky.ground_horizon_color = (profil["boden_horizont"] as Color).lerp(wolke * 0.8, grau)
		sky.ground_bottom_color = (profil["boden_unten"] as Color).lerp(wolke * 0.5, grau)
	_wende_nebel_an()
	_wende_blitz_an()


## Wetter-Nebel + permanenter Fern-Dunst (FB-2): der Fern-Dunst hazed die
## Bergketten nach Distanz (Farbe = Himmel-Horizont), Wetter-Nebel legt
## sich obendrauf und darf auch den Himmel eintrüben.
func _wende_nebel_an() -> void:
	var dichte := float(zustand["nebel_dichte"])
	var fern := 0.0
	if himmel != null:
		fern = LichtKalibrierung.NEBEL_DICHTE_DRAUSSEN * FERN_NEBEL_SKALIERUNG
	_env.fog_enabled = dichte > 0.01 or fern > 0.0
	var farbe := Color(0.86, 0.89, 0.92)
	if himmel != null:
		farbe = himmel.horizont_farbe().lerp(farbe, clampf(dichte, 0.0, 1.0) * 0.6)
	_env.fog_light_color = farbe
	_env.fog_density = maxf(fern, dichte * 0.012)
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
	var staerke := clampf((0.25 if typ == "niesel" else 1.0) * intensitaet, 0.05, 1.0)
	_regen.emitting = regnet
	_regen_fern.emitting = regnet
	_spritzer.emitting = regnet
	if regnet:
		_regen.global_position = fokus + Vector3(0.0, 26.0, 0.0)
		_regen.amount_ratio = staerke
		_regen_fern.global_position = fokus + Vector3(0.0, 28.0, 0.0)
		_regen_fern.amount_ratio = staerke
		_spritzer.global_position = fokus + Vector3(0.0, 0.12, 0.0)
		_spritzer.amount_ratio = staerke
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


## Pfützen wachsen mit der Nässe; nasser Boden dunkelt ab UND bekommt
## nassen Glanz (VIS-1: Roughness sinkt mit der Nässe).
func _wende_boden_an() -> void:
	var naesse := float(zustand["naesse"])
	_pfuetzen.visible = naesse > 0.12
	if _pfuetzen.visible:
		var skala := clampf(naesse, 0.2, 1.0)
		_pfuetzen.scale = Vector3(skala, 1.0, skala)
	if _terrain_mat != null:
		_terrain_mat.albedo_color = _terrain_albedo.darkened(naesse * 0.22)
		_terrain_mat.roughness = lerpf(_terrain_rauheit, 0.45, naesse)
	for eintrag: Array in _nass_mats:
		var mat: StandardMaterial3D = eintrag[0]
		mat.albedo_color = (eintrag[1] as Color).darkened(naesse * 0.28)
		mat.roughness = lerpf(float(eintrag[2]), 0.35, naesse)


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


## VIS-1 Regen-Umbau (Review „weiße, statische Striche"): ZWEI Fall-
## Ebenen (nah = lange schnelle Tropfen-Streaks, fern = kürzere langsame
## — Tiefenstaffelung), Streaks mit weicher Verlaufs-Textur statt harter
## Quads, leicht schräg im Wind, plus Aufschlag-RINGE am Boden.
func _baue_regen() -> void:
	_regen = _regen_ebene("Regen", Vector3(30.0, 2.0, 30.0), Vector2(0.06, 0.7), 900, 0.72, 19.0)
	_regen_fern = _regen_ebene(
		"RegenFern", Vector3(58.0, 3.0, 58.0), Vector2(0.04, 0.44), 650, 0.42, 12.5
	)
	_baue_spritzer()


func _regen_ebene(
	ebene_name: String, box: Vector3, tropfen: Vector2, menge: int, deckung: float, tempo: float
) -> GPUParticles3D:
	var ebene := GPUParticles3D.new()
	ebene.name = ebene_name
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = box
	# Leicht schräg (Wind) — Tropfen kleben nicht senkrecht an der Kamera.
	mat.direction = Vector3(0.14, -1.0, 0.06)
	mat.spread = 4.0
	mat.initial_velocity_min = tempo
	mat.initial_velocity_max = tempo * 1.35
	mat.gravity = Vector3(0.0, -22.0, 0.0)
	ebene.process_material = mat
	ebene.amount = menge
	ebene.lifetime = 1.7
	ebene.emitting = false
	# Default-visibility_aabb ist 8x8x8 m — der Knoten haengt aber 26 m
	# UEBER der Kamera: Box raus aus dem Frustum -> ALLE Tropfen gecullt.
	var weite := box.x + 12.0
	ebene.visibility_aabb = AABB(
		Vector3(-weite, -36.0, -weite), Vector3(weite * 2.0, 44.0, weite * 2.0)
	)
	# Streaks kippen mit der Fallrichtung (Y an Velocity ausgerichtet).
	ebene.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var quad := QuadMesh.new()
	quad.size = tropfen
	var quad_mat := _unlit(Color(0.68, 0.76, 0.9, deckung), false)
	quad_mat.albedo_texture = _streak_textur()
	quad.material = quad_mat
	ebene.draw_pass_1 = quad
	add_child(ebene)
	return ebene


## Aufschlag-Ringe: flache Ring-Meshes, die am Boden aufploppen, wachsen
## und ausblenden (scale_curve + color_ramp) — Regen „trifft" sichtbar.
func _baue_spritzer() -> void:
	_spritzer = GPUParticles3D.new()
	_spritzer.name = "RegenSpritzer"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(13.0, 0.5, 13.0)
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.scale_min = 0.6
	mat.scale_max = 1.8
	var kurve := Curve.new()
	kurve.add_point(Vector2(0.0, 0.15))
	kurve.add_point(Vector2(1.0, 1.0))
	var kurve_tex := CurveTexture.new()
	kurve_tex.curve = kurve
	mat.scale_curve = kurve_tex
	var verlauf := Gradient.new()
	verlauf.set_color(0, Color(0.88, 0.94, 1.0, 0.95))
	verlauf.set_color(1, Color(0.88, 0.94, 1.0, 0.0))
	var verlauf_tex := GradientTexture1D.new()
	verlauf_tex.gradient = verlauf
	mat.color_ramp = verlauf_tex
	_spritzer.process_material = mat
	_spritzer.amount = 320
	_spritzer.lifetime = 0.55
	_spritzer.emitting = false
	_spritzer.visibility_aabb = AABB(Vector3(-16.0, -3.0, -16.0), Vector3(32.0, 6.0, 32.0))
	_spritzer.draw_pass_1 = _ring_mesh()
	add_child(_spritzer)


## Flacher Aufschlag-Ring (Annulus, 14 Segmente) als Partikel-Mesh.
func _ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var innen := 0.17
	var aussen := 0.24
	var segmente := 14
	for s in segmente:
		var w0 := float(s) / float(segmente) * TAU
		var w1 := float(s + 1) / float(segmente) * TAU
		var ecken: Array[Vector3] = [
			Vector3(cos(w0) * innen, 0.0, sin(w0) * innen),
			Vector3(cos(w1) * innen, 0.0, sin(w1) * innen),
			Vector3(cos(w1) * aussen, 0.0, sin(w1) * aussen),
			Vector3(cos(w0) * aussen, 0.0, sin(w0) * aussen),
		]
		# Godot-Winding: Vorderseite = im Uhrzeigersinn (von +Y gesehen).
		for idx: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.add_vertex(ecken[idx])
	var mesh := st.commit()
	var mat := _unlit(Color(1.0, 1.0, 1.0, 0.8), false)
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	return mesh


## Weiche Tropfen-Streak-Textur: vertikaler Alpha-Verlauf (unten/oben
## transparent, Mitte deckend) — kein hartes „Strich"-Rechteck mehr.
func _streak_textur() -> GradientTexture2D:
	var verlauf := Gradient.new()
	verlauf.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	verlauf.colors = PackedColorArray(
		[Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)]
	)
	var tex := GradientTexture2D.new()
	tex.gradient = verlauf
	tex.width = 4
	tex.height = 32
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


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
