class_name RmpRemoteRider
extends Node3D
## Der ANDERE Reiter im Ausritt/Rennen (RW-6): RanchPferd + Gooby-Rig im
## Sattel + Namensschild + „Folge mir"-Marker. Posen kommen mit 10 Hz aus
## dem MG_POSE-Relay — gerendert wird über den RmpInterp-Puffer (150 ms
## Verzögerung, Doc RANCH-DLC-IDEAS-4 §2.1). Reiter sind füreinander
## Geister: KEINE Kollision (bewusst kein PhysicsBody).

const LABEL_HEIGHT := 2.35
const MARKER_HEIGHT := 2.9

var pferd: RanchPferd
var rig: GoobyRig

var _label: Label3D
var _marker: Label3D
var _interp := RmpInterp.neu()
var _gait := 0
var _stale := false


func _ready() -> void:
	pferd = RanchPferd.neu(Color("#B98A5E"), Color("#6E4B2E"))
	add_child(pferd)
	rig = GoobyRig.new()
	rig.scale = Vector3.ONE * 0.72
	rig.position = Vector3(
		0.0, pferd.body_height() if pferd.has_method("body_height") else 1.4, 0.05
	)
	add_child(rig)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 96
	_label.pixel_size = 0.005
	_label.outline_size = 20
	_label.modulate = Color(1.0, 0.98, 0.9)
	_label.outline_modulate = Color(0.25, 0.18, 0.12)
	_label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
	add_child(_label)
	_marker = Label3D.new()
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.text = "⬇ %s" % I18nService.t("ranch_mp.ausritt.folge_mir")
	_marker.font_size = 80
	_marker.pixel_size = 0.006
	_marker.outline_size = 18
	_marker.modulate = Color(1.0, 0.82, 0.35)
	_marker.outline_modulate = Color(0.35, 0.2, 0.05)
	_marker.position = Vector3(0.0, MARKER_HEIGHT, 0.0)
	_marker.visible = false
	add_child(_marker)


func set_display_name(display_name: String) -> void:
	if _label != null:
		_label.text = display_name


## „Folge mir"-Marker über dem Kopf an/aus (FOLGE_MIR-Reaktion).
func set_follow_me(an: bool) -> void:
	if _marker != null:
		_marker.visible = an


## Pose aus MG_PEER_POSE einspeisen (Service-Payload, s. rmp_service.gd).
func apply_pose(data: Dictionary) -> void:
	var p: Array = data.get("p", []) if data.get("p") is Array else []
	if p.size() < 3:
		return
	RmpInterp.push(
		_interp,
		Time.get_ticks_msec(),
		Vector3(float(p[0]), float(p[1]), float(p[2])),
		float(data.get("yaw", 0.0)),
		int(data.get("gait", 0))
	)
	if data.get("jump", false) and pferd != null and pferd.has_method("spiele_aktion"):
		pferd.spiele_aktion("sprung")


## Rejoin/Teleport: Puffer verwerfen, damit nichts über die Karte gleitet.
func reset_interp() -> void:
	RmpInterp.reset(_interp)


func _process(_delta: float) -> void:
	# Das Pferd animiert sich selbst (RanchPferd-Selbstläufer) — hier nur
	# Pose aus dem Interp-Puffer anwenden + Gangart nachziehen.
	var pose := RmpInterp.sample_at(_interp, Time.get_ticks_msec())
	if pose.is_empty():
		return
	global_position = pose["pos"]
	rotation.y = float(pose["yaw"])
	var gait := int(pose["gait"])
	var stale := bool(pose.get("stale", false))
	if gait != _gait or stale != _stale:
		_gait = gait
		_stale = stale
		if pferd != null:
			pferd.set_gait("stand" if stale else RmpKurse.gait_name(gait))
	if _label != null:
		_label.modulate.a = 0.45 if stale else 1.0
