extends Node3D
## Knoten-Pool der 3D-Bühnen (Agent 3D-C): eine feste Zahl vorgebauter Knoten
## (Meteore, Zutaten, Tierchen) wird pro Frame recycelt statt neu instanziiert.
##
## Ablauf pro Frame:
##   pool.begin()
##   var node := pool.take(); node.position = ...      (so oft wie nötig)
##   pool.flush()                                      (Rest unsichtbar)

var _nodes: Array[Node3D] = []
var _factory: Callable
var _cap := 0
var _used := 0


## `factory` liefert einen frischen Knoten; `cap` ist die Obergrenze.
func build(factory: Callable, cap: int) -> void:
	_factory = factory
	_cap = maxi(1, cap)
	for _i in _cap:
		var node: Node3D = _factory.call()
		node.visible = false
		add_child(node)
		_nodes.append(node)


func begin() -> void:
	_used = 0


## Nächster freier Knoten (sichtbar geschaltet) oder null, wenn der Pool leer ist.
func take() -> Node3D:
	if _used >= _nodes.size():
		return null
	var node := _nodes[_used]
	node.visible = true
	_used += 1
	return node


func flush() -> void:
	for i in range(_used, _nodes.size()):
		_nodes[i].visible = false


func used() -> int:
	return _used


func capacity() -> int:
	return _cap
