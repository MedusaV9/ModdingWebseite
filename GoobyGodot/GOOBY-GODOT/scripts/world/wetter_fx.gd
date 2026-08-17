class_name WetterFx
extends Node3D
## Geteilte Wetter-Optik aller GOOBY-Welten (W13/WETTER-FX): Regen-Streaks
## mit Boden-Spritzer-Ringen, Schnee, Gewitter-Blitz (Screen-Flash + Donner
## über die bestehenden Ambience-Loops der SfxMap) und Nebel-Dichte — die
## wiederverwendbare Extraktion aus dem Ranch-Fahrer
## (scripts/ranch/wetter/ranch_wetter_controller.gd, dort NICHT umgebaut).
##
## Der Wetterplan kommt IMMER von außen (SoulWetter/RanchWetter — nichts
## wird hier gewürfelt): `wende_zustand_an(zustand)` nimmt das
## SoulWetter-Schema {typ, regen, schnee} ebenso wie das reichere
## RanchWetter-Schema (typ, intensitaet, nebel_dichte, …).
##
## Mobile-Budget: EIN GPUParticles3D pro Effekt (Regen/Spritzer/Schnee),
## keine Physik-Kollision; Menge skaliert mit Quality.particle_factor();
## Reduced Motion (AppSettings) schaltet Partikel und Flash komplett ab.

## Blitz hat gezündet (staerke 0..1) — Dioramen hellen damit ihr
## Fenster-Bild auf, die Szene kann zusätzlich reagieren.
signal blitz_gezuendet(staerke: float)

## Partikel-Grundmengen (amount) — außen/innen; wirksam wird
## amount_ratio = staerke × particle_factor.
const REGEN_MENGE_AUSSEN := 420
const REGEN_MENGE_INNEN := 90
const SCHNEE_MENGE_AUSSEN := 220
const SCHNEE_MENGE_INNEN := 60
const SPRITZER_MENGE := 160
## Blitz-Takt (Sekunden zwischen zwei Blitzen, deterministisch per Seed).
const BLITZ_PAUSE_MIN_S := 3.5
const BLITZ_PAUSE_MAX_S := 9.0
const BLITZ_DAUER_S := 0.16
## Screen-Flash-Deckung (außen) — bewusst sanft, kein Stroboskop.
const FLASH_ALPHA := 0.28
## Wetter-Nebel → Environment.fog_density (Faktor wie auf der Ranch).
const NEBEL_DICHTE_FAKTOR := 0.012
## Donner/Regen kommen aus den bestehenden Ranch-Ambience-Loops (SfxMap).
const LOOP_IDS := {"regen": "ranch_ambience_regen", "gewitter": "ranch_ambience_gewitter"}

## Halbausdehnung der Emissions-Box (Bereich, XZ) und Fallhöhe des Regens.
var extents := Vector3(18.0, 2.0, 18.0)
var hoehe := 14.0
## Indoor-Modus (Fenster-Diorama): schmales Band, keine Spritzer, kein
## Screen-Flash (das Diorama flasht selbst), gedämpfter Ton.
var indoor_modus := false
## Außen-Szenen mit bewegter Kamera (Stadt): Emitter folgt der Kamera.
var folge_kamera := false
## Deterministischer Blitz-Takt (Szene setzt ihren Seed).
var seed_wert := 0
## Optional verdrahtet: Nebel schreibt in dieses Environment, der Blitz
## spike-t diese Sonne (Muster RanchWetterController).
var env: Environment = null
var sonne: DirectionalLight3D = null
## Tests erzwingen Reduced Motion (-1 = AppSettings fragen) bzw. das
## Partikel-Budget (-1.0 = Quality.particle_factor() fragen).
var reduced_motion_override := -1
var partikel_faktor_override := -1.0

var _zustand: Dictionary = {}
var _plan: Dictionary = {}
var _regen: GPUParticles3D
var _spritzer: GPUParticles3D
var _schnee: GPUParticles3D
var _flash: ColorRect
var _flash_layer: CanvasLayer
var _loops: Dictionary = {}
var _blitz_rng := RandomNumberGenerator.new()
var _blitz_pause := 5.0
var _blitz_rest := 0.0
var _sonne_basis_energie := -1.0


func _ready() -> void:
	_blitz_rng.seed = seed_wert + 77
	_baue_regen()
	_baue_spritzer()
	_baue_schnee()
	_baue_flash()
	_baue_loops()
	# Vor dem Baum-Eintritt gesetzte Zustände jetzt anwenden (erst hier
	# sind AppSettings/Quality über den Baum erreichbar).
	if not _zustand.is_empty():
		wende_zustand_an(_zustand)
	set_process(_process_noetig())


func _process(delta: float) -> void:
	_folge_kamera_nach()
	_tick_blitz(delta)
	_tick_ton(delta)
	# Nach dem Ausklingen (Loops verstummt) wieder schlafen — geweckt wird
	# über wende_zustand_an → _wende_plan_an.
	if not _process_noetig():
		set_process(false)


## Zustand aus dem Tagesplan anwenden (SoulWetter- oder RanchWetter-Schema).
## Deterministisch: gleicher Zustand ⇒ gleicher FX-Zustand.
func wende_zustand_an(zustand: Dictionary) -> void:
	_zustand = zustand.duplicate()
	_plan = fx_plan(zustand, indoor_modus, ist_reduced_motion())
	if _regen != null:
		_wende_plan_an()


## Zuletzt angewendeter FX-Zustand (für Tests/Debug).
func fx_zustand() -> Dictionary:
	return _plan.duplicate()


## PURE Kern-Mapping Tagesplan-Zustand → FX-Zustand — headless testbar.
## Ergebnis: {regen, spritzer, schnee, blitz: bool, staerke, nebel: float}.
static func fx_plan(zustand: Dictionary, indoor: bool, reduced: bool) -> Dictionary:
	var typ := str(zustand.get("typ", "sonne"))
	var regnet := bool(zustand.get("regen", RanchWetter.REGEN_TYPEN.has(typ)))
	var schneit := bool(zustand.get("schnee", typ == "schnee"))
	var gewitter := typ == "gewitter"
	var intensitaet := clampf(float(zustand.get("intensitaet", 0.8)), 0.0, 1.0)
	var staerke := clampf((0.25 if typ == "niesel" else 1.0) * intensitaet, 0.05, 1.0)
	var nebel := clampf(
		float(zustand.get("nebel_dichte", 0.8 if typ == "nebel" else 0.0)), 0.0, 1.0
	)
	return {
		"regen": regnet and not reduced,
		"spritzer": regnet and not reduced and not indoor,
		"schnee": schneit and not reduced,
		"blitz": gewitter and not reduced,
		"staerke": staerke,
		"nebel": nebel,
	}


## Wetter-Zustand fürs Himmel-Shader-Schema (GoobyHimmel/HimmelStimmungen
## kennen keinen Typ "schnee" — Schneehimmel liest sich als "wolken").
static func himmel_zustand(zustand: Dictionary) -> Dictionary:
	var typ := str(zustand.get("typ", "sonne"))
	if typ == "schnee":
		typ = "wolken"
	return {"typ": typ, "vorher": typ, "blend": 1.0}


## Fertig konfiguriertes Indoor-Band für Fenster-Dioramen: schmaler
## Regen-/Schnee-Vorhang direkt hinter der Scheibe, ohne Spritzer und ohne
## Screen-Flash — das Diorama hellt bei `blitz_gezuendet` selbst auf.
static func fuer_diorama(laenge: float, zustand: Dictionary) -> WetterFx:
	var fx := WetterFx.new()
	fx.name = "WetterFx"
	fx.indoor_modus = true
	fx.extents = Vector3(maxf(4.0, laenge * 0.5), 0.5, 1.0)
	# Knapp über der Fensterkrone starten — der Vorhang füllt den sichtbaren
	# Ausschnitt sofort, nichts ragt weit über die Kulissenwand.
	fx.hoehe = 3.0
	fx.wende_zustand_an(zustand)
	return fx


## Reduced Motion aus AppSettings (Tests überschreiben per Override).
func ist_reduced_motion() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override == 1
	if not is_inside_tree():
		return false
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("is_reduced_motion"))


## Partikel-Budget 0..1 aus dem Quality-Autoload (Tests: Override).
func partikel_faktor() -> float:
	if partikel_faktor_override >= 0.0:
		return clampf(partikel_faktor_override, 0.0, 1.0)
	if not is_inside_tree():
		return 1.0
	var quality := get_node_or_null("/root/Quality")
	if quality != null and quality.has_method("particle_factor"):
		return clampf(float(quality.call("particle_factor")), 0.0, 1.0)
	return 1.0


## ------------------------------------------------------------- anwenden


func _wende_plan_an() -> void:
	var staerke := float(_plan.get("staerke", 0.0)) * partikel_faktor()
	_regen.emitting = bool(_plan.get("regen", false))
	_regen.amount_ratio = maxf(0.05, staerke)
	_spritzer.emitting = bool(_plan.get("spritzer", false))
	_spritzer.amount_ratio = maxf(0.05, staerke)
	_schnee.emitting = bool(_plan.get("schnee", false))
	_schnee.amount_ratio = maxf(0.05, staerke)
	if not bool(_plan.get("blitz", false)):
		_blitz_rest = 0.0
		_setze_flash(0.0)
	_wende_nebel_an()
	set_process(_process_noetig())


## _process macht nur Kamera-Folge, Blitz-Takt und Loop-Fades — bei
## Klarwetter/indoor ohne klingende Loops darf der Frame-Tick schlafen
## (Projekt-Muster: dialog_bubble gated den Typewriter genauso). Noch
## spielende Loops halten den Tick wach, bis ihr Fade-out fertig ist.
func _process_noetig() -> bool:
	return (
		bool(_plan.get("regen", false))
		or bool(_plan.get("schnee", false))
		or bool(_plan.get("blitz", false))
		or _loop_spielt()
		or (folge_kamera and not indoor_modus)
	)


func _loop_spielt() -> bool:
	for id: String in _loops:
		if (_loops[id] as AudioStreamPlayer).playing:
			return true
	return false


func _wende_nebel_an() -> void:
	if env == null:
		return
	var dichte := float(_plan.get("nebel", 0.0))
	env.fog_enabled = dichte > 0.01
	env.fog_density = dichte * NEBEL_DICHTE_FAKTOR
	env.fog_sky_affect = clampf(dichte * 0.85, 0.0, 1.0)


func _folge_kamera_nach() -> void:
	if not folge_kamera or indoor_modus:
		return
	var kamera := get_viewport().get_camera_3d()
	if kamera == null:
		return
	var fokus := kamera.global_position
	global_position = Vector3(fokus.x, 0.0, fokus.z)


## ---------------------------------------------------------------- Blitz


func _tick_blitz(delta: float) -> void:
	if not bool(_plan.get("blitz", false)):
		return
	_blitz_pause -= delta
	if _blitz_pause <= 0.0:
		_blitz_rest = BLITZ_DAUER_S
		_blitz_pause = _blitz_rng.randf_range(BLITZ_PAUSE_MIN_S, BLITZ_PAUSE_MAX_S)
		blitz_gezuendet.emit(1.0)
	if _blitz_rest <= 0.0:
		return
	_blitz_rest -= delta
	var anteil := clampf(_blitz_rest / BLITZ_DAUER_S, 0.0, 1.0)
	if not indoor_modus:
		_setze_flash(FLASH_ALPHA * anteil)
	_spike_sonne(anteil)


func _setze_flash(alpha: float) -> void:
	if _flash == null:
		return
	_flash.visible = alpha > 0.001
	_flash.color = Color(0.95, 0.96, 1.0, alpha)


## Kurzer Energie-Spike auf der (optionalen) Szenen-Sonne — danach exakt
## auf den Basiswert zurück (die Stadt-Sonne ist statisch eingestellt).
func _spike_sonne(anteil: float) -> void:
	if sonne == null:
		return
	if _sonne_basis_energie < 0.0:
		_sonne_basis_energie = sonne.light_energy
	if anteil <= 0.001:
		sonne.light_energy = _sonne_basis_energie
		_sonne_basis_energie = -1.0
		return
	sonne.light_energy = maxf(_sonne_basis_energie, 2.4 * anteil)


## ------------------------------------------------------------------ Ton


func _tick_ton(delta: float) -> void:
	if _loops.is_empty():
		return
	var daempfung := 0.35 if indoor_modus else 1.0
	var staerke := float(_plan.get("staerke", 0.0))
	var ziele := {
		"regen": 0.7 * staerke * daempfung if bool(_plan.get("regen", false)) else 0.0,
		"gewitter": 0.85 * daempfung if bool(_plan.get("blitz", false)) else 0.0,
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


## Regen wie auf der Ranch (VIS-1): Streaks mit weicher Verlaufs-Textur,
## leicht schräg im Wind, Y an der Fallrichtung ausgerichtet — aber nur
## EINE Fall-Ebene (Mobile-Budget dieser Komponente).
func _baue_regen() -> void:
	_regen = GPUParticles3D.new()
	_regen.name = "Regen"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = extents
	mat.direction = Vector3(0.14, -1.0, 0.06)
	mat.spread = 4.0
	mat.initial_velocity_min = 16.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3(0.0, -22.0, 0.0)
	_regen.process_material = mat
	_regen.amount = REGEN_MENGE_INNEN if indoor_modus else REGEN_MENGE_AUSSEN
	_regen.lifetime = 1.4
	# Beim Szenen-Betreten regnet es sofort voll (kein leerer Himmel).
	_regen.preprocess = 1.2
	_regen.emitting = false
	_regen.position = Vector3(0.0, hoehe, 0.0)
	var weite := maxf(extents.x, extents.z) + 8.0
	_regen.visibility_aabb = AABB(
		Vector3(-weite, -hoehe - 6.0, -weite), Vector3(weite * 2.0, hoehe + 12.0, weite * 2.0)
	)
	_regen.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.5) if indoor_modus else Vector2(0.06, 0.7)
	var quad_mat := _unlit(Color(0.68, 0.76, 0.9, 0.6 if indoor_modus else 0.72), false)
	quad_mat.albedo_texture = _streak_textur()
	quad.material = quad_mat
	_regen.draw_pass_1 = quad
	add_child(_regen)


## Aufschlag-Ringe am Boden (Ranch-Muster: scale_curve + color_ramp) —
## Regen „trifft" sichtbar. Nur außen (Indoor-Band hat keinen Boden).
func _baue_spritzer() -> void:
	_spritzer = GPUParticles3D.new()
	_spritzer.name = "RegenSpritzer"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(extents.x * 0.7, 0.4, extents.z * 0.7)
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
	_spritzer.amount = SPRITZER_MENGE
	_spritzer.lifetime = 0.55
	_spritzer.emitting = false
	_spritzer.position = Vector3(0.0, 0.12, 0.0)
	var weite := maxf(extents.x, extents.z) + 4.0
	_spritzer.visibility_aabb = AABB(
		Vector3(-weite, -3.0, -weite), Vector3(weite * 2.0, 6.0, weite * 2.0)
	)
	_spritzer.draw_pass_1 = _ring_mesh()
	add_child(_spritzer)


## Schnee: weiche Billboard-Flocken, langsam taumelnd — der „erste
## Schnee"-Moment aus SoulWetter (Winter-Veredelung) wird sichtbar.
func _baue_schnee() -> void:
	_schnee = GPUParticles3D.new()
	_schnee.name = "Schnee"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = extents
	mat.direction = Vector3(0.08, -1.0, 0.05)
	mat.spread = 18.0
	mat.initial_velocity_min = 0.7
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0.0, -0.9, 0.0)
	mat.angular_velocity_min = -40.0
	mat.angular_velocity_max = 40.0
	mat.turbulence_enabled = false
	_schnee.process_material = mat
	_schnee.amount = SCHNEE_MENGE_INNEN if indoor_modus else SCHNEE_MENGE_AUSSEN
	_schnee.lifetime = 9.0
	_schnee.preprocess = 4.0
	_schnee.emitting = false
	_schnee.position = Vector3(0.0, hoehe * 0.7, 0.0)
	var weite := maxf(extents.x, extents.z) + 8.0
	_schnee.visibility_aabb = AABB(
		Vector3(-weite, -hoehe - 6.0, -weite), Vector3(weite * 2.0, hoehe + 12.0, weite * 2.0)
	)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = _unlit(Color(1.0, 1.0, 1.0, 0.9), true)
	_schnee.draw_pass_1 = quad
	add_child(_schnee)


## Sanfter Fullscreen-Flash für den Blitz (außen) — EIN ColorRect, kein
## Postprocess. Reduced Motion/Indoor lassen ihn aus.
func _baue_flash() -> void:
	if indoor_modus:
		return
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "BlitzFlash"
	_flash_layer.layer = 90
	add_child(_flash_layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.95, 0.96, 1.0, 0.0)
	_flash.visible = false
	_flash_layer.add_child(_flash)


func _baue_loops() -> void:
	for id: String in LOOP_IDS:
		var pfad := SfxMap.path(str(LOOP_IDS[id]))
		if pfad.is_empty() or not ResourceLoader.exists(pfad):
			continue
		var stream: AudioStream = load(pfad)
		if stream is AudioStreamOggVorbis:
			# Kopie loopen — der Cache-Stream bleibt für One-Shots unberührt.
			stream = (stream as AudioStreamOggVorbis).duplicate()
			(stream as AudioStreamOggVorbis).loop = true
		var player := AudioStreamPlayer.new()
		player.name = "Loop_%s" % id
		player.stream = stream
		player.bus = &"Sfx"
		player.volume_db = -60.0
		add_child(player)
		_loops[id] = player


## Flacher Aufschlag-Ring (Annulus, 14 Segmente) als Partikel-Mesh —
## identisch zum Ranch-Original.
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
		for idx: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.add_vertex(ecken[idx])
	var mesh := st.commit()
	var mat := _unlit(Color(1.0, 1.0, 1.0, 0.8), false)
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	return mesh


## Weiche Tropfen-Streak-Textur (Ranch-Muster): vertikaler Alpha-Verlauf.
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


func _unlit(farbe: Color, billboard: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if farbe.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return mat
