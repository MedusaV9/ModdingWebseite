class_name GoobyExpressions
extends Node3D
## Ausdrucks-Schicht (SEELE-2) ÜBER dem GoobyRig — macht die durchgehende
## Stimmung SICHTBAR, bevor irgendein Text gelesen wird. Das Rig bleibt
## unangetastet (Besitz W1b); diese Schicht hängt sich als Kind ans Rig
## (läuft dadurch im Frame NACH dem Rig) und legt eigene, kontinuierliche
## Kanäle über dessen Ein-Hot-Emotionen:
##
##  - OHREN: der wichtigste Stimmungs-Anzeiger eines Hasen. Kontinuierlicher
##    Laune-Droop (SoulMood.ausdruck) + lebendiges Mikro-Wippen + Aufperk-
##    Zucken beim Aufmerken — über einen EIGENEN SkeletonModifier3D, der
##    NACH der Rig-Pose additiv komponiert.
##  - LIDER: schwere Lider bei schlechter Laune/Müdigkeit über den
##    blink-Shapekey (max-Komposition mit dem Rig-Blinzeln, nie dagegen),
##    dazu gelegentliche LANGSAME Lidschläge, wenn Gooby matt ist.
##  - BLICK: folgt dem Finger (Ray durch den Cursor/Touch) und wichtigen
##    Dingen (blick_auf), über rig.look_at_target — vorher hat NICHTS im
##    Zuhause das Look-At je benutzt.
##  - KOPF: kleines lebendiges Wandern (Mikro-Yaw/-Pitch), hängender Kopf
##    bei Elend — skaliert mit der Stimmungs-Energie.
##  - AUFMERKEN: Antippen/Ereignis → Ohren-Perk + Blick zur Kamera, mit
##    LATENZ nach Laune (elend = träge Reaktion, selig = sofort).
##
## Reduced Motion (AppSettings): Mikro-Wippen/Zucken entfallen, Zustands-
## Kanäle (Droop, Lider, Blick) bleiben — Stimmung bleibt lesbar.
## Performance: ein Modifier, ≤3 Shapekey-Writes/Frame, kein Alloc im Takt.

## Wie lange der Blick nach der letzten Fingerbewegung noch folgt.
const FINGER_HALTEN_S := 2.5
## Abstand Kamera → Blickpunkt entlang des Finger-Rays.
const FINGER_RAY_DIST := 6.0
## Ohren-Mikro-Wippen: Amplitude (rad-Parameter) und Frequenz (Hz).
const WIPPEN_AMP := 0.035
const WIPPEN_HZ := 0.6
## Aufperk-Zucken: Stärke (negativer Droop = aufgestellt) und Abkling-Rate.
const ZUCKEN_PERK := -0.22
const ZUCKEN_ABKLING := 2.2
## Kopf-Wandern: Amplitude (rad) und Frequenz (Hz).
const KOPF_AMP := 0.05
const KOPF_HZ := 0.23
## Aufmerk-Latenz (s): bei Energie 1.0 … 0.35 (SoulMood.ausdruck.energie).
const LATENZ_FLINK_S := 0.06
const LATENZ_TRAEGE_S := 0.55
## Blick zur Kamera nach dem Aufmerken (s).
const AUFMERKEN_BLICK_S := 2.2
## Langsamer, schwerer Lidschlag bei matter Laune: Takt + Dauer.
const SCHWERBLINZELN_MIN_S := 7.0
const SCHWERBLINZELN_MAX_S := 14.0
const SCHWERBLINZELN_DAUER_S := 0.9

var rig: GoobyRig = null
## Tests: −1 = AppSettings fragen, 0 = aus, 1 = an.
var reduced_motion_override := -1

var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _blink_idx := -1
var _modifier: ExpressionModifier = null
var _blick_ziel: Node3D = null

## Stimmungs-Zielwerte (SoulMood.ausdruck) — weich nachgeführt.
var _ohren_ziel := 0.0
var _lider_ziel := 0.0
var _kopf_ziel := 0.0
var _energie := 1.0
## Geglättete Ist-Werte.
var _ohren := 0.0
var _lider := 0.0
var _kopf := 0.0
## Impulse/Timer.
var _zucken := 0.0
var _zeit := 0.0
var _finger_bis_s := -1000.0
var _finger_pos := Vector2.ZERO
var _blick_node: Node3D = null
var _blick_bis_s := -1000.0
var _blick_punkt := Vector3.ZERO
var _blick_punkt_bis_s := -1000.0
var _blick_kamera_bis_s := -1000.0
var _aufmerken_in_s := -1.0
var _schwerblinzeln_timer := 9.0
var _schwerblinzeln_phase := -1.0
var _letzter_lid_wert := -1.0
var _rng := RandomNumberGenerator.new()


## Eigener SkeletonModifier: additive Ohr-/Kopf-Offsets NACH Animation und
## NACH dem Rig-PoseModifier (Kind-Reihenfolge im Skelett).
class ExpressionModifier:
	extends SkeletonModifier3D
	var expressions: GoobyExpressions
	var head_idx := -1
	var ear_l := -1
	var ear_r := -1

	func _process_modification() -> void:
		if expressions == null:
			return
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		var e := expressions
		var wippen_l := e.wippen_offset(0.0)
		var wippen_r := e.wippen_offset(2.1)
		_neige_ohr(skeleton, ear_l, e._ohren + e._zucken + wippen_l, 1.0)
		_neige_ohr(skeleton, ear_r, e._ohren + e._zucken + wippen_r, -1.0)
		_neige_kopf(skeleton, e._kopf + e.kopf_wandern_pitch(), e.kopf_wandern_yaw())

	func _neige_ohr(skeleton: Skeleton3D, idx: int, droop: float, out_sign: float) -> void:
		if idx < 0 or absf(droop) < 0.001:
			return
		var out_angle := maxf(-0.12, droop) * 1.1
		var back_angle := droop * 0.5
		var pose := skeleton.get_bone_global_pose(idx)
		var offset := (
			Basis(Vector3(0.0, 0.0, out_sign), out_angle) * Basis(Vector3.RIGHT, -back_angle)
		)
		pose.basis = offset * pose.basis
		skeleton.set_bone_global_pose(idx, pose)

	func _neige_kopf(skeleton: Skeleton3D, pitch: float, yaw: float) -> void:
		if head_idx < 0 or (absf(pitch) < 0.001 and absf(yaw) < 0.001):
			return
		var pose := skeleton.get_bone_global_pose(head_idx)
		var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		pose.basis = offset * pose.basis
		skeleton.set_bone_global_pose(head_idx, pose)


## Schicht erzeugen und ans Rig hängen (idempotent).
static func attach_to(target_rig: GoobyRig) -> GoobyExpressions:
	var existing := target_rig.get_node_or_null("GoobyExpressions")
	if existing is GoobyExpressions:
		return existing
	var layer := GoobyExpressions.new()
	layer.name = "GoobyExpressions"
	target_rig.add_child(layer)
	layer.setup(target_rig)
	return layer


func setup(target_rig: GoobyRig) -> void:
	rig = target_rig
	_rng.randomize()
	_skeleton = _find_first(rig, "Skeleton3D")
	_mesh = _find_first(rig, "MeshInstance3D")
	if _mesh != null:
		_blink_idx = _mesh.find_blend_shape_by_name("blink")
	_blick_ziel = Node3D.new()
	_blick_ziel.name = "BlickZiel"
	add_child(_blick_ziel)
	if _skeleton != null:
		_modifier = ExpressionModifier.new()
		_modifier.name = "GoobyExpressionModifier"
		_modifier.expressions = self
		_modifier.head_idx = _skeleton.find_bone("head")
		_modifier.ear_l = _skeleton.find_bone("ear.L.02")
		_modifier.ear_r = _skeleton.find_bone("ear.R.02")
		_skeleton.add_child(_modifier)
	_schwerblinzeln_timer = _rng.randf_range(SCHWERBLINZELN_MIN_S, SCHWERBLINZELN_MAX_S)


## Stimmung anlegen (Wert 0..100): setzt die kontinuierlichen Gesichts-/
## Körper-Ziele aus SoulMood.ausdruck — der Rest läuft in _process weich.
func set_stimmung(wert: float) -> void:
	var params := SoulMood.ausdruck(wert)
	_ohren_ziel = float(params["ohren"])
	_lider_ziel = float(params["lider"])
	_kopf_ziel = float(params["kopf"])
	_energie = float(params["energie"])


## Aufmerken (Antippen, Tür, Ereignis): Ohren-Perk + kurzer Blick zur
## Kamera — mit Latenz nach Laune. Elend = träge, selig = sofort.
func aufmerken() -> void:
	_aufmerken_in_s = reaktions_latenz_s()


## Aktuelle Reaktions-Latenz (PURE über _energie, Tests messen hierüber).
func reaktions_latenz_s() -> float:
	var t := clampf((_energie - 0.35) / 0.75, 0.0, 1.0)
	return lerpf(LATENZ_TRAEGE_S, LATENZ_FLINK_S, t)


## Blick auf ein wichtiges Ding richten (Kühlschrank, Tür, Geschenk …).
func blick_auf(node: Node3D, dauer_s := 3.0) -> void:
	_blick_node = node
	_blick_bis_s = _uhr_s() + dauer_s


## Blick auf einen festen Weltpunkt (Absichts-Ziele ohne eigenen Node).
func blick_auf_punkt(punkt: Vector3, dauer_s := 3.0) -> void:
	_blick_punkt = punkt
	_blick_punkt_bis_s = _uhr_s() + dauer_s


## Blick zum Spieler (Kamera) — der „…und schaut dich an“-Beat der
## Absichts-Momente. Ohne Latenz/Zucken, nur der Blick.
func blick_zur_kamera(dauer_s := 2.5) -> void:
	_blick_kamera_bis_s = _uhr_s() + dauer_s


func blick_frei() -> void:
	_blick_node = null
	_blick_bis_s = -1000.0
	_blick_punkt_bis_s = -1000.0
	_blick_kamera_bis_s = -1000.0


## Messgrößen für Tests/Screenshots.
func ohren_droop() -> float:
	return _ohren


func lider_bias() -> float:
	return _lider


func _find_first(node: Node, klass: String) -> Variant:
	if node.is_class(klass):
		return node
	for child in node.get_children():
		var found: Variant = _find_first(child, klass)
		if found != null:
			return found
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_finger_pos = (event as InputEventMouseMotion).position
		_finger_bis_s = _uhr_s() + FINGER_HALTEN_S
	elif event is InputEventScreenDrag:
		_finger_pos = (event as InputEventScreenDrag).position
		_finger_bis_s = _uhr_s() + FINGER_HALTEN_S
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_finger_pos = (event as InputEventScreenTouch).position
		_finger_bis_s = _uhr_s() + FINGER_HALTEN_S


func _process(delta: float) -> void:
	if rig == null:
		return
	_zeit += delta * _energie
	var glatt := minf(3.0 * delta, 1.0)
	_ohren = lerpf(_ohren, _ohren_ziel, glatt)
	_kopf = lerpf(_kopf, _kopf_ziel, glatt)
	_lider = lerpf(_lider, _lider_ziel, glatt)
	_zucken = move_toward(_zucken, 0.0, ZUCKEN_ABKLING * delta)
	_tick_aufmerken(delta)
	_tick_blick()
	_tick_lider(delta)


## Ohren-Wippen (vom Modifier gelesen): lebendig bei guter Laune, fast
## still bei Elend/Reduced Motion.
func wippen_offset(phase: float) -> float:
	if _reduziert():
		return 0.0
	return WIPPEN_AMP * _energie * sin(TAU * WIPPEN_HZ * _zeit + phase)


func kopf_wandern_pitch() -> float:
	if _reduziert():
		return 0.0
	return KOPF_AMP * 0.6 * _energie * sin(TAU * KOPF_HZ * _zeit * 0.83 + 1.3)


func kopf_wandern_yaw() -> float:
	if _reduziert():
		return 0.0
	return KOPF_AMP * _energie * sin(TAU * KOPF_HZ * _zeit)


func _tick_aufmerken(delta: float) -> void:
	if _aufmerken_in_s < 0.0:
		return
	_aufmerken_in_s -= delta
	if _aufmerken_in_s > 0.0:
		return
	_aufmerken_in_s = -1.0
	if not _reduziert():
		_zucken = ZUCKEN_PERK * clampf(_energie + 0.25, 0.5, 1.0)
	_blick_kamera_bis_s = _uhr_s() + AUFMERKEN_BLICK_S


## Blick-Priorität: wichtiges Ding > Weltpunkt > Kamera (Aufmerken) >
## Finger > frei.
func _tick_blick() -> void:
	var now := _uhr_s()
	if _blick_node != null and is_instance_valid(_blick_node) and now < _blick_bis_s:
		_blick_ziel.global_position = _blick_node.global_position
		rig.look_at_target = _blick_ziel
		return
	if now < _blick_punkt_bis_s:
		_blick_ziel.global_position = _blick_punkt
		rig.look_at_target = _blick_ziel
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null and now < _blick_kamera_bis_s:
		_blick_ziel.global_position = camera.global_position
		rig.look_at_target = _blick_ziel
		return
	if camera != null and now < _finger_bis_s:
		var von := camera.project_ray_origin(_finger_pos)
		var richtung := camera.project_ray_normal(_finger_pos)
		_blick_ziel.global_position = von + richtung * FINGER_RAY_DIST
		rig.look_at_target = _blick_ziel
		return
	if rig.look_at_target == _blick_ziel:
		rig.look_at_target = null


## Lider: Basis-Bias nach Laune + gelegentlicher LANGSAMER Lidschlag bei
## matter Stimmung. Komposition mit dem Rig-Blinzeln über max() — schreibt
## das Rig gerade selbst (Wert ≠ unser letzter), gewinnt der größere.
func _tick_lider(delta: float) -> void:
	if _mesh == null or _blink_idx < 0:
		return
	var schwer := _schwerblinzeln(delta)
	var bias := clampf(maxf(_lider, schwer), 0.0, 0.85)
	var aktuell := _mesh.get_blend_shape_value(_blink_idx)
	var rig_anteil := 0.0
	if not is_equal_approx(aktuell, _letzter_lid_wert):
		rig_anteil = aktuell
	var wert := maxf(bias, rig_anteil)
	_mesh.set_blend_shape_value(_blink_idx, wert)
	_letzter_lid_wert = wert


## Langsamer Lidschlag (0..~0.9-Kurve), nur bei matter Laune und ohne
## Reduced Motion. Dreieck: gemächlich zu, gemächlich auf.
func _schwerblinzeln(delta: float) -> float:
	if _lider_ziel < 0.1 or _reduziert():
		_schwerblinzeln_phase = -1.0
		return 0.0
	if _schwerblinzeln_phase >= 0.0:
		_schwerblinzeln_phase += delta / SCHWERBLINZELN_DAUER_S
		if _schwerblinzeln_phase >= 1.0:
			_schwerblinzeln_phase = -1.0
			_schwerblinzeln_timer = _rng.randf_range(SCHWERBLINZELN_MIN_S, SCHWERBLINZELN_MAX_S)
			return 0.0
		var p := _schwerblinzeln_phase
		return 0.9 * (p / 0.5 if p < 0.5 else (1.0 - p) / 0.5)
	_schwerblinzeln_timer -= delta
	if _schwerblinzeln_timer <= 0.0:
		_schwerblinzeln_phase = 0.0
	return 0.0


func _uhr_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _reduziert() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()
