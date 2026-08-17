extends MultiMeshInstance3D
## Tempo-Striche der 3D-Minispiele (Agent 3D-B) — Port der Web-Fassung
## GOOBY/src/gfx/speedLines.js (§G4.2/§G4.8): ein Pool von Billboards, die im
## Ring um die Blickachse an der Kamera vorbeiziehen. Der GANZE Pool ist EIN
## MultiMesh = 1 Draw-Call.
##
## Der Knoten hängt UNTER der Kamera, rechnet also in Kamera-Koordinaten
## (vorwärts = −z). Dadurch stimmt der Effekt in beiden Orientierungen ohne
## Zusatzmathe, und Kurven/Kameraschwenks ziehen ihn korrekt mit.
##
## Reduced-Motion: `enabled = false` schaltet ihn hart ab (AppSettings-Regel);
## das Spiel fragt die Einstellung ab, der Effekt selbst bleibt dumm.

var enabled := true

var _pool := 0
var _radius := Vector2(2.6, 3.6)
var _ahead := Vector2(4.0, 9.0)
var _life := 0.35
var _vel_mult := 1.6
var _alive: Array[Dictionary] = []
var _spawn_acc := 0.0
var _rng := RandomNumberGenerator.new()


## Pool bauen. `size` = Breite/Länge eines Strichs in Metern.
func build(pool: int, radius: Vector2, ahead: Vector2, size := Vector2(0.06, 1.4)) -> void:
	_pool = maxi(1, pool)
	_radius = radius
	_ahead = ahead
	_rng.randomize()
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.965, 0.925, 0.55)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.no_depth_test = true
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = _pool
	mm.visible_instance_count = 0
	multimesh = mm
	extra_cull_margin = 60.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Pro Frame: `rate` neue Striche/s, `speed` = Weltgeschwindigkeit (m/s).
func update(delta: float, speed: float, rate: float) -> void:
	if not enabled or multimesh == null:
		_write(0)
		return
	_spawn_acc += maxf(0.0, rate) * delta
	while _spawn_acc >= 1.0 and _alive.size() < _pool:
		_spawn_acc -= 1.0
		_spawn()
	if _alive.size() >= _pool:
		_spawn_acc = minf(_spawn_acc, 1.0)
	var travel := maxf(1.0, speed) * _vel_mult * delta
	var live := 0
	for i in range(_alive.size() - 1, -1, -1):
		var s: Dictionary = _alive[i]
		s["t"] = float(s["t"]) + delta
		s["z"] = float(s["z"]) + travel
		if float(s["t"]) >= _life or float(s["z"]) > 1.2:
			_alive.remove_at(i)
			continue
	for s: Dictionary in _alive:
		var fade := 1.0 - float(s["t"]) / _life
		var basis := Basis.IDENTITY.scaled(Vector3(1.0, 0.6 + 0.9 * fade, 1.0))
		var pos := Vector3(float(s["x"]), float(s["y"]), float(s["z"]))
		multimesh.set_instance_transform(live, Transform3D(basis, pos))
		# Additiv auf pastellhellem Himmel schlug volle Deckkraft als weißer
		# Balken durch (`no_depth_test` legt die Striche über ALLES). Gedämpft
		# bleiben sie das, was sie sein sollen: ein Hauch Fahrtwind.
		multimesh.set_instance_color(live, Color(1.0, 1.0, 1.0, fade * fade * 0.55))
		live += 1
	_write(live)


## §G4.2-Rampe: [[speed, rate], …] linear interpoliert.
static func rate_at(speed: float, table: Array) -> float:
	if table.is_empty():
		return 0.0
	var first: Array = table[0]
	if speed <= float(first[0]):
		return float(first[1])
	for i in range(1, table.size()):
		var a: Array = table[i - 1]
		var b: Array = table[i]
		if speed <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), (speed - float(a[0])) / span)
	return float((table[table.size() - 1] as Array)[1])


func _spawn() -> void:
	var angle := _rng.randf() * TAU
	var radius := _rng.randf_range(_radius.x, _radius.y)
	(
		_alive
		. append(
			{
				"x": cos(angle) * radius,
				"y": sin(angle) * radius * 0.72,
				"z": -_rng.randf_range(_ahead.x, _ahead.y),
				"t": 0.0,
			}
		)
	)


func _write(count: int) -> void:
	if multimesh != null:
		multimesh.visible_instance_count = count
