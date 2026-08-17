class_name ChaseCam
extends Camera3D
## Third-Person-Chase-Kamera (W3a CITY, §C7.2-Port): gedämpftes Follow
## k = 4.0/s, Look-Ahead 6 m, FOV 55°→60° mit Tempo 9→13 m/s, kein Roll/Bob.
## Zahlen: CityCarFeel (1:1 aus carFeel.js).

var ziel: CarController


func _process(delta: float) -> void:
	if ziel == null:
		return
	update_cam(delta)


## Ein Kamera-Schritt (Tests rufen es direkt mit dt).
func update_cam(dt: float) -> void:
	var fx := sin(ziel.heading)
	var fz := cos(ziel.heading)
	var p := ziel.position
	var gewuenscht := Vector3(
		p.x - fx * CityCarFeel.CAM_BACK,
		CityCarFeel.ROAD_Y + CityCarFeel.CAM_HEIGHT,
		p.z - fz * CityCarFeel.CAM_BACK
	)
	position = position.lerp(gewuenscht, CityCarFeel.cam_follow_factor(dt))
	var blick := Vector3(
		p.x + fx * CityCarFeel.CAM_LOOKAHEAD_M,
		CityCarFeel.ROAD_Y + 1.2,
		p.z + fz * CityCarFeel.CAM_LOOKAHEAD_M
	)
	look_at(blick)
	var neues_fov := CityCarFeel.chase_fov(ziel.speed)
	if absf(fov - neues_fov) > 0.01:
		fov = neues_fov


## Kamera hart hinters Auto setzen (Szenen-Start/Teleport).
func snap() -> void:
	if ziel == null:
		return
	var fx := sin(ziel.heading)
	var fz := cos(ziel.heading)
	position = Vector3(
		ziel.position.x - fx * CityCarFeel.CAM_BACK,
		CityCarFeel.ROAD_Y + CityCarFeel.CAM_HEIGHT,
		ziel.position.z - fz * CityCarFeel.CAM_BACK
	)
	update_cam(0.016)
