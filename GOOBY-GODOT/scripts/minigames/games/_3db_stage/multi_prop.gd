extends Node3D
## Massen-Requisite der 3D-Minispiele (Agent 3D-B): EIN Modell, beliebig viele
## Exemplare, EIN Draw-Call pro Modell-Teilmesh (MultiMeshInstance3D).
##
## Genau dafür ist das Perf-Budget da: das Streckenband, die Häuserwände, die
## Hindernisse und die Münzen laufen alle über MultiMesh statt über N Knoten.
## Die Transforms werden pro Frame ÜBERSCHRIEBEN (kein Instanzieren) — das ist
## die geforderte Recycling-Regel „Objekte hinter der Kamera nach vorn setzen".
##
## Ablauf pro Frame:
##   prop.begin(); for x in ...: prop.push(xform); prop.flush()
## Alles, was in diesem Frame nicht gepusht wurde, ist danach unsichtbar
## (visible_instance_count), es bleibt aber allokiert.

## Bewusst großzügig: lieber einmal zu viel reservieren als mitten im Lauf
## neu allokieren (MultiMesh.instance_count zu ändern kostet die Puffer).
const DEFAULT_CAP := 64

var _layers: Array[MultiMeshInstance3D] = []
var _offsets: Array[Transform3D] = []
var _cap := 0
var _count := 0
var _colored := false


## Modell-Teile (aus ModelBank.parts) in MultiMesh-Ebenen gießen.
func build(
	parts: Array, cap := DEFAULT_CAP, use_colors := false, material: Material = null
) -> void:
	_clear()
	_cap = maxi(1, cap)
	_colored = use_colors
	for entry: Dictionary in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = use_colors
		mm.mesh = entry["mesh"]
		mm.instance_count = _cap
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if material != null:
			mmi.material_override = material
		# Ein Streckenband ist immer im Bild; das Culling pro MultiMesh-AABB
		# würde bei bewegten Instanzen sonst falsch greifen.
		mmi.extra_cull_margin = 200.0
		add_child(mmi)
		_layers.append(mmi)
		_offsets.append(entry["xform"])


## Anzahl Draw-Calls, die diese Requisite kostet (= Teilmeshes des Modells).
func layer_count() -> int:
	return _layers.size()


## Schattenwurf dieser Requisite an/aus.
##
## Kulissenwände (Häuserzeilen) sollen KEINEN Schatten werfen: ihre
## Schlagschatten legen sich als harte, fast schwarze Querbalken über die
## Fahrbahn, weil das Umgebungslicht nur ein Bruchteil der Sonne ist. Die
## Web-Vorlage rendert ganz ohne Schattenkarte — wir behalten den Schatten
## dort, wo er Tiefe schafft (Figur, Hindernisse, Fahrzeuge).
func set_shadows(on: bool) -> void:
	var mode := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if on
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for mmi in _layers:
		mmi.cast_shadow = mode


func capacity() -> int:
	return _cap


func begin() -> void:
	_count = 0


## Ein Exemplar an dieser Stelle. `xform` ist die WELT-Pose des Modells;
## der eingebackene Teil-Offset kommt automatisch dazu.
func push(xform: Transform3D, color := Color.WHITE) -> void:
	if _count >= _cap:
		return
	for i in _layers.size():
		var mm: MultiMesh = _layers[i].multimesh
		mm.set_instance_transform(_count, xform * _offsets[i])
		if _colored:
			mm.set_instance_color(_count, color)
	_count += 1


func flush() -> void:
	for mmi in _layers:
		mmi.multimesh.visible_instance_count = _count


## Alles unsichtbar (Rundenende / Umbau).
func clear_instances() -> void:
	begin()
	flush()


func _clear() -> void:
	for mmi in _layers:
		mmi.queue_free()
	_layers.clear()
	_offsets.clear()
	_count = 0
